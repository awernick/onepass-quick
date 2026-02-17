import AppKit
import ApplicationServices
import os.log

/// Registers a global Cmd+\ hotkey using a CGEvent tap.
///
/// Requires Accessibility permission. Checks permission on every launch
/// and logs the result. If the event tap fails to create, surfaces the
/// error through the menu bar icon tooltip and logs it.
///
/// - Note: Keycode 42 (`\`) is US-keyboard-specific. Non-US layouts may
///   map a different character to this keycode.
final class HotkeyManager {

    /// Keycode for `\` on US keyboard layout.
    private static let backslashKeycode: Int64 = 42

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "HotkeyManager"
    )

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: () -> Void

    /// Whether the event tap is active and consuming events.
    private(set) var isActive: Bool = false

    /// Creates a hotkey manager that calls `handler` when Cmd+\ is pressed.
    ///
    /// - Parameter handler: Closure invoked on the main thread when the
    ///   hotkey is detected.
    init(handler: @escaping () -> Void) {
        self.handler = handler
        setupEventTap()
    }

    deinit {
        removeEventTap()
    }

    // MARK: - Setup

    private func setupEventTap() {
        let trusted = AXIsProcessTrusted()
        Self.log.info("Accessibility permission: \(trusted ? "granted" : "NOT granted")")

        if !trusted {
            Self.log.warning("Event tap requires Accessibility permission -- prompting user")
            promptForAccessibility()
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // The callback must be a C function pointer, so we pass `self` as userInfo
        // and retrieve it inside the callback.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPointer
        ) else {
            Self.log.error(
                "Failed to create CGEvent tap. Permission granted but tap creation failed -- try restarting the app."
            )
            isActive = false
            return
        }

        eventTap = tap
        isActive = true

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Self.log.info("CGEvent tap created and active -- Cmd+\\ is registered")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    // MARK: - Event Handling

    private func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // If the tap is disabled by the system (e.g., timeout), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.log.warning("Event tap was disabled by system -- re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isBackslash = keycode == Self.backslashKeycode
        let isCommand = flags.contains(.maskCommand)
        let noExtraModifiers = !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskShift)

        if isBackslash && isCommand && noExtraModifiers {
            Self.log.debug("Cmd+\\ detected -- consuming event and toggling panel")
            DispatchQueue.main.async { [weak self] in
                self?.handler()
            }
            // Consume the event so other apps don't also react
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Accessibility Permission

    private func promptForAccessibility() {
        // Prompt the system dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            OnePass Quick needs Accessibility permission to register the global \
            Cmd+\\ hotkey.

            Please grant access in:
            System Settings > Privacy & Security > Accessibility

            After granting permission, restart OnePass Quick.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
