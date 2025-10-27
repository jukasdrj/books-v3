# Cache Health Monitoring System Design

**Date:** October 27, 2025
**Status:** Design Approved
**Approach:** Lightweight Instrumentation (Passive Monitoring)

## Problem Statement

Currently, BooksTrack has no visibility into cache health for trending books and search results. We need observability across:
- Cache hit rates (are requests being served from cache?)
- Image availability (do trending books have high-quality cover images?)
- Response times (cache vs. origin API latency)
- Data freshness (when was cached data last updated?)

This affects both development debugging and production monitoring.

## Design Goals

1. **Zero breaking changes** - Add observability without modifying API contracts
2. **Multi-layer visibility** - Developer logs, in-app debug UI, backend analytics
3. **Production-ready** - Leverage Cloudflare paid plan features (Analytics Engine, Logpush)
4. **Actionable metrics** - Track meaningful KPIs with clear success criteria

## Architecture Overview

**Approach:** Lightweight instrumentation via response headers + telemetry

### Component 1: Backend Cache Metadata Headers

Cloudflare Worker emits cache health data via HTTP headers on all search/trending responses.

**New Response Headers:**
```http
X-Cache-Status: HIT | MISS | STALE | BYPASS
X-Cache-Age: 3600              # Seconds since cache write
X-Cache-TTL: 18000             # Remaining seconds before expiry
X-Image-Quality: high          # high | medium | low | missing
X-Data-Completeness: 85        # % of books with ISBN + cover
```

**Implementation Location:** `cloudflare-workers/api-worker/src/utils/cache.js`

**Header Calculation Logic:**
- `X-Cache-Status`: Based on KV lookup result (hit/miss/stale)
- `X-Cache-Age`: `Date.now() - cachedEntry.timestamp`
- `X-Cache-TTL`: `cachedEntry.expiresAt - Date.now()`
- `X-Image-Quality`: Analyze cover URL size parameter (L=low, M=medium, none=high, null=missing)
- `X-Data-Completeness`: `(booksWithISBN_AND_cover / totalBooks) * 100`

### Component 2: iOS Client Instrumentation

iOS captures and displays cache metrics from backend headers.

**New Model:** `CacheHealthMetrics` (Observable)
```swift
@Observable
class CacheHealthMetrics {
    var cacheHitRate: Double = 0.0              // Rolling average
    var averageResponseTime: TimeInterval = 0   // Milliseconds
    var imageAvailability: Double = 0.0         // % with valid covers
    var dataCompleteness: Double = 0.0          // % with ISBN+cover
    var lastCacheAge: TimeInterval = 0          // Seconds since refresh
}
```

**Integration Point:** `BookSearchAPIService.search()`
```swift
// After receiving HTTPURLResponse
let cacheStatus = response.allHeaderFields["X-Cache-Status"] as? String
let cacheAge = Int(response.allHeaderFields["X-Cache-Age"] as? String ?? "0")
let imageQuality = response.allHeaderFields["X-Image-Quality"] as? String
// ... update CacheHealthMetrics singleton
```

**Debug Logging (DEBUG builds only):**
```
📊 Cache: HIT | Age: 3600s | Images: 92% | Completeness: 85% | Response: 45ms
```

**Debug UI:** Settings → Advanced → Cache Health
- Real-time metrics display
- Color-coded status indicators (green=healthy, yellow=warning, red=degraded)
- "Refresh Trending" button to force cache validation
- Last updated timestamp

### Component 3: Cloudflare Analytics Engine Integration

Production telemetry using Workers Analytics Engine (paid plan feature).

**Analytics Data Points:**
```javascript
await env.ANALYTICS_ENGINE.writeDataPoint({
  blobs: [
    "trending_books",          // Query type
    cacheStatus,               // HIT/MISS
    provider                   // openlibrary/isbndb/cache
  ],
  doubles: [
    responseTimeMs,            // Request duration
    imageQualityScore,         // 0-100
    dataCompletenessPercent    // 0-100
  ],
  indexes: [requestTimestamp]  // For time-series queries
});
```

**Queryable Metrics:**
- Hourly cache hit rates
- P50/P95/P99 response latencies
- Image availability trends over time
- Trending books freshness (time since last update)

**Logpush Configuration:**
Stream cache health logs to R2 for long-term analysis:
```bash
wrangler logpush create --destination r2://cache-health-logs --filter "event.request.url contains 'trending'"
```

**GraphQL Dashboard Queries:**
```graphql
query CacheHealthDashboard($accountId: String!) {
  viewer {
    accounts(filter: {accountTag: $accountId}) {
      workersAnalyticsEngine(limit: 1000) {
        avg(metric: "responseTimeMs")
        sum(metric: "cacheHits")
        percentile(metric: "responseTimeMs", percentile: 95)
      }
    }
  }
}
```

**Cost Analysis:**
- Analytics Engine free tier: 10M writes/month
- Estimated usage: ~50K writes/month (1.5K requests/day)
- Well within free limits ✅

## Data Flow

```
1. iOS app launches → SearchModel.loadTrendingBooks()
2. BookSearchAPIService.search(query: "bestseller 2024")
3. Cloudflare Worker checks KV cache
   ├─ HIT: Return cached data + set X-Cache-Status: HIT, X-Cache-Age: 3600
   └─ MISS: Fetch from OpenLibrary + cache + set X-Cache-Status: MISS
4. Worker writes telemetry → Analytics Engine
5. iOS parses response headers → updates CacheHealthMetrics
6. Debug build logs: "📊 Cache: HIT | Age: 3600s | Images: 92%"
7. Developer views: Settings → Cache Health (real-time dashboard)
8. Backend engineer queries: Cloudflare GraphQL API (historical trends)
```

## Testing & Validation

### Backend Tests

**Local Development:**
```bash
# Terminal 1: Start local worker
npx wrangler dev --local

# Terminal 2: Test cache headers
curl -I https://localhost:8787/search/title?q=bestseller%202024

# Expected headers on first request (MISS):
X-Cache-Status: MISS
X-Cache-Age: 0
X-Cache-TTL: 21600

# Expected headers on second request (HIT):
X-Cache-Status: HIT
X-Cache-Age: 2
X-Cache-TTL: 21598
```

**Production Validation:**
```bash
curl -I https://api-worker.jukasdrj.workers.dev/search/title?q=bestseller%202024

# Verify all 5 headers present
npx wrangler tail --format pretty | grep "Cache"
```

### iOS Tests

**Debug Logging:**
1. Run app in Xcode with `-D DEBUG` flag
2. Navigate to Search tab (triggers trending books load)
3. Check console for: `📊 Cache: ...` logs
4. Verify metrics match backend headers (use Proxyman to inspect)

**Debug UI:**
1. Navigate: Settings → Advanced → Cache Health
2. Verify all metrics display (not 0.0/null)
3. Tap "Refresh Trending"
4. Confirm cache status changes: HIT → MISS → HIT
5. Verify "Last Updated" timestamp updates

**Metrics Accuracy:**
1. Use Charles Proxy/Proxyman to inspect HTTP headers
2. Compare iOS-displayed values with actual header values
3. Verify calculation correctness (e.g., hit rate % matches logs)

## Success Criteria

| Metric | Target | Validation Method |
|--------|--------|-------------------|
| Cache hit rate | >80% after first load | Analytics Engine dashboard |
| Image availability | >90% for trending books | X-Image-Quality header analysis |
| Response time (cached) | <100ms | P95 latency in Analytics Engine |
| Response time (origin) | <800ms | P95 latency for MISS requests |
| Debug logs visible | 100% | Xcode console check |
| Analytics data flowing | Yes | Cloudflare dashboard shows data points |
| Header presence | 100% | All 5 headers on every response |

## Implementation Phases

### Phase 1: Backend Headers (Est. 2 hours)
- [ ] Add header generation in `cache.js` after KV lookup
- [ ] Implement image quality detection (parse cover URL)
- [ ] Calculate data completeness percentage
- [ ] Test locally with curl
- [ ] Deploy to production
- [ ] Verify headers with production curl test

### Phase 2: iOS Instrumentation (Est. 3 hours)
- [ ] Create `CacheHealthMetrics` model
- [ ] Update `BookSearchAPIService` to parse headers
- [ ] Add debug logging (`#if DEBUG`)
- [ ] Test in Simulator (verify console logs)
- [ ] Test on physical device

### Phase 3: Debug UI (Est. 2 hours)
- [ ] Create `CacheHealthView` (Settings → Advanced)
- [ ] Display real-time metrics with color coding
- [ ] Add "Refresh Trending" button
- [ ] Wire up to SearchModel
- [ ] Test user flow

### Phase 4: Analytics Engine (Est. 1 hour)
- [ ] Add `ANALYTICS_ENGINE` binding in `wrangler.toml`
- [ ] Emit data points in cache.js
- [ ] Configure Logpush to R2 (optional)
- [ ] Verify data in Cloudflare dashboard
- [ ] Create sample GraphQL queries

## Monitoring & Maintenance

**Daily Checks:**
- Review Cloudflare dashboard for cache hit rate trends
- Check error logs for header parsing failures

**Weekly Reviews:**
- Analyze P95 response times (target: cache <100ms, origin <800ms)
- Review image availability trends (target: >90%)
- Check for stale cache issues (age > 6 hours for trending)

**Alerts (Optional Future Enhancement):**
- Cache hit rate drops below 60%
- P95 response time exceeds 1000ms
- Image availability drops below 75%

## Open Questions & Future Enhancements

**Answered:**
- ✅ Where should metrics be visible? (All layers: logs, in-app, backend)
- ✅ Which metrics matter most? (Hit rate, image quality, latency, freshness)
- ✅ What's the monitoring approach? (Passive instrumentation via headers)

**Future Enhancements (Not in Scope):**
- Historical trend graphs in iOS app (requires local storage)
- Push notifications for cache degradation (overkill for single-developer app)
- Automated cache warming on deploy (nice-to-have, adds complexity)
- A/B testing different cache TTLs (premature optimization)

## Related Documentation

- `docs/workflows/search-workflow.md` - Search flow diagram
- `cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md` - Backend architecture
- `CLAUDE.md` - Backend caching rules (6h title search, 7-day ISBN)

## References

- [Cloudflare Workers Analytics Engine](https://developers.cloudflare.com/analytics/analytics-engine/)
- [Cloudflare Logpush](https://developers.cloudflare.com/logs/logpush/)
- [HTTP Cache Headers Best Practices](https://web.dev/http-cache/)
