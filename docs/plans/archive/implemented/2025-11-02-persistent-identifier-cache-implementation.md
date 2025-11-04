# PersistentIdentifier Cache Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate DTOMapper.workCache from storing Work objects to PersistentIdentifier for improved robustness against stale references and deletion edge cases.

**Architecture:** Replace direct Work object storage with PersistentIdentifier storage, fetch objects on-demand via `modelContext.model(for:)`, and add automatic staleness detection that evicts deleted objects lazily. This eliminates the need for manual `removeWorkFromCache()` calls.

**Tech Stack:** Swift 6.2, SwiftData, Swift Testing, @MainActor concurrency

**Design:** `docs/plans/2025-11-02-persistent-identifier-cache-design.md`

**Issue:** #168

---

## Task 1: Update DTOMapper Cache Type & Insertion

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift:18`
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift:162-164`

**Step 1: Update cache type declaration**

Change line 18 from:
```swift
private var workCache: [String: Work] = [:] // volumeID -> Work
```

To:
```swift
private var workCache: [String: PersistentIdentifier] = [:] // volumeID -> PersistentIdentifier
```

**Step 2: Update cache insertion in mapToWork()**

Change lines 162-164 from:
```swift
// Update cache
for volumeID in dto.googleBooksVolumeIDs {
    workCache[volumeID] = work
}
```

To:
```swift
// Update cache with PersistentIdentifier
for volumeID in dto.googleBooksVolumeIDs {
    workCache[volumeID] = work.persistentModelID
}
```

**Step 3: Verify compilation**

Run: `/build` (MCP slash command for quick build check)
Expected: Build succeeds with zero warnings

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift
git commit -m "refactor: Change workCache to store PersistentIdentifier (Issue #168)

Store PersistentIdentifier instead of Work objects for more robust
cache management. This is step 1 of the migration.

Related: #168"
```

---

## Task 2: Refactor findExistingWork() with Staleness Detection

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift:197-206`

**Step 1: Replace findExistingWork() implementation**

Replace lines 197-206 with:
```swift
/// Find existing Work by googleBooksVolumeIDs (for deduplication)
///
/// Uses PersistentIdentifier cache with on-demand fetching for robustness.
/// Automatically detects and evicts stale cache entries when Work is deleted.
///
/// Issue: https://github.com/jukasdrj/books-tracker-v1/issues/168
private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
    for volumeID in volumeIDs {
        if let persistentID = workCache[volumeID] {
            // Fetch Work from ModelContext (returns nil if deleted)
            if let cachedWork = modelContext.model(for: persistentID) as? Work {
                logger.info("Deduplication cache hit for volumeID: \(volumeID)")
                return cachedWork
            } else {
                // Work was deleted - evict stale entry
                workCache.removeValue(forKey: volumeID)
                logger.info("Evicted stale cache entry for deleted Work with volumeID: \(volumeID)")
            }
        }
    }
    logger.info("Deduplication cache miss for volumeIDs: \(volumeIDs.joined(separator: ", "))")
    return nil
}
```

**Step 2: Verify compilation**

Run: `/build`
Expected: Build succeeds with zero warnings

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift
git commit -m "refactor: Add automatic staleness detection to findExistingWork() (Issue #168)

Fetch Work objects on-demand via modelContext.model(for:) instead of
returning cached references directly. Automatically evict stale entries
when Work has been deleted.

This makes the cache resilient to external deletions and eliminates
the need for manual cache management.

Related: #168"
```

---

## Task 3: Remove removeWorkFromCache() Method

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift:169-179`

**Step 1: Delete removeWorkFromCache() method**

Delete lines 169-179 (the entire `removeWorkFromCache()` method):
```swift
// DELETE THIS ENTIRE METHOD:
// /// Removes a Work from the deduplication cache.
// /// Call this method when a Work is deleted to prevent returning stale data.
// public func removeWorkFromCache(_ work: Work) {
//     for volumeID in work.googleBooksVolumeIDs {
//         if workCache.removeValue(forKey: volumeID) != nil {
//             logger.info("Removed Work \(work.title) (volumeID: \(volumeID)) from deduplication cache.")
//         }
//     }
// }
```

**Step 2: Update clearCache() documentation (line ~182)**

Update the doc comment to reflect that manual cache management is no longer needed:
```swift
/// Clears the entire deduplication cache.
/// Call this when performing a full library reset.
/// Note: Manual cache cleanup is no longer needed - stale entries are
/// automatically evicted when Works are deleted.
public func clearCache() {
    workCache.removeAll()
    logger.info("Deduplication cache cleared.")
}
```

**Step 3: Verify compilation**

Run: `/build`
Expected: Build succeeds (EditionMetadataView will have compiler error - we'll fix that next)

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift
git commit -m "refactor: Remove manual removeWorkFromCache() method (Issue #168)

With automatic staleness detection in findExistingWork(), manual cache
cleanup is no longer necessary. The cache self-maintains on access.

Updated clearCache() documentation to reflect new behavior.

Related: #168"
```

---

## Task 4: Update EditionMetadataView Call Site

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/EditionMetadataView.swift:412`

**Step 1: Remove removeWorkFromCache() call**

Change line 412 from:
```swift
dtoMapper?.removeWorkFromCache(work)
modelContext.delete(work)
```

To:
```swift
modelContext.delete(work)  // Cache will auto-clean on next access
```

**Step 2: Verify compilation**

Run: `/build`
Expected: Build succeeds with zero warnings/errors

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/EditionMetadataView.swift
git commit -m "refactor: Simplify deletion logic in EditionMetadataView (Issue #168)

Remove manual removeWorkFromCache() call - the cache now automatically
detects and evicts stale entries when Works are deleted.

Related: #168"
```

---

## Task 5: Write Comprehensive Test Suite

**Files:**
- Create: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/DTOMapperCacheTests.swift`

**Step 1: Write test file header and setup**

Create new file:
```swift
import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for DTOMapper PersistentIdentifier cache behavior
/// Issue: https://github.com/jukasdrj/books-tracker-v1/issues/168
@MainActor
struct DTOMapperCacheTests {

    // MARK: - Test Infrastructure

    /// Create in-memory ModelContainer for testing
    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Create test WorkDTO with specific volumeIDs
    private func makeTestWorkDTO(
        title: String = "Test Work",
        volumeIDs: [String] = ["test-volume-1"]
    ) -> WorkDTO {
        return WorkDTO(
            title: title,
            originalLanguage: "en",
            firstPublicationYear: 2024,
            subjectTags: [],
            synthetic: false,
            primaryProvider: "google-books",
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: volumeIDs.first,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: volumeIDs,
            isbndbQuality: 0,
            lastISBNDBSync: nil,
            contributors: ["google-books"],
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )
    }
}
```

**Step 2: Write Test 1 - Cache Hit with Valid Work**

Add to test file:
```swift
// MARK: - Cache Hit Tests

@Test("Cache hit with valid Work returns existing Work")
func cacheHitWithValidWork() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create first Work with volumeID "vol-123"
    let dto1 = makeTestWorkDTO(title: "First Work", volumeIDs: ["vol-123"])
    let work1 = try mapper.mapToWork(dto1)

    // Create second DTO with same volumeID
    let dto2 = makeTestWorkDTO(title: "Second Work", volumeIDs: ["vol-123"])
    let work2 = try mapper.mapToWork(dto2)

    // Should return same Work (deduplication)
    #expect(work1.persistentModelID == work2.persistentModelID)
    #expect(work1.title == "First Work")  // Original title preserved
}

@Test("Cache hit with multiple volumeIDs returns Work on any match")
func cacheHitWithMultipleVolumeIDs() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create Work with 3 volumeIDs
    let dto1 = makeTestWorkDTO(title: "Multi-Volume Work", volumeIDs: ["vol-1", "vol-2", "vol-3"])
    let work1 = try mapper.mapToWork(dto1)

    // Search by different volumeID
    let dto2 = makeTestWorkDTO(title: "Should Find Existing", volumeIDs: ["vol-2"])
    let work2 = try mapper.mapToWork(dto2)

    #expect(work1.persistentModelID == work2.persistentModelID)
}
```

**Step 3: Write Test 2 - Cache Hit with Deleted Work**

Add to test file:
```swift
// MARK: - Stale Entry Tests

@Test("Cache automatically evicts deleted Work and creates new one")
func cacheEvictsDeletedWork() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create Work
    let dto1 = makeTestWorkDTO(title: "Original Work", volumeIDs: ["vol-deleted"])
    let work1 = try mapper.mapToWork(dto1)
    let originalID = work1.persistentModelID

    // Delete Work from ModelContext
    context.delete(work1)
    try context.save()

    // Create new DTO with same volumeID
    let dto2 = makeTestWorkDTO(title: "New Work After Deletion", volumeIDs: ["vol-deleted"])
    let work2 = try mapper.mapToWork(dto2)

    // Should create NEW Work (not return deleted one)
    #expect(work2.persistentModelID != originalID)
    #expect(work2.title == "New Work After Deletion")
}

@Test("Multiple volumeIDs all evicted when Work deleted")
func allVolumeIDsEvictedOnDeletion() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create Work with 3 volumeIDs
    let dto1 = makeTestWorkDTO(title: "Multi-ID Work", volumeIDs: ["vol-a", "vol-b", "vol-c"])
    let work1 = try mapper.mapToWork(dto1)

    // Delete Work
    context.delete(work1)
    try context.save()

    // Try to find via each volumeID - all should create new Works
    let dto2 = makeTestWorkDTO(title: "New Work A", volumeIDs: ["vol-a"])
    let work2 = try mapper.mapToWork(dto2)

    let dto3 = makeTestWorkDTO(title: "New Work B", volumeIDs: ["vol-b"])
    let work3 = try mapper.mapToWork(dto3)

    let dto4 = makeTestWorkDTO(title: "New Work C", volumeIDs: ["vol-c"])
    let work4 = try mapper.mapToWork(dto4)

    // All should be different Works (cache fully evicted)
    #expect(work2.persistentModelID != work3.persistentModelID)
    #expect(work3.persistentModelID != work4.persistentModelID)
    #expect(work2.persistentModelID != work4.persistentModelID)
}
```

**Step 4: Write Test 3 - Cache Miss**

Add to test file:
```swift
// MARK: - Cache Miss Tests

@Test("Cache miss creates new Work")
func cacheMissCreatesNewWork() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create first Work
    let dto1 = makeTestWorkDTO(title: "Work 1", volumeIDs: ["vol-1"])
    let work1 = try mapper.mapToWork(dto1)

    // Create second Work with different volumeID
    let dto2 = makeTestWorkDTO(title: "Work 2", volumeIDs: ["vol-2"])
    let work2 = try mapper.mapToWork(dto2)

    // Should be different Works
    #expect(work1.persistentModelID != work2.persistentModelID)
    #expect(work1.title == "Work 1")
    #expect(work2.title == "Work 2")
}
```

**Step 5: Write Test 4 - clearCache() Behavior**

Add to test file:
```swift
// MARK: - Cache Management Tests

@Test("clearCache() removes all entries")
func clearCacheRemovesAllEntries() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)
    let mapper = DTOMapper(modelContext: context)

    // Create multiple Works
    let dto1 = makeTestWorkDTO(title: "Work 1", volumeIDs: ["vol-1"])
    _ = try mapper.mapToWork(dto1)

    let dto2 = makeTestWorkDTO(title: "Work 2", volumeIDs: ["vol-2"])
    _ = try mapper.mapToWork(dto2)

    // Clear cache
    mapper.clearCache()

    // Next DTOs should create new Works (cache empty)
    let dto3 = makeTestWorkDTO(title: "Work 1 Repeat", volumeIDs: ["vol-1"])
    let work3 = try mapper.mapToWork(dto3)

    let dto4 = makeTestWorkDTO(title: "Work 2 Repeat", volumeIDs: ["vol-2"])
    let work4 = try mapper.mapToWork(dto4)

    // Should be different Works (not cached)
    #expect(work3.title == "Work 1 Repeat")
    #expect(work4.title == "Work 2 Repeat")
}
```

**Step 6: Run tests**

Run: `/test` (MCP slash command for Swift tests)
Expected: All tests pass (5 tests, 0 failures)

**Step 7: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/DTOMapperCacheTests.swift
git commit -m "test: Add comprehensive PersistentIdentifier cache tests (Issue #168)

Tests cover:
- Cache hits with valid Works (deduplication)
- Automatic stale entry eviction on deletion
- Cache misses creating new Works
- clearCache() behavior
- Multiple volumeIDs handling

All tests use Swift Testing framework with @MainActor isolation.

Related: #168"
```

---

## Task 6: Manual Verification & PR Preparation

**Step 1: Run full test suite**

Run: `/test`
Expected: All existing tests + new cache tests pass (0 failures)

**Step 2: Build for device/simulator**

Run: `/build`
Expected: Zero warnings, zero errors

**Step 3: Manual testing - Delete book flow**

1. Launch app in simulator: `/sim`
2. Add a book to library
3. Delete the book via EditionMetadataView
4. Search for same book again
5. Add it back to library
6. Verify: No crashes, book appears normally

**Step 4: Check git status**

```bash
git status
git log --oneline -6
```

Expected: 6 commits on `feature/persistent-id-cache` branch

**Step 5: Push branch and create PR**

```bash
git push -u origin feature/persistent-id-cache
gh pr create --title "Refactor: Migrate DTOMapper cache to PersistentIdentifier (Issue #168)" --body "$(cat <<'EOF'
## Summary

Migrates `DTOMapper.workCache` from storing `Work` objects directly to storing `PersistentIdentifier` for improved robustness against stale references.

## Changes

1. **Cache Type:** `[String: Work]` → `[String: PersistentIdentifier]`
2. **On-Demand Fetching:** `modelContext.model(for:)` fetches Work when needed
3. **Automatic Staleness Detection:** Returns `nil` for deleted Works, evicts stale entries
4. **Simplified Deletion:** Removed `removeWorkFromCache()` method and call site

## Benefits

- ✅ No manual cache management needed
- ✅ Immune to external deletions
- ✅ More robust against concurrent modifications
- ✅ Zero behavior change from user perspective

## Testing

- ✅ 5 new cache-specific tests (all passing)
- ✅ All existing tests pass (0 regressions)
- ✅ Manual verification: Delete/re-add book flow works correctly
- ✅ Zero warnings, zero errors

## Design

See `docs/plans/2025-11-02-persistent-identifier-cache-design.md`

Closes #168

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 6: Done!**

Report: PR created, ready for review.

---

## Notes for Engineer

### Key Concepts

**PersistentIdentifier:** SwiftData's safe reference to a model object that survives deletions. `modelContext.model(for:)` returns `nil` if object was deleted, making it perfect for cache validation.

**Lazy Eviction:** Instead of proactively removing cache entries when Works are deleted, we detect staleness on next access and evict then. This simplifies deletion logic throughout the app.

**@MainActor Isolation:** All DTOMapper methods run on main actor, so no thread-safety concerns with cache mutations.

### Testing Philosophy

We use Swift Testing (`@Test`, `#expect`) instead of XCTest. Each test:
1. Creates isolated in-memory ModelContainer
2. Tests ONE specific behavior
3. Uses descriptive test names
4. Expects exact outcomes with `#expect`

### Common Pitfalls

❌ **Don't** try to access `work.someProperty` after deleting it - will crash
✅ **Do** use `modelContext.model(for: persistentID)` to safely check existence

❌ **Don't** force-unwrap `modelContext.model(for:)` - it returns optional
✅ **Do** use `if let` or guard to handle `nil` case

❌ **Don't** cache `Work` objects across async boundaries
✅ **Do** cache `PersistentIdentifier` and fetch fresh on each access

### DRY Principles Applied

- Test helper methods (`makeTestContainer`, `makeTestWorkDTO`) eliminate duplication
- Single source of truth for cache behavior (in `findExistingWork()`)
- Reusable DTO creation pattern for tests

### YAGNI Principles Applied

- No complex cache invalidation logic - just check on access
- No cache expiry timers or TTL - not needed for this use case
- No cache statistics or metrics - keep it simple

### Related Skills

- `@superpowers:test-driven-development` - Follow RED-GREEN-REFACTOR if modifying
- `@superpowers:systematic-debugging` - If tests fail unexpectedly
- `@superpowers:verification-before-completion` - Run all verification steps before claiming done
