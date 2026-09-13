// AppleSignInButton.swift — Crash-safe Sign in with Apple (ported from AshtreeIDE)
//
// ROOT CAUSE: SwiftUI's SignInWithAppleButton calls ASAuthorizationController
// internally. When its onCompletion then starts a *second* controller (or when
// the button is not at the root window), iOS can crash / fail silently.
//
// FIX: UIViewRepresentable wrapping ASAuthorizationAppleIDButton; Coordinator
// owns the controller and presents from the live key window.
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

    public func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: AppleSignInButton
        private var controller: ASAuthorizationController?

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
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? UIWindow()
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
