import SwiftUI

/// A single row in the search results list.
struct ItemRow: View {

    let item: Item
    let isSelected: Bool

    /// Character indices in the title matched by the fuzzy query.
    /// Empty when no query is active or the match was on another field.
    var titlePositions: [Int] = []

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
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(.blue)
                : nil
        )
        .contentShape(Rectangle())
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
