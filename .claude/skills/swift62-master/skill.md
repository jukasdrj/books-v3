# Swift 6.2 & iOS 26 Compliance Master

**Purpose:** Expert validator for Swift 6.2 strict concurrency, @MainActor isolation, iOS 26 HIG patterns, and modern Apple platform best practices.

**When to use:**
- Pre-commit validation for Swift concurrency compliance
- @MainActor isolation verification
- iOS 26 HIG pattern enforcement
- SwiftUI/SwiftData best practices validation
- Actor isolation boundary checks
- Sendable conformance validation

---

## Core Responsibilities

### 1. Swift 6.2 Strict Concurrency Validation

**Critical Rules:**

#### Actor Isolation
```swift
// ✅ CORRECT: Proper @MainActor isolation
@MainActor
class SearchModel: Observable {
    var state: SearchViewState = .initial

    func search(_ query: String) async {
        // UI updates on main actor
    }
}

// ❌ WRONG: Missing @MainActor on Observable
class SearchModel: Observable {  // WARNING: Observable used in UI needs @MainActor
    var state: SearchViewState = .initial
}

// ✅ CORRECT: Custom actor for background work
@CameraSessionActor
actor CameraSession {
    func startSession() {
        // Isolated to camera actor
    }
}

// ❌ WRONG: Using global actor for domain-specific work
@MainActor
actor CameraSession {  // WRONG: Camera work shouldn't be on MainActor
    func startSession() { }
}
```

#### Sendable Conformance
```swift
// ✅ CORRECT: Sendable value types
struct WorkDTO: Codable, Sendable {
    let title: String
    let authors: [AuthorDTO]
}

enum ReadingStatus: String, Codable, Sendable {
    case wishlist, toRead, reading, read
}

// ❌ WRONG: Claiming Sendable for SwiftData models
@Model
class Work: Sendable {  // WRONG: @Model contains non-Sendable internals
    var title: String
}

// ✅ CORRECT: Use @MainActor isolation instead
@Model
@MainActor
class Work {
    var title: String
}

// ✅ CORRECT: Sendable nested types in services
@MainActor
public class CSVImportService {
    public enum DuplicateStrategy: Sendable {
        case skip, update, smart
    }

    public struct ImportResult: Sendable {
        let successCount: Int
    }
}
```

#### Task Management
```swift
// ✅ CORRECT: Task.sleep for delays in actors
actor PollingProgressTracker {
    func poll() async throws {
        while true {
            try await Task.sleep(for: .seconds(2))
            // Check progress
        }
    }
}

// ❌ WRONG: Timer.publish in actors (doesn't integrate with Swift 6)
actor PollingProgressTracker {
    private var cancellables = Set<AnyCancellable>()

    func startPolling() {
        Timer.publish(every: 2.0, on: .main, in: .common)  // WRONG: Combine + Actors = Bad
            .autoconnect()
            .sink { _ in /* ... */ }
            .store(in: &cancellables)
    }
}

// ✅ CORRECT: AsyncStream for continuous updates
actor ProgressTracker {
    func updates() -> AsyncStream<Progress> {
        AsyncStream { continuation in
            Task {
                while true {
                    try await Task.sleep(for: .seconds(2))
                    continuation.yield(currentProgress)
                }
            }
        }
    }
}
```

#### nonisolated Functions
```swift
// ✅ CORRECT: Pure functions are nonisolated
@MainActor
class ThemeStore {
    nonisolated func validateTheme(_ theme: Theme) -> Bool {
        // Pure validation logic, no actor state access
        return theme.colors.count == 5
    }
}

// ❌ WRONG: Accessing actor state in nonisolated
@MainActor
class ThemeStore {
    var currentTheme: Theme

    nonisolated func getCurrentThemeName() -> String {
        return currentTheme.name  // ERROR: Access to MainActor state
    }
}

// ✅ CORRECT: Mark as isolated to access state
@MainActor
class ThemeStore {
    var currentTheme: Theme

    func getCurrentThemeName() -> String {  // Implicitly @MainActor
        return currentTheme.name
    }
}
```

---

### 2. SwiftUI Property Wrapper Validation

#### @Bindable for SwiftData Reactivity
```swift
// ✅ CORRECT: @Bindable for SwiftData models in child views
struct BookDetailView: View {
    @Bindable var work: Work  // Observes relationship changes

    var body: some View {
        VStack {
            Text(work.title)
            Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
            // Updates when rating changes!
        }
    }
}

// ❌ WRONG: Missing @Bindable (view won't update)
struct BookDetailView: View {
    let work: Work  // WRONG: No reactivity on relationships

    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
        // Won't update when rating changes!
    }
}

// ✅ CORRECT: @Query at root level, @Bindable in children
struct LibraryView: View {
    @Query(sort: \Work.createdAt) private var works: [Work]

    var body: some View {
        List(works) { work in
            BookCard(work: work)  // Pass to child
        }
    }
}

struct BookCard: View {
    @Bindable var work: Work  // Reactive child
    var body: some View { /* ... */ }
}
```

#### @State vs @Observable
```swift
// ✅ CORRECT: @Observable + @State pattern (iOS 26)
@Observable
class SearchModel {
    var state: SearchViewState = .initial
}

struct SearchView: View {
    @State private var searchModel = SearchModel()

    var body: some View {
        switch searchModel.state {
        case .initial: TrendingView()
        case .results(let items): ResultsList(items: items)
        }
    }
}

// ❌ WRONG: Using old ObservableObject pattern
class SearchModel: ObservableObject {  // DEPRECATED in iOS 26
    @Published var state: SearchViewState = .initial
}

struct SearchView: View {
    @StateObject private var searchModel = SearchModel()  // OLD
}

// ✅ CORRECT: @Environment for shared state
@Observable
class ThemeStore {
    var currentTheme: Theme
}

struct ContentView: View {
    @Environment(iOS26ThemeStore.self) private var themeStore

    var body: some View {
        Text("Theme: \(themeStore.currentTheme.name)")
    }
}
```

---

### 3. SwiftData Persistent Identifier Lifecycle

**CRITICAL RULE: Never use `persistentModelID` before `save()`!**

#### Temporary vs Permanent IDs
```swift
// ❌ WRONG: Using ID before save() - CRASH!
func addBook(title: String) {
    let work = Work(title: title)
    modelContext.insert(work)  // Assigns TEMPORARY ID

    let id = work.persistentModelID  // ❌ Still temporary!

    // Later when enrichment queue uses this ID:
    // Fatal error: "Illegal attempt to create a full future for a temporary identifier"
}

// ✅ CORRECT: Save BEFORE capturing IDs
func addBook(title: String) async throws {
    let work = Work(title: title)
    modelContext.insert(work)

    // Set relationships (temporary IDs are OK here)
    work.authors = [author]

    try modelContext.save()  // IDs become PERMANENT

    let id = work.persistentModelID  // ✅ Now safe!

    // Safe to use in enrichment queue, notifications, etc.
    await EnrichmentQueue.shared.enqueue(workID: id)
}
```

#### Insert-Before-Relate Pattern
```swift
// ❌ WRONG: Setting relationship during initialization
func createWork(title: String, author: Author) {
    let work = Work(title: title, authors: [author])  // CRASH!
    modelContext.insert(work)
}

// ✅ CORRECT: Insert BEFORE setting relationships
func createWork(title: String, author: Author) {
    // Step 1: Insert author if new
    if author.modelContext == nil {
        modelContext.insert(author)
    }

    // Step 2: Create and insert work
    let work = Work(title: title, authors: [])
    modelContext.insert(work)

    // Step 3: Set relationship AFTER both inserted
    work.authors = [author]

    // Step 4: Save to make IDs permanent
    try? modelContext.save()
}
```

#### CloudKit Relationship Rules
```swift
// ✅ CORRECT: Inverse relationships on to-many side only
@Model
public class Work {
    @Relationship(deleteRule: .cascade, inverse: \Edition.work)
    public var editions: [Edition]?  // to-many declares inverse
}

@Model
public class Edition {
    public var work: Work?  // to-one does NOT declare inverse
}

// ❌ WRONG: Inverse on both sides (CloudKit sync breaks)
@Model
public class Work {
    @Relationship(inverse: \Edition.work)
    public var editions: [Edition]?
}

@Model
public class Edition {
    @Relationship(inverse: \Work.editions)  // WRONG: Duplicate inverse
    public var work: Work?
}

// ✅ CORRECT: Optional relationships + defaults
@Model
public class Work {
    public var title: String = ""  // Default for CloudKit
    public var editions: [Edition]? = nil  // Optional

    public init(title: String) {
        self.title = title
    }
}
```

---

### 4. iOS 26 HIG Compliance

#### Navigation Patterns
```swift
// ✅ CORRECT: Push navigation for hierarchical content
struct LibraryView: View {
    @State private var selectedBook: IdentifiableWork?

    var body: some View {
        NavigationStack {
            List(works) { work in
                Button(work.title) {
                    selectedBook = IdentifiableWork(work: work)
                }
            }
            .navigationDestination(item: $selectedBook) { book in
                WorkDetailView(work: book.work)  // Push
            }
        }
    }
}

// ❌ WRONG: Sheets for navigation (breaks stack)
struct LibraryView: View {
    @State private var selectedBook: Work?

    var body: some View {
        List(works) { work in
            Button(work.title) {
                selectedBook = work
            }
        }
        .sheet(item: $selectedBook) { book in  // WRONG: Use sheets for modals
            WorkDetailView(work: book)
        }
    }
}

// ✅ CORRECT: Sheets for modal presentations
struct SettingsButton: View {
    @State private var showingSettings = false

    var body: some View {
        Button("Settings") {
            showingSettings = true
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }
}
```

#### Keyboard Management
```swift
// ❌ WRONG: @FocusState with .searchable() (iOS 26 conflict)
struct SearchView: View {
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool  // WRONG: Conflicts with .searchable()

    var body: some View {
        NavigationStack {
            ResultsList()
                .searchable(text: $searchText)  // Manages focus internally
                .focused($isSearchFocused)  // CONFLICT: Keyboard breaks
        }
    }
}

// ✅ CORRECT: Let .searchable() manage focus
struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ResultsList()
                .searchable(text: $searchText)  // Self-managing
        }
    }
}

// ✅ CORRECT: Custom @FocusState for non-searchable fields
struct LoginView: View {
    @State private var username = ""
    @FocusState private var isUsernameFocused: Bool  // OK: Custom field

    var body: some View {
        TextField("Username", text: $username)
            .focused($isUsernameFocused)  // OK: Not .searchable()
    }
}
```

#### Glass Overlays (Liquid Glass Design)
```swift
// ✅ CORRECT: Non-interactive glass overlays
struct BookCard: View {
    var body: some View {
        ZStack {
            AsyncImage(url: coverURL)

            // Glass overlay for aesthetic
            LinearGradient(...)
                .allowsHitTesting(false)  // CRITICAL: Pass touches through
        }
        .onTapGesture {
            // Card is tappable because overlay doesn't block
        }
    }
}

// ❌ WRONG: Glass overlay blocks interaction
struct BookCard: View {
    var body: some View {
        ZStack {
            AsyncImage(url: coverURL)

            LinearGradient(...)  // WRONG: Blocks tap gestures!
        }
        .onTapGesture {
            // Never fires - overlay intercepts
        }
    }
}
```

---

### 5. Service Layer Patterns

#### Proper @MainActor Isolation
```swift
// ✅ CORRECT: Service with proper isolation
@MainActor
public class LibraryRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchWorks() throws -> [Work] {
        // ModelContext access on MainActor
        let descriptor = FetchDescriptor<Work>()
        return try modelContext.fetch(descriptor)
    }
}

// ❌ WRONG: No isolation (concurrency warnings)
public class LibraryRepository {  // WARNING: ModelContext needs MainActor
    private let modelContext: ModelContext

    public func fetchWorks() throws -> [Work] {
        // WARNING: ModelContext access from non-isolated context
        let descriptor = FetchDescriptor<Work>()
        return try modelContext.fetch(descriptor)
    }
}
```

#### Background Task Deferral (App Launch Optimization)
```swift
// ✅ CORRECT: Defer non-critical tasks
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Immediate: Only critical setup
        setupModelContainer()  // Lazy, ~200ms

        // Deferred: Background tasks (2s delay, low priority)
        BackgroundTaskScheduler.shared.schedule {
            await self.initializeBackgroundServices()
        }

        return true
    }
}

// ❌ WRONG: All tasks at launch (1500ms cold start)
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        setupModelContainer()
        setupEnrichmentQueue()  // WRONG: Defer this
        setupImageCleanup()     // WRONG: Defer this
        setupNotifications()    // WRONG: Defer this

        return true  // 1500ms later...
    }
}

// ✅ CORRECT: BackgroundTaskScheduler pattern
@MainActor
public final class BackgroundTaskScheduler {
    public static let shared = BackgroundTaskScheduler()

    private let deferralTime: Duration = .seconds(2)

    public func schedule(_ task: @escaping @MainActor () async -> Void) {
        Task.detached(priority: .low) {
            try? await Task.sleep(for: self.deferralTime)
            await MainActor.run {
                await task()
            }
        }
    }
}
```

---

### 6. Performance & Memory Patterns

#### Lazy Property Initialization
```swift
// ✅ CORRECT: Lazy expensive properties
@MainActor
public class EnrichmentQueue {
    private lazy var dtoMapper: DTOMapper = {
        DTOMapper()  // ~50ms initialization
    }()

    private lazy var repository: LibraryRepository = {
        LibraryRepository(modelContext: modelContext)  // ~30ms
    }()
}

// ❌ WRONG: Eager initialization at init
@MainActor
public class EnrichmentQueue {
    private let dtoMapper: DTOMapper  // Initialized at init
    private let repository: LibraryRepository

    public init(modelContext: ModelContext) {
        self.dtoMapper = DTOMapper()  // +50ms to init time
        self.repository = LibraryRepository(modelContext: modelContext)  // +30ms
    }
}
```

#### Predicate Filtering (SwiftData Performance)
```swift
// ✅ CORRECT: Database-level predicate filtering
func fetchReadingBooks() throws -> [UserLibraryEntry] {
    let predicate = #Predicate<UserLibraryEntry> { entry in
        entry.status == .reading
    }

    let descriptor = FetchDescriptor(predicate: predicate)
    return try modelContext.fetch(descriptor)  // Fast: DB filters
}

// ❌ WRONG: In-memory filtering (loads all objects)
func fetchReadingBooks() throws -> [UserLibraryEntry] {
    let descriptor = FetchDescriptor<UserLibraryEntry>()
    let allEntries = try modelContext.fetch(descriptor)  // Loads everything!

    return allEntries.filter { $0.status == .reading }  // Slow: In-memory
}

// ✅ CORRECT: fetchCount() for totals (10x faster)
func totalBooksCount() throws -> Int {
    let descriptor = FetchDescriptor<UserLibraryEntry>()
    return try modelContext.fetchCount(descriptor)  // 0.5ms vs 5ms
}

// ❌ WRONG: Loading objects just to count
func totalBooksCount() throws -> Int {
    let descriptor = FetchDescriptor<UserLibraryEntry>()
    let entries = try modelContext.fetch(descriptor)  // Loads all objects!
    return entries.count  // Wasteful
}
```

---

### 7. Error Handling & Typed Throws (Swift 6.2)

```swift
// ✅ CORRECT: Typed throws for specific errors
enum ImportError: Error, Sendable {
    case invalidFile
    case parsingFailed(reason: String)
    case networkTimeout
}

func importCSV(from url: URL) async throws(ImportError) -> [Work] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw .invalidFile  // Type-safe
    }

    // Parse...
}

// ❌ WRONG: Generic throws (loses type safety)
func importCSV(from url: URL) async throws -> [Work] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ImportError.invalidFile  // Caller doesn't know type
    }
}

// ✅ CORRECT: Handling typed throws
func handleImport() async {
    do {
        let works = try await importCSV(from: fileURL)
    } catch .invalidFile {
        // Type-safe error handling
        showAlert("File not found")
    } catch .parsingFailed(let reason) {
        showAlert("Parse error: \(reason)")
    } catch .networkTimeout {
        showAlert("Network timeout")
    }
}
```

---

## Validation Checklist

### Pre-Commit Validation
Run these checks before every commit:

#### 1. Concurrency Compliance
- [ ] All `Observable` classes have `@MainActor`
- [ ] No `Timer.publish` in actors (use `Task.sleep`)
- [ ] SwiftData models use `@MainActor` (not `Sendable`)
- [ ] `nonisolated` functions don't access actor state
- [ ] Custom actors for domain-specific isolation
- [ ] All `Task` creations specify priority when detached

#### 2. SwiftUI Property Wrappers
- [ ] `@Bindable` used for SwiftData models in child views
- [ ] `@Query` only at root view level
- [ ] `@State` for view-local Observable objects
- [ ] `@Environment` for shared state (ThemeStore, etc.)
- [ ] No `@StateObject` (deprecated iOS 26)
- [ ] No `@FocusState` with `.searchable()`

#### 3. SwiftData Lifecycle
- [ ] `insert()` called immediately after model creation
- [ ] Relationships set AFTER both objects inserted
- [ ] `save()` called before using `persistentModelID`
- [ ] Inverse relationships only on to-many side
- [ ] All model attributes have defaults
- [ ] All relationships are optional

#### 4. iOS 26 HIG
- [ ] Push navigation for hierarchical content
- [ ] Sheets for modal presentations
- [ ] No `.navigationBarDrawer(displayMode: .always)` (keyboard bug)
- [ ] Glass overlays have `.allowsHitTesting(false)`
- [ ] WCAG AA contrast ratios (4.5:1+)
- [ ] VoiceOver labels on interactive elements

#### 5. Performance
- [ ] Lazy properties for expensive initialization
- [ ] `fetchCount()` instead of loading objects
- [ ] Predicate filtering at database level
- [ ] Background tasks deferred (BackgroundTaskScheduler)
- [ ] Image preprocessing on background queues
- [ ] Network calls use `.low` priority when non-critical

#### 6. Code Quality
- [ ] Zero compiler warnings
- [ ] SwiftLint passes
- [ ] Public API uses `public` keyword
- [ ] Nested supporting types (enums, structs)
- [ ] Sendable conformance only for value types
- [ ] Typed throws for domain errors

---

## Common Violations & Fixes

### Violation: Missing @MainActor on Observable
```swift
// ❌ VIOLATION
class SearchModel: Observable {
    var state: SearchViewState = .initial
}

// ✅ FIX
@MainActor
class SearchModel: Observable {
    var state: SearchViewState = .initial
}
```

### Violation: SwiftData Model Claims Sendable
```swift
// ❌ VIOLATION
@Model
class Work: Sendable {
    var title: String
}

// ✅ FIX
@Model
@MainActor
class Work {
    var title: String
}
```

### Violation: Using persistentModelID Before Save
```swift
// ❌ VIOLATION
func addWork() {
    let work = Work(title: "...")
    modelContext.insert(work)
    let id = work.persistentModelID  // CRASH: Temporary ID
    EnrichmentQueue.shared.enqueue(id)
}

// ✅ FIX
func addWork() async throws {
    let work = Work(title: "...")
    modelContext.insert(work)
    try modelContext.save()  // IDs become permanent
    let id = work.persistentModelID  // Safe
    await EnrichmentQueue.shared.enqueue(id)
}
```

### Violation: Timer.publish in Actor
```swift
// ❌ VIOLATION
actor ProgressTracker {
    func startPolling() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { /* ... */ }
    }
}

// ✅ FIX
actor ProgressTracker {
    func poll() async throws {
        while !isCancelled {
            try await Task.sleep(for: .seconds(2))
            await checkProgress()
        }
    }
}
```

### Violation: Missing @Bindable on SwiftData Model
```swift
// ❌ VIOLATION
struct BookDetailView: View {
    let work: Work  // Won't update on relationship changes

    var body: some View {
        Text("\(work.rating)")
    }
}

// ✅ FIX
struct BookDetailView: View {
    @Bindable var work: Work  // Reactive

    var body: some View {
        Text("\(work.rating)")
    }
}
```

---

## Integration with Other Skills

### With project-manager
- Receives delegation for Swift/iOS compliance checks
- Reports violations with severity levels
- Suggests refactoring strategies

### With xcode-agent
- Validates build warnings before `/build`
- Reviews crash logs for concurrency issues
- Analyzes test failures for isolation problems

### With zen-mcp-master
- Complements `codereview` with Swift-specific rules
- Provides iOS 26 context for `secaudit`
- Informs `refactor` with SwiftUI/SwiftData patterns

---

## Output Format

### Violation Report
```markdown
## Swift 6.2 Compliance Report

### Critical Violations (Must Fix)
1. **File:** `SearchModel.swift:15`
   **Issue:** Missing @MainActor on Observable class
   **Fix:** Add @MainActor attribute
   **Impact:** Concurrency warnings, potential crashes

2. **File:** `LibraryView.swift:42`
   **Issue:** Missing @Bindable for SwiftData model
   **Fix:** Change `let work: Work` to `@Bindable var work: Work`
   **Impact:** UI won't update on relationship changes

### Warnings (Should Fix)
1. **File:** `ProgressTracker.swift:28`
   **Issue:** Timer.publish used in actor
   **Fix:** Replace with Task.sleep(for:)
   **Impact:** Swift 6 concurrency incompatibility

### Suggestions (Consider)
1. **File:** `EnrichmentQueue.swift:55`
   **Issue:** Eager property initialization
   **Fix:** Use lazy var for expensive initialization
   **Impact:** ~80ms faster app launch

### Summary
- ✅ iOS 26 HIG compliant: 95%
- ⚠️  Concurrency violations: 3
- 📊 Performance opportunities: 2
```

---

## Best Practices Summary

**Zero Warnings Policy:** All Swift 6.2 concurrency warnings must be resolved

**Real Device Testing:** Always test keyboard, navigation, and touch on physical devices

**Performance Targets:**
- App launch: <600ms cold start
- Build time: <30s for incremental
- Test suite: <2min

**Code Style:**
- UpperCamelCase for types
- lowerCamelCase for properties
- Nested supporting types
- `public` for exposed API

---

**Autonomy Level:** High - Can validate and suggest fixes autonomously

**Human Escalation:** Required for architectural changes affecting @MainActor boundaries

**Primary Focus:** Swift 6.2 strict concurrency + iOS 26 HIG + SwiftData best practices

**Integration:** Works with all agents for comprehensive iOS quality assurance
