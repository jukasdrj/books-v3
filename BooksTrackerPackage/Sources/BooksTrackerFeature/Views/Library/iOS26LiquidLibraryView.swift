import SwiftUI
import SwiftData

// MARK: - Library Layout Options

enum LibraryLayout: String, CaseIterable, Identifiable {
    case floatingGrid = "floating_grid"
    case adaptiveCards = "adaptive_cards"
    case liquidList = "liquid_list"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floatingGrid: return "Floating Grid"
        case .adaptiveCards: return "Adaptive Cards"
        case .liquidList: return "Liquid List"
        }
    }

    var icon: String {
        switch self {
        case .floatingGrid: return "grid"
        case .adaptiveCards: return "rectangle.grid.2x2"
        case .liquidList: return "list.bullet"
        }
    }
}

// MARK: - Main Library View

@available(iOS 26.0, *)
@MainActor
public struct iOS26LiquidLibraryView: View {

    // MARK: - Data

    // NOTE: Cannot use #Predicate for relationship aggregates (isEmpty, count, etc.)
    // CoreData throws: "Keypath containing KVC aggregate where there shouldn't be one"
    // Must fetch all and filter in-memory via LibraryFilterService
    @Query(sort: \Work.lastModified, order: .reverse)
    private var allWorks: [Work]

    private var libraryWorks: [Work] {
        filterService.filterLibraryWorks(from: allWorks, modelContext: modelContext)
    }

    // MARK: - State

    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var searchText = ""
    @State private var showingDiversityInsights = false
    @State private var showingReviewQueue = false
    @State private var showingSettings = false
    @State private var pendingEnrichmentCount = 0
    @State private var reviewQueueCount = 0
    @State private var isEnriching = false
    @State private var isReadingStatsExpanded = false
    @State private var quickFilter: LibraryRepository.QuickFilterType?
    @State private var errorMessage: String?
    @State private var showError = false

    // MARK: - Performance Cache

    @State private var cachedFilteredWorks: [Work] = []
    @State private var cachedDiversityScore: Double = 0.0
    @State private var cachedStatusCounts: [ReadingStatus: Int] = [:]
    @State private var filterService = LibraryFilterService()
    @State private var isLoading = true

    // MARK: - Environment

    @Namespace private var layoutTransition
    #if os(iOS)
    @State private var scrollPosition = ScrollPosition()
    #endif
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tabCoordinator) private var tabCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.enrichmentQueue) private var enrichmentQueue

    public init() {}

    // MARK: - Body

    public var body: some View {
        searchableContent
            .navigationTitle("My Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar { toolbarContent }
            .navigationDestination(for: Work.self) { work in
                WorkDetailView(work: work)
            }
            .sheet(isPresented: $showingReviewQueue) {
                #if canImport(UIKit)
                ReviewQueueView()
                    .onDisappear { updateReviewQueueCount() }
                #endif
            }
            .sheet(isPresented: $showingDiversityInsights) {
                CulturalDiversityInsightsView(works: cachedFilteredWorks)
                    .presentationDetents([.medium, .large])
                    .iOS26SheetGlass()
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if reviewQueueCount > 0 {
                reviewQueueButton
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            filterMenu
            diversityButton
            layoutMenu
            settingsButton
        }
    }

    private var reviewQueueButton: some View {
        Button { showingReviewQueue.toggle() } label: {
            Label("Review Queue", systemImage: "exclamationmark.triangle.badge.\(min(reviewQueueCount, 99))")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glassProminent)
        .tint(.orange)
        .foregroundStyle(.white)
        .symbolEffect(.bounce, value: reviewQueueCount)
    }

    private var filterMenu: some View {
        Menu {
            Button("Recently Added") {
                quickFilter = .recentlyAdded
                updateFilteredWorks()
            }
            Button("Recently Read") {
                quickFilter = .recentlyRead
                updateFilteredWorks()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        #if os(iOS)
        .buttonStyle(.glass)
        #endif
        .foregroundStyle(.primary)
    }

    private var diversityButton: some View {
        Button { showingDiversityInsights.toggle() } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        #if os(iOS)
        .buttonStyle(.glass)
        #endif
        .foregroundStyle(.primary)
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: $selectedLayout.animation(.smooth)) {
                ForEach(LibraryLayout.allCases, id: \.self) { layout in
                    Label(layout.displayName, systemImage: layout.icon).tag(layout)
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        #if os(iOS)
        .buttonStyle(.glass)
        #endif
        .foregroundStyle(.primary)
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
        }
        #if os(iOS)
        .buttonStyle(.glass)
        #endif
        .foregroundStyle(themeStore.primaryColor)
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView()
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingSettings = false }
                    }
                }
        }
    }


    // MARK: - Searchable Content

    private var searchableContent: some View {
        mainContentView
            .searchable(text: $searchText, prompt: "Search your library")
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { quickFilter = nil }
                updateFilteredWorks()
            }
            .onChange(of: allWorks) { _, _ in updateFilteredWorks() }
            .onChange(of: quickFilter) { _, _ in updateFilteredWorks() }
            .onChange(of: tabCoordinator.highlightedBookIDs) { _, newIDs in
                if !newIDs.isEmpty {
                    searchText = ""
                    cachedFilteredWorks = libraryWorks.filter { newIDs.contains($0.persistentModelID) }
                }
            }
            .task { await initialLoad() }
            .onReceive(NotificationCenter.default.publisher(for: .enrichmentStarted)) { _ in
                isEnriching = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .enrichmentCompleted)) { _ in
                isEnriching = false
                pendingEnrichmentCount = 0
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryWasReset)) { _ in
                clearAllCaches()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        ZStack {
            backgroundGradient

            if isLoading {
                skeletonLoadingView
            } else if cachedFilteredWorks.isEmpty {
                emptyStateView
            } else {
                libraryScrollView
            }

            floatingActionButton
        }
    }

    private var backgroundGradient: some View {
        Color.clear
            .background {
                LinearGradient(
                    colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
    }

    private var emptyStateView: some View {
        Group {
            if searchText.isEmpty && quickFilter == nil {
                SharedEmptyStateView(
                    title: "Your Library Awaits",
                    description: "Start building your personal collection of books.",
                    actions: [
                        EmptyStateAction(title: "Search for Books", icon: "magnifyingglass", color: .blue) {
                            tabCoordinator.selectedTab = .search
                        },
                        EmptyStateAction(title: "Scan a Shelf", icon: "books.vertical.fill", color: .purple) {
                            tabCoordinator.selectedTab = .shelf
                        }
                    ]
                )
            } else {
                SharedEmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Books Found",
                    description: "Try adjusting your search or filters."
                )
            }
        }
    }

    private var libraryScrollView: some View {
        Group {
            if cachedFilteredWorks.count > 50 {
                ScrollViewReader { scrollProxy in
                    scrollContent
                        .overlay(alignment: .trailing) {
                            AlphabeticalIndexView(works: cachedFilteredWorks, scrollProxy: scrollProxy)
                                .padding(.trailing, 4)
                        }
                }
            } else {
                scrollContent
            }
        }
    }

    private var floatingActionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                LiquidFloatingActionButton(items: [
                    FABItem(label: "Search Online", icon: "magnifyingglass", color: .blue) {
                        tabCoordinator.selectedTab = .search
                    },
                    FABItem(label: "Scan Shelf", icon: "books.vertical.fill", color: .purple) {
                        tabCoordinator.selectedTab = .shelf
                    }
                ])
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if pendingEnrichmentCount > 0 {
                    enrichmentStatusView
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }

                if !cachedFilteredWorks.isEmpty {
                    culturalInsightsHeader
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }

                currentLayoutView
                    .padding(.horizontal)
            }
        }
        #if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollPosition($scrollPosition)
        #endif
    }

    // MARK: - Skeleton Loading

    private var skeletonLoadingView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    BookCardSkeleton()
                }
            }
            .padding()
        }
        .accessibilityLabel("Loading your library")
        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
    }


    // MARK: - Grid Columns

    private var gridColumns: [GridItem] {
        switch horizontalSizeClass {
        case .compact:
            return [GridItem(.flexible()), GridItem(.flexible())]
        case .regular:
            return Array(repeating: GridItem(.flexible()), count: 4)
        case .none, .some(_):
            return [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)]
        }
    }

    // MARK: - Layout Views

    @ViewBuilder
    private var currentLayoutView: some View {
        Group {
            switch selectedLayout {
            case .floatingGrid:
                floatingGridLayout
            case .adaptiveCards:
                adaptiveCardsLayout
            case .liquidList:
                liquidListLayout
            }
        }
        .id(selectedLayout.id) // Stable identity for smooth transitions
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    private var floatingGridLayout: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26FloatingBookCard(work: work, namespace: layoutTransition, uniqueID: nil)
                }
                .buttonStyle(ScaleButtonStyle())
                .id(work.id)
                // iOS 26: Smooth scroll transition for visual polish
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.8)
                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                }
                .onAppear {
                    ImagePrefetcher.shared.prefetchIfNeeded(
                        for: work,
                        in: cachedFilteredWorks,
                        prefetchCount: 10,
                        threshold: 5
                    )
                }
            }
        }
    }

    private var adaptiveCardsLayout: some View {
        let displayMode: AdaptiveDisplayMode = (horizontalSizeClass == .compact) ? .standard : .detailed

        return LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26AdaptiveBookCard(work: work, displayMode: displayMode)
                }
                .buttonStyle(ScaleButtonStyle())
                .id(work.id)
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.8)
                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                }
                .onAppear {
                    ImagePrefetcher.shared.prefetchIfNeeded(
                        for: work,
                        in: cachedFilteredWorks,
                        prefetchCount: 10,
                        threshold: 5
                    )
                }
            }
        }
    }

    private var liquidListLayout: some View {
        LazyVStack(spacing: 12) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26LiquidListRow(work: work)
                }
                .buttonStyle(ScaleButtonStyle())
                .id(work.id)
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.9)
                }
                .onAppear {
                    ImagePrefetcher.shared.prefetchIfNeeded(
                        for: work,
                        in: cachedFilteredWorks,
                        prefetchCount: 10,
                        threshold: 5
                    )
                }
            }
        }
    }

    // MARK: - Cultural Insights Header

    private var culturalInsightsHeader: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(cachedFilteredWorks.count) Books")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text("Reading Goals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    culturalDiversityIndicator
                }

                readingProgressOverview
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .blue.opacity(0.1)) // HIG: Subtle tint
        #endif
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cachedDiversityScore > 0.3 ? .green : cachedDiversityScore > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                #if os(iOS)
                .glassEffect(.regular, interactive: true)
                #endif

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(cachedDiversityScore * 100))%")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text("Diverse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture { showingDiversityInsights.toggle() }
    }

    // MARK: - Reading Progress

    private var readingProgressOverview: some View {
        VStack(spacing: 12) {
            if !isReadingStatsExpanded {
                collapsedReadingStats
            } else {
                expandedReadingStats
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isReadingStatsExpanded ? "Reading status expanded" : "Reading status collapsed")
    }

    private var collapsedReadingStats: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { isReadingStatsExpanded = true }
        } label: {
            HStack {
                let inProgressCount = safeCountEntries(for: .reading) + safeCountEntries(for: .toRead)
                Text(inProgressCount == 1 ? "1 book in progress" : "\(inProgressCount) books in progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var expandedReadingStats: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isReadingStatsExpanded = false }
            } label: {
                HStack {
                    Text("Reading Status")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                ForEach(ReadingStatus.allCases.prefix(4), id: \.self) { status in
                    readingStatusBadge(for: status)
                }
            }
        }
    }

    private func readingStatusBadge(for status: ReadingStatus) -> some View {
        VStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundColor(status.color)
                #if os(iOS)
                .glassEffect(.regular, interactive: true)
                #endif

            Text("\(safeCountEntries(for: status))")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text(status.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Enrichment Status

    private var enrichmentStatusView: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Library Enhancement")
                        .font(.headline)
                    Text("\(pendingEnrichmentCount) books pending metadata")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isEnriching {
                    Button("Start") {
                        enrichmentQueue.startProcessing(
                            in: modelContext,
                            progressHandler: { _, _, _ in },
                            timeoutDuration: 300
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.purple)
                }
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .purple.opacity(0.1)) // HIG: Subtle tint
        #endif
    }

    // MARK: - Data Operations

    private func initialLoad() async {
        try? await Task.sleep(for: .seconds(0.5))
        updateFilteredWorks()
        pendingEnrichmentCount = enrichmentQueue.count()
        updateReviewQueueCount()
        withAnimation { isLoading = false }
    }

    private func updateFilteredWorks() {
        var filtered = Array(libraryWorks)

        if !searchText.isEmpty {
            filtered = filtered.filter { work in
                work.title.localizedStandardContains(searchText) ||
                (work.authors?.contains(where: { $0.name.localizedStandardContains(searchText) }) ?? false)
            }
        }

        if let quickFilter {
            guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
                errorMessage = "Failed to calculate date range for filtering"
                showError = true
                return
            }

            switch quickFilter {
            case .recentlyAdded:
                filtered = filtered.filter { work in
                    work.userLibraryEntries?.contains { $0.dateAdded >= thirtyDaysAgo } ?? false
                }
            case .recentlyRead:
                filtered = filtered.filter { work in
                    work.userLibraryEntries?.contains { entry in
                        guard let dateCompleted = entry.dateCompleted else { return false }
                        return dateCompleted >= thirtyDaysAgo
                    } ?? false
                }
            }
        }

        if filtered.map(\.id) != cachedFilteredWorks.map(\.id) {
            cachedFilteredWorks = filtered.sorted { $0.title < $1.title }
            updateCachedStatusCounts()

            Task {
                let score = await filterService.calculateDiversityScoreAsync(for: filtered)
                await MainActor.run { cachedDiversityScore = score }
            }
        }
    }

    private func updateReviewQueueCount() {
        let needsReviewRawValue = ReviewStatus.needsReview.rawValue
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in work.reviewStatusRawValue == needsReviewRawValue }
        )
        reviewQueueCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func updateCachedStatusCounts() {
        guard !cachedFilteredWorks.isEmpty else {
            cachedStatusCounts = [:]
            return
        }

        var counts: [ReadingStatus: Int] = [:]
        for status in ReadingStatus.allCases { counts[status] = 0 }

        for work in cachedFilteredWorks {
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else { continue }
            if let entries = work.userLibraryEntries {
                for entry in entries {
                    guard modelContext.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else { continue }
                    counts[entry.readingStatus, default: 0] += 1
                }
            }
        }
        cachedStatusCounts = counts
    }

    private func safeCountEntries(for status: ReadingStatus) -> Int {
        cachedStatusCounts[status] ?? 0
    }

    private func clearAllCaches() {
        cachedFilteredWorks = []
        cachedDiversityScore = 0.0
        cachedStatusCounts = [:]
        pendingEnrichmentCount = 0
        reviewQueueCount = 0
        isEnriching = false
        #if DEBUG
        print("✅ Library view: Cleared all caches after library reset")
        #endif
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    iOS26LiquidLibraryView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}
