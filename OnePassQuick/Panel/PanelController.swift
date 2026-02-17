import AppKit
import SwiftUI

/// Manages the lifecycle and positioning of the quick access panel.
final class PanelController {

    private let panel: QuickAccessPanel

    init() {
        panel = QuickAccessPanel()

        // Embed a placeholder SwiftUI view (replaced in M2 with SearchView)
        let placeholder = NSHostingView(rootView: PlaceholderView())
        placeholder.frame = panel.contentView?.bounds ?? .zero
        placeholder.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(placeholder)
    }

    // MARK: - Visibility

    /// Toggle panel visibility.
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Show the panel centered horizontally, positioned near the top of the screen.
    ///
    /// The panel uses `.popUpMenu` level + `.canJoinAllSpaces` so app
    /// activation won't trigger a workspace switch -- the panel exists
    /// on every space and the level is above what AeroSpace manages.
    func show() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the panel.
    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Positioning

    /// Center the panel horizontally, ~1/4 from the top of the main screen.
    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - (screenFrame.height * 0.2)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Placeholder View

/// Temporary placeholder shown until M2 adds the real search UI.
private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("OnePass Quick")
                .font(.title2)
                .foregroundStyle(.primary)
            Text("Press Esc to dismiss")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
