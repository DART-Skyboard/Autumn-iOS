import SwiftUI
import UIKit

/// The "hide keyboard" button for everywhere except Ask Autumn (which keeps its own bar on the keyboard).
/// Same icon and glass-circle look as the original, floating at the right just above the keyboard. It lives in its
/// own passthrough window so it shows over the Admin console, sheets and every overlay; only the button takes touches.
@MainActor
final class KeyboardDismissWindow {
    static let shared = KeyboardDismissWindow()
    var accent: UIColor = .white { didSet { icon?.tintColor = accent } }

    private var window: PassthroughWindow?
    private var holder: UIView?
    private var icon: UIImageView?
    private var started = false
    private var lastTop: CGFloat = 0

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.changed(n) }
        }
        nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window?.isHidden = true }
        }
        nc.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }
    }

    private func scene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func changed(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let sc = scene() else { return }
        let screen = sc.screen.bounds
        guard end.height > 80, end.minY < screen.height - 40 else { window?.isHidden = true; return }
        lastTop = end.minY
        let w = ensureWindow(sc)
        let d: CGFloat = 56
        holder?.frame = CGRect(x: screen.width - d - 14, y: end.minY - d - 10, width: d, height: d)
        w.isHidden = false
        refreshVisibility()
        DispatchQueue.main.async { [weak self] in self?.refreshVisibility() }
    }

    /// Hidden while Ask Autumn's composer is focused (it already has the button on its keyboard bar).
    private func refreshVisibility() {
        guard let w = window, lastTop > 0 else { return }
        FirstResponderProbe.found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.autumnProbeFirstResponder), to: nil, from: nil, for: nil)
        let ask = FirstResponderProbe.found is AskAutumnTextView
        w.isHidden = ask
    }

    private func ensureWindow(_ sc: UIWindowScene) -> PassthroughWindow {
        if let w = window, w.windowScene === sc { return w }
        let w = PassthroughWindow(windowScene: sc)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        w.rootViewController = vc
        let d: CGFloat = 56
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.frame = CGRect(x: 0, y: 0, width: d, height: d)
        blur.layer.cornerRadius = d / 2
        blur.clipsToBounds = true
        blur.layer.borderWidth = 1
        blur.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        let img = UIImageView(image: UIImage(systemName: "keyboard.chevron.compact.down",
                                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)))
        img.tintColor = accent
        img.contentMode = .center
        img.frame = blur.bounds
        blur.contentView.addSubview(img)
        let tap = UIButton(type: .custom)
        tap.frame = blur.bounds
        tap.accessibilityLabel = "Hide keyboard"
        tap.addAction(UIAction { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }, for: .touchUpInside)
        blur.contentView.addSubview(tap)
        vc.view.addSubview(blur)
        w.chip = blur
        holder = blur
        icon = img
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
