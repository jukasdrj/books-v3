# Migration Audit - Cloudflare Workers Monolith Refactor

**Date:** October 23, 2025
**Audited By:** Claude Code
**Purpose:** Pre-migration assessment for consolidating 5 distributed workers into monolith

---

## Current Workers Overview

### 1. books-api-proxy

**File:** `cloudflare-workers/books-api-proxy/wrangler.toml`

**Role:** Main orchestrator for book search and enrichment

**Bindings:**
- **KV Namespaces:**
  - `CACHE` → `b9cade63b6db48fd80c109a013f38fdb` (API response cache)
- **R2 Buckets:**
  - `API_CACHE_COLD` → `personal-library-data` (cold storage layer)
  - `LIBRARY_DATA` → `personal-library-data` (unified with cache-warmer)
- **Service Bindings:**
  - `EXTERNAL_APIS_WORKER` → `external-apis-worker` (RPC: ExternalAPIsWorker)
  - `ENRICHMENT_WORKER` → `enrichment-worker` (RPC: EnrichmentWorker)
- **Durable Objects:**
  - `PROGRESS_WEBSOCKET_DO` → `progress-websocket-durable-object` (ProgressWebSocketDO)
- **Secrets (via Secrets Store):**
  - `GOOGLE_BOOKS_API_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: Google_books_hardoooe)
  - `GOOGLE_BOOKS_IOSKEY` (store: b0562ac16fde468c8af12717a6c88400, secret: Google_books_ioskey)
  - `ISBNDB_API_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: ISBNDB_API_KEY)
  - `ISBN_SEARCH_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: ISBN_search_key)
- **Workers AI:**
  - `AI` binding enabled
- **Analytics Engine:**
  - `PERFORMANCE_ANALYTICS` → `books_api_performance`
  - `CACHE_ANALYTICS` → `books_api_cache_metrics`
  - `PROVIDER_ANALYTICS` → `books_api_provider_performance`

**Configuration:**
- `compatibility_date`: `2024-09-17`
- `compatibility_flags`: `["nodejs_compat"]`
- `entrypoint`: `BooksAPIProxyWorker` (RPC-enabled)
- **Limits:** `cpu_ms: 30000`, `memory_mb: 256`
- **Placement:** `smart` (global optimization)
- **Observability:** Enabled with logpush

**Environment Variables:**
```toml
CACHE_HOT_TTL = "7200"         # 2 hours
CACHE_COLD_TTL = "1209600"     # 14 days
MAX_RESULTS_DEFAULT = "40"
RATE_LIMIT_MS = "50"
CONCURRENCY_LIMIT = "10"
AGGRESSIVE_CACHING = "true"
ENABLE_PERFORMANCE_LOGGING = "true"
ENABLE_CACHE_ANALYTICS = "true"
ENABLE_PROVIDER_METRICS = "true"
LOG_LEVEL = "DEBUG"
ENABLE_RATE_LIMIT_TRACKING = "true"
STRUCTURED_LOGGING = "true"
```

**Endpoints:**
- HTTP: `/search/*`, `/enrichment/*`, `/health`
- WebSocket: `/ws/progress?jobId={uuid}` (proxied to Durable Object)

**RPC Methods (BooksAPIProxyWorker):**
- `searchBooks(query, options)`
- `searchByAuthor(authorName, options)`
- `searchByISBN(isbn, options)`
- `advancedSearch(criteria, options)`
- `startBatchEnrichment(jobId, workIds, options)`

**Dependencies:**
- **Calls:** enrichment-worker (RPC), external-apis-worker (RPC), progress-websocket-durable-object (DO)
- **Called By:** iOS app (HTTP/WebSocket), bookshelf-ai-worker (RPC - CIRCULAR!)

---

### 2. enrichment-worker

**File:** `cloudflare-workers/enrichment-worker/wrangler.toml`

**Role:** Batch book enrichment processor

**Bindings:**
- **Service Bindings:**
  - `EXTERNAL_APIS_WORKER` → `external-apis-worker` (RPC: ExternalAPIsWorker)

**Configuration:**
- `compatibility_date`: `2024-10-01`
- No entrypoint specified (uses default export)

**Environment Variables:**
```toml
LOG_LEVEL = "DEBUG"
```

**Endpoints:**
- No HTTP endpoints (RPC-only worker)

**RPC Methods (EnrichmentWorker):**
- `enrichBatch(jobId, workIds, progressCallback, options)`

**Dependencies:**
- **Calls:** external-apis-worker (RPC)
- **Called By:** books-api-proxy (RPC)

**Notes:**
- Uses callback pattern to avoid circular dependency back to books-api-proxy
- No direct access to WebSocket DO (progress via callback)

---

### 3. bookshelf-ai-worker

**File:** `cloudflare-workers/bookshelf-ai-worker/wrangler.toml`

**Role:** AI vision-based bookshelf scanning

**Bindings:**
- **KV Namespaces:**
  - `SCAN_JOBS` → `5d4b89403bbb4be1949b1ee30df5353e` (scan job tracking)
- **Service Bindings:**
  - `BOOKS_API_PROXY` → `books-api-proxy` (RPC: BooksAPIProxyWorker) ⚠️ **CIRCULAR!**
- **Durable Objects:**
  - `PROGRESS_WEBSOCKET_DO` → `progress-websocket-durable-object` (ProgressWebSocketDO)
- **Secrets (via Secrets Store):**
  - `GEMINI_API_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: google_aistudio_key)
- **Workers AI:**
  - `AI` binding enabled (fallback provider)
- **Analytics Engine:**
  - `AI_ANALYTICS` → `bookshelf_ai_performance`

**Configuration:**
- `compatibility_date`: `2024-09-17`
- `compatibility_flags`: `["nodejs_compat"]`
- **Limits:** `cpu_ms: 30000`, `memory_mb: 256`
- **Placement:** `smart`
- **Observability:** Enabled

**Environment Variables:**
```toml
AI_PROVIDER = "gemini"  # or "cloudflare"
MAX_IMAGE_SIZE_MB = "10"
REQUEST_TIMEOUT_MS = "50000"
LOG_LEVEL = "DEBUG"
CONFIDENCE_THRESHOLD = "0.7"
```

**Endpoints:**
- `POST /scan?jobId={uuid}` - Upload bookshelf image
- `GET /scan/status/{jobId}` - Poll for scan status (HTTP fallback)
- `POST /scan/ready/{jobId}` - Signal WebSocket ready
- WebSocket: `/ws/progress?jobId={uuid}` (proxied to DO)

**RPC Methods (BookshelfAIWorker):**
- `scanBookshelf(imageData, options)`

**Dependencies:**
- **Calls:** books-api-proxy (RPC - for enrichment) ⚠️ **CREATES CIRCULAR DEPENDENCY!**
- **Calls:** progress-websocket-durable-object (DO)
- **Called By:** iOS app (HTTP/WebSocket), potentially books-api-proxy (RPC)

**Critical Issue:**
```
books-api-proxy → bookshelf-ai-worker → books-api-proxy (CIRCULAR!)
```

---

### 4. external-apis-worker

**File:** `cloudflare-workers/external-apis-worker/wrangler.toml`

**Role:** Direct integration with external book APIs (Google Books, OpenLibrary, ISBNdb)

**Bindings:**
- **KV Namespaces:**
  - `KV_CACHE` → `b9cade63b6db48fd80c109a013f38fdb` (shared with books-api-proxy)
- **Secrets (via Secrets Store):**
  - `GOOGLE_BOOKS_API_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: Google_books_hardoooe)
  - `ISBNDB_API_KEY` (store: b0562ac16fde468c8af12717a6c88400, secret: ISBNDB_API_KEY)

**Configuration:**
- `compatibility_date`: `2024-09-17`
- `compatibility_flags`: `["nodejs_compat"]`

**Environment Variables:**
```toml
USER_AGENT = "BooksTracker/1.0 (nerd@ooheynerds.com) ExternalAPIsWorker/1.0.0"
LOG_LEVEL = "DEBUG"
```

**Endpoints:**
- HTTP: `/search?q={query}` (for testing)

**RPC Methods (ExternalAPIsWorker):**
- `searchBooks(query, options)`
- `searchByISBN(isbn, options)`
- `searchByAuthor(authorName, options)`

**Dependencies:**
- **Calls:** External APIs (Google Books, OpenLibrary, ISBNdb) via HTTPS
- **Called By:** books-api-proxy (RPC), enrichment-worker (RPC)

**Notes:**
- Leaf node in dependency tree (no service bindings)
- Pure API integration layer

---

### 5. progress-websocket-durable-object

**File:** `cloudflare-workers/progress-websocket-durable-object/wrangler.toml`

**Role:** WebSocket connection manager for real-time progress updates

**Bindings:**
- **Durable Objects:**
  - `PROGRESS_WEBSOCKET_DO` → Self-referential (defines the DO class)

**Configuration:**
- `compatibility_date`: `2024-10-01`
- `compatibility_flags`: `["nodejs_compat"]`
- **Observability:** Enabled with 100% head sampling

**Environment Variables:**
```toml
LOG_LEVEL = "DEBUG"
```

**Migrations:**
```toml
[[migrations]]
tag = "v1"
new_classes = ["ProgressWebSocketDO"]
```

**Endpoints:**
- WebSocket: `/ws/progress?jobId={uuid}` (handled by DO fetch())

**Durable Object Methods:**
- `fetch(request)` - WebSocket upgrade and message routing
- `pushProgress(progressData)` - RPC method for progress updates
- `closeConnection(code, reason)` - RPC method for cleanup

**Dependencies:**
- **Calls:** None (stateful storage only)
- **Called By:** books-api-proxy (DO stub), bookshelf-ai-worker (DO stub)

**Notes:**
- Stateful WebSocket session management
- Single source of truth for progress tracking
- Stores active connections in Durable Object storage

---

## Circular Dependencies Identified

### Primary Circular Dependency

```
books-api-proxy ──RPC──> bookshelf-ai-worker ──RPC──> books-api-proxy
        ^                                                  |
        |__________________________________________________|
```

**Problematic Flow:**
1. iOS app calls `books-api-proxy.startBatchEnrichment()`
2. If worker needs AI scan, it calls `bookshelf-ai-worker.scanBookshelf()` (hypothetical)
3. Bookshelf worker enriches detected books by calling `BOOKS_API_PROXY.advancedSearch()`
4. **CIRCULAR!** books-api-proxy → bookshelf-ai-worker → books-api-proxy

**Evidence from Source:**
- `bookshelf-ai-worker/wrangler.toml` line 49: `binding = "BOOKS_API_PROXY"`
- `bookshelf-ai-worker/src/index.js` line 671: `await env.BOOKS_API_PROXY.advancedSearch()`

**Impact:**
- Deployment order ambiguity (which deploys first?)
- Potential infinite recursion if not carefully managed
- Increased latency (3 network hops: iOS → books-api-proxy → bookshelf-ai → books-api-proxy → external-apis)

---

## Status Systems Analysis

### Current Architecture: Dual System (Push + Poll)

#### Push-Based System (WebSocket)

**Mechanism:**
- Client connects to `wss://books-api-proxy.../ws/progress?jobId={uuid}`
- Worker obtains DO stub: `env.PROGRESS_WEBSOCKET_DO.get(doId)`
- Worker calls `doStub.pushProgress(progressData)` during processing
- DO broadcasts to connected WebSocket clients

**Used By:**
- `books-api-proxy` batch enrichment
- `bookshelf-ai-worker` AI scan (potentially)

**Latency:** ~8ms (from ProgressWebSocketDO benchmarks)

**Advantages:**
- Real-time updates
- Minimal latency
- Battery-efficient (no polling)

**Disadvantages:**
- Requires persistent WebSocket connection
- Connection management complexity

#### Poll-Based System (HTTP)

**Mechanism:**
- Worker stores job status in `SCAN_JOBS` KV namespace
- Client polls `GET /scan/status/{jobId}` every 2-5 seconds
- Returns current status from KV

**Used By:**
- `bookshelf-ai-worker` HTTP fallback endpoints:
  - `GET /scan/status/{jobId}` - Poll for results
  - `POST /scan/ready/{jobId}` - Signal WebSocket ready

**Latency:** 2-5 seconds (polling interval)

**Advantages:**
- Works without WebSocket support
- Simple HTTP requests
- No connection state

**Disadvantages:**
- High latency (2-5s update delay)
- Battery drain (constant polling)
- KV read costs (every poll = 1 KV read)
- Dual system complexity

### Unified System Vision (Monolith)

**Single System:** WebSocket-only via ProgressWebSocketDO

**Changes:**
1. **Remove polling endpoints:**
   - Delete `GET /scan/status/{jobId}`
   - Delete `POST /scan/ready/{jobId}`
   - Delete `SCAN_JOBS` KV namespace

2. **Unify all background jobs:**
   - AI scan → ProgressWebSocketDO
   - Batch enrichment → ProgressWebSocketDO
   - Any future jobs → ProgressWebSocketDO

3. **Benefits:**
   - Single code path for status
   - No KV storage costs for status
   - No dual-system complexity
   - Consistent 8ms latency

---

## Deployment Verification

### Test Results (October 23, 2025)

```bash
# books-api-proxy
curl https://books-api-proxy.jukasdrj.workers.dev/health
✅ {"status":"healthy","worker":"books-api-proxy"}

# bookshelf-ai-worker
curl https://bookshelf-ai-worker.jukasdrj.workers.dev/health
✅ {"status":"healthy","provider":"gemini","timestamp":"2025-10-24T02:20:16.872Z"}

# external-apis-worker
curl https://external-apis-worker.jukasdrj.workers.dev/health
✅ {"status":"healthy","worker":"external-apis-worker"}
```

**Status:** All workers deployed and responding ✅

### Current Deployment Order (from MONOLITH_ARCHITECTURE.md)

```bash
# 1. Leaf workers (no dependencies)
external-apis-worker          # ✅ Deployed
progress-websocket-durable-object  # ✅ Deployed

# 2. Mid-tier workers
enrichment-worker             # ✅ Deployed (depends on external-apis)

# 3. Root orchestrator
books-api-proxy              # ✅ Deployed (depends on enrichment + external-apis + progress-websocket-DO)

# 4. AI worker (creates circular dependency!)
bookshelf-ai-worker          # ✅ Deployed (depends on books-api-proxy - CIRCULAR!)
```

**Note:** bookshelf-ai-worker can deploy successfully because books-api-proxy is already deployed. This masks the circular dependency issue.

---

## API Endpoints Inventory

### books-api-proxy

**HTTP Endpoints:**
- `GET /search/title?q={query}` - Title search (6h cache)
- `GET /search/isbn?isbn={isbn}` - ISBN lookup (7-day cache)
- `POST /search/advanced` - Multi-field search (orchestrates 3 providers)
- `POST /api/enrichment/start` - Batch enrichment with WebSocket progress
- `GET /health` - Health check

**WebSocket Endpoints:**
- `GET /ws/progress?jobId={uuid}` - Real-time progress (Durable Object proxy)

**RPC Methods (for other workers):**
- `searchBooks(query, options)`
- `searchByAuthor(authorName, options)`
- `searchByISBN(isbn, options)`
- `advancedSearch(criteria, options)`
- `startBatchEnrichment(jobId, workIds, options)`

---

### bookshelf-ai-worker

**HTTP Endpoints:**
- `POST /scan?jobId={uuid}` - Upload bookshelf image for AI analysis
- `GET /scan/status/{jobId}` - Poll for scan results (HTTP fallback) ⚠️ **TO BE DELETED**
- `POST /scan/ready/{jobId}` - Signal WebSocket ready ⚠️ **TO BE DELETED**
- `GET /health` - Health check

**WebSocket Endpoints:**
- `GET /ws/progress?jobId={uuid}` - Real-time scan progress (Durable Object proxy)

**RPC Methods:**
- `scanBookshelf(imageData, options)`

---

### enrichment-worker

**HTTP Endpoints:**
- None (RPC-only worker)

**RPC Methods:**
- `enrichBatch(jobId, workIds, progressCallback, options)`

---

### external-apis-worker

**HTTP Endpoints:**
- `GET /search?q={query}` - Testing endpoint (not used in production)
- `GET /health` - Health check

**RPC Methods:**
- `searchBooks(query, options)` - Multi-provider search
- `searchByISBN(isbn, options)` - ISBN-specific search
- `searchByAuthor(authorName, options)` - Author-specific search

---

### progress-websocket-durable-object

**WebSocket Endpoints:**
- `GET /ws/progress?jobId={uuid}` - WebSocket connection management

**Durable Object Methods (RPC via DO stub):**
- `pushProgress(progressData)` - Send progress update to connected clients
- `closeConnection(code, reason)` - Gracefully close WebSocket

---

## Resource Dependencies

### KV Namespaces

| Worker | Binding | ID | Purpose |
|--------|---------|-----|---------|
| books-api-proxy | CACHE | b9cade63b6db48fd80c109a013f38fdb | API response cache (hot) |
| external-apis-worker | KV_CACHE | b9cade63b6db48fd80c109a013f38fdb | Shared cache |
| bookshelf-ai-worker | SCAN_JOBS | 5d4b89403bbb4be1949b1ee30df5353e | Scan job status ⚠️ **TO BE DELETED** |

**Consolidation Plan:**
- Migrate to single `CACHE` binding in monolith
- Delete `SCAN_JOBS` KV namespace (replaced by WebSocket-only)

---

### R2 Buckets

| Worker | Binding | Bucket Name | Purpose |
|--------|---------|-------------|---------|
| books-api-proxy | API_CACHE_COLD | personal-library-data | Cold storage layer |
| books-api-proxy | LIBRARY_DATA | personal-library-data | Unified cache-warmer |

**Consolidation Plan:**
- Migrate both bindings to monolith (same bucket)

---

### Secrets Store

**Store ID:** `b0562ac16fde468c8af12717a6c88400` (shared across all workers)

| Secret Name | Used By | Purpose |
|-------------|---------|---------|
| Google_books_hardoooe | books-api-proxy, external-apis-worker | Google Books API key |
| Google_books_ioskey | books-api-proxy | iOS-specific Google Books key |
| ISBNDB_API_KEY | books-api-proxy, external-apis-worker | ISBNdb API key |
| ISBN_search_key | books-api-proxy | ISBN search key |
| google_aistudio_key | bookshelf-ai-worker | Gemini AI API key |

**Consolidation Plan:**
- All secrets migrate to monolith worker
- No changes to Secrets Store (bindings point to same secrets)

---

### Analytics Engine

| Worker | Binding | Dataset | Purpose |
|--------|---------|---------|---------|
| books-api-proxy | PERFORMANCE_ANALYTICS | books_api_performance | API latency metrics |
| books-api-proxy | CACHE_ANALYTICS | books_api_cache_metrics | Cache hit/miss rates |
| books-api-proxy | PROVIDER_ANALYTICS | books_api_provider_performance | External API health |
| bookshelf-ai-worker | AI_ANALYTICS | bookshelf_ai_performance | AI scan performance |

**Consolidation Plan:**
- Migrate all analytics bindings to monolith
- Datasets remain unchanged

---

## Migration Risks & Considerations

### High Priority

1. **Circular Dependency Elimination**
   - **Risk:** Breaking change for bookshelf-ai-worker
   - **Solution:** Move AI enrichment logic into monolith (internal function calls)
   - **Impact:** No RPC calls needed, ~50ms latency reduction

2. **WebSocket Migration**
   - **Risk:** Durable Object must be embedded in monolith worker
   - **Solution:** Export DO class from monolith, update migrations
   - **Impact:** Single worker handles WebSocket and business logic

3. **Polling Endpoint Deprecation**
   - **Risk:** Breaking change if iOS app uses HTTP fallback
   - **Solution:** Verify iOS app uses WebSocket-only, then delete polling endpoints
   - **Impact:** Simplified codebase, reduced KV costs

### Medium Priority

4. **Secret Migration**
   - **Risk:** Secrets must be bound to new worker name
   - **Solution:** Secrets Store bindings point to same secrets (no re-upload needed)
   - **Impact:** Update wrangler.toml bindings only

5. **KV Namespace Consolidation**
   - **Risk:** Shared KV namespace (b9cade63b6db48fd80c109a013f38fdb) used by multiple workers
   - **Solution:** Single binding in monolith, retire old worker bindings
   - **Impact:** No data migration (same KV namespace ID)

6. **Analytics Continuity**
   - **Risk:** Historical analytics may be lost if datasets change
   - **Solution:** Keep same dataset names in monolith
   - **Impact:** Continuous analytics, no data loss

### Low Priority

7. **RPC Method Signature Changes**
   - **Risk:** iOS app may call old RPC methods
   - **Solution:** iOS app uses HTTP endpoints, not RPC (no impact)
   - **Impact:** None (RPC was for inter-worker communication)

8. **Deployment Rollback**
   - **Risk:** Monolith fails, need to restore old workers
   - **Solution:** Archive old workers in `_archived/`, keep for 30 days
   - **Impact:** 5-minute rollback via `wrangler deploy` from archive

---

## Success Criteria

### Pre-Migration

- [x] All 5 workers deployed and healthy
- [x] Circular dependency documented
- [x] All bindings inventoried
- [x] All endpoints documented
- [x] Status systems analyzed

### Post-Migration

- [ ] Single worker deployed successfully
- [ ] All endpoints functional (HTTP + WebSocket)
- [ ] Zero circular dependencies
- [ ] KV_CACHE consolidated
- [ ] SCAN_JOBS KV namespace deleted
- [ ] Polling endpoints removed (`/scan/status`, `/scan/ready`)
- [ ] iOS app tests pass
- [ ] WebSocket latency < 10ms
- [ ] Analytics continuity verified

---

## Appendix: Compatibility Flags

All workers use:
```toml
compatibility_date = "2024-09-17" or "2024-10-01"
compatibility_flags = ["nodejs_compat"]
```

**Monolith Compatibility:**
- Use latest compatibility_date: `2024-10-01`
- Keep `nodejs_compat` flag
- Test Durable Object migrations

---

## Next Steps (Task 2)

1. Create `api-worker` monolith skeleton
2. Merge all bindings into single `wrangler.toml`
3. Migrate ProgressWebSocketDO to `api-worker/src/durable-objects/`
4. Migrate all service logic to internal functions
5. Test deployment
6. Archive old workers

---

**Audit Complete ✅**
**Ready for Phase 2: Monolith Creation**
