# Cache Warming Design - Phase 2

**Date:** 2025-10-28
**Status:** Design Approved
**Prerequisites:** Phase 1 (Foundation) - Edge + KV + Unified Cache

## Overview

Intelligent cache warming system that seeds from CSV files and automatically discovers related content by exploring author relationships. Uses Cloudflare Queues for scalable, fault-tolerant processing.

## Goals

1. **Seed from CSV:** Import years of Goodreads exports to warm cache with user's library
2. **Auto-discovery:** Expand cache by finding other works by discovered authors
3. **Scalability:** Process thousands of authors without blocking user requests
4. **Fault tolerance:** Automatic retries, duplicate prevention, resume on failure

## Architecture

```
CSV Upload → Gemini Parse → Queue API → Consumer Workers → Cache + Author Discovery → Repeat
```

### Components

#### 1. CSV Ingestion Endpoint

**Endpoint:** `POST /api/warming/upload`

**Request:**
```json
{
  "csv": "base64-encoded CSV file",
  "maxDepth": 2,  // How many levels of author discovery (1-3)
  "priority": "normal|high"
}
```

**Flow:**
1. Accept CSV file (reuse existing Gemini CSV parser)
2. Extract (title, author, ISBN) tuples via Gemini
3. Deduplicate authors
4. Publish each author to `author-warming-queue`
5. Return `jobId` for progress tracking

**Response:**
```json
{
  "jobId": "uuid",
  "authorsQueued": 350,
  "estimatedWorks": 5250,
  "estimatedDuration": "2-4 hours"
}
```

#### 2. Author Warming Queue

**Queue:** `author-warming-queue` (Cloudflare Queues)

**Message Format:**
```json
{
  "author": "Neil Gaiman",
  "source": "csv|discovery",
  "depth": 0,  // 0=from CSV, 1=discovered, 2=co-author
  "queuedAt": "2025-10-28T15:00:00Z"
}
```

**Configuration:**
- Batch size: 10 messages
- Max retries: 3
- Dead letter queue: `author-warming-dlq`
- Consumer concurrency: 5 workers

#### 3. Author Discovery Consumer

**Worker:** `author-warming-consumer.js`

**Processing Flow:**

```javascript
async function processAuthorBatch(batch, env, ctx) {
  for (const message of batch.messages) {
    const { author, depth } = message.body;

    // 1. Check if already processed (prevent duplicates)
    const processed = await env.CACHE.get(`warming:processed:${author}`);
    if (processed && depth <= JSON.parse(processed).depth) {
      message.ack();
      continue;
    }

    // 2. Search external APIs for author's works
    const works = await searchAuthorWorks(author, env);

    // 3. Cache each work via UnifiedCacheService
    const cache = new UnifiedCacheService(env, ctx);
    for (const work of works) {
      const cacheKey = generateCacheKey('search:title', {
        title: work.title.toLowerCase()
      });
      await cache.kvCache.set(cacheKey, work, 'title');
    }

    // 4. Discover co-authors (if depth < maxDepth)
    if (depth < 2) {
      const coAuthors = extractCoAuthors(works);
      for (const coAuthor of coAuthors) {
        await env.AUTHOR_WARMING_QUEUE.send({
          author: coAuthor,
          source: 'discovery',
          depth: depth + 1,
          queuedAt: new Date().toISOString()
        });
      }
    }

    // 5. Mark as processed with TTL
    await env.CACHE.put(
      `warming:processed:${author}`,
      JSON.stringify({
        worksCount: works.length,
        lastWarmed: Date.now(),
        depth: depth
      }),
      { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
    );

    message.ack();
  }
}
```

**Error Handling:**
- Retry 3x with exponential backoff
- After 3 failures → Dead letter queue
- Alert if DLQ depth > 10

#### 4. State Tracking (KV)

**Keys:**

1. `warming:processed:{authorName}`
   - Value: `{worksCount: N, lastWarmed: timestamp, depth: N}`
   - TTL: 90 days (refresh if re-queued)
   - Purpose: Prevent duplicate processing

2. `warming:queue:pending`
   - Value: Array of pending author names
   - TTL: 24 hours
   - Purpose: UI progress display (snapshot, not authoritative)

3. `warming:stats`
   - Value: `{totalAuthors: N, totalWorks: N, startedAt: timestamp, completedAt: timestamp|null}`
   - TTL: None (permanent)
   - Purpose: Job-level metrics

## Example Flow

**Input:** goodreads_library_export.csv (500 books)

1. **Ingestion:**
   - Gemini extracts 300 unique authors
   - 300 messages → `author-warming-queue` (depth=0)

2. **Depth 0 Processing:**
   - Consumer processes 10 authors/batch × 30 batches
   - Each author: Search API → ~15 works average
   - Total: 4,500 works cached
   - Discover 50 unique co-authors

3. **Depth 1 Processing:**
   - 50 co-author messages (depth=1)
   - Each co-author: ~15 works
   - Total: 750 additional works
   - Discover 20 more co-authors (depth=2)

4. **Depth 2 Processing:**
   - 20 co-author messages (depth=2)
   - 300 additional works
   - Stop (maxDepth reached)

**Final Result:** ~5,550 works warmed from 500-book CSV (11x multiplication)

## TTL Strategy

| Resource | TTL | Rationale |
|----------|-----|-----------|
| Processed authors | 90 days | Prevent re-processing, but allow refresh after 3 months |
| Queue pending snapshot | 24 hours | UI display only, refresh daily |
| Cached works (title) | 24 hours | Follow Phase 1 TTLs |
| Cached works (ISBN) | 30 days | Follow Phase 1 TTLs |
| Job stats | Permanent | Historical record |

## Performance Estimates

| Metric | Value |
|--------|-------|
| CSV parse time | 10-30 seconds |
| Author processing rate | 100 authors/hour |
| Works per author (avg) | 15 |
| Cache write rate | 1,500 works/hour |
| Total warmup time (500-book CSV) | 2-4 hours |

## Cost Analysis

**Cloudflare Queues:**
- Free tier: 1M operations/month
- Expected usage: ~10K operations/warmup job
- Cost: $0 (well within limits)

**KV Writes:**
- ~5,500 writes per 500-book CSV
- Cost: $0.50/million writes = $0.003 per warmup
- Monthly (4 CSVs): $0.012

**External API Calls:**
- ~350 authors × 1 API call = 350 calls
- Cached in KV for 24h (reused across depth levels)
- No additional cost (existing API quotas)

**Total Phase 2 Cost:** ~$0.10/month (primarily KV storage growth)

## Error Scenarios & Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| Gemini parse failure | Invalid CSV format | Return 400, suggest format fixes |
| Queue full | Too many pending messages | Return 429, suggest retry after N minutes |
| API rate limit | External API throttling | Exponential backoff, retry after window |
| DLQ depth > 10 | Repeated author failures | Email alert, manual investigation |
| Consumer crash | Worker exception | Auto-restart, message reprocessed |

## Monitoring

**Metrics to track:**
- Queue depth (target: <100 pending)
- Processing rate (authors/hour)
- Cache hit rate (should stay 95%+ during warmup)
- DLQ depth (target: 0, alert >10)

**Dashboard Query (Analytics Engine):**
```sql
SELECT
  DATE_TRUNC('hour', timestamp) as hour,
  COUNT(*) as authors_processed,
  SUM(works_cached) as total_works
FROM WARMING_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '24' HOUR
GROUP BY hour
ORDER BY hour DESC;
```

## Future Enhancements

1. **Priority queue:** Warm popular authors first (based on user's rating/read count)
2. **Smart depth:** Increase depth for favorite authors, decrease for one-off reads
3. **Genre-based discovery:** Expand to similar authors in same genre
4. **User preferences:** Let users configure warmup aggressiveness

## Dependencies

- Phase 1: UnifiedCacheService, KVCacheService
- Cloudflare Queues binding: `AUTHOR_WARMING_QUEUE`
- Existing Gemini CSV parser
- KV namespace: `CACHE` (for state tracking)
