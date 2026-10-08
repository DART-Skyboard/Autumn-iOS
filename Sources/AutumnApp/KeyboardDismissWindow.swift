import SwiftUI
import UIKit

/// App-wide "hide keyboard" chip. Lives in its own passthrough UIWindow above everything
/// (sheets, full-screen covers, the Admin drawer, every overlay), so it appears whenever the
/// keyboard is up, whatever the user is doing. Only the chip itself takes touches.
@MainActor
final class KeyboardDismissWindow {
    static let shared = KeyboardDismissWindow()
    var accent: UIColor = UIColor(red: 0, green: 0.9, blue: 1, alpha: 1) { didSet { button?.tintColor = accent; button?.layer.borderColor = accent.withAlphaComponent(0.45).cgColor } }

    private var window: PassthroughWindow?
    private var button: UIButton?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.keyboardChanged(n) }
        }
        nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func scene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func keyboardChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let sc = scene() else { return }
        let screen = sc.screen.bounds
        // Floating / hardware-keyboard states report a frame at or below the screen edge: nothing to hide.
        guard end.height > 80, end.minY < screen.height - 40 else { hide(); return }
        let w = ensureWindow(sc)
        let size = CGSize(width: 52, height: 40)
        button?.frame = CGRect(x: screen.width - size.width - 12, y: end.minY - size.height - 8, width: size.width, height: size.height)
        w.isHidden = false
    }

    private func hide() { window?.isHidden = true }

    private func ensureWindow(_ sc: UIWindowScene) -> PassthroughWindow {
        if let w = window, w.windowScene === sc { return w }
        let w = PassthroughWindow(windowScene: sc)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        w.rootViewController = vc
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        b.tintColor = accent
        b.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        b.layer.cornerRadius = 20
        b.layer.borderWidth = 1
        b.layer.borderColor = accent.withAlphaComponent(0.45).cgColor
        b.accessibilityLabel = "Hide keyboard"
        b.addAction(UIAction { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }, for: .touchUpInside)
        vc.view.addSubview(b)
        w.chip = b
        button = b
        window = w
        return w
    }
}

final class PassthroughWindow: UIWindow {
    weak var chip: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let chip, !isHidden else { return nil }
        let p = chip.convert(point, from: self)
        return chip.point(inside: p, with: event) ? chip.hitTest(p, with: event) : nil
    }
}
