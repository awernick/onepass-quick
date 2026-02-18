import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

/// Registers a global Cmd+\ hotkey using a CGEvent tap.
///
/// Requires Accessibility permission. Checks permission on every launch
/// and logs the result. If the event tap fails to create, surfaces the
/// error through the menu bar icon tooltip and logs it.
///
/// Uses `UCKeyTranslate` to resolve the keycode for `\` from the current
/// keyboard layout, so the hotkey works on non-US layouts where the
/// backslash key has a different keycode.
final class HotkeyManager {

    /// The target character for the hotkey (backslash).
    private static let targetCharacter: Character = "\\"

    /// Fallback keycode for `\` on US keyboard layout, used when
    /// `UCKeyTranslate` is unavailable.
    private static let fallbackKeycode: Int64 = 42

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "HotkeyManager"
    )

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: () -> Void

    /// Whether the event tap is active and consuming events.
    private(set) var isActive: Bool = false

    /// Optional handler for panel-visible key events. When set, the
    /// CGEvent tap forwards non-toggle key events to this handler.
    /// Return `true` to consume the event, `false` to pass through.
    ///
    /// Set by `PanelController` during show/hide to intercept shortcuts
    /// (like Cmd+Option+C) at the CGEvent tap level, before other apps'
    /// global shortcuts can steal them.
    var panelKeyHandler: ((_ keycode: Int64, _ flags: CGEventFlags) -> Bool)?

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

        // Check if the key produces `\` in the current keyboard layout,
        // falling back to the US keycode if layout translation fails.
        let isBackslash: Bool
        if let character = Self.characterForKeycode(UInt16(keycode)) {
            isBackslash = character == Self.targetCharacter
        } else {
            isBackslash = keycode == Self.fallbackKeycode
        }

        let isCommand = flags.contains(.maskCommand)
        let noExtraModifiers = !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskShift)

        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if isBackslash && isCommand && noExtraModifiers && !isAutoRepeat {
            Self.log.debug("Cmd+\\ detected -- consuming event and toggling panel")
            DispatchQueue.main.async { [weak self] in
                self?.handler()
            }
            // Consume the event so other apps don't also react
            return nil
        }

        // Still consume auto-repeat Cmd+\ so it doesn't leak to other apps
        if isBackslash && isCommand && noExtraModifiers && isAutoRepeat {
            return nil
        }

        // Forward to panel key handler when the panel is visible.
        // This lets PanelController intercept shortcuts at the CGEvent
        // level (before other apps like Alfred consume them).
        if let panelHandler = panelKeyHandler,
            !isAutoRepeat,
            panelHandler(keycode, flags)
        {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Keyboard Layout Translation

    /// Translate a keycode to the character it produces on the current
    /// keyboard layout (without modifiers).
    ///
    /// Uses `TISCopyCurrentKeyboardLayoutInputSource` and `UCKeyTranslate`
    /// to handle non-US layouts where `\` may be on a different physical key.
    private static func characterForKeycode(_ keycode: UInt16) -> Character? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue()
        else { return nil }

        guard let layoutDataRef = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyUnicodeKeyLayoutData
        ) else { return nil }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let keyLayoutPtr = bytePtr.withMemoryRebound(
            to: UCKeyboardLayout.self, capacity: 1
        ) { $0 }

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            keyLayoutPtr,
            keycode,
            UInt16(kUCKeyActionDown),
            0,  // no modifiers
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0,
            let scalar = UnicodeScalar(chars[0])
        else { return nil }
        return Character(scalar)
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
