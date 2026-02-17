import AppKit

/// Floating NSPanel that tiling window managers (AeroSpace) ignore.
///
/// AeroSpace's `isWindowHeuristic` classifies windows as popups (ignored)
/// when `activationPolicy == .accessory && closeButton == nil`. Since this
/// app uses `LSUIElement=true` (accessory policy) and the panel has no
/// window buttons (no `.closable`/`.miniaturizable`), AeroSpace skips it
/// entirely -- no config rules needed.
final class QuickAccessPanel: NSPanel {

    private static let panelWidth: CGFloat = 680
    private static let panelHeight: CGFloat = 420

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.panelWidth,
                height: Self.panelHeight
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        configureAppearance()
    }

    // MARK: - Configuration

    private func configurePanel() {
        // Level 27 matches Alfred -- just above statusBar (25), high enough
        // to float over all normal/floating windows without being excessive.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        isFloatingPanel = true
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true

        // Hide the title bar but keep the window chrome for rounded corners
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Don't show in Mission Control, Exposé, or Cmd+Tab
        isExcludedFromWindowsMenu = true

        // Allow the panel to become key so search field can receive focus (M2)
        isMovableByWindowBackground = true
    }

    private func configureAppearance() {
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Visual effect background for translucent dark appearance
        let visualEffect = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow

        contentView?.addSubview(visualEffect, positioned: .below, relativeTo: nil)
    }

    // MARK: - Key Handling

    /// Allow the panel to become the key window for keyboard input.
    override var canBecomeKey: Bool { true }
}
