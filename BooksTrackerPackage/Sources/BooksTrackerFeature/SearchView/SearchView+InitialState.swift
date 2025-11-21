import SwiftUI
import SwiftData

// MARK: - Initial State View

@available(iOS 26.0, *)
extension SearchView {
    struct InitialStateView: View {
        let trending: [SearchResult]
        let recentSearches: [String]
        @Bindable var searchModel: SearchModel
        @Environment(\.iOS26ThemeStore) private var themeStore
        @Namespace private var searchTransition
        
        let onBookSelected: (SearchResult) -> Void
        
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 32) {
                    // Welcome section - HIG: Clear, inviting empty state
                    welcomeSection
                    
                    // Recent searches section - HIG: Quick access to previous searches
                    if !recentSearches.isEmpty {
                        recentSearchesSection
                    }
                    
                    // Trending books grid - HIG: Contextual content discovery
                    if !trending.isEmpty {
                        trendingBooksSection
                    }
                    
                    // HIG: Helpful tips for first-time users
                    if recentSearches.isEmpty {
                        quickTipsSection
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
        
        private var trendingBooksSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Trending Books", systemImage: "flame.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .symbolRenderingMode(.multicolor)

                    Spacer()
                }

                iOS26FluidGridSystem<SearchResult, AnyView>.bookLibrary(
                    items: trending
                ) { book in
                    AnyView(
                        Button {
                            onBookSelected(book)
                        } label: {
                            iOS26FloatingBookCard(
                                work: book.work,
                                namespace: searchTransition,
                                uniqueID: book.id.uuidString
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Trending book: \(book.displayTitle) by \(book.displayAuthors)")
                    )
                }
            }
        }
        
        private var quickTipsSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Label("Quick Tips", systemImage: "lightbulb.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .symbolRenderingMode(.multicolor)

                VStack(spacing: 12) {
                    tipRow(
                        icon: "magnifyingglass",
                        title: "General Search",
                        description: "Find books by any keyword in title or author"
                    )

                    tipRow(
                        icon: "barcode.viewfinder",
                        title: "Barcode Scanning",
                        description: "Tap the barcode icon to instantly look up books"
                    )

                    tipRow(
                        icon: "line.3.horizontal.decrease",
                        title: "Search Scopes",
                        description: "Filter by title, author, or ISBN for precise results"
                    )
                }
            }
            .padding(.vertical, 8)
        }

        private func tipRow(icon: String, title: String, description: String) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(themeStore.primaryColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.75)) // ✅ WCAG AA: Better contrast for small text
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
