# Monitoring & Optimization - Phase 4

**Status:** ✅ Implemented (Alert Monitoring)
**A/B Testing:** ❌ Not implemented (skipped)

## Overview

Comprehensive monitoring and alerting system for the hybrid cache architecture. Provides real-time metrics aggregation from Analytics Engine, automated alert detection, and health assessment.

## Components

### 1. Metrics Aggregation Service

**Purpose:** Query Analytics Engine and aggregate cache metrics across all tiers.

**File:** `src/services/metrics-aggregator.js`

**Supported Periods:**
- `15m` - Last 15 minutes (for real-time alerts)
- `1h` - Last hour (default)
- `24h` - Last 24 hours
- `7d` - Last 7 days

**Metrics Calculated:**
```javascript
{
  timestamp: "2025-10-29T10:00:00.000Z",
  period: "1h",
  hitRates: {
    edge: 78.2,      // % of requests served from edge cache
    kv: 16.5,        // % of requests served from KV
    r2_cold: 1.8,    // % of requests rehydrated from R2
    api: 3.5,        // % of requests that missed all caches
    combined: 94.7   // edge + kv hit rate
  },
  latency: {
    edge_hit: { avg: 8.2, p50: 7.5, p95: 12.5, p99: 18.0 },
    kv_hit: { avg: 42.1, p50: 38.0, p95: 65.0, p99: 85.0 },
    r2_rehydrated: { avg: 180.0, p50: 165.0, p95: 250.0, p99: 320.0 },
    api_miss: { avg: 350.0, p50: 310.0, p95: 480.0, p99: 620.0 }
  },
  volume: {
    total_requests: 100000,
    edge_hits: 78200,
    kv_hits: 16500,
    r2_rehydrations: 1800,
    api_misses: 3500
  }
}
```

**Analytics Engine Schema:**
- `index1` - Cache source (`edge_hit`, `kv_hit`, `r2_rehydrated`, `api_miss`)
- `double1` - Latency in milliseconds
- `timestamp` - Request timestamp

### 2. Metrics API Endpoint

**Endpoint:** `GET /metrics`

**Query Parameters:**
- `period` - Time period (`15m`, `1h`, `24h`, `7d`) - Default: `1h`
- `format` - Response format (`json`, `prometheus`) - Default: `json`

**JSON Format:**
```bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?period=1h"
```

**Response:**
```json
{
  "timestamp": "2025-10-29T10:00:00.000Z",
  "period": "1h",
  "hitRates": { ... },
  "latency": { ... },
  "volume": { ... },
  "costs": {
    "kv_reads_estimate": "$0.0008/period",
    "r2_reads": "$0.0001/period",
    "total_estimate": "$0.0009/period"
  },
  "health": {
    "status": "healthy",
    "issues": []
  }
}
```

**Prometheus Format:**
```bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?format=prometheus"
```

**Response:**
```
# HELP cache_hit_rate Cache hit rate by tier
# TYPE cache_hit_rate gauge
cache_hit_rate{tier="edge"} 78.2
cache_hit_rate{tier="kv"} 16.5
cache_hit_rate{tier="combined"} 94.7

# HELP cache_requests_total Total cache requests by tier
# TYPE cache_requests_total counter
cache_requests_total{tier="edge"} 78200
cache_requests_total{tier="kv"} 16500
cache_requests_total{tier="api_miss"} 3500
```

**Caching:** Metrics responses are cached in KV for 5 minutes to reduce Analytics Engine query load.

### 3. Alert Monitor

**Purpose:** Detect performance degradation and log alerts automatically.

**File:** `src/services/alert-monitor.js`

**Thresholds:**

| Severity | Metric | Threshold | Description |
|----------|--------|-----------|-------------|
| **Critical** | Miss Rate | > 15% | Combined hit rate < 85% |
| **Critical** | P99 Latency | > 500ms | Requests taking > 500ms at P99 |
| **Warning** | Miss Rate | > 10% | Combined hit rate < 90% |
| **Warning** | Edge Hit Rate | < 75% | Too many requests falling through to KV |
| **Warning** | P95 Latency | > 100ms | Elevated latency at P95 |

**Deduplication:** Alerts are suppressed for 4 hours after being logged to prevent spam.

**Alert Structure:**
```javascript
{
  severity: 'critical',
  type: 'miss_rate',
  value: 18.0,
  threshold: 15.0,
  message: 'Cache miss rate critically high: 18.0%'
}
```

### 4. Scheduled Alert Monitor

**Schedule:** Every 15 minutes (`*/15 * * * *`)

**File:** `src/handlers/scheduled-alerts.js`

**Workflow:**
1. Aggregate metrics for last 15 minutes
2. Check thresholds for violations
3. Check deduplication cache (skip if alerted within 4h)
4. Log alert details to console
5. Mark alert as sent to prevent duplicates

**Console Output Example:**
```
[Alert Monitor] 🚨 NEW ALERTS DETECTED:
  [CRITICAL] Cache miss rate critically high: 18.0%
    Current: 18.0 | Threshold: 15.0
  [WARNING] Edge hit rate below target: 72.5%
    Current: 72.5 | Threshold: 75.0
[Alert Monitor] Recent metrics (15min):
  Hit Rate: 82.0% (Edge: 72.5%, KV: 9.5%)
  Volume: 1250 requests
[Alert Monitor] Alert logged and marked as sent
```

**Email Alerts:** Currently disabled. To enable, implement `sendAlertEmail()` and uncomment email logic in `scheduled-alerts.js`.

## Analytics Engine Queries

**Hit Rate Trend (7 days):**
```sql
SELECT
  DATE_TRUNC('day', timestamp) as day,
  COUNT(CASE WHEN index1 = 'edge_hit' THEN 1 END) as edge_hits,
  COUNT(CASE WHEN index1 = 'kv_hit' THEN 1 END) as kv_hits,
  COUNT(*) as total
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '7' DAY
GROUP BY day
ORDER BY day DESC;
```

**Latency Distribution by Cache Tier:**
```sql
SELECT
  index1 as cache_source,
  AVG(double1) as avg_latency,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY double1) as p50,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY double1) as p95,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY double1) as p99
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY index1;
```

**Request Volume by Hour:**
```sql
SELECT
  DATE_TRUNC('hour', timestamp) as hour,
  index1 as cache_source,
  COUNT(*) as requests
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '24' HOUR
GROUP BY hour, index1
ORDER BY hour DESC;
```

## Cost Analysis

**KV Reads:** $0.50 per million reads
- 16,500 KV hits/hour = 396K/day
- Daily cost: ~$0.20

**R2 Reads:** $0.36 per million reads (Class A operations)
- 1,800 R2 rehydrations/hour = 43K/day
- Daily cost: ~$0.015

**Analytics Engine:** Free tier (10M events/month)
- Current usage: ~2.4M events/day (well within limits)
- Cost: $0.00

**Total Operational Cost:** ~$0.22/day (~$6.50/month)

## Health Assessment

**Status Levels:**
- `healthy` - All metrics within target thresholds
- `degraded` - One or more warnings triggered
- `critical` - Critical threshold breached

**Health Checks:**
1. **Combined Hit Rate** - Target: ≥ 90% (Warning: < 90%)
2. **Edge Hit Rate** - Target: ≥ 75% (Warning: < 75%)
3. **P99 Latency** - Target: ≤ 200ms (Critical: > 500ms)
4. **Miss Rate** - Target: ≤ 10% (Critical: > 15%)

## Troubleshooting

### No metrics returned from `/metrics` endpoint

**Possible Causes:**
1. Analytics Engine dataset not configured
2. No cache analytics data written yet
3. Query syntax error

**Diagnosis:**
```bash
# Check Analytics Engine binding
npx wrangler kv:namespace list

# Check recent logs
npx wrangler tail api-worker --format pretty

# Test with different period
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?period=24h"
```

### Alerts not triggering

**Possible Causes:**
1. Cron trigger not running
2. Metrics below alert thresholds (healthy!)
3. Deduplication suppressing alerts

**Diagnosis:**
```bash
# Check scheduled triggers
npx wrangler deployments list

# Monitor next alert check
npx wrangler tail api-worker --format pretty

# Check deduplication cache
npx wrangler kv:key list --binding=CACHE --prefix="alert:"
```

### High miss rate

**Common Causes:**
1. Edge cache purge/restart (temporary)
2. Traffic spike to new content
3. KV eviction due to storage limits
4. R2 archival too aggressive

**Mitigation:**
1. Check recent deployments (may have purged cache)
2. Increase KV TTLs for stable content
3. Review R2 archival criteria (currently 30 days)
4. Consider cache warming for popular content

### High costs

**Optimization Steps:**
1. Review `/metrics?period=24h` for cost breakdown
2. Check KV hit rate (target: > 15%)
3. Verify R2 archival is working (should reduce KV reads)
4. Consider increasing edge cache TTLs

**Cost Reduction Strategies:**
- Increase edge cache TTLs (reduce KV reads)
- Archive older data to R2 more aggressively
- Implement cache warming for high-traffic keys
- Use conditional requests (304 Not Modified)

## Deployment

**1. Verify Configuration:**
```bash
cd cloudflare-workers/api-worker

# Check Analytics Engine bindings in wrangler.toml
grep -A 3 "analytics_engine_datasets" wrangler.toml

# Check cron triggers
grep -A 3 "triggers" wrangler.toml
```

**2. Run Tests:**
```bash
npm test metrics-aggregator.test.js
npm test alert-monitor.test.js
```

**3. Deploy:**
```bash
npx wrangler deploy
```

**4. Verify Deployment:**
```bash
# Test metrics endpoint
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?period=1h"

# Monitor scheduled alerts (wait ~15 minutes)
npx wrangler tail api-worker --format pretty
```

## Monitoring Best Practices

### 1. Set up external monitoring

Use a service like UptimeRobot or Pingdom to monitor `/metrics` endpoint availability:
- URL: `https://api-worker.YOUR-DOMAIN.workers.dev/metrics`
- Interval: 5 minutes
- Alert: If status ≠ 200 or response time > 2s

### 2. Create a dashboard

Use Grafana with Prometheus scraping:
```yaml
scrape_configs:
  - job_name: 'bookstrack-cache'
    scrape_interval: 5m
    static_configs:
      - targets: ['api-worker.YOUR-DOMAIN.workers.dev']
    metrics_path: '/metrics'
    params:
      format: ['prometheus']
```

### 3. Review metrics regularly

**Daily:** Check combined hit rate trend
**Weekly:** Review cost estimates and optimization opportunities
**Monthly:** Analyze long-term patterns (7d periods)

### 4. Tune alert thresholds

Based on your traffic patterns, adjust thresholds in `src/services/alert-monitor.js`:
```javascript
const ALERT_THRESHOLDS = {
  critical: {
    miss_rate: 15,    // Increase if too noisy
    p99_latency: 500  // Decrease for stricter SLA
  },
  warning: {
    edge_hit_rate: 75 // Tune based on actual edge hit rate
  }
};
```

## Next Steps

**Phase 4 Enhancements (Future):**

1. **Email Alerts via MailChannels**
   - Implement `sendAlertEmail()` in `scheduled-alerts.js`
   - Add `ALERT_EMAIL` environment variable
   - HTML email templates with metrics + troubleshooting tips

2. **Slack/Discord Webhooks**
   - Real-time alerts to team channels
   - Rich formatting with charts
   - Actionable buttons (acknowledge, view details)

3. **A/B Testing Framework** (Not Implemented)
   - Test different TTL configurations
   - Measure hit rate improvements
   - Auto-promote winning treatments

4. **ML-Based Optimization**
   - Predict optimal TTLs per cache key
   - Anomaly detection for unusual patterns
   - Auto-scaling based on traffic predictions

5. **Multi-Region Analytics**
   - Track hit rates by PoP (Point of Presence)
   - Identify regional performance issues
   - Optimize cache distribution

---

**Implemented:** October 29, 2025
**Version:** 1.0.0
**Status:** Production Ready (without email alerts)
