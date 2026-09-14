import SwiftUI
import AutumnServices
import AuthenticationServices
import LEATRCore

/// After Privacy Policy: Welcome (Arc Lake–style) → shell.
/// `showWelcome` / cleared `autumn_welcome_done_v1` force Welcome again (Sign Out & Welcome).
public struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appNav: AppNavigation
    @AppStorage("autumn_welcome_done_v1") private var welcomeDone = false

    public var body: some View {
        return Group {
            if appNav.showWelcome || !welcomeDone {
                WelcomeView()
            } else {
                AppShellView()
            }
        }
        .onAppear { authVM.restoreSession() }
        .onOpenURL { url in
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
