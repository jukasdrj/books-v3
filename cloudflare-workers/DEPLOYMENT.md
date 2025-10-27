# Deployment Guide

**Last Updated:** October 23, 2025
**Current Architecture:** Monolith (consolidated from 5 distributed workers)

## Production Worker

**URL:** https://api-worker.jukasdrj.workers.dev
**Name:** `api-worker`
**Version:** 1.0.0

## Quick Start

### Deploy to Production

```bash
cd cloudflare-workers/api-worker
npm run deploy
```

**Expected Output:**
- Worker uploaded successfully
- Production URL: `https://api-worker.jukasdrj.workers.dev`
- All bindings verified (KV, R2, Durable Objects, AI, Analytics)

### Verify Deployment

```bash
# Health check (should return 200 OK)
curl https://api-worker.jukasdrj.workers.dev/health

# Test title search
curl "https://api-worker.jukasdrj.workers.dev/search/title?q=hamlet&maxResults=2"

# Test ISBN search
curl "https://api-worker.jukasdrj.workers.dev/search/isbn?isbn=9780743273565"
```

## Configuration

### Secrets (via Cloudflare Secrets Store)

All API keys are stored in Cloudflare's Secrets Store and automatically bound to the worker:

- **GOOGLE_BOOKS_API_KEY** - Google Books API access (binding: `GOOGLE_BOOKS_API_KEY`)
- **GEMINI_API_KEY** - Gemini AI vision API access (binding: `GEMINI_API_KEY`)
- **ISBNDB_API_KEY** - ISBNdb API access (binding: `ISBNDB_API_KEY`)

**Configuration Location:** `wrangler.toml` (lines 51-64)

```toml
[[secrets_store_secrets]]
binding = "GOOGLE_BOOKS_API_KEY"
store_id = "b0562ac16fde468c8af12717a6c88400"
secret_name = "Google_books_hardoooe"

[[secrets_store_secrets]]
binding = "GEMINI_API_KEY"
store_id = "b0562ac16fde468c8af12717a6c88400"
secret_name = "GEMINI_API_KEY"

[[secrets_store_secrets]]
binding = "ISBNDB_API_KEY"
store_id = "b0562ac16fde468c8af12717a6c88400"
secret_name = "ISBNDB_API_KEY"
```

**Note:** Secrets are managed through Cloudflare's Secrets Store, not via `wrangler secret put`. To update:
1. Log into Cloudflare Dashboard
2. Navigate to Workers & Pages > Settings > Secrets Store
3. Update the secret values in the store (ID: `b0562ac16fde468c8af12717a6c88400`)

### KV Namespaces

**CACHE / KV_CACHE** (both bindings point to same namespace):
- **ID:** `b9cade63b6db48fd80c109a013f38fdb`
- **Purpose:** API response caching
- **TTL:** 2 hours (hot), 14 days (cold)

### R2 Buckets

**API_CACHE_COLD / LIBRARY_DATA** (both bindings point to same bucket):
- **Bucket:** `personal-library-data`
- **Purpose:** Long-term cold storage for library data

### Durable Objects

**PROGRESS_WEBSOCKET_DO:**
- **Class:** `ProgressWebSocketDO`
- **Purpose:** WebSocket connections for real-time progress updates
- **Migration:** v1 (initial deployment)

### Analytics Engine

- **PERFORMANCE_ANALYTICS** → `books_api_performance`
- **CACHE_ANALYTICS** → `books_api_cache_metrics`
- **PROVIDER_ANALYTICS** → `books_api_provider_performance`
- **AI_ANALYTICS** → `bookshelf_ai_performance`

## API Endpoints

### Search Endpoints

| Endpoint | Method | Description | Cache TTL |
|----------|--------|-------------|-----------|
| `/search/title?q={query}&maxResults={n}` | GET | Title search | 6 hours |
| `/search/isbn?isbn={isbn}&maxResults={n}` | GET | ISBN lookup | 7 days |
| `/search/advanced` | POST | Advanced multi-field search | Dynamic |

**Example:**
```bash
curl "https://api-worker.jukasdrj.workers.dev/search/title?q=the+great+gatsby&maxResults=10"
```

### Background Jobs

| Endpoint | Method | Description | Status Delivery |
|----------|--------|-------------|-----------------|
| `/api/enrichment/start` | POST | Batch book enrichment | WebSocket |
| `/api/scan-bookshelf?jobId={id}` | POST | AI bookshelf scanner | WebSocket |

**Example:**
```bash
# Start enrichment job
curl -X POST https://api-worker.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"jobId":"job-123","workIds":["work-1","work-2"]}'

# Response: {"jobId":"job-123","status":"started","totalBooks":2}
```

### WebSocket Progress

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| `/ws/progress?jobId={id}` | WebSocket | Real-time progress updates for ALL background jobs |

**Example (using wscat):**
```bash
wscat -c "wss://api-worker.jukasdrj.workers.dev/ws/progress?jobId=job-123"
```

**Progress Message Format:**
```json
{
  "progress": 0.5,
  "currentStatus": "Enriched 50/100 books",
  "jobId": "job-123",
  "currentBook": "work-42"
}
```

### External API Proxies (Backward Compatibility)

| Endpoint | Description |
|----------|-------------|
| `/external/google-books?q={query}&maxResults={n}` | Direct Google Books API proxy |
| `/external/google-books-isbn?isbn={isbn}` | Google Books ISBN lookup |
| `/external/openlibrary?q={query}&maxResults={n}` | OpenLibrary search |
| `/external/openlibrary-author?author={name}` | OpenLibrary author search |
| `/external/isbndb?title={title}&author={author}` | ISBNdb search |
| `/external/isbndb-editions?title={title}&author={author}` | ISBNdb editions |
| `/external/isbndb-isbn?isbn={isbn}` | ISBNdb ISBN lookup |

### Health Check

```bash
curl https://api-worker.jukasdrj.workers.dev/health
```

**Response:**
```json
{
  "status": "ok",
  "worker": "api-worker",
  "version": "1.0.0",
  "endpoints": [...]
}
```

## Migration Status

### Consolidated Workers (October 23, 2025)

The following 5 workers were merged into `api-worker`:

1. ✅ **books-api-proxy** → Search endpoints + caching
2. ✅ **enrichment-worker** → Batch enrichment service
3. ✅ **bookshelf-ai-worker** → AI bookshelf scanner
4. ✅ **external-apis-worker** → External API integrations
5. ✅ **progress-websocket-durable-object** → WebSocket progress updates

### Architecture Changes

| Before | After |
|--------|-------|
| 5 separate workers | 1 monolith worker |
| Service bindings (RPC) | Direct function calls |
| Dual status systems (polling + WebSocket) | WebSocket-only |
| Circular dependencies | Zero dependencies |
| 3+ network hops for progress | 0 hops (in-process) |

### Breaking Changes

❌ **Deprecated:**
- Old worker URLs (`books-api-proxy.jukasdrj.workers.dev`, etc.)
- Polling endpoints (`/scan/status/{jobId}`, `/scan/ready/{jobId}`)
- `SCAN_JOBS` KV namespace (ID: `5d4b89403bbb4be1949b1ee30df5353e`)

✅ **New:**
- Unified URL: `https://api-worker.jukasdrj.workers.dev`
- WebSocket-only status delivery
- All endpoints consolidated

## Monitoring

### Real-Time Logs

```bash
cd cloudflare-workers/api-worker
npm run tail

# Or with filtering
wrangler tail api-worker --format pretty --search "error"
```

### Analytics Dashboard

**Cloudflare Dashboard:**
1. Navigate to Workers & Pages
2. Select `api-worker`
3. View Analytics tab

**Datasets:**
- **books_api_performance** - Request latency, errors
- **books_api_cache_metrics** - Hit rates, TTL effectiveness
- **books_api_provider_performance** - External API latency
- **bookshelf_ai_performance** - AI scan durations, confidence scores

### Key Metrics

- **Response Time:** < 500ms (search endpoints)
- **WebSocket Latency:** < 50ms (progress updates)
- **Cache Hit Rate:** > 60% target
- **Error Rate:** < 1% target

## Troubleshooting

### Deployment Fails

**Issue:** Worker upload fails
**Solution:**
```bash
# Verify wrangler version
npx wrangler --version

# Clean and redeploy
rm -rf .wrangler node_modules
npm install
npm run deploy
```

### Secrets Not Available

**Issue:** API returns 401/403 errors
**Solution:**
- Secrets are in Cloudflare Secrets Store (not wrangler secrets)
- Verify store ID: `b0562ac16fde468c8af12717a6c88400`
- Check bindings in wrangler.toml (lines 51-64)

### WebSocket Connection Fails

**Issue:** WebSocket upgrade fails
**Solution:**
```bash
# Check DO binding
wrangler deployments list api-worker

# Verify DO migration ran
# Should show "v1" migration with ProgressWebSocketDO
```

### KV Cache Miss Rate High

**Issue:** Cache not working effectively
**Solution:**
```bash
# Check KV namespace
wrangler kv:namespace list

# Verify CACHE binding ID
# Expected: b9cade63b6db48fd80c109a013f38fdb
```

## Rollback Plan

If critical issues arise:

### 1. Immediate Mitigation

```bash
# Deploy previous version
wrangler deployments list api-worker
wrangler rollback --version-id <previous-version-id>
```

### 2. Full Rollback (if needed)

```bash
# Redeploy old workers from _archived/
cd cloudflare-workers/_archived

# For each worker:
cd books-api-proxy && wrangler deploy
cd enrichment-worker && wrangler deploy
# ... etc
```

### 3. Update iOS App

Revert iOS app URLs in `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/`:
- Change `api-worker.jukasdrj.workers.dev` back to old worker URLs
- Re-enable polling code if WebSocket-only fails

## Development

### Local Development

```bash
cd cloudflare-workers/api-worker

# Start dev server
npm run dev

# Test locally
curl http://localhost:8787/health
```

### Testing

```bash
# Run integration tests
npm test

# Watch mode
npm run test:watch
```

### Code Structure

```
api-worker/
├── src/
│   ├── index.js                      # Main router
│   ├── durable-objects/
│   │   └── progress-socket.js        # ProgressWebSocketDO
│   ├── services/
│   │   ├── external-apis.js          # Google Books, OpenLibrary, ISBNdb
│   │   ├── enrichment.js             # Batch enrichment logic
│   │   └── ai-scanner.js             # Gemini AI bookshelf scanner
│   ├── handlers/
│   │   ├── search-handlers.js        # Advanced search orchestration
│   │   └── book-search.js            # Title/ISBN search with caching
│   └── utils/
│       └── cache.js                  # KV/R2 caching utilities
├── tests/
│   └── integration.test.js           # Integration tests
└── wrangler.toml                     # Production configuration
```

## Performance Optimization

### Cache Configuration

**Hot Cache (KV):**
- TTL: 2 hours (`CACHE_HOT_TTL`)
- Use: Frequent searches, trending queries

**Cold Cache (R2):**
- TTL: 14 days (`CACHE_COLD_TTL`)
- Use: Stable data (ISBN lookups, edition details)

### Rate Limiting

- **Delay:** 50ms between provider requests (`RATE_LIMIT_MS`)
- **Concurrency:** Max 10 parallel requests (`CONCURRENCY_LIMIT`)
- **Prevents:** Provider rate limit violations

### AI Configuration

- **Provider:** Gemini 2.5 Flash (`AI_PROVIDER`)
- **Max Image Size:** 10 MB (`MAX_IMAGE_SIZE_MB`)
- **Timeout:** 50 seconds (`REQUEST_TIMEOUT_MS`)
- **Confidence Threshold:** 0.7 (`CONFIDENCE_THRESHOLD`)

## Security

### API Keys

- All keys in Cloudflare Secrets Store (never in code)
- Worker-level bindings (not environment secrets)
- Automatic key rotation supported

### Rate Limiting

- Internal: 50ms delay between requests
- External: Cloudflare rate limiting (1000 req/min default)

### CORS

- Not configured (backend-to-backend only)
- iOS app uses direct Worker URLs (no CORS needed)

## Support

### Documentation

- **Architecture:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md`
- **AI Scanner:** `docs/features/BOOKSHELF_SCANNER.md`
- **CSV Import:** `docs/features/CSV_IMPORT.md`
- **Main Guide:** `CLAUDE.md`

### Logs

```bash
# View recent logs
wrangler tail api-worker --format pretty

# Filter by level
wrangler tail api-worker --format pretty --level error
```

### Incident Response

1. Check health endpoint: `curl https://api-worker.jukasdrj.workers.dev/health`
2. View real-time logs: `wrangler tail api-worker`
3. Check Cloudflare Dashboard for errors
4. Review Analytics Engine datasets
5. Consider rollback if critical

---

**Deployment Status:** ✅ Production Live
**Last Deploy:** October 23, 2025
**Version:** 1.0.0
**URL:** https://api-worker.jukasdrj.workers.dev
