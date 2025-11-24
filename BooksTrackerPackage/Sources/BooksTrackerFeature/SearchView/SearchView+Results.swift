import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Results State View

@available(iOS 26.0, *)
extension SearchView {
    struct ResultsStateView: View {
        let items: [SearchResult]
        let hasMorePages: Bool
        let cacheHitRate: Double
        @Bindable var searchModel: SearchModel
        let imagePrefetcher: ImagePrefetcher
        @Environment(\.iOS26ThemeStore) private var themeStore
        
        let onBookSelected: (SearchResult) -> Void
        let onBookTapped: (SearchResult, EditionComparisonData?) -> Void
        let onLoadMore: () -> Void
        
        @State private var showBackToTop = false
        @State private var scrollPosition = ScrollPosition()
        
        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Results header
                        resultsHeader
                        
                        // Results list with accessibility
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, result in
                            Button {
                                handleBookTap(result)
                            } label: {
                                iOS26LiquidListRow(
                                    work: result.work,
                                    displayStyle: .standard
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Book: \(result.displayTitle) by \(result.displayAuthors)")
                            .accessibilityHint("Tap to view book details")
                            // HIG: Custom VoiceOver actions for power users
                            .accessibilityAction(named: "Add to library") {
                                // Quick add action
                            }
                            .task {
                                prefetchImages(for: items, currentIndex: index)
                            }
                        }

                        // HIG: Pagination loading indicator
                        if hasMorePages {
                            loadMoreIndicator
                                .onAppear {
                                    onLoadMore()
                                }
                        }

                        Spacer(minLength: 20)
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition($scrollPosition)
                .modifier(iOS26ScrollEdgeEffectModifier(edges: [.top, .bottom]))
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    showBackToTop = newValue > 300
                }

                // HIG: Back to Top button for long lists
                if showBackToTop {
                    backToTopButton
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            // HIG: Memory pressure monitoring (Issue #437)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                imagePrefetcher.cancelPrefetching()
            }
        }
        
        private var resultsHeader: some View {
            HStack {
                Text("\(items.count) results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if cacheHitRate > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(themeStore.primaryColor)
                            .font(.caption)

                        Text("Cached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        
        // HIG: Clear loading indicator for pagination
        private var loadMoreIndicator: some View {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)

                Text("Loading more results...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }

        private var backToTopButton: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollPosition.scrollTo(edge: .top)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
            .accessibilityLabel("Scroll to top")
        }
        
        private func handleBookTap(_ result: SearchResult) {
            if result.isInLibrary {
                // Try edition comparison first
                if let ownedEntry = result.work.userLibraryEntries?.first,
                   let ownedEdition = ownedEntry.edition,
                   let searchEdition = result.primaryEdition {
                    let comparisonData = EditionComparisonData(
                        searchEdition: searchEdition,
                        ownedEdition: ownedEdition
                    )
                    onBookTapped(result, comparisonData)
                } else {
                    // ✅ Fallback: Navigate to existing library entry
                    // This handles edge cases where isInLibrary=true but edition data is missing
                    onBookSelected(result)
                    
                    #if DEBUG
                    // Log edge cases for debugging data integrity issues
                    if result.work.userLibraryEntries?.first == nil {
                        print("⚠️ SearchView: isInLibrary=true but userLibraryEntries is nil for '\(result.work.title)'")
                    } else if result.work.userLibraryEntries?.first?.edition == nil {
                        print("⚠️ SearchView: Library entry exists but edition is nil for '\(result.work.title)'")
                    } else if result.primaryEdition == nil {
                        print("⚠️ SearchView: isInLibrary=true but searchResult has no primaryEdition for '\(result.work.title)'")
                    }
                    #endif
                }
            } else {
                onBookSelected(result)
            }
        }
        
        /// Prefetches images for upcoming search results to improve scrolling performance.
        /// Now prefetches during normal scrolling, not just at the end of the list.
        private func prefetchImages(for items: [SearchResult], currentIndex: Int) {
            // Check for Low Power Mode (Issue #437)
            let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            let prefetchWindow = isLowPower ? 3 : 10

            // Prefetch upcoming items relative to current position
            // We want to prefetch regardless of where we are in the list,
            // unlike pagination triggering which only happens at the end.
            let startIndex = currentIndex + 1
            let endIndex = min(startIndex + prefetchWindow, items.count)

            guard startIndex < endIndex else { return }

            let urlsToPrefetch = items[startIndex..<endIndex].compactMap { CoverImageService.coverURL(for: $0.work) }

            if !urlsToPrefetch.isEmpty {
                imagePrefetcher.startPrefetching(urls: urlsToPrefetch)
            }
        }
    }
}