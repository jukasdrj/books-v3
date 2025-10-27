# Cache Health Monitoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add lightweight cache observability across backend (Cloudflare) and iOS client via response headers, debug logging, and Analytics Engine telemetry.

**Architecture:** Passive instrumentation approach - backend emits cache metadata via HTTP headers (`X-Cache-Status`, `X-Cache-Age`, etc.), iOS captures and displays metrics, Cloudflare Analytics Engine tracks telemetry.

**Tech Stack:** Cloudflare Workers (JavaScript), Swift 6.2 (iOS), Workers Analytics Engine, SwiftUI

---

## Phase 1: Backend Cache Headers (Est. 2 hours)

### Task 1: Add Cache Metadata Headers to Worker

**Files:**
- Modify: `cloudflare-workers/api-worker/src/utils/cache.js`
- Reference: `cloudflare-workers/api-worker/src/handlers/searchHandler.js` (to see how cache.js is used)

**Step 1: Read current cache.js implementation**

Read: `cloudflare-workers/api-worker/src/utils/cache.js`

Understand:
- How `getCachedResponse()` works
- How `setCachedResponse()` works
- Where KV lookups happen

**Step 2: Add header generation function**

Add this function to `cache.js`:

```javascript
/**
 * Generates cache health headers for response
 * @param {object} cacheResult - { hit: boolean, data: object, age: number, ttl: number }
 * @param {array} items - Search result items for quality analysis
 * @returns {object} Headers object
 */
function generateCacheHeaders(cacheResult, items = []) {
  const headers = {};

  // Cache status
  headers['X-Cache-Status'] = cacheResult.hit ? 'HIT' : 'MISS';

  // Cache age (seconds since write)
  headers['X-Cache-Age'] = cacheResult.age || 0;

  // Cache TTL (remaining seconds before expiry)
  headers['X-Cache-TTL'] = cacheResult.ttl || 0;

  // Image quality analysis
  const imageQuality = analyzeImageQuality(items);
  headers['X-Image-Quality'] = imageQuality;

  // Data completeness (% with ISBN + cover)
  const completeness = calculateDataCompleteness(items);
  headers['X-Data-Completeness'] = completeness;

  return headers;
}

/**
 * Analyzes cover image quality from URLs
 * @param {array} items - Search result items
 * @returns {string} 'high' | 'medium' | 'low' | 'missing'
 */
function analyzeImageQuality(items) {
  if (!items || items.length === 0) return 'missing';

  let highCount = 0;
  let mediumCount = 0;
  let lowCount = 0;
  let missingCount = 0;

  for (const item of items) {
    const coverURL = item.cover_url || item.coverURL || '';

    if (!coverURL) {
      missingCount++;
    } else if (coverURL.includes('-L.jpg') || coverURL.includes('size=L')) {
      lowCount++;
    } else if (coverURL.includes('-M.jpg') || coverURL.includes('size=M')) {
      mediumCount++;
    } else {
      highCount++; // No size param = original/high quality
    }
  }

  // Return dominant quality level
  const total = items.length;
  if (highCount / total > 0.5) return 'high';
  if (mediumCount / total > 0.3) return 'medium';
  if (missingCount / total > 0.5) return 'missing';
  return 'low';
}

/**
 * Calculates data completeness percentage
 * @param {array} items - Search result items
 * @returns {number} Percentage (0-100) of items with ISBN + cover
 */
function calculateDataCompleteness(items) {
  if (!items || items.length === 0) return 0;

  let completeCount = 0;

  for (const item of items) {
    const hasISBN = item.isbn || item.isbn13 || item.isbn10;
    const hasCover = item.cover_url || item.coverURL;

    if (hasISBN && hasCover) {
      completeCount++;
    }
  }

  return Math.round((completeCount / items.length) * 100);
}

module.exports = {
  getCachedResponse,
  setCachedResponse,
  generateCacheHeaders, // Export new function
  analyzeImageQuality,
  calculateDataCompleteness
};
```

**Step 3: Test header generation locally**

Run local worker:
```bash
cd cloudflare-workers/api-worker
npx wrangler dev --local
```

In another terminal, test:
```bash
curl -I http://localhost:8787/search/title?q=test
```

Expected: Should see `X-Cache-Status: MISS` on first request

**Step 4: Integrate headers into search handler**

Modify: `cloudflare-workers/api-worker/src/handlers/searchHandler.js`

Find where response is returned (around line 50-80), change from:
```javascript
return new Response(JSON.stringify(responseData), {
  headers: {
    'Content-Type': 'application/json',
    'X-Provider': provider
  }
});
```

To:
```javascript
const { generateCacheHeaders } = require('../utils/cache');

// ... existing cache lookup code ...

const cacheHeaders = generateCacheHeaders(
  { hit: cacheHit, age: cacheAge, ttl: cacheTTL },
  responseData.items
);

return new Response(JSON.stringify(responseData), {
  headers: {
    'Content-Type': 'application/json',
    'X-Provider': provider,
    ...cacheHeaders
  }
});
```

**Step 5: Test headers with real request**

```bash
# First request (should be MISS)
curl -I http://localhost:8787/search/title?q=bestseller%202024

# Expected headers:
# X-Cache-Status: MISS
# X-Cache-Age: 0
# X-Cache-TTL: 21600
# X-Image-Quality: high|medium|low|missing
# X-Data-Completeness: 0-100

# Second request (should be HIT)
curl -I http://localhost:8787/search/title?q=bestseller%202024

# Expected:
# X-Cache-Status: HIT
# X-Cache-Age: 2 (or similar low number)
```

**Step 6: Commit backend headers**

```bash
git add cloudflare-workers/api-worker/src/utils/cache.js
git add cloudflare-workers/api-worker/src/handlers/searchHandler.js
git commit -m "feat(backend): add cache health metadata headers

- Add X-Cache-Status, X-Cache-Age, X-Cache-TTL headers
- Add X-Image-Quality analysis (high/medium/low/missing)
- Add X-Data-Completeness percentage (ISBN + cover)
- Implement analyzeImageQuality() and calculateDataCompleteness()

Headers emitted on all search/trending requests for observability."
```

---

## Phase 2: iOS Client Instrumentation (Est. 3 hours)

### Task 2: Create CacheHealthMetrics Model

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/CacheHealthMetrics.swift`

**Step 1: Create CacheHealthMetrics model**

```swift
import Foundation

/// Observable model tracking cache health metrics from backend headers
@Observable
@MainActor
public final class CacheHealthMetrics {
    // Rolling metrics
    public private(set) var cacheHitRate: Double = 0.0              // 0.0 - 1.0
    public private(set) var averageResponseTime: TimeInterval = 0   // Milliseconds
    public private(set) var imageAvailability: Double = 0.0         // 0.0 - 1.0
    public private(set) var dataCompleteness: Double = 0.0          // 0.0 - 1.0
    public private(set) var lastCacheAge: TimeInterval = 0          // Seconds

    // Internal tracking for rolling averages
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var responseTimes: [TimeInterval] = []
    private let maxResponseSamples = 20  // Keep last 20 requests

    /// Singleton instance
    public static let shared = CacheHealthMetrics()

    private init() {}

    /// Update metrics from HTTP response headers
    /// - Parameters:
    ///   - headers: HTTPURLResponse.allHeaderFields dictionary
    ///   - responseTime: Request duration in milliseconds
    public func update(from headers: [AnyHashable: Any], responseTime: TimeInterval) {
        // Cache status
        if let cacheStatus = headers["X-Cache-Status"] as? String {
            if cacheStatus == "HIT" {
                cacheHits += 1
            } else if cacheStatus == "MISS" {
                cacheMisses += 1
            }

            let totalRequests = cacheHits + cacheMisses
            cacheHitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0
        }

        // Cache age
        if let ageString = headers["X-Cache-Age"] as? String,
           let age = TimeInterval(ageString) {
            lastCacheAge = age
        }

        // Image quality → availability (simplified mapping)
        if let imageQuality = headers["X-Image-Quality"] as? String {
            switch imageQuality {
            case "high": imageAvailability = 1.0
            case "medium": imageAvailability = 0.75
            case "low": imageAvailability = 0.5
            case "missing": imageAvailability = 0.0
            default: break
            }
        }

        // Data completeness
        if let completenessString = headers["X-Data-Completeness"] as? String,
           let completeness = Double(completenessString) {
            dataCompleteness = completeness / 100.0 // Convert percentage to 0-1
        }

        // Response time (rolling average)
        responseTimes.append(responseTime)
        if responseTimes.count > maxResponseSamples {
            responseTimes.removeFirst()
        }
        averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    /// Reset all metrics (useful for testing)
    public func reset() {
        cacheHitRate = 0.0
        averageResponseTime = 0
        imageAvailability = 0.0
        dataCompleteness = 0.0
        lastCacheAge = 0
        cacheHits = 0
        cacheMisses = 0
        responseTimes.removeAll()
    }

    /// Debug description
    public var debugDescription: String {
        """
        📊 Cache Health Metrics:
        - Hit Rate: \(Int(cacheHitRate * 100))%
        - Avg Response: \(Int(averageResponseTime))ms
        - Image Availability: \(Int(imageAvailability * 100))%
        - Data Completeness: \(Int(dataCompleteness * 100))%
        - Last Cache Age: \(Int(lastCacheAge))s
        """
    }
}
```

**Step 2: Commit CacheHealthMetrics model**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/CacheHealthMetrics.swift
git commit -m "feat(ios): add CacheHealthMetrics observable model

- Track cache hit rate, response times, image availability
- Parse backend X-Cache-* headers
- Rolling averages for meaningful metrics
- Singleton pattern for app-wide access"
```

### Task 3: Integrate Metrics into BookSearchAPIService

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`

**Step 1: Add metrics tracking to search() method**

Find the `search()` method (around line 20-124), add metrics tracking after response:

```swift
// After line 51 (after URLSession.data call)
let requestStartTime = CFAbsoluteTimeGetCurrent()
let (data, response): (Data, URLResponse)
do {
    (data, response) = try await urlSession.data(from: url)
} catch {
    throw SearchError.networkError(error)
}
let requestEndTime = CFAbsoluteTimeGetCurrent()
let responseTimeMs = (requestEndTime - requestStartTime) * 1000

// After line 55 (after HTTPURLResponse check)
guard let httpResponse = response as? HTTPURLResponse else {
    throw SearchError.invalidResponse
}

// NEW: Update cache metrics
await MainActor.run {
    CacheHealthMetrics.shared.update(
        from: httpResponse.allHeaderFields,
        responseTime: responseTimeMs
    )
}

#if DEBUG
// Debug logging
let cacheStatus = httpResponse.allHeaderFields["X-Cache-Status"] as? String ?? "UNKNOWN"
let cacheAge = httpResponse.allHeaderFields["X-Cache-Age"] as? String ?? "0"
let imageQuality = httpResponse.allHeaderFields["X-Image-Quality"] as? String ?? "?"
let completeness = httpResponse.allHeaderFields["X-Data-Completeness"] as? String ?? "0"
print("📊 Cache: \(cacheStatus) | Age: \(cacheAge)s | Images: \(imageQuality) | Complete: \(completeness)% | Response: \(Int(responseTimeMs))ms")
#endif
```

**Step 2: Build and verify compilation**

```bash
cd BooksTrackerPackage
swift build
```

Expected: Clean build with no errors

**Step 3: Commit metrics integration**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "feat(ios): integrate cache metrics into search API

- Track response time for each request
- Parse and update CacheHealthMetrics from headers
- Add DEBUG logging for cache status
- Format: Cache: HIT | Age: 3600s | Images: high | Complete: 92%"
```

---

## Phase 3: Debug UI (Est. 2 hours)

### Task 4: Create Cache Health Debug View

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView/CacheHealthView.swift`

**Step 1: Create CacheHealthView**

```swift
import SwiftUI

@available(iOS 26.0, *)
struct CacheHealthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CacheHealthMetrics.self) private var metrics
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Cache Performance") {
                    MetricRow(
                        title: "Cache Hit Rate",
                        value: "\(Int(metrics.cacheHitRate * 100))%",
                        status: metrics.cacheHitRate > 0.8 ? .healthy : metrics.cacheHitRate > 0.5 ? .warning : .degraded
                    )

                    MetricRow(
                        title: "Avg Response Time",
                        value: "\(Int(metrics.averageResponseTime))ms",
                        status: metrics.averageResponseTime < 100 ? .healthy : metrics.averageResponseTime < 500 ? .warning : .degraded
                    )

                    MetricRow(
                        title: "Last Cache Age",
                        value: formatAge(metrics.lastCacheAge),
                        status: metrics.lastCacheAge < 3600 ? .healthy : metrics.lastCacheAge < 7200 ? .warning : .degraded
                    )
                }

                Section("Data Quality") {
                    MetricRow(
                        title: "Image Availability",
                        value: "\(Int(metrics.imageAvailability * 100))%",
                        status: metrics.imageAvailability > 0.9 ? .healthy : metrics.imageAvailability > 0.7 ? .warning : .degraded
                    )

                    MetricRow(
                        title: "Data Completeness",
                        value: "\(Int(metrics.dataCompleteness * 100))%",
                        status: metrics.dataCompleteness > 0.85 ? .healthy : metrics.dataCompleteness > 0.7 ? .warning : .degraded
                    )
                }

                Section {
                    Button {
                        refreshTrendingBooks()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Trending Books")
                        }
                    }
                    .disabled(isRefreshing)

                    Button(role: .destructive) {
                        CacheHealthMetrics.shared.reset()
                    } label: {
                        Text("Reset Metrics")
                    }
                }
            }
            .navigationTitle("Cache Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }

    private func refreshTrendingBooks() {
        isRefreshing = true

        Task {
            // Trigger trending books refresh via SearchModel
            // This will cause a cache validation
            let searchModel = SearchModel()
            await searchModel.loadTrendingBooks()

            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

enum HealthStatus {
    case healthy
    case warning
    case degraded

    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .degraded: return .red
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let status: HealthStatus

    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.body)

            Spacer()

            Text(value)
                .font(.body.bold())
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    CacheHealthView()
        .environment(CacheHealthMetrics.shared)
}
```

**Step 2: Add navigation to SettingsView**

Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift`

Add in the "Advanced" section:

```swift
Section("Advanced") {
    NavigationLink {
        CacheHealthView()
    } label: {
        Label("Cache Health", systemImage: "chart.xyaxis.line")
    }

    // ... existing advanced settings ...
}
```

**Step 3: Add metrics to environment**

Modify: `BooksTracker/ContentView.swift` (main app)

Add to environment:

```swift
.environment(CacheHealthMetrics.shared)
```

**Step 4: Build and test in Simulator**

```bash
# Launch app in Simulator
/sim
```

Navigate: Settings → Advanced → Cache Health

Expected: See metrics dashboard with color-coded indicators

**Step 5: Commit debug UI**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView/CacheHealthView.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift
git add BooksTracker/ContentView.swift
git commit -m "feat(ios): add cache health debug UI

- Create CacheHealthView with real-time metrics
- Color-coded status indicators (green/yellow/red)
- Refresh Trending button to force cache validation
- Reset Metrics button for testing
- Accessible via Settings → Advanced → Cache Health"
```

---

## Phase 4: Analytics Engine Integration (Est. 1 hour)

### Task 5: Add Analytics Engine Binding

**Files:**
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Add ANALYTICS_ENGINE binding**

Add to `wrangler.toml`:

```toml
[[analytics_engine_datasets]]
binding = "ANALYTICS_ENGINE"
```

**Step 2: Emit telemetry data points**

Modify: `cloudflare-workers/api-worker/src/handlers/searchHandler.js`

After generating response (before return statement):

```javascript
// Emit analytics telemetry
if (env.ANALYTICS_ENGINE) {
  try {
    await env.ANALYTICS_ENGINE.writeDataPoint({
      blobs: [
        "trending_books",        // Query type
        cacheStatus,             // HIT/MISS
        provider                 // openlibrary/isbndb
      ],
      doubles: [
        responseTimeMs,          // Request duration
        parseFloat(cacheHeaders['X-Data-Completeness'] || 0),  // Data quality
        items.length             // Result count
      ],
      indexes: [Date.now()]      // Timestamp for time-series
    });
  } catch (error) {
    console.error('Analytics write failed:', error);
    // Non-blocking - don't throw
  }
}
```

**Step 3: Test locally (Analytics Engine not available in local mode)**

```bash
cd cloudflare-workers/api-worker
npx wrangler dev --local
```

Note: Analytics Engine only works in production, but code should not error locally.

**Step 4: Deploy to production**

```bash
npm run deploy
```

**Step 5: Verify Analytics Engine data**

1. Go to Cloudflare dashboard → Workers & Pages → api-worker
2. Click "Analytics Engine" tab
3. Verify data points appearing (may take 5-10 minutes)

**Step 6: Commit Analytics integration**

```bash
git add cloudflare-workers/api-worker/wrangler.toml
git add cloudflare-workers/api-worker/src/handlers/searchHandler.js
git commit -m "feat(backend): add Analytics Engine telemetry

- Track cache hits/misses, response times, data quality
- Emit data points on every search request
- Non-blocking (errors don't fail requests)
- Queryable via Cloudflare GraphQL API"
```

---

## Verification & Testing

### Task 6: End-to-End Verification

**Step 1: Test backend headers locally**

```bash
cd cloudflare-workers/api-worker
npx wrangler dev --local

# In another terminal:
curl -I http://localhost:8787/search/title?q=bestseller%202024

# Verify all 5 headers present:
# X-Cache-Status, X-Cache-Age, X-Cache-TTL, X-Image-Quality, X-Data-Completeness
```

**Step 2: Test iOS metrics in Simulator**

```bash
# Launch app
/sim
```

1. Navigate to Search tab (triggers trending books load)
2. Check Xcode console for `📊 Cache:` logs
3. Navigate: Settings → Advanced → Cache Health
4. Verify metrics populated (not all 0.0)
5. Tap "Refresh Trending"
6. Verify cache status changes: HIT → MISS → HIT

**Step 3: Test on physical device**

```bash
# Deploy to connected iPhone/iPad
/device-deploy
```

Repeat same steps as Simulator test.

**Step 4: Verify production backend**

```bash
curl -I https://api-worker.jukasdrj.workers.dev/search/title?q=bestseller%202024

# Check headers
npx wrangler tail --format pretty | grep Cache
```

**Step 5: Check Analytics Engine (after 10 minutes)**

Go to Cloudflare dashboard → api-worker → Analytics Engine

Verify data points visible.

**Step 6: Final commit**

```bash
git add docs/plans/2025-10-27-cache-health-monitoring-implementation.md
git commit -m "docs: complete cache health monitoring implementation

All phases completed:
✅ Phase 1: Backend cache headers (5 new headers)
✅ Phase 2: iOS CacheHealthMetrics + instrumentation
✅ Phase 3: Debug UI in Settings → Advanced
✅ Phase 4: Analytics Engine telemetry
✅ End-to-end verification

Success criteria met:
- Cache hit rate >80% ✅
- Image availability >90% ✅
- Response time <100ms (cached) ✅
- Debug logs visible ✅
- Analytics Engine data flowing ✅"
```

---

## Success Criteria Checklist

- [ ] Backend emits all 5 cache headers on every response
- [ ] iOS parses headers and updates CacheHealthMetrics
- [ ] Debug logs visible in Xcode console (`📊 Cache:...`)
- [ ] Cache Health UI accessible via Settings → Advanced
- [ ] Metrics display with color-coded status (green/yellow/red)
- [ ] Refresh Trending button triggers cache validation
- [ ] Analytics Engine receiving data points (Cloudflare dashboard)
- [ ] Cache hit rate >80% after first load
- [ ] Image availability >90% for trending books
- [ ] Response time <100ms for cached queries

---

## Rollback Plan

If issues arise after deployment:

1. **Backend headers causing errors:**
   ```bash
   git revert <commit-hash>
   npm run deploy
   ```

2. **iOS crashes from metrics parsing:**
   - Wrap header parsing in try-catch
   - Default to 0.0 for all metrics on error

3. **Analytics Engine quota exceeded:**
   - Add conditional: `if (Math.random() < 0.1)` to sample 10% of requests
   - Or disable entirely: Comment out `writeDataPoint()` call

---

## Related Documentation

- Design doc: `docs/plans/2025-10-27-cache-health-monitoring-design.md`
- Backend architecture: `cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md`
- Search workflow: `docs/workflows/search-workflow.md`
- Cloudflare Analytics Engine: https://developers.cloudflare.com/analytics/analytics-engine/
