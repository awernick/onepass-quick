import AppKit
import os.log
import SwiftUI

/// Manages the lifecycle, positioning, and keyboard handling of the
/// quick access panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "PanelController"
    )

    private let panel: QuickAccessPanel
    private let viewModel: SearchViewModel
    private let actionHandler: ActionHandler

    /// Binding bridge: since NSHostingView is created once, we use a
    /// reference-type wrapper so SwiftUI can observe changes.
    private let focusTriggerSubject = FocusTriggerSubject()

    /// The app that was active before the panel was shown.
    /// Restored on hide so the user returns to their previous context.
    private var previousApp: NSRunningApplication?

    /// Local key event monitor, active only while the panel is visible.
    private var keyMonitor: Any?

    /// Reference to the hotkey manager, used to register/unregister
    /// panel-visible shortcuts at the CGEvent tap level.
    private weak var hotkeyManager: HotkeyManager?

    override init() {
        panel = QuickAccessPanel()
        viewModel = SearchViewModel()
        // Temporary placeholder -- replaced after super.init()
        actionHandler = ActionHandler(
            viewModel: viewModel,
            onDismiss: {},
            onClearPreviousApp: {}
        )
        super.init()

        // Wire up closures now that `self` is available
        actionHandler.onDismiss = { [weak self] in self?.hide() }
        actionHandler.onClearPreviousApp = { [weak self] in
            self?.previousApp = nil
        }

        panel.delegate = self
        setupHostingView()
    }

    /// Set the hotkey manager reference for CGEvent tap shortcut forwarding.
    ///
    /// Called by AppDelegate after both PanelController and HotkeyManager
    /// are created.
    func setHotkeyManager(_ manager: HotkeyManager) {
        hotkeyManager = manager
    }

    // MARK: - Public API

    /// Toggle panel visibility.
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Visibility

    /// Show the panel, load items, and focus the search field.
    private func show() {
        // Capture the frontmost app before we activate ourselves
        previousApp = NSWorkspace.shared.frontmostApplication

        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        viewModel.loadItems()
        requestSearchFieldFocus()
        installKeyMonitor()
        installPanelKeyHandler()
    }

    /// Hide the panel and restore focus to the previous app.
    ///
    /// Safe to call multiple times (idempotent). Called both explicitly
    /// (Esc, Cmd+\) and implicitly via `windowDidResignKey` when the
    /// panel auto-hides due to `hidesOnDeactivate`.
    private func hide() {
        removeKeyMonitor()
        removePanelKeyHandler()

        // Cancel any in-flight actions (credential fetch, toast delay)
        actionHandler.cancelAll()

        if panel.isVisible {
            panel.orderOut(nil)
        }

        viewModel.resetState()

        // Re-activate the previously focused app
        if let app = previousApp {
            app.activate()
            previousApp = nil
        }
    }

    // MARK: - NSWindowDelegate

    /// Called when the panel loses key window status (e.g., user clicks
    /// outside, or `hidesOnDeactivate` triggers). Ensures cleanup runs
    /// even when `hide()` isn't called explicitly.
    ///
    /// Uses `Task { @MainActor in }` instead of `assumeIsolated` because
    /// AppKit does not guarantee the delegate is always called on the main
    /// thread. `assumeIsolated` would trap if that assumption is violated.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            hide()
        }
    }

    // MARK: - Hosting View Setup

    private func setupHostingView() {
        let rootView = SearchView(
            viewModel: viewModel,
            focusTrigger: focusTriggerSubject.binding
        )
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)
    }

    // MARK: - Focus

    private func requestSearchFieldFocus() {
        focusTriggerSubject.value = true
    }

    // MARK: - Keyboard Handling

    /// Install a local event monitor for key events while the panel is visible.
    ///
    /// This intercepts keys even when the search field's field editor is first
    /// responder (unlike `keyDown` override which the field editor swallows).
    private func installKeyMonitor() {
        // Remove any stale monitor to prevent accumulation
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyEvent(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - CGEvent Tap Panel Shortcuts

    /// Register panel-visible shortcuts with the CGEvent tap so they
    /// intercept before other apps' global shortcuts (e.g., Alfred).
    ///
    /// Only shortcuts that conflict with other apps need to go here.
    /// Most panel shortcuts work fine through the local NSEvent monitor.
    private func installPanelKeyHandler() {
        hotkeyManager?.panelKeyHandler = { [weak self] keycode, flags in
            guard let self else { return false }

            // Cmd+Option+C → copy OTP
            let isCKey = keycode == 8
            let isCommand = flags.contains(.maskCommand)
            let isOption = flags.contains(.maskAlternate)
            let noShift = !flags.contains(.maskShift)
            let noControl = !flags.contains(.maskControl)

            if isCKey && isCommand && isOption && noShift && noControl {
                Task { @MainActor in
                    self.actionHandler.copyOTP()
                }
                return true
            }

            return false
        }
    }

    private func removePanelKeyHandler() {
        hotkeyManager?.panelKeyHandler = nil
    }

    // MARK: - Local Key Event Handling

    /// Handle a key event. Returns `nil` to consume, or the event to pass through.
    ///
    /// Modifier checks use `intersection` with device-independent flags to
    /// ignore incidental modifiers (Caps Lock, Fn, etc.).
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53:  // Escape
            hide()
            return nil

        case 125:  // Down Arrow
            viewModel.moveSelection(by: 1)
            return nil

        case 126:  // Up Arrow
            viewModel.moveSelection(by: -1)
            return nil

        case 8 where flags == [.command, .option]:  // Cmd+Option+C
            actionHandler.copyOTP()
            return nil

        case 8 where flags == [.command, .shift]:  // Cmd+Shift+C
            actionHandler.copyPassword()
            return nil

        case 8 where flags == [.command]:  // Cmd+C
            actionHandler.copyUsername()
            return nil

        case 36:  // Enter/Return
            actionHandler.openURL()
            return nil

        case 31 where flags == [.command]:  // Cmd+O
            actionHandler.openInOnePassword()
            return nil

        default:
            return event
        }
    }

    // MARK: - Positioning

    /// Center the panel horizontally, ~20% from the top of the screen
    /// containing the mouse cursor.
    private func positionPanel() {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - (screenFrame.height * 0.2)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Find the screen containing the current mouse location.
    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

// MARK: - Focus Trigger Bridge

/// Reference-type wrapper to bridge a mutable Bool into a SwiftUI Binding.
///
/// Necessary because `PanelController` creates the `NSHostingView` once at
/// init, but needs to toggle focus on each `show()`. A value-type binding
/// would be captured at init time and never update. Uses `@Published` so
/// SwiftUI detects changes and calls `updateNSView` on `SearchField`.
private final class FocusTriggerSubject: ObservableObject {
    @Published var value: Bool = false

    var binding: Binding<Bool> {
        Binding(
            get: { self.value },
            set: { self.value = $0 }
        )
    }
}
