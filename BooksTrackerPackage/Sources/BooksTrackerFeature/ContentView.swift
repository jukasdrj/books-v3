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
    @Environment(EnrichmentQueue.self) private var enrichmentQueue
    @State private var selectedTab: MainTab = .library
    @State private var searchCoordinator = SearchCoordinator()
    @State private var tabCoordinator = TabCoordinator()
    @State private var notificationCoordinator = NotificationCoordinator()
    @State private var libraryRepository: LibraryRepository?
    
    // Review queue count (computed from LibraryRepository)
    private var reviewQueueCount: Int {
        guard let libraryRepository = libraryRepository else { return 0 }
        return (try? libraryRepository.reviewQueueCount()) ?? 0
    }


    // Enrichment progress tracking (no Live Activity required!)
    @State private var isEnriching = false
    @State private var enrichmentProgress: (completed: Int, total: Int) = (0, 0)
    @State private var currentBookTitle = ""

    // Toast notifications
    @State private var showingCompletionToast = false
    @State private var latestCompletionEvent: EnrichmentQueue.EnrichmentCompletionEvent?
    @State private var showingErrorToast = false
    @State private var latestErrorMessage = ""

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
                                .environment(tabCoordinator)
                        }
                        .tabItem {
                            Label("Library", systemImage: selectedTab == .library ? "books.vertical.fill" : "books.vertical")
                        }
                        .tag(MainTab.library)

                        // Search Tab
                        NavigationStack {
                            SearchView()
                                .environment(searchCoordinator)
                                .environment(tabCoordinator)
                        }
                        .tabItem {
                            Label("Search", systemImage: selectedTab == .search ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        }
                        .tag(MainTab.search)

                        // Shelf Tab
                        NavigationStack {
                            CombinedImportView()
                                 .environment(tabCoordinator)
                        }
                        .tabItem {
                            Label("Scan & Import", systemImage: selectedTab == .shelf ? "barcode.viewfinder" : "barcode.viewfinder")
                        }
                         .badge(min(reviewQueueCount, 100))
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
                .environment(libraryRepository)
                .tint(themeStore.primaryColor)
                #if os(iOS)
                .tabBarMinimizeBehavior(
                    voiceOverEnabled || reduceMotion ? .never : (featureFlags.enableTabBarMinimize ? .onScrollDown : .never)
                )
                #endif
                // Sync tab coordinator with actual selected tab
                .onChange(of: tabCoordinator.selectedTab) { _, newValue in
                    selectedTab = newValue
                }
            })
            .themedBackground()
            .onAppear {
                if libraryRepository == nil {
                    libraryRepository = LibraryRepository(modelContext: modelContext, dtoMapper: dtoMapper, featureFlags: featureFlags)
                }
                // @Query provides reactive updates - no manual monitoring needed
                LaunchMetrics.shared.recordMilestone("UI fully interactive")

                // Print full launch report after a short delay (let everything settle)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    LaunchMetrics.shared.printReport()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                // Issue #431: Clear all caches on memory pressure to prevent crashes on memory-constrained devices
                URLCache.shared.removeAllCachedResponses()
                ImageCacheManager.shared.clearCache()
                #if DEBUG
                print("🧹 [Memory Pressure] Cleared URLCache and ImageCacheManager due to memory warning")
                #endif
            }
            .task {
                // Defer non-critical background tasks until app is interactive
                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("EnrichmentQueue validation start")
                    EnrichmentQueue.shared.validateQueue(in: modelContext)
                    LaunchMetrics.shared.recordMilestone("EnrichmentQueue validation end")
                }

                // Fetch API capabilities on app launch (P1 - Feature flags)
                BackgroundTaskScheduler.shared.schedule(priority: .high) {
                    LaunchMetrics.shared.recordMilestone("API Capabilities fetch start")
                    let capabilitiesService = CapabilitiesService()
                    let capabilities = await capabilitiesService.fetchCapabilities()
                    
                    // Update FeatureFlags with capabilities
                    await MainActor.run {
                        featureFlags.updateCapabilities(capabilities)
                    }
                    
                    LaunchMetrics.shared.recordMilestone("API Capabilities fetch end")
                    
                    #if DEBUG
                    print("📊 API Capabilities loaded: v\(capabilities.version)")
                    print("   - Semantic Search: \(capabilities.features.semanticSearch ? "✅" : "❌")")
                    print("   - Similar Books: \(capabilities.features.similarBooks ? "✅" : "❌")")
                    print("   - CSV Import: \(capabilities.features.csvImport ? "✅" : "❌")")
                    print("   - CSV Max Rows: \(capabilities.limits.csvMaxRows)")
                    #endif
                }

                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("ImageCleanup start")
                    await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
                    await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
                    LaunchMetrics.shared.recordMilestone("ImageCleanup end")
                }

                #if DEBUG
                // Sample data only in debug builds (Issue #385)
                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("SampleData check start")
                    let generator = SampleDataGenerator(modelContext: modelContext)
                    generator.setupSampleDataIfNeeded()
                    LaunchMetrics.shared.recordMilestone("SampleData check end")
                }
                #endif
                
                BackgroundTaskScheduler.shared.schedule(priority: .low) {
                    LaunchMetrics.shared.recordMilestone("DTOMapper cache pruning start")
                    await MainActor.run {
                        dtoMapper.pruneStaleCacheEntries()
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
                    onEnrichmentFailed: { payload in
                        isEnriching = false
                        latestErrorMessage = sanitizedErrorMessage(from: payload.errorMessage)
                        withAnimation {
                            showingErrorToast = true
                        }
                        #if DEBUG
                        print("❌ Enrichment failed: \(payload.errorMessage)")
                        #endif
                    },
                    onSearchForAuthor: { payload in
                        selectedTab = .search
                        searchCoordinator.setPendingAuthorSearch(payload.authorName)
                    },
                    onLibraryWasReset: {
                        isEnriching = false
                        enrichmentProgress = (0, 0)
                        currentBookTitle = ""
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
            .overlay(alignment: .top) {
                VStack {
                    if showingErrorToast {
                        EnrichmentErrorToast(
                            errorMessage: latestErrorMessage,
                            isPresented: $showingErrorToast
                        ) {
                            // Retry enrichment if user taps
                            // Note: Could implement retry logic here in a future enhancement
                        }
                        .padding(.top, 8)
                    }
                    
                    if showingCompletionToast, let event = latestCompletionEvent {
                        EnrichmentCompletionToast(
                            event: event,
                            isPresented: $showingCompletionToast
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .onReceive(enrichmentQueue.completionEvents) { event in
                latestCompletionEvent = event
                withAnimation {
                    showingCompletionToast = true
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }

    public init() {}
    
    // MARK: - Error Message Sanitization
    
    /// Sanitizes backend error messages for user-friendly display
    /// Maps known error patterns to actionable messages, prevents internal details from leaking
    private func sanitizedErrorMessage(from rawMessage: String) -> String {
        let lowercased = rawMessage.lowercased()
        
        // Timeout errors
        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return "The request timed out. Please check your internet connection and try again."
        }
        
        // Network errors
        if lowercased.contains("network") || lowercased.contains("connection") || lowercased.contains("offline") {
            return "Unable to connect to the server. Please check your internet connection."
        }
        
        // Rate limiting
        if lowercased.contains("rate limit") || lowercased.contains("too many requests") {
            return "Too many requests. Please wait a moment and try again."
        }
        
        // Authentication errors
        if lowercased.contains("unauthorized") || lowercased.contains("authentication") {
            return "Authentication error. Please restart the app and try again."
        }
        
        // Server errors
        if lowercased.contains("server error") || lowercased.contains("internal error") || lowercased.contains("500") {
            return "The server encountered an error. Please try again later."
        }
        
        // Not found errors
        if lowercased.contains("not found") || lowercased.contains("404") {
            return "The requested resource was not found. Please try searching again."
        }
        
        // Generic fallback - don't expose raw backend errors
        return "An unexpected error occurred during enrichment. Please try again later."
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let switchToLibraryTab = Notification.Name("SwitchToLibraryTab")
    static let enrichmentStarted = Notification.Name("EnrichmentStarted")
    static let enrichmentProgress = Notification.Name("EnrichmentProgress")
    static let enrichmentCompleted = Notification.Name("EnrichmentCompleted")
    static let enrichmentFailed = Notification.Name("EnrichmentFailed")
    static let libraryWasReset = Notification.Name("LibraryWasReset")
    static let searchForAuthor = Notification.Name("SearchForAuthor")
}

// MARK: - Tab Navigation

public enum MainTab: String, CaseIterable {
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
