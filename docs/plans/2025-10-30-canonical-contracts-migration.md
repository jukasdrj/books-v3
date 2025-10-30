# Canonical Data Contracts Migration Design

**Date:** 2025-10-30
**Status:** Approved for Implementation
**Approach:** Bottom-Up (Backend First)
**Strategy:** Conservative (preserve backward compatibility)

## Executive Summary

This design document outlines the migration of BooksTrack's backend enrichment services and iOS search/enrichment layers to use canonical data contracts (WorkDTO/EditionDTO/AuthorDTO). The migration follows a three-phase bottom-up approach: (1) Backend services, (2) iOS integration, (3) Conservative cleanup after validation period.

**Key Insight:** Only endpoints that return enriched book data need canonical contracts. Job control endpoints (start/cancel) and minimal parsers (CSV) are already compatible.

---

## Background

### Current State (v3.0.0)

**Backend:**
- ✅ 3 canonical `/v1/` endpoints deployed: `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`
- ✅ TypeScript canonical types defined: `WorkDTO`, `EditionDTO`, `AuthorDTO`, `ApiResponse<T>`
- ❌ Enrichment services (`enrichBatch`, `enrichBooksParallel`) still return legacy Google Books format
- ❌ AI scanning uses legacy `handleAdvancedSearch` internally

**iOS:**
- ✅ Swift Codable DTOs implemented (5 files, 100% TypeScript alignment)
- ✅ DTOMapper implemented with deduplication (insert-before-relate pattern)
- ✅ 15 tests passing (8 DTO parsing + 7 mapper tests)
- ❌ `BookSearchAPIService` still uses legacy `/search/*` endpoints
- ❌ `EnrichmentService` expects legacy WebSocket response format

### Problem Statement

8 iOS files reference legacy API structures, but only 2 require updates:
- **Critical:** `BookSearchAPIService.swift`, `EnrichmentService.swift` (consume enriched book data)
- **No changes needed:** `EnrichmentAPIClient`, `GeminiCSVImportService`, `BatchCaptureView`, etc. (job control only)

---

## Architecture Decision: Bottom-Up Migration

### Approach Comparison

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Bottom-Up: Backend First** | Safest, backward compatible, backend changes validated independently | Slowest (3 phases) | ✅ **SELECTED** |
| All-At-Once with Feature Flag | Fastest to production, easy rollback | Moderate risk, requires coordination | ❌ Rejected |
| Service-by-Service Migration | Incremental validation, catch edge cases early | Mixed API versions during migration | ❌ Rejected |

**Rationale:** We control both backend and iOS, so backward compatibility during migration is less critical than safety. Backend changes can be validated with unit/integration tests before iOS touches them.

---

## Phase 1: Backend Migration

### Scope

**Files to Modify:**

1. **`parallel-enrichment.js`** (shared enrichment helper)
   - Currently: Calls `handleAdvancedSearch` (legacy handler)
   - Change: Call `handleSearchAdvanced` (v1 canonical handler)
   - Impact: All services using this helper now return canonical format

2. **`enrichment.js`** (`enrichBatch` function)
   - Currently: WebSocket sends `enrichedWorks: [VolumeItem]` (legacy Google Books)
   - Change: Send `{ works: [WorkDTO], authors: [AuthorDTO] }` (canonical)
   - Impact: iOS `EnrichmentService` receives structured DTOs

3. **`ai-scanner.js`** (`processBookshelfScan` function)
   - Currently: Enrichment via legacy `handleAdvancedSearch`
   - Change: Use `handleSearchAdvanced` (v1) through `enrichBooksParallel`
   - Impact: Bookshelf scan results have canonical DTOs

### Technical Details

**Enrichment Response Transformation:**

```javascript
// OLD: Legacy Google Books format
await doStub.pushProgress({
  progress: 1.0,
  result: {
    enrichedWorks: [
      {
        kind: "books#volume",
        id: "volume-id",
        volumeInfo: { title: "...", authors: ["..."], ... }
      }
    ]
  }
});

// NEW: Canonical format
const canonicalResponse = await handleSearchAdvanced(title, author, env);
await doStub.pushProgress({
  progress: 1.0,
  result: {
    works: canonicalResponse.data.works,  // [WorkDTO]
    authors: canonicalResponse.data.authors,  // [AuthorDTO]
    meta: canonicalResponse.meta
  }
});
```

**Key Constraint:** Legacy public endpoints (`/search/title`, `/search/isbn`, etc.) remain UNCHANGED. Only internal service-to-service calls migrate.

### Testing Strategy

**Unit Tests:**
- Test `enrichBatch()` returns canonical `{ works, authors }` structure
- Test `enrichBooksParallel()` calls v1 handler correctly
- Verify all enum mappings preserved (gender, region, format, status)

**Integration Tests:**
- Start enrichment job → monitor WebSocket → verify canonical response
- Upload bookshelf image → verify AI scan result has WorkDTO/EditionDTO
- Real API call: Search "Harry Potter" → validate canonical structure

**Manual Validation:**
```bash
# Test enrichment WebSocket
# Connect to ws://localhost:8787/ws/progress?jobId=test-job
# POST to /api/enrichment/start with test work IDs
# Verify response: { works: [WorkDTO], authors: [AuthorDTO] }
```

### Success Criteria

- ✅ All backend tests pass (existing 18 + new canonical tests)
- ✅ WebSocket messages contain canonical DTOs
- ✅ No breaking changes to public `/search/*` endpoints
- ✅ Manual curl tests show correct format

**Estimated Time:** 3-4 hours

---

## Phase 2: iOS Migration

### Scope

**Files to Modify:**

1. **`BookSearchAPIService.swift`** (Main search service)
   - Update endpoints: `/search/title` → `/v1/search/title` (same for isbn, author)
   - Replace parsing: `APISearchResponse` → `ApiResponse<BookSearchResponse>`
   - Wire mapper: `WorkDTO/EditionDTO` → `DTOMapper.mapToWork()` → SwiftData models
   - Remove: Legacy types (`APISearchResponse`, `APIBookItem`, `APIVolumeInfo`, etc.)

2. **`EnrichmentService.swift`** (Background enrichment consumer)
   - Update WebSocket parsing: Expect `{ works: [WorkDTO], authors: [AuthorDTO] }`
   - Wire mapper: Parse DTOs → call `DTOMapper` → SwiftData models
   - Remove: Legacy types (`EnrichmentSearchResponse`, `VolumeItem`, `VolumeInfo`, etc.)

### Technical Details

**Response Parsing Pattern:**

```swift
// OLD: Legacy parsing
let response = try decoder.decode(APISearchResponse.self, from: data)
let books = response.items.map { convertAPIBookItemToSearchResult($0) }

// NEW: Canonical parsing with discriminated union
let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)

switch envelope {
case .success(let data, let meta):
    // Map DTOs to SwiftData models
    let works = data.works.map { workDTO in
        DTOMapper.mapToWork(dto: workDTO, context: modelContext)
    }
    return works

case .failure(let error, let meta):
    // Handle structured error codes
    switch error.code {
    case .invalidQuery:
        throw SearchError.invalidQuery(error.message)
    case .invalidISBN:
        throw SearchError.invalidISBN(error.message)
    case .providerError:
        throw SearchError.providerUnavailable(error.message)
    case .internalError:
        throw SearchError.serverError(error.message)
    }
}
```

**Error Handling Strategy:**

Map `ApiError.code` to user-friendly messages:
- `INVALID_QUERY` → "Please enter a valid search term"
- `INVALID_ISBN` → "ISBN format is incorrect (use ISBN-10 or ISBN-13)"
- `PROVIDER_ERROR` → "Book database temporarily unavailable, please try again"
- `INTERNAL_ERROR` → "An unexpected error occurred"

**SwiftData Integration:**

The `DTOMapper` already handles:
- ✅ Insert-before-relate pattern (prevents SwiftData crashes)
- ✅ Deduplication by `googleBooksVolumeIDs`
- ✅ Synthetic Work merging (inferred → real upgrade)
- ✅ Contributor union (preserves provider attribution)

### Testing Strategy

**DTO Parsing Tests:**
- Already covered: `DTOTests.swift` (8 tests passing)
- Add: Real API response validation (not mocked)

**Mapper Tests:**
- Already covered: `DTOMapperTests.swift` (7 tests passing)
- Add: Error code handling for all `ApiError` cases

**Integration Tests:**
- Search flow: Type "Harry Potter" → verify SwiftData models created
- ISBN flow: Scan barcode → verify deduplication prevents duplicates
- Enrichment flow: Import CSV → verify background enrichment works
- AI scan flow: Upload bookshelf → verify canonical results parse

**Real Device Testing (Critical):**
- Test on physical iPhone running iOS 26
- Verify all search methods work end-to-end
- Check error messages display correctly
- Validate enrichment and AI scanning complete successfully

### Success Criteria

- ✅ All iOS tests pass (15 DTO/mapper + updated service tests)
- ✅ Search, ISBN scanning, enrichment, AI scanning all functional
- ✅ Deduplication prevents duplicate Works
- ✅ Error messages display correctly for each error code
- ✅ Real device testing passes

**Estimated Time:** 4-5 hours

---

## Phase 3: Conservative Cleanup

### Scope (Defer 2-4 weeks after Phase 2)

**Conservative Strategy:** Preserve backward compatibility, remove only internal/unused code.

**Backend Cleanup:**

✅ **Remove (Safe):**
- `transformGoogleBooksResponse()` helper in `enrichment.js` (unused after Phase 1)

❌ **KEEP (Public API):**
- Legacy `/search/*` endpoints (`/search/title`, `/search/isbn`, `/search/advanced`, `/search/author`)
- Legacy handlers in `book-search.js`, `author-search.js`
- Rationale: External clients may depend on these, breaking changes require major version bump

**iOS Cleanup:**

✅ **Remove (Safe, internal only):**
- Legacy response types (~200 lines):
  - `APISearchResponse`, `APIBookItem`, `APIVolumeInfo`, `APIImageLinks`, `APIIndustryIdentifier` (BookSearchAPIService.swift)
  - `EnrichmentSearchResponse`, `VolumeItem`, `VolumeInfo`, `ImageLinks`, `CrossReferenceIds`, `IndustryIdentifier` (EnrichmentService.swift)
- Legacy conversion logic:
  - `convertEnhancedItemToSearchResult()` (lines 328-382 in BookSearchAPIService.swift)
  - Legacy response handling branches

**Documentation Updates:**

```markdown
# CLAUDE.md updates:
- Update API examples: /search/title → /v1/search/title
- Update response format examples: APISearchResponse → ApiResponse<BookSearchResponse>
- Add error code handling guide
- Document canonical DTO structure

# CHANGELOG.md entry:
## [3.X.0] - 2025-10-30
### Changed
- **Backend:** Enrichment and AI scanning now return canonical WorkDTO/EditionDTO format
- **iOS:** Search services migrated to /v1/ endpoints with structured error codes
- **Response Format:** All search results now use canonical data contracts

### Removed
- **iOS:** Legacy Google Books response parsing (APISearchResponse, APIBookItem, etc.)
- **iOS:** Legacy enrichment response types (EnrichmentSearchResponse, VolumeItem, etc.)

### Deprecated
- **Backend:** Legacy /search/* endpoints will remain for backward compatibility (no removal planned)
```

### Success Criteria

- ✅ No runtime errors after cleanup
- ✅ All tests still pass
- ✅ Documentation reflects current API
- ✅ Public endpoints still functional

**Estimated Time:** 1-2 hours (after 2-4 week validation period)

---

## Rollback Strategy

### Backend Rollback (if issues in Phase 1)

```bash
# Revert commits
git revert <commit-hash>

# Redeploy legacy version
cd cloudflare-workers/api-worker
npx wrangler deploy

# Verify legacy endpoints working
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

**Impact:** iOS not affected (hasn't changed yet)

### iOS Rollback (if issues in Phase 2)

```bash
# Revert iOS commits
git revert <commit-hash>

# Rebuild and deploy
/build
/device-deploy
```

**Impact:** Backend canonical format doesn't hurt legacy iOS parsing (iOS just won't use v1 endpoints)

### Zero-Downtime Rollback

Since legacy `/search/*` endpoints are preserved:
1. iOS can instantly switch back to legacy endpoints
2. Backend v1 handlers remain available (don't affect legacy handlers)
3. No data loss (SwiftData models unchanged)

---

## Timeline & Effort

| Phase | Estimated Time | Deferrable? | Risk Level |
|-------|----------------|-------------|------------|
| **Phase 1: Backend** | 3-4 hours | No | Low (backward compatible) |
| **Phase 2: iOS** | 4-5 hours | No | Medium (integration testing required) |
| **Phase 3: Cleanup** | 1-2 hours | Yes (2-4 weeks) | Low (internal code only) |

**Total Effort:** 8-11 hours of development + 2-4 weeks validation period

**Critical Path:**
- Week 1: Complete Phase 1 (backend)
- Week 2: Complete Phase 2 (iOS integration)
- Week 4-6: Execute Phase 3 (conservative cleanup) after validation

---

## Success Metrics

**Backend (Phase 1):**
- 100% of tests pass (existing + new canonical tests)
- WebSocket messages have canonical structure
- Zero breaking changes to public API

**iOS (Phase 2):**
- All search flows work end-to-end on real device
- Error handling displays correct messages for all error codes
- Deduplication prevents duplicate Works in library
- Background enrichment completes successfully

**Cleanup (Phase 3):**
- Zero runtime errors after legacy code removal
- Documentation reflects current API structure
- Public endpoints remain functional

---

## Open Questions

None - design validated and approved.

---

## References

- **Implementation Plan:** `docs/plans/2025-10-29-canonical-data-contracts-implementation.md`
- **Design Document:** `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- **Backend Types:** `cloudflare-workers/api-worker/src/types/canonical.ts`
- **iOS DTOs:** `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/`
- **iOS Mapper:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`
