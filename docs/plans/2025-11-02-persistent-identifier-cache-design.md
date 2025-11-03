# Design: Migrate DTOMapper workCache to PersistentIdentifier

**Issue:** #168
**Date:** 2025-11-02
**Status:** Design Complete

## Problem Statement

The current `DTOMapper.workCache` stores `Work` objects directly, which creates robustness issues:

1. **Stale References:** If a `Work` is deleted elsewhere in the app, the cache holds a stale object reference
2. **Manual Cache Management:** Requires explicit `removeWorkFromCache()` calls at deletion sites
3. **Crash Risk:** Accessing deleted `Work` objects can lead to undefined behavior or crashes
4. **Tight Coupling:** Deletion logic in `EditionMetadataView` must know about cache implementation

**Current Implementation:**
```swift
// DTOMapper.swift:18
private var workCache: [String: Work] = [:] // volumeID -> Work

// EditionMetadataView.swift:412
dtoMapper?.removeWorkFromCache(work)
modelContext.delete(work)
```

## Proposed Solution

Migrate `workCache` from storing `Work` objects to storing `PersistentIdentifier`, with on-demand fetching and automatic staleness detection.

### Architecture Changes

**1. Cache Type Change**
```swift
// Before:
private var workCache: [String: Work] = [:]

// After:
private var workCache: [String: PersistentIdentifier] = [:]
```

**2. Update `mapToWork()` (Line 162-164)**
```swift
// Before:
for volumeID in dto.googleBooksVolumeIDs {
    workCache[volumeID] = work
}

// After:
for volumeID in dto.googleBooksVolumeIDs {
    workCache[volumeID] = work.persistentModelID
}
```

**3. Refactor `findExistingWork()` (Line 197-206)**
```swift
// Before:
private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
    for volumeID in volumeIDs {
        if let cachedWork = workCache[volumeID] {
            logger.info("Deduplication cache hit for volumeID: \(volumeID)")
            return cachedWork
        }
    }
    logger.info("Deduplication cache miss for volumeIDs: \(volumeIDs.joined(separator: ", "))")
    return nil
}

// After:
private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
    for volumeID in volumeIDs {
        if let persistentID = workCache[volumeID] {
            if let cachedWork = modelContext.model(for: persistentID) as? Work {
                logger.info("Deduplication cache hit for volumeID: \(volumeID)")
                return cachedWork
            } else {
                // Object was deleted, evict from cache
                workCache.removeValue(forKey: volumeID)
                logger.info("Evicted stale cache entry for deleted Work with volumeID: \(volumeID)")
            }
        }
    }
    logger.info("Deduplication cache miss for volumeIDs: \(volumeIDs.joined(separator: ", "))")
    return nil
}
```

**4. Delete `removeWorkFromCache()` Method (Line 173-179)**
- No longer needed with automatic staleness detection
- Simplifies deletion logic across the app

**5. Update Call Sites**
```swift
// EditionMetadataView.swift:412
// Before:
dtoMapper?.removeWorkFromCache(work)
modelContext.delete(work)

// After:
modelContext.delete(work)  // Cache will auto-clean on next access
```

## Benefits

1. **Automatic Staleness Detection:** `modelContext.model(for:)` returns `nil` for deleted objects
2. **Lazy Cache Cleanup:** Eviction happens automatically on next access, no manual calls needed
3. **Simpler Deletion Logic:** Removes need for `removeWorkFromCache()` calls
4. **More Robust:** Immune to external deletions, ModelContext teardowns, concurrent modifications
5. **Zero Behavior Change:** From user perspective, functionality is identical

## Error Handling & Edge Cases

### 1. Work Deleted Elsewhere
- `modelContext.model(for:)` returns `nil`
- Stale entry evicted from cache
- Continues searching remaining volumeIDs
- Returns `nil` if no valid Work found

### 2. Multiple VolumeIDs for Same Work
- All volumeIDs map to same `PersistentIdentifier`
- When Work deleted, first access evicts one entry
- Subsequent accesses evict remaining entries
- Eventually all stale entries cleaned

### 3. ModelContext Torn Down
- `model(for:)` returns `nil` gracefully
- Cache eviction proceeds normally
- No crashes or undefined behavior

### 4. Concurrent Deletions
- On-demand fetching prevents stale references
- Each access validates object still exists
- Thread-safe with `@MainActor` isolation

## Testing Strategy

### Test Cases

**1. Cache Hit with Valid Work**
- Store PersistentIdentifier in cache
- Verify `findExistingWork()` fetches and returns Work
- Confirm deduplication works across multiple DTOs

**2. Cache Hit with Deleted Work**
- Cache PersistentIdentifier
- Delete Work from ModelContext
- Verify `findExistingWork()` returns `nil`
- Confirm stale entry evicted from cache
- Next DTO with same volumeID creates new Work

**3. Cache Miss**
- Search for non-existent volumeID
- Verify returns `nil`
- Create new Work, confirm cached as PersistentIdentifier

**4. Multiple VolumeIDs for Same Work**
- Create Work with 3 googleBooksVolumeIDs
- Verify all 3 volumeIDs cached to same PersistentIdentifier
- Delete Work
- Access via each volumeID, confirm all evicted

**5. EditionMetadataView Deletion Flow**
- Delete library entry → cascades to Work deletion
- Verify no crashes
- Next search for same book creates fresh Work

### Test File
`BooksTrackerPackage/Tests/BooksTrackerFeatureTests/DTOMapperTests.swift`

## Migration Checklist

- [ ] Update `workCache` type declaration (Line 18)
- [ ] Update cache insertion in `mapToWork()` (Line 162-164)
- [ ] Refactor `findExistingWork()` with on-demand fetching (Line 197-206)
- [ ] Delete `removeWorkFromCache()` method (Line 173-179)
- [ ] Remove `removeWorkFromCache()` call in `EditionMetadataView.swift:412`
- [ ] Write unit tests for new behavior
- [ ] Run full test suite (verify zero regressions)
- [ ] Manual testing: Delete books, verify no crashes
- [ ] Update `clearCache()` method documentation (no functional change)

## Implementation Notes

### No Breaking Changes
- Public API unchanged (`clearCache()` still works)
- Caller code simplified (removes `removeWorkFromCache()` calls)
- Zero user-visible behavior change

### Performance Impact
- **Negligible:** `modelContext.model(for:)` is O(1) lookup by PersistentIdentifier
- Cache eviction only happens on deleted objects (rare)
- No additional memory overhead (PersistentIdentifier is lightweight)

### Backward Compatibility
- Not applicable (internal implementation detail)
- No migration of existing cache data needed (ephemeral cache)

## Related Issues

- **Issue #168:** Original bug report from Jules/Gemini Code Assist
- **PR #165:** Discussion thread where issue was identified

## References

- **Original Suggestion:** https://github.com/jukasdrj/books-tracker-v1/pull/165#discussion_r2482787788
- **SwiftData Docs:** PersistentIdentifier usage for safe object references
- **File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`
