# Worker Logging Guide - api-worker

Complete reference for accessing logs and debugging your Cloudflare Worker (`api-worker`).

## Quick Start

Real-time logs (tail):
```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
npx wrangler tail
```

## Wrangler CLI Commands

All commands assume you're in the `api-worker` directory:
```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
```

### 1. Real-Time Log Tailing

**Basic tail (all logs):**
```bash
npx wrangler tail
```

**Tail with search filter (find specific requests):**
```bash
npx wrangler tail --search "provider"
npx wrangler tail --search "csv-gemini"
npx wrangler tail --search "scan-bookshelf"
npx wrangler tail --search "error"
npx wrangler tail --search "ERROR"
npx wrangler tail --search "jobId"
```

**Filter by status code:**
```bash
npx wrangler tail --search "202"          # Accepted responses (batch jobs)
npx wrangler tail --search "500"          # Server errors
npx wrangler tail --search "400"          # Client errors
```

**Filter by endpoint path:**
```bash
npx wrangler tail --search "/api/import/csv-gemini"
npx wrangler tail --search "/api/scan-bookshelf/batch"
npx wrangler tail --search "/api/enrichment"
npx wrangler tail --search "/v1/search"
npx wrangler tail --search "/api/enrichment/cancel"
```

**Filter by status with context:**
```bash
npx wrangler tail --search "error" --format pretty
```

**JSON format (for parsing):**
```bash
npx wrangler tail --format json | jq '.'
```

**Pretty format (human-readable):**
```bash
npx wrangler tail --format pretty
```

### 2. Background Task Failures (202 Responses)

Your CSV import and batch shelf scan return 202 Accepted, then fail asynchronously. Here's how to see those failures:

**Tail for all background task events:**
```bash
npx wrangler tail --search "jobId"
```

**Tail for enrichment failures specifically:**
```bash
npx wrangler tail --search "enrichment"
```

**Tail for Gemini AI failures:**
```bash
npx wrangler tail --search "gemini"
```

**Tail for WebSocket DO errors:**
```bash
npx wrangler tail --search "ProgressWebSocketDO"
```

**Watch for task cancellation:**
```bash
npx wrangler tail --search "canceled"
```

### 3. Performance & Cost Investigation

**View all structured logs:**
```bash
npx wrangler tail --format json | jq '.logs[] | select(.level == "debug")'
```

**Filter provider performance metrics:**
```bash
npx wrangler tail --search "google-books"
npx wrangler tail --search "openlibrary"
npx wrangler tail --search "provider_metric"
```

**View cache analytics:**
```bash
npx wrangler tail --search "cache"
npx wrangler tail --search "CACHE_HIT"
npx wrangler tail --search "CACHE_MISS"
```

**View rate limiting:**
```bash
npx wrangler tail --search "rate"
npx wrangler tail --search "RATE_LIMIT"
```

### 4. Specific Feature Debugging

**CSV Import Debugging:**
```bash
npx wrangler tail --search "csv-gemini"           # All CSV import logs
npx wrangler tail --search "csv.*ERROR"           # CSV errors only
npx wrangler tail --search "csv.*batchId"         # CSV batch processing
```

**Batch Shelf Scan Debugging:**
```bash
npx wrangler tail --search "scan-bookshelf"       # All scan logs
npx wrangler tail --search "scan.*error"          # Scan errors
npx wrangler tail --search "gemini.*vision"       # Gemini vision processing
```

**Image Proxy Debugging:**
```bash
npx wrangler tail --search "/images/proxy"        # All image proxy requests
npx wrangler tail --search "cover.*error"         # Cover image errors
```

## Cloudflare Dashboard Access

### Direct URL Path

1. Go to: **https://dash.cloudflare.com/**
2. Select your account → domain
3. Navigate: **Workers & Pages → Overview → api-worker**
4. Click: **Deployments & logs**

### Dashboard Navigation Steps

**Real-time logs view:**
1. https://dash.cloudflare.com/ (sign in)
2. Workers & Pages (sidebar)
3. Click "api-worker"
4. Scroll down to "Real-time logs"
5. Logs stream in real-time

**Search & filter logs:**
1. In the Deployments & logs section
2. Use the "Search" box to filter by:
   - Endpoint: `/api/import/csv-gemini`
   - Job ID: `jobId=abc123`
   - Status: `202` or `500`
   - Provider: `provider=google-books`

**View recent deployments:**
1. Workers & Pages → api-worker
2. Click "Deployments" tab
3. See deployment history and status

## Advanced Filtering

### Piping Commands for Complex Queries

**Find errors with full context:**
```bash
npx wrangler tail --format json | jq '.logs[] | select(.level == "error" or .message | contains("error"))'
```

**Find all 202 responses with their request details:**
```bash
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("202"))'
```

**Extract structured metrics:**
```bash
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("provider")) | {provider: .message, timestamp: .timestamp}'
```

**Find all background jobs:**
```bash
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("jobId"))'
```

## Log Levels & Message Types

Your worker is configured with:
- `LOG_LEVEL = "DEBUG"`
- `STRUCTURED_LOGGING = "true"`
- All major events logged with context

### Expected Message Patterns

**Successful requests:**
```
GET /v1/search/title → 200 OK (cached: true)
GET /api/import/csv-gemini → 202 Accepted (jobId: abc123)
```

**Background task messages:**
```
[jobId: abc123] Enriching book 1/50...
[jobId: abc123] Gemini vision processing...
[jobId: abc123] Failed: PROVIDER_ERROR (code: 500)
```

**Error messages:**
```
ERROR: Invalid ISBN format
ERROR: Gemini API timeout (50000ms)
ERROR: KV write failed: quota exceeded
```

## Troubleshooting Commands

### CSV Import is Stuck

```bash
# 1. Check if job was started
npx wrangler tail --search "csv-gemini" --format pretty

# 2. Find the jobId
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("jobId")) | .message'

# 3. Check WebSocket DO status
npx wrangler tail --search "ProgressWebSocketDO"

# 4. Look for Gemini API errors
npx wrangler tail --search "gemini"
```

### Background Task Failures

```bash
# 1. Find the failed job
npx wrangler tail --search "ERROR"

# 2. Extract error details
npx wrangler tail --search "ERROR" --format json | jq '.logs[] | {message: .message, timestamp: .timestamp}'

# 3. Check if job was canceled
npx wrangler tail --search "canceled"
```

### Rate Limiting Issues

```bash
# Check if user is hitting rate limits
npx wrangler tail --search "rate"
npx wrangler tail --search "RATE_LIMIT"

# See which IPs are rate limited
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("rate")) | .message'
```

### Cache Issues

```bash
# Monitor cache hit/miss ratio
npx wrangler tail --search "CACHE"

# Debug specific cache entries
npx wrangler tail --search "cache.*title"
npx wrangler tail --search "cache.*isbn"
```

## Environment Variables Reference

From your `wrangler.toml`:

```
LOG_LEVEL = "DEBUG"
ENABLE_PERFORMANCE_LOGGING = "true"
ENABLE_CACHE_ANALYTICS = "true"
ENABLE_PROVIDER_METRICS = "true"
ENABLE_RATE_LIMIT_TRACKING = "true"
STRUCTURED_LOGGING = "true"
```

All events are logged with full context. To increase verbosity during debugging, you can temporarily modify these in wrangler.toml, but this is not needed—current settings capture everything.

## Alternative: Logpush / Analytics Engine

Your worker is configured with Analytics Engine datasets (not yet implemented, Phase 3+):

```
Dataset 1: books_api_performance      (general metrics)
Dataset 2: books_api_cache_metrics    (cache hit/miss)
Dataset 3: books_api_provider_performance (API provider costs)
Dataset 4: bookshelf_ai_performance   (AI processing metrics)
```

These can be queried via Cloudflare GraphQL API later. For now, use `wrangler tail` for real-time debugging.

## Performance Monitoring

Your worker has 3-minute CPU limit and 256MB memory. Check for timeouts:

```bash
# Find timeout errors
npx wrangler tail --search "timeout"
npx wrangler tail --search "CPU"
```

Resource limits in wrangler.toml:
- `cpu_ms = 180000` (3 minutes)
- `memory_mb = 256`
- Batch operations that exceed these will timeout

## Quick Reference Summary

| Task | Command |
|------|---------|
| Real-time logs | `npx wrangler tail` |
| Find CSV errors | `npx wrangler tail --search "csv-gemini"` |
| Find scan errors | `npx wrangler tail --search "scan-bookshelf"` |
| Find 202 responses | `npx wrangler tail --search "202"` |
| Find errors | `npx wrangler tail --search "ERROR"` |
| Search endpoint | `npx wrangler tail --search "/api/endpoint"` |
| JSON format | `npx wrangler tail --format json` |
| Pretty format | `npx wrangler tail --format pretty` |
| With jobId | `npx wrangler tail --search "jobId=xxx"` |
| Provider metrics | `npx wrangler tail --search "google-books"` |

## Next Steps

1. **Reproduce the CSV import failure:**
   ```bash
   npx wrangler tail --search "csv-gemini" --format pretty
   # Then trigger a CSV import from iOS app
   # Watch logs in real-time
   ```

2. **Reproduce the batch scan failure:**
   ```bash
   npx wrangler tail --search "scan-bookshelf" --format pretty
   # Then trigger a batch shelf scan from iOS app
   # Watch logs in real-time
   ```

3. **Extract the jobId:**
   ```bash
   npx wrangler tail --format json | jq '.logs[] | select(.message | contains("jobId")) | .message' | head -1
   ```

4. **Check WebSocket DO status for that job:**
   ```bash
   npx wrangler tail --search "[jobId]" --format pretty
   ```

This should give you full visibility into what's happening in your background tasks.
