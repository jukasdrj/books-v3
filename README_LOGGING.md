# Worker Logging - Quick Start Guide

You now have comprehensive documentation for viewing and debugging your Cloudflare Worker (`api-worker`). This is a quick overview of what was created and how to use it.

## What You Have

**5 Documentation Files** (48KB total):

1. **WORKER_LOGGING_QUICK_REFERENCE.md** (5.0K) - **START HERE**
   - One-page cheat sheet with copy-paste commands
   - Common searches for CSV, scan, and error debugging
   - Quick workflows for immediate debugging

2. **WORKER_LOGGING_GUIDE.md** (9.4K) - Complete Reference
   - All Wrangler CLI commands with options
   - Dashboard navigation path
   - Advanced filtering with jq
   - Alternative methods (Logpush, Analytics Engine)

3. **BACKGROUND_TASK_DEBUGGING.md** (12K) - Scenario-Based
   - Detailed troubleshooting for 202 → Background failures
   - CSV import failure scenarios
   - Batch shelf scan failure scenarios
   - Provider failures, WebSocket issues
   - Complete debugging workflows with commands

4. **LOGGING_EXAMPLES.md** (14K) - Real-World Examples
   - 5 actual debugging scenarios with logs
   - CSV stuck, enrichment timeout, Gemini fails, WebSocket closes, rate limited
   - Step-by-step reproduction and analysis
   - Resolution for each scenario

5. **LOGGING_DOCUMENTATION_INDEX.md** (8.6K) - Navigation
   - Overview of all documentation
   - How to use these docs by scenario
   - File locations and quick links
   - Understanding 202 responses & background tasks

## Immediate Commands

You already have a `/logs` slash command. Use it now:

```bash
/logs                                    # Real-time logs
/logs --search "csv-gemini"              # Filter CSV import
/logs --search "scan-bookshelf"          # Filter batch scan
/logs --search "ERROR"                   # Find errors
```

Or use `wrangler tail` directly:

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
npx wrangler tail                        # Real-time logs
npx wrangler tail --search "csv-gemini"  # CSV import
npx wrangler tail --search "ERROR"       # Errors
```

## Common Scenarios → Document Mapping

| Your Situation | Read This | Command |
|---|---|---|
| CSV import never starts | BACKGROUND_TASK_DEBUGGING.md → Scenario 1 | `npx wrangler tail --search "csv-gemini"` |
| CSV enrichment fails/timeouts | BACKGROUND_TASK_DEBUGGING.md → Scenario 2 | `npx wrangler tail --search "enrichment"` |
| Batch scan stuck | BACKGROUND_TASK_DEBUGGING.md → Batch Scan | `npx wrangler tail --search "scan-bookshelf"` |
| Gemini AI errors | LOGGING_EXAMPLES.md → Example 3 | `npx wrangler tail --search "gemini"` |
| WebSocket never connects | LOGGING_EXAMPLES.md → Example 4 | `npx wrangler tail --search "WebSocket"` |
| Rate limiting happening | LOGGING_EXAMPLES.md → Example 5 | `npx wrangler tail --search "429"` |
| I need all available commands | WORKER_LOGGING_GUIDE.md | - |
| I need to understand architecture | BACKGROUND_TASK_DEBUGGING.md → Architecture | - |
| I'm stuck and don't know where to start | WORKER_LOGGING_QUICK_REFERENCE.md → When Stuck | - |

## File Locations

All files are in your project root:

```
/Users/justingardner/Downloads/xcode/books-tracker-v1/
├── README_LOGGING.md                   ← This file
├── WORKER_LOGGING_QUICK_REFERENCE.md   ← Start here
├── WORKER_LOGGING_GUIDE.md             ← Complete reference
├── BACKGROUND_TASK_DEBUGGING.md        ← Scenarios & troubleshooting
├── LOGGING_EXAMPLES.md                 ← Real-world examples
├── LOGGING_DOCUMENTATION_INDEX.md      ← Navigation guide
│
└── cloudflare-workers/api-worker/
    └── wrangler.toml                   ← Worker config
```

## The Most Important Concept

Your CSV import and batch shelf scan return **202 Accepted** immediately, then process **asynchronously in the background**.

This means:
- iOS gets 202 response instantly
- Real work happens 1-5 minutes later
- Logs appear at different times:
  - "202" log appears immediately
  - Processing logs appear 1-5 minutes later
  - Don't expect everything in first 10 seconds!

See **BACKGROUND_TASK_DEBUGGING.md** → "Architecture Overview" for detailed explanation.

## Step-by-Step Debugging

### For CSV Import Issues:

```bash
# 1. Start watching logs
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
npx wrangler tail --search "csv-gemini" --format pretty

# 2. Trigger CSV import from iOS app

# 3. Watch logs appear in real-time
# Look for: "[jobId: abc123]" messages and any ERROR lines

# 4. If stuck, extract jobId and drill deeper
JOB_ID="550e8400-e29b-41d4-a716-446655440000"  # From logs
npx wrangler tail --search "$JOB_ID" --format pretty
```

### For Batch Scan Issues:

```bash
# 1. Start watching logs
npx wrangler tail --search "scan-bookshelf" --format pretty

# 2. Trigger batch scan from iOS app

# 3. Watch for Gemini vision processing or enrichment failures

# 4. If Gemini fails, check image format
npx wrangler tail --search "image" --format pretty
```

## Key Log Patterns

When reading logs, look for these patterns:

```
[jobId: abc123]          ← All logs for one job
ERROR                    ← Something went wrong
202 Accepted             ← Job was queued
Processing...            ← Background work happening
Enriching book X/Y       ← Progress of enrichment
Gemini API error         ← Specific provider failure
WebSocket connected      ← iOS connected for updates
Rate limit exceeded      ← Hitting 10 req/min limit
timeout                  ← Operation took too long
```

## Understanding 202 Responses

When CSV import or batch scan returns 202:

```
Request Timeline:
0s       | iOS sends POST to /api/import/csv-gemini
0.1s     | Worker receives request
0.2s     | Worker queues job via ProgressWebSocketDO
0.3s     | Worker returns 202 Accepted + jobId to iOS
0.3s     | iOS connects WebSocket with jobId
1-300s   | Background task processes, sends progress updates via WebSocket
300s+    | Task completes, iOS shows final results
```

**Result:** All logs appear between 0.1s and 300s, but most appear 1-5 minutes after the 202 response.

## Dashboard Alternative

If CLI isn't convenient:

1. Open https://dash.cloudflare.com
2. Go to: **Workers & Pages → api-worker**
3. Scroll down: **"Real-time logs"** section
4. Search: Use the search box to filter

Note: CLI is much faster than dashboard for debugging.

## Testing Your Setup

Quick test to verify everything is working:

```bash
# Test 1: Can you see logs?
npx wrangler tail --format pretty | head -10

# Test 2: Can you search?
npx wrangler tail --search "ERROR" --format pretty

# Test 3: Can you get JSON?
npx wrangler tail --format json | jq '.logs[0]'
```

If all 3 work, you're good to go!

## Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| No logs appearing | Worker not deployed, try `npx wrangler deploy` |
| Authentication error | Run `npx wrangler login` |
| Wrong worker | Make sure you're in `/cloudflare-workers/api-worker` |
| Slow logs | Dashboard shows logs slower; use CLI instead |
| Logs from wrong time | Use `--search` to filter to recent events |

## What's Next?

1. **Read:** WORKER_LOGGING_QUICK_REFERENCE.md (5 minutes)
2. **Try:** Run `npx wrangler tail --search "csv-gemini"` and trigger CSV import
3. **Analyze:** Watch logs appear in real-time, identify issues
4. **Drill:** Use scenarios from BACKGROUND_TASK_DEBUGGING.md to troubleshoot
5. **Debug:** Use real-world examples from LOGGING_EXAMPLES.md for specific issues

## Support

If you're still stuck:

1. Read the scenario from BACKGROUND_TASK_DEBUGGING.md that matches your issue
2. Follow the exact commands provided
3. Collect logs: `npx wrangler tail --format json > /tmp/logs.json`
4. Create GitHub issue with reproduction steps + logs file

---

## Summary

You have everything you need to:
- View real-time worker logs
- Search and filter logs
- Debug CSV import failures
- Debug batch scan failures
- Understand why things timeout
- See rate limiting in action
- Monitor enrichment progress
- Identify Gemini AI errors
- Check WebSocket connectivity

Start with **WORKER_LOGGING_QUICK_REFERENCE.md** → then refer to specific guides as needed.

**Good luck! You've got this.**

---

**Created:** 2025-11-04 | **Worker:** api-worker (monolith)
