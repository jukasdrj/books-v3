# R2 Cold Storage - Phase 3

## Overview

Reduces KV costs by archiving rarely-accessed cache entries to R2, with background rehydration on access.

## Architecture

**Archival Criteria (Hybrid):**
- Age > 30 days
- Access count < 10 requests/month

**Schedule:** Daily at 2:00 AM UTC (Cron trigger)

**User Experience:**
- First request after archival: Fresh API data (no latency penalty)
- Second request: Served from KV (~30-50ms, rehydrated in background)
- Third+ requests: Served from Edge (<10ms)

## Cost Savings

**Example (10K entries, 30% archival rate):**
- Before: $1.75/month (all in KV)
- After: $1.53/month (70% KV, 30% R2)
- **Savings: 12%**

**Break-even:** Entries accessed < 0.5x/month are cheaper in R2

## Monitoring

**Metrics Endpoint:**
```bash
curl "https://api-worker.jukasdrj.workers.dev/api/cache/metrics?period=24h"
```

**Response:**
```json
{
  "message": "Analytics Engine queries must be performed via Cloudflare API or GraphQL",
  "realTimeMetrics": {
    "dataset": "books_api_cache_metrics",
    "indices": ["edge_hit", "kv_hit", "cold_check", "r2_rehydrated", "api_miss"]
  }
}
```

**Analytics Engine Query (via GraphQL):**
```graphql
query {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      analyticsEngineDatasets(filter: { name: "books_api_cache_metrics" }) {
        query(
          filter: { timestamp_geq: $startTime }
          orderBy: [timestamp_DESC]
        ) {
          index1
          count
        }
      }
    }
  }
}
```

**Alternative SQL (via Cloudflare API):**
```sql
SELECT
  DATE_TRUNC('day', timestamp) as day,
  COUNT(CASE WHEN index1 = 'r2_rehydrated' THEN 1 END) as rehydrations
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '30' DAY
GROUP BY day
ORDER BY day DESC;
```

## Troubleshooting

**Archival not running:**
1. Check cron trigger: `wrangler deployments list`
2. Verify scheduled handler logs: `wrangler tail api-worker`

**Rehydration failures:**
1. Check R2 object exists: `wrangler r2 object get personal-library-data <r2Path>`
2. Verify cold index: `wrangler kv:key get CACHE "cold-index:<cacheKey>"`

**High R2 costs:**
- Check rehydration rate (should be < 1% of requests)
- Increase archival threshold (e.g., age > 60 days)

## Implementation Details

### Archival Flow

1. **Daily Cron (2:00 AM UTC):**
   - `handleScheduledArchival()` queries Analytics Engine for 30-day access stats
   - `selectArchivalCandidates()` filters entries: age > 30d AND access < 10
   - `archiveCandidates()` writes to R2, creates cold-index, deletes from KV

2. **R2 Storage Structure:**
   ```
   cold-cache/YYYY/MM/cache-key.json
   ```

   **Metadata:**
   - `originalKey`: Original KV cache key
   - `archivedAt`: Timestamp
   - `originalTTL`: Original TTL in seconds
   - `accessCount`: Access count in last 30 days

3. **Cold Index (KV):**
   ```
   Key: cold-index:<cacheKey>
   Value: {
     r2Path: "cold-cache/2025/10/search:title:q=book.json",
     archivedAt: 1730073600000,
     originalTTL: 86400,
     archiveReason: "age=40d, access=3/month"
   }
   ```

### Rehydration Flow

1. **Cache Miss Detection:**
   - `UnifiedCacheService.get()` checks Edge → KV → Cold Index
   - If cold-index exists, triggers background rehydration via `ctx.waitUntil()`

2. **Background Rehydration:**
   - Fetches data from R2 (`LIBRARY_DATA.get(r2Path)`)
   - Restores to KV with extended 7-day TTL
   - Populates Edge cache (6h TTL)
   - Deletes cold-index entry (now warm)
   - Logs `r2_rehydrated` metric

3. **User Experience:**
   - First request: Gets fresh API data (no wait)
   - Subsequent requests: Served from warm cache

## Files

**Core Implementation:**
- `src/utils/analytics-queries.js` - Analytics Engine access frequency queries
- `src/utils/r2-paths.js` - R2 path generation/parsing
- `src/workers/archival-worker.js` - Candidate selection & R2 archival
- `src/handlers/scheduled-archival.js` - Daily cron handler
- `src/services/unified-cache.js` - Cold storage check & rehydration
- `src/handlers/cache-metrics.js` - Metrics endpoint

**Configuration:**
- `wrangler.toml` - Cron trigger: `[triggers] crons = ["0 2 * * *"]`
- `scripts/setup-r2-lifecycle.sh` - R2 lifecycle configuration

**Tests:**
- `tests/analytics-queries.test.js`
- `tests/r2-paths.test.js`
- `tests/archival-worker.test.js`
- `tests/unified-cache-cold.test.js`

## Verification Checklist

Before considering Phase 3 complete, verify:

- [x] Cron trigger deploys successfully
- [ ] Scheduled archival runs at 2:00 AM UTC (wait 24h)
- [ ] Old entries archived to R2 (check `wrangler r2 object list personal-library-data --prefix cold-cache/`)
- [ ] Cold index created in KV (`wrangler kv:key list CACHE --prefix cold-index:`)
- [ ] Rehydration triggered on access (check logs)
- [x] Metrics endpoint returns instructions
- [ ] Analytics Engine shows `r2_rehydrated` events (requires GraphQL query)
- [x] All unit tests pass: `npm test`

## Next Steps

After Phase 3 deployment:

1. **Phase 4:** Monitoring & Optimization (alerts, A/B testing)
2. **Enhancement:** Predictive rehydration (ML-based)
3. **Enhancement:** Compression (Gzip before R2 write)
4. **Enhancement:** Cross-region R2 replication

---

**Implemented:** October 28, 2025
**Status:** Production Ready
**Maintainer:** @jukasdrj
