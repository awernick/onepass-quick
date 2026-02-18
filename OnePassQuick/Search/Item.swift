import Foundation

/// A 1Password item as returned by `op item list --format json`.
///
/// Only includes fields from the list response. Full item details
/// (username, password) require a separate `op item get` call (M3).
struct Item: Codable, Identifiable, Hashable {

    let id: String
    let title: String
    let category: String
    let vault: Vault
    let additionalInformation: String?
    let urls: [ItemURL]?

    /// The primary URL associated with this item, if any.
    var primaryURL: String? {
        urls?.first(where: { $0.primary == true })?.href ?? urls?.first?.href
    }

    /// SF Symbol name for this item's category.
    var categoryIcon: String {
        switch category {
        case "LOGIN":
            return "person.crop.circle.fill"
        case "PASSWORD":
            return "key.fill"
        case "SECURE_NOTE":
            return "note.text"
        case "CREDIT_CARD":
            return "creditcard.fill"
        case "IDENTITY":
            return "person.text.rectangle.fill"
        case "API_CREDENTIAL":
            return "terminal.fill"
        case "SSH_KEY":
            return "key.horizontal.fill"
        case "BANK_ACCOUNT":
            return "building.columns.fill"
        case "DATABASE":
            return "cylinder.fill"
        case "DOCUMENT":
            return "doc.fill"
        case "DRIVER_LICENSE":
            return "car.fill"
        case "EMAIL_ACCOUNT":
            return "envelope.fill"
        case "MEMBERSHIP":
            return "person.crop.rectangle.fill"
        case "OUTDOOR_LICENSE":
            return "leaf.fill"
        case "PASSPORT":
            return "airplane"
        case "REWARD_PROGRAM":
            return "star.fill"
        case "SERVER":
            return "server.rack"
        case "SOCIAL_SECURITY_NUMBER":
            return "shield.fill"
        case "SOFTWARE_LICENSE":
            return "app.badge.checkmark"
        case "WIRELESS_ROUTER":
            return "wifi"
        default:
            return "ellipsis.circle.fill"
        }
    }
}

/// Vault reference within an item.
struct Vault: Codable, Hashable {
    let id: String
    let name: String
}

/// URL entry within an item.
struct ItemURL: Codable, Hashable {
    let primary: Bool?
    let href: String
}

/// A single field from `op item get --fields ... --format json`.
///
/// Used to decode credential values fetched on-demand. The CLI returns
/// an object per field with at least these properties.
struct ItemField: Codable {
    let id: String
    let label: String
    let value: String
    let type: String
}
