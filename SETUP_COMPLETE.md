# Worker Logging Setup - COMPLETE

Your Cloudflare Worker logging documentation is ready to use. All files have been created and verified.

## What Was Created

**6 Documentation Files** (57.3 KB total):

```
README_LOGGING.md                           (8.2 KB)  ← START HERE
WORKER_LOGGING_QUICK_REFERENCE.md           (5.0 KB)  ← 1-page cheat sheet
WORKER_LOGGING_GUIDE.md                     (9.4 KB)  ← Complete reference
BACKGROUND_TASK_DEBUGGING.md                (12.3 KB) ← Scenario-based troubleshooting
LOGGING_EXAMPLES.md                         (13.8 KB) ← 5 real-world examples
LOGGING_DOCUMENTATION_INDEX.md              (8.6 KB)  ← Navigation guide
VERIFY_LOGGING_SETUP.sh                     (script)  ← Verification script
```

All files are in your project root:
`/Users/justingardner/Downloads/xcode/books-tracker-v1/`

## Start Here

**Option 1: Quick Start (10 minutes)**
```bash
cat /Users/justingardner/Downloads/xcode/books-tracker-v1/README_LOGGING.md
```

**Option 2: One-Page Cheat Sheet (5 minutes)**
```bash
cat /Users/justingardner/Downloads/xcode/books-tracker-v1/WORKER_LOGGING_QUICK_REFERENCE.md
```

## Immediate Commands

```bash
# Navigate to worker
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker

# View real-time logs
npx wrangler tail

# Filter by search term
npx wrangler tail --search "csv-gemini"      # CSV import
npx wrangler tail --search "scan-bookshelf"  # Batch scan
npx wrangler tail --search "ERROR"           # Errors
npx wrangler tail --search "429"             # Rate limiting

# Or use the slash command (already configured)
/logs
/logs --search "csv-gemini"
```

## Document Map

| Scenario | Document |
|----------|----------|
| I want quick commands | WORKER_LOGGING_QUICK_REFERENCE.md |
| I want complete reference | WORKER_LOGGING_GUIDE.md |
| CSV import is failing | BACKGROUND_TASK_DEBUGGING.md → Scenario 1, 2 |
| Batch scan is failing | BACKGROUND_TASK_DEBUGGING.md → Batch Scan |
| I need real examples | LOGGING_EXAMPLES.md |
| I'm lost | README_LOGGING.md |
| Navigation | LOGGING_DOCUMENTATION_INDEX.md |

## Key Takeaways

### 1. Understanding 202 Responses

CSV import and batch shelf scan return **202 Accepted** immediately, but process asynchronously:

```
Timeline:
0s       → iOS sends POST request
0.3s     → Worker returns 202 Accepted + jobId
0.3s     → iOS connects WebSocket to get real-time updates
1-300s   → Background task processes (logs appear here)
300s+    → Task completes, iOS shows results
```

**Important:** Don't expect all logs to appear immediately. Processing takes 1-5 minutes!

### 2. Finding Background Task Logs

All logs for one job are grouped by jobId:

```bash
# Extract jobId from first log
JOB_ID=$(npx wrangler tail --format json | jq -r '.logs[] | select(.message | contains("jobId:")) | .message | grep -oE "[a-f0-9-]{36}" | head -1)

# Filter all logs for that job
npx wrangler tail --search "$JOB_ID" --format pretty
```

### 3. Log Patterns to Look For

```
[jobId: abc123]          ← All logs for one operation
ERROR                    ← Something failed
202 Accepted             ← Background job queued
Processing...            ← Task is running
Gemini API error         ← Specific provider failure
WebSocket connected      ← iOS successfully connected
Rate limit exceeded      ← Hitting rate limits
timeout                  ← Operation too slow
```

## Wrangler CLI Reference

```bash
# Real-time logs (all)
npx wrangler tail

# Search logs
npx wrangler tail --search "TERM"

# Pretty format (colored)
npx wrangler tail --format pretty

# JSON format (for piping)
npx wrangler tail --format json

# Specific endpoint
npx wrangler tail --search "/api/import/csv-gemini"

# Error logs
npx wrangler tail --search "ERROR"

# Background jobs (202 responses)
npx wrangler tail --search "202"

# Rate limiting
npx wrangler tail --search "429"

# Provider API errors
npx wrangler tail --search "google-books"
npx wrangler tail --search "openlibrary"
npx wrangler tail --search "gemini"
```

## Dashboard Alternative

If you prefer the Cloudflare dashboard:

1. Go to: https://dash.cloudflare.com
2. Navigate: Workers & Pages → api-worker
3. Scroll to: "Real-time logs"
4. Search: Use the search box to filter

Note: CLI is faster and more powerful than dashboard.

## Debugging Workflow

### For CSV Import Issues:

```bash
# 1. Start watching logs
npx wrangler tail --search "csv-gemini" --format pretty

# 2. Trigger CSV import from iOS app

# 3. Watch logs appear in real-time

# 4. If stuck, extract jobId and drill deeper
JOB_ID="550e8400-..."
npx wrangler tail --search "$JOB_ID" --format pretty

# 5. Reference BACKGROUND_TASK_DEBUGGING.md for scenario
```

### For Batch Scan Issues:

```bash
# 1. Start watching logs
npx wrangler tail --search "scan-bookshelf" --format pretty

# 2. Trigger batch scan from iOS app

# 3. Watch for Gemini vision processing or enrichment errors

# 4. If Gemini fails, check image format
npx wrangler tail --search "image" --format pretty
```

## Verification

Run the verification script to confirm everything is set up:

```bash
bash /Users/justingardner/Downloads/xcode/books-tracker-v1/VERIFY_LOGGING_SETUP.sh
```

Expected output:
```
✓ All documentation files present (6/6)
✓ wrangler.toml found
✓ src/index.js found
✓ wrangler CLI installed
✓ Worker name: api-worker
✓ Log level: DEBUG
✓ Structured logging: enabled
✓ Durable Object binding: ProgressWebSocketDO
```

## Worker Configuration

From `/cloudflare-workers/api-worker/wrangler.toml`:

```toml
name = "api-worker"
main = "src/index.js"
LOG_LEVEL = "DEBUG"
STRUCTURED_LOGGING = "true"
ENABLE_PERFORMANCE_LOGGING = "true"
ENABLE_CACHE_ANALYTICS = "true"
ENABLE_PROVIDER_METRICS = "true"
ENABLE_RATE_LIMIT_TRACKING = "true"

# Limits
cpu_ms = 180000        # 3 minutes
memory_mb = 256

# Durable Objects
[[durable_objects.bindings]]
name = "PROGRESS_WEBSOCKET_DO"
class_name = "ProgressWebSocketDO"

# Rate limiting
Rate limit: 10 requests/minute per IP
```

## Common Issues

| Issue | Solution |
|-------|----------|
| No logs appearing | Worker not deployed; run `npx wrangler deploy` |
| Authentication error | Run `npx wrangler login` |
| Wrong worker | Verify you're in `/cloudflare-workers/api-worker` |
| Slow logs | Dashboard is slower; use CLI instead |
| Lost in docs | Start with README_LOGGING.md |

## Getting Help

If you're stuck after reading the docs:

1. **Identify your scenario** in BACKGROUND_TASK_DEBUGGING.md
2. **Follow the exact commands** provided in that section
3. **Collect logs** if you need to report an issue:
   ```bash
   npx wrangler tail --format json > /tmp/logs.json
   ```
4. **Create GitHub issue** with reproduction steps + logs

## File Locations (for reference)

```
/Users/justingardner/Downloads/xcode/books-tracker-v1/
├── README_LOGGING.md                      ← Start here
├── WORKER_LOGGING_QUICK_REFERENCE.md      ← Cheat sheet
├── WORKER_LOGGING_GUIDE.md                ← Complete reference
├── BACKGROUND_TASK_DEBUGGING.md           ← Troubleshooting
├── LOGGING_EXAMPLES.md                    ← Real examples
├── LOGGING_DOCUMENTATION_INDEX.md         ← Navigation
├── VERIFY_LOGGING_SETUP.sh                ← Verification
│
└── cloudflare-workers/
    └── api-worker/
        ├── wrangler.toml                  ← Configuration
        ├── src/
        │   └── index.js                   ← Worker code
        └── node_modules/wrangler/         ← CLI tool
```

## Next Steps

1. **Read:** `/Users/justingardner/Downloads/xcode/books-tracker-v1/README_LOGGING.md` (or QUICK_REFERENCE.md for speed)
2. **Run:** `npx wrangler tail --search "csv-gemini"` in your terminal
3. **Test:** Trigger CSV import or batch scan from iOS app
4. **Watch:** Logs appear in real-time as processing happens
5. **Debug:** Reference the appropriate scenario doc when you hit issues
6. **Drill:** Use the exact commands provided in the scenario docs

---

**Setup Status:** COMPLETE AND VERIFIED

All documentation files are in place, all commands are ready to use, and verification script confirms proper setup.

You're ready to debug your worker! Start with README_LOGGING.md.

---

**Created:** 2025-11-04
**Worker:** api-worker (monolith, Cloudflare Workers)
**Documentation:** 57.3 KB across 6 files + verification script
