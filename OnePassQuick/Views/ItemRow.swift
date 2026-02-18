import SwiftUI

/// A single row in the search results list.
struct ItemRow: View {

    let item: Item
    let isSelected: Bool

    /// Character indices in the title matched by the fuzzy query.
    /// Empty when no query is active or the match was on another field.
    var titlePositions: [Int] = []

    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.categoryIcon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                highlightedTitle
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            isSelected ? .white.opacity(0.7) : .secondary
                        )
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.vault.name)
                .font(.system(size: 10))
                .foregroundStyle(
                    isSelected ? .white.opacity(0.5) : .secondary.opacity(0.6)
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                selectionBackground
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Selection Style

    /// Background view for the selected row, driven by user preference.
    @ViewBuilder
    private var selectionBackground: some View {
        switch preferences.selectionStyle {
        case .blue:
            Rectangle().fill(.blue.opacity(0.35))
        case .white:
            Rectangle().fill(.white.opacity(0.15))
        case .bordered:
            Rectangle()
                .fill(.white.opacity(0.1))
                .overlay(
                    Rectangle()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Highlighted Title

    /// Build a `Text` view with matched characters visually distinct.
    /// Unmatched characters are dimmed to draw attention to the match.
    private var highlightedTitle: Text {
        guard !titlePositions.isEmpty else {
            return Text(item.title)
                .foregroundColor(isSelected ? .white : .primary)
        }

        let positionSet = Set(titlePositions)
        let matchColor: Color = isSelected ? .white : .primary
        let dimColor: Color = isSelected
            ? .white.opacity(0.5) : .secondary

        var result = Text("")
        for (i, char) in item.title.enumerated() {
            let fragment = Text(String(char))
            if positionSet.contains(i) {
                result = result + fragment.foregroundColor(matchColor)
            } else {
                result = result + fragment.foregroundColor(dimColor)
            }
        }
        return result
    }

    /// Secondary text: username (additionalInformation) or primary URL.
    private var subtitle: String? {
        if let info = item.additionalInformation, !info.isEmpty {
            return info
        }
        return item.primaryURL
    }
}

// MARK: - Preview

#Preview("Login Item - Selected") {
    ItemRow(
        item: Item(
            id: "abc123",
            title: "GitHub",
            category: "LOGIN",
            vault: Vault(id: "v1", name: "Personal"),
            additionalInformation: "user@example.com",
            urls: [ItemURL(primary: true, href: "https://github.com")]
        ),
        isSelected: true,
        titlePositions: [0, 3]
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("Login Item - Normal") {
    ItemRow(
        item: Item(
            id: "abc123",
            title: "GitHub",
            category: "LOGIN",
            vault: Vault(id: "v1", name: "Personal"),
            additionalInformation: "user@example.com",
            urls: [ItemURL(primary: true, href: "https://github.com")]
        ),
        isSelected: false,
        titlePositions: [0, 3]
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("Secure Note") {
    ItemRow(
        item: Item(
            id: "def456",
            title: "Recovery Codes",
            category: "SECURE_NOTE",
            vault: Vault(id: "v2", name: "Work"),
            additionalInformation: nil,
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("API Credential") {
    ItemRow(
        item: Item(
            id: "api001",
            title: "Stripe API Key",
            category: "API_CREDENTIAL",
            vault: Vault(id: "v2", name: "Work"),
            additionalInformation: "sk_live_*****",
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("SSH Key") {
    ItemRow(
        item: Item(
            id: "ssh001",
            title: "deploy@prod-server",
            category: "SSH_KEY",
            vault: Vault(id: "v2", name: "Work"),
            additionalInformation: nil,
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("Server") {
    ItemRow(
        item: Item(
            id: "srv001",
            title: "Production Database",
            category: "SERVER",
            vault: Vault(id: "v2", name: "Work"),
            additionalInformation: "db.example.com",
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("Credit Card") {
    ItemRow(
        item: Item(
            id: "cc001",
            title: "Chase Sapphire",
            category: "CREDIT_CARD",
            vault: Vault(id: "v1", name: "Personal"),
            additionalInformation: nil,
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}

#Preview("Software License") {
    ItemRow(
        item: Item(
            id: "sw001",
            title: "JetBrains All Products",
            category: "SOFTWARE_LICENSE",
            vault: Vault(id: "v2", name: "Work"),
            additionalInformation: nil,
            urls: nil
        ),
        isSelected: false
    )
    .frame(width: 640)
    .background(.black.opacity(0.8))
}
