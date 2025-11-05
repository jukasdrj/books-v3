import SwiftUI
import SwiftData

/// Root view orchestrating BooksTracker's 4-tab navigation layout.
///
/// **Architecture (Refactored November 2, 2025):**
/// - 4-tab layout: Library, Search, Shelf, Insights
/// - Extracted components: `EnrichmentBanner`, `SampleDataGenerator`, `NotificationCoordinator`
/// - Type-safe notifications via `NotificationPayloads` (eliminates magic strings)
/// - Environment-injected `DTOMapper` (no ProgressView flash on launch)
///
/// **Line Reduction:** 448 → 165 lines (63% reduction, 283 lines extracted)
///
/// **Responsibilities:**
/// - Tab navigation orchestration
/// - Enrichment progress state management (banner display)
/// - Notification handling delegation (via NotificationCoordinator)
/// - Theme and environment injection
///
/// **Related Components:**
/// - `UI/EnrichmentBanner.swift` - Progress banner UI (92 lines)
/// - `Services/SampleDataGenerator.swift` - Sample data logic (126 lines)
/// - `Services/NotificationCoordinator.swift` - Type-safe notification handling (80 lines)
/// - `Models/NotificationPayloads.swift` - Structured notification contracts (60 lines)
public struct ContentView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dtoMapper) private var dtoMapper
    @State private var selectedTab: MainTab = .library
    @State private var searchCoordinator = SearchCoordinator()
    @State private var notificationCoordinator = NotificationCoordinator()

    // Enrichment progress tracking (no Live Activity required!)
    @State private var isEnriching = false
    @State private var enrichmentProgress: (completed: Int, total: Int) = (0, 0)
    @State private var currentBookTitle = ""

    public var body: some View {
        // Verify DTOMapper dependency injection (should never fail in production)
        guard let dtoMapper = dtoMapper else {
            return AnyView(Text("Configuration Error: DTOMapper not injected")
                .foregroundColor(.red)
                .onAppear {
                    fatalError("DTOMapper must be injected via environment in BooksTrackerApp")
                })
        }

        if #available(iOS 26.0, *) {
            return AnyView(Group {
                TabView(selection: $selectedTab) {
                        // Library Tab
                        NavigationStack {
                            iOS26LiquidLibraryView()
                        }
                        .tabItem {
                            Label("Library", systemImage: selectedTab == .library ? "books.vertical.fill" : "books.vertical")
                        }
                        .tag(MainTab.library)

                        // Search Tab
                        NavigationStack {
                            SearchView()
                                .environment(searchCoordinator)
                        }
                        .tabItem {
                            Label("Search", systemImage: selectedTab == .search ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        }
                        .tag(MainTab.search)

                        // Shelf Tab
                        NavigationStack {
                            BookshelfScannerView()
                        }
                        .tabItem {
                            Label("Shelf", systemImage: selectedTab == .shelf ? "viewfinder.circle.fill" : "viewfinder")
                        }
                        .tag(MainTab.shelf)

                        // Insights Tab
                        NavigationStack {
                            InsightsView()
                        }
                        .tabItem {
                            Label("Insights", systemImage: selectedTab == .insights ? "chart.bar.fill" : "chart.bar")
                        }
                        .tag(MainTab.insights)
                }
                .environment(\.dtoMapper, dtoMapper)  // Safely unwrapped above
                .tint(themeStore.primaryColor)
                #if os(iOS)
                .tabBarMinimizeBehavior(
                    voiceOverEnabled || reduceMotion ? .never : (featureFlags.enableTabBarMinimize ? .onScrollDown : .never)
                )
                #endif
            })
            .themedBackground()
            .onAppear {
                LaunchMetrics.shared.recordMilestone("UI fully interactive")

                // Print full launch report after a short delay (let everything settle)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    LaunchMetrics.shared.printReport()
                }
            }
            .task {
                // Defer non-critical background tasks until app is interactive
                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("EnrichmentQueue validation start")
                    EnrichmentQueue.shared.validateQueue(in: modelContext)
                    LaunchMetrics.shared.recordMilestone("EnrichmentQueue validation end")
                }

                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("ImageCleanup start")
                    await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
                    await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
                    LaunchMetrics.shared.recordMilestone("ImageCleanup end")
                }

                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("SampleData check start")
                    let generator = SampleDataGenerator(modelContext: modelContext)
                    generator.setupSampleDataIfNeeded()
                    LaunchMetrics.shared.recordMilestone("SampleData check end")
                }
                
                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("DTOMapper cache pruning start")
                    if let dtoMapper = dtoMapper {
                        await dtoMapper.pruneStaleCacheEntries()
                    }
                    LaunchMetrics.shared.recordMilestone("DTOMapper cache pruning end")
                }

                LaunchMetrics.shared.recordMilestone("Background tasks scheduled")
            }
            .task(priority: .userInitiated) {
                LaunchMetrics.shared.recordMilestone("NotificationCoordinator setup")
                await notificationCoordinator.handleNotifications(
                    onSwitchToLibrary: { selectedTab = .library },
                    onEnrichmentStarted: { payload in
                        isEnriching = true
                        enrichmentProgress = (0, payload.totalBooks)
                        currentBookTitle = ""
                    },
                    onEnrichmentProgress: { payload in
                        enrichmentProgress = (payload.completed, payload.total)
                        currentBookTitle = payload.currentTitle
                    },
                    onEnrichmentCompleted: { isEnriching = false },
                    onSearchForAuthor: { payload in
                        selectedTab = .search
                        searchCoordinator.setPendingAuthorSearch(payload.authorName)
                    }
                )
            }
            .overlay(alignment: .bottom) {
                if isEnriching {
                    EnrichmentBanner(
                        completed: enrichmentProgress.completed,
                        total: enrichmentProgress.total,
                        currentBookTitle: currentBookTitle,
                        themeStore: themeStore
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEnriching)
        } else {
            // Fallback on earlier versions
        }
    }

    public init() {}
}

// MARK: - Notification Names

extension Notification.Name {
    static let switchToLibraryTab = Notification.Name("SwitchToLibraryTab")
    static let enrichmentStarted = Notification.Name("EnrichmentStarted")
    static let enrichmentProgress = Notification.Name("EnrichmentProgress")
    static let enrichmentCompleted = Notification.Name("EnrichmentCompleted")
    static let libraryWasReset = Notification.Name("LibraryWasReset")
    static let searchForAuthor = Notification.Name("SearchForAuthor")
}

// MARK: - Tab Navigation

enum MainTab: String, CaseIterable {
    case library = "library"
    case search = "search"
    case shelf = "shelf"
    case insights = "insights"

    var displayName: String {
        switch self {
        case .library: return "Library"
        case .search: return "Search"
        case .shelf: return "Shelf"
        case .insights: return "Insights"
        }
    }
}

// MARK: - Placeholder Views

// SettingsView now implemented in SettingsView.swift
// InsightsView now implemented in Insights/InsightsView.swift

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    ContentView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
