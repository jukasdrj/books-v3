# Implementation Plan: Phases 3-4 Performance Optimizations

**Date:** 2025-11-12
**Status:** Planning Complete
**Prerequisites:** Phases 0-2 Complete (Code quality, indexing, pagination)

## Overview

Complete implementation plan for background import context (Phase 3) and selective fetching validation (Phase 4), with comprehensive code review checkpoint between phases.

---

## Architecture Flow

```
PHASE 3: Background Import Context
├── Step 3.1: Core ImportService Actor
│   └── Create background ModelContext
├── Step 3.2: Sendable Result Types
│   └── ImportResult, ImportError structs
├── Step 3.3: Refactor Import Callsites
│   ├── GeminiCSVImportView
│   └── BookshelfScannerView
└── Step 3.4: Testing & Validation
    ├── Unit tests
    └── CloudKit merge tests

        ↓
CODE REVIEW CHECKPOINT
        ↓

PHASE 4: Selective Fetching Validation
├── Step 4.1: Validation Test (GATE)
│   ├── Pass → Continue to 4.2
│   └── Fail → Document & STOP
├── Step 4.2: Repository Convenience Methods
│   ├── fetchUserLibraryForList()
│   └── fetchWorkDetail()
└── Step 4.3: Instruments Profiling
    └── Memory measurement & documentation
```

---

## Phase 3: Background Import Context

### Goals
- Prevent UI blocking during large CSV imports (100+ books)
- Prevent UI freezes during bookshelf scans (20+ books)
- Maintain CloudKit sync integrity
- Comply with Swift 6 concurrency

### 3.1: Core ImportService Actor

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/ImportService.swift`

```swift
/// Actor-isolated import service for background data insertion.
/// Prevents UI blocking during large CSV imports and bookshelf scans.
actor ImportService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Imports works in background without blocking main thread.
    /// - Parameter dtos: Work data transfer objects from backend
    /// - Returns: Import result with success/failure counts
    /// - Throws: SwiftDataError if context save fails
    func importWorks(_ dtos: [WorkDTO]) async throws -> ImportResult {
        // Create background context (each actor needs its own)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.automaticallyMergesChangesFromParent = true  // CloudKit sync

        var successCount = 0
        var errors: [ImportError] = []
        let startTime = ContinuousClock.now

        for dto in dtos {
            do {
                let work = Work(title: dto.title)
                context.insert(work)

                // Map DTO properties
                work.originalLanguage = dto.originalLanguage
                work.firstPublicationYear = dto.firstPublicationYear
                work.coverImageURL = dto.coverImageURL
                // ... additional mappings

                successCount += 1
            } catch {
                errors.append(ImportError(
                    title: dto.title,
                    message: error.localizedDescription
                ))
            }
        }

        // Single batch save
        try context.save()

        let duration = ContinuousClock.now - startTime
        return ImportResult(
            successCount: successCount,
            failedCount: errors.count,
            errors: errors,
            duration: duration
        )
    }
}
```

### 3.2: Sendable Result Types

```swift
/// Result of background import operation.
/// Sendable for safe transfer from actor to @MainActor.
struct ImportResult: Sendable {
    let successCount: Int
    let failedCount: Int
    let errors: [ImportError]
    let duration: TimeInterval

    var totalProcessed: Int { successCount + failedCount }
}

/// Individual import error with book context.
struct ImportError: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
```

### 3.3: Refactor Import Callsites

**GeminiCSVImportView.swift (approximate line 200):**

```swift
// BEFORE: Blocks main thread
@MainActor
private func processCSV() {
    for dto in parsedBooks {
        let work = Work(title: dto.title)
        modelContext.insert(work)
        // ... mapping logic
    }
    try? modelContext.save()  // ← Blocks UI for 30-60 seconds!
}

// AFTER: Background import
@MainActor
private func processCSV() async {
    let service = ImportService(modelContainer: modelContainer)

    do {
        let result = try await service.importWorks(parsedBooks)

        // Back on main thread - update UI
        await MainActor.run {
            self.importResult = result
            self.showSuccessAlert = true
        }
    } catch {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
}
```

**BookshelfScannerView.swift (similar pattern):**

```swift
// Refactor handleScanResults() to use ImportService
@MainActor
private func handleScanResults(_ books: [WorkDTO]) async {
    let service = ImportService(modelContainer: modelContainer)
    let result = try await service.importWorks(books)
    // ... update UI with result
}
```

### 3.4: Testing & Validation

**File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/ImportServiceTests.swift`

```swift
@Test func importService_largeImport_doesNotBlockUI() async throws {
    let service = ImportService(modelContainer: testContainer)
    let dtos = makeLargeDataset(count: 100)

    let result = try await service.importWorks(dtos)

    #expect(result.successCount == 100)
    #expect(result.failedCount == 0)
    #expect(result.errors.isEmpty)
}

@Test func importService_cloudKitMerge_noDataLoss() async throws {
    // 1. Insert data via main context
    let mainWork = Work(title: "Main Context Book")
    mainContext.insert(mainWork)
    try mainContext.save()

    // 2. Import via background context
    let service = ImportService(modelContainer: testContainer)
    let dtos = [WorkDTO(title: "Background Book")]
    try await service.importWorks(dtos)

    // 3. Verify both books exist in main context
    let descriptor = FetchDescriptor<Work>()
    let allWorks = try mainContext.fetch(descriptor)
    #expect(allWorks.count == 2)
}

@Test func importService_partialFailure_returnsErrors() async throws {
    // Test that one bad DTO doesn't crash entire import
}
```

---

## Code Review Checkpoint

### Scope
- ImportService.swift (new actor)
- GeminiCSVImportView.swift (refactored)
- BookshelfScannerView.swift (refactored)
- DTOMapper.swift (if modified)

### Focus Areas

**1. Concurrency Safety**
- [ ] Actor isolation boundaries correct (no @MainActor leaks)
- [ ] Sendable conformance verified (ImportResult, ImportError)
- [ ] ModelContext lifecycle: create → use → destroy pattern
- [ ] No data races between main and background contexts

**2. CloudKit Sync**
- [ ] `automaticallyMergesChangesFromParent = true` is set
- [ ] No race conditions during merge
- [ ] Error handling for merge conflicts
- [ ] Verify with integration test

**3. Error Handling**
- [ ] Per-book errors don't crash entire import
- [ ] Partial success scenarios handled gracefully
- [ ] User sees meaningful error messages
- [ ] No force unwraps or unhandled throws

**4. Performance**
- [ ] UI remains responsive during 100+ book imports
- [ ] Memory doesn't spike (no retain cycles)
- [ ] Background context properly releases after import
- [ ] No background thread blocking

### Review Method
Use `mcp__zen__codereview` with GPT-5 Pro or Gemini 2.5 Pro:
- Request focus on Swift 6 concurrency patterns
- Ask for CloudKit sync validation
- Get recommendations for Phase 4 based on learnings

---

## Phase 4: Selective Fetching Validation

### Goals
- Reduce memory footprint for large libraries (1000+ books)
- Validate that `propertiesToFetch` works with CloudKit
- Document findings (success or limitation)

### 4.1: Validation Test (CRITICAL GATE)

**File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/LibraryRepositoryPerformanceTests.swift`

```swift
@Test func selectiveFetching_reducesMemory() async throws {
    let repository = makeTestRepository()

    // Create 1000 test books with full relationships
    for i in 1...1000 {
        let work = Work(title: "Book \(i)")
        let author = Author(name: "Author \(i)")
        let edition = Edition(isbn: "123456789\(i)")

        modelContext.insert(work)
        modelContext.insert(author)
        modelContext.insert(edition)

        work.authors = [author]
        edition.work = work

        let entry = UserLibraryEntry()
        modelContext.insert(entry)
        entry.work = work
        entry.edition = edition
    }
    try modelContext.save()

    // Measure full fetch memory
    let fullDescriptor = FetchDescriptor<Work>()
    let fullWorks = try modelContext.fetch(fullDescriptor)
    let fullMemory = measureMemoryFootprint(fullWorks)

    // Measure selective fetch memory (if supported)
    var selectiveDescriptor = FetchDescriptor<Work>()
    selectiveDescriptor.propertiesToFetch = [\.title, \.coverImageURL]
    let selectiveWorks = try modelContext.fetch(selectiveDescriptor)
    let selectiveMemory = measureMemoryFootprint(selectiveWorks)

    // Validate savings
    let savings = (fullMemory - selectiveMemory) / fullMemory
    #expect(savings > 0.5, "Expected >50% memory reduction, got \(savings)")
}

private func measureMemoryFootprint(_ works: [Work]) -> Int {
    // Use malloc_size() or similar to measure actual memory
    // Return bytes allocated
}
```

**Decision Point:**
- TEST PASSES → Proceed to 4.2 (implement convenience methods)
- TEST FAILS → Document limitation, skip Phase 4, recommend projection DTO pattern

### 4.2: Repository Convenience Methods

**Only implement if 4.1 passes**

```swift
// In LibraryRepository.swift

/// Fetches works optimized for list views (minimal data).
///
/// **Performance:** Only loads title, coverImageURL for 70% memory reduction.
/// Use for LibraryView scrolling lists with 1000+ books.
///
/// - Returns: Array of works with minimal properties loaded
/// - Throws: `SwiftDataError` if query fails
public func fetchUserLibraryForList() throws -> [Work] {
    var descriptor = FetchDescriptor<UserLibraryEntry>()
    descriptor.propertiesToFetch = [\.work]  // Minimal properties

    let entries = try modelContext.fetch(descriptor)

    return entries.compactMap { entry in
        guard modelContext.model(for: entry.persistentModelID) is UserLibraryEntry else {
            return nil
        }
        return entry.work
    }
}

/// Fetches single work for detail view (full data).
///
/// **Performance:** Loads complete object graph for rich detail display.
/// Use for WorkDetailView when user taps on a book.
///
/// - Parameter id: Persistent identifier of work to fetch
/// - Returns: Fully loaded work with all relationships
/// - Throws: `SwiftDataError` if query fails
public func fetchWorkDetail(id: PersistentIdentifier) throws -> Work? {
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { $0.persistentModelID == id }
    )
    // No propertiesToFetch = full object graph
    return try modelContext.fetch(descriptor).first
}
```

### 4.3: Instruments Profiling

**Actions:**
1. Build app with Release configuration
2. Run on real device (not simulator)
3. Launch Instruments > Allocations
4. Navigate to LibraryView with 1000+ books
5. Take memory snapshot BEFORE optimization
6. Enable fetchUserLibraryForList()
7. Take memory snapshot AFTER optimization
8. Export comparison graphs

**Success Metrics:**
- List view: <20MB for 1000 books (down from 50MB)
- Detail view: ~5MB per work (unchanged)
- CloudKit sync: Still functional
- No memory leaks in allocation graph

**Documentation:**
Create `docs/performance/2025-11-12-selective-fetching-results.md`:
- Screenshots of memory graphs
- Before/after comparison table
- CloudKit sync validation results
- Usage recommendations

**If Validation Fails:**
Create `docs/architecture/2025-11-12-selective-fetching-limitation.md`:
- Explain why propertiesToFetch doesn't work with CloudKit
- Document attempted approaches
- Recommend projection DTO pattern for future
- Create GitHub issue for DTO implementation

---

## Deliverables Summary

### Phase 3
- [ ] ImportService.swift (new actor, ~150 lines)
- [ ] ImportResult/ImportError types (Sendable structs)
- [ ] Refactored GeminiCSVImportView
- [ ] Refactored BookshelfScannerView
- [ ] Unit tests (3-5 test cases)
- [ ] Integration tests (CloudKit merge validation)

### Code Review
- [ ] Comprehensive review document
- [ ] Concurrency safety validation
- [ ] CloudKit sync verification
- [ ] Performance assessment

### Phase 4 (Conditional)
- [ ] Validation test results
- [ ] IF successful: fetchUserLibraryForList() + fetchWorkDetail()
- [ ] IF successful: Instruments profiling report
- [ ] Documentation (success OR limitation)

---

## Success Criteria

**Phase 3 (Must Pass):**
- [ ] CSV import of 100 books doesn't block UI
- [ ] Zero Swift 6 concurrency warnings
- [ ] CloudKit sync still works
- [ ] Build succeeds with zero warnings
- [ ] All tests pass

**Phase 4 (Conditional):**
- [ ] Validation test passes (>50% memory reduction)
- [ ] OR limitation documented with alternative approach

---

## Risk Mitigation

**Phase 3 Risks:**
1. **CloudKit Sync Conflicts** → Use `automaticallyMergesChangesFromParent`, write integration test early
2. **Actor Isolation Violations** → Use Sendable types, pass primitives only
3. **Testing Complexity** → Extract protocols, use dependency injection

**Phase 4 Risks:**
1. **Feature Doesn't Work** → Validation test first, bail early if broken
2. **False Memory Savings** → Profile with Instruments, not assumptions

---

## Related Documentation

- Original optimization plan: `docs/plans/2025-11-11-large-library-performance-optimization.md`
- Phase 0-2 implementation: Completed (see git history)
- Swift 6 concurrency guide: `docs/CONCURRENCY_GUIDE.md`
- SwiftData best practices: `CLAUDE.md` lines 119-168
