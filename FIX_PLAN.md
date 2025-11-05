# Cloudflare Worker Backend - Detailed Fix Plan

## Overview
This document provides exact line-by-line fixes for 2 critical failures preventing CSV Import and Batch Shelf Scan features from functioning.

**Total Changes Required:** 8 lines of code
**Estimated Fix Time:** 20 minutes (including testing)
**Risk Level:** LOW (isolated changes, well-defined patterns)

---

## Fix #1: Batch Scan Handler RPC Syntax (CRITICAL)

### File
`cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`

### Problem Summary
The handler uses incorrect `.fetch()` syntax for Durable Object RPC method calls. The `.fetch()` method expects HTTP upgrade requests with WebSocket headers, not JSON payloads. This causes all 7 RPC invocations to fail silently, preventing any background job processing.

### Changes Required

#### Change 1A: Line 52-59 - Replace fetch with initBatch() RPC call

**Current Code:**
```javascript
    await doStub.fetch(`http://do/init-batch`, {
      method: 'POST',
      body: JSON.stringify({
        jobId,
        totalPhotos: images.length,
        status: 'uploading'
      })
    });
```

**Fixed Code:**
```javascript
    await doStub.initBatch({
      jobId,
      totalPhotos: images.length,
      status: 'uploading'
    });
```

**Rationale:** `initBatch()` is a direct RPC method on ProgressWebSocketDO (progress-socket.js line 402). Call it directly instead of wrapping in HTTP fetch.

---

#### Change 1B: Line 102-108 - Replace fetch with direct broadcast or remove

**Current Code:**
```javascript
    await doStub.fetch(`http://do/update-batch`, {
      method: 'POST',
      body: JSON.stringify({
        status: 'processing',
        uploads: uploadResults
      })
    });
```

**Fixed Code - Option A (Recommended: Use broadcastToClients):**
```javascript
    // Note: This update-batch concept doesn't map to an RPC method.
    // Option: Remove this call entirely (upload progress is implicit)
    // Or: Create a new updateBatch() RPC method in progress-socket.js
    // For now, remove this call - uploads are transparent to client
```

**Fixed Code - Option B (Alternative: Create RPC method):**
If upload progress reporting is needed, add to progress-socket.js:
```javascript
  async updateBatch(data) {
    this.broadcastToClients({
      type: 'batch-upload-progress',
      ...data
    });
    return { success: true };
  }
```

Then call:
```javascript
    await doStub.updateBatch({
      status: 'processing',
      uploads: uploadResults
    });
```

**Recommendation:** Remove this call (Option A) - file uploads are internal details not relevant to client progress tracking.

---

#### Change 1C: Line 149-155 - Replace fetch with updatePhoto() RPC call

**Current Code:**
```javascript
      await doStub.fetch(`http://do/update-photo`, {
        method: 'POST',
        body: JSON.stringify({
          photoIndex: i,
          status: 'processing'
        })
      });
```

**Fixed Code:**
```javascript
      await doStub.updatePhoto({
        photoIndex: i,
        status: 'processing'
      });
```

**Rationale:** `updatePhoto()` is a direct RPC method on ProgressWebSocketDO (progress-socket.js line 451).

---

#### Change 1D: Line 173-180 - Replace fetch with updatePhoto() RPC call

**Current Code:**
```javascript
        await doStub.fetch(`http://do/update-photo`, {
          method: 'POST',
          body: JSON.stringify({
            photoIndex: i,
            status: 'complete',
            booksFound: result.books.length
          })
        });
```

**Fixed Code:**
```javascript
        await doStub.updatePhoto({
          photoIndex: i,
          status: 'complete',
          booksFound: result.books.length
        });
```

**Rationale:** Same as 1C - direct RPC call to updatePhoto().

---

#### Change 1E: Line 191-198 - Replace fetch with updatePhoto() RPC call

**Current Code:**
```javascript
        await doStub.fetch(`http://do/update-photo`, {
          method: 'POST',
          body: JSON.stringify({
            photoIndex: i,
            status: 'error',
            error: error.message
          })
        });
```

**Fixed Code:**
```javascript
        await doStub.updatePhoto({
          photoIndex: i,
          status: 'error',
          error: error.message
        });
```

**Rationale:** Same as 1C - direct RPC call to updatePhoto().

---

#### Change 1F: Line 206-214 - Replace fetch with completeBatch() RPC call

**Current Code:**
```javascript
    await doStub.fetch(`http://do/complete-batch`, {
      method: 'POST',
      body: JSON.stringify({
        status: 'complete',
        totalBooks: uniqueBooks.length,
        photoResults,
        books: uniqueBooks
      })
    });
```

**Fixed Code:**
```javascript
    await doStub.completeBatch({
      status: 'complete',
      totalBooks: uniqueBooks.length,
      photoResults,
      books: uniqueBooks
    });
```

**Rationale:** `completeBatch()` is a direct RPC method on ProgressWebSocketDO (progress-socket.js line 513).

---

#### Change 1G: Line 218-225 - Replace fetch with error broadcast

**Current Code:**
```javascript
    await doStub.fetch(`http://do/update-batch`, {
      method: 'POST',
      body: JSON.stringify({
        status: 'error',
        error: error.message
      })
    });
```

**Fixed Code:**
This is in the catch block and represents a batch-level error. There's no direct RPC method for this. Options:

**Option A (Recommended): Use fail() method**
```javascript
    // Note: This error occurs during batch processing in background
    // The WebSocket may not have received any messages yet
    // Use the fail() method to properly notify client
    await doStub.fail({
      error: error.message,
      fallbackAvailable: false
    });
```

**Option B: Create updateBatch() RPC method**
Same as 1B - create `updateBatch()` method if needed.

**Recommendation:** Use Option A - call the existing `fail()` method (progress-socket.js line 343) which properly sends error messages.

---

## Fix #2: CSV Import Handler Missing ctx Parameter (MODERATE)

### File
`cloudflare-workers/api-worker/src/handlers/csv-import.js`

### Problem Summary
The function signature is missing the `ctx` parameter, but the function body attempts to use `env.ctx.waitUntil()`. While the caller passes `ctx` as part of the env object `{ ...env, ctx }`, this is fragile and not the correct pattern used elsewhere in the codebase.

### Changes Required

#### Change 2: Line 17 - Add ctx to function signature

**Current Code:**
```javascript
export async function handleCSVImport(request, env) {
  try {
    const formData = await request.formData();
    // ...
    env.ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
    return createSuccessResponse({ jobId }, {}, 202);
  } catch (error) {
    return createErrorResponse(error.message, 500, 'E_INTERNAL');
  }
}
```

**Fixed Code:**
```javascript
export async function handleCSVImport(request, env, ctx) {
  try {
    const formData = await request.formData();
    // ...
    ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
    return createSuccessResponse({ jobId }, {}, 202);
  } catch (error) {
    return createErrorResponse(error.message, 500, 'E_INTERNAL');
  }
}
```

**Changes:**
1. Add `ctx` parameter to function signature
2. Change `env.ctx.waitUntil()` to `ctx.waitUntil()` (line 44)

**Rationale:** This matches the pattern used in other handlers (batch-scan line 12, batch-enrichment). The ctx parameter is the Cloudflare request context needed for background task scheduling.

**Verification:** After change, line 44 should read:
```javascript
ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));
```

---

## Validation Checklist

### Before Making Changes
- [ ] Create feature branch: `git checkout -b fix/rpc-and-ctx-failures`
- [ ] Current tests pass: `npm test` in api-worker directory
- [ ] Both handlers build without errors: `npm run build`

### After Making Changes

**Syntax Validation:**
- [ ] Batch scan handler builds: `npm run build`
- [ ] CSV import handler builds: `npm run build`
- [ ] No TypeScript errors in handlers
- [ ] No linting errors: `npm run lint` (if available)

**Unit Tests:**
- [ ] Run existing tests: `npm test`
- [ ] Batch scan tests pass
- [ ] CSV import tests pass
- [ ] Progress socket tests pass

**Integration Tests (Manual):**
```bash
# Start dev server
npm run dev

# Test Batch Scan (separate terminal)
curl -X POST http://localhost:8787/api/scan-bookshelf/batch \
  -H "Content-Type: application/json" \
  -d '{
    "jobId": "test-batch-1",
    "images": [
      {"index": 0, "data": "base64imagedata..."}
    ]
  }'
# Should return 202 with jobId in data.jobId

# Test CSV Import
curl -X POST http://localhost:8787/api/import/csv-gemini \
  -F "file=@test.csv"
# Should return 202 with jobId in data.jobId
```

**WebSocket Connection Test (Manual):**
```bash
# Connect WebSocket after getting jobId
wscat -c "ws://localhost:8787/ws/progress?jobId=test-batch-1"
# Should receive messages like:
# {"type":"progress","jobId":"...","timestamp":1234567890,"data":{...}}
```

---

## Code Review Checklist

- [ ] All 7 RPC method calls in batch-scan-handler.js use direct method invocation (not .fetch())
- [ ] CSV import handler has ctx parameter in function signature
- [ ] CSV import handler uses ctx directly (not env.ctx)
- [ ] No remaining .fetch('http://do/...') patterns
- [ ] Error handling still catches and reports failures
- [ ] Progress updates still sent to WebSocket via RPC methods

---

## Deployment Steps

1. **Local Testing (15 min)**
   - Make changes to both files
   - Run npm test
   - Test with wscat locally

2. **Staging Deployment (5 min)**
   - Deploy to staging Worker
   - Test with real iOS app pointing to staging
   - Verify WebSocket progress messages arrive

3. **Production Deployment (5 min)**
   - Tag release version
   - Deploy to production Worker
   - Monitor logs for errors

4. **Post-Deployment Verification (5 min)**
   - Test with iOS app in production
   - Monitor Cloudflare analytics for errors
   - Check logs for any issues

---

## Rollback Plan

If issues occur after deployment:

```bash
# Revert to previous version
git revert <commit-hash>
wrangler deploy

# Or reset to previous working commit
git reset --hard <working-commit-hash>
wrangler deploy
```

---

## Files to Commit

```bash
git add cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js
git add cloudflare-workers/api-worker/src/handlers/csv-import.js
git commit -m "fix(backend): correct Durable Object RPC method invocations and missing ctx parameter

- Fix batch-scan-handler.js: Replace 7 .fetch() calls with direct RPC method invocations
  - Lines 52, 102, 149, 173, 191, 206, 218
  - initBatch(), updatePhoto(), completeBatch() now called directly
  - Removes failed HTTP-style fetch patterns for RPC methods

- Fix csv-import.js: Add missing ctx parameter to function signature
  - Line 17: Add ctx parameter
  - Line 44: Change env.ctx.waitUntil() to ctx.waitUntil()
  - Aligns with standard handler pattern used in batch-scan and batch-enrichment

Fixes #XXX (CSV import hangs) and #YYY (Batch scan hangs)"
```

---

## Estimated Impact

- **Lines changed:** 8
- **Files modified:** 2
- **Breaking changes:** None (internal implementation only)
- **API changes:** None
- **Performance impact:** None (fixes broken functionality)
- **Security impact:** None

