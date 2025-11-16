# Swift 6 Concurrency Rules - Quick Reference

**Essential patterns for Swift 6 strict concurrency** (BooksTrack + any Swift 6 project)

---

## 🚨 Critical Rules

### Rule #1: BAN Timer.publish in Actors

```swift
// ❌ WRONG: Combine doesn't integrate with actor isolation
@MainActor
class ProgressTracker {
    func start() {
        Timer.publish(every: 2, on: .main, in: .common)  // ❌ Compiler error!
            .sink { _ in self.poll() }
    }
}

// ✅ CORRECT: Use Task.sleep for polling
@MainActor
class ProgressTracker {
    func start() async {
        while !isCancelled {
            await Task.sleep(for: .seconds(2))
            await poll()
        }
    }
}

// ✅ BETTER: Use AdaptivePollingStrategy (battery-optimized!)
@State private var tracker = PollingProgressTracker<MyJob>()
let result = try await tracker.start(
    job: myJob,
    strategy: AdaptivePollingStrategy(),  // 2s → 5s → 10s intervals
    timeout: 90
)
```

**Why:** Combine's `Timer.publish` predates Swift 6 concurrency and doesn't respect actor isolation boundaries. Use `Task.sleep` for delays and polling.

---

### Rule #2: MainActor for UI

```swift
// ✅ CORRECT: UI components must be @MainActor
@MainActor
struct BookDetailView: View {
    @Bindable var work: Work

    var body: some View {
        Text(work.title)
    }
}

// ✅ CORRECT: ObservableObject classes for UI
@MainActor
@Observable
class SearchModel {
    var results: [Work] = []

    func search(_ query: String) async {
        // Safe to update UI from here (already @MainActor)
        results = await apiClient.search(query)
    }
}

// ❌ WRONG: Missing @MainActor (compiler error)
struct BookDetailView: View {  // ❌ Must be @MainActor!
    var body: some View { ... }
}
```

**Why:** SwiftUI views and UI-related state MUST run on the main thread. `@MainActor` ensures this at compile time.

---

### Rule #3: nonisolated for Pure Functions

```swift
@MainActor
class LibraryRepository {
    private let modelContext: ModelContext

    // ✅ CORRECT: Pure function, no state access
    nonisolated func validateISBN(_ isbn: String) -> Bool {
        // No self access, no async calls
        return isbn.count == 13 && isbn.allSatisfy(\.isNumber)
    }

    // ✅ CORRECT: Accesses state, stays @MainActor
    func fetchAll() async throws -> [Work] {
        try modelContext.fetch(FetchDescriptor<Work>())
    }

    // ❌ WRONG: Pure function but not marked nonisolated
    func validateISBN(_ isbn: String) -> Bool {  // ❌ Forces caller to await!
        return isbn.count == 13
    }
}
```

**Why:** Pure functions (no state access, no async) can be `nonisolated` to avoid forcing callers to `await` unnecessarily.

---

## 🏗️ Actor Isolation Patterns

### @MainActor (UI Thread)

**Use for:**
- SwiftUI views
- @Observable classes for UI state
- Anything that updates UI
- IBOutlet, IBAction in UIKit

```swift
@MainActor
struct LibraryView: View {
    @Query var works: [Work]
    @State private var selectedWork: Work?

    var body: some View {
        List(works, id: \.id) { work in
            Text(work.title)
        }
    }
}

@MainActor
@Observable
class SearchModel {
    var state: SearchViewState = .initial(...)

    func search(_ query: String) async {
        state = .loading
        let results = await apiClient.search(query)
        state = .results(results)  // Safe to update (already @MainActor)
    }
}
```

---

### Actor (Custom Isolation)

**Use for:**
- Background processing
- Mutable shared state
- Concurrent logic

```swift
actor EnrichmentQueue {
    private var queue: [UUID] = []
    private var processing = false

    func enqueue(_ workId: UUID) {
        queue.append(workId)  // Safe, actor-isolated
    }

    func dequeue() -> UUID? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    func processNext() async throws {
        guard !processing, let workId = dequeue() else { return }
        processing = true
        defer { processing = false }

        // Process work (safe, actor-isolated)
        let dto = try await apiClient.enrich(workId)
        await applyEnrichment(dto)  // Can await other actors
    }
}
```

---

### nonisolated (No Isolation)

**Use for:**
- Pure functions (no state access)
- Initialization
- Static methods

```swift
@MainActor
class LibraryRepository {
    // ✅ Pure function
    nonisolated func validateISBN(_ isbn: String) -> Bool {
        ISBN.validate(isbn)  // No state access
    }

    // ✅ Initialization (no state yet)
    nonisolated init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // ✅ Static method (no instance state)
    nonisolated static func createDefault() -> LibraryRepository {
        LibraryRepository(modelContext: ModelContext(...))
    }
}
```

---

## 🔄 Crossing Actor Boundaries

### Calling Across Actors

```swift
@MainActor
class LibraryViewModel {
    func refreshLibrary() async throws {
        // Calling actor method (must await)
        await EnrichmentQueue.shared.processNext()

        // Calling nonisolated method (no await)
        let valid = repository.validateISBN("9780134685991")
    }
}

actor EnrichmentQueue {
    func processNext() async throws {
        // Calling @MainActor method (must await)
        await MainActor.run {
            // Update UI on main thread
            print("Processing...")
        }
    }
}
```

**Rule:** Crossing actor boundaries requires `await`.

---

### Sendable Types

**Sendable = Safe to send across actor boundaries**

```swift
// ✅ Sendable: Value types (struct/enum) with Sendable members
struct WorkDTO: Sendable {
    let id: UUID
    let title: String
    let authors: [AuthorDTO]  // [AuthorDTO] is Sendable
}

// ✅ Sendable: Actors (automatically Sendable)
actor EnrichmentQueue { ... }

// ✅ Sendable: Enums with Sendable cases
enum ReadingStatus: Sendable {
    case wishlist, toRead, reading, read
}

// ❌ NOT Sendable: Classes (mutable, shared)
class Work { ... }  // ❌ Not Sendable

// ❌ NOT Sendable: SwiftData models
@Model
class Work { ... }  // ❌ NEVER claim Sendable!

// ⚠️ @unchecked Sendable (use with caution!)
class ThreadSafeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
```

**Rule:** Only claim `Sendable` if type is genuinely thread-safe. Use `@unchecked Sendable` sparingly (only when you KNOW it's safe).

---

## ⚡ Async/Await Patterns

### Calling Async Functions

```swift
// ✅ CORRECT: await async function
func loadBook() async throws -> Work {
    let dto = try await apiClient.search(isbn: "9780134685991")
    return try DTOMapper.shared.mapToModel(dto)
}

// ✅ CORRECT: Task for fire-and-forget
func refreshLibrary() {
    Task {
        try await enrichmentQueue.processNext()
    }
}

// ❌ WRONG: Can't call async from sync context
func loadBook() -> Work {  // ❌ Not async!
    let dto = apiClient.search(isbn: "...")  // ❌ Can't await!
    return ...
}
```

---

### Structured Concurrency

**Use Task groups for parallel work:**
```swift
func enrichBooks(_ workIds: [UUID]) async throws -> [WorkDTO] {
    try await withThrowingTaskGroup(of: WorkDTO.self) { group in
        for id in workIds {
            group.addTask {
                try await apiClient.enrich(id)
            }
        }

        var results: [WorkDTO] = []
        for try await dto in group {
            results.append(dto)
        }
        return results
    }
}
```

---

### Cancellation

```swift
func processWithCancellation() async throws {
    for id in workIds {
        // Check cancellation before each iteration
        try Task.checkCancellation()

        // Or early exit
        if Task.isCancelled { break }

        try await process(id)
    }
}

// Cancel from outside
let task = Task {
    try await processWithCancellation()
}

// Later...
task.cancel()
await task.value  // Wait for cleanup
```

---

## 🎯 Common Patterns

### Pattern 1: Background Task with UI Updates

```swift
@MainActor
class ScanViewModel {
    @Published var progress: Double = 0
    @Published var status: String = ""

    func scanBookshelf(photo: UIImage) async throws {
        // Switch to background for heavy work
        let results = await Task.detached {
            // Process on background thread
            return try await APIClient.shared.scanBookshelf(photo)
        }.value

        // Back on MainActor (self is @MainActor)
        progress = 1.0
        status = "Completed"
    }
}
```

---

### Pattern 2: Debouncing (Search as You Type)

```swift
@MainActor
@Observable
class SearchModel {
    var query: String = "" {
        didSet {
            // Cancel previous search
            searchTask?.cancel()

            // Debounce by 300ms
            searchTask = Task {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await search(query)
            }
        }
    }

    private var searchTask: Task<Void, Error>?

    private func search(_ query: String) async {
        // Perform search
    }
}
```

---

### Pattern 3: Sequential Processing

```swift
func processSequentially(_ workIds: [UUID]) async throws {
    for id in workIds {
        try Task.checkCancellation()
        try await process(id)  // One at a time
    }
}
```

---

### Pattern 4: Parallel Processing (Batch)

```swift
func processBatch(_ workIds: [UUID]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for id in workIds {
            group.addTask {
                try await self.process(id)
            }
        }

        // Wait for all to complete
        try await group.waitForAll()
    }
}
```

---

## 🐛 Common Issues

### Issue: "Expression is 'async' but is not marked with 'await'"
**Cause:** Calling async function without `await`
**Fix:** Add `await` or make caller `async`

---

### Issue: "Call to actor method must be 'await'"
**Cause:** Crossing actor boundary without `await`
**Fix:** Add `await` before call

---

### Issue: "Main actor-isolated property can only be referenced on the main actor"
**Cause:** Accessing `@MainActor` property from non-MainActor context
**Fix:** Use `await MainActor.run { ... }` or make caller `@MainActor`

---

### Issue: "Timer.publish is unavailable in actor-isolated context"
**Cause:** Using Combine's `Timer.publish` in actor
**Fix:** Replace with `Task.sleep` or `AdaptivePollingStrategy`

---

### Issue: Data race warning in console
**Cause:** Shared mutable state without actor protection
**Fix:** Wrap state in actor or use `@MainActor`

---

## 📚 Best Practices

1. **Use `@MainActor` for all UI code** (SwiftUI views, @Observable UI models)
2. **Use actors for mutable shared state** (queues, caches, background processors)
3. **Use `nonisolated` for pure functions** (no state access, no async)
4. **Don't claim `Sendable` for SwiftData models** (they're not thread-safe)
5. **Use `Task.sleep` instead of `Timer.publish`** (Swift 6 compatible)
6. **Check cancellation in loops** (`Task.checkCancellation()` or `Task.isCancelled`)
7. **Use structured concurrency** (TaskGroup over manual Task management)
8. **Minimize `@unchecked Sendable`** (only when genuinely safe)

---

**Keep this reference handy! Swift 6 concurrency is strict but prevents data races at compile time.**
