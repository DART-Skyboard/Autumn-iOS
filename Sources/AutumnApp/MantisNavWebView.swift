import SwiftUI
import WebKit

/// TF138: Mantis Navigation, accessed the way the web app actually treats it —
/// as an external resource (`mn.html`, loaded in web's own `<iframe>`), not a
/// native reimplementation. Explicit instruction: Mantis Navigation belongs
/// to the separate Arc Lake system, which isn't ready to be folded into
/// Autumn's core program yet — so this loads the exact same URL web does,
/// the same way a browser would, rather than porting `MantisNavigationView`'s
/// native SceneKit attempt further. That native view still exists in the
/// codebase but is no longer what this HUD button opens.
public struct MantisNavWebView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var loadFailed = false

    private static let url = URL(string: "https://leatr.xyz/mn.html")!

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WebViewRepresentable(url: Self.url, isLoading: $isLoading, loadFailed: $loadFailed)
                .ignoresSafeArea(edges: .bottom)
            if isLoading {
                ProgressView("Loading Mantis Navigation…")
                    .tint(.cyan)
                    .foregroundColor(.white)
            }
            if loadFailed {
                VStack(spacing: 10) {
                    Text("Couldn't reach Mantis Navigation")
                        .foregroundColor(.white.opacity(0.8))
                    Text(Self.url.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("MANTIS NAVIGATION")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#00e5ff"))
                Spacer()
                Button { dismiss() } label: {
                    Text("✕").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let v = WKWebView(frame: .zero, configuration: config)
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable
        init(_ parent: WebViewRepresentable) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.loadFailed = true
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.loadFailed = true
        }
    }
}
