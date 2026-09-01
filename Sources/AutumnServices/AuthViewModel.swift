import SwiftUI
import AuthenticationServices

/// AuthViewModel — guest-first like the web app.
/// GitHub: device flow + ASWebAuthenticationSession using the same OAuth App as leatr.xyz.
/// OAuth access tokens live in Keychain. Never a PAT paste field.
@MainActor
public final class AuthViewModel: NSObject, ObservableObject {

    @Published public var isSignedIn      = true   // web is guest-first; no hard gate
    @Published public var isGuest         = true
    @Published public var githubConnected = false
    @Published public var username        = "Guest"
    @Published public var githubUsername  = ""
    @Published public var appleUserId     = ""
    @Published public var error: String?  = nil
    @Published public var deviceFlowCode: DeviceFlowDisplay? = nil
    @Published public var savedAppleAccounts:  [SavedAccount] = []
    @Published public var savedGitHubAccounts: [SavedAccount] = []
    @Published public var githubAvatarURL: URL? = nil
    @Published public var isAuthenticating = false
    @Published public var adminEnabled = false

    public var sessionUID: String {
        if githubConnected && !githubUsername.isEmpty { return githubUsername }
        if !appleUserId.isEmpty { return "apple-" + appleUserId.prefix(8) }
        return UserDefaults.standard.string(forKey: "autumn_guest_uid") ?? {
            let u = "ios-" + UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(u, forKey: "autumn_guest_uid")
            return u
        }()
    }

    public var adminAllowed: Bool {
        githubConnected && githubUsername.lowercased() == AutumnConfig.adminUsername
    }

    private let keychainKey    = "autumn_apple_user_id"
    private let displayNameKey = "autumn_apple_display_name"
    private let oauthTokenKey  = "github_oauth_token"
    private let oauthUserKey   = "github_username"

    public func restoreSession() {
        loadSavedAccounts()
        adminEnabled = UserDefaults.standard.bool(forKey: "_aut_admin_enabled") && adminAllowed
        if let urlStr = KeychainService.shared.load(key: "github_avatar_url"),
           let url = URL(string: urlStr) {
            githubAvatarURL = url
        }

        // OAuth token only — never read a user-pasted PAT field.
        // Migrate leftover device-flow token stored under the old key.
        let token = KeychainService.shared.load(key: oauthTokenKey)
            ?? KeychainService.shared.load(key: "github_pat")
        if let token, !token.isEmpty {
            if KeychainService.shared.load(key: oauthTokenKey) == nil {
                KeychainService.shared.save(key: oauthTokenKey, value: token)
                KeychainService.shared.delete(key: "github_pat")
            }
            Task { await GitHubClient.shared.setToken(token) }
            let ghUser = KeychainService.shared.load(key: oauthUserKey) ?? ""
            if !ghUser.isEmpty {
                githubConnected = true
                githubUsername  = ghUser
                isGuest = false
                if username == "Guest" || username.isEmpty { username = ghUser }
                restoreAdminFlag()
            }
        }

        guard let savedUID = KeychainService.shared.load(key: keychainKey),
              !savedUID.isEmpty else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: savedUID) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized, .transferred:
                    self.appleUserId = savedUID
                    self.username    = KeychainService.shared.load(key: self.displayNameKey) ?? self.username
                    self.isSignedIn  = true
                    self.isGuest     = false
                    Task { await UserVaultService.shared.setup(
                        githubUsername: self.githubConnected ? self.githubUsername : nil) }
                case .revoked, .notFound:
                    KeychainService.shared.delete(key: self.keychainKey)
                    KeychainService.shared.delete(key: self.displayNameKey)
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: — Apple
    public func signInWithApple() {
        error = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    public func switchAppleAccount(to account: SavedAccount) {
        appleUserId = account.id
        username    = account.displayName
        KeychainService.shared.save(key: keychainKey,      value: account.id)
        KeychainService.shared.save(key: displayNameKey,   value: account.displayName)
        isSignedIn = true; isGuest = false
        Task { await UserVaultService.shared.setup(
            githubUsername: githubConnected ? githubUsername : nil) }
    }

    // MARK: — GitHub device flow (ASWebAuthenticationSession)
    public func startGitHubAuth() async {
        error = nil
        isAuthenticating = true
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: AutumnConfig.githubClientId)
            deviceFlowCode = DeviceFlowDisplay(
                userCode: flow.userCode, verificationUrl: flow.verificationUri,
                deviceCode: flow.deviceCode, interval: flow.interval)
            if let url = URL(string: flow.verificationUri) {
                GitHubOAuth.shared.openDeviceVerification(url: url)
            }
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval)
        } catch {
            // GAS fallback for device code (same as web)
            if let d = await AutumnGASClient.shared.deviceCode(),
               let userCode = d["user_code"] as? String,
               let deviceCode = d["device_code"] as? String,
               let uri = d["verification_uri"] as? String {
                let interval = d["interval"] as? Int ?? 5
                deviceFlowCode = DeviceFlowDisplay(
                    userCode: userCode, verificationUrl: uri,
                    deviceCode: deviceCode, interval: interval)
                if let url = URL(string: uri) {
                    GitHubOAuth.shared.openDeviceVerification(url: url)
                }
                await pollForGitHubToken(deviceCode: deviceCode, interval: interval)
            } else {
                self.error = error.localizedDescription
                isAuthenticating = false
            }
        }
    }

    /// If a web-flow `code` ever lands (universal link / autumn://oauth?code=), exchange via GAS.
    public func completeWebFlow(code: String) async {
        error = nil
        isAuthenticating = true
        if let d = await AutumnGASClient.shared.exchangeCode(code),
           let token = d["access_token"] as? String, !token.isEmpty {
            await applyOAuthToken(token)
        } else {
            error = "GitHub exchange failed"
            isAuthenticating = false
        }
    }

    private func pollForGitHubToken(deviceCode: String, interval: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(max(interval, 5)) * 1_000_000_000)
            guard let token = try? await GitHubClient.shared.pollDeviceFlow(
                clientId: AutumnConfig.githubClientId, deviceCode: deviceCode), !token.isEmpty else { continue }
            await applyOAuthToken(token)
            return
        }
        deviceFlowCode = nil
        isAuthenticating = false
        GitHubOAuth.shared.cancel()
        error = "Authorization timed out. Please try again."
    }

    private func applyOAuthToken(_ token: String) async {
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        KeychainService.shared.delete(key: "github_pat")
        await GitHubClient.shared.setToken(token)
        var ghUser = (try? await GitHubClient.shared.fetchAuthenticatedUser()) ?? "GitHub User"
        if ghUser.isEmpty { ghUser = "GitHub User" }
        KeychainService.shared.save(key: oauthUserKey, value: ghUser)
        if let avatar = try? await GitHubClient.shared.fetchAvatarURL() {
            githubAvatarURL = avatar
            KeychainService.shared.save(key: "github_avatar_url", value: avatar.absoluteString)
        }
        githubConnected = true
        githubUsername  = ghUser
        deviceFlowCode  = nil
        isAuthenticating = false
        isSignedIn = true
        isGuest = false
        username = ghUser
        saveGitHubAccount(id: ghUser, displayName: ghUser)
        restoreAdminFlag()
        GitHubOAuth.shared.cancel()
        Task { await UserVaultService.shared.setup(githubUsername: ghUser) }
    }

    public func switchGitHubAccount(to account: SavedAccount) {
        guard let token = KeychainService.shared.load(key: "github_oauth_\(account.id)") else { return }
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        Task { await GitHubClient.shared.setToken(token) }
        githubUsername = account.displayName; githubConnected = true
        username = account.displayName
        isGuest = false
        restoreAdminFlag()
        Task { await UserVaultService.shared.setup(githubUsername: account.displayName) }
    }

    public func disconnectGitHub() {
        githubConnected = false; githubUsername = ""
        githubAvatarURL = nil
        adminEnabled = false
        KeychainService.shared.delete(key: oauthTokenKey)
        KeychainService.shared.delete(key: oauthUserKey)
        KeychainService.shared.delete(key: "github_avatar_url")
        KeychainService.shared.delete(key: "github_pat")
        if appleUserId.isEmpty {
            isGuest = true
            username = "Guest"
        }
    }

    public func continueAsGuest() {
        isGuest = true; isSignedIn = true; username = "Guest"; error = nil
        Task { await UserVaultService.shared.setup(githubUsername: nil) }
    }

    public func signOut() {
        disconnectGitHub()
        isGuest = true; githubConnected = false
        username = "Guest"; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil; adminEnabled = false
        KeychainService.shared.delete(key: keychainKey)
        KeychainService.shared.delete(key: displayNameKey)
    }

    // MARK: — Admin flag (dartsolarpunk only)
    public func restoreAdminFlag() {
        guard adminAllowed else { adminEnabled = false; return }
        adminEnabled = UserDefaults.standard.string(forKey: "_aut_admin_enabled") == "1"
    }

    public func setAdminEnabled(_ on: Bool) {
        guard adminAllowed else { adminEnabled = false; return }
        adminEnabled = on
        UserDefaults.standard.set(on ? "1" : "0", forKey: "_aut_admin_enabled")
    }

    public func toggleAdminFlag() {
        setAdminEnabled(!adminEnabled)
    }

    @AppStorage("policy_accepted_v1") public var hasAcceptedPolicy = false
    public func acceptPolicy() { hasAcceptedPolicy = true }

    private func saveGitHubAccount(id: String, displayName: String) {
        if !savedGitHubAccounts.contains(where: { $0.id == id }) {
            savedGitHubAccounts.append(SavedAccount(id: id, displayName: displayName))
            persistAccounts()
        }
        if let token = KeychainService.shared.load(key: oauthTokenKey) {
            KeychainService.shared.save(key: "github_oauth_\(id)", value: token)
        }
    }

    private func loadSavedAccounts() {
        if let d = UserDefaults.standard.data(forKey: "saved_github_accounts"),
           let a = try? JSONDecoder().decode([SavedAccount].self, from: d) { savedGitHubAccounts = a }
        if let d = UserDefaults.standard.data(forKey: "saved_apple_accounts"),
           let a = try? JSONDecoder().decode([SavedAccount].self, from: d) { savedAppleAccounts = a }
    }

    private func persistAccounts() {
        if let d = try? JSONEncoder().encode(savedGitHubAccounts) {
            UserDefaults.standard.set(d, forKey: "saved_github_accounts")
        }
    }
}

extension AuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        switch authorization.credential {
        case let appleID as ASAuthorizationAppleIDCredential:
            let uid = appleID.user
            let first   = appleID.fullName?.givenName ?? ""
            let last    = appleID.fullName?.familyName ?? ""
            let newName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let display = newName.isEmpty
                ? (KeychainService.shared.load(key: displayNameKey) ?? "User")
                : newName
            KeychainService.shared.save(key: keychainKey,    value: uid)
            KeychainService.shared.save(key: displayNameKey, value: display)
            if !savedAppleAccounts.contains(where: { $0.id == uid }) {
                savedAppleAccounts.append(SavedAccount(id: uid, displayName: display))
                if let d = try? JSONEncoder().encode(savedAppleAccounts) {
                    UserDefaults.standard.set(d, forKey: "saved_apple_accounts")
                }
            }
            appleUserId = uid; username = display
            isSignedIn = true; isGuest = false; error = nil
            Task { await UserVaultService.shared.setup(
                githubUsername: githubConnected ? githubUsername : nil) }
        case let password as ASPasswordCredential:
            username   = password.user
            isSignedIn = true; isGuest = false; error = nil
        default:
            break
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let asErr = error as? ASAuthorizationError
        switch asErr?.code {
        case .canceled: return
        case .unknown:
            if appleUserId.isEmpty && !githubConnected {
                self.error = "Sign in with Apple requires iCloud in Settings → Apple ID"
            }
        case .invalidResponse, .notHandled, .failed:
            self.error = "Sign in failed: \(error.localizedDescription)"
        default:
            self.error = error.localizedDescription
        }
    }
}

public struct DeviceFlowDisplay {
    public let userCode: String
    public let verificationUrl: String
    public let deviceCode: String
    public let interval: Int
}

public struct SavedAccount: Codable, Identifiable {
    public let id: String
    public let displayName: String
}
