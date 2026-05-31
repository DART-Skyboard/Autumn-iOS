import SwiftUI
import AuthenticationServices
import AutumnServices

// MARK: — Auth ViewModel
@MainActor
public final class AuthViewModel: NSObject, ObservableObject {

    @Published public var isSignedIn = false
    @Published public var githubConnected = false
    @Published public var username = ""
    @Published public var appleUserId = ""
    @Published public var deviceFlowCode: DeviceFlowCode? = nil
    @Published public var error: String? = nil

    // GitHub OAuth App client ID (device flow — no secret needed)
    // Replace with your actual OAuth App client_id from github.com/settings/developers
    private let githubClientId = "Ov23li2li2K0njEqO1WTSdD"

    // MARK: — Sign in with Apple
    public func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    public func restoreAppleSession() {
        let uid = KeychainService.shared.load(key: "apple_user_id") ?? ""
        guard !uid.isEmpty else { return }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: uid) { [weak self] state, _ in
            DispatchQueue.main.async {
                if state == .authorized {
                    self?.appleUserId = uid
                    self?.isSignedIn = true
                    self?.username = KeychainService.shared.load(key: "apple_display_name") ?? "User"
                }
            }
        }
    }

    // MARK: — GitHub Device Flow
    public func startGitHubAuth() async {
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: githubClientId)
            await MainActor.run {
                deviceFlowCode = DeviceFlowCode(
                    userCode: flow.userCode,
                    verificationUrl: flow.verificationUri,
                    deviceCode: flow.deviceCode,
                    interval: flow.interval
                )
            }
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval)
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func pollForGitHubToken(deviceCode: String, interval: Int) async {
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            if let token = try? await GitHubClient.shared.pollDeviceFlow(
                clientId: githubClientId, deviceCode: deviceCode) {
                await GitHubClient.shared.setToken(token)
                await MainActor.run {
                    self.githubConnected = true
                    self.deviceFlowCode = nil
                }
                return
            }
        }
        await MainActor.run { error = "GitHub auth timed out." }
    }

    public func connectGitHubPAT(_ pat: String) async {
        await GitHubClient.shared.setToken(pat)
        await MainActor.run { githubConnected = true }
    }

    public func signOut() {
        KeychainService.shared.delete(key: "apple_user_id")
        KeychainService.shared.delete(key: "github_pat")
        isSignedIn = false
        githubConnected = false
        username = ""
    }
}

// MARK: — Apple Auth Delegate
extension AuthViewModel: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        let uid = cred.user
        let name = [cred.fullName?.givenName, cred.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        KeychainService.shared.save(key: "apple_user_id", value: uid)
        if !name.isEmpty { KeychainService.shared.save(key: "apple_display_name", value: name) }
        appleUserId = uid
        username = name.isEmpty ? "User" : name
        isSignedIn = true
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        self.error = error.localizedDescription
    }
}

// MARK: — Device Flow UI Model
public struct DeviceFlowCode: Identifiable {
    public let id = UUID()
    public let userCode: String
    public let verificationUrl: String
    public let deviceCode: String
    public let interval: Int
}