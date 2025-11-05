# Worker Logging - Real-World Examples

Step-by-step examples of actual debugging sessions for CSV import and batch scan failures.

## Setup

All commands run from:
```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
```

Keep this terminal window open with logs streaming while you trigger actions from iOS app.

## Example 1: Debug CSV Import That Never Starts Processing

### Symptom
- iOS uploads CSV file
- Gets 202 response + jobId
- But no progress updates appear on iOS
- Books never appear in library

### Debugging Session

**Terminal 1: Start log stream**
```bash
npx wrangler tail --search "csv-gemini" --format pretty
```

**Terminal 2: Trigger CSV import from iOS**
- Open app → Settings → Import CSV (or Library → Import)
- Select `goodreads_library_export.csv`
- Upload completes, shows "Processing..."
- But progress bar stays at 0%

**Expected logs in Terminal 1:**
```
Request: POST /api/import/csv-gemini
Status: 202 Accepted
Body: { "jobId": "550e8400-e29b-41d4-a716-446655440000", "message": "CSV import job queued" }

[jobId: 550e8400] CSV parsing started
[jobId: 550e8400] File size: 45KB, rows: 89
[jobId: 550e8400] Parsed row 1: "The Great Gatsby", "F. Scott Fitzgerald"
[jobId: 550e8400] Parsed row 2: "1984", "George Orwell"
...
[jobId: 550e8400] CSV parsing complete: 89 rows
[jobId: 550e8400] Starting enrichment phase
```

**If you see nothing after "202 Accepted":**

This means the background task was never queued. Check for errors:

```bash
# Terminal 1: Stop current tail (Ctrl+C)
# Terminal 1: Show all errors in last 100 logs
npx wrangler tail --search "ERROR" --format pretty | head -50
```

Look for stack traces or error messages like:
```
ERROR: Failed to queue background task: Worker crashed
ERROR: ProgressWebSocketDO.put() failed: DO not responding
ERROR: KV write failed: quota exceeded
```

**If WebSocket connection failed:**

```bash
# Terminal 1: Check WebSocket logs
npx wrangler tail --search "WebSocket" --format pretty
```

Expected flow:
```
WebSocket connection from: 203.0.113.42
URL: wss://api-worker.domain/ws/progress?jobId=550e8400
Status: Connected
Subscribed to jobId: 550e8400
```

If you see `Connection closed` immediately, the DO initialization failed.

### Resolution

1. Check wrangler.toml for DO binding
2. Verify worker was deployed (check dashboard)
3. Look for "temporary failure" in logs (retry)
4. If persistent, redeploy: `npx wrangler deploy`

---

## Example 2: Debug CSV Enrichment Stuck Mid-Process

### Symptom
- CSV processing started (logs show parsing complete)
- Books appear in library with minimal data
- Enrichment stuck, no cover images, no detailed metadata

### Debugging Session

**Terminal 1: Tail enrichment logs**
```bash
npx wrangler tail --search "enrichment" --format pretty
```

**Trigger CSV import from iOS, watch logs:**

```
[jobId: 550e8400] CSV parsing complete: 89 rows
[jobId: 550e8400] Starting enrichment phase: 89 books
[jobId: 550e8400] Enriching book 1/89: "The Great Gatsby"
[jobId: 550e8400] Query: ISBN lookup for 9780743273565
[jobId: 550e8400] Google Books API: 200 OK (2.3s)
[jobId: 550e8400] Book 1 enriched: cover=true, authors=1

[jobId: 550e8400] Enriching book 2/89: "1984"
[jobId: 550e8400] Query: ISBN lookup for 9780451524935
[jobId: 550e8400] Google Books API: 200 OK (2.1s)
[jobId: 550e8400] Book 2 enriched: cover=true, authors=1

... (more books)

[jobId: 550e8400] Enriching book 47/89: "The Hobbit"
[jobId: 550e8400] Query: ISBN lookup for 9780547928227
[jobId: 550e8400] Google Books API: ERROR 403 Forbidden (quota exceeded)
[jobId: 550e8400] Falling back to OpenLibrary API
[jobId: 550e8400] OpenLibrary API: 200 OK (1.8s)
[jobId: 550e8400] Book 47 enriched: cover=false, authors=1

... (rest timeout)

[jobId: 550e8400] ERROR: CPU limit exceeded (180000ms)
[jobId: 550e8400] Enrichment aborted at book 73/89 (partial results)
```

### Analysis

**Observation 1: Google Books quota exceeded at book 47**
- Google Books has daily limits (~10K requests/day)
- Once quota hit, fallback to OpenLibrary (slower but free)
- No data loss, just slower processing

**Observation 2: CPU timeout at book 73**
- Processing 89 books took too long (>180 seconds)
- At ~2 seconds/book, 89 books ≈ 180 seconds ← Right at limit
- Enrichment aborted mid-process

**Check Google Books quota status:**
```bash
npx wrangler tail --search "google-books" --format pretty | grep -E "ERROR|quota|429"
```

Expected:
```
[jobId: 550e8400] Google Books API: 200 OK (2.3s)
[jobId: 550e8400] Google Books API: 200 OK (2.1s)
...
[jobId: 550e8400] Google Books API: ERROR 403 (quota exceeded)
```

### Resolution

**For quota issue:**
1. Google Books quota resets daily (UTC midnight)
2. Reduce CSV batch size (max ~60 books per import)
3. Switch to OpenLibrary-only mode (edit wrangler.toml)
4. Wait until tomorrow to upload remaining books

**For CPU timeout:**
1. Reduce batch size: 89 books → split into 45 + 44
2. Increase CPU limit: Edit wrangler.toml `cpu_ms = 300000` (5 min)
3. Optimize enrichment (currently 2s/book, target <1.5s/book)

---

## Example 3: Debug Batch Shelf Scan - Gemini Vision Fails

### Symptom
- Capture 5 bookshelf photos
- Upload completes (all 5 show in progress)
- Gemini processes first photo, then fails
- Only first photo shows results, rest stuck in review queue

### Debugging Session

**Terminal 1: Tail batch scan logs**
```bash
npx wrangler tail --search "scan-bookshelf" --format pretty
```

**Terminal 2: Optional - Tail Gemini-specific logs**
```bash
npx wrangler tail --search "gemini" --format pretty
```

**Trigger batch scan from iOS, watch logs:**

```
[jobId: scan123] Batch shelf scan started: 5 photos
[jobId: scan123] Uploading photo 1/5 (IMG_001.jpg, 512KB)
[jobId: scan123] Uploading photo 2/5 (IMG_002.jpg, 487KB)
[jobId: scan123] Uploading photo 3/5 (IMG_003.jpg, 521KB)
[jobId: scan123] Uploading photo 4/5 (IMG_004.jpg, 498KB)
[jobId: scan123] Uploading photo 5/5 (IMG_005.jpg, 508KB)
[jobId: scan123] All uploads complete (2.4s)

[jobId: scan123] Processing photo 1/5: IMG_001.jpg
[jobId: scan123] Calling Gemini 2.0 Flash vision API
[jobId: scan123] Gemini response: 12 books detected
[jobId: scan123] Extracted ISBNs: [9780123456789, 9876543210123, ...]
[jobId: scan123] Enriching 12 books from photo 1...
[jobId: scan123] Book 1: "The Great Gatsby" enriched (cover: cached)
[jobId: scan123] Book 2: "1984" enriched (cover: cached)
...
[jobId: scan123] Photo 1 complete: 12 books

[jobId: scan123] Processing photo 2/5: IMG_002.jpg
[jobId: scan123] Calling Gemini 2.0 Flash vision API
[jobId: scan123] ERROR: Gemini API returned 400 Bad Request
[jobId: scan123] Error message: "Invalid image format (expected JPEG or PNG)"
[jobId: scan123] Photo 2 skipped due to error
[jobId: scan123] Processing photo 3/5...
```

### Analysis

**The issue: Photo 2 is WebP format, Gemini expects JPEG/PNG**

iOS 26 sometimes exports photos as WebP (smaller, modern format). Gemini doesn't support WebP.

**Check image format issues:**
```bash
npx wrangler tail --search "image.*format" --format pretty
```

Expected output:
```
[jobId: scan123] Image validation: IMG_001.jpg = JPEG (OK)
[jobId: scan123] Image validation: IMG_002.jpg = WebP (ERROR)
[jobId: scan123] Image validation: IMG_003.jpg = WebP (ERROR)
[jobId: scan123] Image validation: IMG_004.jpg = JPEG (OK)
[jobId: scan123] Image validation: IMG_005.jpg = PNG (OK)
```

**Check Gemini provider logs specifically:**
```bash
npx wrangler tail --search "Gemini" --format json | jq '.logs[] | select(.message | contains("image")) | .message'
```

### Resolution

**For iOS app:**
1. Add image format conversion before upload (HEIC/WebP → JPEG)
2. Use UIImage's JPEG export method
3. Verify with: Photos app → Get Info → Check format

**For worker:**
1. Add pre-validation: Reject WebP before sending to Gemini
2. Auto-convert WebP to JPEG in worker (costs CPU time)
3. Return error message to iOS: "Please use JPEG or PNG photos"

---

## Example 4: Debug WebSocket Never Connects

### Symptom
- CSV import returns 202 OK
- iOS tries to connect WebSocket
- Connection times out or immediately closes
- iOS shows "Connection lost" error after 30 seconds

### Debugging Session

**Terminal 1: Tail WebSocket logs**
```bash
npx wrangler tail --search "WebSocket" --format pretty
```

**Terminal 2: Tail Durable Object logs**
```bash
npx wrangler tail --search "ProgressWebSocketDO" --format pretty
```

**Trigger CSV import, watch WebSocket connection:**

Expected flow:
```
[ProgressWebSocketDO] New request from: 203.0.113.42
[ProgressWebSocketDO] URL: wss://api-worker.domain/ws/progress?jobId=550e8400
[ProgressWebSocketDO] Parsing jobId: 550e8400
[ProgressWebSocketDO] Retrieving job state from storage...
[ProgressWebSocketDO] Found job: status=PROCESSING, progress=15%
[ProgressWebSocketDO] Upgrading to WebSocket...
[ProgressWebSocketDO] WebSocket connected successfully
[ProgressWebSocketDO] Sending initial state: { status: "processing", progress: 15 }
[ProgressWebSocketDO] Waiting for messages...
```

**If WebSocket never connects, you'd see:**
```
[ProgressWebSocketDO] New request from: 203.0.113.42
[ProgressWebSocketDO] URL: wss://api-worker.domain/ws/progress?jobId=550e8400
[ProgressWebSocketDO] Parsing jobId: 550e8400
[ProgressWebSocketDO] ERROR: Invalid jobId format (expected UUID)
# OR
[ProgressWebSocketDO] Retrieving job state from storage...
[ProgressWebSocketDO] ERROR: Job not found in storage
[ProgressWebSocketDO] Connection closed
```

### Analysis

**Possible issues:**

1. **jobId format is wrong** - Not a valid UUID
   ```bash
   npx wrangler tail --search "Invalid jobId" --format pretty
   ```

2. **Job not found in storage** - Queuing failed, job never created
   ```bash
   npx wrangler tail --search "Job not found" --format pretty
   ```

3. **WebSocket upgrade failed** - Worker crashed during upgrade
   ```bash
   npx wrangler tail --search "Upgrading to WebSocket" --format pretty
   # Then check for ERROR lines after that
   ```

### Resolution

1. **Verify jobId in iOS logs** - Should be UUID format like `550e8400-e29b-41d4-a716-446655440000`
2. **Check that 202 response included jobId** - Verify worker returned it
3. **Verify DO binding exists in wrangler.toml** - Check `[[durable_objects.bindings]]`
4. **Check DO hasn't crashed** - Look for exceptions in logs

---

## Example 5: Rate Limiting During CSV Import

### Symptom
- CSV import starts processing
- After 20-30 seconds, enrichment slows dramatically
- Some books timeout (500 errors)
- iOS gets "Too many requests" error

### Debugging Session

**Terminal 1: Tail rate limit logs**
```bash
npx wrangler tail --search "rate" --format pretty
```

**Terminal 2: Monitor all 429 responses**
```bash
npx wrangler tail --search "429" --format pretty
```

**Trigger CSV import with 100+ books, watch logs:**

```
[jobId: 550e8400] Enriching book 1/100...
[jobId: 550e8400] Enriching book 2/100...
...
[jobId: 550e8400] Enriching book 40/100...

[RateLimiter] IP 203.0.113.42: 10 requests in last 60s
[RateLimiter] RATE LIMIT: IP 203.0.113.42 exceeded limit (10 req/min)
[RateLimiter] Response: 429 Too Many Requests

[jobId: 550e8400] Enriching book 41/100: ERROR 429 (rate limited)
[jobId: 550e8400] Backoff: waiting 5s before retry
[jobId: 550e8400] Retry: book 41 enrichment
[jobId: 550e8400] SUCCESS (after retry)

[jobId: 550e8400] Enriching book 42/100...
...
```

### Analysis

**Rate limit: 10 requests/minute per IP**

Your worker is configured conservatively:
- Rate limit: 10 requests/minute per IP
- Batch CSV size: 100 books = 100 enrichment requests
- Time to process: 100 books × 2 sec/book = 200 seconds
- Requests per minute: (100 / 200) × 60 = 30 requests/min

**Hit rate limit after ~20 seconds (10 requests at ~30 req/min rate)**

### Resolution

**Option 1: Increase per-IP rate limit**
Edit `/cloudflare-workers/api-worker/wrangler.toml`:
```toml
RATE_LIMIT_MS = "6000"  # From "50" (10 req/min) to 6s (10 req/min sustained)
```

**Option 2: Batch smaller CSVs**
Recommend users split large CSVs:
- Max 50 books per CSV import
- 50 books × 2s = 100s processing = ~30 requests/min (OK)

**Option 3: Implement exponential backoff**
Worker already retries with 5s backoff, but could be smarter:
- First retry: 5 seconds
- Second retry: 10 seconds
- Third retry: 20 seconds

---

## Quick Commands Reference for These Examples

```bash
# CSV import debugging
npx wrangler tail --search "csv-gemini" --format pretty

# Extract jobId
JOB_ID=$(npx wrangler tail --format json | jq -r '.logs[] | select(.message | contains("jobId:")) | .message | grep -oE "[a-f0-9-]{36}" | head -1)
echo "JobId: $JOB_ID"

# Filter all logs for that job
npx wrangler tail --search "$JOB_ID" --format pretty

# Batch scan debugging
npx wrangler tail --search "scan-bookshelf" --format pretty

# Find enrichment errors
npx wrangler tail --search "enrichment" --format pretty | grep ERROR

# Find Gemini errors
npx wrangler tail --search "gemini" --format pretty | grep ERROR

# Find WebSocket issues
npx wrangler tail --search "WebSocket" --format pretty

# Find rate limiting
npx wrangler tail --search "429\|rate" --format pretty

# Get JSON for piping
npx wrangler tail --format json | jq '.logs[] | select(.message | contains("ERROR")) | .message'
```

---

## Typical Processing Times (Reference)

These help you know if things are "stuck" or just slow:

| Operation | Expected Time |
|-----------|----------------|
| CSV parsing (89 rows) | 2-5 seconds |
| Book enrichment (Google Books API) | 2-3 seconds/book |
| Book enrichment (OpenLibrary API) | 1-2 seconds/book |
| Gemini vision API (1 photo) | 25-40 seconds |
| R2 cover image upload | 1-2 seconds/book |
| WebSocket connection | <500ms |
| WebSocket message delivery | <100ms |
| **Total CSV import (89 books)** | 150-250 seconds (3-4 min) |
| **Total batch scan (5 photos, 50 books)** | 200-300 seconds (3-5 min) |

If you see operations taking 3x longer than expected, something is wrong (rate limiting, provider down, timeout, etc.).

---

**Updated:** 2025-11-04
