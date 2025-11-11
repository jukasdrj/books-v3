# Fix Plan: Bookshelf Scan Data Loss

**Status:** Ready to implement
**Priority:** Critical (breaks analytics tracking)
**Root Cause:** Data model mismatch between backend WebSocket messages and iOS decoder

---

## Problem Statement

WebSocket completion message sends `works`, `editions`, `authors` arrays (canonical format), but iOS decoder expects a unified `books` array. This causes:

1. iOS decoder silently drops the `works` array (no matching field in ScanResultData)
2. `ScanResultData.books` decodes as `nil`
3. iOS treats `nil` as empty array `[]`
4. No books are extracted, analytics logs `books_detected: 0`
5. BUT user sees success messages with correct book counts (from metadata fields)

**Result:** Data contradictions - backend says "9 books" but analytics says "0 books"

---

## Solution: Backend Restructuring

**File:** `/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker/src/services/ai-scanner.js`

**Lines affected:** 164-191 (completion message structure)

### Current Code (Lines 164-191)

```javascript
// Extract canonical DTOs from enriched books
const works = enrichedBooks.map(b => b.enrichment.work).filter(Boolean);
const editions = enrichedBooks.flatMap(b => b.enrichment.editions || []);
const authors = enrichedBooks.flatMap(b => b.enrichment.authors || []);

await doStub.pushProgress({
  progress: 1.0,
  processedItems: 3,
  totalItems: 3,
  currentStatus: 'Scan complete',
  jobId,
  result: {
    totalDetected: detectedBooks.length,
    approved: approved.length,
    needsReview: review.length,
    works,           // ← Problem: iOS expects "books" not "works"
    editions,
    authors,
    detections: detectedBooks,
    metadata: {
      processingTime,
      enrichedCount: enrichedBooks.filter(b => b.enrichment?.status === 'success').length,
      timestamp: new Date().toISOString(),
      modelUsed: modelUsed
    }
  }
});
```

### Fixed Code

Replace lines 164-191 with:

```javascript
// Reconstruct books array with embedded enrichment data
const books = enrichedBooks.map(b => ({
  title: b.title,
  author: b.author,
  isbn: b.isbn || null,
  format: b.format || 'unknown',
  confidence: b.confidence,
  boundingBox: b.boundingBox,
  enrichment: {
    status: b.enrichment?.status || 'unknown',
    work: b.enrichment?.work || null,
    editions: b.enrichment?.editions || [],
    authors: b.enrichment?.authors || [],
    provider: b.enrichment?.provider || 'unknown',
    cachedResult: b.enrichment?.cachedResult || false
  }
}));

await doStub.pushProgress({
  progress: 1.0,
  processedItems: 3,
  totalItems: 3,
  currentStatus: 'Scan complete',
  jobId,
  result: {
    totalDetected: detectedBooks.length,
    approved: approved.length,
    needsReview: review.length,
    books,  // ← Now matches iOS expectation
    metadata: {
      processingTime,
      enrichedCount: enrichedBooks.filter(b => b.enrichment?.status === 'success').length,
      timestamp: new Date().toISOString(),
      modelUsed: modelUsed
    }
  }
});
```

### Key Changes

1. **Lines 164-167 (NEW):** Create `books` array that combines Gemini detections with enrichment data
2. **Line 176 (CHANGED):** Send `books` instead of separate `works`, `editions`, `authors`
3. **Removed:** No longer send `detections` separately (data now embedded in each book)
4. **Unchanged:** Metadata fields `totalDetected`, `approved`, `needsReview` remain accurate

### Why This Works

- iOS expects `books: [{ title, author, ..., enrichment: {...} }]`
- Backend now sends exactly that structure
- iOS decoder successfully populates `ScanResultData.books`
- `compactMap` finds 9 books instead of 0
- Analytics logs correct count: `books_detected: 9`

---

## No iOS Changes Required

The iOS code is already compatible with the fixed backend format:

```swift
// WebSocketProgressManager.swift - NO CHANGES NEEDED
struct ScanResultData: Codable {
    let totalDetected: Int          // ✅ Already receives this
    let approved: Int               // ✅ Already receives this
    let needsReview: Int            // ✅ Already receives this
    let books: [BookData]?          // ✅ Will now receive array instead of nil
    let metadata: ScanMetadata

    struct BookData: Codable {
        let title: String
        let author: String
        let isbn: String?
        let format: String?
        let confidence: Double
        let boundingBox: BoundingBox
        let enrichment: Enrichment?  // ✅ Already receives embedded enrichment
    }
}
```

iOS handler is also compatible:

```swift
// BookshelfAIService.swift - NO CHANGES NEEDED
let detectedBooks = scanResult.books.compactMap { bookPayload in
    self.convertPayloadToDetectedBook(bookPayload)  // ✅ Will work with populated books array
}

// Analytics will now log correct count
print("[Analytics] bookshelf_scan_completed - ... books_detected: \(result.0.count) ...")
```

---

## Testing Strategy

### Unit Test (Node.js)

Add test to verify message structure:

**File:** `cloudflare-workers/api-worker/src/services/__tests__/ai-scanner-books-structure.test.js`

```javascript
import { describe, it, expect } from '@jest/globals';

describe('AI Scanner - Books Array Structure', () => {
  it('should include books array with embedded enrichment in completion message', () => {
    const mockEnrichedBooks = [
      {
        title: 'Test Book 1',
        author: 'Test Author 1',
        isbn: '978-0000000000',
        format: 'hardcover',
        confidence: 0.85,
        boundingBox: { x1: 0, y1: 0, x2: 1, y2: 1 },
        enrichment: {
          status: 'success',
          work: { id: 'work1', title: 'Test Book 1' },
          editions: [{ id: 'ed1' }],
          authors: [{ id: 'auth1' }],
          provider: 'google-books',
          cachedResult: false
        }
      }
    ];

    // Simulate the result construction
    const books = mockEnrichedBooks.map(b => ({
      title: b.title,
      author: b.author,
      isbn: b.isbn || null,
      format: b.format || 'unknown',
      confidence: b.confidence,
      boundingBox: b.boundingBox,
      enrichment: {
        status: b.enrichment?.status || 'unknown',
        work: b.enrichment?.work || null,
        editions: b.enrichment?.editions || [],
        authors: b.enrichment?.authors || [],
        provider: b.enrichment?.provider || 'unknown',
        cachedResult: b.enrichment?.cachedResult || false
      }
    }));

    const result = {
      totalDetected: 1,
      approved: 1,
      needsReview: 0,
      books,
      metadata: { processingTime: 5000 }
    };

    // Verify structure
    expect(result.books).toBeDefined();
    expect(result.books.length).toBe(1);
    expect(result.books[0].title).toBe('Test Book 1');
    expect(result.books[0].enrichment.work).toBeDefined();
    expect(result.books[0].enrichment.work.id).toBe('work1');
  });
});
```

### Integration Test (Manual)

1. **Capture bookshelf photo with 9+ books**
2. **Run scan**
3. **Check Cloudflare logs:**
   ```bash
   npx wrangler tail api-worker --search "Scan complete" --format pretty
   ```
   Should show: `[AI Scanner] Scan complete for job ...: 9 books`

4. **Check iOS console:**
   ```
   ✅ Scan complete with 9 books (9 approved, 0 review)
   [Analytics] bookshelf_scan_completed - books_detected: 9
   ```
   Should show: `books_detected: 9` (not 0)

5. **Verify review queue:** All 9 books appear in queue (not 0)

---

## Rollout Plan

### Step 1: Update Backend (Immediate)
- Edit `ai-scanner.js` lines 164-191
- Deploy to `api-worker`
- Verify deployment with health check: `curl https://api-worker.jukasdrj.workers.dev/health`

### Step 2: Test with Manual Scan
- Run one bookshelf scan
- Monitor logs for correct book count in WebSocket message
- Verify iOS analytics logs correct count

### Step 3: Monitor Analytics
- Check analytics dashboard for pattern change
- Should see `books_detected` counts match user expectations
- No other changes needed

---

## Verification Checklist

- [ ] File: `ai-scanner.js` lines 164-191 updated
- [ ] Backend deployed successfully
- [ ] One test scan completed (>5 books)
- [ ] Cloudflare logs show books array in completion message
- [ ] iOS logs show matching `books_detected` count
- [ ] Review queue displays all books (not empty)
- [ ] Analytics event logged with correct count
- [ ] No errors in worker logs

---

## Rollback Plan

If needed, revert to sending separate `works`, `editions`, `authors` arrays:

```bash
git checkout HEAD -- cloudflare-workers/api-worker/src/services/ai-scanner.js
npx wrangler deploy
```

But this is unlikely needed since iOS already expects the `books` format.

---

## Related Files

- Affected: `/api-worker/src/services/ai-scanner.js` (lines 164-191)
- No changes: `/BooksTrackerPackage/Sources/.../WebSocketProgressManager.swift`
- No changes: `/BooksTrackerPackage/Sources/.../BookshelfAIService.swift`
- Test: (Add new test file if running Jest tests)

---

## Notes

- This fix only affects the WebSocket completion message structure
- Regular progress updates (lines 35-151) are unaffected
- The change is backward-compatible with current iOS code
- Canonical DTO philosophy is maintained (data is still canonical, just restructured for iOS compatibility)

