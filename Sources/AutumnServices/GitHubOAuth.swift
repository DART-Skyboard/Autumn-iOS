import Foundation
import AuthenticationServices
import UIKit

/// Native GitHub login using the same OAuth App as leatr.xyz.
/// Device flow + ASWebAuthenticationSession (no client secret, no PAT paste).
/// Web-flow code exchange via GAS (`?action=exchange&code=`) is also supported if a code lands.
@MainActor
public final class GitHubOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    public static let shared = GitHubOAuth()
    private var session: ASWebAuthenticationSession?

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow } ?? UIWindow()
    }

    /// Open GitHub device verification in an in-app auth session.
    public func openDeviceVerification(url: URL) {
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: AutumnConfig.oauthCallbackScheme) { _, _ in }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    public func cancel() {
        session?.cancel()
        session = nil
    }
}
