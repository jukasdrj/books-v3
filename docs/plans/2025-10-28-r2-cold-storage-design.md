# R2 Cold Storage Design - Phase 3

**Date:** 2025-10-28
**Status:** Design Approved
**Prerequisites:** Phase 1 (Foundation), Phase 2 (Warming)

## Overview

Long-tail cold storage tier using R2 to archive rarely-accessed cache entries, reducing KV costs while maintaining fast access for hot data via background rehydration.

## Goals

1. **Cost reduction:** Move cold data from KV ($0.50/GB/month) to R2 ($0.015/GB/month)
2. **No latency impact:** Users never wait for R2 reads (background rehydration)
3. **Smart archival:** Hybrid strategy (age + access frequency)
4. **Automatic recovery:** Rehydrate to KV on access

## Architecture

```
Scheduled Archival (Hybrid: TTL + Access) → R2 Storage → Background Rehydration on Access
```

### Components

#### 1. Archival Worker

**Schedule:** Cron daily at 2:00 AM UTC

**Algorithm:**
```javascript
async function archiveColdData(env, ctx) {
  // 1. Query Analytics Engine for access stats (last 30 days)
  const accessStats = await queryAccessFrequency(env, 30);

  // 2. Scan KV entries with metadata
  const keys = await env.CACHE.list();

  const candidates = [];
  for (const key of keys.keys) {
    const metadata = await env.CACHE.getWithMetadata(key.name);
    const age = Date.now() - metadata.metadata.cachedAt;
    const accessCount = accessStats[key.name] || 0;

    // Hybrid archival criteria
    if (age > 30 * 24 * 60 * 60 * 1000 && accessCount < 10) {
      candidates.push({
        key: key.name,
        data: metadata.value,
        age: age,
        accessCount: accessCount
      });
    }
  }

  // 3. Archive to R2
  for (const candidate of candidates) {
    const r2Path = generateR2Path(candidate.key);

    // Write to R2
    await env.LIBRARY_DATA.put(r2Path, JSON.stringify(candidate.data), {
      customMetadata: {
        originalKey: candidate.key,
        archivedAt: Date.now().toString(),
        originalTTL: '86400',  // 24h
        accessCount: candidate.accessCount.toString()
      }
    });

    // Add to index (KV, for fast lookups)
    await env.CACHE.put(`cold-index:${candidate.key}`, JSON.stringify({
      r2Path: r2Path,
      archivedAt: Date.now(),
      originalTTL: 86400
    }));

    // Delete from KV
    await env.CACHE.delete(candidate.key);
  }

  // 4. Log metrics
  await logArchivalMetrics(env, {
    archived_count: candidates.length,
    space_saved_kb: candidates.reduce((sum, c) => sum + c.data.length, 0) / 1024,
    cost_reduction: candidates.length * 0.00005  // Rough estimate
  });
}
```

**R2 Path Structure:**
```
cold-cache/
  2025/
    10/
      search:title:q=obscure-book.json
      search:isbn:isbn=9780123456789.json
    11/
      search:title:q=another-old-book.json
  2026/
    01/
      ...
```

**Benefits:**
- Date-based organization enables bulk deletion (e.g., delete all 2024 data)
- Helps with R2 lifecycle policies
- Easy to audit/debug (grep by year/month)

#### 2. Cold Storage Index

**Purpose:** Fast lookup to check if data is archived (without querying R2 list)

**KV Namespace:** Same as `CACHE`, prefixed keys

**Entry Format:**
```json
{
  "key": "cold-index:search:title:q=obscure-book",
  "value": {
    "r2Path": "cold-cache/2025/10/search:title:q=obscure-book.json",
    "archivedAt": 1730160000000,
    "originalTTL": 86400,
    "archiveReason": "age=45d, access=3/month"
  }
}
```

**TTL:** None (permanent index, small footprint ~1KB/entry)

#### 3. Background Rehydration

**Integration Point:** `UnifiedCacheService.get()`

**Modified Flow:**
```javascript
// In UnifiedCacheService.get()
async get(cacheKey, endpoint, options = {}) {
  const startTime = Date.now();

  // Tier 1: Edge Cache
  const edgeResult = await this.edgeCache.get(cacheKey);
  if (edgeResult) {
    this.logMetrics('edge_hit', cacheKey, Date.now() - startTime);
    return edgeResult;
  }

  // Tier 2: KV Cache
  const kvResult = await this.kvCache.get(cacheKey, endpoint);
  if (kvResult) {
    this.ctx.waitUntil(
      this.edgeCache.set(cacheKey, kvResult.data, 6 * 60 * 60)
    );
    this.logMetrics('kv_hit', cacheKey, Date.now() - startTime);
    return kvResult;
  }

  // NEW: Tier 2.5: Check Cold Storage Index
  const coldIndex = await this.env.CACHE.get(`cold-index:${cacheKey}`, 'json');
  if (coldIndex) {
    // Return null immediately (cache miss to user)
    this.logMetrics('cold_check', cacheKey, Date.now() - startTime);

    // Background rehydration (non-blocking)
    this.ctx.waitUntil(
      this.rehydrateFromR2(cacheKey, coldIndex, endpoint)
    );

    return null;  // User gets fresh data from API
  }

  // Tier 3: External APIs
  this.logMetrics('api_miss', cacheKey, Date.now() - startTime);
  return null;
}

async rehydrateFromR2(cacheKey, coldIndex, endpoint) {
  try {
    // 1. Fetch from R2
    const r2Object = await this.env.LIBRARY_DATA.get(coldIndex.r2Path);
    if (!r2Object) {
      console.error(`R2 object not found: ${coldIndex.r2Path}`);
      return;
    }

    const data = await r2Object.json();

    // 2. Restore to KV with extended TTL (7 days)
    await this.kvCache.set(cacheKey, data, endpoint, { ttl: 7 * 24 * 60 * 60 });

    // 3. Populate Edge cache
    await this.edgeCache.set(cacheKey, data, 6 * 60 * 60);

    // 4. Remove from cold index (now warm)
    await this.env.CACHE.delete(`cold-index:${cacheKey}`);

    // 5. Log rehydration
    this.logMetrics('r2_rehydrated', cacheKey, 0);
  } catch (error) {
    console.error(`Rehydration failed for ${cacheKey}:`, error);
  }
}
```

**User Experience:**
- **First request after archival:** User gets fresh API data (no latency penalty)
- **Second request:** Served from KV (30-50ms, rehydrated in background)
- **Third+ requests:** Served from Edge (<10ms)

#### 4. R2 Lifecycle Management

**Automatic Deletion:**
```toml
# wrangler.toml
[[r2_buckets]]
binding = "LIBRARY_DATA"
bucket_name = "personal-library-data"

# R2 Lifecycle Rule (configured via dashboard or API)
# Delete objects older than 1 year
```

**Manual Purge Script:**
```bash
# Delete all 2024 archives (after 1 year)
wrangler r2 object bulk-delete \
  --bucket personal-library-data \
  --prefix cold-cache/2024/
```

## Archival Criteria (Hybrid Strategy)

| Criterion | Threshold | Logic |
|-----------|-----------|-------|
| Age | > 30 days | Cached more than 1 month ago |
| Access frequency | < 10 requests/month | Rarely accessed |
| Combined logic | `age > 30d AND access < 10/month` | Both conditions must be true |

**Example Scenarios:**

| Age | Access/Month | Archive? | Reason |
|-----|--------------|----------|--------|
| 45 days | 3 | ✅ Yes | Old and rarely accessed |
| 45 days | 50 | ❌ No | Old but frequently accessed |
| 10 days | 2 | ❌ No | New (regardless of access) |
| 100 days | 15 | ❌ No | Old but accessed weekly |

## Cost Analysis

### Current Costs (All in KV)

- 10,000 cached entries × 50KB avg = 500MB
- KV storage: 500MB × $0.50/GB = **$0.25/month**
- KV reads: 100K/day × 30 × $0.50/million = **$1.50/month**
- **Total: $1.75/month**

### With R2 Cold Storage

Assume 30% of entries qualify for archival (old + rarely accessed):

- 7,000 entries in KV (hot) × 50KB = 350MB
  - KV storage: $0.175/month
  - KV reads: 90K/day × 30 × $0.50/million = $1.35/month

- 3,000 entries in R2 (cold) × 50KB = 150MB
  - R2 storage: 150MB × $0.015/GB = $0.002/month
  - R2 reads (rehydration): 100/day × 30 × $0.36/million = $0.001/month

**Total: $1.53/month (12% reduction)**

### Break-Even Analysis

- KV entry cost: $0.00005/month storage + $0.0005/read
- R2 entry cost: $0.0000015/month storage + $0.00036/read (Class A)

**Break-even:** Entries accessed < 0.5x/month are cheaper in R2

**ROI:** Significant savings at scale (10K+ entries, 30%+ archival rate)

## Performance Impact

| Scenario | Before (KV only) | After (with R2) | Delta |
|----------|------------------|-----------------|-------|
| Hot data (Edge hit) | <10ms | <10ms | 0ms |
| Warm data (KV hit) | 30-50ms | 30-50ms | 0ms |
| Cold data (1st access) | 30-50ms (KV) | 300-500ms (API) | +250-450ms |
| Cold data (2nd access) | N/A | 30-50ms (rehydrated) | N/A |

**Trade-off:** First access to archived data is slower, but user gets fresh data. Subsequent access is fast.

## Monitoring

**Metrics to track:**

1. **Archival rate:** Entries archived per day
2. **Storage distribution:** % in Edge vs KV vs R2
3. **Rehydration rate:** Archived entries accessed per day
4. **Cost savings:** Estimated $/month reduction

**Dashboard Query:**
```sql
SELECT
  DATE_TRUNC('day', timestamp) as day,
  COUNT(CASE WHEN index1 = 'r2_rehydrated' THEN 1 END) as rehydrations,
  COUNT(CASE WHEN index1 = 'cold_check' THEN 1 END) as cold_checks
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '30' DAY
GROUP BY day
ORDER BY day DESC;
```

## Error Handling

| Error | Resolution |
|-------|------------|
| R2 write failure | Retry 3x, log error, skip entry (leave in KV) |
| R2 read failure (rehydration) | Log error, user gets API data (same as miss) |
| Index corruption | Rebuild index from R2 list (one-time job) |
| R2 storage full | Alert, pause archival, investigate |

## Future Enhancements

1. **Predictive rehydration:** Warm cache before user requests (ML-based)
2. **Tiered R2 storage:** Infrequent Access class for even older data
3. **Compression:** Gzip entries before R2 write (50-70% size reduction)
4. **Cross-region replication:** R2 multi-region for disaster recovery

## Dependencies

- Phase 1: UnifiedCacheService, KVCacheService, EdgeCacheService
- R2 bucket: `LIBRARY_DATA` (existing)
- Analytics Engine: `CACHE_ANALYTICS` (for access stats)
- KV namespace: `CACHE` (for cold index)
