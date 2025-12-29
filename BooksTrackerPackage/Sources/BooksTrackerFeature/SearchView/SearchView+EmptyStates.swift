import SwiftUI

// MARK: - Empty State Views

@available(iOS 26.0, *)
extension SearchView {
    struct NoResultsView: View {
        let query: String
        let scope: SearchScope
        var onLaunchScanner: () -> Void
        @Environment(\.iOS26ThemeStore) private var themeStore
        @Bindable var searchModel: SearchModel

        var body: some View {
            SharedEmptyStateView(
                icon: iconForScope(scope),
                title: "No Results Found",
                description: noResultsMessage(for: scope, query: query),
                actions: [
                    EmptyStateAction(
                        title: "Clear Search",
                        subtitle: "Start a new search",
                        icon: "xmark.circle",
                        color: themeStore.primaryColor,
                        handler: {
                            searchModel.clearSearch()
                        }
                    ),
                    EmptyStateAction(
                        title: "Browse Trending Books",
                        subtitle: "Discover popular titles",
                        icon: "flame.fill",
                        color: .orange,
                        handler: {
                            searchModel.clearSearch()
                        }
                    ),
                    EmptyStateAction(
                        title: "Scan ISBN Barcode",
                        subtitle: "Use your camera to search",
                        icon: "barcode.viewfinder",
                        color: .purple,
                        handler: {
                            onLaunchScanner()
                        }
                    )
                ]
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Icon selection based on search scope
        private func iconForScope(_ scope: SearchScope) -> String {
            switch scope {
            case .all:
                return "magnifyingglass"
            case .title:
                return "book"
            case .author:
                return "person.fill"
            case .isbn:
                return "barcode"
            case .semantic:
                return "brain"
            }
        }

        // HIG: Contextual no results messages
        private func noResultsMessage(for scope: SearchScope, query: String) -> String {
            switch scope {
            case .all:
                return "Try different keywords or check your spelling"
            case .title:
                return "No books found with that title. Try searching all fields."
            case .author:
                return "No authors found with that name. Check spelling or try searching all fields."
            case .isbn:
                return "No book found with that ISBN. Verify the number or try scanning a barcode."
            case .semantic:
                return "No books matched your description. Try different keywords or be more specific."
            }
        }
    }

    struct ErrorStateView: View {
        let message: String
        let lastQuery: String?
        let lastScope: SearchScope?
        let recoverySuggestion: String?
        @Environment(\.iOS26ThemeStore) private var themeStore
        @Bindable var searchModel: SearchModel

        var body: some View {
            SharedEmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Search Error",
                description: buildErrorDescription(),
                actions: buildActions()
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        private func buildErrorDescription() -> String {
            if let suggestion = recoverySuggestion {
                return "\(message)\n\n\(suggestion)"
            }
            return message
        }

        private func buildActions() -> [EmptyStateAction] {
            var actions: [EmptyStateAction] = []

            // Retry action
            if let query = lastQuery, let scope = lastScope {
                actions.append(
                    EmptyStateAction(
                        title: "Retry Search",
                        subtitle: "Try searching again",
                        icon: "arrow.clockwise",
                        color: themeStore.primaryColor,
                        handler: {
                            searchModel.search(query: query, scope: scope)
                        }
                    )
                )
            } else {
                actions.append(
                    EmptyStateAction(
                        title: "Try Again",
                        subtitle: "Retry your last search",
                        icon: "arrow.clockwise",
                        color: themeStore.primaryColor,
                        handler: {
                            searchModel.retryLastSearch()
                        }
                    )
                )
            }

            // Clear search action
            actions.append(
                EmptyStateAction(
                    title: "Clear Search",
                    subtitle: "Start fresh",
                    icon: "xmark.circle",
                    color: .secondary,
                    handler: {
                        searchModel.clearSearch()
                    }
                )
            )

            // View recent searches
            actions.append(
                EmptyStateAction(
                    title: "View Recent Searches",
                    subtitle: "Browse your search history",
                    icon: "clock.arrow.circlepath",
                    color: .blue,
                    handler: {
                        // TODO: Navigate to recent searches
                    }
                )
            )

            return actions
        }
    }
}
