import SwiftUI

/// A subtle bar at the bottom of the panel showing available keyboard
/// shortcuts. Provides discoverability without cluttering the UI.
struct ShortcutHintsBar: View {

    var body: some View {
        HStack(spacing: 16) {
            hint("↩", "Open URL")
            hint("⌘C", "Username")
            hint("⌘⇧C", "Password")
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

#Preview {
    ShortcutHintsBar()
        .frame(width: 680)
        .background(.black.opacity(0.8))
}
