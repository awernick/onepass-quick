import Combine
import Foundation
import os.log

/// Centralizes all search UI state. Owned by `PanelController` and
/// passed to `SearchView` as `@ObservedObject`.
@MainActor
final class SearchViewModel: ObservableObject {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "SearchViewModel"
    )

    // MARK: - Published State

    /// The raw search query bound to the search field.
    @Published var query: String = ""

    /// Index of the currently highlighted result row.
    @Published var selectedIndex: Int = 0

    /// Whether items are being loaded from the CLI.
    @Published var isLoading: Bool = false

    /// Error from the most recent load attempt, if any.
    @Published var error: OPClientError?

    // MARK: - Private State

    /// Full item list from the last successful `op item list` call.
    @Published private var items: [Item] = []

    /// Whether items have been loaded at least once this session.
    private var hasLoaded: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Reset selection to top whenever the query changes
        $query
            .dropFirst()
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    /// Items filtered by the current query, sorted by relevance.
    /// Returns all items when query is empty.
    var filteredItems: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }

        let lowered = trimmed.lowercased()
        return items
            .compactMap { item -> (item: Item, rank: Int)? in
                let title = item.title.lowercased()
                if title.hasPrefix(lowered) {
                    return (item, 0)
                } else if title.contains(lowered) {
                    return (item, 1)
                } else if item.additionalInformation?.lowercased()
                    .contains(lowered) ?? false
                {
                    return (item, 2)
                } else if item.primaryURL?.lowercased()
                    .contains(lowered) ?? false
                {
                    return (item, 3)
                }
                return nil
            }
            .sorted { $0.rank < $1.rank }
            .map(\.item)
    }

    // MARK: - Actions

    /// Load items from the op CLI. Skips if already loaded unless `force` is true.
    func loadItems(force: Bool = false) {
        guard !isLoading else { return }
        guard force || !hasLoaded else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let fetchedItems = try await OPClient.listItems()
                items = fetchedItems
                hasLoaded = true
                Self.log.info("Loaded \(fetchedItems.count) items into cache")
            } catch let opError as OPClientError {
                error = opError
                Self.log.error("Failed to load items: \(opError.localizedDescription)")
            } catch {
                self.error = .executionFailed(error.localizedDescription)
                Self.log.error("Unexpected error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    /// Move selection up or down within the filtered results.
    ///
    /// - Parameter delta: Positive moves down, negative moves up.
    func moveSelection(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }

        let newIndex = selectedIndex + delta
        selectedIndex = max(0, min(newIndex, count - 1))
    }

    /// The currently selected item, if any.
    var selectedItem: Item? {
        let items = filteredItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    /// Reset state for the next panel show. Clears query and selection
    /// but preserves cached items.
    func resetState() {
        query = ""
        selectedIndex = 0
        error = nil
    }
}
