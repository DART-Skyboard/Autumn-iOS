import SwiftUI
import UIKit

/// UIKit composer for "Ask Autumn…", reintroduced at TF103.
///
/// Background: TF89's plain SwiftUI `TextField` + `@FocusState` + a
/// `ToolbarItemGroup(placement: .keyboard)` hide-keyboard button reproduced a
/// "keyboard shows once, then stops responding until the view is torn down and
/// rebuilt" bug. TF102 tried the documented fix for that exact SwiftUI pattern
/// (wrap the hierarchy in a `NavigationStack`) — confirmed on-device that alone
/// wasn't enough, most likely because of how the OS-beta iOS 27 keyboard/focus
/// pipeline this ships against behaves, not something a source-level SwiftUI
/// workaround can route around from outside UIKit.
///
/// This composer takes first-responder control directly via UIKit instead of
/// going through SwiftUI's `@FocusState` layer at all. It previously existed
/// (TF90) and was removed (TF98) only because of two *unrelated* bugs it had —
/// both fixed here from the start, not reintroduced:
///   1. A `touchesBegan` override that manually called `becomeFirstResponder()`,
///      racing UITextView's own internal tap-to-edit gesture recognizer. Not
///      present here — UITextView already becomes first responder on tap
///      natively (isEditable/isSelectable/isUserInteractionEnabled are true).
///   2. An `intrinsicContentSize` that called `sizeThatFits` from within itself,
///      recursing into layout. Fixed here: height is owned by SwiftUI's
///      `.frame(minHeight:maxHeight:)`, this always returns a fixed value.
/// (Separately: the scene-create watchdog crash chased across builds 91-99 was
/// eventually traced to a diagnostic tool's `UserDefaults.synchronize()` call
/// and a synchronous NotificationCenter post — neither related to this file.)
struct AskAutumnComposer: UIViewRepresentable {
    @Binding var text: String
    var accent: UIColor
    var onSubmit: () -> Void
    /// TF104: without this, the composer's height was left to whatever SwiftUI's
    /// generic UIViewRepresentable sizing guessed from the min/maxHeight range —
    /// in practice it settled much closer to the max than the actual single-line
    /// content needed, making the whole input bar visibly too tall. Reporting the
    /// real measured height back (and having InputBar apply it directly via
    /// .frame(height:)) makes it size to content: short by default, grows only
    /// when the text actually wraps to more lines.
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AskAutumnTextView {
        let tv = AskAutumnTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.tintColor = accent
        tv.font = .systemFont(ofSize: 16)
        tv.keyboardType = .default
        tv.returnKeyType = .send
        tv.autocapitalizationType = .sentences
        tv.autocorrectionType = .yes
        tv.spellCheckingType = .default
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.keyboardDismissMode = .none
        tv.isEditable = true
        tv.isSelectable = true
        tv.isUserInteractionEnabled = true
        tv.adjustsFontForContentSizeCategory = true
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.accessibilityLabel = "Ask Autumn"
        tv.attributedPlaceholder = placeholder(accent: accent)
        context.coordinator.installAccessory(on: tv, accent: accent)
        return tv
    }

    func updateUIView(_ uiView: AskAutumnTextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.text = text
            if selected.location <= (uiView.text as NSString).length {
                uiView.selectedRange = selected
            }
        }
        context.coordinator.measureHeight(uiView)
        uiView.tintColor = accent
        uiView.attributedPlaceholder = placeholder(accent: accent)
        uiView.setPlaceholderVisible(text.isEmpty && !uiView.isFirstResponder)
    }

    private func placeholder(accent: UIColor) -> NSAttributedString {
        NSAttributedString(
            string: "Ask Autumn...",
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.35),
                .font: UIFont.systemFont(ofSize: 16)
            ]
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AskAutumnComposer
        init(_ parent: AskAutumnComposer) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            textView.invalidateIntrinsicContentSize()
            if let tv = textView as? AskAutumnTextView {
                tv.setPlaceholderVisible((textView.text ?? "").isEmpty)
            }
            measureHeight(textView)
        }

        /// Measures the actual content height (1 line by default, grows as text
        /// wraps) and writes it back to InputBar's @State so .frame(height:) uses
        /// a real value instead of SwiftUI guessing within the min/maxHeight range.
        func measureHeight(_ textView: UITextView) {
            let width = textView.bounds.width > 0 ? textView.bounds.width : UIScreen.main.bounds.width - 140
            let fitSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let clamped = min(96, max(40, fitSize.height))
            if abs(parent.measuredHeight - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.measuredHeight = clamped }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if let tv = textView as? AskAutumnTextView {
                tv.setPlaceholderVisible(false)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if let tv = textView as? AskAutumnTextView {
                tv.setPlaceholderVisible((textView.text ?? "").isEmpty)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func installAccessory(on tv: UITextView, accent: UIColor) {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
            bar.barStyle = .black
            bar.isTranslucent = true
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let hide = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain,
                target: self,
                action: #selector(hideKeyboard)
            )
            hide.tintColor = accent
            hide.accessibilityLabel = "Hide keyboard"
            bar.items = [spacer, hide]
            tv.inputAccessoryView = bar
        }

        @objc func hideKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

final class AskAutumnTextView: UITextView {
    private let placeholderLabel = UILabel()

    var attributedPlaceholder: NSAttributedString? {
        didSet { placeholderLabel.attributedText = attributedPlaceholder }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeFirstResponder: Bool { true }

    // Height is owned by SwiftUI (.frame(minHeight:maxHeight:)) — never derive it
    // from sizeThatFits here, which would recurse into layout (the TF91 bug).
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        placeholderLabel.frame = CGRect(
            x: inset.left + textContainer.lineFragmentPadding,
            y: inset.top,
            width: max(0, bounds.width - inset.left - inset.right),
            height: 22
        )
    }

    // No touchesBegan override — UITextView already becomes first responder on
    // tap via its own gesture recognizers (isEditable/isSelectable/
    // isUserInteractionEnabled are all true above). Manually forcing
    // becomeFirstResponder() here raced that native gesture recognizer and was
    // the actual cause of the original "works once, dead after" bug.

    func setPlaceholderVisible(_ visible: Bool) {
        placeholderLabel.isHidden = !visible
    }
}
