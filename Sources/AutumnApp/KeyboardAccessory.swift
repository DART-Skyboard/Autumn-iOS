import SwiftUI
import UIKit

/// The one "hide keyboard" bar (the same toolbar Ask Autumn has always used), shared app-wide.
/// Ask Autumn installs it directly; every other text field / text view (Admin console, AGENTS,
/// Math Solver, LaTeX, Mist, sheets...) gets the same bar automatically when editing begins.
@MainActor
enum KeyboardAccessory {
    /// Updated from the theme so the bar matches Ask Autumn's.
    static var accent: UIColor = .systemTeal

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
}

enum FirstResponderProbe { nonisolated(unsafe) static var found: UIResponder? }
extension UIResponder {
    @objc func autumnProbeFirstResponder() { FirstResponderProbe.found = self }
}
