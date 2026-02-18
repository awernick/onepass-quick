import SwiftUI

/// Main search interface embedded in the quick access panel.
///
/// Displays a search field at the top and a scrollable list of results below.
/// All state is managed by `SearchViewModel` (owned by `PanelController`).
struct SearchView: View {

    @ObservedObject var viewModel: SearchViewModel

    /// Toggled by PanelController to trigger search field focus.
    @Binding var focusTrigger: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchFieldSection
            Divider()
                .background(.white.opacity(0.1))
            resultsSection
            Divider()
                .background(.white.opacity(0.1))
            ShortcutHintsBar()
        }
    }

    // MARK: - Search Field

    private var searchFieldSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            SearchField(
                text: $viewModel.query,
                focusTrigger: $focusTrigger
            )
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.isLoading {
            loadingView
        } else if let error = viewModel.error {
            errorView(error)
        } else if viewModel.filteredResults.isEmpty {
            emptyView
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(viewModel.filteredResults.enumerated()),
                        id: \.element.item.id
                    ) { index, result in
                        ItemRow(
                            item: result.item,
                            isSelected: index == viewModel.selectedIndex,
                            titlePositions: result.titlePositions
                        )
                        .id(result.item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                let results = viewModel.filteredResults
                guard newIndex >= 0, newIndex < results.count
                else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(results[newIndex].item.id, anchor: .center)
                }
            }
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading items...")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: OPClientError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: errorIcon(for: error))
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(error.localizedDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Distinct message depending on whether the user has typed a query.
    private var emptyMessage: String {
        if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No items found"
        }
        return "No matching items"
    }

    private func errorIcon(for error: OPClientError) -> String {
        switch error {
        case .cliNotFound:
            return "terminal.fill"
        case .notAuthenticated:
            return "lock.fill"
        case .executionFailed:
            return "exclamationmark.triangle.fill"
        case .decodingFailed:
            return "doc.questionmark.fill"
        case .fieldNotFound:
            return "questionmark.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview("With Results") {
    let vm = SearchViewModel()
    SearchView(viewModel: vm, focusTrigger: .constant(false))
        .frame(width: 680, height: 420)
        .background(.black.opacity(0.8))
}
