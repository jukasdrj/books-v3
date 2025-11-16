# BooksTrack API Monitoring Guide

**Document Version:** 1.0
**Last Updated:** November 16, 2025
**Related Issue:** #93 - Configure monitoring dashboard for API v2.0 rollout
**Production URL:** https://api.oooefam.net

---

## Table of Contents
1. [Quick Start](#quick-start)
2. [Analytics Architecture](#analytics-architecture)
3. [Cloudflare Dashboard](#cloudflare-dashboard)
4. [GraphQL Queries](#graphql-queries)
5. [Key Metrics](#key-metrics)
6. [Alerting Rules](#alerting-rules)
7. [Real-Time Monitoring](#real-time-monitoring)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Accessing the Dashboard

1. **Cloudflare Dashboard (Recommended)**
   - URL: https://dash.cloudflare.com/
   - Navigate: **Workers & Pages** → **api-worker** → **Analytics**
   - View: Request volume, error rates, P50/P95/P99 latency

2. **Wrangler Tail (Real-Time Logs)**
   ```bash
   npx wrangler tail --format pretty
   ```
   - Shows live request/response logs
   - Includes error codes, cache status, processing time
   - Useful for debugging specific issues

3. **Custom Slash Command**
   ```bash
   /logs [optional-filter-pattern]
   ```
   - Stream and analyze production logs
   - Filter by error code, endpoint, or pattern

### Essential Health Checks

**1. Overall System Health**
```bash
curl https://api.oooefam.net/health
```

Expected response:
```json
{
  "status": "ok",
  "worker": "api-worker",
  "version": "1.0.0"
}
```

**2. API v2.0 Compliance Check**
```bash
curl https://api.oooefam.net/v1/search/isbn?isbn=9780439708180
```

Expected format (v2.0 canonical):
```json
{
  "data": {
    "isbn": "9780439708180",
    "title": "Harry Potter and the Sorcerer's Stone",
    ...
  },
  "metadata": {
    "source": "google_books",
    "cached": true,
    "timestamp": "2025-11-16T10:00:00Z"
  }
}
```

⚠️ **WARNING SIGNS:**
- Response has `success` field → Legacy format leak
- Missing `metadata` field → v2.0 compliance broken
- Error response lacks `error` object → Response builder issue

**3. Cache Performance Check**
```bash
# First request (should be MISS)
curl -I "https://api.oooefam.net/v1/search/isbn?isbn=9780439708180"

# Second request (should be HIT)
curl -I "https://api.oooefam.net/v1/search/isbn?isbn=9780439708180"
```

Check headers:
```
X-Cache-Status: HIT
X-Response-Time: 45ms
```

---

## Analytics Architecture

### Analytics Engine Datasets

BooksTrack uses **5 Analytics Engine datasets** for comprehensive monitoring:

| Dataset | Binding | Purpose | Cost |
|---------|---------|---------|------|
| `books_api_performance` | `PERFORMANCE_ANALYTICS` | Request latency, error rates, response formats | Free (10M writes/day) |
| `books_api_cache_metrics` | `CACHE_ANALYTICS` | Cache hit rates, KV performance | Free |
| `books_api_provider_performance` | `ANALYTICS_ENGINE` | External API (Google Books, ISBNdb) latency | Free |
| `bookshelf_ai_performance` | `AI_ANALYTICS` | Gemini AI scan performance, token usage | Free |
| `books_api_sampling_metrics` | `SAMPLING_ANALYTICS` | Sampling behavior tracking | Free |

**Configuration:** `wrangler.toml:196-215`

### Data Points Written

Each request writes a data point to `PERFORMANCE_ANALYTICS`:

```javascript
{
  blobs: [
    endpoint,        // "/v1/search/isbn"
    statusCode,      // "200", "404", "500"
    errorCode,       // "SUCCESS", "NOT_FOUND", "RATE_LIMIT_EXCEEDED"
    anonymizedIP,    // "192.168.1.0" (GDPR-compliant)
    datacenter,      // "SJC" (Cloudflare colo code)
    cacheStatus,     // "HIT", "MISS", "BYPASS"
    responseFormat   // "v2.0", "legacy", "hybrid-malformed"
  ],
  doubles: [
    processingTime   // 125.4 (milliseconds)
  ],
  indexes: [
    endpoint         // For fast filtering by endpoint
  ]
}
```

**Location:** `src/middleware/analytics-tracker.js:315-335`

### Sampling Strategy

To optimize costs, high-volume endpoints use probabilistic sampling:

```javascript
const SAMPLING_RATES = {
  "/v1/search/isbn": 0.1,    // 10% of requests
  "/v1/search/title": 0.1,   // 10% of requests
  "/search/title": 0.1,      // Legacy endpoint - 10%
  "/search/isbn": 0.1,       // Legacy endpoint - 10%
  "/api/enrichment/start": 0.5  // 50% of requests
  // Default: 1.0 (100%) for other endpoints
};
```

**Impact:** 90% cost reduction on search endpoints with minimal accuracy loss for dashboards.

**Location:** `src/middleware/analytics-tracker.js:24-31`

---

## Cloudflare Dashboard

### Overview Tab

**Access:** https://dash.cloudflare.com/ → Workers → api-worker → Analytics

**Key Metrics (Real-Time):**

1. **Requests**
   - Total requests (24h, 7d, 30d)
   - Requests per second
   - Geographic distribution

2. **Errors**
   - 4xx rate (client errors)
   - 5xx rate (server errors)
   - Error trend over time

3. **CPU Time**
   - P50, P95, P99 percentiles
   - Shows actual computation time (not wall-clock time)
   - Useful for identifying CPU-intensive operations

4. **Duration**
   - Total request duration (includes network I/O)
   - P50: <100ms (target)
   - P95: <200ms (target for cached)
   - P95: <500ms (target for uncached)

**Example Screenshot Interpretation:**

```
Requests:  ▂▃▅▇█▇▅▃▂  2.4M (24h)  ✅ Normal traffic pattern
Errors:    ▁▁▁▁▂▁▁▁▁  0.3%        ✅ Below 1% threshold
CPU P95:   ▃▄▅▅▄▃▃▃▂  45ms        ✅ Well below 30s limit
Duration:  ▃▅▆▇▅▄▃▂▁  180ms P95   ✅ Below 500ms target
```

### Invocations Tab

**Filter by:**
- **Endpoint:** `/v1/search/isbn`, `/v1/search/title`, etc.
- **Status Code:** 200, 404, 500
- **Date Range:** Last 1h, 24h, 7d, 30d, custom

**Useful Views:**

1. **Error Rate by Endpoint**
   - Identify which endpoints are failing
   - Example: `/v1/search/advanced` at 5% error rate → Investigate

2. **Latency by Endpoint**
   - Compare cached vs. uncached performance
   - Example: `/v1/search/title` P95: 450ms → Cache warming needed

3. **Request Distribution**
   - Which endpoints are most popular?
   - Example: 70% of traffic to `/v1/search/isbn` → Consider caching optimization

---

## GraphQL Queries

### Using GraphQL API

Cloudflare provides a GraphQL API for custom analytics queries.

**Authentication:**
```bash
export CF_API_TOKEN="your-api-token"
export CF_ACCOUNT_ID="your-account-id"
```

**Endpoint:**
```
https://api.cloudflare.com/client/v4/graphql
```

### Query 1: Error Rate by Endpoint (Last 24 Hours)

```graphql
query ApiErrorRates($accountId: String!, $startTime: Time!, $endTime: Time!) {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      workersInvocationsAdaptive(
        filter: {
          datetime_geq: $startTime
          datetime_leq: $endTime
          scriptName: "api-worker"
        }
        limit: 10000
      ) {
        dimensions {
          scriptName
          status
        }
        sum {
          requests
          errors
        }
        ratio {
          errorRate
        }
      }
    }
  }
}
```

**Variables:**
```json
{
  "accountId": "your-account-id",
  "startTime": "2025-11-16T00:00:00Z",
  "endTime": "2025-11-16T23:59:59Z"
}
```

**Example Response:**
```json
{
  "data": {
    "viewer": {
      "accounts": [
        {
          "workersInvocationsAdaptive": [
            {
              "dimensions": { "scriptName": "api-worker", "status": 200 },
              "sum": { "requests": 1200000, "errors": 0 },
              "ratio": { "errorRate": 0.0 }
            },
            {
              "dimensions": { "scriptName": "api-worker", "status": 404 },
              "sum": { "requests": 3000, "errors": 3000 },
              "ratio": { "errorRate": 1.0 }
            },
            {
              "dimensions": { "scriptName": "api-worker", "status": 500 },
              "sum": { "requests": 120, "errors": 120 },
              "ratio": { "errorRate": 1.0 }
            }
          ]
        }
      ]
    }
  }
}
```

**Calculation:**
```
Total Requests: 1,203,120
Total Errors (4xx + 5xx): 3,120
Error Rate: 3,120 / 1,203,120 = 0.26% ✅
```

### Query 2: P95 Latency by Endpoint

```graphql
query ApiLatencyMetrics($accountId: String!, $startTime: Time!, $endTime: Time!) {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      workersInvocationsAdaptive(
        filter: {
          datetime_geq: $startTime
          datetime_leq: $endTime
          scriptName: "api-worker"
        }
        limit: 10000
      ) {
        dimensions {
          scriptName
        }
        quantiles {
          cpuTimeP50
          cpuTimeP95
          cpuTimeP99
          durationP50
          durationP95
          durationP99
        }
      }
    }
  }
}
```

**Example Response:**
```json
{
  "data": {
    "viewer": {
      "accounts": [
        {
          "workersInvocationsAdaptive": [
            {
              "dimensions": { "scriptName": "api-worker" },
              "quantiles": {
                "cpuTimeP50": 12.3,
                "cpuTimeP95": 45.7,
                "cpuTimeP99": 89.2,
                "durationP50": 98.4,
                "durationP95": 187.6,
                "durationP99": 452.1
              }
            }
          ]
        }
      ]
    }
  }
}
```

**Interpretation:**
- **P50 CPU Time:** 12.3ms (computation time)
- **P95 CPU Time:** 45.7ms (well below 30s limit ✅)
- **P50 Duration:** 98.4ms (includes network I/O)
- **P95 Duration:** 187.6ms (below 500ms target ✅)

### Query 3: Response Format Compliance (v2.0 Rollout)

**Custom Analytics Engine Query:**

```graphql
query ResponseFormatCompliance($accountId: String!, $startTime: Time!, $endTime: Time!) {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      analyticsEngineDatasets(filter: { dataset: "books_api_performance" }) {
        data(
          filter: {
            datetime_geq: $startTime
            datetime_leq: $endTime
            blob6: "v2.0"  # responseFormat field
          }
        ) {
          count
          blob1  # endpoint
          blob6  # responseFormat
        }
      }
    }
  }
}
```

**Purpose:** Track percentage of responses using v2.0 canonical format vs. legacy format.

**Target:** 100% of `/v1/*` endpoints should return v2.0 format within 7 days of rollout.

---

## Key Metrics

### 1. Response Format Compliance

**Definition:** Percentage of API responses using v2.0 canonical format (`{data, metadata}`).

**Target:**
- **v1.0 endpoints** (`/search/*`): 0% (legacy format expected)
- **v2.0 endpoints** (`/v1/*`): 100% (canonical format required)
- **Hybrid responses:** 0% (indicates bug)

**How to Check:**

```bash
# Test v2.0 endpoint
curl https://api.oooefam.net/v1/search/isbn?isbn=9780439708180 | jq 'keys'

# Expected: ["data", "metadata"]
# WARNING: ["success", "data"] → Legacy format leak!
```

**Dashboard Query:**
```sql
SELECT
  blob6 AS responseFormat,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage
FROM books_api_performance
WHERE blob1 LIKE '/v1/%'  -- v2.0 endpoints only
  AND timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY blob6
ORDER BY count DESC;
```

**Expected Result (After v2.0 Rollout):**
```
responseFormat | count  | percentage
---------------|--------|------------
v2.0           | 985423 | 99.8%
non-json       | 1234   | 0.1%  (health checks, OPTIONS)
legacy         | 456    | 0.04% ⚠️ INVESTIGATE!
```

### 2. Error Rate

**Definition:** Percentage of requests returning 4xx or 5xx status codes.

**Targets:**
- **Overall Error Rate:** <1% (normal operations)
- **4xx Rate:** <2% (includes valid NOT_FOUND responses)
- **5xx Rate:** <0.1% (server errors indicate bugs)

**Calculation:**
```
Error Rate = (4xx Count + 5xx Count) / Total Requests
```

**Thresholds:**
- ✅ **Green:** <1%
- ⚠️ **Yellow:** 1-5% (investigate)
- 🚨 **Red:** >5% (consider rollback)

**Common Error Codes:**

| Code | Meaning | Normal Rate | Alert Threshold |
|------|---------|-------------|-----------------|
| 400 | Bad Request (invalid ISBN, missing params) | <1% | >2% |
| 401 | Unauthorized (WebSocket auth failure) | <0.1% | >1% |
| 404 | Not Found (book doesn't exist) | <1% | >3% |
| 429 | Rate Limit Exceeded | <0.5% | >2% |
| 500 | Internal Server Error (bug) | <0.01% | >0.1% 🚨 |
| 502 | Bad Gateway (upstream API failure) | <0.05% | >0.5% |

### 3. Latency (P50, P95, P99)

**Percentile Explanation:**
- **P50 (Median):** 50% of requests faster than this
- **P95:** 95% of requests faster than this (focus metric)
- **P99:** 99% of requests faster than this (outlier detection)

**Targets by Endpoint Type:**

| Endpoint Type | P50 | P95 | P99 | Notes |
|---------------|-----|-----|-----|-------|
| Cached search | <50ms | <100ms | <200ms | KV cache hit |
| Uncached search | <200ms | <500ms | <1000ms | External API call |
| WebSocket upgrade | <100ms | <300ms | <600ms | Durable Object fetch |
| AI scan (Gemini) | <15s | <30s | <60s | Long-running, async |
| Batch enrichment | N/A | N/A | N/A | Async (WebSocket progress) |

**Alert Thresholds:**

- ⚠️ **Warning:** P95 > 500ms (15-minute window)
- 🚨 **Critical:** P95 > 2 seconds (5-minute window) → Consider rollback

**How to Interpret:**

```
P50: 98ms, P95: 187ms, P99: 452ms

✅ Good distribution - most requests fast, few outliers
📊 Cache hit rate likely high (~80%+)
```

```
P50: 450ms, P95: 1800ms, P99: 5000ms

⚠️ Warning - high latency, possible issues:
   - Cache warming needed
   - External API slowdown (Google Books, ISBNdb)
   - Database contention (KV)
```

### 4. Cache Hit Rate

**Definition:** Percentage of requests served from KV cache without external API calls.

**Targets:**
- **ISBN Search:** >90% (ISBNs are immutable)
- **Title Search:** >70% (popular queries cached)
- **Author Search:** >60% (large result sets, less cacheable)

**Calculation:**
```
Cache Hit Rate = (HIT Count) / (HIT Count + MISS Count)
```

**How to Check:**
```bash
npx wrangler tail | grep "X-Cache-Status" | sort | uniq -c
```

Expected output:
```
   8542 X-Cache-Status: HIT
   1234 X-Cache-Status: MISS

Cache Hit Rate: 8542 / (8542 + 1234) = 87% ✅
```

**Troubleshooting Low Hit Rate (<50%):**

1. **Cache Key Format Changed**
   - Recent deployment changed cache key structure
   - Old cache entries invalidated
   - **Fix:** Wait 24 hours for cache warming

2. **Cache Eviction (Storage Quota)**
   - KV namespace at storage limit
   - Oldest entries evicted automatically
   - **Fix:** Increase KV quota or implement LRU cleanup

3. **High Query Diversity**
   - Many unique queries (e.g., random ISBNs)
   - Each query is cache miss initially
   - **Normal behavior** for diverse traffic

### 5. WebSocket Metrics

**Connection Stability:**
- **Target:** <5% disconnection rate
- **Warning:** 5-10% disconnection rate
- **Critical:** >10% disconnection rate

**Message Throughput:**
- **Typical:** 1-5 messages/second per job
- **Peak:** 10-20 messages/second (batch enrichment)

**Job Completion Rate:**
- **Target:** >95% of jobs complete successfully
- **Warning:** 90-95% completion rate
- **Critical:** <90% completion rate → Investigate failures

**How to Monitor:**

```bash
# Real-time WebSocket logs
npx wrangler tail | grep "WebSocket"

# Look for:
# ✅ "WebSocket connection accepted"
# ✅ "Client ready signal received"
# ⚠️ "WebSocket closed: code=1006" (abnormal closure)
# 🚨 "WebSocket authentication failed"
```

**Common Disconnection Codes:**

| Code | Meaning | Severity | Action |
|------|---------|----------|--------|
| 1000 | Normal Closure | ✅ OK | None (job completed) |
| 1001 | Going Away (client navigated) | ✅ OK | None |
| 1006 | Abnormal Closure (no close frame) | ⚠️ Warning | Investigate if frequent |
| 1008 | Policy Violation (invalid message) | 🚨 Error | Check client message format |
| 1011 | Internal Error (server bug) | 🚨 Critical | Rollback if widespread |

---

## Alerting Rules

### Critical Alerts (Immediate Action Required)

**1. High Error Rate**
- **Condition:** Error rate > 10% (5-minute window)
- **Action:** Execute rollback immediately
- **Notification:** PagerDuty alert + Slack #incidents

**2. Extreme Latency**
- **Condition:** P95 > 2 seconds (5-minute window)
- **Action:** Investigate + prepare rollback
- **Notification:** PagerDuty alert + Slack #engineering

**3. WebSocket Instability**
- **Condition:** >20% disconnection rate (10-minute window)
- **Action:** Investigate Durable Object stability
- **Notification:** PagerDuty alert

**4. Complete Service Outage**
- **Condition:** All endpoints returning 5xx
- **Action:** Rollback immediately + escalate
- **Notification:** PagerDuty P1 incident + CEO notification

### Warning Alerts (Investigate Soon)

**1. Elevated Error Rate**
- **Condition:** Error rate 5-10% (1-hour window)
- **Action:** Monitor for 15 minutes, prepare rollback plan
- **Notification:** Slack #engineering

**2. Moderate Latency**
- **Condition:** P95 between 500ms-2s (15-minute window)
- **Action:** Check cache hit rate, external API status
- **Notification:** Slack #engineering

**3. Low Cache Hit Rate**
- **Condition:** <50% cache hit rate (1-hour window)
- **Action:** Investigate cache invalidation, warming needed?
- **Notification:** Slack #engineering (low priority)

### Informational Alerts (Awareness Only)

**1. Traffic Spike**
- **Condition:** Requests > 10x normal (15-minute window)
- **Action:** Monitor error rate, may be legitimate growth
- **Notification:** Slack #analytics

**2. Geographic Anomaly**
- **Condition:** >80% traffic from single region (unusual)
- **Action:** Check for bot traffic or coordinated use
- **Notification:** Slack #security

### Alert Configuration (Example: Cloudflare Notifications)

Navigate to: **Cloudflare Dashboard** → **Notifications** → **Add Notification**

**Error Rate Alert:**
```yaml
Name: "API Error Rate - Critical"
Notification Type: "Workers Script"
Trigger:
  - Metric: Error Rate
  - Condition: Greater Than
  - Value: 10%
  - Duration: 5 minutes
Action:
  - Webhook: https://hooks.slack.com/services/YOUR_WEBHOOK
  - Email: oncall@oooefam.net
```

---

## Real-Time Monitoring

### Wrangler Tail

**Basic Usage:**
```bash
npx wrangler tail --format pretty
```

**Filter by Endpoint:**
```bash
npx wrangler tail | grep "/v1/search/isbn"
```

**Filter by Error Code:**
```bash
npx wrangler tail | grep "ERROR"
```

**Filter by Response Time:**
```bash
npx wrangler tail | grep "X-Response-Time" | awk '$2 > 500'  # >500ms
```

### Custom Logging Patterns

**Performance Logging:**
```bash
npx wrangler tail | grep "X-Response-Time" | \
  sed 's/.*X-Response-Time: \([0-9]*\)ms.*/\1/' | \
  awk '{sum+=$1; count++} END {print "Avg:", sum/count "ms"}'
```

**Cache Hit Rate (Live):**
```bash
npx wrangler tail | grep "X-Cache-Status" | \
  awk '{cache[$2]++} END {for (c in cache) print c, cache[c]}'
```

**Error Breakdown:**
```bash
npx wrangler tail | grep "X-Error-Code" | \
  awk '{errors[$2]++} END {for (e in errors) print e, errors[e]}' | \
  sort -k2 -nr
```

---

## Troubleshooting

### Issue: Dashboard Shows No Data

**Possible Causes:**
1. Analytics Engine not enabled (`wrangler.toml`)
2. No requests in selected time range
3. Cloudflare dashboard caching delay (up to 5 minutes)

**Resolution:**
```bash
# Check wrangler.toml for analytics bindings
grep "analytics_engine_datasets" wrangler.toml

# Send test request
curl https://api.oooefam.net/health

# Wait 5 minutes, refresh dashboard
```

### Issue: GraphQL Query Returns Empty Results

**Possible Causes:**
1. Incorrect `scriptName` (check exact worker name)
2. Time range outside of data retention (90 days max)
3. Wrong account ID

**Resolution:**
```bash
# Verify worker name
npx wrangler whoami
npx wrangler deployments list

# Check account ID
npx wrangler whoami | grep "Account ID"
```

### Issue: Real-Time Logs Not Showing

**Possible Causes:**
1. Wrangler not authenticated
2. Worker not deployed
3. No traffic to worker

**Resolution:**
```bash
# Re-authenticate
npx wrangler login

# Check deployment status
npx wrangler deployments list

# Send test request
curl https://api.oooefam.net/health

# Retry tail
npx wrangler tail --format pretty
```

---

## Related Documentation

- `docs/ROLLBACK_PROCEDURES.md` - Rollback execution guide
- `docs/DEPLOYMENT.md` - Deployment procedures
- `docs/API_CONTRACT.md` - API v2.0 specification
- `.claude/commands/logs.md` - Logs slash command

---

**Document Maintenance:**
Update this guide when:
- New metrics added to Analytics Engine
- Alerting thresholds changed
- GraphQL API schema updated

**Last Reviewed:** November 16, 2025
**Next Review:** February 16, 2026
**Owner:** @jukasdrj
