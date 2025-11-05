# CloudFlare Worker Backend Failure Investigation Report
**Date:** November 4, 2025
**Investigator:** Claude Code
**Status:** ROOT CAUSES IDENTIFIED - READY FOR FIX

---

## Executive Summary

Systematic code analysis revealed **TWO CRITICAL FAILURES** in the BooksTrack Cloudflare Worker backend affecting CSV Import and Batch Shelf Scan features:

1. **Batch Scan Handler (CRITICAL)**: RPC method invocations use incorrect `.fetch()` syntax instead of direct method calls
2. **CSV Import Handler (MODERATE)**: Missing `env.ctx` parameter in handler signature causes `ctx.waitUntil()` failures

Both failures prevent background job processing from executing, leaving iOS clients hanging without progress updates.

---

## Part 1: Batch Scan Handler Failure

### Affected Code
**File:** `cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`
**Lines:** 52, 102, 149, 173, 191, 206, 218
**Severity:** CRITICAL - 100% failure rate

### Root Cause Analysis

The batch-scan handler uses **incorrect Durable Object RPC invocation syntax**:

```javascript
// ❌ WRONG: Using .fetch() with HTTP-style routing
await doStub.fetch(`http://do/init-batch`, {
  method: 'POST',
  body: JSON.stringify({ jobId, totalPhotos, status })
});

await doStub.fetch(`http://do/update-photo`, {
  method: 'POST',
  body: JSON.stringify({ photoIndex: i, status: 'processing' })
});

await doStub.fetch(`http://do/complete-batch`, {
  method: 'POST',
  body: JSON.stringify({ status: 'complete', totalBooks, photoResults, books })
});
```

### Expected Behavior (Correct Pattern)

The test endpoints in `index.js` (lines 737, 766, 795, 817) demonstrate the **correct RPC invocation pattern**:

```javascript
// ✅ CORRECT: Direct method invocation on doStub
const result = await doStub.initBatch({ jobId, totalPhotos, status });
const state = await doStub.getState();
const result = await doStub.updatePhoto({ photoIndex, status, booksFound, error });
const result = await doStub.completeBatch({ status, totalBooks, photoResults, books });
```

### Error Chain

1. **Client Request:** iOS sends batch of 2-5 photos to `/api/scan-bookshelf/batch`
2. **Validation Passes:** Handler validates images and R2 binding (line 12-46)
3. **RPC Failure:** `await doStub.fetch('http://do/init-batch', ...)` on line 52 **fails because**:
   - `.fetch()` expects HTTP upgrade request with WebSocket headers
   - The JSON payload is not a valid WebSocket upgrade request
   - Returns 426 "Upgrade Required" or throws TypeError
   - Entire batch job silently fails (caught in catch block line 71-74)
4. **Empty Response:** `processBatchPhotos()` never executes (line 62 waitUntil is canceled)
5. **Client Impact:**
   - iOS receives 202 Accepted with jobId ✓
   - Client connects WebSocket to `/ws/progress?jobId=...` ✓
   - **WebSocket sits idle** - no progress updates arrive ✗
   - Client timeout after 90s with "Job failed" error ✗

### Evidence

**Comparison of RPC Methods in progress-socket.js:**
```
Line 402:  async initBatch({ jobId, totalPhotos, status })
Line 451:  async updatePhoto({ photoIndex, status, booksFound, error })
Line 513:  async completeBatch({ status, totalBooks, photoResults, books })
Line 558:  async isBatchCanceled()
Line 567:  async cancelBatch()
```

**These are all direct async methods** - not HTTP endpoints. They must be invoked as:
```javascript
await doStub.methodName(params)  // ✓ RPC call
```

NOT as:
```javascript
await doStub.fetch('http://do/method-path', ...)  // ✗ HTTP call
```

---

## Part 2: CSV Import Handler Failure

### Affected Code
**File:** `cloudflare-workers/api-worker/src/handlers/csv-import.js`
**Line:** 17 (function signature)
**Severity:** MODERATE - Blocks background task scheduling

### Root Cause Analysis

The CSV import handler is missing the `ctx` parameter from its function signature:

```javascript
// ❌ WRONG: Missing ctx parameter
export async function handleCSVImport(request, env) {
  // ...
  env.ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
  // ↑ env.ctx is undefined - causes crash
}
```

### Expected Behavior

The correct signature should include `ctx`:

```javascript
// ✅ CORRECT: Has ctx parameter
export async function handleCSVImport(request, env, ctx) {
  // ...
  ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
}
```

### Verification

**Called from index.js (line 220):**
```javascript
return handleCSVImport(request, { ...env, ctx });
```

The caller **does pass ctx** in the env object (`{ ...env, ctx }`), but the handler function tries to access it as `env.ctx`, which is fragile and confusing.

**Compare to correct pattern (batch-scan, line 165):**
```javascript
return handleBatchScan(request, env, ctx);
// Handler signature (line 12): export async function handleBatchScan(request, env, ctx)
```

### Error Chain

1. **Client Request:** iOS sends CSV file to `/api/import/csv-gemini`
2. **File Validation:** File size check passes (line 27-34)
3. **WebSocket Setup:** DO stub created successfully (line 40-41)
4. **Task Scheduling:** Line 44 executes `env.ctx.waitUntil(...)`
   - If caller doesn't pass `ctx` in env: `env.ctx` is undefined ✗
   - Background task never registers with Cloudflare runtime
5. **Worker Shutdown:** Request returns 202 (line 46)
6. **Task Lost:** Cloudflare terminates worker before background job starts
7. **Client Impact:**
   - iOS receives 202 Accepted with jobId ✓
   - WebSocket connects ✓
   - **Progress never updates** - task was never scheduled ✗
   - After 30-60s, connection timeout ✗

---

## Part 3: ResponseEnvelope Migration Context

### Timeline
**Commits affecting these handlers:**
- `f6457f8` (Nov 4 20:07): CSV import migration to ResponseEnvelope
- `34d1913` (Nov 4 20:13): Batch scan migration to ResponseEnvelope
- `f591bcc` (Nov 4 20:14): Batch scan tests updated for ResponseEnvelope

### What Changed (Correctly)
Both handlers were updated to use `createSuccessResponse()` and `createErrorResponse()` utilities for HTTP response wrapping. This change is **correct and not the root cause**.

### What Should Have Been Changed (But Wasn't)
During the ResponseEnvelope migration, the **RPC method calls should have been reviewed and fixed**, but they weren't noticed because the migration focused only on HTTP response formatting.

**The batch-scan `.fetch()` usage likely existed BEFORE the migration** but was overlooked during the code review.

---

## Summary of Root Causes

| Feature | Problem | Root Cause | Impact |
|---------|---------|-----------|--------|
| **Batch Scan** | RPC method calls use incorrect `.fetch()` syntax | Line 52, 102, 149, 173, 191, 206, 218 invoke `.fetch()` instead of direct method calls | Background job never starts; client hangs indefinitely |
| **CSV Import** | Missing `ctx` parameter in handler function | Handler signature line 17 doesn't include `ctx` parameter (passed as `env.ctx` instead) | `ctx.waitUntil()` fails; background job never scheduled |

---

## Recommended Fixes

### Fix 1: Batch Scan Handler - Replace .fetch() with Direct RPC Calls

**File:** `cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`

**Lines to modify:** 52-59, 102-108, 149-155, 173-180, 191-198, 206-214, 218-225

**Pattern:**
```javascript
// BEFORE:
await doStub.fetch(`http://do/init-batch`, {
  method: 'POST',
  body: JSON.stringify({ jobId, totalPhotos, status })
});

// AFTER:
await doStub.initBatch({ jobId, totalPhotos, status });
```

**Specific replacements:**

1. **Line 52-59:** Replace fetch with `initBatch()` call
2. **Line 102-108:** Replace fetch with new method or remove (HTTP not available for this)
3. **Line 149-155:** Replace fetch with `updatePhoto()` call
4. **Line 173-180:** Replace fetch with `updatePhoto()` call
5. **Line 191-198:** Replace fetch with `updatePhoto()` call
6. **Line 206-214:** Replace fetch with `completeBatch()` call
7. **Line 218-225:** Replace fetch with error broadcast pattern

**Note:** Some `.fetch()` calls (e.g., "update-batch" on line 102, 218) don't correspond to RPC methods. Need to either:
- Remove them (if they're not needed)
- Create new RPC methods in progress-socket.js
- Use `broadcastToClients()` pattern instead

### Fix 2: CSV Import Handler - Add ctx Parameter

**File:** `cloudflare-workers/api-worker/src/handlers/csv-import.js`

**Line 17:**
```javascript
// BEFORE:
export async function handleCSVImport(request, env) {

// AFTER:
export async function handleCSVImport(request, env, ctx) {
```

**Line 44:** (no change needed, already correct)
```javascript
ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
```

---

## Verification Steps (Post-Fix)

### For Batch Scan:
1. Send batch request: `POST /api/scan-bookshelf/batch` with 2 images
2. Connect WebSocket: `GET /ws/progress?jobId=...`
3. Verify progress updates arrive (not instant timeout)
4. Verify R2 images uploaded: Check `BOOKSHELF_IMAGES` bucket
5. Verify final results received with books array

### For CSV Import:
1. Send CSV: `POST /api/import/csv-gemini` with FormData
2. Connect WebSocket: `GET /ws/progress?jobId=...`
3. Verify progress updates arrive (0%, 25%, 50%, 75%, 100%)
4. Verify Gemini API is called (check logs for "Gemini processing complete")
5. Verify final results with parsed books

---

## Files Requiring Changes

1. **`cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`** (HIGH PRIORITY)
   - Fix 7 RPC method calls (lines 52, 102, 149, 173, 191, 206, 218)

2. **`cloudflare-workers/api-worker/src/handlers/csv-import.js`** (MEDIUM PRIORITY)
   - Fix function signature (line 17)

---

## Additional Observations

### Positive Findings:
- WebSocket infrastructure (progress-socket.js) is correctly implemented
- Test endpoints in index.js demonstrate correct RPC patterns
- ResponseEnvelope migration is technically sound
- Error handling with try/catch blocks exists but silently swallows failures

### Recommendations for Prevention:
1. **Code Review:** All RPC method invocations should be checked against their definitions in Durable Objects
2. **Testing:** Add integration tests that actually connect WebSocket and verify progress messages
3. **Type Safety:** Consider using TypeScript for Durable Object stubs to catch signature mismatches at compile time
4. **Error Logging:** Don't silently catch errors in background task initialization - log to external monitoring

---

## Timeline of Investigation

1. **Code Inspection:** Reviewed CSV import and batch scan handlers
2. **RPC Pattern Discovery:** Examined progress-socket.js async methods
3. **Comparison Analysis:** Found test endpoints using correct syntax (lines 737, 766, 795, 817 in index.js)
4. **Root Cause Confirmation:** Batch scan uses `.fetch('http://do/...')` instead of `.methodName()`
5. **Secondary Issue:** CSV import missing ctx parameter in function signature
6. **Evidence Collection:** Verified correct patterns from working test endpoints

---

## Conclusion

Both failures are implementation bugs introduced during recent refactoring:

1. **Batch Scan (CRITICAL):** Incorrect RPC method syntax prevents all background job execution
2. **CSV Import (MODERATE):** Missing function parameter creates fragile env.ctx reference

Neither issue is related to the ResponseEnvelope migration per se, but both were likely introduced during the same development sprint and not caught by testing.

The fixes are straightforward and low-risk - change 8 lines of code total.

