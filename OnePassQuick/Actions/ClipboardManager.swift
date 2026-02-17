import AppKit
import os.log

/// Manages clipboard operations with support for concealed (sensitive) content.
///
/// Passwords are set with the `org.nspasteboard.ConcealedType` pasteboard type
/// so clipboard history tools and password managers know the content is sensitive.
/// All clipboard content auto-clears after 30 seconds.
enum ClipboardManager {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "ClipboardManager"
    )

    /// Pasteboard type used by convention to mark sensitive clipboard content.
    private static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )

    /// Duration before clipboard is auto-cleared.
    private static let clearDelay: TimeInterval = 30

    /// The pending clear task. Stored so repeated copies cancel the previous
    /// timer instead of accumulating.
    private static var clearTask: DispatchWorkItem?

    // MARK: - Public API

    /// Copy text to the clipboard.
    ///
    /// - Parameters:
    ///   - text: The string to copy.
    ///   - concealed: When `true`, also sets the concealed pasteboard type
    ///     so clipboard history tools know this is sensitive. Defaults to `true`.
    static func copy(_ text: String, concealed: Bool = true) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if concealed {
            pasteboard.setString(text, forType: concealedType)
        }
        pasteboard.setString(text, forType: .string)

        log.info("Copied to clipboard (concealed: \(concealed))")
        scheduleClear()
    }

    /// Clear the clipboard immediately.
    static func clear() {
        clearTask?.cancel()
        clearTask = nil

        NSPasteboard.general.clearContents()
        log.info("Clipboard cleared")
    }

    // MARK: - Private

    /// Schedule a clipboard clear after `clearDelay` seconds.
    /// Cancels any previously scheduled clear.
    ///
    /// Captures the pasteboard's `changeCount` at schedule time and only
    /// clears if it hasn't changed — meaning the user hasn't copied
    /// something else in the meantime.
    private static func scheduleClear() {
        clearTask?.cancel()

        let changeCount = NSPasteboard.general.changeCount
        let task = DispatchWorkItem {
            guard NSPasteboard.general.changeCount == changeCount else {
                log.info(
                    "Skipping auto-clear — clipboard was replaced"
                )
                return
            }
            NSPasteboard.general.clearContents()
            log.info("Clipboard auto-cleared after \(Int(clearDelay))s")
        }
        clearTask = task

        DispatchQueue.main.asyncAfter(
            deadline: .now() + clearDelay,
            execute: task
        )
    }
}
