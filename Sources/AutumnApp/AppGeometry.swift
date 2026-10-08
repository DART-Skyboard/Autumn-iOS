import UIKit

/// Window/scene-based geometry (no UIScreen.main): the app can be resized (iPhone Duo, iPhone Mirroring),
/// so sizes come from the app's own window, and keyboard frames are converted into that window's space.
enum AppGeometry {
    static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let sc = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return sc?.windows.first { $0.isKeyWindow } ?? sc?.windows.first { !($0 is PassthroughWindow) } ?? sc?.windows.first
    }

    static var bounds: CGRect {
        if let w = window { return w.bounds }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.coordinateSpace.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    /// Keyboard end-frame (screen coordinates) -> frame in the app window's coordinates.
    static func inWindow(_ screenFrame: CGRect) -> CGRect {
        guard let w = window else { return screenFrame }
        return w.convert(screenFrame, from: w.screen.coordinateSpace)
    }

    /// How far the keyboard covers the bottom of the app window.
    static func keyboardOverlap(_ screenFrame: CGRect) -> CGFloat {
        guard let w = window else { return 0 }
        return max(0, w.bounds.maxY - inWindow(screenFrame).minY)
    }
}
