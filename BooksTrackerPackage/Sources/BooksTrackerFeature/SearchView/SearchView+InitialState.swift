import SwiftUI
import SwiftData

// MARK: - Initial State View

@available(iOS 26.0, *)
extension SearchView {
    struct InitialStateView: View {
        let trending: [SearchResult]  // Keep for future use, but display as search chips
        let recentSearches: [String]
        @Bindable var searchModel: SearchModel
        @Environment(\.iOS26ThemeStore) private var themeStore
        @Namespace private var searchTransition

        let onBookSelected: (SearchResult) -> Void  // Keep for backward compatibility
        
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 32) {
                    // Welcome section - HIG: Clear, inviting empty state
                    welcomeSection

                    // Trending searches chips - HIG: Inspiration and quick discovery (Issue #16)
                    if !searchModel.popularSearches.isEmpty {
                        trendingSearchesSection
                    }

                    // Recent searches section - HIG: Quick access to previous searches
                    if !recentSearches.isEmpty {
                        recentSearchesSection
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity.combined(with: .scale(scale: 1.05))
            ))
        }
        
        private var welcomeSection: some View {
            // Flattened: removed nested VStack (was 2 levels, now 1)
            VStack(spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(themeStore.primaryColor)
                    .symbolEffect(.pulse, options: .repeating)

                Text("Discover Your Next Great Read")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Search millions of books or scan a barcode to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 32)
        }
        
        private var recentSearchesSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Recent Searches", systemImage: "clock")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    Button("Clear") {
                        searchModel.clearRecentSearches()
                    }
                    .font(.subheadline)
                    .foregroundColor(themeStore.primaryColor)
                }

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(recentSearches.prefix(6)), id: \.self) { search in
                        Button {
                            searchModel.searchText = search
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(search)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search for \(search)")
                    }
                }
            }
        }
        
        // HIG: Trending search queries as pill-shaped chips (Issue #16)
        private var trendingSearchesSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Trending Searches", systemImage: "flame.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .symbolRenderingMode(.multicolor)

                    Spacer()
                }

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(searchModel.popularSearches.prefix(8)), id: \.self) { query in
                        Button {
                            searchModel.searchText = query
                        } label: {
                            Text(query)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(themeStore.primaryColor.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search for \(query)")
                    }
                }
            }
        }
    }
}
