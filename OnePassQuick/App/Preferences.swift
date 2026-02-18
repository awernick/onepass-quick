import Foundation

/// Lightweight app preferences backed by UserDefaults.
///
/// Observable so SwiftUI views can react to changes. Each property
/// reads/writes through UserDefaults directly — no caching layer.
final class Preferences: ObservableObject {

    /// Shared singleton used across the app.
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Selection Style

    /// Visual style for the selected row highlight.
    enum SelectionStyle: String, CaseIterable {
        /// Semi-transparent blue fill.
        case blue
        /// Neutral white tint (Spotlight/Alfred style).
        case white
        /// White fill with a subtle white border.
        case bordered

        var label: String {
            switch self {
            case .blue: return "Blue"
            case .white: return "White"
            case .bordered: return "Bordered"
            }
        }
    }

    private static let selectionStyleKey = "selectionStyle"

    var selectionStyle: SelectionStyle {
        get {
            guard let raw = defaults.string(forKey: Self.selectionStyleKey),
                  let style = SelectionStyle(rawValue: raw)
            else { return .blue }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.selectionStyleKey)
            objectWillChange.send()
        }
    }
}
