# Cache Metrics Queries

## Overview

The hybrid cache system logs metrics to Cloudflare Analytics Engine via the `CACHE_ANALYTICS` binding. Metrics include:

- **Event types:** `edge_hit`, `kv_hit`, `api_miss`
- **Data:** Cache key, latency (ms), timestamp
- **Purpose:** Track hit rates, latency distribution, cache effectiveness

## Querying Metrics

Use `wrangler` CLI to query Analytics Engine:

```bash
wrangler query-analytics \
  --dataset CACHE_ANALYTICS \
  --query "<SQL_QUERY>"
```

## Common Queries

### Overall Hit Rate (Last Hour)

```sql
SELECT
  index1 as cache_source,
  COUNT(*) as requests,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as percentage
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY index1
ORDER BY requests DESC;
```

**Example output:**
```
cache_source | requests | percentage
-------------|----------|------------
edge_hit     | 1250     | 78.13%
kv_hit       | 280      | 17.50%
api_miss     | 70       | 4.37%
```

**Target:** 95% combined hit rate (edge + KV)

### Latency by Tier (Last Hour)

```sql
SELECT
  index1 as cache_source,
  AVG(double1) as avg_latency_ms,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY double1) as p50_latency_ms,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY double1) as p95_latency_ms,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY double1) as p99_latency_ms
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY index1
ORDER BY avg_latency_ms ASC;
```

**Expected:**
- Edge: P50 < 10ms
- KV: P50 30-50ms
- API: P50 300-500ms

### Cache Effectiveness Over Time (24h)

```sql
SELECT
  DATE_TRUNC('hour', timestamp) as hour,
  index1 as cache_source,
  COUNT(*) as requests
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '24' HOUR
GROUP BY hour, index1
ORDER BY hour DESC, requests DESC;
```

### Top Cache Keys by Hit Rate

```sql
SELECT
  blob2 as cache_key,
  COUNT(*) as total_hits,
  COUNT(CASE WHEN index1 = 'edge_hit' THEN 1 END) as edge_hits,
  COUNT(CASE WHEN index1 = 'kv_hit' THEN 1 END) as kv_hits
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY cache_key
ORDER BY total_hits DESC
LIMIT 20;
```

### Cache Miss Rate (Alert Threshold)

```sql
SELECT
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM CACHE_ANALYTICS WHERE timestamp > NOW() - INTERVAL '1' HOUR) as miss_rate_percentage
FROM CACHE_ANALYTICS
WHERE index1 = 'api_miss'
  AND timestamp > NOW() - INTERVAL '1' HOUR;
```

**Alert if:** Miss rate > 10% (indicates cache not warming properly)

## Monitoring Dashboard

### Key Metrics to Track

1. **Hit Rate:** Target 95% (edge + KV combined)
2. **P50 Latency:** Target < 10ms overall
3. **P95 Latency:** Target < 50ms overall
4. **Miss Rate:** Alert if > 10%
5. **Edge Hit Rate:** Target 80% (most popular content)
6. **KV Hit Rate:** Target 15% (warm cache)

### Daily Health Check

```bash
# Run this daily to verify cache health
wrangler query-analytics \
  --dataset CACHE_ANALYTICS \
  --query "
    SELECT
      COUNT(CASE WHEN index1 = 'edge_hit' THEN 1 END) * 100.0 / COUNT(*) as edge_rate,
      COUNT(CASE WHEN index1 = 'kv_hit' THEN 1 END) * 100.0 / COUNT(*) as kv_rate,
      COUNT(CASE WHEN index1 = 'api_miss' THEN 1 END) * 100.0 / COUNT(*) as miss_rate,
      AVG(double1) as avg_latency_ms
    FROM CACHE_ANALYTICS
    WHERE timestamp > NOW() - INTERVAL '24' HOUR
  "
```

**Healthy output:**
```
edge_rate | kv_rate | miss_rate | avg_latency_ms
----------|---------|-----------|----------------
78-82%    | 15-17%  | 3-7%      | 8-12ms
```

## Cost Optimization

Analytics Engine is **free for up to 10M events/month**. At current request volume (~500K requests/month), we're well within limits.

**Note:** Metrics are batched and may have 1-5 minute delay before appearing in queries.
