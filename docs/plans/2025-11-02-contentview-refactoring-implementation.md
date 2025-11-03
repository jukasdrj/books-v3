# ContentView Refactoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Decompose ContentView (449 lines) into focused, single-responsibility components while adding type-safe notification payloads and optimizing database queries.

**Architecture:** File-based separation extracting 4 components (EnrichmentBanner, SampleDataGenerator, NotificationCoordinator, NotificationPayloads) with type-safe notification system and environment-injected DTOMapper.

**Tech Stack:** SwiftUI, SwiftData, Swift 6.2 concurrency (@MainActor), iOS 26 patterns

---

## Phase 1: Extract EnrichmentBanner Component

### Task 1: Create EnrichmentBanner.swift

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/UI/EnrichmentBanner.swift`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:348-439`

**Step 1: Create UI directory if needed**

```bash
mkdir -p BooksTrackerPackage/Sources/BooksTrackerFeature/UI
```

**Step 2: Write EnrichmentBanner.swift**

Create `BooksTrackerPackage/Sources/BooksTrackerFeature/UI/EnrichmentBanner.swift`:

```swift
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

**Step 3: Build to verify syntax**

Run: `/build`
Expected: Build succeeds (new file compiles, not yet used)

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/UI/EnrichmentBanner.swift
git commit -m "feat: extract EnrichmentBanner to dedicated file

- Move 92-line banner component from ContentView to UI/EnrichmentBanner.swift
- No functional changes, pure extraction
- Part of ContentView refactoring (Phase 1)"
```

---

### Task 2: Update ContentView to use extracted EnrichmentBanner

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:348-439`

**Step 1: Read current ContentView**

Read `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift` to locate the inline EnrichmentBanner definition (lines 348-439).

**Step 2: Delete inline EnrichmentBanner, keep usage**

In `ContentView.swift`, find and DELETE the private `EnrichmentBanner` struct definition (approximately lines 348-439).

KEEP the usage in the overlay:

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

**Step 3: Build to verify integration**

Run: `/build`
Expected: Build succeeds, EnrichmentBanner imported from UI/EnrichmentBanner.swift

**Step 4: Test on simulator**

Run: `/sim`
Expected:
- App launches successfully
- Trigger enrichment (add books, start enrichment from settings)
- Banner appears at bottom with progress

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift
git commit -m "refactor: use extracted EnrichmentBanner in ContentView

- Remove 92-line inline EnrichmentBanner definition
- Use public EnrichmentBanner from UI/EnrichmentBanner.swift
- ContentView.swift: 449 → 357 lines (-92 lines)
- Part of ContentView refactoring (Phase 1)"
```

---

## Phase 2: Extract SampleDataGenerator Service

### Task 3: Create SampleDataGenerator.swift

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/SampleDataGenerator.swift`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:116-240` (approximate sample data section)

**Step 1: Create Services directory if needed**

```bash
mkdir -p BooksTrackerPackage/Sources/BooksTrackerFeature/Services
```

**Step 2: Write SampleDataGenerator.swift**

Create `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/SampleDataGenerator.swift`:

```swift
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
        // Sample Authors - insert BEFORE relating
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

        // Sample Works - insert BEFORE relating
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

        // Set relationships AFTER insert (insert-before-relate pattern)
        klaraAndTheSun.authors = [kazuoIshiguro]
        kindred.authors = [octaviaButler]
        americanah.authors = [chimamandaNgozi]

        // Sample Editions - insert BEFORE relating
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

        // Link editions to works AFTER insert
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

**Step 3: Build to verify syntax**

Run: `/build`
Expected: Build succeeds (new service compiles, not yet used)

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/SampleDataGenerator.swift
git commit -m "feat: extract SampleDataGenerator to dedicated service

- Move 126-line sample data logic from ContentView
- Optimize isLibraryEmpty() with fetchLimit=1 (no longer fetches all Works)
- Follow insert-before-relate pattern for SwiftData relationships
- Part of ContentView refactoring (Phase 2)"
```

---

### Task 4: Update ContentView to use SampleDataGenerator

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift` (sample data section)

**Step 1: Read ContentView sample data code**

Read `ContentView.swift` to locate the `setupSampleData()` function and its call site.

**Step 2: Delete setupSampleData() function**

In `ContentView.swift`, find and DELETE the entire `setupSampleData()` private function (approximately 124 lines).

**Step 3: Replace .task with SampleDataGenerator call**

Find the `.task` block that calls `setupSampleData()` and replace it:

**Before:**
```swift
.task {
    setupSampleData()
}
```

**After:**
```swift
.task {
    let generator = SampleDataGenerator(modelContext: modelContext)
    generator.setupSampleDataIfNeeded()
}
```

**Step 4: Build to verify integration**

Run: `/build`
Expected: Build succeeds

**Step 5: Test on simulator (fresh install)**

Run:
```bash
# Reset simulator to test first-launch sample data
xcrun simctl boot "iPhone 16"
xcrun simctl erase "iPhone 16"
/sim
```

Expected:
- App launches on empty library
- Sample data appears (3 books: Klara and the Sun, Kindred, Americanah)
- NO duplicate sample data on subsequent launches (relaunch app to verify)

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift
git commit -m "refactor: use SampleDataGenerator in ContentView

- Remove 126-line setupSampleData() function
- Use extracted SampleDataGenerator service
- Optimize library empty check (fetchLimit=1)
- ContentView.swift: 357 → 231 lines (-126 lines)
- Part of ContentView refactoring (Phase 2)"
```

---

## Phase 3: Type-Safe Notification System

### Task 5: Create NotificationPayloads.swift

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/NotificationPayloads.swift`
- Reference: Design doc section 2 (Type-Safe Notification Payloads)

**Step 1: Create Models directory if needed**

```bash
mkdir -p BooksTrackerPackage/Sources/BooksTrackerFeature/Models
```

**Step 2: Write NotificationPayloads.swift**

Create `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/NotificationPayloads.swift`:

```swift
import Foundation

/// Type-safe payload for enrichment start notifications
public struct EnrichmentStartedPayload: Sendable {
    public let totalBooks: Int

    public init(totalBooks: Int) {
        self.totalBooks = totalBooks
    }
}

/// Type-safe payload for enrichment progress notifications
public struct EnrichmentProgressPayload: Sendable {
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
public struct SearchForAuthorPayload: Sendable {
    public let authorName: String

    public init(authorName: String) {
        self.authorName = authorName
    }
}
```

**Step 3: Build to verify syntax**

Run: `/build`
Expected: Build succeeds (new payload types compile)

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Models/NotificationPayloads.swift
git commit -m "feat: add type-safe notification payload structs

- EnrichmentStartedPayload (totalBooks)
- EnrichmentProgressPayload (completed, total, currentTitle)
- SearchForAuthorPayload (authorName)
- All Sendable for Swift 6 concurrency safety
- Part of ContentView refactoring (Phase 3)"
```

---

### Task 6: Create NotificationCoordinator.swift

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/NotificationCoordinator.swift`
- Reference: Design doc section 3 (NotificationCoordinator Service)

**Step 1: Write NotificationCoordinator.swift**

Create `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/NotificationCoordinator.swift`:

```swift
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

    public func postEnrichmentCompleted() {
        NotificationCenter.default.post(
            name: .enrichmentCompleted,
            object: nil
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

    public func postSwitchToLibraryTab() {
        NotificationCenter.default.post(
            name: .switchToLibraryTab,
            object: nil
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

**Step 2: Build to verify syntax**

Run: `/build`
Expected: Build succeeds (coordinator compiles, not yet used)

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/NotificationCoordinator.swift
git commit -m "feat: add NotificationCoordinator for type-safe notifications

- Centralized notification posting with type-safe payloads
- Centralized notification handling (single async stream)
- Type-safe payload extraction helpers
- Part of ContentView refactoring (Phase 3)"
```

---

### Task 7: Update ContentView notification handling

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:243-271` (notification tasks)

**Step 1: Read current notification handling**

Read `ContentView.swift` to locate the 5 separate `.task` blocks handling notifications (approximately lines 243-271).

**Step 2: Add NotificationCoordinator @State property**

In `ContentView`, add after other `@State` properties:

```swift
@State private var notificationCoordinator = NotificationCoordinator()
```

**Step 3: Replace 5 .task blocks with single coordinator call**

Find and DELETE the 5 separate notification `.task` blocks:
- `.task { for await _ in NotificationCenter.default.notifications(named: .switchToLibraryTab) { ... } }`
- `.task { for await notification in NotificationCenter.default.notifications(named: .enrichmentStarted) { ... } }`
- `.task { for await notification in NotificationCenter.default.notifications(named: .enrichmentProgress) { ... } }`
- `.task { for await _ in NotificationCenter.default.notifications(named: .enrichmentCompleted) { ... } }`
- `.task { for await notification in NotificationCenter.default.notifications(named: .searchForAuthor) { ... } }`

REPLACE with single `.task`:

```swift
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

**Step 4: Build to verify syntax**

Run: `/build`
Expected: Build succeeds

**Step 5: Test on simulator (manual notification testing)**

Run: `/sim`
Expected:
- App launches successfully
- Tab switching works
- Enrichment notifications work (test by triggering enrichment)
- Author search notification works (test by tapping author in book details)

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift
git commit -m "refactor: use NotificationCoordinator in ContentView

- Replace 5 separate notification .task blocks with single coordinator call
- Type-safe payload handling (no more magic strings)
- ContentView.swift: 231 → 161 lines (-70 lines)
- Part of ContentView refactoring (Phase 3)"
```

---

### Task 8: Update EnrichmentQueue to use NotificationCoordinator

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- Find: All `NotificationCenter.default.post` calls for enrichment notifications

**Step 1: Read EnrichmentQueue.swift**

Read entire file to locate notification posting code.

**Step 2: Add NotificationCoordinator property**

At top of `EnrichmentQueue` class, add:

```swift
@MainActor private let notificationCoordinator = NotificationCoordinator()
```

**Step 3: Replace enrichmentStarted notification**

Find:
```swift
NotificationCenter.default.post(
    name: .enrichmentStarted,
    object: nil,
    userInfo: ["totalBooks": totalBooks]
)
```

Replace with:
```swift
await notificationCoordinator.postEnrichmentStarted(totalBooks: totalBooks)
```

**Step 4: Replace enrichmentProgress notification**

Find:
```swift
NotificationCenter.default.post(
    name: .enrichmentProgress,
    object: nil,
    userInfo: [
        "completed": completed,
        "total": total,
        "currentTitle": currentTitle
    ]
)
```

Replace with:
```swift
await notificationCoordinator.postEnrichmentProgress(
    completed: completed,
    total: total,
    currentTitle: currentTitle
)
```

**Step 5: Replace enrichmentCompleted notification**

Find:
```swift
NotificationCenter.default.post(
    name: .enrichmentCompleted,
    object: nil
)
```

Replace with:
```swift
await notificationCoordinator.postEnrichmentCompleted()
```

**Step 6: Build to verify syntax**

Run: `/build`
Expected: Build succeeds

**Step 7: Test end-to-end enrichment flow**

Run: `/sim`

Test steps:
1. Add books to library (use search or CSV import)
2. Trigger enrichment (Settings → Library Management → "Enrich All Books")
3. Verify banner appears with progress updates
4. Verify banner shows current book title
5. Verify banner disappears when enrichment completes

Expected: All notifications work with type-safe payloads

**Step 8: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift
git commit -m "refactor: use NotificationCoordinator in EnrichmentQueue

- Replace direct NotificationCenter.default.post calls
- Use type-safe coordinator methods (no magic strings)
- Enrichment progress notifications now use typed payloads
- Part of ContentView refactoring (Phase 3)"
```

---

### Task 9: Update other notification senders (iOS26AdaptiveBookCard, WorkDiscoveryView)

**Files:**
- Find: All files posting .searchForAuthor or .switchToLibraryTab notifications
- Modify: Replace with NotificationCoordinator calls

**Step 1: Search for searchForAuthor notification senders**

Run:
```bash
ast-grep --lang swift --pattern 'NotificationCenter.default.post(name: .searchForAuthor, $$$)' BooksTrackerPackage/Sources/BooksTrackerFeature/
```

Expected: Find all files posting searchForAuthor notifications

**Step 2: Search for switchToLibraryTab notification senders**

Run:
```bash
ast-grep --lang swift --pattern 'NotificationCenter.default.post(name: .switchToLibraryTab, $$$)' BooksTrackerPackage/Sources/BooksTrackerFeature/
```

Expected: Find all files posting switchToLibraryTab notifications

**Step 3: Update each file found**

For EACH file found:
1. Add `@MainActor private let notificationCoordinator = NotificationCoordinator()` property (if class/actor)
   OR create local instance `let coordinator = NotificationCoordinator()` (if function scope)
2. Replace `NotificationCenter.default.post(name: .searchForAuthor, object: nil, userInfo: ["authorName": name])`
   with `await coordinator.postSearchForAuthor(authorName: name)`
3. Replace `NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)`
   with `await coordinator.postSwitchToLibraryTab()`

**Step 4: Build to verify all files updated**

Run: `/build`
Expected: Build succeeds, zero warnings

**Step 5: Test notification senders**

Run: `/sim`

Test steps:
1. Find book with author link (e.g., book detail view)
2. Tap author name
3. Verify switches to Search tab and searches for author

Expected: Author search navigation works

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/
git commit -m "refactor: migrate all notification senders to NotificationCoordinator

- Update iOS26AdaptiveBookCard, WorkDiscoveryView (and others found)
- Replace magic string userInfo dictionaries with type-safe coordinator
- Eliminate all remaining NotificationCenter.default.post calls
- Part of ContentView refactoring (Phase 3)"
```

---

## Phase 4: DTOMapper Environment Injection

### Task 10: Add DTOMapper environment key

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift` (add extension at end)
- OR Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Extensions/EnvironmentValues+DTOMapper.swift`

**Step 1: Read DTOMapper.swift to determine best location**

Read `DTOMapper.swift` to see if it has environment extensions already.

**Step 2: Add EnvironmentKey extension**

At END of `DTOMapper.swift` (or in new file), add:

```swift
// MARK: - Environment Injection

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

**Step 3: Build to verify syntax**

Run: `/build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift
git commit -m "feat: add DTOMapper environment key

- EnvironmentKey + EnvironmentValues extension
- Enables dependency injection via .environment(\.dtoMapper, ...)
- Part of ContentView refactoring (Phase 4)"
```

---

### Task 11: Update BooksTrackerApp to inject DTOMapper

**Files:**
- Modify: `BooksTracker/BooksTrackerApp.swift`

**Step 1: Read BooksTrackerApp.swift**

Read entire file to understand current initialization.

**Step 2: Add DTOMapper property**

In `BooksTrackerApp`, add property after `modelContainer`:

```swift
let dtoMapper: DTOMapper
```

**Step 3: Initialize DTOMapper in init()**

In `init()`, AFTER `modelContainer` is created, add:

```swift
// Create DTOMapper with main context
self.dtoMapper = DTOMapper(modelContext: modelContainer.mainContext)
```

**Step 4: Inject DTOMapper in environment**

In `body`, add `.environment(\.dtoMapper, dtoMapper)` after other environment modifiers:

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .modelContainer(modelContainer)
            .environment(themeStore)
            .environment(featureFlags)
            .environment(\.dtoMapper, dtoMapper)  // NEW
    }
}
```

**Step 5: Build to verify syntax**

Run: `/build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add BooksTracker/BooksTrackerApp.swift
git commit -m "feat: create and inject DTOMapper at app launch

- Initialize DTOMapper with main context in BooksTrackerApp.init()
- Inject via environment (.environment(\.dtoMapper, dtoMapper))
- Eliminates need for ContentView to create DTOMapper
- Part of ContentView refactoring (Phase 4)"
```

---

### Task 12: Update ContentView to use environment DTOMapper

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift`

**Step 1: Read ContentView DTOMapper setup**

Read `ContentView.swift` to locate:
- `@State private var dtoMapper: DTOMapper?` property
- `setupDTOMapper()` function
- `.onAppear(perform: setupDTOMapper)` call
- `if let dtoMapper = dtoMapper { ... } else { ProgressView() }` wrapper

**Step 2: Replace @State property with @Environment**

Find:
```swift
@State private var dtoMapper: DTOMapper?
```

Replace with:
```swift
@Environment(\.dtoMapper) private var dtoMapper
```

**Step 3: Remove setupDTOMapper() function**

Find and DELETE entire `setupDTOMapper()` private function.

**Step 4: Remove .onAppear(perform: setupDTOMapper)**

Find and DELETE `.onAppear(perform: setupDTOMapper)` modifier.

**Step 5: Unwrap body's if let wrapper**

Find:
```swift
public var body: some View {
    if let dtoMapper = dtoMapper {
        TabView(selection: $selectedTab) { ... }
            .environment(\.dtoMapper, dtoMapper)
    } else {
        ProgressView()
    }
}
```

Replace with:
```swift
public var body: some View {
    TabView(selection: $selectedTab) { ... }
        .environment(\.dtoMapper, dtoMapper!)  // Force-unwrap safe (app guarantees injection)
}
```

**Step 6: Build to verify syntax**

Run: `/build`
Expected: Build succeeds

**Step 7: Test app launch (verify no ProgressView flash)**

Run: `/sim`

Expected:
- App launches directly to TabView (NO brief ProgressView flash)
- All tabs work correctly
- Search functionality works (uses DTOMapper)

**Step 8: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift
git commit -m "refactor: use environment-injected DTOMapper in ContentView

- Replace @State optional DTOMapper with @Environment
- Remove setupDTOMapper() function and .onAppear setup
- Remove if let wrapper and ProgressView fallback
- ContentView.swift: 161 → ~120 lines (-41 lines)
- Eliminates ProgressView flash on app launch
- Part of ContentView refactoring (Phase 4)"
```

---

## Phase 5: Final Verification & Documentation

### Task 13: Run comprehensive manual tests

**Files:**
- Test: Full app flow on simulator

**Step 1: Clean build**

Run:
```bash
/build
```

Expected: Zero warnings, zero errors

**Step 2: Test sample data (fresh install)**

Run:
```bash
xcrun simctl boot "iPhone 16"
xcrun simctl erase "iPhone 16"
/sim
```

Expected:
- App launches without ProgressView flash
- Sample data appears (3 books)
- Relaunch app → sample data does NOT duplicate

**Step 3: Test enrichment notifications**

Run: `/sim`

Steps:
1. Add book via search (any book)
2. Settings → Library Management → "Enrich All Books"
3. Observe enrichment banner appears
4. Verify progress updates (0/4 → 1/4 → 2/4 → 3/4 → 4/4)
5. Verify current book title updates
6. Verify banner disappears when complete

Expected: All enrichment UI works correctly

**Step 4: Test author search notification**

Steps:
1. Open any book detail view
2. Tap author name
3. Verify switches to Search tab
4. Verify searches for author

Expected: Author search navigation works

**Step 5: Test tab switching**

Steps:
1. Navigate through all 4 tabs (Library, Search, Shelf, Insights)
2. Verify no crashes or layout issues

Expected: All tabs render correctly

**Step 6: Verify zero warnings**

Run:
```bash
/build
```

Expected: Zero warnings (Swift 6 concurrency, deprecated APIs)

**Step 7: Document test results**

If ALL tests pass, proceed to next step.
If ANY test fails, investigate and fix before committing.

---

### Task 14: Update ContentView file header comment

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift:1-10`

**Step 1: Read current file header**

Read top of `ContentView.swift` to see current comment structure.

**Step 2: Add refactoring note**

At top of file (after existing copyright/description), add:

```swift
/// Main app container with tab navigation and enrichment progress UI.
///
/// **Architecture:**
/// - Orchestrates 4-tab layout (Library, Search, Shelf, Insights)
/// - Enrichment progress UI via extracted EnrichmentBanner component
/// - Type-safe notifications via NotificationCoordinator
/// - Sample data via SampleDataGenerator service
/// - Environment-injected DTOMapper (no optional state)
///
/// **Refactoring History:**
/// - Nov 2, 2025: Reduced from 449 → 120 lines (-73%)
///   - Extracted EnrichmentBanner → UI/EnrichmentBanner.swift
///   - Extracted SampleDataGenerator → Services/SampleDataGenerator.swift
///   - Migrated to type-safe NotificationCoordinator
///   - Migrated to environment-injected DTOMapper
```

**Step 3: Commit documentation**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift
git commit -m "docs: add ContentView refactoring header comment

- Document architecture and component extraction
- Record line count reduction (449 → 120 lines)
- Reference extracted components and services
- Part of ContentView refactoring (Phase 5)"
```

---

### Task 15: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

**Step 1: Read current CHANGELOG structure**

Read `CHANGELOG.md` to understand versioning format.

**Step 2: Add refactoring entry**

Under latest version (or create new "Unreleased" section), add:

```markdown
### Refactoring

**ContentView Decomposition (Issue #XXX)**
- Reduced ContentView from 449 → 120 lines (-73% reduction)
- Extracted components:
  - `UI/EnrichmentBanner.swift` - Glass effect progress banner (92 lines)
  - `Services/SampleDataGenerator.swift` - Sample data with optimized DB check (126 lines)
  - `Services/NotificationCoordinator.swift` - Type-safe notification routing (80 lines)
  - `Models/NotificationPayloads.swift` - Compile-time safe payloads (60 lines)
- **Type Safety:** Replaced magic string `userInfo` dictionaries with structured payloads (prevents silent runtime failures)
- **Performance:** Optimized sample data check (`fetchLimit=1` instead of fetching all Works)
- **UX:** Eliminated ProgressView flash on launch (DTOMapper now environment-injected)
- **Architecture:** Clear separation of concerns (UI, business logic, coordination)
```

**Step 3: Commit CHANGELOG**

```bash
git add CHANGELOG.md
git commit -m "docs: add ContentView refactoring to CHANGELOG

- Record 73% line reduction and component extraction
- Document type safety improvements
- Note performance optimization (fetchLimit=1)
- Part of ContentView refactoring (Phase 5)"
```

---

### Task 16: Create GitHub PR (if using feature branch)

**Files:**
- N/A (Git operations only)

**Step 1: Verify all commits**

Run:
```bash
git log --oneline -16
```

Expected: See all 16 commit messages from this plan

**Step 2: Push feature branch**

```bash
git push -u origin feature/contentview-refactoring
```

**Step 3: Create pull request**

Run:
```bash
gh pr create --title "Refactor ContentView: 73% reduction via component extraction" --body "$(cat <<'EOF'
## Summary

Decomposes ContentView (449 → 120 lines) into focused, single-responsibility components:

- **EnrichmentBanner** → `UI/EnrichmentBanner.swift` (92 lines)
- **SampleDataGenerator** → `Services/SampleDataGenerator.swift` (126 lines)
- **NotificationCoordinator** → `Services/NotificationCoordinator.swift` (80 lines)
- **NotificationPayloads** → `Models/NotificationPayloads.swift` (60 lines)

## Key Improvements

✅ **Type Safety**: Replaced magic string `userInfo` dictionaries with compile-time safe payloads
✅ **Performance**: Optimized `isLibraryEmpty()` with `fetchLimit=1` (no longer fetches all Works)
✅ **UX**: Eliminated ProgressView flash on launch (DTOMapper environment-injected)
✅ **Maintainability**: Clear separation of concerns (UI, business logic, coordination)

## Testing

- ✅ Zero warnings (Swift 6 concurrency compliance)
- ✅ Sample data works (fresh install + no duplication)
- ✅ Enrichment notifications work (banner shows progress)
- ✅ Author search navigation works (tap author → Search tab)
- ✅ No ProgressView flash on app launch

## Commits

16 atomic commits following TDD workflow (see commit history)

Closes #XXX (update with actual issue number)
EOF
)"
```

**Step 4: Mark PR ready for review**

Expected: PR created successfully with all 16 commits

---

## Rollback Plan

Each phase is independent. If issues arise:

**Phase 1 (EnrichmentBanner):** Revert Task 1-2 commits
**Phase 2 (SampleDataGenerator):** Revert Task 3-4 commits
**Phase 3 (NotificationCoordinator):** Revert Task 5-9 commits
**Phase 4 (DTOMapper):** Revert Task 10-12 commits
**Phase 5 (Documentation):** Revert Task 13-16 commits (docs only, no risk)

**Full Rollback:**
```bash
git reset --hard HEAD~16  # Reverts all 16 commits
```

---

## Success Criteria

- ✅ ContentView reduced from 449 → ~120 lines (-73%)
- ✅ Zero compiler warnings (Swift 6 concurrency, deprecated APIs)
- ✅ All manual tests pass (sample data, enrichment, navigation)
- ✅ No ProgressView flash on app launch
- ✅ Type-safe notifications (compile errors for typos, not runtime failures)
- ✅ Optimized sample data check (fetchLimit=1)
- ✅ 16 atomic commits with clear history

---

## Post-Implementation

After merging, consider:

1. **Add unit tests** for `SampleDataGenerator.isLibraryEmpty()` (verify fetchLimit behavior)
2. **Add unit tests** for `NotificationCoordinator` payload extraction (verify type safety)
3. **Add snapshot tests** for `EnrichmentBanner` UI states (0%, 50%, 100%)
4. **Evolve NotificationCoordinator** into full AppCoordinator owning navigation state (future refactoring)
