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
            return "person.fill"
        case "PASSWORD":
            return "key.fill"
        case "SECURE_NOTE":
            return "doc.text.fill"
        case "CREDIT_CARD":
            return "creditcard.fill"
        case "IDENTITY":
            return "person.text.rectangle.fill"
        case "API_CREDENTIAL":
            return "terminal.fill"
        case "SSH_KEY":
            return "lock.shield.fill"
        default:
            return "globe"
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
