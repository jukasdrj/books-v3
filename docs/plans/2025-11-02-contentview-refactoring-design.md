# ContentView Refactoring Design

**Date:** November 2, 2025
**Status:** Design Approved
**Priority:** Medium
**Scope:** File-Based Separation (Moderate Refactoring)

## Problem Statement

ContentView.swift (449 lines) violates the Single Responsibility Principle by handling:

1. Tab navigation orchestration
2. Sample data generation (124 lines)
3. Notification listening (5 concurrent tasks, 70+ lines)
4. EnrichmentBanner UI definition (92 lines)
5. DTOMapper initialization with optional state

**Specific Issues Identified:**

- **Magic Strings:** Notification `userInfo` keys use raw strings ("totalBooks", "authorName") causing silent failures on typos (ContentView.swift:280-301)
- **Inefficient Database Query:** `setupSampleData()` fetches ALL Work objects just to check existence (ContentView.swift:116-117)
- **Optional State Initialization:** DTOMapper requires `if let` unwrapping and causes ProgressView flash on launch (ContentView.swift:12, 22, 68-70)
- **Verbose Notification Handling:** Five separate concurrent Tasks create cognitive overhead (ContentView.swift:243-271)

**Impact:** Difficult to maintain, test, and extend. Cognitive load for developers working on ContentView.

## Goals

**Primary:** Improve maintainability by decomposing ContentView into focused, single-responsibility components.

**Success Criteria:**
- Reduce ContentView from 449 → ~120 lines (73% reduction)
- Eliminate magic strings with compile-time safe notification payloads
- Optimize sample data check to avoid fetching all Works
- Remove DTOMapper optional state and ProgressView flash

**Non-Goals:**
- Comprehensive test coverage (deferred to future PR)
- Rearchitecting notification system away from NotificationCenter (keep existing patterns)
- Performance optimization beyond sample data check

## Design Overview

**Approach:** File-Based Separation with Type-Safe Notifications

Extract 4 components from ContentView into separate files while maintaining current architecture:

1. **EnrichmentBanner** → `UI/EnrichmentBanner.swift` (pure SwiftUI component)
2. **SampleDataGenerator** → `Services/SampleDataGenerator.swift` (business logic)
3. **NotificationCoordinator** → `Services/NotificationCoordinator.swift` (notification routing)
4. **NotificationPayloads** → `Models/NotificationPayloads.swift` (type definitions)

**Why This Approach:**
- Minimal disruption (keeps NotificationCenter, @State patterns)
- Clear separation of concerns (UI, business logic, coordination)
- Incremental improvement (can evolve to Coordinator Pattern later)
- Low risk (no architectural changes, just extraction)

## Detailed Design

### 1. File Structure

```
BooksTrackerPackage/Sources/BooksTrackerFeature/
├── ContentView.swift (slimmed to ~120 lines)
├── UI/
│   └── EnrichmentBanner.swift (NEW - 92 lines extracted)
├── Services/
│   ├── SampleDataGenerator.swift (NEW - 126 lines extracted)
│   └── NotificationCoordinator.swift (NEW - ~80 lines)
└── Models/
    └── NotificationPayloads.swift (NEW - ~60 lines)
```

### 2. Type-Safe Notification Payloads

**Problem:** Magic strings in `userInfo` dictionaries cause silent runtime failures.

**Solution:** Structured payload types with compile-time safety.

```swift
// Models/NotificationPayloads.swift
import Foundation

/// Type-safe payload for enrichment start notifications
public struct EnrichmentStartedPayload {
    public let totalBooks: Int

    public init(totalBooks: Int) {
        self.totalBooks = totalBooks
    }
}

/// Type-safe payload for enrichment progress notifications
public struct EnrichmentProgressPayload {
    public let completed: Int
    public let total: Int
    public let currentTitle: String

    public init(completed: Int, total: Int, currentTitle: String) {
        self.completed = completed
        self.total = total
        self.currentTitle = currentTitle
    }
}

/// Type-safe payload for author search notifications
public struct SearchForAuthorPayload {
    public let authorName: String

    public init(authorName: String) {
        self.authorName = authorName
    }
}
```

**Benefits:**
- Typos become compile errors (not silent runtime failures)
- Autocomplete for payload properties
- Self-documenting notification contracts
- Easy to evolve (add fields without breaking existing code)

### 3. NotificationCoordinator Service

**Responsibilities:**
1. Type-safe notification posting
2. Type-safe payload extraction
3. Centralized notification handling loop

```swift
// Services/NotificationCoordinator.swift
import Foundation
import SwiftUI

@MainActor
public final class NotificationCoordinator {
    public init() {}

    // MARK: - Type-Safe Posting

    public func postEnrichmentStarted(totalBooks: Int) {
        let payload = EnrichmentStartedPayload(totalBooks: totalBooks)
        NotificationCenter.default.post(
            name: .enrichmentStarted,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    public func postEnrichmentProgress(completed: Int, total: Int, currentTitle: String) {
        let payload = EnrichmentProgressPayload(
            completed: completed,
            total: total,
            currentTitle: currentTitle
        )
        NotificationCenter.default.post(
            name: .enrichmentProgress,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    public func postSearchForAuthor(authorName: String) {
        let payload = SearchForAuthorPayload(authorName: authorName)
        NotificationCenter.default.post(
            name: .searchForAuthor,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    // MARK: - Type-Safe Extraction

    public func extractEnrichmentStarted(from notification: Notification) -> EnrichmentStartedPayload? {
        notification.userInfo?["payload"] as? EnrichmentStartedPayload
    }

    public func extractEnrichmentProgress(from notification: Notification) -> EnrichmentProgressPayload? {
        notification.userInfo?["payload"] as? EnrichmentProgressPayload
    }

    public func extractSearchForAuthor(from notification: Notification) -> SearchForAuthorPayload? {
        notification.userInfo?["payload"] as? SearchForAuthorPayload
    }

    // MARK: - Centralized Notification Handling

    /// Handles all app notifications in a single stream. Call from ContentView.task { }.
    public func handleNotifications(
        onSwitchToLibrary: @escaping () -> Void,
        onEnrichmentStarted: @escaping (EnrichmentStartedPayload) -> Void,
        onEnrichmentProgress: @escaping (EnrichmentProgressPayload) -> Void,
        onEnrichmentCompleted: @escaping () -> Void,
        onSearchForAuthor: @escaping (SearchForAuthorPayload) -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .switchToLibraryTab) {
                    onSwitchToLibrary()
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .enrichmentStarted) {
                    if let payload = self.extractEnrichmentStarted(from: notification) {
                        onEnrichmentStarted(payload)
                    }
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .enrichmentProgress) {
                    if let payload = self.extractEnrichmentProgress(from: notification) {
                        onEnrichmentProgress(payload)
                    }
                }
            }

            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .enrichmentCompleted) {
                    onEnrichmentCompleted()
                }
            }

            group.addTask {
                for await notification in NotificationCenter.default.notifications(named: .searchForAuthor) {
                    if let payload = self.extractSearchForAuthor(from: notification) {
                        onSearchForAuthor(payload)
                    }
                }
            }
        }
    }
}
```

**ContentView Integration:**

```swift
@State private var notificationCoordinator = NotificationCoordinator()

// In body:
.task {
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
```

**Benefits:**
- Reduces ContentView notification handling from 70 → 15 lines
- Clear callback-based API (easy to understand what notifications do)
- Type safety enforced by coordinator
- Centralized notification logic (add new notifications in one place)

### 4. SampleDataGenerator Service

**Problem:** Inefficient database check fetches all Work objects. Sample data logic clutters ContentView (124 lines).

**Solution:** Extract to service with optimized query.

```swift
// Services/SampleDataGenerator.swift
import SwiftData
import Foundation

@MainActor
public final class SampleDataGenerator {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Adds sample data only if library is empty. Optimized check (fetchLimit=1).
    public func setupSampleDataIfNeeded() {
        guard isLibraryEmpty() else { return }
        addSampleData()
    }

    // MARK: - Private Helpers

    private func isLibraryEmpty() -> Bool {
        var descriptor = FetchDescriptor<Work>()
        descriptor.fetchLimit = 1  // Only check existence, don't fetch all Works

        let works = (try? modelContext.fetch(descriptor)) ?? []
        return works.isEmpty
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

        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save sample data: \(error)")
        }
    }
}
```

**ContentView Integration:**

```swift
.task {
    let generator = SampleDataGenerator(modelContext: modelContext)
    generator.setupSampleDataIfNeeded()
}
```

**Benefits:**
- **Performance:** `fetchLimit=1` avoids loading entire library into memory (critical for large libraries)
- **Maintainability:** Sample data logic isolated, easy to modify/extend (e.g., add new sample books)
- **Testability:** Can test sample data generation independently (future-proof for unit tests)
- **Removes 126 lines from ContentView**

### 5. DTOMapper Environment Injection

**Problem:** Optional `@State` DTOMapper requires `if let` unwrapping, causes brief ProgressView flash on launch.

**Solution:** Create DTOMapper in `BooksTrackerApp.swift` and inject via environment.

```swift
// BooksTrackerApp.swift (modifications)
@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags()
    let modelContainer: ModelContainer
    let dtoMapper: DTOMapper  // NEW - created once at app launch

    init() {
        // ... existing modelContainer setup ...

        // Create DTOMapper with main context
        self.dtoMapper = DTOMapper(modelContext: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environment(themeStore)
                .environment(featureFlags)
                .environment(\.dtoMapper, dtoMapper)  // Inject DTOMapper
        }
    }
}

// EnvironmentValues extension (add to DTOMapper.swift or new file)
private struct DTOMapperKey: EnvironmentKey {
    static let defaultValue: DTOMapper? = nil
}

extension EnvironmentValues {
    public var dtoMapper: DTOMapper? {
        get { self[DTOMapperKey.self] }
        set { self[DTOMapperKey.self] = newValue }
    }
}
```

**ContentView Changes:**

```swift
// Before:
@State private var dtoMapper: DTOMapper?

public var body: some View {
    if let dtoMapper = dtoMapper {
        TabView(selection: $selectedTab) { ... }
            .environment(\.dtoMapper, dtoMapper)
    } else {
        ProgressView()
    }
}
.onAppear(perform: setupDTOMapper)

private func setupDTOMapper() {
    if dtoMapper == nil {
        dtoMapper = DTOMapper(modelContext: modelContext)
    }
}

// After:
@Environment(\.dtoMapper) private var dtoMapper

public var body: some View {
    TabView(selection: $selectedTab) { ... }
        .environment(\.dtoMapper, dtoMapper!)  // Force-unwrap safe (app guarantees injection)
}
// No onAppear, no setupDTOMapper function
```

**Benefits:**
- **No ProgressView flash** on launch (DTOMapper ready immediately)
- **Simpler ContentView body** (removes `if let` wrapper and `onAppear` setup)
- **Testable** (can inject mock DTOMapper in previews/tests)
- **Follows SwiftUI patterns** (dependency injection via environment)

**Trade-off:** Requires force-unwrap (`dtoMapper!`) since environment value is technically optional. This is safe because `BooksTrackerApp` guarantees injection at app launch.

### 6. EnrichmentBanner Extraction

**Problem:** EnrichmentBanner definition clutters ContentView (92 lines, ContentView.swift:348-439).

**Solution:** Extract to dedicated file in `UI/` folder.

```swift
// UI/EnrichmentBanner.swift
import SwiftUI

/// Banner displaying real-time enrichment progress with glass effect.
/// Shown at bottom of screen during background metadata enrichment.
public struct EnrichmentBanner: View {
    public let completed: Int
    public let total: Int
    public let currentBookTitle: String
    public let themeStore: iOS26ThemeStore

    public init(
        completed: Int,
        total: Int,
        currentBookTitle: String,
        themeStore: iOS26ThemeStore
    ) {
        self.completed = completed
        self.total = total
        self.currentBookTitle = currentBookTitle
        self.themeStore = themeStore
    }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var body: some View {
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
```

**ContentView Integration (unchanged):**

```swift
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
```

**Benefits:**
- **Removes 92 lines from ContentView**
- **Reusable** (can show enrichment progress in other views if needed)
- **Easier to maintain** (all banner logic in one file)
- **Future-proof** (can add snapshot tests for UI validation)

### 7. Final ContentView Structure

After refactoring, ContentView becomes a clean orchestration layer:

```swift
public struct ContentView: View {
    // MARK: - Environment
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper  // Non-optional!
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // MARK: - State
    @State private var selectedTab: MainTab = .library
    @State private var searchCoordinator = SearchCoordinator()
    @State private var notificationCoordinator = NotificationCoordinator()

    // Enrichment progress (owned by ContentView, updated by coordinator)
    @State private var isEnriching = false
    @State private var enrichmentProgress: (completed: Int, total: Int) = (0, 0)
    @State private var currentBookTitle = ""

    public var body: some View {
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
        .environment(\.dtoMapper, dtoMapper!)  // Force-unwrap safe (injected by app)
        .tint(themeStore.primaryColor)
        #if os(iOS)
        .tabBarMinimizeBehavior(
            voiceOverEnabled || reduceMotion ? .never : (featureFlags.enableTabBarMinimize ? .onScrollDown : .never)
        )
        #endif
        .themedBackground()
        .task {
            EnrichmentQueue.shared.validateQueue(in: modelContext)
        }
        .task {
            await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
            await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
        }
        .task {
            let generator = SampleDataGenerator(modelContext: modelContext)
            generator.setupSampleDataIfNeeded()
        }
        .task {
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
    }

    public init() {}
}
```

**Line Count:**
- **Before:** 449 lines
- **After:** ~120 lines
- **Reduction:** 73% (329 lines extracted)

## Implementation Impact

### Files Modified

**Existing Files:**
1. `ContentView.swift` - Slim down to ~120 lines
2. `BooksTrackerApp.swift` - Add DTOMapper initialization and environment injection
3. `EnrichmentQueue.swift` - Replace `NotificationCenter.default.post` with `NotificationCoordinator` calls

**New Files:**
1. `UI/EnrichmentBanner.swift` - Extracted component (92 lines)
2. `Services/SampleDataGenerator.swift` - Sample data logic (126 lines)
3. `Services/NotificationCoordinator.swift` - Notification routing (~80 lines)
4. `Models/NotificationPayloads.swift` - Type-safe payloads (~60 lines)

### Migration Strategy

**Phase 1: Extract Components (Low Risk)**
1. Create `UI/EnrichmentBanner.swift` (pure extraction, no API changes)
2. Create `Services/SampleDataGenerator.swift` (pure extraction, no API changes)
3. Update `ContentView.swift` to use extracted components
4. **Validation:** Build succeeds, app launches, sample data still works

**Phase 2: Type-Safe Notifications (Medium Risk)**
1. Create `Models/NotificationPayloads.swift` (new types, no breaking changes)
2. Create `Services/NotificationCoordinator.swift` (new service)
3. Update `ContentView.swift` to use coordinator for notification handling
4. **Validation:** Build succeeds, notifications still work (manual testing)

**Phase 3: Notification Senders (Medium Risk)**
1. Update `EnrichmentQueue.swift` to post via `NotificationCoordinator`
2. Update any other notification senders (WorkDiscoveryView, iOS26AdaptiveBookCard, etc.)
3. **Validation:** End-to-end testing (trigger enrichment, verify banner shows)

**Phase 4: DTOMapper Injection (Low Risk)**
1. Add `EnvironmentValues` extension for DTOMapper
2. Update `BooksTrackerApp.swift` to create and inject DTOMapper
3. Update `ContentView.swift` to use environment DTOMapper
4. **Validation:** Build succeeds, app launches without ProgressView flash

**Rollback Plan:** Each phase is independent. Can revert individual commits if issues arise.

## Testing Strategy

**Manual Testing (Comprehensive):**
1. App launches without ProgressView flash
2. Sample data appears on first launch (empty library)
3. Sample data does NOT duplicate on subsequent launches
4. Enrichment banner shows during background enrichment
5. Enrichment progress updates in real-time
6. Tab switches work (Library, Search, Shelf, Insights)
7. "Search for Author" notification switches to Search tab and triggers search

**Automated Testing (Deferred):**
- Unit tests for `SampleDataGenerator.isLibraryEmpty()` (verify fetchLimit=1)
- Unit tests for `NotificationCoordinator` payload extraction
- Snapshot tests for `EnrichmentBanner` UI states (0%, 50%, 100%)

## Trade-offs

### Pros
- **Maintainability:** 73% reduction in ContentView lines, focused components
- **Type Safety:** Compile-time errors for notification payload typos
- **Performance:** `fetchLimit=1` optimizes sample data check
- **Testability:** Extracted components easier to test in isolation
- **Readability:** Clear separation of concerns (UI, business logic, coordination)

### Cons
- **Slightly More Verbose:** NotificationCoordinator adds indirection vs direct `NotificationCenter.default.post`
- **Force Unwrap:** DTOMapper environment injection requires `dtoMapper!` (safe but not ideal)
- **Migration Effort:** Must update all notification senders to use coordinator (4 files)

## Future Enhancements

**Post-Refactoring Opportunities:**

1. **Test Coverage:** Add unit tests for extracted components (SampleDataGenerator, NotificationCoordinator)
2. **Snapshot Testing:** Add UI tests for EnrichmentBanner states (0%, 50%, 100%, empty title)
3. **Coordinator Pattern:** Evolve NotificationCoordinator into full AppCoordinator owning navigation state
4. **Observable Streams:** Replace NotificationCenter with Combine or AsyncStream publishers for reactive notifications
5. **Feature Modules:** Group Enrichment/, SampleData/, Notifications/ into feature modules with public APIs

## References

**Related Issues:**
- Code audit recommendations (Medium Priority: ContentView decomposition)
- Magic strings in notification handling (Medium Priority: Type safety)
- Inefficient database check (Medium Priority: Performance)

**Related Documentation:**
- `docs/README.md` - Documentation navigation
- `CLAUDE.md` - Swift 6.2 concurrency patterns
- `docs/CONCURRENCY_GUIDE.md` - Actor isolation best practices

**Code Locations:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:280-301` - Magic strings
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:116-117` - Inefficient query
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:243-271` - Verbose notification handling
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:348-439` - EnrichmentBanner definition
