# Cache Warming System - DTO Normalization Alignment

**Date:** November 5, 2025  
**Status:** ✅ Fixed  
**Issue:** Cache warming incompatible with DTO normalization and search handlers  
**Design Doc:** [2025-10-29-cache-warming-fix.md](./2025-10-29-cache-warming-fix.md)

## Problem Statement

The cache warming system (deployed October 28, 2025) was built **before** the DTO normalization commits. This created a critical incompatibility where warmed cache entries were **never used** by search endpoints, resulting in a 0% cache hit rate from warming.

### Root Causes

1. **Cache Key Mismatch**
   - **Warming:** `search:title:the hobbit`
   - **Search:** `search:title:maxresults=20&title=hobbit`
   - Missing `maxResults` parameter in warming keys
   - Missing title normalization (article removal, punctuation)

2. **DTO Format Incompatibility**
   - **Warming:** Raw OpenLibrary work objects `{ title, firstPublicationYear, openLibraryWorkKey }`
   - **Search:** Canonical WorkDTO format with `{ subjectTags, primaryProvider, reviewStatus, ... }`
   - Search handlers couldn't deserialize warming cache entries

3. **Normalization Not Applied**
   - **Warming:** Simple `.toLowerCase()` on title
   - **Search:** `normalizeTitle()` removes articles ("the", "a", "an") and punctuation
   - "The Hobbit" cached as "the hobbit" but searched as "hobbit"

4. **TTL Mismatch**
   - **Warming:** 24-hour TTL
   - **Search:** 6-hour TTL for title searches
   - Inconsistent expiration behavior

5. **Single-Tier Caching**
   - **Warming:** KV only (Tier 2)
   - **Search:** Edge → KV → R2 (multi-tier via UnifiedCacheService)
   - Warming entries never populated fastest cache tier (Edge)

## Solution

### Core Strategy: Use Search Handlers for Warming

Instead of duplicating cache key generation and API call logic, **reuse the exact same handlers** that serve search requests. This guarantees compatibility.

#### Old Implementation (Broken)

```javascript
// author-warming-consumer.js (OLD - DO NOT USE)
const searchResult = await getOpenLibraryAuthorWorks(author, env);
const works = searchResult.works || [];

for (const work of works) {
  const cacheKey = `search:title:${work.title.toLowerCase()}`; // ❌ WRONG
  await env.CACHE.put(cacheKey, JSON.stringify({
    items: [work],  // ❌ WRONG FORMAT
    cached: true,
    timestamp: Date.now()
  }), {
    expirationTtl: 24 * 60 * 60  // ❌ WRONG TTL
  });
}
```

**Issues:**
- ❌ Manually constructed cache key without `maxResults` param
- ❌ No title normalization applied
- ❌ Stored raw OpenLibrary work (not canonical DTO)
- ❌ Wrong TTL (24h vs 6h)
- ❌ KV-only caching (missing Edge tier)

#### New Implementation (Correct)

```javascript
// author-warming-consumer.js (NEW - CORRECT)
import { searchByTitle } from '../handlers/book-search.js';
import { searchByAuthor } from '../handlers/author-search.js';

// STEP 1: Warm author bibliography
const authorResult = await searchByAuthor(author, {
  limit: 100,
  offset: 0,
  sortBy: 'publicationYear'
}, env, ctx);

// STEP 2: Warm each title
for (const work of authorResult.works) {
  await searchByTitle(work.title, { maxResults: 20 }, env, ctx);
  // ✅ Correct cache key via generateCacheKey()
  // ✅ Correct normalization via normalizeTitle()
  // ✅ Canonical DTO via enrichMultipleBooks()
  // ✅ Correct TTL (6h)
  // ✅ Multi-tier (Edge + KV + R2)
}
```

**Benefits:**
- ✅ Cache keys identical to search handlers
- ✅ Title normalization applied automatically
- ✅ Canonical WorkDTO format from enrichMultipleBooks
- ✅ Correct 6h TTL
- ✅ Multi-tier caching (Edge for 80%+ hit rate)

### Cache Key Comparison

| Title | Old Warming Key | New Warming Key | Search Handler Key | Match? |
|-------|----------------|-----------------|-------------------|--------|
| "The Hobbit" | `search:title:the hobbit` | `search:title:maxresults=20&title=hobbit` | `search:title:maxresults=20&title=hobbit` | ✅ |
| "American Gods" | `search:title:american gods` | `search:title:maxresults=20&title=american gods` | `search:title:maxresults=20&title=american gods` | ✅ |
| "Good Omens" | `search:title:good omens` | `search:title:maxresults=20&title=good omens` | `search:title:maxresults=20&title=good omens` | ✅ |

### DTO Format Comparison

#### Old Format (Incompatible)
```json
{
  "title": "American Gods",
  "firstPublicationYear": 2001,
  "openLibraryWorkKey": "/works/OL45804W",
  "authors": [{ "name": "Neil Gaiman" }],
  "editions": [...]
}
```

**Missing canonical fields:**
- ❌ `subjectTags` (required for genre filtering)
- ❌ `primaryProvider` (required for provenance tracking)
- ❌ `reviewStatus` (required for AI-detected books)
- ❌ `goodreadsWorkIDs`, `amazonASINs`, etc. (required for external ID linking)

#### New Format (Compatible)
```json
{
  "title": "American Gods",
  "subjectTags": ["fiction", "fantasy", "mythology"],
  "originalLanguage": "en",
  "firstPublicationYear": 2001,
  "description": "A novel by Neil Gaiman about gods in America",
  "synthetic": false,
  "primaryProvider": "google-books",
  "contributors": ["google-books", "openlibrary"],
  "goodreadsWorkIDs": [],
  "amazonASINs": [],
  "librarythingIDs": [],
  "googleBooksVolumeIDs": ["ABC123"],
  "isbndbQuality": 0,
  "reviewStatus": "unreviewed",
  "authors": [{ "name": "Neil Gaiman", "gender": "unknown" }]
}
```

**All canonical fields present** ✅

## Implementation Changes

### Files Modified

1. **`src/consumers/author-warming-consumer.js`**
   - Import `searchByTitle` and `searchByAuthor` handlers
   - Remove direct `getOpenLibraryAuthorWorks` call
   - Use handlers for all caching operations
   - Add `sleep()` utility for rate limiting
   - Update processed key format: `warming:processed:author:{lowercase}`
   - Track `titlesWarmed` separately from `worksCount`

2. **`tests/author-warming-consumer.test.js`**
   - Mock `searchByAuthor` and `searchByTitle` handlers
   - Add tests for cache key compatibility
   - Add tests for canonical DTO format
   - Add tests for rate limit handling
   - Add tests for partial failure recovery

3. **`tests/cache-warming-integration.test.js`** (NEW)
   - Comprehensive integration tests
   - Cache key format validation
   - DTO structure validation
   - Old vs new format comparison
   - Migration validation tests

### Breaking Changes

**⚠️ BREAKING CHANGE:** Cache warming now uses `searchByAuthor` and `searchByTitle` handlers instead of direct OpenLibrary API calls.

**Migration Required:**
- Existing warmed cache entries (old format) will naturally expire in 6-24 hours
- No manual cleanup needed (TTL will auto-purge old entries)
- Re-run warming job after deployment to populate with new format

## Testing Strategy

### Unit Tests
```bash
cd cloudflare-workers/api-worker
npm test tests/author-warming-consumer.test.js
npm test tests/cache-warming-integration.test.js
```

### Integration Test (Manual)
```bash
# 1. Deploy updated worker
npx wrangler deploy

# 2. Upload small test CSV (10 authors)
curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d '{"csv":"<base64-encoded-test-csv>","maxDepth":1}'

# 3. Wait 5 minutes for processing

# 4. Test author search (should be cached)
curl -v https://api-worker.jukasdrj.workers.dev/search/author?name=Neil%20Gaiman \
  | grep "X-Cache-Tier"

# 5. Test title search (should be cached)
curl -v https://api-worker.jukasdrj.workers.dev/search/title?q=American%20Gods \
  | grep "X-Cache-Tier"

# Expected: X-Cache-Tier: EDGE (or KV if Edge evicted)
```

### Success Criteria
- ✅ Cache keys match between warming and search (100% compatibility)
- ✅ Title searches return `cached: true, cacheSource: "EDGE"` or `"KV"`
- ✅ Author searches return `cached: true, cacheSource: "EDGE"` or `"KV"`
- ✅ No rate limit errors (429) in logs
- ✅ All three cache tiers populated (Edge, KV, R2 index)
- ✅ DTO structure matches canonical WorkDTO interface

## Performance Expectations

### Processing Speed (Unchanged)
- **Per author:** ~3-4 minutes (1 author search + ~100 title searches)
- **Per batch (5 authors):** ~15 minutes
- **Full CSV (47 authors):** ~1.5-2 hours

### API Usage (Unchanged)
- **Per author:** ~201 API calls (1 author + 100 titles × 2 providers)
- **Full CSV (47 authors):** ~9,447 API calls
- **Within limits:** Google Books (4,700 < 10K/day), OpenLibrary (no strict limits)

### Cache Hit Rate (Improved)
- **Before fix:** 0% (warming entries never used)
- **After fix:** 80-90% for warmed titles, 90-95% for warmed authors
- **Edge tier hit rate:** 80%+ (fastest response time)

## Monitoring

### Logs (Real-time)
```bash
npx wrangler tail api-worker --format pretty
```

**Expected patterns:**
```
Cached author "Neil Gaiman": 43 works
Warmed 40 titles for author "Neil Gaiman"
Skipping Harper Lee: already processed at depth 0
```

### Analytics Queries
```sql
-- Cache warming activity
SELECT
  blob2 as author_name,
  SUM(double1) as total_works,
  SUM(double2) as total_titles_warmed,
  COUNT(*) as warming_runs
FROM CACHE_ANALYTICS
WHERE blob1 = 'warming'
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY author_name
ORDER BY total_titles_warmed DESC
LIMIT 20;

-- Cache hit rates (post-warming)
SELECT
  blob1 as endpoint,
  blob3 as cache_status,
  COUNT(*) as requests,
  AVG(double1) as avg_response_time_ms
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY endpoint, cache_status
ORDER BY endpoint, cache_status;
```

## Related Documentation

- **Design Doc:** [2025-10-29-cache-warming-fix.md](./2025-10-29-cache-warming-fix.md)
- **Canonical DTOs:** [../src/types/canonical.ts](../src/types/canonical.ts)
- **Normalization Utils:** [../src/utils/normalization.ts](../src/utils/normalization.ts)
- **Cache Key Utils:** [../src/utils/cache.js](../src/utils/cache.js)
- **Search Handlers:** [../src/handlers/book-search.js](../src/handlers/book-search.js), [../src/handlers/author-search.js](../src/handlers/author-search.js)

## Changelog

- **November 5, 2025:** Fixed cache warming to use search handlers (this doc)
- **October 29, 2025:** Identified cache key mismatch issue (design doc)
- **October 28, 2025:** Initial cache warming deployment (broken)
- **November 4, 2025:** DTO normalization and ResponseEnvelope migration

## Next Steps

- [x] Deploy fix to production
- [ ] Run warming job with test CSV (10 authors)
- [ ] Validate cache hit rates (expect 80-90%)
- [ ] Monitor for rate limit errors
- [ ] Re-run full CSV warming (47 authors)
- [ ] Document cache warming in main README
