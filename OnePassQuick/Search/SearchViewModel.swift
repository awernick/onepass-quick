import Combine
import Foundation
import os.log

/// A filtered item paired with its fuzzy match positions in the title.
struct SearchResult {
    let item: Item

    /// Character indices in the title where query characters matched.
    /// Empty when the query is empty or the match was on a non-title field.
    let titlePositions: [Int]
}

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

    /// Items filtered and scored by the current query. Recalculated
    /// once when `query` or `items` change, not on every access.
    @Published private(set) var filteredResults: [SearchResult] = []

    // MARK: - Private State

    /// Full item list from the last successful `op item list` call.
    @Published private var items: [Item] = []

    /// Whether items have been loaded at least once this session.
    private var hasLoaded: Bool = false

    /// When items were last successfully loaded. Used to decide whether
    /// to background-refresh on panel show.
    private var lastLoadTime: Date?

    /// Whether a background refresh is in progress. Prevents overlapping
    /// CLI calls when the panel is shown repeatedly while stale.
    private var isRefreshing: Bool = false

    /// How long before cached items are considered stale.
    private static let cacheMaxAge: TimeInterval = 5 * 60  // 5 minutes

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Recalculate filtered results when query or items change,
        // and reset selection to top.
        Publishers.CombineLatest($query, $items)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.selectedIndex = 0
                self.filteredResults = self.computeFilteredResults()
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    /// Field-priority bonuses added to fuzzy scores so that title
    /// matches always rank above username matches, which rank above
    /// URL matches. The bonus values are large enough to dominate
    /// any realistic fuzzy score.
    private static let titleBonus: Double = 1000.0
    private static let usernameBonus: Double = 500.0
    private static let urlBonus: Double = 0.0

    /// Compute filtered results from the current query and items.
    /// Called once per query/items change via Combine, not per access.
    private func computeFilteredResults() -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return items.map { SearchResult(item: $0, titlePositions: []) }
        }

        return items
            .compactMap { item -> (result: SearchResult, score: Double)? in
                // Title match (highest priority)
                if let m = FuzzyMatcher.match(
                    query: trimmed, candidate: item.title
                ) {
                    let result = SearchResult(
                        item: item, titlePositions: m.positions
                    )
                    return (result, Self.titleBonus + m.score)
                }
                // Username / additional info match
                if let info = item.additionalInformation,
                    let m = FuzzyMatcher.match(
                        query: trimmed, candidate: info
                    )
                {
                    let result = SearchResult(
                        item: item, titlePositions: []
                    )
                    return (result, Self.usernameBonus + m.score)
                }
                // URL match
                if let url = item.primaryURL,
                    let m = FuzzyMatcher.match(
                        query: trimmed, candidate: url
                    )
                {
                    let result = SearchResult(
                        item: item, titlePositions: []
                    )
                    return (result, Self.urlBonus + m.score)
                }
                return nil
            }
            .sorted { $0.score > $1.score }
            .map(\.result)
    }

    // MARK: - Actions

    /// Load items from the op CLI.
    ///
    /// On first call, shows a loading indicator and fetches items. On
    /// subsequent calls, returns cached items immediately but triggers a
    /// background refresh if the cache is stale (> 5 minutes).
    func loadItems(force: Bool = false) {
        guard !isLoading else { return }

        let isStale = isCacheStale()

        // First load: show loading indicator
        if !hasLoaded || force {
            isLoading = true
            error = nil
            Task { await fetchItems() }
            return
        }

        // Background refresh: fetch silently without loading indicator
        if isStale, !isRefreshing {
            isRefreshing = true
            Self.log.info("Cache stale, refreshing in background")
            Task {
                await fetchItems()
                isRefreshing = false
            }
        }
    }

    /// Whether the cached items are older than `cacheMaxAge`.
    private func isCacheStale() -> Bool {
        guard let lastLoad = lastLoadTime else { return true }
        return Date().timeIntervalSince(lastLoad) > Self.cacheMaxAge
    }

    /// Fetch items from the CLI and update state.
    private func fetchItems() async {
        do {
            let fetchedItems = try await OPClient.listItems()
            items = fetchedItems
            hasLoaded = true
            lastLoadTime = Date()
            Self.log.info("Loaded \(fetchedItems.count) items into cache")
        } catch let opError as OPClientError {
            // Only surface errors on initial load, not background refresh
            if !hasLoaded { error = opError }
            Self.log.error(
                "Failed to load items: \(opError.localizedDescription)"
            )
        } catch {
            if !hasLoaded {
                self.error = .executionFailed(error.localizedDescription)
            }
            Self.log.error("Unexpected error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    /// Move selection up or down within the filtered results.
    ///
    /// - Parameter delta: Positive moves down, negative moves up.
    func moveSelection(by delta: Int) {
        let count = filteredResults.count
        guard count > 0 else { return }

        let newIndex = selectedIndex + delta
        selectedIndex = max(0, min(newIndex, count - 1))
    }

    /// The currently selected item, if any.
    var selectedItem: Item? {
        let results = filteredResults
        guard selectedIndex >= 0, selectedIndex < results.count else {
            return nil
        }
        return results[selectedIndex].item
    }

    /// Reset state for the next panel show. Clears query and selection
    /// but preserves cached items.
    func resetState() {
        query = ""
        selectedIndex = 0
        error = nil
    }
}
