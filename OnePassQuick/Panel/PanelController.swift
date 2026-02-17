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

    /// Binding bridge: since NSHostingView is created once, we use a
    /// reference-type wrapper so SwiftUI can observe changes.
    private let focusTriggerSubject = FocusTriggerSubject()

    /// The app that was active before the panel was shown.
    /// Restored on hide so the user returns to their previous context.
    private var previousApp: NSRunningApplication?

    /// Local key event monitor, active only while the panel is visible.
    private var keyMonitor: Any?

    /// Guards against overlapping async actions (e.g., double Cmd+Shift+C
    /// while Touch ID is pending).
    private var isPerformingAction: Bool = false

    /// In-flight password fetch task. Stored so it can be cancelled when
    /// the panel hides (e.g., user presses Esc during Touch ID).
    private var actionTask: Task<Void, Never>?

    override init() {
        panel = QuickAccessPanel()
        viewModel = SearchViewModel()
        super.init()
        panel.delegate = self
        setupHostingView()
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
    }

    /// Hide the panel and restore focus to the previous app.
    ///
    /// Safe to call multiple times (idempotent). Called both explicitly
    /// (Esc, Cmd+\) and implicitly via `windowDidResignKey` when the
    /// panel auto-hides due to `hidesOnDeactivate`.
    private func hide() {
        removeKeyMonitor()

        // Cancel any in-flight credential fetch (e.g., Touch ID pending)
        actionTask?.cancel()
        actionTask = nil
        isPerformingAction = false

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
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            hide()
        }
    }

    // MARK: - Hosting View Setup

    private func setupHostingView() {
        let searchView = SearchView(
            viewModel: viewModel,
            focusTrigger: focusTriggerSubject.binding
        )

        let hostingView = NSHostingView(rootView: searchView)
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

        case 8 where flags == [.command, .shift]:  // Cmd+Shift+C
            copyPassword()
            return nil

        case 8 where flags == [.command]:  // Cmd+C
            copyUsername()
            return nil

        case 36:  // Enter/Return
            openURL()
            return nil

        case 31 where flags == [.command]:  // Cmd+O
            openInOnePassword()
            return nil

        default:
            return event
        }
    }

    // MARK: - Actions

    /// Copy the selected item's username to clipboard.
    ///
    /// Uses `additionalInformation` from the cached item list — no CLI call,
    /// no Touch ID.
    private func copyUsername() {
        guard let item = viewModel.selectedItem else { return }

        guard let username = item.additionalInformation, !username.isEmpty else {
            Self.log.info("No username for item '\(item.title)'")
            return
        }

        ClipboardManager.copy(username, concealed: false)
        Self.log.info("Copied username for '\(item.title)'")
        hide()
    }

    /// Copy the selected item's password to clipboard.
    ///
    /// Fetches the password via `op item get` which triggers a Touch ID prompt.
    /// Panel stays visible during the fetch and hides only on success.
    private func copyPassword() {
        guard let item = viewModel.selectedItem else { return }
        guard !isPerformingAction else { return }

        isPerformingAction = true
        actionTask = Task {
            defer { isPerformingAction = false }
            do {
                let password = try await OPClient.getField(
                    itemID: item.id,
                    field: "password"
                )
                guard !Task.isCancelled else { return }
                ClipboardManager.copy(password, concealed: true)
                Self.log.info("Copied password for '\(item.title)'")
                hide()
            } catch OPClientError.fieldNotFound {
                Self.log.info("No password for item '\(item.title)'")
            } catch OPClientError.notAuthenticated {
                Self.log.info("Auth cancelled for '\(item.title)'")
                // User cancelled Touch ID — panel stays open, no-op
            } catch {
                guard !Task.isCancelled else { return }
                Self.log.error("Failed to fetch password: \(error)")
            }
        }
    }

    /// Open the selected item's primary URL in the default browser.
    ///
    /// Uses the cached URL from the item list — no CLI call.
    private func openURL() {
        guard let item = viewModel.selectedItem else { return }

        guard let urlString = item.primaryURL,
              let url = URL(string: urlString)
        else {
            Self.log.info("No URL for item '\(item.title)'")
            return
        }

        NSWorkspace.shared.open(url)
        Self.log.info("Opened URL for '\(item.title)'")
        hide()
    }

    /// Open the 1Password desktop app.
    ///
    /// 1Password 8 does not support deep linking to specific items via
    /// URL scheme (known limitation). This just activates the app so the
    /// user can find the item there. A future improvement could use
    /// Private Links if we fetch the account UUID.
    private func openInOnePassword() {
        guard viewModel.selectedItem != nil else { return }

        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.1password.1password"
        ) {
            NSWorkspace.shared.open(url)
            Self.log.info("Opened 1Password app")
        } else {
            Self.log.error("1Password app not found")
        }
        hide()
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
