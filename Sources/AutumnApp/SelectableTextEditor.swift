import SwiftUI
import UIKit

/// TF156: SwiftUI's native TextEditor doesn't expose the selection range,
/// which the system-message editor's "select text, make it a link" tool
/// genuinely needs — wrapping only the selected words, not just inserting
/// a placeholder at the cursor. This is a thin UITextView bridge that
/// keeps the current selection available to the SwiftUI side.
struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 15)
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.isScrollEnabled = true
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if uiView.selectedRange != selectedRange,
           selectedRange.location != NSNotFound,
           selectedRange.location + selectedRange.length <= (uiView.text as NSString).length {
            uiView.selectedRange = selectedRange
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectableTextEditor
        init(_ parent: SelectableTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selectedRange = textView.selectedRange }
    }
}
