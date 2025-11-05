# Batch Endpoints ResponseEnvelope Migration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate batch enrichment and bookshelf scan endpoints from legacy `ApiResponse<T>` (discriminated union) to standardized `ResponseEnvelope<T>` format, ensuring consistency across all API endpoints.

**Architecture:** Backend endpoints (`/api/enrichment/batch` and `/api/scan-bookshelf/batch`) currently return `createSuccessResponse`/`createErrorResponse` which uses the new `ResponseEnvelope` structure. However, iOS clients still parse these as the legacy `ApiResponse` discriminated union. This migration updates the backend to use dedicated v1-style helpers and updates iOS to parse the correct envelope structure.

**Tech Stack:** TypeScript (Cloudflare Workers), Swift (iOS), Vitest (backend tests), Swift Testing (iOS tests)

---

## Phase 1: Backend Migration (Cloudflare Worker)

### Task 1: Update api-responses.ts Helper Functions

**Goal:** The existing `createSuccessResponse` and `createErrorResponse` already create `ResponseEnvelope` structures. We need to ensure they match the exact v1 contract (with `data: null` on error, `error: undefined` on success).

**Files:**
- Modify: `cloudflare-workers/api-worker/src/utils/api-responses.ts:11-58`

**Step 1: Review current implementation**

Read the file to confirm the structure:

```bash
cat cloudflare-workers/api-worker/src/utils/api-responses.ts
```

Expected: Functions already create `ResponseEnvelope<T>` with `data`, `metadata`, and optional `error`.

**Step 2: Verify envelope contract compliance**

Check that:
- Success responses have `data: T`, `error: undefined`
- Error responses have `data: null`, `error: ApiError`

The current implementation at lines 16-22 and 46-52 already follows this pattern. No changes needed.

**Step 3: Document the contract**

Add JSDoc comments clarifying the v1 contract:

```typescript
/**
 * Creates a standardized successful JSON response using the ResponseEnvelope (v1 format).
 *
 * Contract guarantees:
 * - data: T (non-null payload)
 * - metadata: ResponseMetadata (timestamp always present)
 * - error: undefined (no error field on success)
 *
 * @param data The payload to send
 * @param metadata Optional metadata (timestamp added automatically)
 * @param status HTTP status code (default: 200)
 * @returns Response object with enveloped JSON
 */
```

**Step 4: Commit**

```bash
git add cloudflare-workers/api-worker/src/utils/api-responses.ts
git commit -m "docs(backend): clarify ResponseEnvelope v1 contract in api-responses helpers

🤖 Generated with Claude Code"
```

---

### Task 2: Update Batch Enrichment Handler

**Goal:** Ensure all response paths in `batch-enrichment.js` use the correct `createSuccessResponse`/`createErrorResponse` helpers (they already do, but we verify).

**Files:**
- Verify: `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js:1-102`

**Step 1: Verify imports**

Check that the handler imports the correct helpers:

```bash
grep -n "createSuccessResponse\|createErrorResponse" cloudflare-workers/api-worker/src/handlers/batch-enrichment.js
```

Expected output:
```
4:import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';
24:      return createErrorResponse('Invalid books array', 400, 'E_INVALID_REQUEST');
28:      return createErrorResponse('Missing jobId', 400, 'E_INVALID_REQUEST');
32:      return createErrorResponse('Empty books array', 400, 'E_EMPTY_BATCH');
42:    return createSuccessResponse({ jobId }, {}, 202);
45:    return createErrorResponse(error.message, 500, 'E_INTERNAL');
```

**Step 2: Verify all responses use ResponseEnvelope**

All return statements already use the correct helpers. No changes needed.

**Step 3: Add validation test**

Manually test the endpoint structure:

```bash
# In separate terminal, start worker
cd cloudflare-workers/api-worker
npm run dev

# Test request
curl -X POST http://localhost:8787/api/enrichment/batch \
  -H "Content-Type: application/json" \
  -d '{"books": [{"title": "Test", "author": "Author"}], "jobId": "test-123"}'
```

Expected JSON structure:
```json
{
  "data": { "jobId": "test-123" },
  "metadata": { "timestamp": "2025-11-04T..." }
}
```

**Step 4: Commit (no changes needed)**

This step is verification only. The handler already uses the correct response format.

---

### Task 3: Update Batch Scan Handler

**Goal:** Ensure all response paths in `batch-scan-handler.js` use the correct `createSuccessResponse`/`createErrorResponse` helpers.

**Files:**
- Verify: `cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js:1-248`

**Step 1: Verify imports**

```bash
grep -n "createSuccessResponse\|createErrorResponse" cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js
```

Expected: All response construction uses the imported helpers.

**Step 2: Verify all responses use ResponseEnvelope**

Check lines 18, 22, 26, 44, 65-69, 73 use `createSuccessResponse` or `createErrorResponse`.

Current code already compliant (lines 7, 18, 22, 26, 65, 73).

**Step 3: Commit (no changes needed)**

Verification only.

---

### Task 4: Update Backend Integration Tests (batch-scan.test.js)

**Goal:** Update test assertions to expect `ResponseEnvelope<T>` structure instead of `ApiResponse<T>`.

**Files:**
- Modify: `cloudflare-workers/api-worker/tests/batch-scan.test.js:33-98`

**Step 1: Write the failing test (update first test)**

Update the first test at lines 33-58 to expect the new structure:

```javascript
it('accepts batch scan request with multiple images', async () => {
  const jobId = crypto.randomUUID();
  const request = {
    jobId,
    images: [
      { index: 0, data: 'base64image1...' },
      { index: 1, data: 'base64image2...' }
    ]
  };

  const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request)
  });

  expect(response.status).toBe(202); // Accepted
  const body = await response.json();

  // NEW: ResponseEnvelope assertions
  expect(body.data).toBeDefined();
  expect(body.data.jobId).toBe(jobId);
  expect(body.data.totalPhotos).toBe(2);
  expect(body.data.status).toBe('processing');
  expect(body.metadata).toBeDefined();
  expect(body.metadata.timestamp).toBeDefined();
  expect(body.error).toBeUndefined(); // No error field on success
});
```

**Step 2: Run test to verify it passes**

```bash
cd cloudflare-workers/api-worker
npm run dev  # In separate terminal
npm test -- batch-scan.test.js
```

Expected: Test passes (handler already returns correct format).

**Step 3: Update error test assertions**

Update lines 60-80 (rejects batches exceeding 5 photos):

```javascript
it('rejects batches exceeding 5 photos', async () => {
  const jobId = crypto.randomUUID();
  const images = Array.from({ length: 6 }, (_, i) => ({
    index: i,
    data: 'base64image...'
  }));

  const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jobId, images })
  });

  expect(response.status).toBe(400);
  const body = await response.json();

  // NEW: ResponseEnvelope error assertions
  expect(body.data).toBeNull(); // Null on error
  expect(body.error).toBeDefined();
  expect(body.error.message).toContain('maximum 5 photos');
  expect(body.error.code).toBe('E_INVALID_IMAGES');
  expect(body.metadata).toBeDefined();
  expect(body.metadata.timestamp).toBeDefined();
});
```

**Step 4: Update remaining error tests**

Apply the same pattern to lines 82-98 (rejects without jobId) and lines 100+ (rejects without images array).

Replace:
- `body.success` → Remove (no longer exists)
- `body.data` → Check for expected payload (success) or `null` (error)
- `body.error` → Check for error object (error) or `undefined` (success)
- `body.meta` → `body.metadata`

**Step 5: Run all tests**

```bash
npm test -- batch-scan.test.js
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add cloudflare-workers/api-worker/tests/batch-scan.test.js
git commit -m "test(backend): update batch-scan tests for ResponseEnvelope format

- Replace ApiResponse assertions with ResponseEnvelope structure
- Success: expect data + metadata, error undefined
- Failure: expect data null, error defined + metadata
- All tests passing with new contract

🤖 Generated with Claude Code"
```

---

### Task 5: Update Backend Integration Tests (batch-enrichment.test.ts)

**Goal:** Update test assertions in `batch-enrichment.test.ts` to expect `ResponseEnvelope<T>`.

**Files:**
- Modify: `cloudflare-workers/api-worker/tests/integration/batch-enrichment.test.ts:49-89`

**Step 1: Update success test assertions**

Update lines 49-71 (should accept valid workIds):

```typescript
it('should accept valid workIds and return 202 Accepted', async () => {
  const jobId = generateJobId();
  const workIds = ['work-1', 'work-2', 'work-3'];

  const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ workIds, jobId })
  });

  expect(response.status).toBe(202);

  const body = await response.json();

  // NEW: ResponseEnvelope assertions
  expect(body.data).toBeDefined();
  expect(body.data.jobId).toBe(jobId);
  expect(body.data.status).toBe('started');
  expect(body.data.totalBooks).toBe(3);
  expect(body.data.message).toContain('ws/progress');
  expect(body.data.message).toContain(jobId);
  expect(body.metadata).toBeDefined();
  expect(body.metadata.timestamp).toBeDefined();
  expect(body.error).toBeUndefined(); // No error on success
});
```

**Step 2: Update remaining success tests**

Apply same pattern to lines 73-89 (single workId test) and lines 91-100+ (large batch test).

**Step 3: Find and update error test assertions**

Search for error tests in the file:

```bash
grep -n "expect.*400\|expect.*500" cloudflare-workers/api-worker/tests/integration/batch-enrichment.test.ts
```

Update each error test to expect:
- `body.data` to be `null`
- `body.error` to be defined with `message` and `code`
- `body.metadata.timestamp` to be defined

**Step 4: Run tests**

```bash
cd cloudflare-workers/api-worker
npm run dev  # In separate terminal
npm test -- integration/batch-enrichment
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add cloudflare-workers/api-worker/tests/integration/batch-enrichment.test.ts
git commit -m "test(backend): update batch-enrichment tests for ResponseEnvelope

- Migrate from ApiResponse discriminated union to ResponseEnvelope
- Update success assertions (data + metadata, no error)
- Update error assertions (data null, error + metadata)
- All integration tests passing

🤖 Generated with Claude Code"
```

---

## Phase 2: iOS Client Migration (Swift)

### Task 6: Understand Current iOS Response Parsing

**Goal:** Identify where iOS incorrectly expects `ApiResponse<T>` for batch endpoints.

**Files:**
- Read: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift:1-64`
- Read: `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift:590-619`

**Step 1: Search for ApiResponse usage in batch contexts**

```bash
cd BooksTrackerPackage
grep -rn "ApiResponse<.*Enrichment" Sources/BooksTrackerFeature/
grep -rn "ApiResponse<.*Batch" Sources/BooksTrackerFeature/
```

Expected findings:
- `EnrichmentAPIClient.swift:36` - Decodes `ApiResponse<EnrichmentResult>`
- `BookshelfAIService.swift:616` - Decodes `BatchSubmissionResponse` (may use ApiResponse)

**Step 2: Document current parsing pattern**

Note the current pattern at `EnrichmentAPIClient.swift:36-47`:

```swift
if let errorResponse = try? JSONDecoder().decode(ApiResponse<EnrichmentResult>.self, from: data),
   case .failure(let apiError, _) = errorResponse {
    // Extract error details
    throw NSError(...)
}
```

This needs to change to parse `ResponseEnvelope<EnrichmentResult>` instead.

**Step 3: Commit (documentation only)**

This is analysis only, no code changes yet.

---

### Task 7: Update EnrichmentAPIClient Response Parsing

**Goal:** Change `EnrichmentAPIClient.swift` to decode `ResponseEnvelope<EnrichmentResult>` instead of `ApiResponse<EnrichmentResult>`.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift:33-62`

**Step 1: Write the failing test (update mock data)**

First, check if there are tests for `EnrichmentAPIClient`:

```bash
find BooksTrackerPackage/Tests -name "*EnrichmentAPI*" -type f
```

If tests exist, update mock JSON to use `ResponseEnvelope` format.

If no tests exist, create a simple integration test:

Create: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/EnrichmentAPIClientTests.swift`

```swift
import Testing
@testable import BooksTrackerFeature

@Test("EnrichmentAPIClient parses ResponseEnvelope on success")
func testEnrichmentClientParsesResponseEnvelope() async throws {
    // Mock JSON response (ResponseEnvelope format)
    let mockJSON = """
    {
      "data": {
        "success": true,
        "processedCount": 5,
        "totalCount": 5
      },
      "metadata": {
        "timestamp": "2025-11-04T12:00:00Z",
        "traceId": "test-trace-123"
      }
    }
    """.data(using: .utf8)!

    // Verify we can decode ResponseEnvelope
    let decoder = JSONDecoder()
    let envelope = try decoder.decode(
        ResponseEnvelope<EnrichmentAPIClient.EnrichmentResult>.self,
        from: mockJSON
    )

    #expect(envelope.data != nil)
    #expect(envelope.data?.success == true)
    #expect(envelope.data?.processedCount == 5)
    #expect(envelope.metadata.timestamp == "2025-11-04T12:00:00Z")
    #expect(envelope.error == nil)
}

@Test("EnrichmentAPIClient parses ResponseEnvelope on error")
func testEnrichmentClientParsesError() async throws {
    let mockJSON = """
    {
      "data": null,
      "metadata": {
        "timestamp": "2025-11-04T12:00:00Z"
      },
      "error": {
        "message": "Invalid workIds",
        "code": "E_INVALID_REQUEST"
      }
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let envelope = try decoder.decode(
        ResponseEnvelope<EnrichmentAPIClient.EnrichmentResult>.self,
        from: mockJSON
    )

    #expect(envelope.data == nil)
    #expect(envelope.error != nil)
    #expect(envelope.error?.message == "Invalid workIds")
    #expect(envelope.error?.code == "E_INVALID_REQUEST")
}
```

**Step 2: Run test to verify it fails**

```bash
cd BooksTrackerPackage
swift test --filter EnrichmentAPIClientTests
```

Expected: Tests fail because `EnrichmentAPIClient` still tries to decode `ApiResponse`.

**Step 3: Update startEnrichment method**

Replace the error handling at lines 33-47 with ResponseEnvelope parsing:

```swift
let (data, response) = try await URLSession.shared.data(for: request)

guard let httpResponse = response as? HTTPURLResponse else {
    throw URLError(.badServerResponse)
}

// Decode ResponseEnvelope
let decoder = JSONDecoder()
let envelope = try decoder.decode(ResponseEnvelope<EnrichmentResult>.self, from: data)

// Check for API error in envelope
if let error = envelope.error {
    let userInfo: [String: Any] = [
        NSLocalizedDescriptionKey: error.message,
        "errorCode": error.code ?? "UNKNOWN"
    ]
    throw NSError(
        domain: "EnrichmentAPIClient",
        code: httpResponse.statusCode,
        userInfo: userInfo
    )
}

// Ensure data is present
guard let result = envelope.data else {
    throw URLError(.badServerResponse)
}

// Check HTTP status (should be 202 for batch enrichment)
guard httpResponse.statusCode == 202 else {
    throw URLError(.badServerResponse)
}

return result
```

**Step 4: Run tests to verify they pass**

```bash
swift test --filter EnrichmentAPIClientTests
```

Expected: Both tests pass.

**Step 5: Build package to check for compilation errors**

```bash
swift build
```

Expected: Build succeeds with zero warnings.

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/EnrichmentAPIClientTests.swift
git commit -m "refactor(iOS): migrate EnrichmentAPIClient to ResponseEnvelope parsing

- Replace ApiResponse discriminated union with ResponseEnvelope
- Add error handling for envelope.error field
- Add unit tests for success and error parsing
- Zero warnings, all tests passing

🤖 Generated with Claude Code"
```

---

### Task 8: Update BookshelfAIService Batch Submission Parsing

**Goal:** Ensure `BookshelfAIService.submitBatch()` correctly parses `ResponseEnvelope<BatchSubmissionResponse>`.

**Files:**
- Verify: `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift:590-619`

**Step 1: Check current parsing logic**

Read lines 604-618 to see how `BatchSubmissionResponse` is decoded:

```bash
sed -n '604,618p' BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
```

Expected: Direct decode of `BatchSubmissionResponse` without envelope.

**Step 2: Verify BatchSubmissionResponse structure**

Check if `BatchSubmissionResponse` is already wrapped in `ResponseEnvelope`:

```bash
grep -A 5 "struct BatchSubmissionResponse" BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
```

Current structure (lines 672-676):
```swift
public struct BatchSubmissionResponse: Codable, Sendable {
    public let jobId: String
    public let totalPhotos: Int
    public let status: String
}
```

This is the **data payload**, not the full response. The endpoint returns `ResponseEnvelope<BatchSubmissionResponse>`.

**Step 3: Write failing test**

Create test for batch submission response parsing:

Create or update: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServiceTests.swift`

```swift
@Test("BookshelfAIService parses batch submission ResponseEnvelope")
func testBatchSubmissionParsesEnvelope() async throws {
    let mockJSON = """
    {
      "data": {
        "jobId": "batch-123",
        "totalPhotos": 3,
        "status": "processing"
      },
      "metadata": {
        "timestamp": "2025-11-04T12:00:00Z"
      }
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let envelope = try decoder.decode(
        ResponseEnvelope<BatchSubmissionResponse>.self,
        from: mockJSON
    )

    #expect(envelope.data != nil)
    #expect(envelope.data?.jobId == "batch-123")
    #expect(envelope.data?.totalPhotos == 3)
    #expect(envelope.data?.status == "processing")
    #expect(envelope.error == nil)
}
```

**Step 4: Run test to verify it fails**

```bash
swift test --filter testBatchSubmissionParsesEnvelope
```

Expected: Test passes for decoding, but `submitBatch()` method likely doesn't use this structure yet.

**Step 5: Update submitBatch method**

Replace lines 614-618 with ResponseEnvelope parsing:

```swift
let (data, response) = try await URLSession.shared.data(for: request)

guard let httpResponse = response as? HTTPURLResponse else {
    throw BookshelfAIError.invalidResponse
}

// Decode ResponseEnvelope
let decoder = JSONDecoder()
let envelope = try decoder.decode(
    ResponseEnvelope<BatchSubmissionResponse>.self,
    from: data
)

// Check for API error
if let error = envelope.error {
    throw BookshelfAIError.serverError(
        httpResponse.statusCode,
        error.message
    )
}

// Ensure data is present
guard let submissionResponse = envelope.data else {
    throw BookshelfAIError.invalidResponse
}

// Verify 202 Accepted status
guard httpResponse.statusCode == 202 else {
    throw BookshelfAIError.serverError(
        httpResponse.statusCode,
        "Unexpected status code"
    )
}

return submissionResponse
```

**Step 6: Run tests**

```bash
swift test --filter BookshelfAIService
```

Expected: All tests pass.

**Step 7: Build package**

```bash
swift build
```

Expected: Zero warnings.

**Step 8: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServiceTests.swift
git commit -m "refactor(iOS): migrate BookshelfAIService batch submission to ResponseEnvelope

- Update submitBatch() to parse ResponseEnvelope wrapper
- Add error handling for envelope.error field
- Add unit test for envelope parsing
- Zero warnings, all tests passing

🤖 Generated with Claude Code"
```

---

### Task 9: Verify Full iOS Build and Tests

**Goal:** Ensure the entire iOS package builds with zero warnings and all tests pass.

**Files:**
- Verify: `BooksTrackerPackage/` (all sources and tests)

**Step 1: Clean build**

```bash
cd BooksTrackerPackage
swift package clean
swift build
```

Expected: Build succeeds with zero warnings.

**Step 2: Run all tests**

```bash
swift test
```

Expected: All tests pass.

**Step 3: Check for any remaining ApiResponse usage in batch contexts**

```bash
grep -rn "ApiResponse<.*Batch\|ApiResponse<.*Enrichment" Sources/ Tests/
```

Expected: No matches (all migrated to ResponseEnvelope).

**Step 4: Commit**

```bash
git add -A
git commit -m "test(iOS): verify all batch endpoints use ResponseEnvelope

- Full package builds with zero warnings
- All tests passing (unit + integration)
- No remaining ApiResponse usage in batch contexts

🤖 Generated with Claude Code"
```

---

## Phase 3: Code Cleanup (Optional)

### Task 10: Remove Legacy Response Types (Backend)

**Goal:** Remove unused `ApiResponse`, `SuccessResponse`, `ErrorResponse` types from TypeScript codebase.

**Files:**
- Modify: `cloudflare-workers/api-worker/src/types/responses.ts:57-83`
- Modify: `cloudflare-workers/api-worker/src/types/responses.ts:127-163`

**Step 1: Search for remaining usage**

```bash
cd cloudflare-workers/api-worker
grep -rn "ApiResponse<\|SuccessResponse<\|ErrorResponse\|createSuccessResponseObject\|createErrorResponseObject" src/
```

Expected: Only type definitions, no actual usage.

**Step 2: Check if types are imported anywhere**

```bash
grep -rn "import.*ApiResponse\|import.*SuccessResponse\|import.*ErrorResponse" src/
```

If any imports remain, update those files first.

**Step 3: Remove legacy types**

Delete lines 57-83 (ApiResponse, SuccessResponse, ErrorResponse) and lines 127-163 (helper functions) from `responses.ts`.

**Step 4: Run TypeScript build**

```bash
npm run build
```

Expected: Build succeeds (if types truly unused).

**Step 5: Run all tests**

```bash
npm test
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add cloudflare-workers/api-worker/src/types/responses.ts
git commit -m "refactor(backend): remove legacy ApiResponse types

- Delete ApiResponse, SuccessResponse, ErrorResponse (unused)
- Delete createSuccessResponseObject, createErrorResponseObject helpers
- All endpoints migrated to ResponseEnvelope
- Zero warnings, all tests passing

🤖 Generated with Claude Code"
```

---

### Task 11: Remove Legacy Response Types (iOS)

**Goal:** Remove unused `ApiResponse` enum from `ResponseEnvelope.swift`.

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/ResponseEnvelope.swift:51-106`

**Step 1: Search for remaining ApiResponse usage**

```bash
cd BooksTrackerPackage
grep -rn "ApiResponse<" Sources/ Tests/
```

Expected: Usage only in v1 search endpoints (not batch endpoints).

**Step 2: Determine if ApiResponse is still needed**

If v1 search endpoints (`/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`) still use the legacy format, keep `ApiResponse`.

If all endpoints migrated to `ResponseEnvelope`, remove `ApiResponse`.

**Step 3: (Conditional) Remove ApiResponse enum**

If safe to remove, delete lines 51-106 from `ResponseEnvelope.swift`.

**Step 4: Build package**

```bash
swift build
```

Expected: Build succeeds if ApiResponse truly unused.

**Step 5: Run tests**

```bash
swift test
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/ResponseEnvelope.swift
git commit -m "refactor(iOS): remove legacy ApiResponse discriminated union

- Delete ApiResponse enum (all endpoints use ResponseEnvelope)
- Delete ApiError nested struct (replaced by ResponseEnvelope.ApiErrorInfo)
- Zero warnings, all tests passing

🤖 Generated with Claude Code"
```

---

## Verification Checklist

**Backend:**
- [ ] All batch endpoint responses use `createSuccessResponse`/`createErrorResponse`
- [ ] `batch-scan.test.js` expects `ResponseEnvelope` structure
- [ ] `batch-enrichment.test.ts` expects `ResponseEnvelope` structure
- [ ] All tests passing (`npm test`)
- [ ] Zero TypeScript warnings (`npm run build`)

**iOS:**
- [ ] `EnrichmentAPIClient.startEnrichment()` parses `ResponseEnvelope<EnrichmentResult>`
- [ ] `BookshelfAIService.submitBatch()` parses `ResponseEnvelope<BatchSubmissionResponse>`
- [ ] Unit tests cover both success and error envelope parsing
- [ ] Full package builds with zero warnings (`swift build`)
- [ ] All tests passing (`swift test`)

**Documentation:**
- [ ] Update `CHANGELOG.md` with migration notes
- [ ] Update `CLAUDE.md` if batch endpoint contracts changed
- [ ] Update API documentation in `docs/features/` if applicable

---

## Rollback Plan

If issues arise during deployment:

1. **Backend rollback:** The backend changes are backward-compatible (ResponseEnvelope already used). No rollback needed.

2. **iOS rollback:** Revert commits for Tasks 7-8. The old `ApiResponse` parsing will fail with the new backend format, requiring immediate fix-forward.

3. **Fix-forward:** If iOS crashes in production, hotfix by reverting to `ApiResponse` parsing temporarily and deploy backend compatibility layer.

---

## Success Criteria

- [ ] All batch endpoints return `ResponseEnvelope<T>` structure
- [ ] iOS correctly parses success and error envelopes
- [ ] All backend tests passing (Vitest)
- [ ] All iOS tests passing (Swift Testing)
- [ ] Zero warnings (TypeScript + Swift)
- [ ] No production incidents related to response parsing
- [ ] Legacy types removed (Phase 3 complete)
