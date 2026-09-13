import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

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

    /// Web `_aut_sid` — one sid per install so we do not mint a new live orb every launch.
    public var sessionSID: String {
        if let s = UserDefaults.standard.string(forKey: "autumn_session_sid"), !s.isEmpty { return s }
        let s = sessionUID + "_t" + String(Int(Date().timeIntervalSince1970), radix: 36)
        UserDefaults.standard.set(s, forKey: "autumn_session_sid")
        return s
    }

    public var adminAllowed: Bool {
        githubConnected && githubUsername.lowercased() == AutumnConfig.adminUsername
    }

    /// Bumped by cancelGitHubAuth so in-flight poll loops exit.
    private var githubPollGeneration = 0

    private let keychainKey    = "autumn_apple_user_id"
    private let displayNameKey = "autumn_apple_display_name"
    private let oauthTokenKey  = "github_oauth_token"
    private let oauthUserKey   = "github_username"

    private var _currentNonce = ""
    /// Strongly retain the ProfileSheet-driven ASAuthorizationController.
    private var appleAuthController: ASAuthorizationController?

    public func restoreSession() {
        loadSavedAccounts()
        adminEnabled = UserDefaults.standard.bool(forKey: "_aut_admin_enabled") && adminAllowed
        if let urlStr = KeychainService.shared.load(key: "github_avatar_url"),
           let url = URL(string: urlStr) {
            githubAvatarURL = GitHubClient.sizedAvatarURL(from: url.absoluteString) ?? url
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
            let ghUser = KeychainService.shared.load(key: oauthUserKey) ?? ""
            if !ghUser.isEmpty {
                githubConnected = true
                githubUsername  = ghUser
                isGuest = false
                if username == "Guest" || username.isEmpty { username = ghUser }
                restoreAdminFlag()
            }
            // Always refresh login + avatar from GET /user when a token is present.
            Task {
                await GitHubClient.shared.setToken(token)
                await applyGitHubProfile()
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

    /// Called from AppleSignInButton.onRequest — sets nonce BEFORE performRequests.
    public func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = generateNonce()
        _currentNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)
    }

    /// Called from AppleSignInButton.onCompletion (and legacy delegate).
    public func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            applyAppleAuthorization(authorization)
        case .failure(let error):
            applyAppleError(error)
        }
    }

    /// Legacy no-op — AppleSignInButton (Welcome) owns the ASAuthorizationController.
    /// Profile must dismiss its overlay first, then call performAppleSignInFromRootWindow().
    public func signInWithApple() {
        // Intentionally empty (Ashtree IDEAuthViewModel pattern).
    }

    /// Present SIWA from the key window AFTER Profile overlay is fully dismissed.
    /// Nested overlay/sheet presentation is the remaining .unknown failure mode vs Ashtree.
    public func performAppleSignInFromRootWindow() {
        error = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleAuthController = controller
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
    /// - Parameter openVerification: When true (default), opens ASWebAuthenticationSession.
    ///   GitHubDeviceFlowSheet passes false and owns the dismissible Safari sheet instead —
    ///   stacking both overlays left Cancel/swipe broken.
    public func startGitHubAuth(openVerification: Bool = true) async {
        error = nil
        isAuthenticating = true
        githubPollGeneration += 1
        let gen = githubPollGeneration
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: AutumnConfig.githubClientId)
            guard gen == githubPollGeneration else { return }
            deviceFlowCode = DeviceFlowDisplay(
                userCode: flow.userCode, verificationUrl: flow.verificationUri,
                deviceCode: flow.deviceCode, interval: flow.interval)
            if openVerification, let url = URL(string: flow.verificationUri) {
                GitHubOAuth.shared.openDeviceVerification(url: url)
            }
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval, generation: gen)
        } catch {
            // GAS fallback for device code (same as web)
            if let d = await AutumnGASClient.shared.deviceCode(),
               let userCode = d["user_code"] as? String,
               let deviceCode = d["device_code"] as? String,
               let uri = d["verification_uri"] as? String {
                guard gen == githubPollGeneration else { return }
                let interval = d["interval"] as? Int ?? 5
                deviceFlowCode = DeviceFlowDisplay(
                    userCode: userCode, verificationUrl: uri,
                    deviceCode: deviceCode, interval: interval)
                if openVerification, let url = URL(string: uri) {
                    GitHubOAuth.shared.openDeviceVerification(url: url)
                }
                await pollForGitHubToken(deviceCode: deviceCode, interval: interval, generation: gen)
            } else {
                self.error = error.localizedDescription
                isAuthenticating = false
            }
        }
    }

    /// Stop device-flow poll + dismiss any ASWebAuthenticationSession. Safe to call from Cancel / sheet onDismiss.
    public func cancelGitHubAuth() {
        githubPollGeneration += 1
        deviceFlowCode = nil
        isAuthenticating = false
        GitHubOAuth.shared.cancel()
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

    private func pollForGitHubToken(deviceCode: String, interval: Int, generation: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(max(interval, 5)) * 1_000_000_000)
            guard generation == githubPollGeneration else { return }
            guard let token = try? await GitHubClient.shared.pollDeviceFlow(
                clientId: AutumnConfig.githubClientId, deviceCode: deviceCode), !token.isEmpty else { continue }
            await applyOAuthToken(token)
            return
        }
        guard generation == githubPollGeneration else { return }
        deviceFlowCode = nil
        isAuthenticating = false
        GitHubOAuth.shared.cancel()
        error = "Authorization timed out. Please try again."
    }

    private func applyOAuthToken(_ token: String) async {
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        KeychainService.shared.delete(key: "github_pat")
        await GitHubClient.shared.setToken(token)
        await applyGitHubProfile()
        deviceFlowCode  = nil
        isAuthenticating = false
        isSignedIn = true
        isGuest = false
        GitHubOAuth.shared.cancel()
        Task { await UserVaultService.shared.setup(githubUsername: githubUsername) }
    }

    /// One GET /user. Persists login + avatar URL. Letter fallback only if this fails.
    private func applyGitHubProfile() async {
        guard let profile = try? await GitHubClient.shared.fetchAuthenticatedProfile() else { return }
        let ghUser = profile.login.isEmpty ? "GitHub User" : profile.login
        KeychainService.shared.save(key: oauthUserKey, value: ghUser)
        githubConnected = true
        githubUsername  = ghUser
        username = ghUser
        if let avatar = profile.avatarURL {
            githubAvatarURL = avatar
            KeychainService.shared.save(key: "github_avatar_url", value: avatar.absoluteString)
        }
        saveGitHubAccount(id: ghUser, displayName: ghUser, avatarURL: profile.avatarURL?.absoluteString)
        restoreAdminFlag()
    }

    public func switchGitHubAccount(to account: SavedAccount) {
        guard let token = KeychainService.shared.load(key: "github_oauth_\(account.id)") else { return }
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        githubUsername = account.displayName
        githubConnected = true
        username = account.displayName
        isGuest = false
        if let s = account.avatarURL, let url = URL(string: s) {
            githubAvatarURL = url
            KeychainService.shared.save(key: "github_avatar_url", value: s)
        }
        restoreAdminFlag()
        Task {
            await GitHubClient.shared.setToken(token)
            await applyGitHubProfile()
            await UserVaultService.shared.setup(githubUsername: account.displayName)
        }
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
        cancelGitHubAuth()
        disconnectGitHub()
        isGuest = true; githubConnected = false
        username = "Guest"; githubUsername = ""; appleUserId = ""
        error = nil; adminEnabled = false
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

    private func saveGitHubAccount(id: String, displayName: String, avatarURL: String? = nil) {
        if let idx = savedGitHubAccounts.firstIndex(where: { $0.id == id }) {
            if let avatarURL { savedGitHubAccounts[idx].avatarURL = avatarURL }
        } else {
            savedGitHubAccounts.append(SavedAccount(id: id, displayName: displayName, avatarURL: avatarURL))
        }
        persistAccounts()
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
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        appleAuthController = nil
        handleAppleCompletion(.success(authorization))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        appleAuthController = nil
        handleAppleCompletion(.failure(error))
    }

    fileprivate func applyAppleAuthorization(_ authorization: ASAuthorization) {
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

    fileprivate func applyAppleError(_ error: Error) {
        let asErr = error as? ASAuthorizationError
        switch asErr?.code {
        case .canceled:
            // User dismissed the sheet — stay silent.
            return
        case .unknown:
            // Presentation/hierarchy failures often surface as .unknown; do not always blame iCloud.
            self.error = "Sign in failed — try again from Welcome, or check Settings → Apple ID / iCloud"
        case .invalidResponse, .notHandled, .failed:
            self.error = "Sign in failed: \(error.localizedDescription)"
        case .notInteractive:
            self.error = "Sign in failed — Apple Sign In is not available in this context. Try again from Welcome."
        case nil:
            self.error = error.localizedDescription
        default:
            if let asErr {
                self.error = "Sign in failed (\(asErr.code.rawValue)): \(error.localizedDescription)"
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    fileprivate func generateNonce(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for r in randoms {
                guard remaining > 0 else { break }
                guard r < charset.count else { continue }
                let idx = charset.index(charset.startIndex, offsetBy: Int(r))
                result.append(charset[idx])
                remaining -= 1
            }
        }
        return result
    }

    fileprivate func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
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
    public var avatarURL: String? = nil
}
