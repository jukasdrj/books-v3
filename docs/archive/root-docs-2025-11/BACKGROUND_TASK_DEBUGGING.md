# Background Task Debugging Guide

Detailed troubleshooting for CSV import and batch shelf scan failures (202 Accepted → Background Processing).

## Architecture Overview

Both features follow the same pattern:
1. iOS → POST request → Worker returns **202 Accepted** + `jobId`
2. Worker creates async background task (via ProgressWebSocketDO)
3. iOS WebSocket connects to DO: `wss://api-worker.domain/ws/progress?jobId={jobId}`
4. Background task processes, sends updates via WebSocket
5. Task succeeds/fails, DO sends final status

**Key:** Logs appear across three components:
- Worker request logs (the 202 response)
- Background task logs (async processing)
- DO logs (WebSocket communication)

All are accessible via `wrangler tail`.

## CSV Import Failure Debugging

### Scenario 1: CSV Processing Never Starts

**Symptom:** iOS gets 202 OK, but no progress messages via WebSocket.

**Debug steps:**

```bash
# 1. Confirm 202 response was sent
npx wrangler tail --search "csv-gemini" --format pretty
# Look for: "POST /api/import/csv-gemini → 202"

# 2. Extract jobId from logs
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("csv-gemini")) | .message'

# 3. Check if WebSocket connection was established
npx wrangler tail --search "WebSocket.*csv"
# Look for: "WebSocket connected" or connection errors

# 4. Check if background task was queued
npx wrangler tail --search "enqueue.*csv"
```

**Common causes:**
- Worker crashed before queuing background task → Check for runtime errors
- WebSocket DO initialization failed → Check DO logs
- Network issue between iOS and WebSocket → Check worker logs for connection errors

### Scenario 2: CSV Processing Starts, Then Fails

**Symptom:** iOS gets updates, then connection closes with error.

```bash
# 1. Watch full CSV import lifecycle
npx wrangler tail --search "csv-gemini" --format pretty

# 2. Find the jobId
JOB_ID=$(npx wrangler tail --format json | jq -r '.logs[] | select(.message | contains("jobId:")) | .message | match("[a-f0-9-]{36}") | .string' | head -1)
echo "JobId: $JOB_ID"

# 3. Filter logs to this job only
npx wrangler tail --search "$JOB_ID" --format pretty

# 4. Look for phase-specific errors
npx wrangler tail --search "csv.*parsing"    # Phase 1: CSV parsing
npx wrangler tail --search "csv.*enriching"  # Phase 2: Enrichment
npx wrangler tail --search "csv.*ERROR"      # Any errors
```

**Expected flow:**
```
[jobId: abc123] CSV parsing started
[jobId: abc123] Parsed 45 rows successfully
[jobId: abc123] Starting enrichment phase (45 books)
[jobId: abc123] Enriching book 1/45... (title: "The Great Gatsby")
[jobId: abc123] Book 1 complete (ISBN: 9780743273565)
...
[jobId: abc123] Enrichment complete: 45/45 succeeded
[jobId: abc123] Final status: COMPLETE
```

**If you see errors:**

```
[jobId: abc123] ERROR during parsing: File size exceeds 10MB
[jobId: abc123] ERROR: Invalid CSV format
[jobId: abc123] ERROR: Gemini API timeout
[jobId: abc123] ERROR: KV quota exceeded
```

### Scenario 3: CSV Parsing Succeeds, Enrichment Fails

**Symptom:** Books appear in library, but with missing data (no cover, no author, etc.).

```bash
# Check enrichment phase specifically
npx wrangler tail --search "enrichment" --format pretty | grep -A 5 -B 5 "ERROR"

# Check Gemini API errors
npx wrangler tail --search "gemini"

# Check if job was canceled mid-enrichment
npx wrangler tail --search "canceled"

# Check R2 write failures (cover image storage)
npx wrangler tail --search "R2.*error"
```

**Root causes:**
- Gemini API rate limiting → See "Provider Failures" section below
- R2 bucket quota exceeded → Cost issue, check Cloudflare billing
- Book enrichment quota exceeded → Limited enrichment requests per minute
- Network timeout → Increase timeout in wrangler.toml (currently 50s)

## Batch Shelf Scan Failure Debugging

### Scenario 1: Scan Never Starts Processing

**Symptom:** iOS returns 202 OK, uploads complete, but no Gemini processing begins.

```bash
# 1. Confirm upload succeeded
npx wrangler tail --search "scan-bookshelf" --format pretty

# 2. Check image storage
npx wrangler tail --search "R2.*bookshelf"

# 3. Confirm processing was queued
npx wrangler tail --search "gemini.*queue"
```

**Likely cause:** Worker crashed during image storage before queuing Gemini job.

### Scenario 2: Gemini Vision Processing Fails

**Symptom:** Images upload OK, but Gemini returns error (wrong format, corrupted image, etc.).

```bash
# Find Gemini-specific errors
npx wrangler tail --search "gemini.*error" --format pretty

# Extract detailed error
npx wrangler tail --search "vision" --format json | jq '.logs[] | select(.level == "error") | .message'

# Check image format validation
npx wrangler tail --search "image.*format"
```

**Common Gemini failures:**

```
ERROR: Image format not supported (only JPEG, PNG, GIF, WebP allowed)
  → Solution: iOS preprocessing needs to output supported format

ERROR: Image too small (minimum 32x32 pixels)
  → Solution: Minimum bookshelf photo size

ERROR: Content moderation (potentially unsafe content detected)
  → Solution: Image contains prohibited content, skip or resubmit

ERROR: Vision quota exceeded
  → Solution: Gemini API quota hit, wait and retry
```

### Scenario 3: Partial Results (Some Books Process, Some Fail)

**Symptom:** Scan completes but only 3 of 5 books detected, others in review queue.

```bash
# Check per-book processing
npx wrangler tail --search "scan.*book" --format pretty

# Find books below confidence threshold
npx wrangler tail --search "confidence"

# Check deduplication (same ISBN detected twice)
npx wrangler tail --search "dedup"
```

**Expected log flow:**
```
[jobId: scan123] Processing photo 1/5: IMG_001.jpg
[jobId: scan123] Gemini vision API call (50-70ms)
[jobId: scan123] Detected 12 books, 8 with high confidence (>0.7)
[jobId: scan123] Extracted ISBNs: [9780123456789, 9789876543210, ...]
[jobId: scan123] Deduplication: 1 duplicate found, 7 unique books
[jobId: scan123] Enriching 7 books...
[jobId: scan123] Book 1: "The Great Gatsby" enriched (cover: cached)
[jobId: scan123] Book 2: "1984" - low confidence (0.45), added to review queue
...
[jobId: scan123] Photo 1 complete: 7 books (1 in review queue)
[jobId: scan123] Processing photo 2/5...
```

## Provider Failures (Google Books, OpenLibrary)

### Scenario: Google Books Rate Limiting

**Symptom:** Random book enrichment failures with "quota exceeded" message.

```bash
# Check Google Books API errors
npx wrangler tail --search "google-books.*error"

# See rate limit status
npx wrangler tail --search "PROVIDER_ERROR"

# Check provider fallback logic
npx wrangler tail --search "openlibrary"  # Does it fall back to OpenLibrary?
```

**What to expect:**
```
[jobId: job123] Enriching book with Google Books API
[jobId: job123] ERROR: google-books API: 403 Forbidden (quota exceeded)
[jobId: job123] Falling back to OpenLibrary API
[jobId: job123] SUCCESS: openlibrary data enriched
```

**Cost implications:**
- Google Books: ~$0.01 per request (shared quota, 10K/day free)
- OpenLibrary: Free
- Current behavior: Falls back automatically, no cost overrun

### Scenario: All Providers Failing

**Symptom:** Books stuck in review queue, no enrichment data available.

```bash
# Check both provider failures
npx wrangler tail --search "google-books" | grep ERROR
npx wrangler tail --search "openlibrary" | grep ERROR

# Check if ISBNdb is available as 3rd provider
npx wrangler tail --search "isbndb"

# See what data is available from Gemini extraction
npx wrangler tail --search "gemini.*extracted"
```

**Root cause analysis:**
- Network connectivity issue → Check Worker logs for HTTP errors
- All provider APIs offline → Check Cloudflare Worker status page
- Credentials missing or expired → Check `GOOGLE_BOOKS_API_KEY` secret
- Rate limits on all providers → Wait 1 hour, retry

## WebSocket / Durable Object Issues

### Scenario 1: iOS Never Receives Progress Updates

**Symptom:** iOS connects to WebSocket but receives no messages before disconnect.

```bash
# 1. Verify WebSocket connection
npx wrangler tail --search "WebSocket.*connected"

# 2. Check DO initialization
npx wrangler tail --search "ProgressWebSocketDO.*init"

# 3. Look for connection errors
npx wrangler tail --search "WebSocket.*error"

# 4. Check message sending
npx wrangler tail --search "sendMessage"
```

**Verify DO is running:**
```bash
# Check Durable Object status
npx wrangler tail --search "DurableObject"

# Verify jobId state was stored
npx wrangler tail --search "storage.*set"
```

### Scenario 2: WebSocket Connection Closes Unexpectedly

**Symptom:** iOS receives 2-3 updates, then connection drops.

```bash
# Check connection lifecycle
npx wrangler tail --search "WebSocket" --format pretty

# See disconnect reason
npx wrangler tail --search "close\|disconnect"

# Check if Worker crashed
npx wrangler tail --search "Error\|exception" | head -20
```

**Reasons for disconnect:**
- Worker process restarted → Normal, expected behavior
- Memory quota exceeded → Check memory usage in logs
- DO storage write failed → KV quota issue
- iOS closed connection → Check iOS logs for errors

## Cost Investigation (Rate Limiting)

Both features are rate-limited to prevent wallet attacks:

```bash
# Check rate limiting
npx wrangler tail --search "rate"

# See per-IP tracking
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("rate")) | {ip: .message, timestamp: .timestamp}'
```

Your configuration:
- 10 requests/minute per IP (includes all endpoints)
- Protected endpoints: `/api/import/*`, `/api/scan-bookshelf/*`, `/api/enrichment/*`

If iOS is hitting rate limits, it will get `429 Too Many Requests`. Check:
```bash
npx wrangler tail --search "429"
```

## Complete Debugging Workflow

### For CSV Import Failure:

```bash
# Step 1: Start tail in separate terminal (leave running)
npx wrangler tail --search "csv-gemini" --format pretty

# Step 2: Trigger CSV import from iOS (upload file)

# Step 3: Watch logs appear in real-time, find jobId
# Look for: "[jobId: abc123] CSV parsing started"

# Step 4: If it fails, extract full logs
JOB_ID="abc123"  # Replace with actual from logs
npx wrangler tail --search "$JOB_ID" --format json > /tmp/job_logs.json

# Step 5: Analyze phases
cat /tmp/job_logs.json | jq '.logs[] | select(.message | contains("parsing")) | .message'
cat /tmp/job_logs.json | jq '.logs[] | select(.message | contains("enriching")) | .message'
cat /tmp/job_logs.json | jq '.logs[] | select(.message | contains("ERROR")) | .message'
```

### For Batch Scan Failure:

```bash
# Step 1: Start tail
npx wrangler tail --search "scan-bookshelf" --format pretty

# Step 2: Trigger batch scan from iOS (capture photos)

# Step 3: Watch for jobId and phase logs

# Step 4: If Gemini fails
npx wrangler tail --search "gemini" --format pretty | tail -50

# Step 5: If enrichment fails
npx wrangler tail --search "enrichment" --format pretty | tail -50
```

## Dashboard Alternative

If CLI is not convenient:

1. Open **https://dash.cloudflare.com**
2. **Workers & Pages → api-worker**
3. **Scroll to "Real-time logs"**
4. Manual search in dashboard (less powerful than CLI)

Dashboard is slower than CLI for debugging, so use `wrangler tail` when possible.

## Performance Tuning

Your worker has:
- CPU limit: 180 seconds (3 minutes)
- Memory: 256 MB
- Batch processing: Up to 50 books per CSV, 5 photos per scan

If you're hitting CPU limits, check logs for slow operations:

```bash
# Find slow operations
npx wrangler tail --format json | jq '.logs[] | select(.duration > 5000) | {message: .message, duration: .duration}'
```

Common slow operations:
- Gemini vision API: 25-40 seconds per image (normal)
- Image upload to R2: 2-5 seconds per image
- Database enrichment: 1-2 seconds per book
- Total for 50 books: 60-120 seconds (within 180s limit)

## Summary: Where to Look First

| Problem | Command |
|---------|---------|
| CSV didn't start | `npx wrangler tail --search "csv-gemini"` |
| CSV parsing failed | `npx wrangler tail --search "parsing"` |
| Enrichment stuck | `npx wrangler tail --search "enrichment"` |
| Gemini failing | `npx wrangler tail --search "gemini"` |
| WebSocket disconnected | `npx wrangler tail --search "WebSocket"` |
| Rate limited | `npx wrangler tail --search "429"` |
| Background task never ran | `npx wrangler tail --search "202"` |

Start with the command above for your specific issue, then drill deeper with the scenarios in this guide.
