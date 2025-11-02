# Batch Enrichment Service - Design Document

**Date:** November 1, 2025
**Status:** Design Approved
**Timeline:** 1 week implementation
**Issue:** #143 - Add batch enrichment support to API and iOS client

## Problem Statement

The `/api/enrichment/start` endpoint has TODO stubs in `batch-enrichment.js` (lines 56-59) that currently return books unchanged. iOS needs actual enrichment logic to fill in missing book metadata (title, author, ISBN) during CSV imports and batch operations.

## Requirements

**Functional:**
- Enrich books with metadata from external providers (Google Books, OpenLibrary)
- Reuse existing `/v1/search` canonical normalization (genre mapping, author demographics, ISBN validation)
- Best-effort error handling (skip unfindable books, enrich what's possible)
- Real-time progress updates via WebSocket (status: "Enriching (3/10): 1984 [success]")

**Non-Functional:**
- Metadata-only enrichment (title, author, ISBN) - fast performance
- No breaking changes to existing `/v1/search/*` endpoints
- Maintain KV cache integration
- Handle 100+ book batches with 10-parallel concurrency limit

**Success Criteria:**
- TODO stubs replaced with working enrichment service
- Tests validate: Google Books primary, OpenLibrary fallback, null for not-found
- iOS EnrichmentQueue can process 50+ book batches without crashes
- DTOMapper `workCache` stress-tested under concurrent load

## Design Decision: Shared Service Module (DRY)

### Strategy Selection

**Selected Approach:** Extract search/enrichment logic into shared `src/services/enrichment.js` module

**Alternatives Considered:**
1. Direct `/v1/search/title` fetch - Simple but HTTP overhead, can't bypass cache
2. Hybrid (direct + fallback) - Best performance but too complex (two code paths)

**Why Shared Service:**
- ✅ DRY principle - one enrichment implementation
- ✅ No HTTP overhead (direct function call)
- ✅ Both `/v1/search` and `/api/enrichment` use same logic
- ✅ Clean separation of concerns
- ⚠️ Requires refactoring `/v1/search/title` handler (one-time cost)

## Architecture Overview

### Core Components

**1. New Service Module:** `src/services/enrichment.js`

```javascript
export async function enrichSingleBook(query, env) {
  // Input: { title, author?, isbn? }
  // Output: WorkDTO | null

  try {
    // 1. Try Google Books API first (primary)
    const googleResult = await searchGoogleBooks(query, env);
    if (googleResult) {
      return normalizeToCanonical(googleResult, 'google-books');
    }

    // 2. Fallback to OpenLibrary
    const openLibResult = await searchOpenLibrary(query, env);
    if (openLibResult) {
      return normalizeToCanonical(openLibResult, 'openlibrary');
    }

    // 3. Book not found
    return null;

  } catch (error) {
    console.error('Enrichment error:', error);
    return null; // Best-effort: API errors = not found
  }
}
```

**Reused Functions (extracted from existing code):**
- `searchGoogleBooks(query, env)` - Google Books API call + KV cache lookup
- `searchOpenLibrary(query, env)` - OpenLibrary API call + KV cache lookup
- `normalizeToCanonical(result, provider)` - Genre normalization, demographics, ISBN validation

**2. Refactored Handler:** `src/handlers/search-title.js`

**Before (inline logic):**
```javascript
export async function handleSearchTitle(request, env) {
  // ... inline Google Books API call ...
  // ... inline normalization ...
}
```

**After (uses shared service):**
```javascript
import { enrichSingleBook } from '../services/enrichment.js';

export async function handleSearchTitle(request, env) {
  const { q } = await request.json();
  const result = await enrichSingleBook({ title: q }, env);

  if (result) {
    return Response.json({ success: true, data: { works: [result] } });
  } else {
    return Response.json({ success: false, error: { message: 'Not found' } });
  }
}
```

**No Behavior Change:** Endpoint still returns same canonical WorkDTO, just cleaner code.

**3. Updated Batch Handler:** `src/handlers/batch-enrichment.js`

**Replace TODO stubs (lines 56-59):**
```javascript
async (book) => {
  // NEW: Call enrichment service
  const enriched = await enrichSingleBook(
    {
      title: book.title,
      author: book.author,
      isbn: book.isbn
    },
    env
  );

  if (enriched) {
    return { ...book, enriched, success: true };
  } else {
    return {
      ...book,
      enriched: null,
      success: false,
      error: 'Book not found in any provider'
    };
  }
}
```

## Data Flow

```
iOS Client → POST /api/enrichment/start
  ↓
batch-enrichment.js → processBatchEnrichment(books, doStub, env)
  ↓
enrichBooksParallel() loops 10 books at a time
  ↓
For each book:
  enrichSingleBook({ title, author, isbn }, env)
    ↓
  searchGoogleBooks(query, env)
    ↓ (cache miss)
  Google Books API → normalize → WorkDTO
    ↓ (cache hit)
  KV cached result → WorkDTO
    ↓ (not found)
  searchOpenLibrary(query, env) → WorkDTO or null
  ↓
Progress update via WebSocket DO
  ↓
Final response: { books: [ {enriched: WorkDTO, success: true}, ... ] }
```

## Error Handling Strategy

**Best-Effort Approach:**
- Individual book failures don't abort the batch
- Unfindable books return `{ success: false, error: "..." }`
- API errors treated as "not found" (logged but not thrown)
- WebSocket progress shows: `"Enriching (5/10): Unknown Book [not found]"`

**Response Structure:**
```json
{
  "books": [
    {
      "title": "1984",
      "author": "George Orwell",
      "enriched": { /* WorkDTO */ },
      "success": true
    },
    {
      "title": "Unknown Book",
      "author": "???",
      "enriched": null,
      "success": false,
      "error": "Book not found in any provider"
    }
  ]
}
```

**iOS Handling:** EnrichmentQueue can display:
- Success count: "Enriched 8/10 books"
- Failed books list: "Could not find: Unknown Book, ..."
- User can retry failed books individually

## Testing Strategy

### Unit Tests

**File:** `test/enrichment.test.js`

```javascript
describe('enrichSingleBook()', () => {
  test('returns WorkDTO for valid book', async () => {
    const result = await enrichSingleBook(
      { title: '1984', author: 'Orwell' },
      mockEnv
    );
    expect(result).toMatchObject({
      title: '1984',
      authors: [{ name: 'George Orwell' }],
      primaryProvider: 'google-books'
    });
  });

  test('returns null for unknown book', async () => {
    const result = await enrichSingleBook(
      { title: 'XYZ123NonexistentBook' },
      mockEnv
    );
    expect(result).toBeNull();
  });

  test('tries Google Books first, OpenLibrary as fallback', async () => {
    // Mock: Google Books returns nothing
    // Mock: OpenLibrary returns result
    const result = await enrichSingleBook({ title: 'Obscure Book' }, mockEnv);
    expect(result.primaryProvider).toBe('openlibrary');
  });

  test('handles API errors gracefully', async () => {
    // Mock: Google Books throws network error
    const result = await enrichSingleBook({ title: 'Any Book' }, mockEnv);
    expect(result).toBeNull(); // No crash, just returns null
  });
});
```

### Integration Tests

**File:** `test/batch-enrichment.test.js`

```javascript
describe('POST /api/enrichment/start', () => {
  test('enriches batch with partial failures', async () => {
    const books = [
      { title: '1984' },           // Findable
      { title: 'Unknown123' },     // Not findable
      { title: 'Brave New World' } // Findable
    ];

    const response = await fetch('/api/enrichment/start', {
      method: 'POST',
      body: JSON.stringify({ books, jobId: 'test-123' })
    });

    expect(response.books).toHaveLength(3);
    expect(response.books.filter(b => b.success)).toHaveLength(2);
    expect(response.books.filter(b => !b.success)).toHaveLength(1);
  });

  test('sends WebSocket progress updates', async () => {
    const messages = [];
    // Mock: Capture WebSocket messages
    // Verify: Progress updates for all books (3/3, 2/3, 1/3)
    expect(messages).toContainEqual({
      progress: 0.33,
      status: 'Enriching (1/3): 1984'
    });
  });
});
```

### Load Testing

**Manual Test via Wrangler:**
```bash
# Deploy to staging
wrangler deploy --env staging

# Tail logs
wrangler tail --env staging

# Send 100-book batch from iOS or curl
curl -X POST https://staging-worker.dev/api/enrichment/start \
  -d '{"books": [...100 books...], "jobId": "load-test-1"}'

# Monitor:
# - Concurrency stays at ~10 parallel
# - KV cache hit rate
# - Total time: ~30-60s for 100 books
# - Memory usage stable
```

### DTOMapper Stress Test

**iOS Test (after backend deployed):**
1. Import 50-book CSV via Gemini CSV import
2. Watch EnrichmentQueue process batch
3. Verify: No SwiftData crashes in `DTOMapper.workCache`
4. Check: Duplicate detection works (same Work not inserted twice)

## Validation Checklist

**Pre-Deployment:**
- [ ] Extract `searchGoogleBooks()` + `searchOpenLibrary()` to enrichment.js
- [ ] Refactor `/v1/search/title` to use `enrichSingleBook()`
- [ ] Update `batch-enrichment.js` TODO stubs (lines 56-59)
- [ ] Unit tests pass (enrichment.test.js)
- [ ] Integration tests pass (batch-enrichment.test.js)
- [ ] `/v1/search/title` still works (no breaking changes)

**Post-Deployment (Staging):**
- [ ] Test 10-book batch via iOS dev build
- [ ] Verify WebSocket progress updates accurate
- [ ] Check `wrangler tail` logs show enrichment calls
- [ ] Confirm KV cache still working (hit/miss logged)
- [ ] Load test: 100-book batch completes in <90s

**Production Rollout:**
- [ ] Deploy to production worker
- [ ] iOS stress test: 50+ book CSV import
- [ ] Monitor CloudWatch/Grafana: No error spikes
- [ ] Verify DTOMapper workCache handles concurrency
- [ ] Close Issue #143

## Rollout Plan

**Phase 1: Implementation (3 days)**
- Day 1: Create `enrichment.js` service, extract existing logic
- Day 2: Refactor `/v1/search/title`, update batch handler
- Day 3: Write tests (unit + integration)

**Phase 2: Testing (2 days)**
- Day 4: Deploy to staging, run integration tests
- Day 5: Load testing (100-book batches), fix issues

**Phase 3: Production (2 days)**
- Day 6: Deploy to production, iOS dev build testing
- Day 7: Monitor production, DTOMapper stress test, close issue

**Total:** 1 week (7 days)

## Risk Mitigation

**Risk:** Refactoring `/v1/search/title` breaks existing functionality
**Mitigation:** Keep unit tests for search endpoint, validate response format unchanged

**Risk:** KV caching broken after extraction
**Mitigation:** Cache logic stays inside `searchGoogleBooks()` - transparent to caller

**Risk:** Concurrency issues in DTOMapper workCache
**Mitigation:** iOS stress test with 50+ books, monitor SwiftData crash logs

**Risk:** API rate limits hit during large batches
**Mitigation:** Concurrency limit = 10 (already in place), KV cache reduces API calls

## Success Metrics

**Backend:**
- ✅ TODO stubs replaced with working enrichment service
- ✅ 0 test failures in enrichment.test.js + batch-enrichment.test.js
- ✅ `/v1/search/title` refactored with no behavior change
- ✅ 100-book batch completes in <90s

**iOS:**
- ✅ EnrichmentQueue processes 50+ book batches without crashes
- ✅ DTOMapper workCache deduplication works under load
- ✅ CSV import enrichment success rate >80% (findable books)

**Operational:**
- ✅ KV cache hit rate >60% (reduces API costs)
- ✅ CloudWatch error rate <1% post-deployment
- ✅ WebSocket DO latency <50ms for progress updates

## References

- **Issue:** #143 - Add batch enrichment support to API and iOS client
- **Existing Code:** `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js` (TODO stubs)
- **Canonical Endpoints:** `/v1/search/title`, `/v1/search/isbn` (reuse normalization)
- **Related:** Issue #168 (DTOMapper workCache) - will stress-test during implementation

---

**Document Status:** ✅ Design Approved
**Next Step:** Begin Phase 5 (Worktree Setup) for implementation
**Owner:** Justin Gardner

🤖 Generated with Claude Code using superpowers:brainstorming skill
