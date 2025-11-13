# Cloudflare Workers Architecture (Monolith)

**Last Updated:** November 13, 2025
**Status:** Monolith refactor completed + Multi-Edition Harvest active

## Overview

BooksTrack backend has been consolidated into a single monolith worker (`api-worker`) to eliminate circular dependencies, reduce network latency, and unify status reporting.

**Previous Architecture:** 5 distributed workers with RPC service bindings (archived in `_archived/`)

**Current Architecture:** Single worker with direct function calls

## Current Architecture

### Single Worker: api-worker

All backend logic runs in one Cloudflare Worker process. No service bindings. No circular dependencies.

**Worker URL:** `https://api-worker.jukasdrj.workers.dev`

### Components

```
api-worker/
├── src/
│   ├── index.js                          # Main router & request handling
│   ├── durable-objects/
│   │   └── progress-socket.js            # ProgressWebSocketDO
│   ├── services/
│   │   ├── external-apis.js              # Google Books, OpenLibrary
│   │   ├── enrichment.js                 # Batch book enrichment
│   │   ├── ai-scanner.js                 # Gemini AI bookshelf scanning
│   │   ├── edition-discovery.js          # Multi-edition harvest (NEW)
│   │   └── isbndb-api.js                 # ISBNdb cover images
│   ├── handlers/
│   │   ├── search-handlers.js            # Advanced search logic
│   │   ├── book-search.js                # Title/ISBN search
│   │   ├── scheduled-harvest.js          # Daily cover harvest (NEW)
│   │   ├── harvest-dashboard.js          # HTML dashboard (NEW)
│   │   └── test-multi-edition.js         # Edition discovery test
│   └── utils/
│       ├── cache.js                      # KV caching utilities
│       └── analytics.js                  # Analytics Engine logging (NEW)
```

### Component Roles

**Main Router (`src/index.js`):**
- HTTP request routing
- WebSocket connection delegation to Durable Object
- Endpoint handlers

**Durable Object (`src/durable-objects/progress-socket.js`):**
- WebSocket connection management
- Real-time progress updates for ALL background jobs
- Single source of truth for job status

**Services (`src/services/`):**
- Business logic modules
- Direct function calls (no RPC)
- Internal communication via shared `env` and `doStub` parameters

**Handlers (`src/handlers/`):**
- Request processing logic
- Search orchestration
- Response formatting

**Utils (`src/utils/`):**
- Shared utilities
- KV cache management
- Helper functions

## API Endpoints

### Book Search
- `GET /search/title?q={query}` - General book search (6h cache)
- `GET /search/isbn?isbn={isbn}` - ISBN lookup (7-day cache)
- `GET /search/advanced?title={title}&author={author}` - Multi-field search (primary method, HTTP cacheable)
- `POST /search/advanced` - Multi-field search (legacy support, accepts JSON body)

### Background Jobs
- `POST /api/enrichment/start` - Batch book enrichment with WebSocket progress
- `POST /api/scan-bookshelf?jobId={uuid}` - AI bookshelf scan with WebSocket progress

### Status Updates
- `GET /ws/progress?jobId={uuid}` - WebSocket for real-time progress (unified for ALL jobs)

### Health
- `GET /health` - Health check and endpoint listing

## Status Reporting Architecture

### Unified WebSocket System

**Single Durable Object:** `ProgressWebSocketDO`

All background jobs (enrichment, AI scanning, etc.) report status via WebSocket. No polling endpoints.

**Flow:**
1. Client generates unique `jobId`
2. Client connects to `/ws/progress?jobId={uuid}`
3. Client triggers background job (enrichment or AI scan)
4. Worker processes job and pushes progress via Durable Object stub
5. Client receives real-time updates via WebSocket
6. Worker closes WebSocket when job completes

**Example:**
```javascript
// Get DO stub for this job
const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

// Start background job with DO stub for progress updates
ctx.waitUntil(enrichment.enrichBatch(jobId, workIds, env, doStub));

// Inside enrichment service
await doStub.pushProgress({
  progress: 0.5,
  currentStatus: 'Enriched 5/10 books',
  jobId
});
```

## Internal Communication Patterns

### Direct Function Calls

All services communicate via direct function imports. No network calls between modules.

**Example:**
```javascript
// src/services/ai-scanner.js
import { handleAdvancedSearch } from '../handlers/search-handlers.js';

// Direct function call (no RPC!)
const searchResults = await handleAdvancedSearch({
  title: detectedBook.title,
  author: detectedBook.author,
  isbn: detectedBook.isbn
}, env);
```

### Shared Dependencies

Services receive shared dependencies as function parameters:

- `env` - Worker environment bindings (KV, R2, AI, secrets)
- `doStub` - ProgressWebSocketDO stub for status updates
- `ctx` - Execution context for `waitUntil()` (background tasks)

**Example:**
```javascript
export async function processBookshelfScan(jobId, imageData, env, doStub) {
  // Access secrets
  const geminiKey = env.GEMINI_API_KEY;

  // Push progress
  await doStub.pushProgress({ progress: 0.1, currentStatus: 'Starting...', jobId });

  // Call external API
  const result = await callGeminiVision(imageData, env);

  // Enrich via internal function
  const enriched = await handleAdvancedSearch({ title: result.title }, env);
}
```

## Deployment

### Single Worker Deployment

```bash
cd cloudflare-workers/api-worker
npm run deploy
```

**No deployment order required!** Single worker, no dependencies.

### Environment Variables

**Secrets (via `wrangler secret put`):**
- `GOOGLE_BOOKS_API_KEY` - Google Books API authentication
- `GEMINI_API_KEY` - Gemini AI authentication

**Vars (in `wrangler.toml`):**
- `OPENLIBRARY_BASE_URL` - OpenLibrary API base URL
- `CONFIDENCE_THRESHOLD` - AI detection confidence threshold (0.6)
- `MAX_SCAN_FILE_SIZE` - Maximum upload size in bytes (10485760 = 10MB)

### Bindings

**KV Namespaces:**
- `CACHE` - Response caching for search APIs

**R2 Buckets:**
- `BOOKSHELF_IMAGES` - Uploaded bookshelf photos (optional)

**AI:**
- `AI` - Cloudflare AI binding (if using Cloudflare AI instead of Gemini)

**Durable Objects:**
- `PROGRESS_WEBSOCKET_DO` → `ProgressWebSocketDO` class

## Previous Architecture (Archived)

The previous distributed architecture with 5 workers and RPC service bindings is archived in `_archived/` for reference.

**Archived Workers:**
- `books-api-proxy` - Main orchestrator
- `enrichment-worker` - Batch enrichment service
- `bookshelf-ai-worker` - AI vision processing
- `external-apis-worker` - External API integrations
- `progress-websocket-durable-object` - WebSocket DO (standalone)

**Why Consolidated:**
- Eliminated circular dependency risk
- Reduced network latency (0ms between services vs 3+ network hops)
- Simplified deployment (1 worker vs 5)
- Unified status reporting (single Durable Object instead of dual polling/push)
- Easier debugging and monitoring

**See:** `_archived/README.md` for migration details.

## Architecture Principles

1. **No Network Calls Between Services:** All communication via direct function calls
2. **Single Status System:** WebSocket-only progress updates via ProgressWebSocketDO
3. **Shared Dependencies:** Services receive `env` and `doStub` as parameters
4. **Background Jobs via waitUntil:** Long-running tasks use `ctx.waitUntil()` pattern
5. **No Polling Endpoints:** Removed `/scan/status/{jobId}`, `/scan/ready/{jobId}`, etc.

## Testing

### Local Development

```bash
cd cloudflare-workers/api-worker
npx wrangler dev
```

### Health Check

```bash
curl https://api-worker.jukasdrj.workers.dev/health
```

Expected response:
```json
{
  "status": "ok",
  "worker": "api-worker",
  "version": "1.0.0",
  "endpoints": [
    "/search/title",
    "/search/isbn",
    "/search/advanced",
    "/api/scan-bookshelf",
    "/api/enrichment/start",
    "/ws/progress"
  ]
}
```

### Search Endpoints

```bash
# Title search
curl "https://api-worker.jukasdrj.workers.dev/search/title?q=hamlet"

# ISBN search
curl "https://api-worker.jukasdrj.workers.dev/search/isbn?isbn=9780743273565"

# Advanced search
curl -X POST https://api-worker.jukasdrj.workers.dev/search/advanced \
  -H "Content-Type: application/json" \
  -d '{"title":"1984","author":"Orwell"}'
```

### WebSocket Flow

1. Connect to WebSocket:
```bash
wscat -c "wss://api-worker.jukasdrj.workers.dev/ws/progress?jobId=test-123"
```

2. Trigger background job (in another terminal):
```bash
curl -X POST https://api-worker.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test-123","workIds":["9780439708180"]}'
```

3. Observe real-time progress in WebSocket terminal

## Monitoring

### Production Logs

```bash
cd cloudflare-workers/api-worker
wrangler tail --format pretty
```

### Metrics to Monitor

- Response times (search endpoints < 500ms)
- WebSocket latency (< 50ms)
- Cache hit rate (> 60% target)
- Error rate (< 1% target)
- Background job completion rate

### Common Debugging Patterns

**Check for direct function calls (not RPC):**
```bash
wrangler tail --format pretty | grep -v "rpc_"
```

Expected: No RPC-related logs (all internal calls are direct)

**Verify WebSocket connections:**
```bash
wrangler tail --format pretty | grep "WebSocket"
```

Expected: Connection opens, progress updates, connection closes

**Monitor cache performance:**
```bash
wrangler tail --format pretty | grep "Cache"
```

Expected: Cache HIT/SET logs with TTL values

## Migration Notes

**Breaking Changes from Distributed Architecture:**
- Old worker URLs deprecated (`books-api-proxy.jukasdrj.workers.dev`, etc.)
- Polling endpoints removed (`/scan/status/{jobId}`, `/scan/ready/{jobId}`)
- `SCAN_JOBS` KV namespace deleted (WebSocket-only status)

**iOS App Updates Required:**
- Update API base URLs to `api-worker.jukasdrj.workers.dev`
- Remove polling-based status checks
- Unify WebSocket connection logic for all background jobs

**See:** `docs/plans/2025-10-23-cloudflare-workers-monolith-refactor.md` for full migration plan.
