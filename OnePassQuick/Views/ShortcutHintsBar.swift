import SwiftUI

/// A subtle bar at the bottom of the panel showing available keyboard
/// shortcuts. Labels update based on the selected item's category
/// (e.g. "Username" for LOGIN, "Card Number" for CREDIT_CARD).
struct ShortcutHintsBar: View {

    /// The category of the currently selected item, if any.
    /// When nil, shows default LOGIN labels.
    let category: String?

    private var actions: CategoryActions {
        CategoryActions.actions(for: category ?? "LOGIN")
    }

    var body: some View {
        HStack(spacing: 16) {
            hint("↩", "Open URL")
            if let primary = actions.primary {
                hint("⌘C", primary.label)
            }
            if let secret = actions.secret {
                hint("⌘⇧C", secret.label)
            }
            if let tertiary = actions.tertiary {
                hint("⌘⌥C", tertiary.label)
            }
            hint("⌘O", "1Password")
            Spacer()
            hint("esc", "Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - Preview

#Preview("Login") {
    ShortcutHintsBar(category: "LOGIN")
        .frame(width: 680)
        .background(.black.opacity(0.8))
}

#Preview("Credit Card") {
    ShortcutHintsBar(category: "CREDIT_CARD")
        .frame(width: 680)
        .background(.black.opacity(0.8))
}

#Preview("SSH Key") {
    ShortcutHintsBar(category: "SSH_KEY")
        .frame(width: 680)
        .background(.black.opacity(0.8))
}
