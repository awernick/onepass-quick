import AppKit
import SwiftUI

/// NSTextField wrapper that reliably becomes first responder in an NSPanel.
///
/// SwiftUI's `TextField` cannot reliably receive focus when embedded in
/// an `NSPanel` via `NSHostingView`. This representable wraps a native
/// `NSTextField` and exposes a focus trigger to programmatically activate it.
struct SearchField: NSViewRepresentable {

    @Binding var text: String

    /// Toggle this value to request focus. The field will call
    /// `makeFirstResponder` whenever this value changes.
    @Binding var focusTrigger: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = "Search items..."
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update text if it differs to avoid cursor jumps
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Focus the field when the trigger changes
        if focusTrigger {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                self.focusTrigger = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {

        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
