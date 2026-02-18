import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private var hotkeyManager: HotkeyManager?

    /// Whether the app is registered to start at login.
    private var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        panelController = PanelController()
        hotkeyManager = HotkeyManager { [weak self] in
            self?.panelController?.toggle()
        }
        // Wire up hotkey manager so PanelController can register
        // panel-visible shortcuts at the CGEvent tap level.
        if let manager = hotkeyManager {
            panelController?.setHotkeyManager(manager)
        }
        updateMenuBarStatus()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "key.fill",
                accessibilityDescription: "OnePass Quick"
            )
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = hotkeyStatus()
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
        case .requiresApproval:
            loginItem.state = .mixed
        default:
            loginItem.state = .off
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Appearance submenu
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for style in Preferences.SelectionStyle.allCases {
            let item = NSMenuItem(
                title: "\(style.label) Selection",
                action: #selector(changeSelectionStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = Preferences.shared.selectionStyle == style ? .on : .off
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit OnePass Quick", action: #selector(quit), keyEquivalent: "q")
        )

        self.statusItem?.menu = menu
    }

    /// Update the menu bar icon and tooltip to reflect hotkey status.
    private func updateMenuBarStatus() {
        let active = hotkeyManager?.isActive ?? false

        if let button = statusItem?.button {
            button.toolTip = active
                ? "OnePass Quick -- Cmd+\\ to toggle"
                : "OnePass Quick -- hotkey inactive (check Accessibility permission)"

            // Dim the icon if the hotkey isn't working
            button.appearsDisabled = !active
        }

        rebuildMenu()
    }

    private func hotkeyStatus() -> String {
        let active = hotkeyManager?.isActive ?? false
        return active
            ? "Hotkey: Cmd+\\ (active)"
            : "Hotkey: inactive -- grant Accessibility permission and restart"
    }

    @objc private func toggleLoginItem() {
        do {
            if isLoginItemEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // SMAppService can fail if the app is not in /Applications
            // or not properly signed. Log but don't crash.
            NSLog("Failed to toggle login item: \(error)")
        }
        rebuildMenu()
    }

    @objc private func changeSelectionStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = Preferences.SelectionStyle(rawValue: raw)
        else { return }
        Preferences.shared.selectionStyle = style
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
