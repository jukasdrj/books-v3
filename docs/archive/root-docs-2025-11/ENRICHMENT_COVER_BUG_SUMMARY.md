# Cover Image Bug - Root Cause and Fix Summary

## Issue

CSV import enrichment jobs complete successfully (202 Accepted), but enriched books do not show cover images despite backend having access to cover URLs from Google Books and OpenLibrary APIs.

## Root Cause

**Critical Architecture Bug:** Cover image URLs are being extracted into `EditionDTO` objects but the enrichment pipeline only returns `WorkDTO` objects, so cover images are discarded before reaching iOS.

### Architecture Diagram

```
External API Response
    ↓
normalizeGoogleBooksResponse()
├─ normalizeGoogleBooksToWork()    → WorkDTO (NO cover image!)
├─ normalizeGoogleBooksToEdition() → EditionDTO (HAS cover image!)
└─ Returns: { works: [...], editions: [...] }
    ↓
enrichment.ts:searchGoogleBooks()
    ↓
enrichment.ts:enrichSingleBook()
    │
    └─ Returns: WorkDTO (line 237-240)
       ❌ Edition is discarded!
       ❌ Cover image is lost!
    ↓
batch-enrichment.js:processBatchEnrichment()
    ↓
iOS via WebSocket
    ↓
Result: Books WITHOUT cover images
```

## Files Requiring Changes

1. **`cloudflare-workers/api-worker/src/types/canonical.ts`**
   - Add `coverImageURL?: string` to `WorkDTO` interface

2. **`cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`**
   - Extract `coverImageURL` from `volumeInfo.imageLinks.thumbnail` in `normalizeGoogleBooksToWork()`

3. **`cloudflare-workers/api-worker/src/services/normalizers/openlibrary.ts`**
   - Extract `coverImageURL` from `cover_i` field in `normalizeOpenLibraryToWork()`

4. **iOS Swift Codable (optional if using automatic generation)**
   - Add `coverImageURL` field to `WorkDTO` Swift struct

## Implementation

See detailed implementation guide in `ENRICHMENT_DIAGNOSTICS.md` (sections "Solution" and "Verification Steps")

## Testing Strategy

1. Unit test normalizers to verify cover URL extraction
2. Integration test batch enrichment to verify cover URLs in WebSocket response
3. E2E test CSV import with cover image verification in iOS

## Impact

- High Priority: Affects all enrichment jobs (CSV import, background enrichment, manual add)
- Low Risk: Non-breaking change (adding optional field)
- Immediate Value: All books will have cover images after fix

## Files Modified

- `cloudflare-workers/api-worker/src/types/canonical.ts` (add field to interface)
- `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts` (2 lines)
- `cloudflare-workers/api-worker/src/services/normalizers/openlibrary.ts` (2 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/API/DTOs/WorkDTO.swift` (if not auto-generated)

## Deployment Checklist

- [ ] Implement canonical.ts changes
- [ ] Update Google Books normalizer
- [ ] Update OpenLibrary normalizer
- [ ] Update iOS Swift Codable
- [ ] Run unit tests
- [ ] Build backend worker
- [ ] Test search endpoints return coverImageURL
- [ ] Test batch enrichment returns coverImageURL in WebSocket
- [ ] Deploy to production
- [ ] Verify CSV import shows cover images
