
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
    @Published public var deviceFlowCode: DeviceFlowCode? = nil
    @Published public var error: String?   = nil

    // Correct client_id — Ov23li prefix
    private let githubClientId = "Ov23li2K0njEqO1WTSdD"

    // MARK: — Continue as Guest (no account needed)
    public func continueAsGuest() {
        isGuest    = true
        isSignedIn = true
        username   = "Guest"
        error      = nil
    }

    // MARK: — Sign in with Apple
    // Fix for error 1000: must set presentationContextProvider
    public func signInWithApple() {
        error = nil
        let provider  = ASAuthorizationAppleIDProvider()
        let request   = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                  = self
        controller.presentationContextProvider = self   // ← fixes error 1000
        controller.performRequests()
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
            }
        }
    }

    // MARK: — GitHub Device Flow
    public func startGitHubAuth() async {
        error = nil
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: githubClientId)
            deviceFlowCode = DeviceFlowCode(
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
                githubConnected = true
                githubUsername  = "GitHub User"
                deviceFlowCode  = nil
                if !isSignedIn { isSignedIn = true; username = "User" }
                return
            }
        }
        deviceFlowCode = nil
        error = "Authorization timed out. Please try again."
    }

    // MARK: — Sign in with PAT (Settings only — not on welcome screen)
    public func signInWithPAT(pat: String) {
        guard !pat.isEmpty else { error = "Please enter a PAT"; return }
        error = nil
        KeychainService.shared.save(key: "github_pat", value: pat)
        githubConnected = true
        githubUsername  = "dartsolarpunk"
        if !isSignedIn { isSignedIn = true; username = "User" }
    }

    // MARK: — Privacy policy
    @AppStorage("policy_accepted_v1") public var hasAcceptedPolicy = false

    public func acceptPolicy() {
        hasAcceptedPolicy = true
    }

    // MARK: — Sign out
    public func signOut() {
        isSignedIn = false; isGuest = false; githubConnected = false
        username = ""; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil
        KeychainService.shared.delete(key: "apple_user_id")
        KeychainService.shared.delete(key: "github_pat")
    }
}

// MARK: — ASAuthorization delegates
// Both required: delegate (callbacks) + presentation context (fixes error 1000)
extension AuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    // ── Presentation context — gives Apple a window to present the sheet from ──
    public func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // Find the frontmost key window
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }

    // ── Success ──────────────────────────────────────────────────────
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }

        let uid = cred.user
        // Apple only sends full name on first auth — cache it
        let firstName = cred.fullName?.givenName ?? ""
        let lastName  = cred.fullName?.familyName ?? ""
        let fullName  = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let display   = fullName.isEmpty
            ? (KeychainService.shared.load(key: "apple_display_name") ?? "User")
            : fullName

        KeychainService.shared.save(key: "apple_user_id",      value: uid)
        KeychainService.shared.save(key: "apple_display_name", value: display)

        appleUserId = uid
        username    = display
        isSignedIn  = true
        isGuest     = false
        error       = nil
    }

    // ── Failure ───────────────────────────────────────────────────────
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError err: Error
    ) {
        let asErr = err as? ASAuthorizationError
        // 1001 = user cancelled — silent
        if asErr?.code == .canceled { return }
        error = err.localizedDescription
    }
}
