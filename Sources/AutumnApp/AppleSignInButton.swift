// AppleSignInButton.swift — Crash-safe Sign in with Apple (ported from AshtreeIDE / ArcLake)
//
// ROOT CAUSE: SwiftUI's SignInWithAppleButton calls ASAuthorizationController
// internally. When its onCompletion then starts a *second* controller (or when
// the button is not at the root window), iOS can crash / fail silently.
//
// FIX: UIViewRepresentable wrapping ASAuthorizationAppleIDButton; Coordinator
// owns the controller and presents from the live key window.
// Arc Lake lesson: app entitlements not granted by the profile poison the whole
// entitlement blob and SIWA fails with ASAuthorizationError 1000 (.unknown).
import SwiftUI
import AuthenticationServices

public struct AppleSignInButton: UIViewRepresentable {
    public let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    public let onCompletion: (Result<ASAuthorization, Error>) -> Void

    public init(
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
        onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void
    ) {
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }

    public func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    public func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.hostView = uiView
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: AppleSignInButton
        private var controller: ASAuthorizationController?
        weak var hostView: UIView?

        public init(parent: AppleSignInButton) { self.parent = parent }

        @objc func tapped() {
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            parent.onRequest(request)
            let ctrl = ASAuthorizationController(authorizationRequests: [request])
            ctrl.delegate = self
            ctrl.presentationContextProvider = self
            controller = ctrl // retain strongly
            ctrl.performRequests()
        }

        public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // Prefer the button's own window (same gesture / hierarchy).
            if let w = hostView?.window { return w }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let w = scenes.filter({ $0.activationState == .foregroundActive })
                .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return w
            }
            if let w = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return w
            }
            if let w = scenes.flatMap({ $0.windows }).first {
                return w
            }
            // Never return a detached UIWindow() — that yields ASAuthorizationError 1000.
            if let scene = scenes.first {
                let w = UIWindow(windowScene: scene)
                w.frame = scene.coordinateSpace.bounds
                w.makeKeyAndVisible()
                return w
            }
            return UIWindow()
        }

        public func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization auth: ASAuthorization
        ) {
            self.controller = nil
            parent.onCompletion(.success(auth))
        }

        public func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            self.controller = nil
            parent.onCompletion(.failure(error))
        }
    }
}
