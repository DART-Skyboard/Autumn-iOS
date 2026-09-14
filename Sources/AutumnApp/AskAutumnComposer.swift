import SwiftUI
import UIKit

/// UIKit composer for “Ask Autumn…”.
/// SwiftUI `TextField(axis: .vertical)` + `@FocusState` + `.toolbar(.keyboard)` (no
/// NavigationStack) was taking SwiftUI focus without calling `becomeFirstResponder`,
/// so the software keyboard never appeared (TF81: focused without a real keyboard).
/// SceneKit/AVPlayer sit in the same window; this field becomes first responder itself.
struct AskAutumnComposer: UIViewRepresentable {
    @Binding var text: String
    var accent: UIColor
    var onSubmit: () -> Void

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

    // Do NOT call sizeThatFits from intrinsicContentSize — that recurses into layout
    // and can stack-overflow / black-screen crash on first ChatView mount (TF91).
    // Height is owned by SwiftUI (.frame(minHeight:maxHeight:)).
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

    // NOTE (TF94): do NOT override touchesBegan to force becomeFirstResponder here.
    // UITextView already becomes first responder on tap via its own internal gesture
    // recognizers (isEditable/isSelectable/isUserInteractionEnabled are all true below).
    // The manual override was racing that internal UITextInteraction gesture: the first
    // tap after mount worked (nothing else had touched the responder chain yet), but any
    // resign — send, the accessory "hide keyboard" button, or an interactive scroll
    // dismiss — left this override's manual call silently losing the race on the next
    // tap. Only a full teardown/rebuild of the view (rotating away and back, which remounts
    // AskAutumnComposer via SwiftUI) reset it. Removing the override lets UIKit's native
    // tap-to-edit handling own first-responder requests, which does not have this race.

    func setPlaceholderVisible(_ visible: Bool) {
        placeholderLabel.isHidden = !visible
    }
}
