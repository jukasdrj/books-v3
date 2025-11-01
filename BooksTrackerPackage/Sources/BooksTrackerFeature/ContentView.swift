import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var selectedTab: MainTab = .library
    @State private var searchCoordinator = SearchCoordinator()
    @State private var dtoMapper: DTOMapper?

    // Enrichment progress tracking (no Live Activity required!)
    @State private var isEnriching = false
    @State private var enrichmentProgress: (completed: Int, total: Int) = (0, 0)
    @State private var currentBookTitle = ""

    public var body: some View {
        if #available(iOS 26.0, *) {
            Group {
                if let dtoMapper = dtoMapper {
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
                    .environment(\.dtoMapper, dtoMapper)
                    .tint(themeStore.primaryColor)
                    #if os(iOS)
                    .tabBarMinimizeBehavior(
                        voiceOverEnabled || reduceMotion ? .never : (featureFlags.enableTabBarMinimize ? .onScrollDown : .never)
                    )
                    #endif
                } else {
                    ProgressView()
                }
            }
            .themedBackground()
            .onAppear(perform: setupDTOMapper)
            .task {
                // Validate enrichment queue on app startup - remove stale persistent IDs
                EnrichmentQueue.shared.validateQueue(in: modelContext)
            }
            .task {
                // Clean up temporary scan images after all books reviewed
                await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
                // Clean up orphaned temp files from failed scans (24h+ old)
                await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
            }
            .task {
                await handleNotifications()
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

    private func setupDTOMapper() {
        if dtoMapper == nil {
            dtoMapper = DTOMapper(modelContext: modelContext)
        }
    }

    public init() {}

    // MARK: - Sample Data Setup

    private func setupSampleData() {
        // Only add sample data if the library is empty
        let fetchRequest = FetchDescriptor<Work>()
        let existingWorks = try? modelContext.fetch(fetchRequest)

        if existingWorks?.isEmpty == true {
            addSampleData()
        }
    }

    private func addSampleData() {
        // Sample Authors
        let kazuoIshiguro = Author(
            name: "Kazuo Ishiguro",
            gender: .male,
            culturalRegion: .asia
        )

        let octaviaButler = Author(
            name: "Octavia E. Butler",
            gender: .female,
            culturalRegion: .northAmerica
        )

        let chimamandaNgozi = Author(
            name: "Chimamanda Ngozi Adichie",
            gender: .female,
            culturalRegion: .africa
        )

        modelContext.insert(kazuoIshiguro)
        modelContext.insert(octaviaButler)
        modelContext.insert(chimamandaNgozi)

        // Sample Works - follow insert-before-relate pattern
        let klaraAndTheSun = Work(
            title: "Klara and the Sun",
            originalLanguage: "English",
            firstPublicationYear: 2021
        )

        let kindred = Work(
            title: "Kindred",
            originalLanguage: "English",
            firstPublicationYear: 1979
        )

        let americanah = Work(
            title: "Americanah",
            originalLanguage: "English",
            firstPublicationYear: 2013
        )

        modelContext.insert(klaraAndTheSun)
        modelContext.insert(kindred)
        modelContext.insert(americanah)

        // Set relationships after insert
        klaraAndTheSun.authors = [kazuoIshiguro]
        kindred.authors = [octaviaButler]
        americanah.authors = [chimamandaNgozi]

        // Sample Editions - create without work parameter
        let klaraEdition = Edition(
            isbn: "9780571364893",
            publisher: "Faber & Faber",
            publicationDate: "2021",
            pageCount: 303,
            format: .hardcover
        )

        let kindredEdition = Edition(
            isbn: "9780807083697",
            publisher: "Beacon Press",
            publicationDate: "1979",
            pageCount: 287,
            format: .paperback
        )

        let americanahEdition = Edition(
            isbn: "9780307455925",
            publisher: "Knopf",
            publicationDate: "2013",
            pageCount: 477,
            format: .ebook
        )

        modelContext.insert(klaraEdition)
        modelContext.insert(kindredEdition)
        modelContext.insert(americanahEdition)

        // Link editions to works
        klaraEdition.work = klaraAndTheSun
        kindredEdition.work = kindred
        americanahEdition.work = americanah

        // Sample Library Entries
        let klaraEntry = UserLibraryEntry.createOwnedEntry(
            for: klaraAndTheSun,
            edition: klaraEdition,
            status: .reading,
            context: modelContext
        )
        klaraEntry.readingProgress = 0.35
        klaraEntry.dateStarted = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        let kindredEntry = UserLibraryEntry.createOwnedEntry(
            for: kindred,
            edition: kindredEdition,
            status: .read,
            context: modelContext
        )
        kindredEntry.dateCompleted = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        kindredEntry.personalRating = 5.0

        _ = UserLibraryEntry.createWishlistEntry(for: americanah, context: modelContext)

        // Note: Entries already inserted by factory methods - no need to insert again

        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save sample data: \(error)")
        }
    }

    // MARK: - Notification Handling (Swift 6.2)

    private func handleNotifications() async {
        // Handle each notification type sequentially to avoid Swift 6 isolation checker limitations
        // See: https://github.com/swiftlang/swift/issues/XXXXX
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .switchToLibraryTab) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentStarted) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentProgress) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentCompleted) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .searchForAuthor) {
                handle(notification)
            }
        }
    }

    @MainActor
    private func handle(_ notification: Notification) {
        switch notification.name {
        case .switchToLibraryTab:
            selectedTab = .library

        case .enrichmentStarted:
            if let userInfo = notification.userInfo,
               let total = userInfo["totalBooks"] as? Int {
                isEnriching = true
                enrichmentProgress = (0, total)
                currentBookTitle = ""
            }

        case .enrichmentProgress:
            if let userInfo = notification.userInfo,
               let completed = userInfo["completed"] as? Int,
               let total = userInfo["total"] as? Int,
               let title = userInfo["currentTitle"] as? String {
                enrichmentProgress = (completed, total)
                currentBookTitle = title
            }

        case .enrichmentCompleted:
            isEnriching = false

        case .searchForAuthor:
            if let authorName = notification.userInfo?["authorName"] as? String {
                selectedTab = .search
                searchCoordinator.setPendingAuthorSearch(authorName)
                // SearchView will observe the coordinator and trigger search when tab becomes visible
            }

        default:
            break
        }
    }
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

// MARK: - Enrichment Banner (No Live Activity Required!)

struct EnrichmentBanner: View {
    let completed: Int
    let total: Int
    let currentBookTitle: String
    let themeStore: iOS26ThemeStore

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 4)

                    // Progress fill with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [themeStore.primaryColor, themeStore.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(1.0, max(0.0, progress)),
                            height: 4
                        )
                        .animation(.smooth(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)

            // Content
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeStore.primaryColor, themeStore.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enriching Metadata")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !currentBookTitle.isEmpty {
                        Text(currentBookTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Progress text
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completed)/\(total)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background {
                GlassEffectContainer {
                    Rectangle()
                        .fill(.clear)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    ContentView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
