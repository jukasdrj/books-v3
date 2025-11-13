# ISBNdb Cover Harvest System

**Version:** 1.0.0 (Multi-Edition)
**Last Updated:** November 13, 2025
**Status:** ✅ Production Active

## Overview

Automated system for pre-caching high-quality book cover images from ISBNdb API. Maximizes API quota (5000 req/day) through intelligent multi-edition discovery and Analytics Engine tracking.

## Architecture

### Data Flow
```
┌─────────────────────────────────────────────────────────────┐
│ DATA SOURCES (Priority Ordering)                             │
├─────────────────────────────────────────────────────────────┤
│ 1. Curated ISBNs (478)                                       │
│    └─> Multi-Edition Discovery (350 Works × 2-3 editions)   │
│        └─> 700-1050 ISBNs                                    │
│                                                              │
│ 2. Analytics Engine (0-300)                                  │
│    └─> Popular search ISBNs from real users                 │
│        └─> 24h aggregation delay                            │
│                                                              │
│ 3. User Library (0) [Future]                                 │
│    └─> CloudKit → D1 sync                                   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ HARVEST ORCHESTRATION                                         │
├─────────────────────────────────────────────────────────────┤
│ • Scheduled Cron: Daily at 3 AM UTC                          │
│ • Rate Limiting: 10 req/sec (ISBNdb)                         │
│ • Deduplication: Skip already-cached covers                  │
│ • Quota Cap: 5000 ISBNs/day maximum                          │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ PROCESSING PIPELINE                                           │
├─────────────────────────────────────────────────────────────┤
│ ISBNdb API → Download Image → WebP Compression (85%)        │
│                                      ↓                        │
│                         R2 Storage (covers/{isbn13})         │
│                                      ↓                        │
│                    KV Index (cover:{isbn} → metadata)        │
│                                      ↓                        │
│                         Analytics Engine Logging             │
└─────────────────────────────────────────────────────────────┘
```

### Storage Architecture

**R2 Bucket: `bookstrack-covers`**
- **Key Format:** `covers/{isbn13}` (e.g., `covers/9780385529985`)
- **Content-Type:** `image/webp` or `image/jpeg`
- **TTL:** 1 year (365 days)
- **Metadata:**
  - `isbn`: ISBN-13
  - `title`: Book title
  - `authors`: Comma-separated author names
  - `originalSize`: Pre-compression size (bytes)
  - `compressedSize`: Post-compression size (bytes)
  - `compressionSavings`: Percentage saved
  - `harvestedAt`: ISO timestamp
  - `source`: `isbndb-harvest`

**KV Namespace: `KV_CACHE`**
- **Key Format:** `cover:{isbn}` (e.g., `cover:9780385529985`)
- **Value:** JSON metadata
  ```json
  {
    "r2Key": "covers/9780385529985",
    "isbn": "9780385529985",
    "title": "Ready Player One",
    "authors": ["Ernest Cline"],
    "harvestedAt": "2025-11-13T03:00:00Z",
    "originalSize": 156780,
    "compressedSize": 62892,
    "savings": 60
  }
  ```
- **TTL:** 1 year (365 days)
- **Purpose:** Fast existence checks (avoid re-harvesting)

## Multi-Edition Discovery

### Edition Scoring Algorithm (100-Point System)

**Image Quality (40 points max)**
- `extraLarge` image: 40 pts
- `large` image: 30 pts
- `medium` image: 20 pts
- `thumbnail` image: 10 pts

**Edition Type (30 points max)**
- Illustrated Edition: 30 pts
- First Edition: 25 pts
- Collector's Edition: 25 pts
- Anniversary Edition: 20 pts

**Binding (15 points max)**
- Hardcover: 15 pts
- Paperback: 10 pts

**Recency (10 points max)**
- ≤5 years old: 10 pts
- ≤15 years old: 5 pts

**Completeness (5 points max)**
- Has page count: 5 pts

### Edition Discovery Flow

```javascript
// 1. Load seed ISBN (from curated list)
const seedISBN = "9780385529985";

// 2. Query Google Books for Work metadata
const metadata = await getBookMetadata(seedISBN);
// Returns: { title: "Ready Player One", authors: ["Ernest Cline"] }

// 3. Discover all editions of this Work
const editions = await discoverEditions(metadata);
// Returns: [
//   { isbn: "9780307887436", score: 40, ... }, // Kindle Edition
//   { isbn: "9780345537621", score: 35, ... }, // Movie Tie-in
//   { isbn: "9780804190138", score: 30, ... }  // Paperback
// ]

// 4. Select top 3 editions
const topEditions = editions.slice(0, 3);
```

### Google Books API Integration

**Endpoint:** `https://www.googleapis.com/books/v1/volumes`

**Query Strategy:**
- **Discovery Query:** `intitle:"Exact Title" inauthor:"Author Name"`
- **Max Results:** 40 (Google Books limit)
- **Print Type:** `books` (exclude magazines)
- **Order By:** `relevance`

**Rate Limiting:**
- 10 req/sec (Google Books free tier)
- Implemented via `RateLimiter` class

**Edition Discovery Steps:**
1. Query: `isbn:{seedISBN}` → Get Work metadata
2. Query: `intitle:"Title" inauthor:"Author"` → Get all editions
3. Score each edition (100-point algorithm)
4. Return top 3 ISBNs

## Analytics Engine Integration

### ISBN Logging Schema

**Dataset:** `books_api_provider_performance`

**Write Format:**
```javascript
await env.CACHE_ANALYTICS.writeDataPoint({
  blobs: [
    isbn,            // blob1: '9780385529985'
    'isbn_search'    // blob2: constant marker
  ],
  doubles: [
    responseTime,    // double1: milliseconds
    dataCompleteness,// double2: 0-100
    itemCount        // double3: results count
  ],
  indexes: [
    'google-books-isbn',        // index1: provider type
    cacheHit ? 'HIT' : 'MISS'   // index0: cache status
  ]
});
```

### Analytics Harvest Query

**SQL Query:**
```sql
SELECT blob1 as isbn, COUNT(*) as search_count
FROM books_api_provider_performance
WHERE timestamp > NOW() - INTERVAL '7' DAY
  AND index1 = 'google-books-isbn'
  AND blob2 = 'isbn_search'
GROUP BY isbn
ORDER BY search_count DESC
LIMIT 500
```

**Aggregation Delay:** ~24 hours
**Data Retention:** 7 days (cost optimization)

### Analytics Integration Timeline

**Day 0 (Deployment):**
- ISBN logging active for all search endpoints
- Analytics query returns 422 (no data yet)

**Day 1 (24h later):**
- Analytics aggregation complete
- Harvest query returns popular ISBNs
- Multi-edition + Analytics ISBNs = 1000 total

## Harvest Schedule

### Cron Trigger
```
0 3 * * *  # Daily at 3 AM UTC (11 PM EST / 8 PM PST)
```

### Execution Flow

**Phase 1: ISBN Collection (2-3 minutes)**
```
1. Load curated ISBNs (478) from GitHub CSV
2. Select 350 Works for multi-edition discovery
3. Query Google Books API for each Work (350 requests)
4. Discover 2-3 editions per Work → 700-1050 ISBNs
5. Query Analytics Engine for popular ISBNs (0-500)
6. Deduplicate and cap at 1000 total
```

**Phase 2: Cover Harvest (4-5 minutes)**
```
1. Check KV for already-cached covers → Skip
2. Query ISBNdb API for book metadata + cover URL
3. Download cover image
4. Compress to WebP (85% quality, ~60% size reduction)
5. Upload to R2 (covers/{isbn13})
6. Create KV index entry (cover:{isbn})
7. Log to Analytics Engine
```

**Total Duration:** ~6-8 minutes for 1000 ISBNs

### Success Metrics

**Target Outcomes:**
- ✅ 700-1050 ISBNs harvested/day (multi-edition)
- ✅ 0-300 ISBNs from Analytics (after 24h)
- ✅ 20-30% API quota utilization (1000-1500 / 5000 daily cap)
- ✅ ~60% compression savings (WebP)
- ✅ 75-90% cache hit rate (goal)

**Current Performance (Nov 13, 2025):**
- 768 ISBNs processed
- 72 new covers (9.4% success rate)
- 447 skipped (already cached)
- 249 no cover available (ISBNdb gap)
- 2.92 MB total storage

## API Endpoints

### Public Endpoints

**Harvest Dashboard (HTML)**
```
GET /admin/harvest-dashboard
```
Returns: Beautiful Cloudflare Workers showcase dashboard with real-time stats

**Test Multi-Edition Discovery**
```
GET /api/test-multi-edition?count=5
```
Returns: JSON with edition discovery results for testing

### Admin Endpoints (Require Auth)

**Manual Harvest Trigger**
```
POST /api/harvest-covers
Headers:
  X-Harvest-Secret: {HARVEST_SECRET}
```
Returns: JSON with harvest stats

**Cancel Running Harvest** (Future)
```
POST /api/harvest-covers/cancel
Headers:
  X-Harvest-Secret: {HARVEST_SECRET}
```

## Dashboard Showcase

### Live Dashboard
**URL:** https://api-worker.jukasdrj.workers.dev/admin/harvest-dashboard

### Features
- 📊 Real-time stats (total covers, storage, API quota, hit rate)
- 🎨 Cloudflare brand design (orange/blue gradient)
- 📈 Source breakdown (ISBNdb, Google Books, OpenLibrary)
- 🔄 Multi-edition strategy status
- ⚡ Auto-refresh on page load
- 📱 Mobile-responsive design
- 🌙 Dark theme with glass morphism

### Design Highlights
- **Cloudflare Orange:** `#f48120`
- **Cloudflare Blue:** `#0051c3`
- **Gradient backgrounds** with backdrop blur
- **Card hover effects** with transform + shadow
- **Progress bars** with animated fills
- **Live indicator** with pulse animation
- **5-minute cache** for performance

## Configuration

### Environment Variables

```toml
# ISBNdb API
ISBNDB_API_KEY = "secret:ISBNDB_API_KEY"

# R2 Buckets
[[r2_buckets]]
binding = "BOOK_COVERS"
bucket_name = "bookstrack-covers"

# KV Namespaces
[[kv_namespaces]]
binding = "KV_CACHE"
id = "b9cade63b6db48fd80c109a013f38fdb"

# Analytics Engine
[[analytics_engine_datasets]]
binding = "CACHE_ANALYTICS"
dataset = "books_api_cache_metrics"

[[analytics_engine_datasets]]
binding = "PROVIDER_ANALYTICS"
dataset = "books_api_provider_performance"

# Harvest Schedule
[[triggers.crons]]
crons = ["0 3 * * *"]
```

### Harvest Secret

**Purpose:** Prevent unauthorized manual harvest triggers

**Setup:**
```bash
npx wrangler secret put HARVEST_SECRET
# Enter: {random-secure-string}
```

**Usage:**
```bash
curl -X POST 'https://api-worker.jukasdrj.workers.dev/api/harvest-covers' \
  -H 'X-Harvest-Secret: {secret}'
```

## Cost Analysis

### ISBNdb API
- **Plan:** $39/month (5000 req/day - Premium Plan)
- **Usage:** 20-30% utilization (1000-1500 ISBNs/day)
- **Cost per ISBN:** $0.0013
- **Headroom:** 3500-4000 requests/day available for future expansion

### Cloudflare Resources
- **R2 Storage:** $0.015/GB/month
  - 519 covers × 5.6 KB avg = 2.92 MB
  - Cost: ~$0.000044/month (negligible)
- **KV Operations:** Free tier (1M reads/day)
- **Analytics Engine:** Free tier (10M events/month)
- **Worker CPU:** Free tier (100k req/day)

**Total Monthly Cost:** ~$39.05 ($39 ISBNdb + $0.05 infrastructure)

## Monitoring

### Key Metrics

**Harvest Success Rate:**
```
successRate = (successful / total) * 100
Target: 80%+ (accounts for already-cached and no-cover ISBNs)
```

**Cache Hit Rate:**
```
hitRate = (cacheHits / totalRequests) * 100
Target: 75-90%
```

**API Quota Utilization:**
```
utilization = (dailyRequests / 1000) * 100
Target: 77-100%
```

**Storage Efficiency:**
```
compressionSavings = ((originalSize - compressedSize) / originalSize) * 100
Target: 60%+ (WebP)
```

### Alerts (Future)

- Harvest failures (>20% error rate)
- API quota exhausted (<100 requests remaining)
- Analytics Engine errors
- R2 upload failures

## Troubleshooting

### Common Issues

**Problem:** Analytics query returns 0 ISBNs
**Solution:** Wait 24h for data aggregation, verify logging format matches query

**Problem:** Low harvest success rate (<50%)
**Solution:** Check ISBNdb API status, verify curated ISBN quality

**Problem:** High storage costs
**Solution:** Verify WebP compression is active, check for duplicate uploads

**Problem:** Multi-edition discovery returns 0 editions
**Solution:** Check Google Books API rate limiting, verify seed ISBN validity

### Debug Endpoints

**Worker Logs:**
```bash
npx wrangler tail --format pretty
```

**Test Edition Discovery:**
```bash
curl "https://api-worker.jukasdrj.workers.dev/api/test-multi-edition?count=3"
```

**Check Dashboard Stats:**
```bash
curl "https://api-worker.jukasdrj.workers.dev/admin/harvest-dashboard"
```

## Future Enhancements

### Phase 3: Author Bibliography Integration (Optional)
- Query Analytics for top 50 most-searched authors
- Cache ALL books by popular authors via edition discovery
- Estimated 1000-2000 additional covers

### Phase 4: Quality Validation (Implemented)
- ✅ HTML dashboard at `/admin/harvest-dashboard`
- ✅ Real-time stats visualization
- ✅ Source breakdown analytics
- ✅ Multi-edition strategy status

### Other Ideas
- Smart cache expiration (refresh old covers)
- User-requested ISBN harvesting
- Cover quality scoring (resolution, aspect ratio)
- A/B testing for edition selection
- Predictive caching based on trends

## References

- **ISBNdb API Docs:** https://isbndb.com/apidocs
- **Google Books API:** https://developers.google.com/books/docs/v1/getting_started
- **Cloudflare R2:** https://developers.cloudflare.com/r2/
- **Cloudflare KV:** https://developers.cloudflare.com/kv/
- **Analytics Engine:** https://developers.cloudflare.com/analytics/analytics-engine/

---

**Last Reviewed:** November 13, 2025
**Maintainer:** Claude Code
**Status:** ✅ Production Active
