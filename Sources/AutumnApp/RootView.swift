import SwiftUI
import AutumnServices
import AuthenticationServices
import LEATRCore

/// Guest-first like the web. Policy gate still wraps the WindowGroup.
public struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel

    public var body: some View {
        AppShellView()
            .onAppear { authVM.restoreSession() }
            .onOpenURL { url in
                // autumn://oauth?code=... if the OAuth App ever adds this callback
                guard url.scheme == AutumnConfig.oauthCallbackScheme else { return }
                if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                   let code = items.first(where: { $0.name == "code" })?.value {
                    Task { await authVM.completeWebFlow(code: code) }
                }
            }
    }
}

// Legacy MainTabView kept so existing previews/tests that import it still compile.
public struct MainTabView: View {
    public var body: some View { AppShellView() }
}
