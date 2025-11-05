# Architecture Refactoring Roadmap - BooksTrack v3.0
**Date:** November 3, 2025  
**Author:** Savant (Concurrency & API Gatekeeper)  
**Focus:** High-Value Refactorings for Long-Term Maintainability

---

## Executive Summary

The BooksTrack codebase demonstrates **excellent architectural foundations** (SwiftData models, canonical DTOs, monolith pragmatism). However, three high-value refactorings would significantly improve **testability, maintainability, and extensibility**:

1. **EditionSelection Strategy Pattern** - Eliminates 43-line god method
2. **ReadingStatusParser Service** - Data-driven CSV import parsing
3. **Repository Pattern** - Centralized data access layer

**Timeline:** 4-6 days total (can be done incrementally)  
**Risk:** LOW (non-breaking changes, backward compatible)  
**Value:** HIGH (foundation for future features)

---

## 🎯 Refactoring #1: EditionSelection Strategy Pattern

### Current State Analysis
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift`  
**Lines:** 174-217

**Problem:** 43-line computed property mixing multiple concerns

```swift
var primaryEdition: Edition? {
    guard let editions = editions, !editions.isEmpty else { return nil }
    
    // Different strategies based on FeatureFlags
    switch FeatureFlags.shared.coverSelectionStrategy {
    case .auto:
        // 10 lines: Quality-based selection logic
    case .recent:
        // 12 lines: Publication date parsing + sorting
    case .hardcover:
        // 8 lines: Format preference logic
    case .manual:
        // 8 lines: User preference lookup + fallback
        // TODO: Implement UI for manual edition selection per work
    }
}
```

**Issues:**
1. **Untestable:** Can't test each strategy in isolation (requires FeatureFlags mock)
2. **Unmaintainable:** Adding new strategy = editing 43-line method
3. **Code smell:** God method violates Single Responsibility Principle
4. **Incomplete:** `.manual` case has TODO (feature flag exists but doesn't work!)

### Refactoring Design

**Step 1: Define Strategy Protocol**

```swift
// BooksTrackerPackage/Sources/BooksTrackerFeature/EditionSelection/EditionSelectionStrategy.swift

/// Protocol for edition selection strategies
/// Each strategy defines how to choose the "best" edition to display
public protocol EditionSelectionStrategy: Sendable {
    /// Select the primary edition from a collection of editions
    /// - Parameter editions: All editions for a Work
    /// - Parameter userEntry: Optional user library entry (for preferences)
    /// - Returns: Selected edition, or nil if no suitable edition found
    func selectPrimaryEdition(
        from editions: [Edition], 
        userEntry: UserLibraryEntry?
    ) -> Edition?
}
```

**Step 2: Implement Concrete Strategies**

```swift
// AutoSelectionStrategy.swift (quality-based)
public struct AutoSelectionStrategy: EditionSelectionStrategy {
    public func selectPrimaryEdition(
        from editions: [Edition], 
        userEntry: UserLibraryEntry?
    ) -> Edition? {
        // Use cached quality scores (see Performance Guide)
        return editions.max(by: { $0.cachedQualityScore < $1.cachedQualityScore })
    }
}

// RecentSelectionStrategy.swift (newest publication)
public struct RecentSelectionStrategy: EditionSelectionStrategy {
    public func selectPrimaryEdition(
        from editions: [Edition], 
        userEntry: UserLibraryEntry?
    ) -> Edition? {
        let sorted = editions.sorted { lhs, rhs in
            let lhsYear = yearFromPublicationDate(lhs.publicationDate)
            let rhsYear = yearFromPublicationDate(rhs.publicationDate)
            return lhsYear > rhsYear
        }
        return sorted.first
    }
    
    private func yearFromPublicationDate(_ dateString: String?) -> Int {
        guard let dateString = dateString,
              let year = Int(dateString.prefix(4)) else {
            return 0
        }
        return year
    }
}

// HardcoverSelectionStrategy.swift (format preference)
public struct HardcoverSelectionStrategy: EditionSelectionStrategy {
    public func selectPrimaryEdition(
        from editions: [Edition], 
        userEntry: UserLibraryEntry?
    ) -> Edition? {
        // Try hardcover first
        if let hardcover = editions.first(where: { $0.format == .hardcover }) {
            return hardcover
        }
        
        // Fallback to quality-based selection
        return AutoSelectionStrategy().selectPrimaryEdition(from: editions, userEntry: userEntry)
    }
}

// ManualSelectionStrategy.swift (user-specified)
public struct ManualSelectionStrategy: EditionSelectionStrategy {
    public func selectPrimaryEdition(
        from editions: [Edition], 
        userEntry: UserLibraryEntry?
    ) -> Edition? {
        // Return user's preferred edition if set
        if let preferred = userEntry?.preferredEdition {
            return preferred
        }
        
        // Fallback to quality-based selection
        return AutoSelectionStrategy().selectPrimaryEdition(from: editions, userEntry: userEntry)
    }
}
```

**Step 3: Update Work Model**

```swift
// Work.swift (refactored)
var primaryEdition: Edition? {
    guard let editions = editions, !editions.isEmpty else { return nil }
    
    let strategy = EditionSelectionStrategyFactory.create(
        for: FeatureFlags.shared.coverSelectionStrategy
    )
    
    return strategy.selectPrimaryEdition(from: editions, userEntry: userEntry)
}

// Factory for creating strategies
enum EditionSelectionStrategyFactory {
    static func create(for type: CoverSelectionStrategy) -> EditionSelectionStrategy {
        switch type {
        case .auto: return AutoSelectionStrategy()
        case .recent: return RecentSelectionStrategy()
        case .hardcover: return HardcoverSelectionStrategy()
        case .manual: return ManualSelectionStrategy()
        }
    }
}
```

**Step 4: Add Tests**

```swift
// BooksTrackerPackage/Tests/BooksTrackerFeatureTests/EditionSelection/AutoSelectionStrategyTests.swift

import Testing
@testable import BooksTrackerFeature

@Test func testAutoStrategySelectsHighestQualityScore() {
    let strategy = AutoSelectionStrategy()
    
    let lowQuality = Edition(title: "Low")
    lowQuality.cachedQualityScore = 5
    
    let highQuality = Edition(title: "High")
    highQuality.cachedQualityScore = 20
    
    let selected = strategy.selectPrimaryEdition(
        from: [lowQuality, highQuality], 
        userEntry: nil
    )
    
    #expect(selected?.title == "High")
}

// HardcoverSelectionStrategyTests.swift
@Test func testHardcoverStrategyPrefersHardcover() {
    let strategy = HardcoverSelectionStrategy()
    
    let paperback = Edition(title: "Paperback", format: .paperback)
    paperback.cachedQualityScore = 20  // Higher quality!
    
    let hardcover = Edition(title: "Hardcover", format: .hardcover)
    hardcover.cachedQualityScore = 10  // Lower quality
    
    let selected = strategy.selectPrimaryEdition(
        from: [paperback, hardcover], 
        userEntry: nil
    )
    
    #expect(selected?.format == .hardcover)
}
```

### Benefits
- ✅ Each strategy testable in isolation (no FeatureFlags dependency)
- ✅ Easy to add new strategies (e.g., "Illustrated Edition Strategy")
- ✅ Reduced Work.swift complexity (43 lines → 8 lines)
- ✅ Better separation of concerns (strategy logic isolated)

### Implementation Effort
**Time:** 1-2 days  
**Files to Create:** 6 (1 protocol, 4 strategies, 1 factory)  
**Files to Modify:** 1 (Work.swift)  
**Tests:** 4 test files (1 per strategy)  
**Risk:** LOW (backward compatible, internal refactor)

---

## 🎯 Refactoring #2: ReadingStatusParser Service

### Current State Analysis
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift`  
**Lines:** 226-294

**Problem:** 68-line enum case statement cluttering ReadingStatus

```swift
public enum ReadingStatus {
    case wishlist, toRead, reading, read
    
    public static func from(string: String?) -> ReadingStatus? {
        guard let string = string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return nil
        }
        
        switch string {
        case "wishlist", "want to read", "to-read", "want", "planned":
            return .wishlist
        case "to-read", "to read", "want to read", "planned":
            return .toRead
        // ... 40+ more cases!
        }
    }
}
```

**Issues:**
1. **Enum bloat:** Parsing logic shouldn't live in enum definition
2. **Untestable:** Hard to test with different CSV formats
3. **Inflexible:** Adding new import format = editing enum
4. **No fuzzy matching:** "reaading" (typo) won't match "reading"

### Refactoring Design

**Step 1: Extract Parser Service**

```swift
// BooksTrackerPackage/Sources/BooksTrackerFeature/Services/ReadingStatusParser.swift

/// Service for parsing reading status from various import formats
/// Supports Goodreads, StoryGraph, LibraryThing, and custom CSV formats
public struct ReadingStatusParser: Sendable {
    /// Mapping of common status strings to ReadingStatus
    /// Data-driven approach allows easy extension
    private static let statusMappings: [String: ReadingStatus] = [
        // Wishlist variations
        "wishlist": .wishlist,
        "want to read": .wishlist,
        "to-read": .wishlist,
        "want": .wishlist,
        "planned": .wishlist,
        
        // To-read variations
        "to read": .toRead,
        "unread": .toRead,
        "tbr": .toRead,
        
        // Currently reading
        "reading": .reading,
        "currently reading": .reading,
        "in progress": .reading,
        "started": .reading,
        
        // Finished/read
        "read": .read,
        "finished": .read,
        "completed": .read,
        "done": .read
    ]
    
    /// Parse reading status from string (case-insensitive)
    /// - Parameter string: Status string from CSV/import
    /// - Returns: ReadingStatus, or nil if no match
    public static func parse(_ string: String?) -> ReadingStatus? {
        guard let normalized = string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return nil
        }
        
        // Direct lookup (fast path)
        if let status = statusMappings[normalized] {
            return status
        }
        
        // Fuzzy matching (handles typos)
        return fuzzyMatch(normalized)
    }
    
    /// Fuzzy match using Levenshtein distance
    /// Handles common typos: "reaading" → "reading"
    private static func fuzzyMatch(_ input: String) -> ReadingStatus? {
        let threshold = 2  // Allow 2-character difference
        
        for (key, status) in statusMappings {
            if levenshteinDistance(input, key) <= threshold {
                return status
            }
        }
        
        return nil
    }
    
    /// Calculate Levenshtein distance between two strings
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var matrix = [[Int]](
            repeating: [Int](repeating: 0, count: s2Array.count + 1), 
            count: s1Array.count + 1
        )
        
        for i in 0...s1Array.count { matrix[i][0] = i }
        for j in 0...s2Array.count { matrix[0][j] = j }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    /// Load custom mappings from CSV (for advanced users)
    /// Format: "custom_status,reading_status"
    public static func loadCustomMappings(from csvURL: URL) throws -> [String: ReadingStatus] {
        // Implementation for future extensibility
        var customMappings: [String: ReadingStatus] = [:]
        // ... CSV parsing logic
        return customMappings
    }
}
```

**Step 2: Update ReadingStatus Enum**

```swift
// UserLibraryEntry.swift (cleaned up)
public enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case wishlist = "Wishlist"
    case toRead = "To Read"
    case reading = "Reading"
    case read = "Read"
    
    // Simple parser (delegates to service)
    public static func from(string: String?) -> ReadingStatus? {
        return ReadingStatusParser.parse(string)
    }
}
```

**Benefit:** Enum reduced from 94 lines → 8 lines!

**Step 3: Add Tests**

```swift
// ReadingStatusParserTests.swift

@Test func testParseGoodreadsStatuses() {
    #expect(ReadingStatusParser.parse("want to read") == .wishlist)
    #expect(ReadingStatusParser.parse("currently-reading") == .reading)
    #expect(ReadingStatusParser.parse("read") == .read)
}

@Test func testParseCaseInsensitive() {
    #expect(ReadingStatusParser.parse("READING") == .reading)
    #expect(ReadingStatusParser.parse("WaNt To ReAd") == .wishlist)
}

@Test func testFuzzyMatchHandlesTypos() {
    #expect(ReadingStatusParser.parse("reaading") == .reading)  // 1 char typo
    #expect(ReadingStatusParser.parse("finsihed") == .read)     // 2 char typo
}

@Test func testReturnsNilForInvalidStatus() {
    #expect(ReadingStatusParser.parse("invalid-status") == nil)
    #expect(ReadingStatusParser.parse("") == nil)
    #expect(ReadingStatusParser.parse(nil) == nil)
}

@Test func testParseLibraryThingFormat() {
    #expect(ReadingStatusParser.parse("tbr") == .toRead)
    #expect(ReadingStatusParser.parse("completed") == .read)
}
```

### Benefits
- ✅ Data-driven mapping (easy to extend for new formats)
- ✅ Fuzzy matching handles typos
- ✅ Testable with CSV files as input
- ✅ Enum stays focused on behavior, not parsing

### Implementation Effort
**Time:** 1 day  
**Files to Create:** 2 (parser service, tests)  
**Files to Modify:** 1 (UserLibraryEntry.swift)  
**Risk:** LOW (backward compatible)

---

## 🎯 Refactoring #3: Repository Pattern for SwiftData

### Current State Analysis
**Problem:** SwiftData queries scattered across views

```swift
// LibraryView.swift
@Query(filter: #Predicate<Work> { work in
    work.userLibraryEntries?.isEmpty == false
}) var libraryWorks: [Work]

// InsightsView.swift
@Query(filter: #Predicate<Work> { work in
    work.userLibraryEntries?.isEmpty == false
}) var allWorks: [Work]  // Duplicate!

// SearchView.swift
let descriptor = FetchDescriptor<Work>(
    predicate: #Predicate { $0.title.contains(searchText) }
)
```

**Issues:**
1. **Code duplication:** Same query logic in 3+ places
2. **Untestable:** Can't test queries without SwiftUI environment
3. **Performance:** No centralized query optimization
4. **Maintenance:** Changing query = updating multiple views

### Refactoring Design

**Step 1: Create Repository Protocol**

```swift
// BooksTrackerPackage/Sources/BooksTrackerFeature/Repositories/LibraryRepository.swift

/// Repository for Work/Edition/Author data access
/// Centralizes SwiftData queries and business logic
@MainActor
public protocol LibraryRepositoryProtocol {
    /// Fetch all works in user's library
    func fetchUserLibrary() throws -> [Work]
    
    /// Fetch works by reading status
    func fetchWorks(withStatus status: ReadingStatus) throws -> [Work]
    
    /// Search works by title or author
    func searchWorks(query: String) throws -> [Work]
    
    /// Fetch work by ISBN
    func fetchWork(byISBN isbn: String) throws -> Work?
}

@MainActor
public final class LibraryRepository: LibraryRepositoryProtocol {
    private let modelContext: ModelContext
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func fetchUserLibrary() throws -> [Work] {
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.userLibraryEntries?.isEmpty == false
            },
            sortBy: [SortDescriptor(\.title)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func fetchWorks(withStatus status: ReadingStatus) throws -> [Work] {
        // First fetch all works with library entries
        let works = try fetchUserLibrary()
        
        // Filter in-memory (SwiftData can't filter on to-many relationships)
        return works.filter { work in
            work.userEntry?.readingStatus == status
        }
    }
    
    public func searchWorks(query: String) throws -> [Work] {
        let lowercaseQuery = query.lowercased()
        
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.title.lowercased().contains(lowercaseQuery) ||
                work.authors?.contains { $0.name.lowercased().contains(lowercaseQuery) } == true
            }
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    public func fetchWork(byISBN isbn: String) throws -> Work? {
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.editions?.contains { $0.isbns.contains(isbn) } == true
            }
        )
        
        return try modelContext.fetch(descriptor).first
    }
}
```

**Step 2: Mock Repository for Testing**

```swift
// MockLibraryRepository.swift (for tests)

@MainActor
public final class MockLibraryRepository: LibraryRepositoryProtocol {
    public var mockWorks: [Work] = []
    
    public func fetchUserLibrary() throws -> [Work] {
        return mockWorks
    }
    
    public func fetchWorks(withStatus status: ReadingStatus) throws -> [Work] {
        return mockWorks.filter { $0.userEntry?.readingStatus == status }
    }
    
    public func searchWorks(query: String) throws -> [Work] {
        return mockWorks.filter { $0.title.contains(query) }
    }
    
    public func fetchWork(byISBN isbn: String) throws -> Work? {
        return mockWorks.first { work in
            work.editions?.contains { $0.isbns.contains(isbn) } ?? false
        }
    }
}
```

**Step 3: Update Views to Use Repository**

```swift
// LibraryView.swift (refactored)
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var repository: LibraryRepository?
    @State private var works: [Work] = []
    
    var body: some View {
        List(works) { work in
            WorkRowView(work: work)
        }
        .onAppear {
            repository = LibraryRepository(modelContext: modelContext)
            loadWorks()
        }
    }
    
    private func loadWorks() {
        do {
            works = try repository?.fetchUserLibrary() ?? []
        } catch {
            print("Failed to load library: \(error)")
        }
    }
}
```

**Step 4: Add Tests**

```swift
// LibraryRepositoryTests.swift

@Test func testFetchUserLibraryReturnsOnlyWorksWithEntries() async throws {
    let context = try await createTestContext()
    let repository = LibraryRepository(modelContext: context)
    
    // Create work WITH library entry
    let libraryWork = Work(title: "In Library")
    context.insert(libraryWork)
    let entry = UserLibraryEntry.createWishlistEntry(for: libraryWork)
    context.insert(entry)
    
    // Create work WITHOUT library entry
    let nonLibraryWork = Work(title: "Not In Library")
    context.insert(nonLibraryWork)
    
    try context.save()
    
    let results = try repository.fetchUserLibrary()
    
    #expect(results.count == 1)
    #expect(results.first?.title == "In Library")
}
```

### Benefits
- ✅ Testable without SwiftUI environment
- ✅ Reusable across views
- ✅ Centralized query optimization
- ✅ Easy to add caching layer
- ✅ Mockable for UI tests

### Implementation Effort
**Time:** 2-3 days  
**Files to Create:** 3 (repository, mock, tests)  
**Files to Modify:** 5-10 views  
**Risk:** MEDIUM (requires careful migration of all queries)

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Refactoring #2: ReadingStatusParser (1 day)
  - Low risk, immediate value
  - Foundation for future import formats

### Phase 2: Performance + Architecture (Week 2)
- [ ] Refactoring #1: EditionSelection Strategy (1-2 days)
  - Pairs well with Edition score caching (Performance Guide)
  - Unblocks `.manual` feature completion

### Phase 3: Data Layer (Week 3-4)
- [ ] Refactoring #3: Repository Pattern (2-3 days)
  - Highest effort, highest long-term value
  - Foundation for offline sync, caching, etc.

### Optional: Advanced Features (Future)
- [ ] Add caching layer to Repository (1 day)
- [ ] Implement offline-first sync (3-5 days)
- [ ] Add analytics/telemetry to Repository (1 day)

---

## Success Metrics

### Code Quality
- **Before:** Work.swift = 449 lines, UserLibraryEntry.swift = 294 lines
- **After:** Work.swift = ~250 lines, UserLibraryEntry.swift = ~150 lines
- **Reduction:** 40-50% in critical files

### Testability
- **Before:** 43 test files
- **After:** 50+ test files (7+ new for refactorings)
- **Coverage:** 80%+ for business logic

### Maintainability
- **Before:** Adding new feature = modifying 5-10 files
- **After:** Adding new feature = adding 1-2 new files

---

## Risk Mitigation

### Testing Strategy
1. **Unit tests first:** Test each component in isolation
2. **Integration tests:** Test component interactions
3. **Regression tests:** Ensure existing features work
4. **Manual QA:** Test on real devices with large datasets

### Rollback Plan
- Each refactoring is isolated (can be reverted independently)
- Git branches for each refactoring
- Feature flags for gradual rollout (if needed)

### Migration Path
- **Backward compatible:** Old code continues to work
- **Incremental:** Migrate one view at a time
- **Parallel systems:** New code runs alongside old (no big bang)

---

## Conclusion

**Total Effort:** 4-6 days (can be spread over 2-4 weeks)  
**Value:** HIGH (foundation for future scaling)  
**Risk:** LOW-MEDIUM (incremental, testable)

**Recommended Approach:**
1. Start with ReadingStatusParser (quick win)
2. Do EditionSelection Strategy + Performance optimizations together (synergy)
3. Save Repository Pattern for when you have 3-5 days for focused work

**Next Steps:**
1. Review this roadmap with team
2. Prioritize refactorings based on current feature work
3. Create GitHub issues for each refactoring
4. Schedule incremental implementation

**Questions?** I'm here to provide detailed implementation guidance for any of these refactorings!
