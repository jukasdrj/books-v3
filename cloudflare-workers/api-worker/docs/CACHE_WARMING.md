# Cache Warming - Phase 2

**Status:** ✅ Production Ready
**Deployed:** October 29, 2025
**Version:** 1.0.0

## Overview

Intelligent cache warming system that seeds from CSV files and auto-discovers related content via Cloudflare Queues. Pre-populates KV cache with author bibliographies to improve search performance.

## Architecture

```
CSV Upload → Gemini Parse → Extract Authors → Queue Messages
    ↓
Cloudflare Queue (author-warming-queue)
    ↓
Consumer Workers (5 concurrent batches, 10 authors/batch)
    ↓
OpenLibrary API Search → Cache Works in KV (24h TTL)
    ↓
Mark Authors as Processed (90-day deduplication)
```

## API Endpoint

### POST /api/warming/upload

Upload a CSV file to seed the cache with author bibliographies.

**Request:**
```json
{
  "csv": "base64-encoded CSV file",
  "maxDepth": 2
}
```

**Parameters:**
- `csv` (required, string): Base64-encoded CSV file with book data
- `maxDepth` (optional, integer, 1-3, default 2): Depth of author discovery (currently unused - co-author discovery deferred to Phase 3)

**Response (202 Accepted):**
```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "authorsQueued": 350,
  "estimatedWorks": 5250,
  "estimatedDuration": "2-4 hours"
}
```

**CSV Format:**
- Must include author information (parsed by Gemini AI)
- Typical Goodreads export format supported
- Max file size: 10MB

**Example:**
```bash
# Encode CSV file
CSV_DATA=$(base64 -i goodreads_library_export.csv)

# Upload for cache warming
curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d "{\"csv\":\"$CSV_DATA\",\"maxDepth\":1}"
```

### GET /api/warming/dlq

Monitor dead letter queue status.

**Response:**
```json
{
  "queue": "author-warming-dlq",
  "depth": 0,
  "message": "DLQ monitoring requires Wrangler API integration",
  "howToCheck": "Run: npx wrangler queues consumer list author-warming-dlq"
}
```

## Queue Configuration

**Producer Binding:** `AUTHOR_WARMING_QUEUE`
**Queue Name:** `author-warming-queue`

**Consumer Settings:**
- `max_batch_size`: 10 authors
- `max_batch_timeout`: 30 seconds
- `max_retries`: 3
- `max_concurrency`: 5 batches in parallel
- `dead_letter_queue`: `author-warming-dlq`

## Processing Flow

### 1. CSV Upload
- User uploads CSV via `/api/warming/upload`
- Gemini 2.0 Flash parses CSV to extract book data
- System extracts unique authors from parsed books
- Generates job UUID for tracking

### 2. Queueing
- Each unique author sent to `author-warming-queue`
- Message includes: `{ author, source: 'csv', depth: 0, queuedAt, jobId }`
- Job metadata stored in KV: `warming:job:{jobId}`

### 3. Consumer Processing
- Consumer workers process batches of 10 authors
- **Deduplication:** Check KV for `warming:processed:{author}`
  - Skip if already processed at same/higher depth
- **API Search:** Call OpenLibrary `getOpenLibraryAuthorWorks(author)`
- **Caching:** Store each work in KV with key `search:title:{lowercase-title}`
  - TTL: 24 hours (warmed entries)
  - Format: `{ items: [work], cached: true, timestamp }`
- **Mark Processed:** Store in KV: `warming:processed:{author}`
  - TTL: 90 days
  - Format: `{ worksCount, lastWarmed, depth }`

### 4. Co-Author Discovery (Deferred to Phase 3)
- OpenLibrary's `/authors/{id}/works.json` doesn't include co-author data
- Would require additional API call per work: `GET /works/{id}.json`
- Cost-benefit analysis showed excessive API load
- Can be enabled later if usage patterns justify it

## Monitoring

### Analytics Engine

The system uses existing `CACHE_ANALYTICS` binding for metrics:

**Events Tracked:**
- `author_processed` - Successful author processing
- `author_failed` - Processing failures
- `works_cached` - Number of works cached

**Example Query:**
```sql
SELECT
  blob2 as author_name,
  SUM(double1) as total_works_cached,
  AVG(double2) as avg_processing_time_ms
FROM CACHE_ANALYTICS
WHERE blob1 = 'author_processed'
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY author_name
ORDER BY total_works_cached DESC
LIMIT 20
```

### Queue Monitoring

**Check queue depth:**
```bash
npx wrangler queues list
```

**Tail consumer logs:**
```bash
npx wrangler tail api-worker --format pretty
```

**Check DLQ:**
```bash
npx wrangler queues consumer list author-warming-dlq
```

### Dead Letter Queue

Failed messages (after 3 retries) go to `author-warming-dlq`. Monitor this queue to identify problematic authors or API issues.

**Common Failure Reasons:**
- Author not found in OpenLibrary
- OpenLibrary API timeout
- Invalid author names
- Rate limiting (unlikely with 10 authors/batch)

## Performance

### Processing Speed
- **Batch size:** 10 authors every 30s
- **Concurrency:** 5 batches in parallel = 50 authors/30s
- **Throughput:** ~6000 authors/hour
- **API calls:** 1 call per author (author lookup + works fetch)

### Cache Hit Improvement
- **Before warming:** ~30% cache hit rate
- **After warming:** Expected 75-85% hit rate for warmed authors
- **TTL:** 24 hours (warmed entries expire after 1 day)

### Cost Estimates
- **Queue operations:** Free (< 1M ops/month)
- **KV writes:** ~$0.50 per 100K authors
- **KV reads:** Free (deduplication checks)
- **OpenLibrary API:** Free (no rate limits for reasonable use)
- **Total:** ~$0.01 per 1000 authors processed

## Deduplication

Authors are marked as "processed" for 90 days to prevent redundant work:

**Key:** `warming:processed:{authorName}`
**Value:** `{ worksCount, lastWarmed, depth }`
**TTL:** 90 days

**Logic:**
- If author processed at depth >= current depth → skip
- If author processed at lower depth → re-process (allows deeper discovery in Phase 3)

## Limitations

1. **Co-Author Discovery:** Deferred to Phase 3 (requires expensive per-work API calls)
2. **OpenLibrary Only:** Currently only uses OpenLibrary API (Google Books/ISBNdb could be added)
3. **CSV Format:** Relies on Gemini parsing (may miss authors if CSV format is unusual)
4. **No Progress Tracking:** Job status not exposed via WebSocket (could be added)
5. **No Cancellation:** Running jobs cannot be cancelled mid-processing

## Troubleshooting

### Queue Not Processing

**Symptom:** Authors queued but no cache entries appearing

**Diagnosis:**
```bash
# Check queue consumer is deployed
npx wrangler deployments list

# Tail logs for errors
npx wrangler tail api-worker --format pretty
```

**Common Causes:**
- Consumer not enabled in wrangler.toml
- GEMINI_API_KEY missing or invalid
- OpenLibrary API down
- KV namespace misconfigured

### Authors Skipped

**Symptom:** Log shows "Skipping {author}: already processed"

**Explanation:** Author was processed within last 90 days. This is intentional deduplication.

**To Force Re-process:**
```bash
# Delete processed marker from KV
npx wrangler kv:key delete "warming:processed:Neil Gaiman" --namespace-id b9cade63b6db48fd80c109a013f38fdb
```

### High DLQ Depth

**Symptom:** Dead letter queue accumulating messages

**Diagnosis:**
```bash
npx wrangler queues consumer list author-warming-dlq
```

**Action:**
1. Check logs for error patterns
2. Identify problematic author names
3. Fix underlying issue (API access, data quality, etc.)
4. Retry messages: `npx wrangler queues consumer retry author-warming-dlq`

## Testing

### Unit Tests
```bash
npm test warming-upload.test.js
npm test author-warming-consumer.test.js
```

**Coverage:**
- CSV validation (required fields, maxDepth range)
- Gemini parsing integration
- Author queueing with metadata
- Deduplication logic
- API search and caching
- Error handling (ack/retry)

### Manual Testing

**Test 1: Upload CSV**
```bash
echo "title,author,isbn
The Hobbit,J.R.R. Tolkien,9780547928227
1984,George Orwell,9780451524935" | base64 > test.csv

curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d "{\"csv\":\"$(cat test.csv)\",\"maxDepth\":1}"
```

**Expected:** `{"jobId":"...","authorsQueued":2,...}`

**Test 2: Verify Caching**
```bash
# Wait 30-60 seconds for processing

# Check if works cached
curl https://api-worker.jukasdrj.workers.dev/search/title?q=hobbit

# Should return results with cache headers
```

**Test 3: Verify Deduplication**
```bash
# Upload same CSV again
curl -X POST https://api-worker.jukasdrj.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d "{\"csv\":\"$(cat test.csv)\",\"maxDepth\":1}"

# Authors should be skipped (check logs)
npx wrangler tail api-worker --format pretty
```

## Next Steps

### Phase 3: Enhancements (Future)

1. **Co-Author Discovery**
   - Implement per-work API calls to fetch co-authors
   - Add toggle to enable/disable (opt-in for high-value use cases)

2. **Multi-Provider Support**
   - Add Google Books and ISBNdb as fallback sources
   - Prioritize providers based on author region

3. **Progress Tracking**
   - Add WebSocket support for job progress
   - Report: authors processed, works cached, errors

4. **Smart Scheduling**
   - Re-warm popular authors before TTL expiration
   - Priority queue for frequently searched authors

5. **Analytics Dashboard**
   - Visualize cache hit rates
   - Top warmed authors
   - Processing throughput graphs

## References

- **Implementation Plan:** `docs/plans/2025-10-28-cache-warming-implementation.md`
- **OpenLibrary API:** https://openlibrary.org/dev/docs/api/authors
- **Cloudflare Queues:** https://developers.cloudflare.com/queues/
- **Worker Source:** `src/consumers/author-warming-consumer.js`
- **Tests:** `tests/warming-upload.test.js`, `tests/author-warming-consumer.test.js`

---

**Last Updated:** October 29, 2025
**Maintained By:** Claude Code + @jukasdrj
