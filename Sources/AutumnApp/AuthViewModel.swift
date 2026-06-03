import SwiftUI
import AuthenticationServices
import AutumnServices

@MainActor
public final class AuthViewModel: NSObject, ObservableObject {

    // MARK: — Published state
    @Published public var isSignedIn       = false
    @Published public var isGuest          = false
    @Published public var githubConnected  = false
    @Published public var username         = ""
    @Published public var githubUsername   = ""
    @Published public var appleUserId      = ""
    @Published public var deviceFlowCode: DeviceFlowDisplay? = nil
    @Published public var error: String?   = nil

    // Multiple saved accounts per method — active index stored in UserDefaults
    @Published public var savedAppleAccounts: [SavedAccount] = []
    @Published public var savedGitHubAccounts: [SavedAccount] = []

    private let githubClientId = "Ov23li2K0njEqO1WTSdD"

    // MARK: — Continue as Guest
    public func continueAsGuest() {
        isGuest    = true
        isSignedIn = true
        username   = "Guest"
        error      = nil
        Task { await UserVaultService.shared.setup(githubUsername: nil) }
    }

    // MARK: — Sign in with Apple
    public func signInWithApple() {
        error = nil
        let provider   = ASAuthorizationAppleIDProvider()
        let request    = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                   = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // Swap to a different saved Apple account
    public func switchAppleAccount(to account: SavedAccount) {
        appleUserId = account.id
        username    = account.displayName
        KeychainService.shared.save(key: "apple_user_id",      value: account.id)
        KeychainService.shared.save(key: "apple_display_name", value: account.displayName)
        isSignedIn = true
        isGuest    = false
        Task { await UserVaultService.shared.setup(githubUsername: githubConnected ? githubUsername : nil) }
    }

    public func restoreAppleSession() {
        let uid = KeychainService.shared.load(key: "apple_user_id") ?? ""
        guard !uid.isEmpty else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: uid) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard state == .authorized else { return }
                self?.appleUserId = uid
                self?.isSignedIn  = true
                self?.username    = KeychainService.shared.load(key: "apple_display_name") ?? "User"
                // Restore vault
                Task {
                    await UserVaultService.shared.setup(
                        githubUsername: self?.githubConnected == true ? self?.githubUsername : nil
                    )
                }
            }
        }
        loadSavedAccounts()
    }

    // MARK: — GitHub Device Flow
    public func startGitHubAuth() async {
        error = nil
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: githubClientId)
            deviceFlowCode = DeviceFlowDisplay(
                userCode:        flow.userCode,
                verificationUrl: flow.verificationUri,
                deviceCode:      flow.deviceCode,
                interval:        flow.interval)
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pollForGitHubToken(deviceCode: String, interval: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            if let token = try? await GitHubClient.shared.pollDeviceFlow(
                clientId: githubClientId, deviceCode: deviceCode), !token.isEmpty {

                KeychainService.shared.save(key: "github_pat", value: token)
                await GitHubClient.shared.setToken(token)

                // Fetch real GitHub username
                let ghUser = await fetchGitHubUsername()
                githubConnected  = true
                githubUsername   = ghUser
                deviceFlowCode   = nil
                if !isSignedIn { isSignedIn = true; username = ghUser }

                // Save account + setup vault
                saveGitHubAccount(id: ghUser, displayName: ghUser)
                Task { await UserVaultService.shared.setup(githubUsername: ghUser) }
                return
            }
        }
        deviceFlowCode = nil
        error = "Authorization timed out. Please try again."
    }

    // Swap to a different saved GitHub account
    public func switchGitHubAccount(to account: SavedAccount) {
        guard let token = KeychainService.shared.load(key: "github_pat_\(account.id)") else { return }
        KeychainService.shared.save(key: "github_pat", value: token)
        Task { await GitHubClient.shared.setToken(token) }
        githubUsername  = account.displayName
        githubConnected = true
        Task { await UserVaultService.shared.setup(githubUsername: account.displayName) }
    }

    // Disconnect current GitHub account
    public func disconnectGitHub() {
        githubConnected = false
        githubUsername  = ""
        KeychainService.shared.delete(key: "github_pat")
    }

    // MARK: — PAT sign-in (Settings only)
    public func signInWithPAT(pat: String) {
        guard !pat.isEmpty else { error = "Please enter a PAT"; return }
        error = nil
        KeychainService.shared.save(key: "github_pat", value: pat)
        Task { await GitHubClient.shared.setToken(pat) }
        githubConnected = true
        githubUsername  = "dartsolarpunk"
        if !isSignedIn { isSignedIn = true; username = "dartsolarpunk" }
        Task { await UserVaultService.shared.setup(githubUsername: "dartsolarpunk") }
    }

    // MARK: — Privacy policy
    @AppStorage("policy_accepted_v1") public var hasAcceptedPolicy = false
    public func acceptPolicy() { hasAcceptedPolicy = true }

    // MARK: — Sign out (single method, clears active session)
    public func signOut() {
        isSignedIn = false; isGuest = false; githubConnected = false
        username = ""; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil
        KeychainService.shared.delete(key: "apple_user_id")
        KeychainService.shared.delete(key: "github_pat")
    }

    // MARK: — Helpers
    private func fetchGitHubUsername() async -> String {
        return (try? await GitHubClient.shared.fetchAuthenticatedUser()) ?? "GitHub User"
    }

    // MARK: — Multi-account persistence
    private func saveGitHubAccount(id: String, displayName: String) {
        var accounts = savedGitHubAccounts
        if !accounts.contains(where: { $0.id == id }) {
            accounts.append(SavedAccount(id: id, displayName: displayName))
            savedGitHubAccounts = accounts
            persistAccounts()
        }
        // Store per-account PAT
        if let token = KeychainService.shared.load(key: "github_pat") {
            KeychainService.shared.save(key: "github_pat_\(id)", value: token)
        }
    }

    private func loadSavedAccounts() {
        if let data = UserDefaults.standard.data(forKey: "saved_github_accounts"),
           let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            savedGitHubAccounts = accounts
        }
        if let data = UserDefaults.standard.data(forKey: "saved_apple_accounts"),
           let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            savedAppleAccounts = accounts
        }
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(savedGitHubAccounts) {
            UserDefaults.standard.set(data, forKey: "saved_github_accounts")
        }
    }
}

// MARK: — ASAuthorization delegates
extension AuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }

        let uid       = cred.user
        let firstName = cred.fullName?.givenName ?? ""
        let lastName  = cred.fullName?.familyName ?? ""
        let fullName  = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let display   = fullName.isEmpty
            ? (KeychainService.shared.load(key: "apple_display_name") ?? "User")
            : fullName

        KeychainService.shared.save(key: "apple_user_id",      value: uid)
        KeychainService.shared.save(key: "apple_display_name", value: display)

        // Save to multi-account list
        if !savedAppleAccounts.contains(where: { $0.id == uid }) {
            savedAppleAccounts.append(SavedAccount(id: uid, displayName: display))
            if let data = try? JSONEncoder().encode(savedAppleAccounts) {
                UserDefaults.standard.set(data, forKey: "saved_apple_accounts")
            }
        }

        appleUserId = uid
        username    = display
        isSignedIn  = true
        isGuest     = false
        error       = nil

        // Setup Autumn-Ash vault
        Task {
            await UserVaultService.shared.setup(
                githubUsername: githubConnected ? githubUsername : nil
            )
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError err: Error
    ) {
        let asErr = err as? ASAuthorizationError
        if asErr?.code == .canceled { return }
        error = err.localizedDescription
    }
}

// MARK: — Models
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
