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

@available(iOS 26.0, *)
@MainActor
public struct iOS26LiquidLibraryView: View {
    // ✅ FIX 1: Query all works, filter in-memory for library items
    // Note: SwiftData predicates cannot filter on to-many relationships
    @Query(
        sort: \Work.lastModified,
        order: .reverse
    ) private var allWorks: [Work]

    // Computed property to get only works in user's library
    // CRITICAL: Safe access after library reset - UserLibraryEntry might be deleted but Work still exists during CloudKit sync
    private var libraryWorks: [Work] {
        filterService.filterLibraryWorks(from: allWorks)
    }
    
    // ✅ FIX 2: Simplified state management
    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var searchText = ""
    @State private var showingDiversityInsights = false
    @State private var showingReviewQueue = false
    @State private var showingSettings = false
    @State private var pendingEnrichmentCount = 0
    @State private var reviewQueueCount = 0
    @State private var isEnriching = false

    // ✅ FIX 3: Performance optimizations
    @State private var cachedFilteredWorks: [Work] = []
    @State private var cachedDiversityScore: Double = 0.0
    @State private var lastSearchText = ""
    @State private var filterService = LibraryFilterService()

    @Namespace private var layoutTransition
    @State private var scrollPosition = ScrollPosition()
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        mainContentView
            .searchable(text: $searchText, prompt: "Search your library")
            .onChange(of: searchText) { _, newValue in
                updateFilteredWorks()
            }
            .onChange(of: libraryWorks) { _, _ in
                updateFilteredWorks()
            }
            .onAppear {
                updateFilteredWorks()
                pendingEnrichmentCount = EnrichmentQueue.shared.count()
                updateReviewQueueCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .enrichmentStarted)) { _ in
                isEnriching = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .enrichmentCompleted)) { _ in
                isEnriching = false
                pendingEnrichmentCount = 0
            }
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Alert/Action items - Leading placement for prominence
                ToolbarItem(placement: .navigationBarLeading) {
                    if reviewQueueCount > 0 {
                        Button {
                            showingReviewQueue.toggle()
                        } label: {
                            Label {
                                Text("Review Queue")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.badge.\(min(reviewQueueCount, 99))")
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(GlassProminentButtonStyle(tint: .orange))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: reviewQueueCount)
                        .accessibilityLabel("Review Queue")
                        .accessibilityValue("\(reviewQueueCount) book\(reviewQueueCount == 1 ? "" : "s") need review")
                        .accessibilityHint("Opens queue to verify AI-detected book information")
                    }
                }

                // Informational/Settings - Trailing placement for secondary actions
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingDiversityInsights.toggle()
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Diversity Insights")
                    .accessibilityHint("View reading diversity and cultural statistics")

                    Menu {
                        Picker("Layout", selection: $selectedLayout.animation(.smooth)) {
                            ForEach(LibraryLayout.allCases, id: \.self) { layout in
                                Label(layout.displayName, systemImage: layout.icon)
                                    .tag(layout)
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Change layout")
                    .accessibilityHint("Switch between grid, cards, and list views")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(GlassButtonStyle())
                    .foregroundStyle(themeStore.primaryColor)
                    .accessibilityLabel("Settings")
                }
            }
            // ✅ FIX 4: Navigation with Work objects (SwiftData PersistentIdentifier)
            .navigationDestination(for: Work.self) { work in
                WorkDetailView(work: work)
            }
            .sheet(isPresented: $showingReviewQueue) {
                ReviewQueueView()
                    .onDisappear {
                        // Refresh queue count when returning from review queue
                        updateReviewQueueCount()
                    }
            }
            .sheet(isPresented: $showingDiversityInsights) {
                CulturalDiversityInsightsView(works: cachedFilteredWorks)
                    .presentationDetents([.medium, .large])
                    .iOS26SheetGlass()
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showingSettings = false
                                }
                            }
                        }
                }
            }
    }

    // MARK: - Main Content View

    private var mainContentView: some View {
        ZStack {
            Color.clear
                .background {
                    LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if pendingEnrichmentCount > 0 {
                        enrichmentStatusView
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                    }
                    // Cultural insights header
                    if !cachedFilteredWorks.isEmpty {
                        culturalInsightsHeader
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                    }

                    // Library content based on selected layout
                    Group {
                        switch selectedLayout {
                        case .floatingGrid:
                            optimizedFloatingGridLayout
                        case .adaptiveCards:
                            optimizedAdaptiveCardsLayout
                        case .liquidList:
                            optimizedLiquidListLayout
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)  // iOS 26: Soft fade under nav bar for Liquid Glass depth
            .scrollPosition($scrollPosition)
        }
    }

    // MARK: - Optimized Layout Implementations

    @ViewBuilder
    private var optimizedFloatingGridLayout: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    OptimizedFloatingBookCard(work: work, namespace: layoutTransition)
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id) // ✅ Explicit ID for view recycling
            }
        }
    }

    @ViewBuilder
    private var optimizedAdaptiveCardsLayout: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26AdaptiveBookCard(work: work)
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id)
            }
        }
    }

    @ViewBuilder
    private var optimizedLiquidListLayout: some View {
        LazyVStack(spacing: 12) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26LiquidListRow(work: work)
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id)
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
        .glassEffect(.regular, tint: .blue.opacity(0.3))
    }

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
                        EnrichmentQueue.shared.startProcessing(in: modelContext) { completed, total, bookTitle in
                            // This closure is for progress updates, but ContentView is already handling it
                            // via notifications. We can leave it empty or log to console for debugging.
                            print("Enriching from library view: \(completed)/\(total) - \(bookTitle)")
                        }
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .foregroundStyle(.purple)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .purple.opacity(0.2))
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cachedDiversityScore > 0.3 ? .green : cachedDiversityScore > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                .glassEffect(.regular, interactive: true)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(cachedDiversityScore * 100))%")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text("Diverse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture {
            showingDiversityInsights.toggle()
        }
    }

    private var readingProgressOverview: some View {
        HStack(spacing: 16) {
            ForEach(ReadingStatus.allCases.prefix(4), id: \.self) { status in
                let count = cachedFilteredWorks.compactMap(\.userLibraryEntries).flatMap { $0 }.filter { $0.readingStatus == status }.count

                VStack(spacing: 4) {
                    Image(systemName: status.systemImage)
                        .font(.title3)
                        .foregroundColor(status.color)
                        .glassEffect(.regular, interactive: true)

                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    Text(status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Performance Optimizations

    private func updateFilteredWorks() {
        // ✅ FIX 5: Cached filtering and diversity calculation using LibraryFilterService
        let filtered: [Work]

        if searchText.isEmpty {
            filtered = Array(libraryWorks)
        } else {
            filtered = filterService.searchWorks(libraryWorks, searchText: searchText)
        }

        // Only update if actually changed
        if filtered.map(\.id) != cachedFilteredWorks.map(\.id) {
            cachedFilteredWorks = filtered
            cachedDiversityScore = filterService.calculateDiversityScore(for: filtered)
        }
    }

    private func updateReviewQueueCount() {
        // Count works needing human review - filter in memory since enum comparison not supported
        let descriptor = FetchDescriptor<Work>()

        if let allWorks = try? modelContext.fetch(descriptor) {
            reviewQueueCount = allWorks.filter { $0.reviewStatus == .needsReview }.count
        }
    }

    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let screenWidth = size.width
        let columnCount: Int

        if screenWidth > 1000 {
            columnCount = 6
        } else if screenWidth > 800 {
            columnCount = 4
        } else if screenWidth > 600 {
            columnCount = 3
        } else {
            columnCount = 2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }
}

// MARK: - Ultra-Optimized Library View

/// ✅ CRITICAL FIXES: This version addresses all the major iOS UX issues
@available(iOS 26.0, *)
@MainActor
public struct UltraOptimizedLibraryView: View {
    // ✅ FIX 1: Highly optimized SwiftData query - only loads library entries
    @Query(
        filter: #Predicate<UserLibraryEntry> { entry in
            true // Get all library entries, works will be loaded lazily
        },
        sort: \UserLibraryEntry.lastModified,
        order: .reverse
    ) private var libraryEntries: [UserLibraryEntry]
    
    // ✅ FIX 2: Minimal state management
    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var searchText = ""
    @State private var showingDiversityInsights = false
    
    // ✅ FIX 3: Performance-optimized data source
    @State private var dataSource = OptimizedLibraryDataSource()
    @State private var filteredWorks: [Work] = []
    @State private var diversityScore: Double = 0.0
    
    @Namespace private var layoutTransition
    @State private var scrollPosition = ScrollPosition()
    @Environment(\.iOS26ThemeStore) private var themeStore

    // ✅ FIX 4: Memory management
    private let memoryHandler = MemoryPressureHandler.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            optimizedMainContent
                .searchable(text: $searchText, prompt: "Search your library")
                .task {
                    await updateData()
                }
                .onChange(of: searchText) { _, _ in
                    Task { await updateData() }
                }
                .onChange(of: libraryEntries) { _, _ in
                    Task { await updateData() }
                }
        }
        .navigationTitle("My Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showingDiversityInsights.toggle()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(GlassButtonStyle())
                .foregroundStyle(.primary)
                .accessibilityLabel("Diversity Insights")
                .accessibilityHint("View reading diversity and cultural statistics")

                Menu {
                    Picker("Layout", selection: $selectedLayout.animation(.smooth)) {
                        ForEach(LibraryLayout.allCases, id: \.self) { layout in
                            Label(layout.displayName, systemImage: layout.icon)
                                .tag(layout)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(GlassButtonStyle())
                .foregroundStyle(.primary)
                .accessibilityLabel("Change layout")
                .accessibilityHint("Switch between grid, cards, and list views")
            }
        }
        .modifier(SafeWorkNavigation(
            workID: UUID(), // Will be overridden by individual NavigationLinks
            allWorks: filteredWorks
        ))
        .sheet(isPresented: $showingDiversityInsights) {
            CulturalDiversityInsightsView(works: filteredWorks)
                .presentationDetents([.medium, .large])
                .iOS26SheetGlass()
        }
        .performanceMonitor("UltraOptimizedLibraryView")
    }

    // MARK: - Optimized Main Content

    private var optimizedMainContent: some View {
        ZStack {
            Color.clear
                .background {
                    LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }

            if filteredWorks.isEmpty {
                emptyStateView
            } else {
                contentScrollView
            }
        }
    }

    private var contentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Insights header
                optimizedInsightsHeader
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .performanceMonitor("InsightsHeader")

                // Books grid/list
                optimizedBooksLayout
                    .padding(.horizontal)
                    .performanceMonitor("BooksLayout")
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.visible, axes: .vertical)
    }

    // HIG: Enhanced empty state with inviting design and clear calls-to-action
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero section - HIG: Clear, inviting empty state
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Your Library Awaits")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("Start building your personal collection of books")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.top, 60)

                // HIG: Clear calls-to-action with visual hierarchy
                VStack(spacing: 24) {
                    actionCard(
                        icon: "magnifyingglass",
                        title: "Search for Books",
                        description: "Browse millions of books by title, author, or ISBN",
                        color: .blue
                    )

                    actionCard(
                        icon: "barcode.viewfinder",
                        title: "Scan a Barcode",
                        description: "Use your camera to quickly add books from ISBN",
                        color: .purple
                    )

                    actionCard(
                        icon: "sparkles",
                        title: "Discover Diverse Voices",
                        description: "Track cultural diversity and explore underrepresented authors",
                        color: .green
                    )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library is empty")
        .accessibilityHint("Search for books or scan barcodes to start building your library")
    }

    // HIG: Action card component for empty state suggestions
    private func actionCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Optimized Layout Implementations

    @ViewBuilder
    private var optimizedBooksLayout: some View {
        switch selectedLayout {
        case .floatingGrid:
            ultraOptimizedGrid
        case .adaptiveCards:
            ultraOptimizedAdaptiveGrid
        case .liquidList:
            ultraOptimizedList
        }
    }

    private var ultraOptimizedGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    OptimizedFloatingBookCard(
                        work: work,
                        namespace: layoutTransition
                    )
                    .performanceMonitor("BookCard-\(work.title)")
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id)
            }
        }
    }

    private var ultraOptimizedAdaptiveGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26AdaptiveBookCard(work: work)
                        .performanceMonitor("AdaptiveCard-\(work.title)")
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id)
            }
        }
    }

    private var ultraOptimizedList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26LiquidListRow(work: work)
                        .performanceMonitor("ListRow-\(work.title)")
                }
                .buttonStyle(.plain) // ✅ FIX: Changed from BookCardButtonStyle() to allow NavigationLink taps
                .id(work.id)
            }
        }
    }

    // MARK: - Optimized Insights Header

    private var optimizedInsightsHeader: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(filteredWorks.count) Books")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text("Reading Goals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    optimizedDiversityIndicator
                }

                optimizedProgressOverview
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.3))
    }

    private var optimizedDiversityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(diversityScore > 0.3 ? .green : diversityScore > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                .glassEffect(.regular, interactive: true)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(diversityScore * 100))%")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text("Diverse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture {
            showingDiversityInsights.toggle()
        }
    }

    private var optimizedProgressOverview: some View {
        HStack(spacing: 16) {
            ForEach(ReadingStatus.allCases.prefix(4), id: \.self) { status in
                let count = libraryEntries.filter { $0.readingStatus == status }.count

                VStack(spacing: 4) {
                    Image(systemName: status.systemImage)
                        .font(.title3)
                        .foregroundColor(status.color)
                        .glassEffect(.regular, interactive: true)

                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    Text(status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Performance Optimizations

    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let screenWidth = size.width
        let columnCount: Int

        if screenWidth > 1000 {
            columnCount = 6
        } else if screenWidth > 800 {
            columnCount = 4
        } else if screenWidth > 600 {
            columnCount = 3
        } else {
            columnCount = 2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    private var adaptiveColumns: [GridItem] {
        // Use a reasonable default when no geometry is available
        adaptiveColumns(for: CGSize(width: 400, height: 800))
    }

    @MainActor
    private func updateData() async {
        // Convert library entries to works efficiently
        let works = libraryEntries.compactMap(\.work)
        
        let filtered = dataSource.getFilteredWorks(
            from: works,
            searchText: searchText
        )
        
        // Update diversity score efficiently
        let newDiversityScore = calculateDiversityScore(for: filtered)
        
        // Only update if changed to prevent unnecessary re-renders
        if filtered.map(\.id) != filteredWorks.map(\.id) {
            filteredWorks = filtered
        }
        
        if abs(newDiversityScore - diversityScore) > 0.01 {
            diversityScore = newDiversityScore
        }
    }

    private func calculateDiversityScore(for works: [Work]) -> Double {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        guard !allAuthors.isEmpty else { return 0.0 }

        let diverseCount = allAuthors.filter { author in
            author.representsMarginalizedVoices() || author.representsIndigenousVoices()
        }.count

        return Double(diverseCount) / Double(allAuthors.count)
    }
}

// MARK: - Cultural Diversity Insights Sheet

@available(iOS 26.0, *)
struct CulturalDiversityInsightsView: View {
    let works: [Work]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Diversity metrics
                    diversityMetricsSection

                    // Cultural regions breakdown
                    culturalRegionsSection

                    // Author gender distribution
                    genderDistributionSection

                    // Reading goals progress
                    readingGoalsSection
                }
                .padding()
                .scrollTargetLayout()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Cultural Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var diversityMetricsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diversity Overview")
                    .font(.headline.bold())

                let metrics = calculateDiversityMetrics()

                HStack(spacing: 20) {
                    MetricView(
                        title: "Diverse Voices",
                        value: "\(Int(metrics.diversePercentage * 100))%",
                        color: metrics.diversePercentage > 0.3 ? .green : .orange
                    )

                    MetricView(
                        title: "Cultural Regions",
                        value: "\(metrics.regionCount)",
                        color: .blue
                    )

                    MetricView(
                        title: "Languages",
                        value: "\(metrics.languageCount)",
                        color: .purple
                    )
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.2))
    }

    private var culturalRegionsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cultural Regions")
                    .font(.headline.bold())

                let regionStats = calculateRegionStatistics()

                ForEach(regionStats.sorted(by: { $0.value > $1.value }), id: \.key) { region, count in
                    HStack {
                        Text(region.emoji)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.displayName)
                                .font(.body.bold())

                            Text("\(count) books")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(Int(Double(count) / Double(works.count) * 100))%")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .green.opacity(0.2))
    }

    private var genderDistributionSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Author Gender Distribution")
                    .font(.headline.bold())

                let genderStats = calculateGenderStatistics()

                ForEach(genderStats.sorted(by: { $0.value > $1.value }), id: \.key) { gender, count in
                    HStack {
                        Image(systemName: gender.icon)
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 24)

                        Text(gender.displayName)
                            .font(.body)

                        Spacer()

                        Text("\(count)")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .purple.opacity(0.2))
    }

    private var readingGoalsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reading Goals Progress")
                    .font(.headline.bold())

                // Placeholder for reading goals - implement based on user's goals
                VStack(spacing: 8) {
                    ProgressView(value: 0.65) {
                        Text("Diverse Authors Goal")
                            .font(.subheadline)
                    }
                    .tint(.green)

                    ProgressView(value: 0.8) {
                        Text("Annual Reading Goal")
                            .font(.subheadline)
                    }
                    .tint(.blue)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .orange.opacity(0.2))
    }

    // MARK: - Helper Methods

    private func calculateDiversityMetrics() -> (diversePercentage: Double, regionCount: Int, languageCount: Int) {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        let diverseCount = allAuthors.filter { $0.representsMarginalizedVoices() }.count
        let diversePercentage = allAuthors.isEmpty ? 0.0 : Double(diverseCount) / Double(allAuthors.count)

        let regions = Set(allAuthors.compactMap(\.culturalRegion))
        let languages = Set(works.compactMap(\.originalLanguage))

        return (diversePercentage, regions.count, languages.count)
    }

    private func calculateRegionStatistics() -> [CulturalRegion: Int] {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        var regionCounts: [CulturalRegion: Int] = [:]

        for author in allAuthors {
            if let region = author.culturalRegion {
                regionCounts[region, default: 0] += 1
            }
        }

        return regionCounts
    }

    private func calculateGenderStatistics() -> [AuthorGender: Int] {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        var genderCounts: [AuthorGender: Int] = [:]

        for author in allAuthors {
            genderCounts[author.gender, default: 0] += 1
        }

        return genderCounts
    }
}

// MARK: - Metric View Component

@available(iOS 26.0, *)
struct MetricView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Book Card Button Style

struct BookCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    iOS26LiquidLibraryView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}