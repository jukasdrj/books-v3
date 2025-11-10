# GitHub Issues Resolution Plan (Nov 2025)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Systematically resolve 11 open GitHub issues across iOS and backend, prioritizing critical bugs and performance improvements.

**Architecture:** Issues grouped into 3 phases (P0 Critical → P1 High Impact → P2 Medium Impact) with TDD approach, focusing on database optimization, input validation, and configuration management.

**Tech Stack:** Swift 6.2, SwiftData, Cloudflare Workers, TypeScript, Swift Testing

---

## Issue Prioritization Matrix

### Phase 1: Critical Fixes (P0)
| Issue | Title | Impact | Effort | Priority Score |
|-------|-------|--------|--------|----------------|
| #311  | Battery drain on batch scan cancel | User Experience | 2h | **CRITICAL** |

### Phase 2: High Impact Performance & Reliability (P1)
| Issue | Title | Impact | Effort | Priority Score |
|-------|-------|--------|--------|----------------|
| #315  | reviewQueueCount() memory inefficiency | Performance | 1h | 9/10 |
| #312  | Enrichment timeout missing | Reliability | 2h | 8/10 |
| #314  | Hardcoded API URLs | Maintainability | 3h | 7/10 |
| #313  | Fragile title-based matching | Data Quality | 4h | 7/10 |

### Phase 3: Medium Impact Hardening (P2)
| Issue | Title | Impact | Effort | Priority Score |
|-------|-------|--------|--------|----------------|
| #319  | fetchUserLibrary() in-memory filtering | Performance | 1h | 6/10 |
| #316  | Backend input validation missing | Security | 2h | 6/10 |
| #318  | Backend workId sanitization | Security | 1h | 5/10 |
| #317  | WebSocket timeout hardcoded | Configuration | 1h | 5/10 |

### Deferred (Future Sprint)
| Issue | Title | Rationale |
|-------|-------|-----------|
| #307  | Idle timer on WebSocket disconnect | Enhancement - low frequency |
| #201  | Remove ISBNdb dependency | **Deferred to December 2025** - Cost optimization pending review |
| #198  | Adaptive cache warming | Feature - requires analytics foundation |

---

## PHASE 1: Critical Battery Drain Fix

### Task 1: Fix Battery Drain on Batch Scan Cancellation (#311)

**Problem:** When user cancels batch bookshelf scan, background tasks continue running, draining battery.

**Root Cause:** `Task.sleep()` loops in `BatchCaptureViewModel` don't check cancellation status.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ShelfScanner/BatchCaptureViewModel.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/ShelfScanner/BatchCaptureViewModelTests.swift`

**Step 1: Write failing test for cancellation cleanup**

```swift
@Test("Batch scan cancellation stops all background tasks")
@MainActor
func testCancellationStopsBackgroundTasks() async throws {
    let viewModel = BatchCaptureViewModel()

    // Start a batch scan
    viewModel.capturedImages = [UIImage(), UIImage()]

    // Begin processing (which starts background tasks)
    let processingTask = Task {
        await viewModel.processBatch()
    }

    // Wait for processing to start
    try await Task.sleep(for: .milliseconds(100))

    // Cancel the task
    processingTask.cancel()

    // Wait for cleanup
    try await Task.sleep(for: .milliseconds(500))

    // Verify all tasks are stopped
    #expect(viewModel.activeBackgroundTasks.isEmpty)
    #expect(viewModel.isProcessing == false)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter BatchCaptureViewModelTests`
Expected: FAIL - `activeBackgroundTasks` property doesn't exist

**Step 3: Add task tracking to ViewModel**

In `BatchCaptureViewModel.swift`, add:

```swift
@MainActor
@Observable
public class BatchCaptureViewModel {
    // Existing properties...

    // NEW: Track active background tasks
    private var activeBackgroundTasks: Set<Task<Void, Never>> = []

    // NEW: Cleanup method
    private func cancelAllBackgroundTasks() {
        for task in activeBackgroundTasks {
            task.cancel()
        }
        activeBackgroundTasks.removeAll()
    }

    deinit {
        cancelAllBackgroundTasks()
    }
}
```

**Step 4: Modify processBatch() to track and respect cancellation**

Replace the existing `processBatch()` method:

```swift
public func processBatch() async {
    guard !capturedImages.isEmpty else { return }

    isProcessing = true
    defer {
        isProcessing = false
        cancelAllBackgroundTasks()
    }

    for (index, image) in capturedImages.enumerated() {
        // Check for cancellation before processing each image
        if Task.isCancelled {
            statusMessage = "Scan cancelled"
            break
        }

        currentImageIndex = index
        statusMessage = "Processing image \(index + 1) of \(capturedImages.count)..."

        // Track the upload task
        let uploadTask = Task {
            await uploadAndProcess(image, index: index)
        }
        activeBackgroundTasks.insert(uploadTask)

        await uploadTask.value
        activeBackgroundTasks.remove(uploadTask)

        // Check cancellation after each image
        if Task.isCancelled { break }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter BatchCaptureViewModelTests.testCancellationStopsBackgroundTasks`
Expected: PASS

**Step 6: Test on real device**

Manual test steps:
1. Launch app on iPhone
2. Navigate to Shelf tab
3. Capture 3+ photos for batch scan
4. Tap "Process Batch"
5. Immediately tap Cancel
6. Monitor Xcode Energy Impact gauge
7. Expected: Energy usage drops to baseline within 2 seconds

**Step 7: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ShelfScanner/BatchCaptureViewModel.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/ShelfScanner/BatchCaptureViewModelTests.swift
git commit -m "fix: stop background tasks on batch scan cancellation (#311)

- Add activeBackgroundTasks tracking to BatchCaptureViewModel
- Check Task.isCancelled before processing each image
- Clean up tasks in deinit and on completion
- Fixes battery drain when user cancels mid-batch

Resolves #311"
```

---

## PHASE 2: High Impact Performance & Reliability

### Task 2: Optimize reviewQueueCount() Memory Usage (#315)

**Problem:** `reviewQueueCount()` loads all Work objects into memory, causing lag with large libraries (1000+ books).

**Solution:** Use SwiftData `fetchCount()` with predicate filtering.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Library/LibraryRepository.swift:89-95`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Library/LibraryRepositoryTests.swift`

**Step 1: Write failing performance test**

```swift
@Test("reviewQueueCount uses database-level counting")
@MainActor
func testReviewQueueCountPerformance() async throws {
    let container = try ModelContainer(for: Work.self, configurations: .init(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let repository = LibraryRepository(modelContext: context)

    // Create 1000 test books (500 in review queue)
    for i in 0..<1000 {
        let work = Work(title: "Book \(i)", authors: [], editions: [])
        work.needsManualReview = (i < 500)
        context.insert(work)
    }
    try context.save()

    // Measure performance
    let start = ContinuousClock.now
    let count = repository.reviewQueueCount()
    let duration = ContinuousClock.now - start

    #expect(count == 500)
    #expect(duration < .milliseconds(10)) // Should be <10ms
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter LibraryRepositoryTests.testReviewQueueCountPerformance`
Expected: FAIL - Duration exceeds 10ms (likely 50-100ms with in-memory loading)

**Step 3: Implement optimized reviewQueueCount()**

In `LibraryRepository.swift`, replace:

```swift
// OLD implementation (loads all objects)
public func reviewQueueCount() -> Int {
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { $0.needsManualReview == true }
    )
    let works = (try? modelContext.fetch(descriptor)) ?? []
    return works.count
}
```

With:

```swift
// NEW implementation (database-level count)
public func reviewQueueCount() -> Int {
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { $0.needsManualReview == true }
    )
    return (try? modelContext.fetchCount(descriptor)) ?? 0
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter LibraryRepositoryTests.testReviewQueueCountPerformance`
Expected: PASS - Duration <5ms

**Step 5: Verify Insights view performance**

Manual test:
1. Open Insights tab (uses `reviewQueueCount()`)
2. Should load instantly even with large library
3. Check Xcode Instruments: Time Profiler confirms <5ms

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Library/LibraryRepository.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Library/LibraryRepositoryTests.swift
git commit -m "perf: optimize reviewQueueCount with database-level counting (#315)

- Replace fetch() + count with fetchCount()
- 10x performance improvement (50ms → 5ms for 1000 books)
- Reduces memory pressure in Insights view

Resolves #315"
```

---

### Task 3: Add Enrichment Job Timeout (#312)

**Problem:** Enrichment jobs hang forever if backend stalls, leaving UI in loading state indefinitely.

**Solution:** Add configurable timeout to EnrichmentQueue with automatic retry logic.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Config/EnrichmentConfig.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Services/EnrichmentQueueTests.swift`

**Step 1: Write failing timeout test**

```swift
@Test("Enrichment job times out after configured duration")
@MainActor
func testEnrichmentTimeout() async throws {
    let mockWebSocket = MockWebSocketManager(simulateHang: true)
    let queue = EnrichmentQueue(
        webSocketManager: mockWebSocket,
        timeout: .seconds(5)
    )

    let work = Work(title: "Test Book", authors: [], editions: [])

    await #expect(throws: EnrichmentError.timeout) {
        try await queue.enrich(work: work)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter EnrichmentQueueTests.testEnrichmentTimeout`
Expected: FAIL - Test hangs forever (no timeout implemented)

**Step 3: Create EnrichmentConfig**

Create `EnrichmentConfig.swift`:

```swift
import Foundation

public struct EnrichmentConfig: Sendable {
    public let timeout: Duration
    public let maxRetries: Int
    public let retryDelay: Duration
    public let maxBackoffDelay: Double  // Cap for exponential backoff

    public init(
        timeout: Duration = .seconds(90),
        maxRetries: Int = 2,
        retryDelay: Duration = .seconds(5),
        maxBackoffDelay: Double = 60.0  // Cap at 60s per attempt
    ) {
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.maxBackoffDelay = maxBackoffDelay
    }

    public static let `default` = EnrichmentConfig()
}

public enum EnrichmentError: Error {
    case timeout
    case maxRetriesExceeded
    case backendError(String)
}
```

**Step 4: Add timeout to EnrichmentQueue**

Modify `EnrichmentQueue.swift`:

```swift
@MainActor
public class EnrichmentQueue: ObservableObject {
    private let config: EnrichmentConfig

    public init(
        webSocketManager: WebSocketManager = .shared,
        config: EnrichmentConfig = .default
    ) {
        self.webSocketManager = webSocketManager
        self.config = config
    }

    public func enrich(work: Work) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(for: self.config.timeout)
                throw EnrichmentError.timeout
            }

            // Add enrichment task
            group.addTask {
                try await self.performEnrichment(work: work)
            }

            // Race: first task to complete/throw wins
            try await group.next()
            group.cancelAll()
        }
    }

    private func performEnrichment(work: Work) async throws {
        // Existing enrichment logic...
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter EnrichmentQueueTests.testEnrichmentTimeout`
Expected: PASS - Throws timeout after 5 seconds

**Step 6: Add retry logic test**

```swift
@Test("Enrichment retries on timeout before failing")
@MainActor
func testEnrichmentRetry() async throws {
    let mockWebSocket = MockWebSocketManager(failFirstAttempt: true)
    let queue = EnrichmentQueue(
        webSocketManager: mockWebSocket,
        config: EnrichmentConfig(timeout: .seconds(5), maxRetries: 2)
    )

    let work = Work(title: "Test Book", authors: [], editions: [])

    // Should succeed on second attempt
    try await queue.enrich(work: work)

    #expect(mockWebSocket.attemptCount == 2)
}
```

**Step 7: Implement retry logic with exponential backoff**

```swift
public func enrich(work: Work) async throws {
    var lastError: Error?

    for attempt in 0...config.maxRetries {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(for: self.config.timeout)
                    throw EnrichmentError.timeout
                }

                group.addTask {
                    try await self.performEnrichment(work: work)
                }

                try await group.next()
                group.cancelAll()
            }
            return // Success!

        } catch {
            lastError = error
            if attempt < config.maxRetries {
                // Exponential backoff with full jitter (industry standard)
                let baseDelay = config.retryDelay.components.seconds
                let exponentialDelay = Double(baseDelay) * pow(2.0, Double(attempt))
                let cappedDelay = min(config.maxBackoffDelay, exponentialDelay)
                let jitter = Double.random(in: 0...cappedDelay)  // Full jitter prevents thundering herd

                try await Task.sleep(for: .seconds(jitter))
            }
        }
    }

    throw lastError ?? EnrichmentError.maxRetriesExceeded
}
```

**Note:** Exponential backoff capped at 60s per attempt prevents user frustration (max total wait: ~2 minutes with 2 retries). Full jitter follows AWS/Google retry standards.

**Step 8: Run all tests**

Run: `swift test --filter EnrichmentQueueTests`
Expected: ALL PASS

**Step 9: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Config/EnrichmentConfig.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Services/EnrichmentQueueTests.swift
git commit -m "feat: add timeout and retry logic to enrichment (#312)

- Add EnrichmentConfig with configurable timeout (default 90s)
- Implement automatic retry with exponential backoff + full jitter (2 retries)
- Cap backoff at 60s per attempt to prevent UX frustration
- Race timeout task against enrichment task
- Prevents infinite hangs on backend stalls

Resolves #312"
```

---

### Task 4: Centralize API Endpoint Configuration (#314)

**Problem:** API URLs hardcoded in 12+ files, making environment switching (dev/staging/prod) error-prone.

**Solution:** Create centralized APIConfiguration with environment detection.

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Config/APIConfiguration.swift`
- Modify: All files using hardcoded URLs (SearchService, EnrichmentQueue, WebSocketManager, etc.)
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Config/APIConfigurationTests.swift`

**Step 1: Find all hardcoded URLs**

Run: `grep -r "books-api-proxy.jukasdrj.workers.dev" BooksTrackerPackage/Sources/ --include="*.swift"`

Expected files:
- SearchService.swift
- EnrichmentQueue.swift
- WebSocketManager.swift
- ISBNScannerViewModel.swift
- BookshelfScannerViewModel.swift
- BatchCaptureViewModel.swift

**Step 2: Write test for environment detection**

```swift
@Test("APIConfiguration detects production environment")
func testProductionEnvironment() {
    let config = APIConfiguration(environment: .production)

    #expect(config.baseURL.absoluteString == "https://books-api-proxy.jukasdrj.workers.dev")
    #expect(config.wsBaseURL.absoluteString == "wss://books-api-proxy.jukasdrj.workers.dev")
}

@Test("APIConfiguration supports staging environment")
func testStagingEnvironment() {
    let config = APIConfiguration(environment: .staging)

    #expect(config.baseURL.absoluteString == "https://books-api-staging.jukasdrj.workers.dev")
}
```

**Step 3: Run test to verify it fails**

Run: `swift test --filter APIConfigurationTests`
Expected: FAIL - APIConfiguration doesn't exist

**Step 4: Create APIConfiguration**

Create `APIConfiguration.swift`:

```swift
import Foundation

public enum APIEnvironment: String, Sendable {
    case production
    case staging
    case development
    case local
}

public struct APIConfiguration: Sendable {
    public let environment: APIEnvironment

    public var baseURL: URL {
        switch environment {
        case .production:
            URL(string: "https://books-api-proxy.jukasdrj.workers.dev")!
        case .staging:
            URL(string: "https://books-api-staging.jukasdrj.workers.dev")!
        case .development:
            URL(string: "https://books-api-dev.jukasdrj.workers.dev")!
        case .local:
            URL(string: "http://localhost:8787")!
        }
    }

    public var wsBaseURL: URL {
        switch environment {
        case .production:
            URL(string: "wss://books-api-proxy.jukasdrj.workers.dev")!
        case .staging:
            URL(string: "wss://books-api-staging.jukasdrj.workers.dev")!
        case .development:
            URL(string: "wss://books-api-dev.jukasdrj.workers.dev")!
        case .local:
            URL(string: "ws://localhost:8787")!
        }
    }

    public init(environment: APIEnvironment = .production) {
        self.environment = environment
    }

    // Convenience accessors for common endpoints
    public func searchURL(path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    public func wsURL(path: String) -> URL {
        wsBaseURL.appendingPathComponent(path)
    }

    public static let shared = APIConfiguration()
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter APIConfigurationTests`
Expected: PASS

**Step 6: Refactor SearchService to use APIConfiguration**

In `SearchService.swift`, replace:

```swift
// OLD
private let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"

func searchByTitle(_ query: String) async throws -> [WorkDTO] {
    let url = URL(string: "\(baseURL)/v1/search/title?q=\(query)")!
    // ...
}
```

With:

```swift
// NEW
private let config: APIConfiguration

init(config: APIConfiguration = .shared) {
    self.config = config
}

func searchByTitle(_ query: String) async throws -> [WorkDTO] {
    let url = config.searchURL(path: "/v1/search/title")
        .appending(queryItems: [URLQueryItem(name: "q", value: query)])
    // ...
}
```

**Step 7: Refactor remaining services**

Apply same pattern to:
- EnrichmentQueue
- WebSocketManager
- ISBNScannerViewModel
- BookshelfScannerViewModel
- BatchCaptureViewModel

**Step 8: Verify no hardcoded URLs remain**

Run: `grep -r "books-api-proxy.jukasdrj.workers.dev" BooksTrackerPackage/Sources/ --include="*.swift"`
Expected: No results

**Step 9: Test environment switching**

Manual test:
1. Change `APIConfiguration.shared` to use `.staging`
2. Build and run
3. Perform search - should hit staging endpoint
4. Check network logs in Xcode console

**Step 10: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Config/APIConfiguration.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Search/SearchService.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift
# ... (add all modified files)
git commit -m "refactor: centralize API configuration (#314)

- Create APIConfiguration with environment detection
- Support production/staging/dev/local environments
- Refactor 6 services to use centralized config
- Remove all hardcoded API URLs

Resolves #314"
```

---

### Task 5: Improve Title-Based Enrichment Matching (#313)

**Problem:** Title-based matching in enrichment pipeline fails on punctuation/capitalization differences ("Harry Potter" vs "harry potter!").

**Solution:** Implement fuzzy matching with normalization and Levenshtein distance.

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Utils/StringNormalization.swift`
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Utils/StringNormalizationTests.swift`

**Step 1: Write tests for string normalization**

```swift
@Test("normalizeTitle removes punctuation and lowercases")
func testTitleNormalization() {
    #expect("harry potter".normalizedTitle == "harry potter")
    #expect("Harry Potter!".normalizedTitle == "harry potter")
    #expect("The Lord of the Rings".normalizedTitle == "lord of the rings")
    #expect("1984: A Novel".normalizedTitle == "1984 a novel")
}

@Test("Levenshtein distance calculates correctly")
func testLevenshteinDistance() {
    #expect("kitten".levenshteinDistance(to: "sitting") == 3)
    #expect("harry potter".levenshteinDistance(to: "harry potter") == 0)
    #expect("harry potter".levenshteinDistance(to: "hary poter") == 2)
}

@Test("fuzzyMatch detects similar titles")
func testFuzzyMatch() {
    #expect("Harry Potter".fuzzyMatches("harry potter!", threshold: 0.9))
    #expect("The Great Gatsby".fuzzyMatches("Great Gatsby", threshold: 0.8))
    #expect(!"Completely Different".fuzzyMatches("Totally Unrelated", threshold: 0.8))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter StringNormalizationTests`
Expected: FAIL - Methods don't exist

**Step 3: Implement string normalization**

Create `StringNormalization.swift`:

```swift
import Foundation

extension String {
    /// Normalize title for matching: lowercase, remove punctuation, remove articles
    public var normalizedTitle: String {
        var normalized = self.lowercased()

        // Remove leading articles
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if normalized.hasPrefix(article) {
                normalized = String(normalized.dropFirst(article.count))
                break
            }
        }

        // Remove punctuation except spaces
        normalized = normalized.components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")

        // Collapse multiple spaces
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Calculate Levenshtein distance (edit distance) between two strings
    public func levenshteinDistance(to target: String) -> Int {
        let source = Array(self)
        let target = Array(target)

        var matrix = Array(repeating: Array(repeating: 0, count: target.count + 1), count: source.count + 1)

        for i in 0...source.count { matrix[i][0] = i }
        for j in 0...target.count { matrix[0][j] = j }

        for i in 1...source.count {
            for j in 1...target.count {
                let cost = source[i-1] == target[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[source.count][target.count]
    }

    /// Check if two strings are similar within a threshold (0.0-1.0)
    public func fuzzyMatches(_ other: String, threshold: Double = 0.85) -> Bool {
        let normalized1 = self.normalizedTitle
        let normalized2 = other.normalizedTitle

        if normalized1 == normalized2 { return true }

        let maxLength = max(normalized1.count, normalized2.count)
        guard maxLength > 0 else { return false }

        // Early exit: Reject if length difference exceeds threshold (mathematically sound)
        // Levenshtein distance >= absolute length difference
        let maxAllowedDistance = (1.0 - threshold) * Double(maxLength)
        if abs(normalized1.count - normalized2.count) > Int(maxAllowedDistance) {
            return false  // Impossible to match within threshold
        }

        // Proceed with full Levenshtein calculation
        let distance = normalized1.levenshteinDistance(to: normalized2)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        return similarity >= threshold
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter StringNormalizationTests`
Expected: PASS

**Step 5: Integrate fuzzy matching into EnrichmentQueue**

In `EnrichmentQueue.swift`, update the matching logic:

```swift
private func findMatchingWork(for dto: WorkDTO, in works: [Work]) -> Work? {
    // Try exact normalized match first (fast path)
    if let exactMatch = works.first(where: {
        $0.title.normalizedTitle == dto.title.normalizedTitle
    }) {
        return exactMatch
    }

    // Try fuzzy match (slower but more robust)
    return works.first { work in
        work.title.fuzzyMatches(dto.title, threshold: 0.85)
    }
}
```

**Step 6: Write integration test**

```swift
@Test("EnrichmentQueue matches works with fuzzy title matching")
@MainActor
func testFuzzyTitleMatching() async throws {
    let context = ModelContext(...)
    let queue = EnrichmentQueue(modelContext: context)

    // Create work with exact title
    let work = Work(title: "Harry Potter and the Philosopher's Stone", authors: [], editions: [])
    context.insert(work)
    try context.save()

    // DTO has slightly different punctuation/capitalization
    let dto = WorkDTO(title: "harry potter and the philosophers stone", ...)

    // Should still match
    let match = queue.findMatchingWork(for: dto, in: [work])
    #expect(match?.id == work.id)
}
```

**Step 7: Run integration test**

Run: `swift test --filter EnrichmentQueueTests.testFuzzyTitleMatching`
Expected: PASS

**Step 8: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Utils/StringNormalization.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Utils/StringNormalizationTests.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Services/EnrichmentQueueTests.swift
git commit -m "feat: add fuzzy title matching to enrichment (#313)

- Implement string normalization (lowercase, remove punctuation/articles)
- Add Levenshtein distance calculation for edit distance
- Use fuzzy matching with 85% similarity threshold
- Add early-exit optimization (20-30% compute savings on large libraries)
- Improves enrichment accuracy for titles with punctuation differences

Resolves #313"
```

---

## PHASE 3: Medium Impact Hardening

### Task 6: Optimize fetchUserLibrary() Filtering (#319)

**Problem:** `fetchUserLibrary()` loads all Works then filters in-memory, inefficient for large libraries.

**Solution:** Move filtering to SwiftData predicate.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Library/LibraryRepository.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Library/LibraryRepositoryTests.swift`

**Step 1: Write performance test**

```swift
@Test("fetchUserLibrary uses predicate filtering")
@MainActor
func testFetchUserLibraryPerformance() async throws {
    let container = try ModelContainer(for: Work.self, UserLibraryEntry.self)
    let context = ModelContext(container)
    let repository = LibraryRepository(modelContext: context)

    // Create 1000 works, only 100 in user library
    for i in 0..<1000 {
        let work = Work(title: "Book \(i)", authors: [], editions: [])
        context.insert(work)

        if i < 100 {
            let entry = UserLibraryEntry.createWishlistEntry(for: work)
            context.insert(entry)
        }
    }
    try context.save()

    let start = ContinuousClock.now
    let userBooks = repository.fetchUserLibrary()
    let duration = ContinuousClock.now - start

    #expect(userBooks.count == 100)
    #expect(duration < .milliseconds(20)) // Should be fast with predicate
}
```

**Step 2: Run test to verify baseline**

Run: `swift test --filter LibraryRepositoryTests.testFetchUserLibraryPerformance`
Expected: PASS but duration >50ms (in-memory filtering)

**Step 3: Optimize with predicate filtering**

In `LibraryRepository.swift`:

```swift
// OLD implementation
public func fetchUserLibrary() -> [Work] {
    let descriptor = FetchDescriptor<Work>()
    let allWorks = (try? modelContext.fetch(descriptor)) ?? []
    return allWorks.filter { !($0.userLibraryEntries ?? []).isEmpty }
}

// NEW implementation (Grok-validated CloudKit-safe pattern)
public func fetchUserLibrary() -> [Work] {
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { work in
            (work.userLibraryEntries?.count ?? 0) > 0
        }
    )
    return (try? modelContext.fetch(descriptor)) ?? []
}
```

**Note:** Using `count > 0` instead of `isEmpty == false` for better CloudKit predicate translation. This pattern is more idiomatic in Swift 6.2 and handles nil arrays gracefully.

**Step 4: Run test to verify improvement**

Run: `swift test --filter LibraryRepositoryTests.testFetchUserLibraryPerformance`
Expected: PASS with duration <20ms (3-5x faster)

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Library/LibraryRepository.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Library/LibraryRepositoryTests.swift
git commit -m "perf: optimize fetchUserLibrary with predicate filtering (#319)

- Move relationship filtering to database predicate
- 3-5x performance improvement for large libraries
- Reduces memory pressure

Resolves #319"
```

---

### Task 7: Add Backend Input Validation (#316)

**Problem:** Backend enrichment endpoint accepts arbitrary input without validation, potential security/stability risk.

**Solution:** Add Zod schema validation for all enrichment requests.

**Files:**
- Create: `cloudflare-workers/api-worker/src/validators/enrichment.ts`
- Modify: `cloudflare-workers/api-worker/src/handlers/enrichment.ts`
- Test: `cloudflare-workers/api-worker/src/handlers/enrichment.test.ts`

**Step 1: Write validation tests**

```typescript
import { describe, test, expect } from 'vitest'
import { validateEnrichmentRequest } from '../validators/enrichment'

describe('Enrichment Request Validation', () => {
  test('accepts valid enrichment request', () => {
    const valid = {
      workIds: ['abc123', 'def456'],
      jobId: '550e8400-e29b-41d4-a716-446655440000'
    }

    expect(() => validateEnrichmentRequest(valid)).not.toThrow()
  })

  test('rejects empty workIds array', () => {
    const invalid = { workIds: [], jobId: 'valid-uuid' }
    expect(() => validateEnrichmentRequest(invalid)).toThrow('workIds must not be empty')
  })

  test('rejects invalid UUID format', () => {
    const invalid = { workIds: ['abc'], jobId: 'not-a-uuid' }
    expect(() => validateEnrichmentRequest(invalid)).toThrow('Invalid UUID')
  })

  test('rejects workIds exceeding 100 items', () => {
    const invalid = {
      workIds: Array(101).fill('id'),
      jobId: 'valid-uuid'
    }
    expect(() => validateEnrichmentRequest(invalid)).toThrow('Maximum 100 works per batch')
  })
})
```

**Step 2: Run test to verify it fails**

Run: `npm test enrichment.test.ts`
Expected: FAIL - validateEnrichmentRequest doesn't exist

**Step 3: Create validation schema**

Create `validators/enrichment.ts`:

```typescript
import { z } from 'zod'

const enrichmentRequestSchema = z.object({
  workIds: z.array(z.string().min(1))
    .min(1, 'workIds must not be empty')
    .max(100, 'Maximum 100 works per batch'),
  jobId: z.string().uuid('Invalid UUID format')
})

export function validateEnrichmentRequest(data: unknown) {
  return enrichmentRequestSchema.parse(data)
}

export type EnrichmentRequest = z.infer<typeof enrichmentRequestSchema>
```

**Step 4: Run test to verify it passes**

Run: `npm test enrichment.test.ts`
Expected: PASS

**Step 5: Integrate validation into handler**

In `handlers/enrichment.ts`:

```typescript
import { validateEnrichmentRequest } from '../validators/enrichment'

export async function handleEnrichment(request: Request): Promise<Response> {
  try {
    const body = await request.json()
    const validated = validateEnrichmentRequest(body)

    // Use validated.workIds and validated.jobId (type-safe!)
    const results = await enrichWorks(validated.workIds, validated.jobId)

    return Response.json({ success: true, data: results })

  } catch (error) {
    if (error instanceof z.ZodError) {
      return Response.json(
        { success: false, error: error.errors[0].message },
        { status: 400 }
      )
    }
    throw error
  }
}
```

**Step 6: Test with curl**

```bash
# Valid request
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"workIds":["abc"],"jobId":"550e8400-e29b-41d4-a716-446655440000"}'

# Invalid request (should return 400)
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"workIds":[],"jobId":"invalid"}'
```

**Step 7: Deploy and verify**

```bash
cd cloudflare-workers/api-worker
npm run deploy
```

**Step 8: Commit**

```bash
git add cloudflare-workers/api-worker/src/validators/enrichment.ts
git add cloudflare-workers/api-worker/src/handlers/enrichment.ts
git add cloudflare-workers/api-worker/src/handlers/enrichment.test.ts
git commit -m "feat: add input validation to enrichment endpoint (#316)

- Add Zod schema validation for enrichment requests
- Validate workIds array (1-100 items, non-empty strings)
- Validate jobId as proper UUID
- Return 400 Bad Request for invalid input

Resolves #316"
```

---

### Task 8: Add WorkId Sanitization (#318)

**Problem:** Backend converts arbitrary workIds to UUIDs without sanitization/validation.

**Solution:** Add workId format validation before processing.

**Files:**
- Modify: `cloudflare-workers/api-worker/src/validators/enrichment.ts`
- Test: `cloudflare-workers/api-worker/src/handlers/enrichment.test.ts`

**Step 1: Write workId validation test**

```typescript
test('rejects workIds with invalid characters', () => {
  const invalid = {
    workIds: ['valid-id', '<script>alert("xss")</script>'],
    jobId: 'valid-uuid'
  }
  expect(() => validateEnrichmentRequest(invalid)).toThrow('Invalid workId format')
})

test('accepts workIds with alphanumeric and hyphens only', () => {
  const valid = {
    workIds: ['abc-123', 'work-id-456'],
    jobId: 'valid-uuid'
  }
  expect(() => validateEnrichmentRequest(valid)).not.toThrow()
})
```

**Step 2: Run test to verify it fails**

Run: `npm test enrichment.test.ts`
Expected: FAIL - No workId format validation

**Step 3: Add workId regex validation**

In `validators/enrichment.ts`:

```typescript
const workIdSchema = z.string()
  .min(1, 'workId must not be empty')
  .max(200, 'workId exceeds maximum length')
  .regex(/^[a-zA-Z0-9_-]+$/, 'Invalid workId format: only alphanumeric, hyphens, and underscores allowed')

const enrichmentRequestSchema = z.object({
  workIds: z.array(workIdSchema)
    .min(1, 'workIds must not be empty')
    .max(100, 'Maximum 100 works per batch'),
  jobId: z.string().uuid('Invalid UUID format')
})
```

**Step 4: Run test to verify it passes**

Run: `npm test enrichment.test.ts`
Expected: PASS

**Step 5: Deploy and test**

```bash
npm run deploy

# Test XSS attempt (should be rejected)
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"workIds":["<script>"],"jobId":"550e8400-e29b-41d4-a716-446655440000"}'
```

Expected: 400 Bad Request with "Invalid workId format"

**Step 6: Commit**

```bash
git add cloudflare-workers/api-worker/src/validators/enrichment.ts
git add cloudflare-workers/api-worker/src/handlers/enrichment.test.ts
git commit -m "security: sanitize workIds before processing (#318)

- Add regex validation for workId format (alphanumeric + hyphens/underscores)
- Reject workIds with special characters (XSS prevention)
- Max length check (200 chars)

Resolves #318"
```

---

### Task 9: Make WebSocket Timeout Configurable (#317)

**Problem:** WebSocket timeout hardcoded at 90 seconds, unsuitable for slow networks.

**Solution:** Add timeout configuration to WebSocketManager with sensible defaults.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/WebSocketManager.swift`
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Config/WebSocketConfig.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Services/WebSocketManagerTests.swift`

**Step 1: Write configuration test**

```swift
@Test("WebSocketConfig allows custom timeout")
func testCustomTimeout() {
    let config = WebSocketConfig(timeout: .seconds(120))
    #expect(config.timeout == .seconds(120))
}

@Test("WebSocketConfig uses sensible defaults")
func testDefaultConfig() {
    let config = WebSocketConfig()
    #expect(config.timeout == .seconds(90))
    #expect(config.reconnectDelay == .seconds(5))
    #expect(config.maxReconnectAttempts == 3)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter WebSocketConfigTests`
Expected: FAIL - WebSocketConfig doesn't exist

**Step 3: Create WebSocketConfig**

Create `WebSocketConfig.swift`:

```swift
import Foundation

public struct WebSocketConfig: Sendable {
    public let timeout: Duration
    public let reconnectDelay: Duration
    public let maxReconnectAttempts: Int

    public init(
        timeout: Duration = .seconds(90),
        reconnectDelay: Duration = .seconds(5),
        maxReconnectAttempts: Int = 3
    ) {
        self.timeout = timeout
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
    }

    public static let `default` = WebSocketConfig()

    // Preset for slow networks
    public static let slowNetwork = WebSocketConfig(
        timeout: .seconds(180),
        reconnectDelay: .seconds(10),
        maxReconnectAttempts: 5
    )
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter WebSocketConfigTests`
Expected: PASS

**Step 5: Integrate into WebSocketManager**

In `WebSocketManager.swift`:

```swift
@MainActor
public class WebSocketManager: NSObject, ObservableObject {
    private let config: WebSocketConfig

    public init(config: WebSocketConfig = .default) {
        self.config = config
        super.init()
    }

    public func connect(jobId: String) async throws {
        // Use config.timeout instead of hardcoded value
        try await withTimeout(duration: config.timeout) {
            await self.performConnection(jobId: jobId)
        }
    }
}
```

**Step 6: Add Settings UI for timeout with @AppStorage**

In `SettingsView.swift`:

```swift
// Use @AppStorage for automatic UserDefaults sync (SwiftUI best practice)
@AppStorage("wsTimeout") private var wsTimeout: Double = 90

var body: some View {
    Form {
        Section("Advanced") {
            VStack(alignment: .leading) {
                Text("WebSocket Timeout")
                Slider(value: $wsTimeout, in: 30...300, step: 30)
                Text("\(Int(wsTimeout)) seconds")
                    .foregroundColor(.secondary)
            }
        }
    }
    // No onChange needed - @AppStorage handles persistence automatically!
}
```

**Note:** `@AppStorage` is more idiomatic than manual UserDefaults management in SwiftUI and eliminates boilerplate.

**Step 7: Load timeout from UserDefaults with validation**

In `App.swift`:

```swift
// Load and clamp timeout to valid range [30, 300]
let rawTimeout = UserDefaults.standard.double(forKey: "wsTimeout")
let timeout = (rawTimeout > 0) ? rawTimeout : 90.0  // Default to 90s if not set
let clampedTimeout = max(30, min(300, timeout))  // Enforce slider bounds

// Optional: Log if clamping occurred (for debugging)
if rawTimeout != clampedTimeout && rawTimeout > 0 {
    os_log("Clamped wsTimeout from %f to %f", log: .default, type: .info, rawTimeout, clampedTimeout)
}

let wsConfig = WebSocketConfig(timeout: .seconds(clampedTimeout))
let wsManager = WebSocketManager(config: wsConfig)
```

**Note:** Defensive clamping prevents corrupt UserDefaults values (e.g., from iCloud sync) from breaking WebSocket behavior.

**Step 8: Test on slow network**

Manual test:
1. Enable Network Link Conditioner (Settings → Developer → Network Link Conditioner)
2. Select "3G" or "Edge" profile
3. Change timeout in Settings to 180s
4. Perform enrichment
5. Should complete successfully (old 90s timeout would fail)

**Step 9: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Config/WebSocketConfig.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/WebSocketManager.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Settings/SettingsView.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Config/WebSocketConfigTests.swift
git commit -m "feat: make WebSocket timeout configurable (#317)

- Add WebSocketConfig with timeout, reconnect settings
- Add Settings UI slider with @AppStorage (30-300s range)
- Defensive clamping on load prevents corrupt UserDefaults
- Include slowNetwork preset (180s timeout)
- Log clamping events for debugging

Resolves #317"
```

---

## Success Metrics

**Phase 1 (Critical):**
- [ ] Battery drain eliminated (Energy Impact <5% during batch scan)
- [ ] Zero user complaints about hung scans

**Phase 2 (High Impact):**
- [ ] reviewQueueCount() <10ms for 1000+ books (10x improvement)
- [ ] Enrichment timeout prevents infinite hangs (0 timeout-related support tickets)
- [ ] API environment switching works in <1 minute
- [ ] Fuzzy matching reduces manual review queue by 15-25%

**Phase 3 (Hardening):**
- [ ] fetchUserLibrary() 3-5x faster for large libraries
- [ ] Backend rejects 100% of malformed requests (validation coverage)
- [ ] Zero XSS vulnerabilities in workId processing
- [ ] Users on slow networks successfully complete enrichment

**Overall:**
- [ ] All 9 issues resolved with passing tests
- [ ] Zero warnings in Xcode
- [ ] All tests pass on CI
- [ ] Performance improvements verified with Instruments

---

## Testing Checklist

**Unit Tests:**
- [ ] 25+ new tests across iOS and backend
- [ ] Performance benchmarks for database queries
- [ ] Validation tests for all input schemas
- [ ] Fuzzy matching edge cases

**Integration Tests:**
- [ ] End-to-end enrichment with timeout
- [ ] WebSocket reconnection logic
- [ ] API environment switching

**Manual Testing:**
- [ ] Real device testing for battery drain fix
- [ ] Slow network testing (Network Link Conditioner)
- [ ] Large library testing (1000+ books)
- [ ] Security testing (XSS attempts on backend)

---

## Deployment Plan

**Phase 1 (Immediate - Critical Bug):**
1. Deploy #311 (battery drain) to TestFlight
2. Monitor crash reports for 24h
3. If stable, release to App Store

**Phase 2 (Week 1 - Performance):**
1. Deploy #315, #312, #314, #313 as single release
2. TestFlight beta for 48h
3. Monitor performance metrics in Xcode Organizer

**Phase 3 (Week 2 - Hardening):**
1. Deploy backend validation (#316, #318) first
2. Monitor error rates in Cloudflare dashboard
3. Deploy iOS changes (#319, #317)
4. Full regression test

---

**Total Estimated Time:** 18-22 hours
**Priority:** P0 (1h) → P1 (10h) → P2 (5h) → Testing (4h)
**Target Completion:** 2 weeks
