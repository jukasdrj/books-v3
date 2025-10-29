# Cache Warming Fix - ADDENDUM: Advanced Search Support

**Date:** October 29, 2025
**Relates to:** `2025-10-29-cache-warming-fix-implementation.md`

## Problem

The original implementation plan covers:
- ✅ Title-only search: `/search/title?q={title}`
- ✅ Author-only search: `/search/author?name={author}`
- ❌ **MISSING:** Author+Title search: `/search/advanced?title={title}&author={author}`

**Current State:**
- `/search/advanced` endpoint exists but does **NOT** use `UnifiedCacheService`
- Only sets HTTP `Cache-Control` headers (relies on Edge cache, no KV/R2)
- Warmer does not cache author+title combinations
- **Impact:** Multi-field searches always hit APIs (0% cache hit rate)

## Solution: Add Advanced Search Caching

### Task 1.5: Add Caching to Advanced Search Handler

**Insert this task AFTER Task 1 (UnifiedCacheService.set()) and BEFORE Task 2 (Consumer Refactor)**

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/advanced-search.js` (new file)
- Modify: `cloudflare-workers/api-worker/src/handlers/search-handlers.js` (move code)
- Modify: `cloudflare-workers/api-worker/src/index.js` (update import + route)

---

#### Step 1: Create new advanced-search.js handler with caching

Location: Create new file `cloudflare-workers/api-worker/src/handlers/advanced-search.js`

```javascript
/**
 * Advanced search handler with UnifiedCacheService integration
 * Migrated from search-handlers.js to add caching support
 */

import * as externalApis from '../services/external-apis.js';
import { generateCacheKey } from '../utils/cache.js';
import { UnifiedCacheService } from '../services/unified-cache.js';

/**
 * Search books by title AND/OR author with caching
 * @param {Object} searchParams - Search parameters
 * @param {string} searchParams.bookTitle - Book title (optional if author provided)
 * @param {string} searchParams.authorName - Author name (optional if title provided)
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results (default: 20)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Search results in Google Books format
 */
export async function searchByTitleAndAuthor(searchParams, options, env, ctx) {
  const { bookTitle, authorName } = searchParams;
  const { maxResults = 20 } = options;

  // Validate: at least one parameter required
  if (!bookTitle && !authorName) {
    return {
      success: false,
      error: 'At least one search parameter required (title or author)',
      items: []
    };
  }

  // Generate cache key (sorted params for consistency)
  const cacheParams = {};
  if (authorName) cacheParams.author = authorName.toLowerCase();
  if (bookTitle) cacheParams.title = bookTitle.toLowerCase();
  cacheParams.maxResults = maxResults;

  const cacheKey = generateCacheKey('search:advanced', cacheParams);

  // Try UnifiedCache first (Edge → KV → R2)
  const cache = new UnifiedCacheService(env, ctx);
  const cachedResult = await cache.get(cacheKey, 'advanced', {
    query: { bookTitle, authorName, maxResults }
  });

  if (cachedResult && cachedResult.data) {
    const { data, source } = cachedResult;
    console.log(`Advanced search cache HIT (${source}): ${cacheKey}`);

    // Write cache metrics
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/advanced',
      cacheHit: true,
      responseTime: 0,
      itemCount: data.items?.length || 0
    }));

    return {
      ...data,
      cached: true,
      cacheSource: source
    };
  }

  const startTime = Date.now();

  try {
    // Build combined query
    const query = [bookTitle, authorName].filter(Boolean).join(' ');
    console.log(`Advanced search for: "${query}" (title: "${bookTitle || 'any'}", author: "${authorName || 'any'}")`);

    // Try Google Books first (most reliable)
    const googleResult = await externalApis.searchGoogleBooks(query, { maxResults }, env);

    if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
      // Convert normalized works to Google Books format (for compatibility)
      const items = googleResult.works.flatMap(work =>
        work.editions.map(edition => ({
          id: edition.googleBooksVolumeId || `synthetic-${edition.isbn13 || edition.isbn10}`,
          volumeInfo: {
            title: work.title,
            subtitle: work.subtitle,
            authors: work.authors.map(a => a.name),
            publishedDate: edition.publicationDate || edition.publishDate,
            publisher: edition.publisher,
            pageCount: edition.pageCount || edition.pages,
            categories: edition.genres || [],
            description: edition.description,
            imageLinks: edition.coverImageURL ? {
              thumbnail: edition.coverImageURL,
              smallThumbnail: edition.coverImageURL
            } : undefined,
            industryIdentifiers: [
              edition.isbn13 ? { type: 'ISBN_13', identifier: edition.isbn13 } : null,
              edition.isbn10 ? { type: 'ISBN_10', identifier: edition.isbn10 } : null
            ].filter(Boolean),
            previewLink: edition.previewLink,
            infoLink: edition.infoLink
          }
        }))
      );

      const responseData = {
        success: true,
        provider: 'google',
        items: items.slice(0, maxResults),
        cached: false,
        responseTime: Date.now() - startTime
      };

      // Cache for 6 hours (matches /search/title)
      const ttl = 6 * 60 * 60; // 21600 seconds
      ctx.waitUntil(cache.set(cacheKey, responseData, 'advanced', ttl));

      // Write cache metrics
      ctx.waitUntil(writeCacheMetrics(env, {
        endpoint: '/search/advanced',
        cacheHit: false,
        responseTime: Date.now() - startTime,
        itemCount: items.length
      }));

      console.log(`Advanced search cached: ${items.length} results (key: ${cacheKey})`);
      return responseData;
    }

    // Fallback to OpenLibrary
    console.log('Google Books returned no results, trying OpenLibrary...');
    const olResult = await externalApis.searchOpenLibrary(query, { maxResults }, env);

    if (olResult.success && olResult.works && olResult.works.length > 0) {
      // Convert OpenLibrary format to Google Books-compatible format
      const items = olResult.works.flatMap(work =>
        work.editions.map(edition => ({
          id: work.externalIds?.openLibraryWorkId || `ol-${work.title.replace(/\s+/g, '-').toLowerCase()}`,
          volumeInfo: {
            title: work.title,
            subtitle: work.subtitle,
            authors: work.authors.map(a => a.name),
            publishedDate: edition.publicationDate,
            publisher: edition.publisher,
            pageCount: edition.pageCount,
            categories: work.subjects?.slice(0, 5) || [],
            imageLinks: edition.coverImageURL ? {
              thumbnail: edition.coverImageURL,
              smallThumbnail: edition.coverImageURL
            } : undefined,
            industryIdentifiers: [
              edition.isbn13 ? { type: 'ISBN_13', identifier: edition.isbn13 } : null,
              edition.isbn10 ? { type: 'ISBN_10', identifier: edition.isbn10 } : null
            ].filter(Boolean)
          }
        }))
      );

      const responseData = {
        success: true,
        provider: 'openlibrary',
        items: items.slice(0, maxResults),
        cached: false,
        responseTime: Date.now() - startTime
      };

      // Cache for 6 hours
      const ttl = 6 * 60 * 60;
      ctx.waitUntil(cache.set(cacheKey, responseData, 'advanced', ttl));

      // Write cache metrics
      ctx.waitUntil(writeCacheMetrics(env, {
        endpoint: '/search/advanced',
        cacheHit: false,
        responseTime: Date.now() - startTime,
        itemCount: items.length
      }));

      console.log(`Advanced search cached (OpenLibrary): ${items.length} results`);
      return responseData;
    }

    // No results from any provider
    return {
      success: true,
      provider: 'none',
      items: [],
      cached: false,
      responseTime: Date.now() - startTime
    };

  } catch (error) {
    console.error(`Advanced search failed:`, error);
    return {
      success: false,
      error: error.message,
      items: [],
      responseTime: Date.now() - startTime
    };
  }
}

/**
 * Write cache metrics to Analytics Engine
 */
async function writeCacheMetrics(env, metrics) {
  if (!env.CACHE_ANALYTICS) return;

  try {
    await env.CACHE_ANALYTICS.writeDataPoint({
      blobs: [
        metrics.endpoint,
        metrics.cacheHit ? 'HIT' : 'MISS'
      ],
      doubles: [
        metrics.responseTime,
        metrics.itemCount
      ],
      indexes: [
        metrics.cacheHit ? 'HIT' : 'MISS'
      ]
    });
  } catch (error) {
    console.error('Failed to write cache metrics:', error);
  }
}
```

#### Step 2: Update index.js to use new handler

Location: `cloudflare-workers/api-worker/src/index.js`

Replace import (around line 15):
```javascript
// OLD:
import { handleAdvancedSearch } from './handlers/search-handlers.js';

// NEW:
import { searchByTitleAndAuthor } from './handlers/advanced-search.js';
```

Update route handler (around line 503):
```javascript
// OLD:
const result = await handleAdvancedSearch(
  { bookTitle, authorName },
  { maxResults },
  env
);

// NEW:
const result = await searchByTitleAndAuthor(
  { bookTitle, authorName },
  { maxResults },
  env,
  ctx  // IMPORTANT: Pass ctx for cache.set()
);
```

#### Step 3: Deprecate old search-handlers.js

Location: `cloudflare-workers/api-worker/src/handlers/search-handlers.js`

Add deprecation notice at top:
```javascript
/**
 * @deprecated This file is deprecated. Advanced search moved to advanced-search.js
 * with UnifiedCacheService integration. This file kept for reference only.
 *
 * DO NOT USE handleAdvancedSearch() - use searchByTitleAndAuthor() instead.
 */
```

#### Step 4: Test advanced search caching

```bash
# Test title+author search
curl -i "https://api-worker.jukasdrj.workers.dev/search/advanced?title=The%20Martian&author=Andy%20Weir&maxResults=20"

# Verify cache key format
# Expected: search:advanced:author=andy weir&maxresults=20&title=the martian
# (Alphabetical param order via generateCacheKey())

# Second request should be cached
curl -i "https://api-worker.jukasdrj.workers.dev/search/advanced?title=The%20Martian&author=Andy%20Weir&maxResults=20"
# Expected headers: X-Cache-Tier: EDGE, cached: true
```

#### Step 5: Commit

```bash
git add cloudflare-workers/api-worker/src/handlers/advanced-search.js \
        cloudflare-workers/api-worker/src/handlers/search-handlers.js \
        cloudflare-workers/api-worker/src/index.js
git commit -m "feat(cache): add UnifiedCacheService to advanced search

Creates new advanced-search.js handler with tier-aware caching.

Cache key format: search:advanced:author={author}&maxresults={n}&title={title}
TTL: 6 hours (matches /search/title)

Deprecates handleAdvancedSearch() in search-handlers.js.

Part of cache warming fix - enables warming of author+title combos.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2 UPDATE: Add Advanced Search Warming to Consumer

**Add this step to Task 2 (Author Warming Consumer), AFTER Step 4 (Title warming)**

#### Step 4.5: Warm author+title combinations

Location: In `processAuthorBatch()`, after title warming loop (after line with "Warmed N titles")

```javascript
// 4. STEP 3: Warm author+title combinations (for advanced search)
console.log(`Step 3: Warming author+title combinations...`);
let combosWarmed = 0;

for (const work of authorResult.works) {
  try {
    if (!work.title) continue;

    // Call advanced search with author+title
    const advancedResult = await searchByTitleAndAuthor({
      bookTitle: work.title,
      authorName: author
    }, { maxResults: 20 }, env, ctx);

    if (advancedResult && advancedResult.items && advancedResult.items.length > 0) {
      // Cache key auto-generated by searchByTitleAndAuthor()
      // Format: search:advanced:author={author}&maxresults=20&title={title}
      combosWarmed++;

      if (combosWarmed % 10 === 0) {
        console.log(`  Progress: ${combosWarmed}/${authorResult.works.length} combos warmed`);
      }
    }

    // Rate limiting: 100ms delay (same as title warming)
    await sleep(100);

  } catch (error) {
    console.error(`Failed to warm combo "${author}" + "${work.title}":`, error);
    // Continue with next combo
  }
}

console.log(`✅ Warmed ${combosWarmed} author+title combinations`);
```

Update "Mark author as processed" step to include combosWarmed:

```javascript
await env.CACHE.put(
  processedKey,
  JSON.stringify({
    worksCount: authorResult.works.length,
    titlesWarmed: titlesWarmed,
    titlesSkipped: titlesSkipped,
    combosWarmed: combosWarmed,  // NEW
    lastWarmed: Date.now(),
    jobId: jobId
  }),
  { expirationTtl: 90 * 24 * 60 * 60 }
);
```

Update analytics to track combos:

```javascript
await env.CACHE_ANALYTICS.writeDataPoint({
  blobs: ['warming', author, source],
  doubles: [
    authorResult.works.length,
    titlesWarmed,
    titlesSkipped,
    combosWarmed  // NEW: Track combo warming
  ],
  indexes: ['cache-warming']
});
```

---

## Updated Success Criteria

Add to original success criteria:

- [ ] Advanced search (author+title) returns cached results from Edge tier
- [ ] Cache keys include all three query types:
  - `search:title:maxresults=20&title={title}`
  - `search:author:author={author}&limit=100&offset=0&sortby=publicationyear`
  - `search:advanced:author={author}&maxresults=20&title={title}`

---

## Performance Impact

**Per Author (with advanced search warming):**
- Author search: 1 call (500ms)
- Title searches: 100 calls (3 minutes)
- **Author+Title combos: 100 calls (3 minutes)** ← NEW
- **Total:** ~6-7 minutes per author (doubled from original estimate)

**Full CSV (47 authors):**
- **Original estimate:** ~2 hours
- **New estimate:** ~4-5 hours (with combo warming)
- **API calls:** 9,447 → **18,894 calls** (doubled)
  - Still within Google Books free tier (10K/day) if spread over 2 days

**Recommendation:** Run combo warming as **optional** (can skip with feature flag if API limits are a concern).

---

## Optional: Feature Flag for Combo Warming

Add to `wrangler.toml`:

```toml
[vars]
ENABLE_COMBO_WARMING = "true"  # Set to "false" to skip author+title combos
```

Update consumer code:

```javascript
// Only warm combos if feature flag enabled
if (env.ENABLE_COMBO_WARMING === "true") {
  console.log(`Step 3: Warming author+title combinations...`);
  // ... combo warming code ...
} else {
  console.log(`Step 3: Skipping combo warming (feature flag disabled)`);
}
```

---

## Testing Checklist

After implementing Task 1.5 and updating Task 2:

- [ ] Advanced search endpoint uses UnifiedCacheService
- [ ] Advanced search cache keys match format
- [ ] First request populates all three cache tiers
- [ ] Second request returns from Edge cache
- [ ] Warmer creates author+title combo entries
- [ ] All three query types have matching cache keys

---

**Addendum Complete**
**Estimated Additional Effort:** +2 hours (Task 1.5) + 1 hour (Task 2 update) = **3 hours total**
**Total Project Effort:** Original 6 hours + 3 hours = **9 hours**
