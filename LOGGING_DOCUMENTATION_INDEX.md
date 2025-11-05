# Worker Logging Documentation Index

Complete reference for accessing and debugging Cloudflare Worker (`api-worker`) logs, with focus on CSV import and batch shelf scan failures.

## Documentation Files

### 1. WORKER_LOGGING_QUICK_REFERENCE.md (START HERE)
**Purpose:** One-page cheat sheet for daily debugging

- Essential commands (copy-paste ready)
- Common searches (CSV, scan, errors)
- Quick debugging workflows
- Dashboard access path
- Tips for faster debugging

**Use when:** You need to quickly find logs for a specific issue

### 2. WORKER_LOGGING_GUIDE.md (COMPREHENSIVE)
**Purpose:** Complete reference for all logging capabilities

- Wrangler CLI commands with all flags
- Cloudflare Dashboard navigation
- Real-time tailing vs historical logs
- Advanced filtering with jq piping
- Performance monitoring
- Alternative access methods (Logpush, Analytics Engine)

**Use when:** You need to understand all available options

### 3. BACKGROUND_TASK_DEBUGGING.md (SCENARIO-BASED)
**Purpose:** Detailed troubleshooting for 202 Accepted → Background failures

- Architecture overview (how 202 responses work)
- CSV import failure scenarios
- Batch shelf scan failure scenarios
- Provider failure debugging (Google Books, OpenLibrary)
- WebSocket/Durable Object issues
- Complete debugging workflows with commands

**Use when:** CSV import or batch scan is failing and you need step-by-step troubleshooting

## Quick Links by Issue

| Issue | Document | Command |
|-------|----------|---------|
| CSV import stuck | BACKGROUND_TASK_DEBUGGING.md | `npx wrangler tail --search "csv-gemini"` |
| Batch scan failed | BACKGROUND_TASK_DEBUGGING.md | `npx wrangler tail --search "scan-bookshelf"` |
| Unknown error | WORKER_LOGGING_QUICK_REFERENCE.md | `npx wrangler tail --search "ERROR"` |
| Rate limiting | WORKER_LOGGING_GUIDE.md | `npx wrangler tail --search "429"` |
| WebSocket disconnected | BACKGROUND_TASK_DEBUGGING.md | `npx wrangler tail --search "WebSocket"` |
| All errors | WORKER_LOGGING_QUICK_REFERENCE.md | `npx wrangler tail --search "ERROR"` |

## How to Use These Docs

### Scenario 1: "CSV Import Failed"
1. Read: BACKGROUND_TASK_DEBUGGING.md - "CSV Import Failure Debugging"
2. Follow: "Scenario 2: CSV Processing Starts, Then Fails"
3. Run: Commands in that section
4. Extract: jobId from logs
5. Filter: All logs by jobId to see full lifecycle

### Scenario 2: "What Commands Are Available?"
1. Read: WORKER_LOGGING_GUIDE.md - "Wrangler CLI Commands"
2. Reference: Table of commands with descriptions
3. Copy-paste: Command for your use case

### Scenario 3: "I'm Stuck, Where Do I Look?"
1. Read: WORKER_LOGGING_QUICK_REFERENCE.md - "When Stuck"
2. Follow: Step-by-step guide
3. Use: One-liners for common queries
4. Drill deeper: Reference the other docs as needed

## File Locations

All documentation in project root:

```
/Users/justingardner/Downloads/xcode/books-tracker-v1/
├── LOGGING_DOCUMENTATION_INDEX.md          ← This file (navigation)
├── WORKER_LOGGING_QUICK_REFERENCE.md       ← Quick cheat sheet
├── WORKER_LOGGING_GUIDE.md                 ← Complete reference
├── BACKGROUND_TASK_DEBUGGING.md            ← Scenario-based troubleshooting
│
└── cloudflare-workers/
    ├── api-worker/
    │   ├── wrangler.toml                   ← Configuration
    │   └── src/
    │       ├── index.js                    ← Main worker
    │       ├── handlers/                   ← Request handlers
    │       ├── services/                   ← Business logic
    │       └── durable-objects/            ← WebSocket DO
    │
    └── MONOLITH_ARCHITECTURE.md            ← Worker architecture details
```

## Wrangler Commands Quick Start

```bash
# Navigate to worker
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker

# Real-time logs (all)
npx wrangler tail

# Filter logs
npx wrangler tail --search "csv-gemini"
npx wrangler tail --search "scan-bookshelf"
npx wrangler tail --search "ERROR"

# JSON format (for piping to jq)
npx wrangler tail --format json

# Pretty format (default)
npx wrangler tail --format pretty
```

## Slash Command Integration

Your project has a `/logs` slash command already configured:

```bash
/logs                                    # Stream logs with pretty formatting
/logs --search "gemini"                 # Filter by search term
/logs --status error                    # Filter errors only
```

This is a wrapper around `wrangler tail`. See `/logs` command reference for usage.

## Dashboard Alternative

If CLI is not convenient:

1. Go to: https://dash.cloudflare.com
2. Select your account
3. Navigate: **Workers & Pages → api-worker**
4. Scroll: "Real-time logs" section
5. Search: Use the search box to filter

**Note:** CLI (`wrangler tail`) is faster and more powerful than dashboard for debugging.

## Understanding 202 Responses & Background Tasks

Both CSV import and batch shelf scan use this pattern:

```
iOS App → POST /api/import/csv-gemini → Worker Returns 202 Accepted + jobId
         ↓
    Worker queues background task via ProgressWebSocketDO
         ↓
    iOS connects WebSocket: wss://api-worker.../ws/progress?jobId=xxx
         ↓
    Background task processes (enrichment, Gemini, etc.)
    Sends real-time updates via WebSocket
         ↓
    Task completes or fails, DO sends final status
```

**Key:** The 202 response is immediate. The actual work happens asynchronously in the background. Logs appear in multiple phases:
- Phase 1: Initial 202 response → Logs appear immediately
- Phase 2: Background processing → Logs appear 1-5 minutes later
- Phase 3: Final status → Logs appear at end of processing

See BACKGROUND_TASK_DEBUGGING.md for detailed architecture explanation.

## Log Levels & Environment

From `wrangler.toml`:

```
LOG_LEVEL = "DEBUG"                      # All events captured
STRUCTURED_LOGGING = "true"              # Logs include context/metadata
ENABLE_PERFORMANCE_LOGGING = "true"      # Performance metrics
ENABLE_CACHE_ANALYTICS = "true"          # Cache hit/miss tracking
ENABLE_PROVIDER_METRICS = "true"         # API provider metrics
ENABLE_RATE_LIMIT_TRACKING = "true"      # Rate limit tracking
```

Everything is logged. No need to adjust environment variables for debugging.

## Common Error Patterns

**Keep these patterns in mind when searching logs:**

```
[jobId: abc123]          - Job-scoped logs (all related to one job)
ERROR:                   - Error-level messages
WARNING:                 - Warning-level messages
[csv-gemini]             - Feature-specific logs
[gemini]                 - Gemini API calls
[google-books]           - Google Books API calls
[openlibrary]            - OpenLibrary API calls
[WebSocket]              - WebSocket/DO communication
[R2]                     - R2 bucket operations
[KV]                     - KV namespace operations
200, 201, 202, 4xx, 5xx  - HTTP status codes
timeout                  - Operation timeout
quota                    - Rate limit or quota issue
```

## Troubleshooting Path

```
1. Issue occurs (CSV fails, scan hangs, etc.)
   ↓
2. Read QUICK_REFERENCE.md for initial command
   ↓
3. Run wrangler tail with appropriate --search
   ↓
4. Find jobId in logs or identify error
   ↓
5. Drill deeper using BACKGROUND_TASK_DEBUGGING.md scenario
   ↓
6. If still stuck, reference WORKER_LOGGING_GUIDE.md for advanced options
   ↓
7. Collect logs and create GitHub issue with reproduction steps
```

## Key Takeaways

1. **Use CLI not dashboard** - `wrangler tail` is faster and more powerful
2. **Understand 202 responses** - Background tasks appear in logs 1-5 minutes later
3. **Always use jobId when available** - Filter by jobId to see full lifecycle of one operation
4. **Check phase-specific logs** - CSV has parsing + enrichment phases; scan has upload + Gemini + enrichment
5. **Look for provider failures** - Google Books and OpenLibrary failures are common
6. **WebSocket = real-time updates** - If iOS isn't getting updates, check ProgressWebSocketDO logs

## Support

If you're still stuck after reviewing these docs:

1. **Collect detailed logs:**
   ```bash
   npx wrangler tail --search "csv-gemini" --format json > /tmp/csv_logs.json
   # or
   npx wrangler tail --search "scan-bookshelf" --format json > /tmp/scan_logs.json
   ```

2. **Include in GitHub issue:**
   - Description of what you were doing
   - Steps to reproduce
   - The JSON logs file
   - Any error messages from iOS app logs

3. **Reference:** See `/BACKGROUND_TASK_DEBUGGING.md` - "Summary: Where to Look First" for quick diagnosis

---

**Updated:** 2025-11-04 | **Worker:** api-worker (monolith)

Next: Read WORKER_LOGGING_QUICK_REFERENCE.md for immediate commands
