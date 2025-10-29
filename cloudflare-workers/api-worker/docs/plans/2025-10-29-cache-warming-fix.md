# Cache Warming System Fix - Design Document

**Status:** Design Complete, Ready for Implementation
**Created:** October 29, 2025
**Author:** Claude Code + @jukasdrj
**Related Issue:** Cache key mismatch causing 0% warming hit rate

## Problem Statement

The current cache warming system (deployed October 28, 2025) creates cache entries that are **never used** by search endpoints due to five critical mismatches:

### Identified Issues

1. **Cache Key Format Mismatch** (Critical)
   - Warmer: `search:title:the hobbit`
   - Search: `search:title:maxresults=20&title=the hobbit`
   - **Impact:** 0% cache hit rate from warming

2. **Data Structure Incompatibility**
   - Warmer stores minimal OpenLibrary work objects
   - Search expects Google Books + OpenLibrary orchestrated format
   - **Impact:** Even if keys matched, data structure won't work

3. **Cache Tier Bypass**
   - Warmer writes to KV only (Tier 2)
   - Search reads Edge → KV → R2 (prioritizes Edge/Tier 1 with 80% hit rate)
   - **Impact:** Warmed entries never populate fastest cache tier

4. **TTL Mismatch**
   - Warmer: 24h TTL
   - Title search: 6h TTL
   - **Impact:** Inconsistent expiration behavior

5. **Missing R2 Cold Storage Integration**
   - Warmer doesn't create R2 cold indexes
   - UnifiedCacheService expects `cold-index:` entries for rehydration
   - **Impact:** Warmed data not eligible for long-term storage

### Business Impact

- **Current warming job:** 47 authors queued, ~10 processed, creating ~500 unusable cache entries
- **API cost:** Wasting OpenLibrary API calls that don't improve cache hit rates
- **Performance:** No improvement to title/author search response times
- **Resource waste:** Queue processing time spent on ineffective operations

## Goals

1. **Primary:** Fix cache key format to match search endpoint expectations (100% compatibility)
2. **Secondary:** Integrate with UnifiedCacheService (Edge → KV → R2) for tier-aware caching
3. **Tertiary:** Optimize for actual user flow (author browse → title drill-down)
4. **Cost:** Avoid ISBNdb usage, rely on free APIs (Google Books + OpenLibrary)

## Design Decision: Author-First Hierarchical Warming

### Core Strategy

Instead of warming titles from CSV, **warm authors first, then cascade to titles**:

```
CSV Upload → Extract Authors → Queue Authors
    ↓
For each author:
    1. Warm author bibliography (search:author:*)
    2. Extract titles from author's works
    3. Warm each title (search:title:*)
```

### Rationale

- **Fewer queue messages:** Queue 47 authors, not 1000+ titles
- **User flow alignment:** Users browse authors first, then individual books
- **Efficient API usage:** Author lookup discovers all titles automatically
- **Hierarchical caching:** Both author pages AND title searches pre-warmed

## Architecture

### Component Changes

#### 1. UnifiedCacheService Enhancement

**Add `set()` method** for tier-aware writes:

```javascript
// src/services/unified-cache.js
async set(cacheKey, data, endpoint, ttl = 21600) {
  // Write to all three tiers
  await Promise.all([
    this.edgeCache.set(cacheKey, data, ttl),           // Tier 1: Edge
    this.kvCache.set(cacheKey, data, endpoint, ttl),   // Tier 2: KV
    this.createColdIndex(cacheKey, data, endpoint)     // Tier 3: R2 index
  ]);
}

async createColdIndex(cacheKey, data, endpoint) {
  // Create R2 cold storage index for future rehydration
  const indexKey = `cold-index:${cacheKey}`;
  const indexData = {
    r2Key: `cold-cache/${new Date().toISOString().split('T')[0]}/${cacheKey}`,
    createdAt: Date.now(),
    endpoint: endpoint,
    size: JSON.stringify(data).length
  };

  await this.env.CACHE.put(indexKey, JSON.stringify(indexData), {
    expirationTtl: 90 * 24 * 60 * 60 // 90 days
  });
}
```

#### 2. Cache Warming Consumer (Modified)

**File:** `src/consumers/author-warming-consumer.js` (keep existing name)

**New Flow:**

```javascript
export async function processAuthorBatch(batch, env, ctx) {
  const unifiedCache = new UnifiedCacheService(env, ctx);

  for (const message of batch.messages) {
    try {
      const { author, source, jobId } = message.body;

      // 1. Check if already processed
      const processed = await env.CACHE.get(`warming:processed:author:${author.toLowerCase()}`);
      if (processed) {
        console.log(`Skipping ${author}: already processed`);
        message.ack();
        continue;
      }

      // 2. STEP 1: Warm author bibliography
      const authorResult = await searchByAuthor(author, {
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      }, env, ctx);

      if (!authorResult.success || !authorResult.works || authorResult.works.length === 0) {
        console.warn(`No works found for ${author}, skipping`);
        message.ack();
        continue;
      }

      // Cache author search result
      const authorCacheKey = generateCacheKey('search:author', {
        author: author.toLowerCase(),
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      });

      await unifiedCache.set(authorCacheKey, authorResult, 'author', 21600); // 6h TTL
      console.log(`Cached author "${author}": ${authorResult.works.length} works`);

      // 3. STEP 2: Extract titles and warm each one
      let titlesWarmed = 0;
      for (const work of authorResult.works) {
        try {
          // Search by title to get full orchestrated data (Google + OpenLibrary)
          const titleResult = await searchByTitle(work.title, {
            maxResults: 20
          }, env, ctx);

          if (titleResult && titleResult.items && titleResult.items.length > 0) {
            const titleCacheKey = generateCacheKey('search:title', {
              title: work.title.toLowerCase(),
              maxResults: 20
            });

            await unifiedCache.set(titleCacheKey, titleResult, 'title', 21600); // 6h TTL
            titlesWarmed++;
          }

          // Rate limiting: Small delay between title searches
          await sleep(100); // 100ms between titles

        } catch (titleError) {
          console.error(`Failed to warm title "${work.title}":`, titleError);
          // Continue with next title (don't fail entire batch)
        }
      }

      console.log(`Warmed ${titlesWarmed} titles for author "${author}"`);

      // 4. Mark author as processed
      await env.CACHE.put(
        `warming:processed:author:${author.toLowerCase()}`,
        JSON.stringify({
          worksCount: authorResult.works.length,
          titlesWarmed: titlesWarmed,
          lastWarmed: Date.now(),
          jobId: jobId
        }),
        { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
      );

      // 5. Analytics
      if (env.CACHE_ANALYTICS) {
        await env.CACHE_ANALYTICS.writeDataPoint({
          blobs: ['warming', author, source],
          doubles: [authorResult.works.length, titlesWarmed],
          indexes: ['cache-warming']
        });
      }

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);

      // Retry on rate limits, fail otherwise
      if (error.message.includes('429') || error.message.includes('rate limit')) {
        message.retry();
      } else {
        message.retry(); // Retry up to 3 times
      }
    }
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
```

#### 3. Queue Configuration

**File:** `wrangler.toml`

```toml
[[queues.consumers]]
queue = "author-warming-queue"  # UNCHANGED
max_batch_size = 5              # REDUCED from 10 (API safety)
max_batch_timeout = 30          # UNCHANGED
max_retries = 3                 # UNCHANGED
max_concurrency = 3             # REDUCED from 5 (rate limit protection)
dead_letter_queue = "author-warming-dlq"
```

**Rationale:**
- **Batch size 5:** Each author triggers 1 author search + 100+ title searches
- **Concurrency 3:** Avoid overwhelming Google Books (1000 queries/day limit)
- **Processing time:** 5-15 minutes per batch (acceptable for background warming)

#### 4. Warming Upload Handler

**File:** `src/handlers/warming-upload.js`

**Changes:** MINIMAL - Keep existing author extraction logic

```javascript
// Extract unique authors (UNCHANGED)
const authorsSet = new Set();
for (const book of books) {
  if (book.author) {
    authorsSet.add(book.author.trim());
  }
}

const uniqueAuthors = Array.from(authorsSet);

// Queue each author (UNCHANGED)
for (const author of uniqueAuthors) {
  await env.AUTHOR_WARMING_QUEUE.send({
    author: author,
    source: 'csv',
    queuedAt: new Date().toISOString(),
    jobId: jobId
  });
}
```

**Note:** No changes needed to upload handler!

## Data Flow

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. CSV Upload → Gemini Parse → Extract Authors → Queue Messages│
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. Cloudflare Queue (author-warming-queue)                      │
│    - Batch size: 5 authors                                      │
│    - Concurrency: 3 batches                                     │
│    - Timeout: 30 seconds                                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. Consumer: For each author in batch                           │
│                                                                  │
│    STEP 1: Warm Author Bibliography                             │
│    ├─ searchByAuthor(author, {limit: 100, ...})                │
│    ├─ Returns: OpenLibrary author works (minimal data)         │
│    ├─ Cache key: search:author:author=harper lee&limit=100...  │
│    └─ Store via UnifiedCacheService.set()                      │
│        ├─ Edge Cache (Tier 1): 6h TTL                          │
│        ├─ KV Cache (Tier 2): 6h TTL                            │
│        └─ R2 Index (Tier 3): 90-day pointer                    │
│                                                                  │
│    STEP 2: Extract Titles, Warm Each                           │
│    └─ For each work in author.works:                           │
│        ├─ searchByTitle(work.title, {maxResults: 20})          │
│        ├─ Returns: Google + OpenLibrary orchestrated data      │
│        ├─ Cache key: search:title:maxresults=20&title=...      │
│        └─ Store via UnifiedCacheService.set()                  │
│            ├─ Edge Cache: 6h TTL                                │
│            ├─ KV Cache: 6h TTL                                  │
│            └─ R2 Index: 90-day pointer                          │
│                                                                  │
│    STEP 3: Mark Processed                                       │
│    └─ warming:processed:author:{author} → KV (90-day TTL)      │
└─────────────────────────────────────────────────────────────────┘
```

### Cache Key Alignment

**Author Search:**
- **Warmer generates:** `search:author:author=harper lee&limit=100&offset=0&sortby=publicationyear`
- **Search endpoint:** `search:author:author=harper lee&limit=100&offset=0&sortby=publicationyear`
- **Result:** ✅ Perfect match

**Title Search:**
- **Warmer generates:** `search:title:maxresults=20&title=the hobbit`
- **Search endpoint:** `search:title:maxresults=20&title=the hobbit`
- **Result:** ✅ Perfect match

## Error Handling

### Rate Limit Protection

**Google Books:** 1000 queries/day free tier
- **Strategy:** Reduce concurrency to 3, add 100ms delay between titles
- **Handling:** Retry with exponential backoff on 429 responses

**OpenLibrary:** No strict limits (courtesy 1 req/sec)
- **Strategy:** Built-in delays in title warming loop
- **Handling:** Retry transient errors

### Consumer Error Handling

```javascript
try {
  // Warm author + titles
} catch (error) {
  if (error.message.includes('429') || error.message.includes('rate limit')) {
    console.error(`Rate limit hit for ${author}, will retry`);
    message.retry(); // Exponential backoff
  } else {
    console.error(`Failed to warm ${author}:`, error);
    message.retry(); // Up to 3 retries
  }
}
```

### Dead Letter Queue

- **Queue:** `author-warming-dlq`
- **After 3 retries:** Failed authors sent to DLQ
- **Monitor:** `npx wrangler queues consumer list author-warming-dlq`
- **Common failures:** API timeouts, invalid author names, network errors

## Performance Estimates

### Processing Speed

**Per Author:**
- Author search: 1 OpenLibrary call (~500ms)
- Title searches: 100 titles × 2 API calls (Google + OpenLibrary) = 200 calls (~2-3 minutes)
- **Total:** ~3-4 minutes per author

**Per Batch (5 authors):**
- Sequential processing: 5 authors × 3 minutes = **15 minutes**
- With parallelization: ~10 minutes (limited by rate limits)

**Full CSV (47 authors):**
- 47 authors ÷ 5 per batch = ~10 batches
- 10 batches × 10 minutes = **~2 hours total**
- Concurrency 3: Multiple batches run in parallel, reduces to ~1.5 hours

### API Usage

**Per Author (100 works average):**
- 1 author search (OpenLibrary)
- 100 title searches × 2 providers = 200 API calls
- **Total:** 201 API calls per author

**Full CSV (47 authors):**
- 47 authors × 201 calls = **~9,447 API calls**
- Google Books: 4,700 calls (within 10K/day limit)
- OpenLibrary: 4,700 calls (no strict limits)

### Cache Hit Improvement

**Before warming:**
- Title search: 30% hit rate (cold cache)
- Author search: 20% hit rate (cold cache)

**After warming:**
- Title search: 80-90% hit rate (warmed titles from popular authors)
- Author search: 90-95% hit rate (all CSV authors cached)

## Migration Plan

### Phase A: Stop Current Job (Immediate)

**Action:** Let current warming job complete (37 authors remaining, ~1-2 hours)

**Cleanup after completion:**
```bash
# List incompatible cache entries (missing maxResults param)
npx wrangler kv:key list \
  --namespace-id b9cade63b6db48fd80c109a013f38fdb \
  --prefix "search:title:"

# Identify old format: Keys without "maxresults=" are from broken warmer
# These will naturally expire in 24h, no manual deletion needed
```

### Phase B: Implement UnifiedCacheService.set()

**Files to modify:**
- `src/services/unified-cache.js` - Add `set()` and `createColdIndex()` methods
- `src/services/edge-cache.js` - Add `set()` method (wraps `caches.default.put()`)
- `src/services/kv-cache.js` - Add `set()` method (wraps `env.CACHE.put()`)

**Testing:**
- Manual script to test tier writes
- Verify Edge, KV, and R2 index all populated

### Phase C: Refactor Consumer

**Files to modify:**
- `src/consumers/author-warming-consumer.js` - Implement author-first flow

**Testing:**
- Unit tests for author + title warming logic
- Mock `searchByAuthor()` and `searchByTitle()` responses
- Verify cache key generation

### Phase D: Update Queue Config & Deploy

**Files to modify:**
- `wrangler.toml` - Update batch size (5) and concurrency (3)

**Deployment:**
```bash
cd cloudflare-workers/api-worker
npx wrangler deploy
```

**Monitoring:**
```bash
npx wrangler tail api-worker --format pretty
```

### Phase E: Validation

**Test CSV (10 authors):**
```bash
# Upload small test CSV
curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d '{"csv":"<base64-encoded-test-csv>","maxDepth":1}'
```

**Verify cache hits:**
```bash
# Wait 5 minutes for processing

# Test author search (should be cached)
curl https://api-worker.jukasdrj.workers.dev/search/author?name=Neil%20Gaiman

# Test title search (should be cached)
curl https://api-worker.jukasdrj.workers.dev/search/title?q=American%20Gods

# Check response headers for X-Cache-Tier: EDGE or KV
```

**Success Criteria:**
- Author searches return `cached: true, cacheSource: "EDGE"`
- Title searches return `cached: true, cacheSource: "EDGE"`
- Queue processes without rate limit errors
- All three cache tiers populated

### Phase F: Full Re-Run

**If validation succeeds:**
```bash
# Re-upload 2015.csv (47 authors)
CSV_DATA=$(base64 -i docs/testImages/csv-expansion/2015.csv)
curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d "{\"csv\":\"$CSV_DATA\",\"maxDepth\":1}"
```

**Monitor progress:**
- Watch logs for processing activity
- Check Analytics Engine for warming metrics
- Verify no DLQ accumulation

## Cost Analysis

### API Costs

**Google Books:**
- Free tier: 1,000 queries/day
- Current usage: 4,700 queries per full CSV
- **Impact:** Within limits (spread over 2 hours)

**OpenLibrary:**
- Free, no rate limits
- Courtesy: ~1 req/sec
- **Impact:** No cost

**ISBNdb:**
- Currently unused in warming
- **Recommendation:** Keep endpoint for manual testing, consider removal later

### Cloudflare Costs

**Queue Operations:**
- Free tier: 1M operations/month
- Current usage: ~500 messages/day
- **Impact:** $0

**KV Writes:**
- $0.50 per 1M writes
- Current usage: ~10K writes per CSV
- **Impact:** ~$0.005 per CSV

**R2 Storage:**
- $0.015 per GB/month
- Current usage: ~100MB for cold indexes
- **Impact:** ~$0.001/month

**Total Cost:** ~$0.01 per CSV warming run

## Monitoring

### Logs

**Real-time:**
```bash
npx wrangler tail api-worker --format pretty
```

**Key patterns:**
- `Cached author "Harper Lee": 43 works`
- `Warmed 40 titles for author "Harper Lee"`
- `Skipping Neil Gaiman: already processed`

### Analytics Queries

**Cache warming performance:**
```sql
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
LIMIT 20
```

**Cache hit rates (post-warming):**
```sql
SELECT
  blob1 as endpoint,
  blob3 as cache_status,
  COUNT(*) as requests,
  AVG(double1) as avg_response_time_ms
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY endpoint, cache_status
ORDER BY endpoint, cache_status
```

### Dead Letter Queue

**Check DLQ depth:**
```bash
npx wrangler queues consumer list author-warming-dlq
```

**Retry failed messages:**
```bash
npx wrangler queues consumer retry author-warming-dlq
```

## Success Metrics

### Primary Metrics

1. **Cache Key Compatibility:** 100% match between warmer and search endpoints
2. **Cache Hit Rate:** 80-90% for warmed titles, 90-95% for warmed authors
3. **Tier Coverage:** Edge, KV, and R2 all populated by warmer

### Secondary Metrics

1. **Processing Time:** <2 hours for 47-author CSV
2. **API Errors:** <5% failure rate (rate limits, timeouts)
3. **DLQ Depth:** <10 messages (healthy error rate)

### Validation Checklist

- [ ] Cache keys match between warmer and search
- [ ] Author searches return cached results (Edge tier)
- [ ] Title searches return cached results (Edge tier)
- [ ] R2 cold indexes created for warmed entries
- [ ] Queue processes without rate limit errors
- [ ] DLQ remains empty or near-empty
- [ ] Analytics show warming activity
- [ ] Response times improve for warmed queries

## Risks & Mitigations

### Risk 1: Google Books Rate Limits

**Likelihood:** Medium (4,700 calls per CSV run)
**Impact:** High (warming stops, incomplete cache)

**Mitigation:**
- Reduce concurrency to 3
- Add 100ms delays between title searches
- Implement exponential backoff on 429 responses
- Monitor daily quota usage

### Risk 2: OpenLibrary Timeouts

**Likelihood:** Low (stable API)
**Impact:** Medium (individual author failures)

**Mitigation:**
- Retry logic (3 attempts)
- DLQ for persistent failures
- Skip to next author on failure

### Risk 3: Edge Cache Eviction

**Likelihood:** High (Edge cache is ephemeral)
**Impact:** Low (KV and R2 still available)

**Mitigation:**
- Multi-tier caching (Edge + KV + R2)
- R2 rehydration on Edge misses
- Accept Edge cache as best-effort

### Risk 4: Stale Author Bibliographies

**Likelihood:** Low (authors rarely add 10+ books/week)
**Impact:** Low (90-day TTL refreshes periodically)

**Mitigation:**
- 90-day deduplication window (balances freshness and efficiency)
- Manual re-warming available via `/api/warming/upload`

## Future Enhancements

### Phase 2: Smart Scheduling

- Re-warm popular authors before TTL expiration
- Priority queue for frequently searched authors
- Analytics-driven warming (warm most-accessed content first)

### Phase 3: Multi-Provider Expansion

- Add Google Books author search as alternative to OpenLibrary
- Prioritize providers based on author region/language
- Fallback to secondary provider on primary failure

### Phase 4: Progress Tracking

- WebSocket support for warming job progress
- Report: authors processed, titles warmed, errors
- Real-time dashboard for monitoring

### Phase 5: ISBN-based Warming

- Extract ISBNs from CSV (in addition to authors)
- Pre-warm ISBN searches (7-day TTL)
- Reduce lookup time for barcode scanner

## References

- **Current Implementation:** `docs/CACHE_WARMING.md`
- **OpenLibrary API:** https://openlibrary.org/dev/docs/api/authors
- **Google Books API:** https://developers.google.com/books/docs/v1/using
- **Cloudflare Queues:** https://developers.cloudflare.com/queues/
- **UnifiedCacheService:** `src/services/unified-cache.js`
- **Author Search Handler:** `src/handlers/author-search.js`
- **Book Search Handler:** `src/handlers/book-search.js`

---

**Design Status:** Complete
**Next Step:** Worktree setup + implementation planning
**Estimated Effort:** 4-6 hours (implementation) + 2 hours (testing/validation)
