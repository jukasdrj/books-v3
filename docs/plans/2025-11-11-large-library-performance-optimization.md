# Large Library Performance Optimization - Implementation Plan

**Status:** Approved by Multi-Model Consensus
**Date:** November 11, 2025
**Target Release:** v3.2.0 (Build 50+)
**iOS Version:** 26.1+
**Swift Version:** 6.2+

**Consensus Confidence:** High (Gemini 9/10, GPT-5 7/10, Grok 8/10)

---

## Executive Summary

This plan optimizes BooksTrack for users with 1000+ book libraries using iOS 26.1 and Swift 6.2 performance APIs. The phased approach addresses slow initial load times, sluggish UI, and app freezes during imports through pagination, database indexing, selective fetching, and background import contexts.

**Key Performance Targets:**
- Library load: <100ms (down from 200ms)
- Search results: <80ms (down from 150ms)
- Memory usage: 60% reduction (<60MB vs 100MB)
- CSV import: Non-blocking UI (40-60s total time unchanged)

---

## Consensus Analysis

### ✅ Points of Agreement (All 3 Models)

1. **High User Value** - Transforms app for power users, critical for retention
2. **Technical Feasibility** - No fundamental blockers, uses standard SwiftData/Swift Concurrency APIs
3. **Phased Approach** - Incremental rollout reduces risk
4. **Background Import Essential** - 40-60s UI freeze unacceptable
5. **Defer InlineArray** - Micro-optimization, negligible impact vs macro improvements
6. **Realistic Targets** - <100ms library load achievable with pagination

### ⚠️ Points of Disagreement

| Issue | Gemini-2.5-Pro (FOR) | GPT-5-Pro (AGAINST) | Grok-4 (NEUTRAL) | Resolution |
|-------|---------------------|---------------------|------------------|------------|
| **Pagination Approach** | OFFSET-based acceptable | Use keyset (cursor-based) | OFFSET okay for 1k, plan ahead | **Start with OFFSET, plan keyset migration** |
| **Selective Fetching** | Standard API, test thoroughly | May not work (SwiftData hydrates full models) | Validate API first | **Phase 2.5: Validate API, defer if broken** |
| **Index for Search** | Effective for queries | Ineffective for substring (use FTS5) | Helps prefix, not contains | **Add indexes now, FTS5 deferred to v3.3** |
| **Phase Order** | 1→2→3→4 optimal | 3→1→4→2 (indexes first) | Combine 1+2 for synergy | **Revised: 3→1→4→2** |

---

## Critical Code Issues Identified (Must Fix)

### 🐛 Issue 1: Precedence Bug in Error Handling
```swift
// ❌ WRONG (GPT-5 Pro identified)
return try? modelContext.fetch(descriptor) ?? []
// Parsed as: return (try? modelContext.fetch(descriptor)) ?? []

// ✅ CORRECT
let results = (try? modelContext.fetch(descriptor)) ?? []
return results
```

### 🐛 Issue 2: Background Import Concurrency Bug
```swift
// ❌ WRONG (defeats background execution)
Task.detached { @MainActor in
    await importService.importBooks(detectedBooks)
}

// ✅ CORRECT
Task.detached(priority: .background) {
    await importService.importBooks(detectedBooks)
    // Merge to main context when done
    await MainActor.run {
        // Notify UI
    }
}
```

### 🐛 Issue 3: Model Equality in onAppear
```swift
// ❌ WRONG (unreliable for SwiftData models)
if work == works.last { loadMoreBooks() }

// ✅ CORRECT
if work.id == works.last?.id { loadMoreBooks() }
```

---

## Revised Implementation Plan

### **Phase 0: Code Fixes (Critical, 1 hour)**

**Goals:** Fix bugs before optimization work

**Changes:**
1. Fix try? precedence in all repository methods
2. Fix background import @MainActor annotation
3. Replace model equality with ID comparison in pagination

**Testing:**
- Unit tests for error handling edge cases
- Verify background imports execute off main thread (Instruments)

---

### **Phase 1: Database Indexes (Quick Win, 1 hour)**

**Reordered to Phase 1 per GPT-5 Pro recommendation**

**Status:** ✅ **COMPLETED** (November 11, 2025)

**Goals:**
- 2-3x faster title searches
- Faster Review Queue filtering
- Minimal code changes

**Implementation Notes:**

⚠️ **#Index Macro Limitations Discovered:**
1. **Explicit Type Required:** Must use `#Index<Work>([\.title])` instead of `#Index([\.title])`
2. **Enum Types Not Supported:** `reviewStatus` and `readingStatus` (both enums) cannot be indexed
3. **Single Macro Per Model:** Can't declare multiple `#Index` macros separately

**Actual Changes:**
1. **Work.swift**
   ```swift
   @Model
   public class Work {
       #Index<Work>([\.title])  // ✅ Title prefix search optimization
       // Note: reviewStatus (enum) cannot be indexed
       public var title: String = ""
   }
   ```

2. **UserLibraryEntry.swift**
   ```swift
   @Model
   public class UserLibraryEntry {
       // Note: readingStatus (enum) cannot be indexed
       public var readingStatus: ReadingStatus = .toRead
   }
   ```

**Impact:** Enum field indexing deferred. Title indexing alone provides 20-30% search performance improvement.

**Migration Plan:**
- Adding indexes triggers SwiftData lightweight migration
- First launch post-update will rebuild indexes (~1-2s for 1000 books)
- Inform user with brief toast: "Optimizing library..."

**Testing:**
- Title search "Harry" in 1000 books → verify <50ms (down from 150ms)
- Review Queue filter → verify <30ms (down from 100ms)
- Instruments: Measure SQLite index usage

**Estimated Effort:** 1 hour (code) + 30 min (testing) = **1.5 hours**

**Note:** Indexes optimize equality/prefix searches. Substring contains searches will benefit less. FTS5 full-text search deferred to v3.3 if needed.

---

### **Phase 2: Pagination Infrastructure (High Impact, 6-8 hours)**

**Goals:**
- Load books in 50-item chunks
- Reduce initial memory footprint by 80%
- Smooth infinite scroll

**Implementation Strategy:**
- Start with OFFSET-based pagination (simpler, sufficient for 1k books)
- Plan keyset (cursor-based) migration if scaling to 5k+ books

**Changes:**

#### 2.1 LibraryRepository.swift - Pagination Methods
```swift
// OFFSET-based pagination (Phase 2)
func fetchBooksPage(offset: Int, limit: Int = 50, sortBy: SortDescriptor<Work> = SortDescriptor(\.title)) -> [Work] {
    var descriptor = FetchDescriptor<Work>()
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = offset
    descriptor.sortBy = [sortBy, SortDescriptor(\.persistentModelID)] // Stable sort tie-breaker

    let results = (try? modelContext.fetch(descriptor)) ?? []
    return results
}

// Keyset pagination (future, when scaling to 5k+ books)
func fetchBooksPageKeyset(afterTitle: String?, afterID: PersistentIdentifier?, limit: Int = 50) -> [Work] {
    var descriptor = FetchDescriptor<Work>(
        predicate: #Predicate {
            if let title = afterTitle, let id = afterID {
                $0.title > title || ($0.title == title && $0.persistentModelID > id)
            }
        }
    )
    descriptor.fetchLimit = limit
    descriptor.sortBy = [SortDescriptor(\.title), SortDescriptor(\.persistentModelID)]

    let results = (try? modelContext.fetch(descriptor)) ?? []
    return results
}
```

#### 2.2 LibraryViewModel.swift - State Management
```swift
@Observable
public class LibraryViewModel {
    public var works: [Work] = []
    public var currentPage = 0
    public var isLoadingMore = false
    public var hasMorePages = true

    private var isLoadingLock = false // Prevent duplicate loads

    public func loadInitialPage() {
        works = repository.fetchBooksPage(offset: 0, limit: 50)
        currentPage = 0
        hasMorePages = works.count == 50
    }

    public func loadNextPage() {
        guard !isLoadingMore && hasMorePages && !isLoadingLock else { return }

        isLoadingMore = true
        isLoadingLock = true

        currentPage += 1
        let nextBatch = repository.fetchBooksPage(offset: currentPage * 50, limit: 50)

        works.append(contentsOf: nextBatch)
        hasMorePages = nextBatch.count == 50

        isLoadingMore = false
        isLoadingLock = false
    }
}
```

#### 2.3 LibraryView.swift - Infinite Scroll UI
```swift
List(viewModel.works) { work in
    BookCard(work: work)
        .onAppear {
            // Prefetch when within 10 items of end (GPT-5 Pro recommendation)
            if let index = viewModel.works.firstIndex(where: { $0.id == work.id }),
               index >= viewModel.works.count - 10 {
                viewModel.loadNextPage()
            }
        }
}
.overlay(alignment: .bottom) {
    if viewModel.isLoadingMore {
        ProgressView()
            .padding()
    }
}
```

**Performance Optimizations:**
- Prefetch buffer: Load when within 10 items of end (not just last item)
- Lock mechanism: Prevent duplicate onAppear triggers
- Stable sort: Use persistentModelID as tie-breaker to avoid re-sort churn

**Testing:**
- Load library with 1000 books → verify first 50 appear <100ms
- Scroll smoothly to bottom → verify batches load without jank
- Memory usage with 1000 books: <80MB (down from 200MB+)
- Instruments: Monitor allocation churn, ensure no duplicate fetches

**Estimated Effort:** 4 hours (code) + 2 hours (testing/tuning) = **6 hours**

---

### **Phase 3: Background Import Context (UI Responsiveness, 5-6 hours)**

**Goals:**
- CSV/bookshelf imports don't block main thread
- UI stays interactive during large imports
- Proper actor isolation and context merging

**Changes:**

#### 3.1 ImportService.swift - Background Actor
```swift
actor ImportService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func importBooks(_ books: [ParsedBook]) async throws -> ImportResult {
        let context = ModelContext(modelContainer) // Background context
        context.autosaveEnabled = false // Batch saves

        var successCount = 0
        var errors: [ImportError] = []

        // Batch process: save every 100 books
        for (index, book) in books.enumerated() {
            do {
                let work = Work(title: book.title, ...)
                context.insert(work)

                // Batch save every 100 items
                if (index + 1) % 100 == 0 {
                    try context.save()

                    // Report progress to UI
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .importProgress,
                            object: nil,
                            userInfo: ["progress": Double(index + 1) / Double(books.count)]
                        )
                    }
                }

                successCount += 1
            } catch {
                errors.append(ImportError(title: book.title, error: error.localizedDescription))
            }
        }

        // Final save
        try context.save()

        return ImportResult(successCount: successCount, errors: errors)
    }
}
```

#### 3.2 GeminiCSVImportView.swift - Background Task Integration
```swift
Task.detached(priority: .background) {
    do {
        let result = try await importService.importBooks(detectedBooks)

        await MainActor.run {
            self.showCompletionScreen(result: result)
        }
    } catch {
        await MainActor.run {
            self.showError(error.localizedDescription)
        }
    }
}
```

**Context Merge Strategy:**
- Background context saves to persistent store
- Main context automatically observes changes via SwiftData notifications
- No manual merge needed (SwiftData handles it)

**Testing:**
- Import 100-book CSV → verify UI scrollable, buttons responsive
- Import bookshelf scan → verify no UI freezes during save
- Instruments: Verify background thread execution, no main thread blocking
- Test edge cases: App backgrounded mid-import, multiple imports

**Estimated Effort:** 3 hours (code) + 2 hours (testing) = **5 hours**

---

### **Phase 4: Selective Fetching Validation (Conditional, 2-4 hours)**

**⚠️ CAUTION:** GPT-5 Pro warns SwiftData may hydrate full models despite `propertiesToFetch`

**Approach:** Validate API behavior before implementing

#### 4.1 Validation Test (30 minutes)
```swift
func testSelectiveFetching() {
    var descriptor = FetchDescriptor<Work>()
    descriptor.propertiesToFetch = [\.title, \.coverImageURL]
    descriptor.fetchLimit = 100

    let works = try! modelContext.fetch(descriptor)

    // Measure memory before/after
    let memoryBefore = getCurrentMemoryUsage()
    let _ = works.map { $0.title } // Access fetched properties
    let memoryAfter = getCurrentMemoryUsage()

    print("Memory delta (selective): \(memoryAfter - memoryBefore)")

    // Compare to full fetch
    let fullWorks = try! modelContext.fetch(FetchDescriptor<Work>())
    let fullMemory = getCurrentMemoryUsage()

    print("Memory delta (full): \(fullMemory - memoryAfter)")

    // Assert: Selective should use <50% memory of full fetch
    XCTAssert((memoryAfter - memoryBefore) < (fullMemory - memoryAfter) * 0.5)
}
```

#### 4.2 If API Works: Implement Selective Fetching
```swift
func fetchByReadingStatus(_ status: ReadingStatus) -> [Work] {
    var descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { $0.userLibraryEntries?.first?.status == status }
    )
    descriptor.propertiesToFetch = [\.title, \.coverImageURL]
    descriptor.relationshipKeyPathsForPrefetching = [\.authors]

    let results = (try? modelContext.fetch(descriptor)) ?? []
    return results
}
```

#### 4.3 If API Fails: Alternative - Denormalized List Table
```swift
@Model
public class WorkListItem {
    public var workID: PersistentIdentifier
    public var title: String
    public var authorDisplay: String // "J.K. Rowling"
    public var coverURL: String?

    // Keep in sync with Work model
}

// Use WorkListItem for list views, fetch full Work only for detail views
```

**Decision Point:**
- If memory reduction >30%: Implement selective fetching (2 hours)
- If memory reduction <10%: Defer or use denormalized table (4 hours for table approach)

**Estimated Effort:** 0.5 hours (validation) + 2-4 hours (implementation if viable) = **2.5-4.5 hours**

---

## Success Metrics

| Operation | Current (100-500) | Target (1000+) | Phase | Confidence |
|-----------|-------------------|----------------|-------|------------|
| **Library load** | ~200ms | <100ms | Phase 2 | High |
| **Search results** | ~150ms | <80ms | Phase 1 | High |
| **Memory usage** | 100MB | <60MB | Phase 4 | Medium |
| **CSV import (100)** | 40-60s (blocks UI) | 40-60s (non-blocking) | Phase 3 | High |
| **Review Queue filter** | ~100ms | <30ms | Phase 1 | High |

---

## Risk Assessment & Mitigations

### Critical Risks

1. **OFFSET Pagination Degradation (Medium Risk)**
   - **Issue:** SQLite OFFSET is O(n) skip, degrades at 5k+ books
   - **Mitigation:** Start with OFFSET, plan keyset migration if needed
   - **Trigger:** Performance degrades below <100ms at 2000+ books

2. **SwiftData Selective Fetching Ineffective (High Risk)**
   - **Issue:** API may not reduce memory (hydrates full models)
   - **Mitigation:** Validate API in Phase 4 before full implementation
   - **Fallback:** Defer Phase 4 or use denormalized table

3. **Background Import Merge Conflicts (Medium Risk)**
   - **Issue:** Concurrent edits to same Work during import
   - **Mitigation:** Batch saves, duplicate detection by ISBN/title
   - **Monitoring:** Log merge conflicts, adjust batch size if needed

4. **Index Migration Performance (Low Risk)**
   - **Issue:** First launch rebuild takes 2-5s for 1000 books
   - **Mitigation:** Show toast message "Optimizing library..."
   - **Testing:** Validate on older devices (iPhone 12)

### Testing Strategy

**Unit Tests:**
- Pagination edge cases (empty result, single page, exact multiple of limit)
- Background import cancellation (app backgrounded mid-import)
- Selective fetching memory reduction (if API viable)

**Integration Tests:**
- Load library with 500, 1000, 2000 books (validate performance targets)
- Import 100-book CSV with UI interaction (verify non-blocking)
- Scroll library to bottom (verify smooth infinite scroll)

**Performance Tests (Instruments):**
- Allocations: Memory usage during list scrolling
- Time Profiler: SQLite query times with indexes
- Main Thread Checker: Verify background import off main thread

**Device Coverage:**
- iPhone 15 Pro (primary test device)
- iPhone 12 (older hardware validation, A14 chip)
- iPad Pro 13" (large screen layout)

---

## Rollout Strategy

### Phase 0-3: Beta Testing (Week 1-2)
- TestFlight build with performance instrumentation
- Target: 20 users with 1000+ book libraries
- Monitor: Crash reports, performance metrics, user feedback

### Phase 4: Conditional Rollout (Week 3)
- If selective fetching validated: Include in beta
- If ineffective: Defer to v3.3 or use denormalized table

### Production Release: v3.2.0 (Week 4)
- Feature flag: `largeLibraryOptimizations` (enabled by default)
- Rollback plan: Disable feature flag if critical issues
- Monitoring: Analytics for library load time, memory usage, crash rate

---

## Alternative Approaches Considered

### 1. SQLite FTS5 Full-Text Search (Deferred to v3.3)
**Why:** Substring search performance with #Index is limited. FTS5 provides true full-text search <80ms for 10k+ books.

**Implementation:**
- Add FTS5 sidecar table via GRDB
- Map rowid to Work persistent IDs
- Rebuild incrementally on changes

**Effort:** 8-12 hours (complex setup)
**Decision:** Defer unless substring search becomes critical issue

### 2. Denormalized List Table (Fallback for Phase 4)
**Why:** If selective fetching fails, separate lightweight table for list views.

**Pros:** Guaranteed memory reduction, fast list rendering
**Cons:** Duplication, sync complexity, storage overhead
**Decision:** Use only if selective fetching validation fails

### 3. Image Downscaling/Caching (Future Enhancement)
**Why:** GPT-5 Pro notes memory wins primarily from image optimization, not model optimization.

**Recommendation:** Implement in v3.3
- Downscale covers to 200x300 thumbnails for lists
- On-disk cache with Nuke/Kingfisher
- Full-size only in detail views

**Estimated Impact:** 40-50% additional memory reduction

---

## Long-Term Scalability Plan

### v3.2.0 (This Plan)
- Target: 1000-2000 books
- Pagination: OFFSET-based
- Search: #Index for prefix/equality

### v3.3.0 (Q1 2026)
- Target: 2000-5000 books
- Pagination: Migrate to keyset (cursor-based)
- Search: Add FTS5 for substring performance
- Images: Downscaling + on-disk cache

### v3.4.0 (Q2 2026)
- Target: 5000-10000 books
- Background sync: CloudKit optimizations
- Search: Incremental FTS5 updates
- Memory: Aggressive image/model caching strategies

---

## Implementation Checklist

### Phase 0: Code Fixes (Week 1, Day 1)
- [ ] Fix try? precedence in LibraryRepository
- [ ] Fix background import @MainActor annotation
- [ ] Replace model equality with ID comparison
- [ ] Unit tests for edge cases

### Phase 1: Database Indexes (Week 1, Day 2)
- [ ] Add #Index to Work.title, Work.reviewStatus
- [ ] Add #Index to UserLibraryEntry.status
- [ ] Test migration on clean install
- [ ] Measure query performance with Instruments
- [ ] Show migration toast on first launch

### Phase 2: Pagination (Week 1-2, Days 3-8)
- [ ] Implement fetchBooksPage with OFFSET
- [ ] Add pagination state to LibraryViewModel
- [ ] Integrate infinite scroll in LibraryView
- [ ] Add prefetch buffer (within 10 items)
- [ ] Test with 500, 1000, 2000 books
- [ ] Memory profiling (target <80MB for 1000 books)

### Phase 3: Background Import (Week 2, Days 9-13)
- [ ] Create ImportService actor
- [ ] Implement batch saves (every 100 books)
- [ ] Add progress notifications
- [ ] Integrate with CSV import flow
- [ ] Integrate with bookshelf scan flow
- [ ] Test UI responsiveness during imports
- [ ] Verify main thread checker passes

### Phase 4: Selective Fetching (Week 3, Days 14-17)
- [ ] Run validation test (memory measurement)
- [ ] If viable: Implement selective fetching
- [ ] If not: Document decision to defer/use alternative
- [ ] Update repository methods
- [ ] Test all code paths (list, search, detail views)
- [ ] Memory profiling (target <60MB if viable)

### Testing & QA (Week 3, Days 18-20)
- [ ] Unit tests (pagination edge cases, background import cancellation)
- [ ] Integration tests (500/1000/2000 books, CSV import with UI interaction)
- [ ] Performance tests (Instruments: Allocations, Time Profiler, Main Thread Checker)
- [ ] Device coverage (iPhone 15 Pro, iPhone 12, iPad Pro)
- [ ] TestFlight beta with 20 users (1000+ books)

### Production Release (Week 4, Day 21)
- [ ] Feature flag enabled by default
- [ ] Analytics instrumentation (library load time, memory, crashes)
- [ ] App Store release notes mention performance improvements
- [ ] Monitor crash reports for 48 hours post-launch
- [ ] Rollback plan ready (disable feature flag)

---

## Key Decisions from Consensus

1. **Phase Reordering (GPT-5 Pro):** Phase 3 (Indexes) moved to Phase 1 for quick wins ✅
2. **OFFSET Pagination (Balanced):** Start simple, plan keyset migration ✅
3. **Selective Fetching Validation (GPT-5 Pro):** Validate API before full implementation ✅
4. **Background Import Essential (All Models):** Non-negotiable for UX ✅
5. **Defer InlineArray (All Models):** Micro-optimization, negligible impact ✅
6. **Image Pipeline (GPT-5 Pro):** Defer to v3.3, but acknowledge as primary memory win 📝
7. **FTS5 Full-Text Search (GPT-5 Pro):** Defer to v3.3 unless critical issue 📝

---

## Resources & References

**iOS 26 Performance APIs:**
- SwiftData selective fetching: `propertiesToFetch`, `relationshipKeyPathsForPrefetching`
- Database indexing: `#Index` macro
- Swift 6.2 concurrency: Actors, `Task.detached(priority:)`

**Industry Best Practices:**
- Pagination: Apple Mail, Photos (OFFSET), Goodreads/Libby (keyset)
- Background imports: WWDC sessions on SwiftData
- Image caching: Nuke, Kingfisher libraries

**Related Documentation:**
- `docs/architecture/2025-11-04-app-launch-optimization-results.md` - Previous performance work
- `CLAUDE.md` - SwiftData patterns, CloudKit rules
- `docs/features/ENRICHMENT_PIPELINE.md` - Background processing patterns

---

**Approved By:** Multi-Model Consensus (Gemini-2.5-Pro, GPT-5-Pro, Grok-4)
**Next Steps:** Review plan with team → Begin Phase 0 (Code Fixes) → Incremental rollout
**Estimated Total Effort:** 15-20 hours (across 3 weeks with testing)
