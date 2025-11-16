# BooksTrack Code Patterns & Best Practices

**Version:** 3.0.0 (Build 47+)
**Swift:** 6.2+ | **iOS:** 26.0+
**Last Updated:** November 13, 2025

This document defines code standards, patterns, and anti-patterns for BooksTrack. AI assistants MUST follow these rules when generating code.

---

## 🚨 Critical Rules (NEVER VIOLATE)

### 1. SwiftData Persistent ID Lifecycle

**NEVER use `persistentModelID` before calling `save()`!**

```swift
// ❌ WRONG: Crash! "Illegal attempt to create a full future for temporary identifier"
let work = Work(title: "...")
modelContext.insert(work)  // Assigns TEMPORARY ID
let id = work.persistentModelID  // ❌ Still temporary!
EnrichmentQueue.shared.enqueue(id)  // ❌ CRASH!

// ✅ CORRECT: Save BEFORE capturing IDs
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]  // Relationships use temporary IDs (OK)
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Now safe!
EnrichmentQueue.shared.enqueue(id)  // ✅ Safe!
```

**Rule:** Always `save()` before:
- Using `persistentModelID` for anything
- Enqueuing background tasks (enrichment, notifications, etc.)
- Passing IDs to other services
- Storing IDs in dictionaries/arrays

---

### 2. SwiftData Insert-Before-Relate

**NEVER set relationships during model initialization!**

```swift
// ❌ WRONG: Crash! Relationship set before insert
let work = Work(title: "...", authors: [author])  // ❌ CRASH!
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE setting relationships
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]  // Set relationship AFTER both are inserted
try modelContext.save()
```

**Rule:**
1. Create models with empty relationships
2. Insert both sides into context
3. Set relationships AFTER both are inserted
4. Save when done

---

### 3. @Bindable for SwiftData Reactivity

**ALWAYS use `@Bindable` for SwiftData models in child views!**

```swift
// ❌ WRONG: View won't update when rating changes
struct BookDetailView: View {
    let work: Work  // ❌ Not reactive!
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
        // User changes rating → UI doesn't update!
    }
}

// ✅ CORRECT: @Bindable observes changes
struct BookDetailView: View {
    @Bindable var work: Work  // ✅ Reactive!
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
        // User changes rating → UI updates immediately!
    }
}
```

**Rule:** Use `@Bindable` for SwiftData models passed to child views that need reactive updates.

---

### 4. Swift 6 Actor Isolation

**BAN `Timer.publish` in Actors!**

```swift
// ❌ WRONG: Combine doesn't integrate with Swift 6 actor isolation
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

**Rule:** Use `Task.sleep` for delays, `AdaptivePollingStrategy` for polling, NEVER `Timer.publish` in actors.

---

### 5. iOS 26 HIG: Don't Mix @FocusState with .searchable()

**iOS 26's `.searchable()` manages focus internally!**

```swift
// ❌ WRONG: Manual focus creates keyboard conflicts
@FocusState var searchFocused: Bool
var body: some View {
    SearchView()
        .searchable(text: $query)
        .focused($searchFocused)  // ❌ Conflict!
}

// ✅ CORRECT: Let .searchable() manage focus
var body: some View {
    SearchView()
        .searchable(text: $query)  // ✅ iOS handles focus
}
```

**Rule:** NEVER use `@FocusState` with `.searchable()`. Let iOS handle keyboard focus.

---

### 6. Navigation: Push, Not Sheets

**Use push navigation for drill-down, sheets for modals.**

```swift
// ✅ CORRECT: Push navigation for details
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ✅ CORRECT: Sheets for modals (Settings, etc.)
.sheet(isPresented: $showingSettings) {
    NavigationStack { SettingsView() }
}
```

**Rule:** Push for drill-down, sheets for modals (iOS 26 HIG).

---

## 🎨 State Management

### Pattern: @Observable Models + @State (No ViewModels!)

```swift
// ✅ CORRECT: @Observable model + @State
@Observable
class SearchModel {
    var state: SearchViewState = .initial(trending: [], recentSearches: [])

    func search(_ query: String) async {
        state = .loading
        // ... fetch results
        state = .results(...)
    }
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch searchModel.state {
        case .initial(let trending, _):
            TrendingBooksView(trending: trending)
        case .loading:
            ProgressView()
        case .results(_, _, let items, _, _):
            ResultsListView(items: items)
        case .error(let message):
            ErrorView(message: message)
        }
    }
}

// ❌ WRONG: ObservableObject (pre-Swift 6 pattern)
class SearchViewModel: ObservableObject {
    @Published var state: SearchViewState = .initial(...)
}
```

**Rule:** Use `@Observable` classes with `@State`, not `ObservableObject` with `@Published`.

---

### Property Wrappers

**When to use each:**

| Wrapper | Use Case | Example |
|---------|----------|---------|
| `@State` | View-local state, model objects | `@State private var searchModel = SearchModel()` |
| `@Observable` | Observable model classes | `@Observable class SearchModel { ... }` |
| `@Environment` | Dependency injection | `@Environment(\.modelContext) private var modelContext` |
| `@Bindable` | SwiftData models in child views | `@Bindable var work: Work` |
| `@Query` | SwiftData queries | `@Query var works: [Work]` |

**Anti-patterns:**
- ❌ `@StateObject` (use `@State` instead)
- ❌ `@ObservedObject` (use `@Bindable` for SwiftData, `@State` for others)
- ❌ `@Published` (use `@Observable` instead)

---

## 🏗️ Architecture Patterns

### Nested Types for Related Code

**Group supporting types inside their parent class.**

```swift
// ✅ CORRECT: Nested types
@MainActor
public class CSVImportService {
    // Supporting types nested
    public enum DuplicateStrategy: Sendable {
        case skip, update, smart
    }

    public struct ImportResult {
        let successCount: Int
        let duplicateCount: Int
        let failedCount: Int
    }

    public func importCSV(_ data: Data, strategy: DuplicateStrategy) async throws -> ImportResult {
        // ...
    }
}

// Usage: CSVImportService.DuplicateStrategy.smart

// ❌ WRONG: Top-level types clutter namespace
public enum CSVImportDuplicateStrategy { ... }  // ❌ Redundant prefix
public struct CSVImportResult { ... }           // ❌ Redundant prefix
```

**Rule:** Nest supporting types (enums, structs) inside their parent class/struct.

---

### Service Layer Pattern

**Services are stateless, use dependency injection.**

```swift
// ✅ CORRECT: Stateless service with DI
public class EnrichmentService {
    private let apiClient: APIClient
    private let logger: Logger

    public init(apiClient: APIClient, logger: Logger) {
        self.apiClient = apiClient
        self.logger = logger
    }

    public func enrich(_ workId: UUID) async throws -> WorkDTO {
        // Stateless logic
    }
}

// ❌ WRONG: Singleton with hidden dependencies
public class EnrichmentService {
    static let shared = EnrichmentService()  // ❌ Singleton
    private init() {}

    public func enrich(_ workId: UUID) async throws -> WorkDTO {
        // Hidden dependencies on URLSession.shared, etc.
    }
}
```

**Rule:** Services are stateless and injectable. Avoid singletons (except for truly global state like ModelContainer).

---

### Error Handling

**Use typed throws (Swift 6).**

```swift
// ✅ CORRECT: Typed throws
public enum EnrichmentError: Error {
    case networkFailure(URLError)
    case invalidResponse(String)
    case workNotFound(UUID)
}

public func enrich(_ workId: UUID) async throws(EnrichmentError) -> WorkDTO {
    guard let work = try? modelContext.fetch(...) else {
        throw .workNotFound(workId)
    }
    // ...
}

// ❌ WRONG: Generic throws
public func enrich(_ workId: UUID) async throws -> WorkDTO {
    // Unclear what errors can be thrown
}
```

**Rule:** Use typed throws for clear error contracts.

---

## 🎨 SwiftUI Patterns

### View Composition

**Break large views into smaller, focused components.**

```swift
// ✅ CORRECT: Small, focused views
struct BookCard: View {
    let work: Work
    var body: some View {
        VStack {
            CoverImageView(url: CoverImageService.coverURL(for: work))
            BookMetadataView(work: work)
        }
    }
}

struct CoverImageView: View {
    let url: URL?
    var body: some View {
        CachedAsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            PlaceholderView()
        }
    }
}

// ❌ WRONG: Monolithic view
struct BookCard: View {
    let work: Work
    var body: some View {
        VStack {
            // 200 lines of nested code...
        }
    }
}
```

**Rule:** Keep views under 100 lines. Extract subviews for clarity.

---

### Cover Image Display

**ALWAYS use `CoverImageService` for cover URLs!**

```swift
// ✅ CORRECT: Centralized service with fallback
struct BookCard: View {
    let work: Work
    var body: some View {
        CachedAsyncImage(url: CoverImageService.coverURL(for: work)) {
            image in image.resizable()
        } placeholder: {
            PlaceholderView()
        }
    }
}

// ❌ WRONG: Direct access misses fallback
CachedAsyncImage(url: work.primaryEdition?.coverURL)  // Misses Work-level covers!
```

**Why:** Enrichment populates covers at both Edition and Work levels. `CoverImageService` provides intelligent fallback (Edition → Work → placeholder).

---

### Text Contrast (WCAG AA)

**Use system semantic colors for automatic adaptation.**

```swift
// ✅ CORRECT: System semantic colors (auto-adapt to backgrounds)
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)
Text(work.title).foregroundColor(.primary)

// ✅ CORRECT: Brand color from theme
Text("Featured").foregroundColor(themeStore.primaryColor)

// ❌ WRONG: Custom "accessible" colors (removed v1.12.0)
Text("Author").foregroundColor(.accessibleSecondary)  // ❌ Doesn't exist!
```

**Rule:**
- Use `.secondary`/`.tertiary` for metadata
- Use `themeStore.primaryColor` for brand
- System colors auto-adapt to ensure WCAG AA compliance (4.5:1+ contrast)

---

## 🚀 Performance Patterns

### Database Queries

**Use `fetchCount()` instead of loading all objects.**

```swift
// ✅ CORRECT: fetchCount() (0.5ms for 1000 books)
let count = try modelContext.fetchCount(FetchDescriptor<Work>())

// ❌ WRONG: Loading all objects (50ms for 1000 books - 100x slower!)
let works = try modelContext.fetch(FetchDescriptor<Work>())
let count = works.count
```

**Rule:** Use `fetchCount()` when you only need counts, not objects.

---

### Predicate Filtering

**Filter BEFORE loading objects into memory.**

```swift
// ✅ CORRECT: Database-level filtering (fast)
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.status == .reading }
)
let reading = try modelContext.fetch(descriptor)

// ❌ WRONG: Load all, filter in-memory (slow)
let all = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let reading = all.filter { $0.status == .reading }
```

**Rule:** Use predicates for filtering, not in-memory filter().

**Caveat:** Can't filter on to-many relationships with predicates (CloudKit limitation). Filter in-memory for those:
```swift
// ✅ CORRECT: Filter to-many relationships in-memory
let works = try modelContext.fetch(FetchDescriptor<Work>())
let withLibraryEntries = works.filter { !$0.userLibraryEntries.isEmpty }
```

---

### Image Loading

**Use `CachedAsyncImage` everywhere.**

```swift
// ✅ CORRECT: Cached loading
CachedAsyncImage(url: url) { image in
    image.resizable()
} placeholder: {
    ProgressView()
}

// ❌ WRONG: AsyncImage (no cache, re-downloads every time)
AsyncImage(url: url)
```

**Rule:** NEVER use `AsyncImage` directly. Always use `CachedAsyncImage`.

---

## 🧪 Testing Patterns

### Swift Testing (@Test, #expect)

```swift
import Testing

// ✅ CORRECT: @Test with #expect
@Test("LibraryRepository returns correct count")
func testLibraryCount() async throws {
    let repository = LibraryRepository(modelContext: testContext)
    let count = try await repository.totalBooksCount()
    #expect(count == 5)
}

// ✅ CORRECT: Parameterized tests
@Test("ISBN validation", arguments: [
    ("978-0-123456-78-9", true),
    ("invalid", false),
    ("123", false)
])
func testISBNValidation(input: String, expected: Bool) {
    let result = ISBN.validate(input)
    #expect(result == expected)
}

// ❌ WRONG: XCTest (legacy)
class LibraryTests: XCTestCase {
    func testLibraryCount() {
        XCTAssertEqual(count, 5)
    }
}
```

**Rule:** Use Swift Testing (`@Test`, `#expect`) for all new tests. No XCTest.

---

## 🔐 Security Patterns

### Never Hardcode Secrets

```swift
// ✅ CORRECT: Environment variables
let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""

// ❌ WRONG: Hardcoded
let apiKey = "AIzaSyABC123..."  // ❌ Exposed in git!
```

**Rule:** Use environment variables or keychain, NEVER hardcode.

---

### Validate User Input

```swift
// ✅ CORRECT: Validation + sanitization
func searchISBN(_ input: String) throws {
    guard ISBN.validate(input) else {
        throw SearchError.invalidISBN(input)
    }
    let normalized = ISBN.normalize(input)  // Remove hyphens, etc.
    // ... proceed with normalized ISBN
}

// ❌ WRONG: No validation
func searchISBN(_ input: String) {
    // Directly use input without checking
}
```

**Rule:** Validate and sanitize ALL user input before processing.

---

## 📝 Code Style

### Naming Conventions

**Swift Conventions:**
- `UpperCamelCase` for types (classes, structs, enums, protocols)
- `lowerCamelCase` for properties, methods, variables
- `SCREAMING_SNAKE_CASE` for constants (rare in Swift)

```swift
// ✅ CORRECT
class LibraryRepository { ... }
struct WorkDTO { ... }
enum ReadingStatus { ... }
protocol Enrichable { ... }

var currentPage: Int = 0
func fetchByReadingStatus(_ status: ReadingStatus) { ... }

// ❌ WRONG
class libraryRepository { ... }  // ❌ Should be UpperCamelCase
var CurrentPage: Int = 0         // ❌ Should be lowerCamelCase
```

---

### Optional Handling

**Use `guard let` / `if let`, avoid force unwrapping.**

```swift
// ✅ CORRECT: guard let for early exit
guard let work = works.first else {
    return nil
}
print(work.title)

// ✅ CORRECT: if let for conditional logic
if let coverURL = work.primaryEdition?.coverURL {
    loadImage(coverURL)
} else {
    showPlaceholder()
}

// ❌ WRONG: Force unwrapping (crash risk!)
let work = works.first!  // ❌ Crash if empty!
```

**Rule:** Use `guard let` / `if let` / `??`. NEVER force unwrap (`!`) unless you can prove it's safe.

---

### Access Control

**Use `public` for package-exposed APIs, `private`/`fileprivate` for internal.**

```swift
// ✅ CORRECT: Public API
public class LibraryRepository {
    public func fetchAll() async throws -> [Work] { ... }
    private func buildPredicate() -> Predicate<Work> { ... }
}

// ❌ WRONG: Everything public
public class LibraryRepository {
    public func fetchAll() async throws -> [Work] { ... }
    public func buildPredicate() -> Predicate<Work> { ... }  // ❌ Internal detail!
}
```

**Rule:** Minimize public surface area. Only expose what's needed outside the module.

---

## 🚫 Anti-Patterns

### 1. ViewModels (Replaced by @Observable)
```swift
// ❌ WRONG: ViewModel + ObservableObject (pre-Swift 6)
class SearchViewModel: ObservableObject {
    @Published var results: [Work] = []
}

// ✅ CORRECT: @Observable model
@Observable
class SearchModel {
    var results: [Work] = []
}
```

---

### 2. Singletons (Use Dependency Injection)
```swift
// ❌ WRONG: Hidden dependencies
class LibraryService {
    static let shared = LibraryService()
    private init() {}
}

// ✅ CORRECT: Injectable
class LibraryService {
    init(modelContext: ModelContext) { ... }
}
```

---

### 3. Force Unwrapping
```swift
// ❌ WRONG: Crash risk
let work = works.first!

// ✅ CORRECT: Safe unwrapping
guard let work = works.first else { return }
```

---

### 4. Sheets for Drill-Down Navigation
```swift
// ❌ WRONG: Breaks navigation stack
.sheet(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ✅ CORRECT: Push navigation
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}
```

---

## ✅ Zero-Warning Policy

**All code MUST build with zero warnings.**

**Common warnings to fix:**
- Unused variables → Remove or prefix with `_`
- Deprecated APIs → Update to new APIs
- Swift 6 concurrency → Add `@MainActor` or `nonisolated`
- Missing `Sendable` → Add `@unchecked Sendable` with caution

**Rule:** Warnings are treated as errors (`-Werror`). All PRs must build clean.

---

## 🎯 PR Checklist

Before submitting code:
- [ ] Zero warnings (Swift 6 concurrency, deprecated APIs)
- [ ] `@Bindable` for SwiftData models in child views
- [ ] No `Timer.publish` in actors (use `Task.sleep`)
- [ ] Nested supporting types (enums, structs inside classes)
- [ ] WCAG AA contrast (4.5:1+ with system semantic colors)
- [ ] Real device testing (keyboard, navigation, etc.)
- [ ] Tests pass (Swift Testing, `@Test` + `#expect`)
- [ ] Documentation updated (if public API changed)

---

**These patterns are enforced by AI assistants and human code review. Violations block PRs.**
