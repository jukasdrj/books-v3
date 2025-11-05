# Worker Logging - Quick Reference Card

**Worker:** `api-worker` | **Location:** `/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker`

## Essential Commands

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker

# Real-time logs
npx wrangler tail

# Search logs
npx wrangler tail --search "TERM"

# JSON format (for piping)
npx wrangler tail --format json

# Pretty format
npx wrangler tail --format pretty
```

## Common Searches

| Task | Command |
|------|---------|
| **CSV import** | `npx wrangler tail --search "csv-gemini"` |
| **Batch scan** | `npx wrangler tail --search "scan-bookshelf"` |
| **All errors** | `npx wrangler tail --search "ERROR"` |
| **202 responses** | `npx wrangler tail --search "202"` |
| **Specific endpoint** | `npx wrangler tail --search "/api/import/csv-gemini"` |
| **Gemini AI** | `npx wrangler tail --search "gemini"` |
| **Google Books** | `npx wrangler tail --search "google-books"` |
| **WebSocket** | `npx wrangler tail --search "WebSocket"` |
| **Rate limit** | `npx wrangler tail --search "429"` |
| **Job ID** | `npx wrangler tail --search "jobId=abc123"` |

## Debugging Workflows

### CSV Import Stuck?
```bash
npx wrangler tail --search "csv-gemini" --format pretty
# Watch for: "202 Accepted" + "jobId" + processing logs
# If no processing: Check WebSocket DO status
```

### Batch Scan Failed?
```bash
npx wrangler tail --search "scan-bookshelf" --format pretty
# Watch for: Gemini vision errors, enrichment failures
# If Gemini fails: Check image format & size
```

### Find Job Failures?
```bash
# 1. Get recent jobId
JOB_ID=$(npx wrangler tail --format json | jq -r '.logs[] | select(.message | contains("jobId:")) | .message | match("[a-f0-9-]{36}") | .string' | head -1)

# 2. See all logs for that job
npx wrangler tail --search "$JOB_ID" --format pretty
```

## Dashboard Access

**URL:** https://dash.cloudflare.com/
1. Workers & Pages → api-worker
2. Scroll to "Real-time logs"
3. Use search box to filter

(CLI is faster than dashboard for debugging)

## Environment

From `wrangler.toml`:
- Worker name: `api-worker`
- Log level: `DEBUG` (all events captured)
- Structured logging: `true`
- Rate limit: 10 req/min per IP
- CPU limit: 3 minutes
- Memory: 256 MB
- DO: ProgressWebSocketDO (WebSocket comms)

## File Locations

| File | Path |
|------|------|
| **This guide** | `/Users/justingardner/Downloads/xcode/books-tracker-v1/WORKER_LOGGING_GUIDE.md` |
| **Background task guide** | `/Users/justingardner/Downloads/xcode/books-tracker-v1/BACKGROUND_TASK_DEBUGGING.md` |
| **Worker code** | `/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker/src/` |
| **Config** | `/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker/wrangler.toml` |

## Endpoints Reference

| Endpoint | Returns | Purpose |
|----------|---------|---------|
| `POST /api/import/csv-gemini` | 202 | Start CSV import job |
| `POST /api/scan-bookshelf/batch` | 202 | Start batch scan job |
| `GET /ws/progress?jobId=xxx` | WebSocket | Real-time progress updates |
| `POST /api/enrichment/cancel` | 200 | Cancel background job |
| `GET /v1/search/title?q=xxx` | 200 | Title search (cached) |
| `GET /v1/search/isbn?isbn=xxx` | 200 | ISBN lookup |
| `GET /health` | 200 | Worker health |

## Error Codes to Search

```
ERROR  = General error
500    = Server error (check logs for cause)
429    = Rate limited (10 req/min)
400    = Bad request (invalid input)
202    = Accepted (background job queued)
timeout = CPU/timeout limit hit
```

## Tips

1. **Start tail first, then trigger action** - Don't start tail after action (logs may be missed)
2. **Use jobId for focus** - When you have a jobId, filter all logs by it
3. **Check for 202 first** - Means request was accepted, check background logs next
4. **WebSocket = real-time updates** - iOS uses WebSocket to get progress, check DO logs if stuck
5. **Gemini = expensive** - Vision API takes 25-40s per image, watch for timeout errors

## One-Liners

```bash
# Watch CSV import in real-time
npx wrangler tail --search "csv" --format pretty

# Find last error
npx wrangler tail --format json | jq '.logs[] | select(.level == "error") | .message' | head -1

# Count API requests per minute
npx wrangler tail --format json | jq '[.logs[] | .timestamp] | length'

# See all 202 responses (background jobs)
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("202")) | .message'

# Extract all jobIds
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("jobId")) | .message'

# Watch for Gemini errors only
npx wrangler tail --search "gemini.*ERROR" --format pretty
```

## When Stuck

1. Check `/WORKER_LOGGING_GUIDE.md` for detailed commands
2. Check `/BACKGROUND_TASK_DEBUGGING.md` for specific scenarios
3. Open issue on GitHub with:
   ```bash
   # Collect logs for report
   npx wrangler tail --search "csv-gemini" --format json > /tmp/logs.json
   ```
4. Post `logs.json` + steps to reproduce

---

**Last Updated:** 2025-11-04 | **Worker Version:** api-worker (monolith)
