import AppKit
import os.log

/// Handles user actions (copy, open URL, open in 1Password) for the
/// selected item. Extracted from `PanelController` to separate UI
/// lifecycle management from service/action logic.
///
/// Owns the async action lifecycle (in-flight tasks, toast display,
/// dismiss timing) and calls back to the panel via closures.
@MainActor
final class ActionHandler {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "ActionHandler"
    )

    /// The view model providing selected item, account info, and toast state.
    private let viewModel: SearchViewModel

    /// Called when the action wants to dismiss the panel (after toast delay).
    var onDismiss: @MainActor () -> Void

    /// Called when the action needs to prevent focus restoration
    /// (e.g., opening 1Password should keep focus on 1Password).
    var onClearPreviousApp: @MainActor () -> Void

    /// Guards against overlapping async actions (e.g., double Cmd+Shift+C
    /// while Touch ID is pending).
    private var isPerformingAction: Bool = false

    /// In-flight password fetch task. Stored so it can be cancelled when
    /// the panel hides (e.g., user presses Esc during Touch ID).
    private var actionTask: Task<Void, Never>?

    /// Pending hide after toast display. Cancelled if the user dismisses
    /// manually (Esc) before the delay expires.
    private var toastHideTask: Task<Void, Never>?

    /// Duration the toast is visible before the panel auto-hides.
    private static let toastDuration: UInt64 = 500_000_000  // 0.5s

    init(
        viewModel: SearchViewModel,
        onDismiss: @escaping @MainActor () -> Void,
        onClearPreviousApp: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onClearPreviousApp = onClearPreviousApp
    }

    // MARK: - Lifecycle

    /// Cancel any in-flight actions. Called when the panel hides.
    func cancelAll() {
        actionTask?.cancel()
        actionTask = nil
        isPerformingAction = false

        toastHideTask?.cancel()
        toastHideTask = nil
    }

    // MARK: - Actions

    /// Copy the primary field (Cmd+C) for the selected item.
    ///
    /// The actual field depends on the item's category (e.g. username
    /// for LOGIN, card number for CREDIT_CARD). See `CategoryActions`.
    func copyPrimary() {
        guard let item = viewModel.selectedItem else { return }
        guard let action = item.categoryActions.primary else { return }
        performAction(action, for: item)
    }

    /// Copy the secret field (Cmd+Shift+C) for the selected item.
    ///
    /// The actual field depends on the item's category (e.g. password
    /// for LOGIN, CVV for CREDIT_CARD). See `CategoryActions`.
    func copySecret() {
        guard let item = viewModel.selectedItem else { return }
        guard let action = item.categoryActions.secret else { return }
        performAction(action, for: item)
    }

    /// Copy the tertiary field (Cmd+Option+C) for the selected item.
    ///
    /// The actual field depends on the item's category (e.g. OTP
    /// for LOGIN, expiry for CREDIT_CARD). See `CategoryActions`.
    func copyTertiary() {
        guard let item = viewModel.selectedItem else { return }
        guard let action = item.categoryActions.tertiary else { return }
        performAction(action, for: item)
    }

    /// Execute a copy action, resolving the value from the appropriate source.
    private func performAction(
        _ action: CategoryActions.Action,
        for item: Item
    ) {
        switch action.source {
        case .additionalInfo:
            guard let value = item.additionalInformation,
                !value.isEmpty
            else {
                Self.log.info("No \(action.label) for item '\(item.title)'")
                return
            }
            ClipboardManager.copy(value, concealed: action.concealed)
            Self.log.info("Copied \(action.label) for '\(item.title)'")
            showToastThenDismiss("\(action.label) copied")

        case .field(let fieldID):
            fetchAndCopy(
                item: item,
                label: action.label,
                concealed: action.concealed
            ) {
                try await OPClient.getField(itemID: item.id, field: fieldID)
            }

        case .otp:
            fetchAndCopy(
                item: item,
                label: action.label,
                concealed: action.concealed
            ) {
                try await OPClient.getOTP(itemID: item.id)
            }
        }
    }

    /// Fetch a value asynchronously (triggers Touch ID) and copy to clipboard.
    ///
    /// Shows a "Fetching..." toast during the fetch and handles errors
    /// (field not found, auth cancelled, timeout) gracefully.
    private func fetchAndCopy(
        item: Item,
        label: String,
        concealed: Bool,
        fetch: @escaping () async throws -> String
    ) {
        guard !isPerformingAction else { return }

        viewModel.toastMessage = "Fetching \(label.lowercased())\u{2026}"
        viewModel.toastIcon = "ellipsis.circle"

        isPerformingAction = true
        actionTask = Task {
            defer { isPerformingAction = false }
            do {
                let value = try await fetch()
                guard !Task.isCancelled else { return }
                ClipboardManager.copy(value, concealed: concealed)
                Self.log.info("Copied \(label) for '\(item.title)'")
                showToastThenDismiss("\(label) copied")
            } catch OPClientError.fieldNotFound {
                Self.log.info("No \(label) for item '\(item.title)'")
                viewModel.toastMessage = nil
                viewModel.toastIcon = nil
            } catch OPClientError.notAuthenticated {
                Self.log.info("Auth cancelled for '\(item.title)'")
                viewModel.toastMessage = nil
                viewModel.toastIcon = nil
            } catch {
                guard !Task.isCancelled else { return }
                Self.log.error("Failed to fetch \(label): \(error)")
                viewModel.toastMessage = nil
                viewModel.toastIcon = nil
            }
        }
    }

    /// Open the selected item's primary URL in the default browser.
    ///
    /// Uses the cached URL from the item list -- no CLI call.
    func openURL() {
        guard let item = viewModel.selectedItem else { return }

        guard let urlString = item.primaryURL else {
            Self.log.info("No URL for item '\(item.title)'")
            return
        }

        // Ensure URL has a scheme -- op CLI may return bare hostnames
        let normalized = urlString.hasPrefix("http://")
            || urlString.hasPrefix("https://")
            ? urlString : "https://\(urlString)"

        guard let url = URL(string: normalized) else {
            Self.log.info("Invalid URL for item '\(item.title)'")
            return
        }

        NSWorkspace.shared.open(url)
        Self.log.info("Opened URL for '\(item.title)'")
        showToastThenDismiss("Opening URL\u{2026}", icon: "arrow.up.forward")
    }

    /// Open the selected item in the 1Password desktop app.
    ///
    /// Uses the native `onepassword://view-item/` URL scheme to deep
    /// link directly into the 1Password 8 desktop app. This bypasses
    /// the browser entirely (unlike `start.1password.com` Private Links).
    ///
    /// Falls back to just activating the 1Password app if account info
    /// is unavailable.
    func openInOnePassword() {
        guard let item = viewModel.selectedItem else { return }

        // Clear previousApp so hide() doesn't steal focus from 1Password
        // when it re-activates the previously focused app.
        onClearPreviousApp()

        if let account = viewModel.account {
            var components = URLComponents()
            components.scheme = "onepassword"
            components.host = "view-item"
            components.path = "/"
            components.queryItems = [
                URLQueryItem(name: "a", value: account.accountUuid),
                URLQueryItem(name: "v", value: item.vault.id),
                URLQueryItem(name: "i", value: item.id),
            ]

            if let url = components.url {
                NSWorkspace.shared.open(url)
                Self.log.info(
                    "Opened item \(item.id) in 1Password via onepassword:// scheme"
                )
            } else {
                Self.log.error("Failed to construct onepassword:// URL")
                openOnePasswordApp()
            }
        } else {
            Self.log.warning(
                "Account info unavailable, opening 1Password without deep link"
            )
            openOnePasswordApp()
        }

        showToastThenDismiss(
            "Opening 1Password\u{2026}",
            icon: "arrow.up.forward"
        )
    }

    // MARK: - Private Helpers

    /// Show a toast message in the panel, then dismiss after a short delay.
    ///
    /// The toast replaces the results area with an icon + message. If the
    /// user dismisses manually (Esc) before the delay, `cancelAll()` cancels
    /// the pending task.
    private func showToastThenDismiss(
        _ message: String,
        icon: String = "checkmark.circle.fill"
    ) {
        viewModel.toastMessage = message
        viewModel.toastIcon = icon

        toastHideTask?.cancel()
        toastHideTask = Task {
            try? await Task.sleep(nanoseconds: Self.toastDuration)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    /// Activate the 1Password app without navigating to a specific item.
    private func openOnePasswordApp() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.1password.1password"
        ) {
            NSWorkspace.shared.open(url)
            Self.log.info("Opened 1Password app (no deep link)")
        } else {
            Self.log.error("1Password app not found")
        }
    }
}
