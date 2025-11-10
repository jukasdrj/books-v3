# Analytics-Driven Cache Warming

## Overview

Automated system that analyzes real user search patterns and proactively warms the cache for popular queries with low hit rates.

## Architecture

```
┌─────────────────┐
│ Analytics Engine│  ← Tracks all searches (cache hits/misses)
└────────┬────────┘
         │
         │ Daily Query (GraphQL)
         ↓
┌─────────────────┐
│ analyze-and-warm│  ← Node.js script (GitHub Actions)
│     script      │
└────────┬────────┘
         │
         │ Identifies: Popular + Low Hit Rate
         ↓
┌─────────────────┐
│ author-warming  │  ← Cloudflare Queue
│      queue      │
└────────┬────────┘
         │
         │ Batch Processing
         ↓
┌─────────────────┐
│ Queue Consumer  │  ← Worker processes warming jobs
│     Worker      │
└────────┬────────┘
         │
         │ Fetch & Cache
         ↓
┌─────────────────┐
│  KV + Edge Cache│  ← Pre-warmed before user asks
└─────────────────┘
```

## Setup

### 1. Cloudflare API Token

Create a token with permissions:
- **Analytics Engine**: Read
- **Queues**: Write

```bash
# Set environment variables
export CF_ACCOUNT_ID="your-account-id"
export CF_API_TOKEN="your-api-token"
```

### 2. GitHub Secrets

Add to repository secrets:
- `CF_ACCOUNT_ID`
- `CF_API_TOKEN`

### 3. Test Locally

```bash
cd cloudflare-workers/api-worker
node scripts/analyze-and-warm.js
```

**Expected Output:**
```
🔍 Analyzing cache performance...
   Period: Last 24 hours
   Min requests: 5
   Top N: 20

📊 Querying Analytics Engine...
🧮 Analyzing query patterns...

📋 Found 12 warming candidates:
   1. "Stephen King" (47 requests)
   2. "J.K. Rowling" (32 requests)
   ...

📤 Sending 12 warming jobs to queue...
✅ Queued 12 warming jobs

🎉 Analytics-driven warming complete!
```

## How It Works

### 1. Analytics Collection

Every search request writes to Analytics Engine:

```javascript
env.CACHE_ANALYTICS.writeDataPoint({
  blobs: ['title', 'Harry Potter'],  // [type, query]
  indexes: ['HIT']                    // 'HIT' or 'MISS'
});
```

### 2. Pattern Analysis

Script queries Analytics Engine and identifies:
- Queries with **≥5 requests** in last 24h
- Focus on **author searches** (highest warming ROI)
- Sorted by **popularity** (total requests)

### 3. Queue Production

Warming jobs sent to `author-warming-queue`:

```javascript
{
  author: "Stephen King",
  depth: 1,
  source: "analytics-driven",
  jobId: "analytics-1699123456-0",
  priority: 47  // Total requests
}
```

### 4. Consumer Processing

`author-warming-consumer.js` processes each job:
1. Fetch author bibliography (100 works)
2. Cache author data
3. Warm individual title searches
4. Mark author as processed (90-day TTL)

### 5. Result

Users get instant cache hits on next search!

## Configuration

Edit `scripts/analyze-and-warm.js`:

```javascript
// Warming criteria
const MIN_REQUESTS = 5;         // Minimum popularity threshold
const MAX_CACHE_HIT_RATE = 0.6; // Max 60% hit rate (lower = more warming needed)
const TOP_N_QUERIES = 20;       // Warm top N queries
const LOOKBACK_HOURS = 24;      // Analysis window
```

## Monitoring

### GitHub Actions

View warming reports:
1. Go to **Actions** → **Analytics-Driven Cache Warming**
2. Check workflow run logs
3. Download `warming-report.json` artifact

### Analytics Engine Queries

Query via GraphQL:

```graphql
query {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      analyticsEngineDatasets(filter: { name: "books_api_cache_metrics" }) {
        query(
          filter: {
            timestamp_geq: "2025-01-01T00:00:00Z"
            index1_eq: "MISS"
          }
          orderBy: [count_DESC]
          limit: 20
        ) {
          blob1  # Query type (title/isbn/author)
          blob2  # Actual query
          count  # Miss count
        }
      }
    }
  }
}
```

### Wrangler Queues

Check queue metrics:

```bash
npx wrangler queues list
npx wrangler queues consumer list author-warming-queue
```

## Performance Impact

**Expected Results:**
- **Before warming:** 60-70% cache hit rate
- **After warming:** 85-95% cache hit rate
- **Latency improvement:** 200ms → <10ms for popular queries
- **API call reduction:** 30-40% fewer upstream requests

**Cost Analysis:**
- Script runtime: ~30 seconds/day
- Queue processing: 5-10 minutes/day (20 jobs × 30s each)
- Cache storage: +50MB KV (~$0.025/month)
- **Total additional cost:** < $0.10/month

**ROI:** Massive latency improvement for negligible cost.

## Troubleshooting

### No Analytics Data

Check Analytics Engine is writing:

```bash
# Test search endpoint
curl "https://api-worker.jukasdrj.workers.dev/search/title?q=test"

# Check logs
npx wrangler tail api-worker --search "CACHE_ANALYTICS"
```

### Queue Not Processing

Check consumer health:

```bash
# View consumer logs
npx wrangler tail api-worker --search "author-warming-consumer"

# Check queue status
npx wrangler queues consumer list author-warming-queue
```

### Script Fails

Common issues:
- **403 Forbidden:** Check API token permissions
- **GraphQL errors:** Verify account ID and dataset name
- **No candidates:** Analytics period too short or cache already hot

## Future Enhancements

**Phase 2 (D1 Migration):**
- Mirror analytics to D1 for Worker-native queries
- Real-time warming triggers (no daily delay)
- Advanced ML-based prediction

**Phase 3 (Intelligent Warming):**
- Time-based patterns (warm morning bestsellers)
- Geographic patterns (regional author preferences)
- Trend detection (new release spikes)

## Related Documentation

- `author-warming-consumer.js` - Queue consumer implementation
- `wrangler.toml` - Queue configuration
- `docs/plans/2025-10-29-cache-warming-fix.md` - Cache key alignment fix
- Sprint 1-2 optimization results

---

**Status:** ✅ Production ready (Sprint 3-4)
**Last Updated:** January 2025
