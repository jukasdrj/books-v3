---
name: Cache-Aware Enrichment for CSV/Bookshelf Imports
about: Make /v1/search/advanced cache-aware to maximize ISBNdb image caching before subscription expires
title: '[URGENT] Phase 1: Cache-Aware /v1/search/advanced + ISBNdb Fallback'
labels: backend, performance, urgent
assignees: ''
---

## 🚨 **URGENT: ISBNdb Subscription Expires End of Month**

**Timeline:** ISBNdb subscription ends ~Dec 31, 2025
**Daily Quota:** 5,000 API calls/day (high-quality cover images!)
**Goal:** Maximize cover image caching before subscription ends

---

## 📋 **Problem Statement**

### Current State
- CSV import enrichment uses `/v1/search/advanced` (NO caching!)
- Bookshelf scan enrichment uses `/v1/search/advanced` (NO caching!)
- ISBNdb **not integrated** into enrichment fallback chain
- Cache hit rate: **0-10%** (only from manual user searches)

### Impact
- **Wasting ISBNdb calls:** 5,000 calls/day unused while subscription active
- **Poor cover coverage:** 60-70% of imported books have covers (missing ISBNdb's high-quality images)
- **Missed caching opportunity:** Enrichment could warm cache for future searches but doesn't

---

## 🎯 **Solution: Phase 1 - Cache-Aware Enrichment**

### Objectives
1. **Add caching to `/v1/search/advanced`** - CSV/bookshelf enrichment populates cache
2. **Add ISBNdb as 3rd fallback provider** - Maximize cover image quality/coverage
3. **Respect existing normalization paths** - Use `normalizeTitle()`, `normalizeAuthor()`, `normalizeISBN()`

### Expected Impact
| Metric | Current | After Phase 1 |
|--------|---------|---------------|
| Cache hit rate | 0-10% | **70-85%** |
| Cover image coverage | 60-70% | **85-90%** |
| ISBNdb API usage | 0 calls/day | **3,000-5,000 calls/day** (maximized!) |
| Cache warmth | Cold | **Hot** (from imports) |

---

## 🛠️ **Implementation Plan**

### **Step 1: Add Caching to `/v1/search/advanced`**

**File:** `cloudflare-workers/api-worker/src/handlers/v1/search-advanced.ts`

**Changes:**
```typescript
import { setCached, generateCacheKey } from '../../utils/cache.js';
import { UnifiedCacheService } from '../../services/unified-cache.js';
import { normalizeTitle, normalizeAuthor } from '../../utils/normalization.js';

export async function handleSearchAdvanced(
  title: string,
  author: string,
  env: any,
  ctx: ExecutionContext // ADD: context for cache writes
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation (existing)
  const hasTitle = title && title.trim().length > 0;
  const hasAuthor = author && author.trim().length > 0;
  if (!hasTitle && !hasAuthor) {
    return createErrorResponseObject(...);
  }

  try {
    // ===== NEW: Cache lookup with normalization =====
    const normalizedTitle = hasTitle ? normalizeTitle(title) : '';
    const normalizedAuthor = hasAuthor ? normalizeAuthor(author) : '';

    const cacheKey = generateCacheKey('v1:advanced', {
      title: normalizedTitle,
      author: normalizedAuthor
    });

    const cache = new UnifiedCacheService(env, ctx);
    const cachedResult = await cache.get(cacheKey, 'advanced', {
      query: `${title} ${author}`.trim()
    });

    if (cachedResult?.data) {
      console.log(`✅ Cache HIT: /v1/search/advanced (${cacheKey})`);
      return {
        ...cachedResult.data,
        meta: {
          ...cachedResult.data.meta,
          cached: true,
          cacheSource: cachedResult.source // EDGE or KV
        }
      };
    }
    // ===== END NEW =====

    console.log(`v1 advanced search - title: "${title}" (normalized: "${normalizedTitle}"), author: "${author}" (normalized: "${normalizedAuthor}")`);

    // Use enrichMultipleBooks (EXISTING LOGIC - NO CHANGES)
    const result = await enrichMultipleBooks(
      { title: normalizedTitle, author: normalizedAuthor },
      env,
      { maxResults: 20 }
    );

    // ... existing response formatting ...

    const response = createSuccessResponseObject(
      { works: cleanWorks, editions: result.editions, authors },
      {
        processingTime: Date.now() - startTime,
        provider: result.works[0]?.primaryProvider || 'google-books',
        cached: false,
      }
    );

    // ===== NEW: Write to cache (6h TTL, same as /search/title) =====
    const ttl = 6 * 60 * 60; // 21600 seconds
    ctx.waitUntil(setCached(cacheKey, response, ttl, env));
    console.log(`💾 Cache WRITE: /v1/search/advanced (${cacheKey}, TTL: ${ttl}s)`);
    // ===== END NEW =====

    return response;

  } catch (error: any) {
    console.error('Error in v1 advanced search:', error);
    return createErrorResponseObject(...);
  }
}
```

**Key Points:**
- ✅ Uses **existing normalization functions** (`normalizeTitle`, `normalizeAuthor`)
- ✅ Uses **existing cache utilities** (`setCached`, `generateCacheKey`, `UnifiedCacheService`)
- ✅ **No changes** to `enrichMultipleBooks()` (keeps current provider fallback)
- ✅ Cache key format: `v1:advanced:{normalizedTitle}:{normalizedAuthor}`
- ✅ TTL: 6 hours (same as `/search/title`)

---

### **Step 2: Add ISBNdb as 3rd Fallback Provider**

**File:** `cloudflare-workers/api-worker/src/services/enrichment.ts`

**Changes:**
```typescript
import * as externalApis from './external-apis.js';

export async function enrichMultipleBooks(
  query: BookSearchQuery,
  env: WorkerEnv,
  options: SearchOptions = { maxResults: 20 }
): Promise<EnrichmentResult> {
  const { title, author, isbn } = query;
  const { maxResults = 20 } = options;

  // ISBN search returns single result (EXISTING LOGIC - NO CHANGES)
  if (isbn) {
    // ... existing ISBN search logic ...
  }

  const searchQuery = [title, author].filter(Boolean).join(' ');
  if (!searchQuery) {
    return { works: [], editions: [], authors: [] };
  }

  try {
    // Try Google Books first (EXISTING - NO CHANGES)
    console.log(`enrichMultipleBooks: Searching Google Books for "${searchQuery}"`);
    const googleResult: ApiResponse = await externalApis.searchGoogleBooks(searchQuery, { maxResults }, env);

    if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
      return {
        works: googleResult.works.map((work: WorkDTO) => addProvenanceFields(work, 'google-books')),
        editions: googleResult.editions || [],
        authors: googleResult.authors || []
      };
    }

    // Fallback to OpenLibrary (EXISTING - NO CHANGES)
    console.log(`enrichMultipleBooks: Google Books returned no results, trying OpenLibrary`);
    const olResult: ApiResponse = await externalApis.searchOpenLibrary(searchQuery, { maxResults }, env);

    if (olResult.success && olResult.works && olResult.works.length > 0) {
      return {
        works: olResult.works.map((work: WorkDTO) => addProvenanceFields(work, 'openlibrary')),
        editions: olResult.editions || [],
        authors: olResult.authors || []
      };
    }

    // ===== NEW: Fallback to ISBNdb (maximize cover image pulls!) =====
    if (title && author) {
      console.log(`enrichMultipleBooks: OpenLibrary returned no results, trying ISBNdb`);
      const isbndbResult: ApiResponse = await externalApis.searchISBNdb(title, author, env);

      if (isbndbResult.success && isbndbResult.works && isbndbResult.works.length > 0) {
        console.log(`✅ ISBNdb SUCCESS: Found ${isbndbResult.works.length} works`);
        return {
          works: isbndbResult.works.map((work: WorkDTO) => addProvenanceFields(work, 'isbndb')),
          editions: isbndbResult.editions || [],
          authors: isbndbResult.authors || []
        };
      }
    }
    // ===== END NEW =====

    // No results from any provider
    console.log(`enrichMultipleBooks: No results for "${searchQuery}"`);
    return { works: [], editions: [], authors: [] };

  } catch (error) {
    console.error('enrichMultipleBooks error:', error);
    return { works: [], editions: [], authors: [] };
  }
}
```

**Key Points:**
- ✅ **No changes** to Google Books or OpenLibrary logic
- ✅ ISBNdb only called if both providers fail (respects existing fallback order)
- ✅ ISBNdb normalizers **already exist** (`normalizeISBNdbToWork`, `normalizeISBNdbToEdition`)
- ✅ Rate limiting **already implemented** (1 req/second, enforced in `external-apis.js:506`)
- ✅ Quality scoring **already implemented** (`calculateISBNdbQuality()` in `isbndb.ts:115`)

---

### **Step 3: Update `/v1/search/advanced` Route to Pass Context**

**File:** `cloudflare-workers/api-worker/src/index.js`

**Changes:**
```javascript
// GET /v1/search/advanced
if (url.pathname === '/v1/search/advanced' && request.method === 'GET') {
  const title = url.searchParams.get('title') || '';
  const author = url.searchParams.get('author') || '';

  // CHANGE: Pass ctx for cache writes
  const response = await handleSearchAdvanced(title, author, env, ctx); // ADD ctx param

  return new Response(JSON.stringify(response), {
    headers: { 'Content-Type': 'application/json' },
  });
}
```

---

## 🧪 **Testing Plan**

### **Test 1: Cache Warmth from CSV Import**
```bash
# Import 50 books via CSV (uses /v1/search/advanced)
# Expected: Cache keys created for all 50 books

# Verify cache entries
wrangler kv:key list --namespace-id b9cade63b6db48fd80c109a013f38fdb --prefix "v1:advanced"
# Expected: 50 keys (one per book)

# Check cache hit rate
curl "https://api-worker.jukasdrj.workers.dev/metrics"
# Expected: hitRates.combined > 60%
```

### **Test 2: ISBNdb Fallback Coverage**
```bash
# Import obscure book not in Google Books/OpenLibrary
# Example: "The Forgotten Garden" by Kate Morton (ISBN: 9781416550549)

# Check logs for provider fallback
wrangler tail api-worker | grep "ISBNdb SUCCESS"
# Expected: "✅ ISBNdb SUCCESS: Found 1 works"

# Verify cover image from ISBNdb
curl "https://api-worker.jukasdrj.workers.dev/v1/search/advanced?title=The+Forgotten+Garden&author=Kate+Morton" | jq '.data.editions[0].coverImageURL'
# Expected: ISBNdb cover URL (not Google Books)
```

### **Test 3: Normalization Consistency**
```bash
# Search with different casing/punctuation
curl "https://api-worker.jukasdrj.workers.dev/v1/search/advanced?title=The%20Great%20Gatsby&author=F.%20Scott%20Fitzgerald"
curl "https://api-worker.jukasdrj.workers.dev/v1/search/advanced?title=great%20gatsby&author=fitzgerald"

# Expected: Both return cached result (same normalized cache key)
# Cache key: v1:advanced:great-gatsby:fitzgerald (normalized!)
```

### **Test 4: ISBNdb API Usage Tracking**
```bash
# Monitor ISBNdb calls during CSV import (100 books)
wrangler tail api-worker | grep "ISBNdb" | wc -l
# Expected: 10-30 calls (only for books not found in Google/OpenLibrary)

# Verify rate limiting (1 req/second)
# Expected: No 429 errors, calls spaced 1s apart
```

---

## 📊 **Success Metrics**

### **Before Phase 1**
- Cache hit rate: **0-10%**
- Cover image coverage: **60-70%**
- ISBNdb API usage: **0 calls/day**

### **After Phase 1** (Target)
- Cache hit rate: **70-85%** ✅
- Cover image coverage: **85-90%** ✅
- ISBNdb API usage: **3,000-5,000 calls/day** ✅ (maximized before subscription expires!)

---

## 🔐 **Normalization Paths (MUST RESPECT)**

### **Existing Normalization Functions** (DO NOT CHANGE)
- `normalizeTitle(title)` - Removes articles, punctuation, lowercases (`utils/normalization.ts:8`)
- `normalizeAuthor(author)` - Lowercases, trims (`utils/normalization.ts:31`)
- `normalizeISBN(isbn)` - Removes hyphens, preserves digits + 'X' (`utils/normalization.ts:22`)
- `normalizeImageURL(url)` - Removes query params, forces HTTPS (`utils/normalization.ts:41`)

### **Existing Cache Utilities** (DO NOT CHANGE)
- `generateCacheKey(prefix, params)` - Creates cache keys (`utils/cache.js:79`)
- `setCached(key, value, ttl, env)` - Writes to KV (`utils/cache.js:60`)
- `getCached(key, env)` - Reads from KV (`utils/cache.js:12`)
- `UnifiedCacheService` - Edge → KV → R2 tiered cache (`services/unified-cache.js`)

### **Existing ISBNdb Integration** (DO NOT CHANGE)
- `searchISBNdb(title, author, env)` - ISBNdb search (`services/external-apis.js:368`)
- `normalizeISBNdbToWork(book)` - Canonical WorkDTO (`services/normalizers/isbndb.ts:51`)
- `normalizeISBNdbToEdition(book)` - Canonical EditionDTO (`services/normalizers/isbndb.ts:74`)
- `calculateISBNdbQuality(book)` - Quality score 0-100 (`services/normalizers/isbndb.ts:115`)

---

## 🚀 **Deployment Checklist**

- [ ] Implement cache lookup/write in `search-advanced.ts`
- [ ] Add ISBNdb fallback to `enrichMultipleBooks()`
- [ ] Update route handler to pass `ctx` parameter
- [ ] Test cache warmth with CSV import (50 books)
- [ ] Test ISBNdb fallback with obscure books
- [ ] Verify normalization consistency
- [ ] Monitor ISBNdb API usage (stay under 5,000 calls/day)
- [ ] Deploy to production
- [ ] Monitor cache hit rate in `/metrics`
- [ ] Run bulk CSV imports to maximize ISBNdb caching before subscription expires!

---

## 📅 **Timeline**

**Week 1 (Urgent):** Implement Phase 1 (cache + ISBNdb fallback)
**Week 2:** Deploy to production
**Week 3:** Bulk CSV imports to cache 10,000+ ISBNdb covers before subscription expires
**Week 4:** Monitor cache hit rates and validate success

---

## 💰 **ISBNdb Budget Maximization**

**Subscription Details:**
- Daily quota: 5,000 API calls
- Expires: ~Dec 31, 2025
- Remaining days: ~25 days
- **Total available calls: 125,000** (maximize before expiry!)

**Strategy:**
1. Deploy Phase 1 immediately (enable ISBNdb fallback)
2. Run bulk CSV imports (100-500 books/day)
3. Prioritize books without covers in Google Books/OpenLibrary
4. Target: Cache 50,000-100,000 high-quality ISBNdb covers before subscription ends

---

## 🔗 **Related Documentation**

- Normalization utilities: `cloudflare-workers/api-worker/src/utils/normalization.ts`
- Cache utilities: `cloudflare-workers/api-worker/src/utils/cache.js`
- ISBNdb normalizers: `cloudflare-workers/api-worker/src/services/normalizers/isbndb.ts`
- Unified cache service: `cloudflare-workers/api-worker/src/services/unified-cache.js`
- Enrichment service: `cloudflare-workers/api-worker/src/services/enrichment.ts`
- Issue #202: ISBNdb Cover Harvest (completed Nov 2025)

---

**Priority:** 🚨 **URGENT** (ISBNdb subscription expires end of month)
**Labels:** `backend`, `performance`, `urgent`, `cache`, `isbndb`
**Assignee:** @copilot (for review), @jukasdrj (implementation)
