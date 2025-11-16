import SwiftUI

// MARK: - Empty State Views

@available(iOS 26.0, *)
extension SearchView {
    struct NoResultsView: View {
        let query: String
        let scope: SearchScope
        @Environment(\.iOS26ThemeStore) private var themeStore
        @Bindable var searchModel: SearchModel
        
        var body: some View {
            VStack(spacing: 24) {
                Spacer()

                ContentUnavailableView {
                    Label("No Results Found", systemImage: "magnifyingglass")
                } description: {
                    Text(noResultsMessage(for: scope, query: query))
                } actions: {
                    VStack(spacing: 12) {
                        Button("Clear Search") {
                            searchModel.clearSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(themeStore.primaryColor)
                    }
                }

                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
            VStack(spacing: 24) {
                Spacer()

                ContentUnavailableView {
                    Label("Search Error", systemImage: "exclamationmark.triangle")
                } description: {
                    VStack(spacing: 8) {
                        Text(message)

                        if let suggestion = recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                } actions: {
                    VStack(spacing: 12) {
                        if let query = lastQuery, let scope = lastScope {
                            Button("Retry Search") {
                                searchModel.search(query: query, scope: scope)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeStore.primaryColor)
                        } else {
                            Button("Try Again") {
                                searchModel.retryLastSearch()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeStore.primaryColor)
                        }

                        Button("Clear Search") {
                            searchModel.clearSearch()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
