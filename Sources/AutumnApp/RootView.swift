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
        // TF102: wrapped in NavigationStack. TextField + @FocusState +
        // ToolbarItemGroup(placement: .keyboard) WITHOUT a NavigationStack in the
        // view hierarchy is a documented SwiftUI reliability issue — the keyboard
        // toolbar/focus state can silently stop calling becomeFirstResponder after
        // the first dismiss, which matches exactly what's been reported: the field
        // focuses and shows the keyboard once, then stops responding until the
        // view is torn down and rebuilt (e.g. by rotating). NavigationStack gives
        // SwiftUI's focus/toolbar machinery the context it expects; the nav bar
        // itself is hidden so nothing changes visually.
        NavigationStack {
            Group {
                if appNav.showWelcome || !welcomeDone {
                    WelcomeView()
                } else {
                    AppShellView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            authVM.restoreSession()
            // TF117: fetch the live grammar reference once per launch — see
            // GrammarReferenceSync's own doc comment for what this does.
            Task { await GrammarReferenceSync.fetchAndApply() }
            // TF126: WordNet buckets now need an authenticated fetch (see
            // WordNetRemoteSync's doc comment) — separate from the reference
            // JSON above since it needs a signed-in GitHub token and skips
            // itself gracefully when there isn't one.
            Task { await WordNetRemoteSync.fetchAndApply() }
        }
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
