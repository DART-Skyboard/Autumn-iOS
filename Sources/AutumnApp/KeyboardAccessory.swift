import SwiftUI
import UIKit

/// The one "hide keyboard" bar (the same toolbar Ask Autumn has always used), shared app-wide.
/// Ask Autumn installs it directly; every other text field / text view (Admin console, AGENTS,
/// Math Solver, LaTeX, Mist, sheets...) gets the same bar automatically when editing begins.
@MainActor
enum KeyboardAccessory {
    /// Updated from the theme so the bar matches Ask Autumn's.
    static var accent: UIColor = .systemTeal
    private static var installed = false

    static func make(accent: UIColor, target: Any?, action: Selector) -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.barStyle = .black
        bar.isTranslucent = true
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let hide = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"),
                                   style: .plain, target: target, action: action)
        hide.tintColor = accent
        hide.accessibilityLabel = "Hide keyboard"
        bar.items = [spacer, hide]
        return bar
    }

    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private final class Target: NSObject { @objc func tap() { KeyboardAccessory.hide() } }
    private static let target = Target()

    static func installEverywhere() {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { attach(n.object as? UIResponder & UITextInput) }
        }
        nc.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { attach(n.object as? UIResponder & UITextInput) }
        }
    }

    private static func attach(_ r: (UIResponder & UITextInput)?) {
        if let f = r as? UITextField, f.inputAccessoryView == nil {
            f.inputAccessoryView = make(accent: accent, target: target, action: #selector(Target.tap))
            f.reloadInputViews()
        } else if let v = r as? UITextView, v.inputAccessoryView == nil {
            v.inputAccessoryView = make(accent: accent, target: target, action: #selector(Target.tap))
            v.reloadInputViews()
        }
    }
}
