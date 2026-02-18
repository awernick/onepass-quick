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

    /// The copy actions available for this item's category.
    var categoryActions: CategoryActions {
        CategoryActions.actions(for: category)
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

/// A 1Password account as returned by `op account list --format json`.
///
/// Used to construct Private Link URLs for deep linking into the
/// 1Password desktop app (e.g. "Open in 1Password").
struct OPAccount: Codable {
    let url: String
    let accountUuid: String
}

// MARK: - Category Actions

/// Defines the copy actions available for a given item category.
///
/// Controls both the shortcut hint labels shown in the footer and
/// the CLI fields fetched when the user presses a copy shortcut.
/// Each category maps its three copy shortcuts (Cmd+C, Cmd+Shift+C,
/// Cmd+Option+C) to category-appropriate fields.
struct CategoryActions {

    /// Action bound to Cmd+C.
    let primary: Action?
    /// Action bound to Cmd+Shift+C.
    let secret: Action?
    /// Action bound to Cmd+Option+C.
    let tertiary: Action?

    /// A single copy action with its display label and data source.
    struct Action {
        /// Label shown in the shortcut hints bar (e.g. "Username", "Card Number").
        let label: String
        /// How to retrieve the value from the op CLI.
        let source: Source
        /// Whether the value is sensitive (uses concealed pasteboard type).
        let concealed: Bool
    }

    /// How a field value is retrieved.
    enum Source {
        /// Use `item.additionalInformation` directly (no CLI call, no Touch ID).
        case additionalInfo
        /// Fetch via `op item get <id> --fields <fieldID> --format json`.
        case field(String)
        /// Fetch via `op item get <id> --otp`.
        case otp
    }

    /// Returns the actions for a given 1Password item category.
    static func actions(for category: String) -> CategoryActions {
        switch category {
        case "LOGIN":
            return CategoryActions(
                primary: Action(
                    label: "Username",
                    source: .additionalInfo,
                    concealed: false
                ),
                secret: Action(
                    label: "Password",
                    source: .field("password"),
                    concealed: true
                ),
                tertiary: Action(
                    label: "OTP",
                    source: .otp,
                    concealed: true
                )
            )

        case "CREDIT_CARD":
            return CategoryActions(
                primary: Action(
                    label: "Card Number",
                    source: .field("ccnum"),
                    concealed: true
                ),
                secret: Action(
                    label: "CVV",
                    source: .field("cvv"),
                    concealed: true
                ),
                tertiary: Action(
                    label: "Expiry",
                    source: .field("expiry"),
                    concealed: false
                )
            )

        case "API_CREDENTIAL":
            return CategoryActions(
                primary: Action(
                    label: "Username",
                    source: .field("username"),
                    concealed: false
                ),
                secret: Action(
                    label: "Credential",
                    source: .field("credential"),
                    concealed: true
                ),
                tertiary: nil
            )

        case "SSH_KEY":
            return CategoryActions(
                primary: Action(
                    label: "Public Key",
                    source: .field("public_key"),
                    concealed: false
                ),
                secret: Action(
                    label: "Fingerprint",
                    source: .field("fingerprint"),
                    concealed: false
                ),
                tertiary: nil
            )

        case "SERVER":
            return CategoryActions(
                primary: Action(
                    label: "Username",
                    source: .additionalInfo,
                    concealed: false
                ),
                secret: Action(
                    label: "Password",
                    source: .field("password"),
                    concealed: true
                ),
                tertiary: nil
            )

        case "SOFTWARE_LICENSE":
            return CategoryActions(
                primary: Action(
                    label: "License Key",
                    source: .field("reg_code"),
                    concealed: true
                ),
                secret: nil,
                tertiary: nil
            )

        case "PASSWORD":
            return CategoryActions(
                primary: Action(
                    label: "Password",
                    source: .field("password"),
                    concealed: true
                ),
                secret: nil,
                tertiary: nil
            )

        case "IDENTITY":
            return CategoryActions(
                primary: Action(
                    label: "Name",
                    source: .additionalInfo,
                    concealed: false
                ),
                secret: Action(
                    label: "Email",
                    source: .field("email"),
                    concealed: false
                ),
                tertiary: nil
            )

        case "BANK_ACCOUNT":
            return CategoryActions(
                primary: Action(
                    label: "Account #",
                    source: .field("accountNo"),
                    concealed: true
                ),
                secret: Action(
                    label: "Routing #",
                    source: .field("routingNo"),
                    concealed: true
                ),
                tertiary: Action(
                    label: "PIN",
                    source: .field("pin"),
                    concealed: true
                )
            )

        case "MEMBERSHIP":
            return CategoryActions(
                primary: Action(
                    label: "Member #",
                    source: .field("membership_no"),
                    concealed: false
                ),
                secret: Action(
                    label: "PIN",
                    source: .field("pin"),
                    concealed: true
                ),
                tertiary: nil
            )

        default:
            // Fallback for SECURE_NOTE, DOCUMENT, and other categories.
            return CategoryActions(
                primary: Action(
                    label: "Username",
                    source: .additionalInfo,
                    concealed: false
                ),
                secret: Action(
                    label: "Password",
                    source: .field("password"),
                    concealed: true
                ),
                tertiary: nil
            )
        }
    }
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
