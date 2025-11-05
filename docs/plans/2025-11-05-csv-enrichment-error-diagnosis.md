# CSV Import & Enrichment Failure Diagnosis
**Date:** November 5, 2025
**Investigation Focus:** CSV import error display & enrichment data gaps
**Status:** Root Causes Identified (2 Critical Issues)

---

## Executive Summary

Based on code analysis of the ResponseEnvelope migration (commit f6457f8), I've identified **two critical root causes**:

1. **CSV Import HTTP Status Code Bug** - Backend returns 202 (Accepted) but iOS expects 200 (OK) for success
2. **Enrichment Response Envelope Mismatch** - Backend sends legacy format while iOS expects new ResponseEnvelope structure

These prevent proper response decoding, causing error messages to display to users and books to save without enrichment data.

---

## Issue 1: CSV Import HTTP Status Mismatch

### Root Cause
The CSV import handler correctly returns HTTP 202 (Accepted) to indicate the background job was accepted, but the iOS client requires HTTP 200 to consider the request successful.

**Backend Code** (`src/handlers/csv-import.js:47`):
```javascript
return createSuccessResponse({ jobId }, {}, 202);  // ← Returns 202 (Accepted)
```

**iOS Code** (`GeminiCSVImportService.swift:115`):
```swift
if httpResponse.statusCode != 200 {  // ← Expects exactly 200, not 202
    // Try to decode error response...
    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
}
```

### Impact
When CSV import is triggered:
1. Backend correctly processes the file and returns `{ "data": { "jobId": "..." }, "metadata": {...} }` with HTTP 202
2. iOS sees status 202 ≠ 200, treats it as an error
3. Error response is shown to user: "Server error (202): ..."
4. WebSocket progress never connects because jobId is never extracted

### User Experience
- User sees error message (as reported)
- CSV file is NOT imported
- No books appear in library

### Fix Location
File: `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`
Line: 115

**Change:**
```swift
// BEFORE (Line 115)
if httpResponse.statusCode != 200 {

// AFTER
if httpResponse.statusCode != 202 && httpResponse.statusCode != 200 {
```

**Rationale:** HTTP 202 (Accepted) is the correct response for asynchronous job acceptance. We should accept both 200 and 202 as success cases.

---

## Issue 2: Enrichment Batch API Response Format

### Root Cause
The enrichment batch endpoint (`/api/enrichment/batch`) was migrated to use the new ResponseEnvelope format, but the iOS EnrichmentAPIClient and backend handler have incompatible expectations.

**Backend Handler** (`src/handlers/batch-enrichment.js:40-43`):
```javascript
// The handler receives ctx from... nowhere (ctx is not passed as parameter!)
// This causes ctx.waitUntil to fail
env.ctx.waitUntil(processBatchEnrichment(books, doStub, env));
```

**iOS Client** (`EnrichmentAPIClient.swift:50`):
```swift
let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data)
```

### Deeper Problem (CONFIRMED)
The batch-enrichment.js handler has a **critical bug**: it references `env.ctx.waitUntil()` but the handler's function signature doesn't include `ctx` as a parameter.

**Verified in source code:**

Batch-enrichment handler (`src/handlers/batch-enrichment.js:19`):
```javascript
export async function handleBatchEnrichment(request, env) {  // ← ctx is MISSING from parameters!
  // ...
  env.ctx.waitUntil(processBatchEnrichment(...)) // ← This will fail: env.ctx is undefined
}
```

Router calls the handler (`src/index.js:241`):
```javascript
return handleBatchEnrichment(request, { ...env, ctx });  // ← Router CORRECTLY passes ctx in env object
```

**The Problem:** The router merges ctx into the env object as `{ ...env, ctx }`, but the handler tries to access `env.ctx` which doesn't exist. The ctx should either:
1. Be extracted as the third parameter `(request, env, ctx)`, or
2. Be accessed from the merged env object correctly

### Impact
When batch enrichment is triggered from iOS:
1. iOS makes POST to `/api/enrichment/batch` with jobId and books
2. Backend handler attempts to call `env.ctx.waitUntil()` but `ctx` is undefined
3. Background job fails to start
4. Response may be incomplete or error
5. iOS receives malformed response, decoding fails
6. User sees no error, but enrichment never happens
7. Books appear in library without metadata (cover, ISBN, publication details)

### User Experience
- User imports CSV or batch enriches books
- No visible error message
- Books appear in library instantly (good UX)
- But books have NO enrichment data (title, author, cover)
- Books appear "empty" in library view

---

## Critical Files Affected

### Backend
1. **csv-import.js** - HTTP 202 status correct, iOS decoding bug
2. **batch-enrichment.js** - Missing `ctx` parameter and `env.ctx.waitUntil()` call
3. **api-responses.ts** - ResponseEnvelope format correct
4. **index.js** - Router must pass `ctx` to handler

### iOS
1. **GeminiCSVImportService.swift** (Line 115) - Wrong HTTP status check
2. **EnrichmentAPIClient.swift** - Correct but depends on backend fix
3. **EnrichmentService.swift** - Calls EnrichmentAPIClient correctly
4. **EnrichmentQueue.swift** - Orchestrates background enrichment

---

## How the ResponseEnvelope Works

### New Format (Deployed Nov 4)
Backend sends:
```json
{
  "data": { "jobId": "uuid", ...enrichment data... },
  "metadata": { "timestamp": "2025-11-05...", "provider": "google-books" },
  "error": null
}
```

iOS expects (in ResponseEnvelope.swift):
```swift
public struct ResponseEnvelope<T: Codable>: Codable {
    public let data: T?              // ← Data payload
    public let metadata: ResponseMetadata  // ← Always required
    public let error: ApiErrorInfo?  // ← Error details
}
```

**Issue:** If `metadata` is missing or malformed, the entire response fails to decode.

---

## Root Cause Chain

### CSV Import Error Chain
```
User selects CSV file
  ↓
iOS POST multipart/form-data to /api/import/csv-gemini
  ↓
Backend parseCSVWithGemini() → Gemini API → Parsed books
  ↓
Backend returns ResponseEnvelope + HTTP 202 (Accepted)
  ↓
iOS checks if httpResponse.statusCode == 200  ← FAILS (is 202)
  ↓
iOS throws GeminiCSVImportError.serverError(202, "...")
  ↓
User sees error message on screen
  ❌ Books never imported, WebSocket never connects
```

### Enrichment Data Gap Chain
```
CSV books imported OR manual books added
  ↓
iOS calls EnrichmentQueue.startProcessing()
  ↓
EnrichmentQueue creates jobId, connects WebSocket
  ↓
iOS POST to /api/enrichment/batch with { books, jobId }
  ↓
Backend handleBatchEnrichment() called
  ↓
Backend tries env.ctx.waitUntil(...)  ← ctx is undefined
  ↓
Background job fails to start
  ↓
No enrichment data fetched from Google Books/OpenLibrary
  ↓
iOS receives incomplete response
  ↓
User sees books in library with NO cover/ISBN/details
```

---

## Verification Steps

### Check CSV Import Error
```bash
# Make curl request to CSV import endpoint
curl -X POST \
  -F "file=@test.csv" \
  https://api-worker.jukasdrj.workers.dev/api/import/csv-gemini

# Expected: HTTP 202 response
# Actual: [Need to verify from logs]
```

### Check Batch Enrichment
```bash
# Stream worker logs
npx wrangler tail api-worker --search "batch-enrichment"

# Look for:
# - "env.ctx is undefined" errors
# - Failed job starts
# - WebSocket DO timeouts
```

### Check ResponseEnvelope Format
```bash
# Both endpoints should return:
{
  "data": { ... },
  "metadata": { "timestamp": "..." },
  "error": null  // or error object if failed
}
```

---

## Implementation Plan

### Phase 1: Fix CSV Import (High Priority)
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`

```swift
// Line 115: Change from
if httpResponse.statusCode != 200 {

// To
if ![200, 202].contains(httpResponse.statusCode) {
```

**Rationale:** HTTP 202 (Accepted) is standard for asynchronous operations. Verify both success cases.

### Phase 2: Fix Batch Enrichment Handler (Critical)
**File:** `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`
**Lines:** 19, 40

The router correctly passes ctx merged into env: `{ ...env, ctx }`. The handler needs to access it properly.

**Current Bug (Line 19):**
```javascript
export async function handleBatchEnrichment(request, env) {  // ← Missing ctx parameter
  // ...
  env.ctx.waitUntil(processBatchEnrichment(...)) // ← Line 40: env.ctx is undefined!
}
```

**Fix (Add ctx parameter extraction):**
```javascript
export async function handleBatchEnrichment(request, env, ctx) {  // ← ADD ctx parameter
  try {
    const { books, jobId } = await request.json();

    if (!books || !Array.isArray(books)) {
      return createErrorResponse('Invalid books array', 400, 'E_INVALID_REQUEST');
    }

    if (!jobId) {
      return createErrorResponse('Missing jobId', 400, 'E_INVALID_REQUEST');
    }

    if (books.length === 0) {
      return createErrorResponse('Empty books array', 400, 'E_EMPTY_BATCH');
    }

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Start background enrichment (NOW ctx is available as parameter!)
    ctx.waitUntil(processBatchEnrichment(books, doStub, env));  // ← Use ctx parameter

    return createSuccessResponse({ jobId }, {}, 202);

  } catch (error) {
    return createErrorResponse(error.message, 500, 'E_INTERNAL');
  }
}
```

**Explanation:** The router passes ctx as the third parameter but the handler only accepts (request, env). By adding ctx as the third parameter, we can access the ExecutionContext properly and schedule the background job.

### Phase 3: Verify ResponseEnvelope Format (Testing)
- Ensure all `/api/*` endpoints return ResponseEnvelope
- Test iOS decoding with real responses
- Add integration tests

---

## Testing Checklist

### CSV Import Test
- [ ] Import 5-book test CSV
- [ ] Verify HTTP 202 response received
- [ ] Verify jobId extracted
- [ ] Verify WebSocket connects
- [ ] Verify progress updates received
- [ ] Verify books appear in library with enrichment data

### Batch Enrichment Test
- [ ] Manually add 5 books
- [ ] Trigger enrichment from Library view
- [ ] Verify background job starts (check logs)
- [ ] Verify WebSocket receives progress updates
- [ ] Verify books update with cover images
- [ ] Verify publication details added

### Response Format Test
- [ ] Verify `/api/import/csv-gemini` returns ResponseEnvelope
- [ ] Verify `/api/enrichment/batch` returns ResponseEnvelope
- [ ] Verify error responses include `error` field
- [ ] Verify all responses include `metadata` with timestamp

---

## Next Steps

1. **Immediate:** Deploy fix for CSV import HTTP status check (5 min)
2. **Urgent:** Fix batch enrichment handler ctx parameter (15 min)
3. **Verify:** Run integration tests against live endpoints
4. **Monitor:** Watch backend logs for any enrichment failures
5. **Document:** Update API response contract documentation

---

## Files to Review

**Backend:**
- `/cloudflare-workers/api-worker/src/index.js` - Router (to verify ctx passing)
- `/cloudflare-workers/api-worker/src/handlers/csv-import.js` - CSV handler (correct)
- `/cloudflare-workers/api-worker/src/handlers/batch-enrichment.js` - Enrichment handler (buggy)
- `/cloudflare-workers/api-worker/src/utils/api-responses.ts` - Response utilities (correct)

**iOS:**
- `/BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift` - CSV client (buggy)
- `/BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift` - Enrichment client (correct)
- `/BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/ResponseEnvelope.swift` - Response models (correct)

---

## References

- **Commit:** f6457f8 (ResponseEnvelope migration)
- **Branch:** main (deployed)
- **Endpoints:**
  - CSV: `/api/import/csv-gemini` (POST)
  - Enrichment: `/api/enrichment/batch` (POST)
  - WebSocket: `/ws/progress?jobId=...` (GET/upgrade)
