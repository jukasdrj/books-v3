# API Contract Refactoring - ResponseEnvelope Migration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** ✅ PHASE 4 COMPLETE (Backend Only) | ⚠️ Phase 4.3-4.4 Blocked (See Issue #230)
**Completed:**
- Phase 1 (Utilities) ✅
- Phase 2 (CSV Import) ✅
- Phase 3 (Batch Enrichment) ✅
- Phase 4.1-4.2 (Batch Scan Backend) ✅

**Blocker:** Phase 4.3-4.4 cannot proceed - `/api/scan-bookshelf/batch` is legacy namespace, not `/v1/batch-scan`. iOS BookshelfAIService lacks batch scan methods. See [Issue #230](https://github.com/jukasdrj/books-tracker-v1/issues/230).

**Latest Commits:**
- `34d1913` - "refactor(backend): migrate batch-scan handlers to ResponseEnvelope"
- `f591bcc` - "test(backend): update batch-scan tests for ResponseEnvelope"

**Next:** Skip Phase 4.3-4.4, proceed to Phase 5 (Validation)

**Goal:** Refactor all non-compliant `/v1` endpoints to use the canonical `ResponseEnvelope<T>` wrapper, standardizing API communication across backend and iOS client.

**Architecture:** Create reusable backend response utilities, then migrate 5 endpoint groups (CSV import, batch enrichment, batch scan x3) in parallel. Each migration follows: backend handler → backend tests → iOS client → iOS tests. All responses wrapped in `{ data: T, metadata: {...}, error?: {...} }`.

**Tech Stack:** TypeScript (Cloudflare Workers), Swift 6.2 (iOS), Vitest (backend tests), Swift Testing (iOS tests)

---

## Phase 1: Backend Response Utilities

### Task 1.1: Write tests for response utilities (TDD)

**Files:**
- Create: `cloudflare-workers/api-worker/tests/utils/api-responses.test.ts`

**Step 1: Write failing tests for createSuccessResponse**

```typescript
// cloudflare-workers/api-worker/tests/utils/api-responses.test.ts
import { describe, test, expect } from 'vitest';
import { createSuccessResponse, createErrorResponse } from '../../src/utils/api-responses';
import type { ResponseEnvelope } from '../../src/types/responses';

describe('API Response Utilities', () => {
  test('createSuccessResponse wraps data with metadata', async () => {
    const payload = { id: 123, name: 'Test Book' };
    const response = createSuccessResponse(payload, { traceId: 'abc-123' }, 201);

    expect(response.status).toBe(201);
    expect(response.headers.get('Content-Type')).toBe('application/json');

    const body: ResponseEnvelope<typeof payload> = await response.json();

    expect(body.data).toEqual(payload);
    expect(body.error).toBeUndefined();
    expect(body.metadata.traceId).toBe('abc-123');
    expect(body.metadata.timestamp).toBeDefined();
    expect(new Date(body.metadata.timestamp).getTime()).toBeGreaterThan(0);
  });

  test('createSuccessResponse uses defaults for status and metadata', async () => {
    const payload = { message: 'OK' };
    const response = createSuccessResponse(payload);

    expect(response.status).toBe(200);

    const body: ResponseEnvelope<typeof payload> = await response.json();
    expect(body.data).toEqual(payload);
    expect(body.metadata.timestamp).toBeDefined();
  });

  test('createErrorResponse formats error with code', async () => {
    const response = createErrorResponse('Resource not found', 404, 'E_NOT_FOUND');

    expect(response.status).toBe(404);
    expect(response.headers.get('Content-Type')).toBe('application/json');

    const body: ResponseEnvelope<null> = await response.json();

    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error?.message).toBe('Resource not found');
    expect(body.error?.code).toBe('E_NOT_FOUND');
    expect(body.metadata.timestamp).toBeDefined();
  });

  test('createErrorResponse uses default status 500', async () => {
    const response = createErrorResponse('Internal error');

    expect(response.status).toBe(500);

    const body: ResponseEnvelope<null> = await response.json();
    expect(body.error?.message).toBe('Internal error');
    expect(body.error?.code).toBeUndefined();
  });
});
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd cloudflare-workers/api-worker
npm test -- tests/utils/api-responses.test.ts
```

Expected: FAIL with "Cannot find module '../../src/utils/api-responses'"

**Step 3: Create the api-responses.ts utility**

**Files:**
- Create: `cloudflare-workers/api-worker/src/utils/api-responses.ts`

```typescript
// cloudflare-workers/api-worker/src/utils/api-responses.ts
import type { ResponseEnvelope, ResponseMetadata, ApiError } from '../types/responses';

/**
 * Creates a standardized successful JSON response using the ResponseEnvelope.
 *
 * @param data The payload to send
 * @param metadata Optional metadata (timestamp added automatically)
 * @param status HTTP status code (default: 200)
 * @returns Response object with enveloped JSON
 */
export function createSuccessResponse<T>(
  data: T,
  metadata: Partial<ResponseMetadata> = {},
  status: number = 200
): Response {
  const envelope: ResponseEnvelope<T> = {
    data: data,
    metadata: {
      timestamp: new Date().toISOString(),
      ...metadata,
    },
  };

  return new Response(JSON.stringify(envelope), {
    status: status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Creates a standardized error JSON response using the ResponseEnvelope.
 *
 * @param message The error message
 * @param status The HTTP error status code (default: 500)
 * @param code An optional internal error code
 * @returns Response object with enveloped error JSON
 */
export function createErrorResponse(
  message: string,
  status: number = 500,
  code?: string
): Response {
  const error: ApiError = { message, code };
  const envelope: ResponseEnvelope<null> = {
    data: null,
    metadata: {
      timestamp: new Date().toISOString(),
    },
    error: error,
  };

  return new Response(JSON.stringify(envelope), {
    status: status,
    headers: { 'Content-Type': 'application/json' },
  });
}
```

**Step 4: Run tests to verify they pass**

Run:
```bash
npm test -- tests/utils/api-responses.test.ts
```

Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add src/utils/api-responses.ts tests/utils/api-responses.test.ts
git commit -m "feat(backend): add ResponseEnvelope utility functions

Add createSuccessResponse and createErrorResponse helpers to standardize
all /v1 endpoint responses with canonical envelope format.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 2: Refactor /v1/csv-import

### Task 2.1: Update backend handler to use envelope

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/csv-import.js`

**Step 1: Add import for response utilities**

Find the imports section at the top of `csv-import.js` and add:

```javascript
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';
```

**Step 2: Replace success responses with createSuccessResponse**

Find all instances of:
```javascript
return new Response(JSON.stringify(job), {
  status: 202,
  headers: { 'Content-Type': 'application/json' },
});
```

Replace with:
```javascript
return createSuccessResponse(job, {}, 202);
```

**Step 3: Replace error responses with createErrorResponse**

Find all instances like:
```javascript
return new Response('CSV validation failed', { status: 400 });
```

Replace with:
```javascript
return createErrorResponse('CSV validation failed', 400, 'E_INVALID_CSV');
```

For other error responses, use appropriate error codes:
- `'E_INVALID_CSV'` - CSV validation failures
- `'E_MISSING_FILE'` - Missing file in request
- `'E_FILE_TOO_LARGE'` - File size exceeded
- `'E_INTERNAL'` - Unexpected errors

**Step 4: Verify the handler compiles**

Run:
```bash
npm run build
```

Expected: No errors

**Step 5: Commit**

```bash
git add src/handlers/csv-import.js
git commit -m "refactor(backend): migrate csv-import handler to ResponseEnvelope

Wrap all /v1/csv-import responses in canonical envelope format.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2.2: Update backend tests for csv-import

**Files:**
- Modify: `cloudflare-workers/api-worker/test/csv-import.test.js`

**Step 1: Update success response assertions**

Find all test assertions like:
```javascript
const json = await res.json();
expect(json.jobId).toBeDefined();
expect(json.status).toBe('pending');
```

Replace with:
```javascript
const body = await res.json();
expect(body.data).toBeDefined();
expect(body.data.jobId).toBeDefined();
expect(body.data.status).toBe('pending');
expect(body.metadata).toBeDefined();
expect(body.metadata.timestamp).toBeDefined();
expect(body.error).toBeUndefined();
```

**Step 2: Update error response assertions**

Find error test assertions and update to check envelope:
```javascript
const body = await res.json();
expect(body.data).toBeNull();
expect(body.error).toBeDefined();
expect(body.error.message).toContain('validation failed');
expect(body.error.code).toBe('E_INVALID_CSV');
expect(body.metadata.timestamp).toBeDefined();
```

**Step 3: Run tests to verify they pass**

Run:
```bash
npm test -- test/csv-import.test.js
```

Expected: All tests PASS

**Step 4: Commit**

```bash
git add test/csv-import.test.js
git commit -m "test(backend): update csv-import tests for ResponseEnvelope

Validate envelope structure in all /v1/csv-import test assertions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2.3: Update iOS client for csv-import

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`

**Step 1: Find the uploadCSV method**

Locate the method that calls `/v1/csv-import`:

```swift
public func uploadCSV(data: Data) async throws -> JobStatus {
    let jobStatus: JobStatus = try await apiClient.post(
        to: "v1/csv-import",
        body: data,
        contentType: "text/csv"
    )
    return jobStatus
}
```

**Step 2: Change to decode ResponseEnvelope and unwrap data**

Replace with:

```swift
public func uploadCSV(data: Data) async throws -> JobStatus {
    let response: ResponseEnvelope<JobStatus> = try await apiClient.post(
        to: "v1/csv-import",
        body: data,
        contentType: "text/csv"
    )

    // Unwrap the data from the envelope
    return response.data
}
```

**Step 3: Verify the code compiles**

Run:
```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1
xcodebuild -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift
git commit -m "refactor(ios): decode ResponseEnvelope in GeminiCSVImportService

Unwrap /v1/csv-import response from canonical envelope format.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2.4: Update iOS tests for csv-import

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/GeminiCSVImportServiceTests.swift`

**Step 1: Create ResponseEnvelope test helper (if not exists)**

Add at top of test file:

```swift
extension ResponseEnvelope {
    /// Create a mock ResponseEnvelope for testing
    static func mock<T>(with data: T) -> ResponseEnvelope<T> {
        ResponseEnvelope(
            data: data,
            metadata: ResponseMetadata(timestamp: ISO8601DateFormatter().string(from: Date()))
        )
    }
}
```

**Step 2: Update mock API responses to use envelope**

Find test setup like:
```swift
let mockJob = JobStatus(jobId: "test-123", status: .pending)
let mockData = try JSONEncoder().encode(mockJob)
mockAPIClient.registerMock(response: mockData, for: "v1/csv-import")
```

Replace with:
```swift
let mockJob = JobStatus(jobId: "test-123", status: .pending)
let mockEnvelope = ResponseEnvelope.mock(with: mockJob)
let mockData = try JSONEncoder().encode(mockEnvelope)
mockAPIClient.registerMock(response: mockData, for: "v1/csv-import")
```

**Step 3: Test assertions remain unchanged**

The test assertions on the service's return value should not need changes, since the service unwraps the data:

```swift
let result = try await service.uploadCSV(data: csvData)
#expect(result.jobId == "test-123")
#expect(result.status == .pending)
```

**Step 4: Run iOS tests**

Run:
```bash
xcodebuild test -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: All GeminiCSVImportServiceTests PASS

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/GeminiCSVImportServiceTests.swift
git commit -m "test(ios): update GeminiCSVImportService tests for ResponseEnvelope

Mock enveloped responses in csv-import test fixtures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 3: Refactor /v1/batch-enrich

### Task 3.1: Update batch-enrichment backend handler

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`

**Step 1: Add import**

```javascript
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';
```

**Step 2: Replace response creation**

Find:
```javascript
return new Response(JSON.stringify(job), {
  status: 202,
  headers: { 'Content-Type': 'application/json' },
});
```

Replace with:
```javascript
return createSuccessResponse(job, {}, 202);
```

**Step 3: Update error responses**

Use appropriate error codes:
- `'E_INVALID_REQUEST'` - Missing or invalid request body
- `'E_EMPTY_BATCH'` - Empty ISBNs array
- `'E_INTERNAL'` - Unexpected errors

**Step 4: Build check**

```bash
npm run build
```

Expected: No errors

**Step 5: Commit**

```bash
git add src/handlers/batch-enrichment.js
git commit -m "refactor(backend): migrate batch-enrichment to ResponseEnvelope

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3.2: Update batch-enrichment backend tests

**Files:**
- Modify: `cloudflare-workers/api-worker/tests/integration/batch-enrichment.test.ts`

**Step 1: Update all response parsing**

Find:
```typescript
const job: JobStatus = await resp.json();
expect(job.status).toBe('pending');
```

Replace with:
```typescript
const body: ResponseEnvelope<JobStatus> = await resp.json();
expect(body.data.status).toBe('pending');
expect(body.metadata.timestamp).toBeDefined();
expect(body.error).toBeUndefined();
```

**Step 2: Update error test assertions**

```typescript
const body: ResponseEnvelope<null> = await resp.json();
expect(body.data).toBeNull();
expect(body.error).toBeDefined();
expect(body.error.message).toContain('expected error message');
```

**Step 3: Run tests**

```bash
npm test -- tests/integration/batch-enrichment.test.ts
```

Expected: All tests PASS

**Step 4: Commit**

```bash
git add tests/integration/batch-enrichment.test.ts
git commit -m "test(backend): update batch-enrichment tests for ResponseEnvelope

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3.3: Update iOS EnrichmentAPIClient

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift`

**Step 1: Find submitBatchEnrichmentJob method**

Locate:
```swift
public func submitBatchEnrichmentJob(isbns: [String]) async throws -> JobStatus {
    let payload = ["isbns": isbns]
    let jobStatus: JobStatus = try await post(to: "v1/batch-enrich", body: payload)
    return jobStatus
}
```

**Step 2: Decode envelope and unwrap**

Replace with:
```swift
public func submitBatchEnrichmentJob(isbns: [String]) async throws -> JobStatus {
    let payload = ["isbns": isbns]
    let response: ResponseEnvelope<JobStatus> = try await post(to: "v1/batch-enrich", body: payload)
    return response.data
}
```

**Step 3: Build check**

```bash
xcodebuild -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift
git commit -m "refactor(ios): decode ResponseEnvelope in EnrichmentAPIClient

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3.4: Update iOS enrichment tests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Enrichment/EnrichmentQueueValidationTests.swift`

**Step 1: Update mock API responses**

Find:
```swift
let mockJob = JobStatus(jobId: "enrich-123", status: .pending)
let mockData = try JSONEncoder().encode(mockJob)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-enrich")
```

Replace with:
```swift
let mockJob = JobStatus(jobId: "enrich-123", status: .pending)
let mockEnvelope = ResponseEnvelope.mock(with: mockJob)
let mockData = try JSONEncoder().encode(mockEnvelope)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-enrich")
```

**Step 2: Run tests**

```bash
xcodebuild test -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BooksTrackerFeatureTests/EnrichmentQueueValidationTests
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Enrichment/EnrichmentQueueValidationTests.swift
git commit -m "test(ios): update enrichment tests for ResponseEnvelope

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 4: Refactor /v1/batch-scan (3 endpoints)

### Task 4.1: Update batch-scan backend handlers

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`

**Step 1: Add import**

```javascript
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';
```

**Step 2: Update handleBatchScanSubmit**

Find:
```javascript
return new Response(JSON.stringify(jobStatus), {
  status: 202,
  headers: { 'Content-Type': 'application/json' },
});
```

Replace with:
```javascript
return createSuccessResponse(jobStatus, {}, 202);
```

**Step 3: Update handleBatchScanProgress**

Find:
```javascript
return new Response(JSON.stringify(jobStatus), {
  status: 200,
  headers: { 'Content-Type': 'application/json' },
});
```

Replace with:
```javascript
return createSuccessResponse(jobStatus);
```

**Step 4: Update handleBatchScanResults**

Find:
```javascript
return new Response(JSON.stringify(results), {
  status: 200,
  headers: { 'Content-Type': 'application/json' },
});
```

Replace with:
```javascript
return createSuccessResponse(results);
```

**Step 5: Update error responses**

Use error codes:
- `'E_INVALID_JOB_ID'` - Missing or invalid jobId
- `'E_JOB_NOT_FOUND'` - Job doesn't exist
- `'E_INVALID_IMAGES'` - Invalid image data
- `'E_INTERNAL'` - Unexpected errors

**Step 6: Build check**

```bash
npm run build
```

Expected: No errors

**Step 7: Commit**

```bash
git add src/handlers/batch-scan-handler.js
git commit -m "refactor(backend): migrate batch-scan handlers to ResponseEnvelope

Wrap submit, progress, and results endpoints in canonical envelope.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4.2: Update batch-scan backend tests

**Files:**
- Modify: `cloudflare-workers/api-worker/tests/batch-scan.test.js`

**Step 1: Update submit endpoint tests**

Find:
```javascript
const json = await res.json();
expect(json.jobId).toBeDefined();
```

Replace with:
```javascript
const body = await res.json();
expect(body.data).toBeDefined();
expect(body.data.jobId).toBeDefined();
expect(body.metadata.timestamp).toBeDefined();
```

**Step 2: Update progress endpoint tests**

Find:
```javascript
const status = await res.json();
expect(status.status).toBe('processing');
```

Replace with:
```javascript
const body = await res.json();
expect(body.data.status).toBe('processing');
expect(body.metadata.timestamp).toBeDefined();
```

**Step 3: Update results endpoint tests**

Find:
```javascript
const results = await res.json();
expect(results.books).toBeDefined();
```

Replace with:
```javascript
const body = await res.json();
expect(body.data).toBeDefined();
expect(body.data.books).toBeDefined();
expect(body.metadata.timestamp).toBeDefined();
```

**Step 4: Run tests**

```bash
npm test -- tests/batch-scan.test.js
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add tests/batch-scan.test.js
git commit -m "test(backend): update batch-scan tests for ResponseEnvelope

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4.3: Update iOS BookshelfAIService

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`

**Step 1: Update submitScanJob**

Find:
```swift
public func submitScanJob(images: [ProcessedBookshelfImage]) async throws -> JobStatus {
    // ... image preparation code ...
    let jobStatus: JobStatus = try await apiClient.post(
        to: "v1/batch-scan",
        body: payload
    )
    return jobStatus
}
```

Replace return section with:
```swift
    let response: ResponseEnvelope<JobStatus> = try await apiClient.post(
        to: "v1/batch-scan",
        body: payload
    )
    return response.data
```

**Step 2: Update pollJobStatus**

Find:
```swift
public func pollJobStatus(jobId: String) async throws -> JobStatus {
    let jobStatus: JobStatus = try await apiClient.get(
        from: "v1/batch-scan/progress/\(jobId)"
    )
    return jobStatus
}
```

Replace with:
```swift
public func pollJobStatus(jobId: String) async throws -> JobStatus {
    let response: ResponseEnvelope<JobStatus> = try await apiClient.get(
        from: "v1/batch-scan/progress/\(jobId)"
    )
    return response.data
}
```

**Step 3: Update fetchJobResults**

Find:
```swift
public func fetchJobResults(jobId: String) async throws -> BatchScanResults {
    let results: BatchScanResults = try await apiClient.get(
        from: "v1/batch-scan/results/\(jobId)"
    )
    return results
}
```

Replace with:
```swift
public func fetchJobResults(jobId: String) async throws -> BatchScanResults {
    let response: ResponseEnvelope<BatchScanResults> = try await apiClient.get(
        from: "v1/batch-scan/results/\(jobId)"
    )
    return response.data
}
```

**Step 4: Build check**

```bash
xcodebuild -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
git commit -m "refactor(ios): decode ResponseEnvelope in BookshelfAIService

Unwrap all batch-scan endpoint responses from canonical envelope.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4.4: Update iOS batch-scan tests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServiceTests.swift`
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServicePollingTests.swift`
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfScanning/ScanResultsModelTests.swift`

**Step 1: Update BookshelfAIServiceTests mocks**

Find submitScanJob test mocks:
```swift
let mockJob = JobStatus(jobId: "scan-123", status: .pending)
let mockData = try JSONEncoder().encode(mockJob)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-scan")
```

Replace with:
```swift
let mockJob = JobStatus(jobId: "scan-123", status: .pending)
let mockEnvelope = ResponseEnvelope.mock(with: mockJob)
let mockData = try JSONEncoder().encode(mockEnvelope)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-scan")
```

**Step 2: Update polling test mocks**

In `BookshelfAIServicePollingTests.swift`, update progress mocks:

```swift
let mockStatus = JobStatus(jobId: "scan-123", status: .processing, progress: 50)
let mockEnvelope = ResponseEnvelope.mock(with: mockStatus)
let mockData = try JSONEncoder().encode(mockEnvelope)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-scan/progress/scan-123")
```

**Step 3: Update results test mocks**

In `ScanResultsModelTests.swift`, update results mocks:

```swift
let mockResults = BatchScanResults(/* ... */)
let mockEnvelope = ResponseEnvelope.mock(with: mockResults)
let mockData = try JSONEncoder().encode(mockEnvelope)
mockAPIClient.registerMock(response: mockData, for: "v1/batch-scan/results/scan-123")
```

**Step 4: Run all bookshelf tests**

```bash
xcodebuild test -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:BooksTrackerFeatureTests/BookshelfAIServiceTests -only-testing:BooksTrackerFeatureTests/BookshelfAIServicePollingTests -only-testing:BooksTrackerFeatureTests/ScanResultsModelTests
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServiceTests.swift \
        BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfAIServicePollingTests.swift \
        BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfScanning/ScanResultsModelTests.swift
git commit -m "test(ios): update batch-scan tests for ResponseEnvelope

Mock enveloped responses in all bookshelf scanning test fixtures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 5: Validation

### Task 5.1: Run full backend test suite

**Step 1: Run all backend tests**

```bash
cd cloudflare-workers/api-worker
npm test
```

Expected: All tests PASS (including new api-responses tests and all migrated endpoint tests)

**Step 2: Check for any test warnings**

Expected: No warnings about missing assertions or type mismatches

**Step 3: Verify test coverage**

```bash
npm run test:coverage
```

Expected: Coverage maintained or improved (especially for response utilities)

---

### Task 5.2: Run full iOS test suite

**Step 1: Run all iOS tests**

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1
xcodebuild test -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: All tests PASS with zero warnings

**Step 2: Verify zero warnings**

Check build output for:
- No decoding warnings
- No type mismatch warnings
- No deprecation warnings

Expected: Clean build

---

### Task 5.3: Manual iOS simulator testing

**Step 1: Launch app in simulator**

```bash
/sim
```

Wait for app to launch and show Library view.

**Step 2: Test CSV Import flow**

1. Navigate to Settings → Library Management → "AI-Powered CSV Import"
2. Select a test CSV file
3. Verify upload starts and job ID appears
4. Wait for completion
5. Check books appear in library

Expected: Flow completes without errors, books imported successfully

**Step 3: Test Bookshelf Scan flow**

1. Navigate to Shelf tab
2. Tap "Batch Capture"
3. Add 1-2 test images (use test images from docs/testImages/)
4. Submit scan
5. Observe progress updates
6. Wait for results
7. Verify books detected and can be added to library

Expected: Scan completes, progress updates appear, results load correctly

**Step 4: Test Batch Enrichment flow**

1. Go to Settings → Library Management
2. If enrichment queue banner appears, tap "Start Enrichment"
3. Observe progress
4. Wait for completion

Expected: Enrichment job starts, progresses, completes successfully

**Step 5: Check app logs for errors**

In simulator output, check for:
- Decoding errors
- Network errors
- Unexpected nil values

Expected: No errors related to API response parsing

---

### Task 5.4: Deploy backend and smoke test

**Step 1: Deploy to production**

```bash
cd cloudflare-workers/api-worker
npx wrangler deploy
```

Expected: Deployment succeeds

**Step 2: Test health endpoint**

```bash
/backend-health
```

Expected: Returns healthy status with ResponseEnvelope structure

**Step 3: Test one endpoint manually**

```bash
curl -X POST https://api-worker.your-domain.workers.dev/v1/csv-import \
  -H "Content-Type: text/csv" \
  -d "Title,Author,ISBN
The Great Gatsby,F. Scott Fitzgerald,9780743273565"
```

Expected: Response contains `{ data: {...}, metadata: {...} }` structure

**Step 4: Monitor logs**

```bash
/logs
```

Watch for 2-3 minutes for any errors

Expected: No errors, normal operation

---

### Task 5.5: Final commit and documentation

**Step 1: Update CHANGELOG.md**

Add entry:

```markdown
## [Unreleased]

### Changed
- **API Contract**: All `/v1/*` endpoints now return responses wrapped in canonical `ResponseEnvelope<T>` format
- **Backend**: Added `createSuccessResponse` and `createErrorResponse` utilities for standardized responses
- **iOS**: Updated all API clients to decode and unwrap `ResponseEnvelope` responses

### Migration Notes
- Backend and iOS changes deployed simultaneously to maintain compatibility
- All endpoints now include standardized `metadata` (timestamp, etc.) and optional `error` objects
- Improved error handling with structured error codes (`E_INVALID_CSV`, `E_NOT_FOUND`, etc.)

### Endpoints Updated
- `POST /v1/csv-import` - CSV upload job submission
- `POST /v1/batch-enrich` - Batch enrichment job submission
- `POST /v1/batch-scan` - Bookshelf scan job submission
- `GET /v1/batch-scan/progress/:jobId` - Scan job progress polling
- `GET /v1/batch-scan/results/:jobId` - Scan job results retrieval
```

**Step 2: Create final summary commit**

```bash
git add CHANGELOG.md
git commit -m "docs: document ResponseEnvelope migration in CHANGELOG

All /v1 endpoints now use canonical envelope format for improved
error handling and consistent API contracts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Step 3: Push all changes**

```bash
git push origin main
```

Expected: All commits pushed successfully

---

## Rollback Plan

### If Backend Issues Detected

**Step 1: Check Wrangler deployment history**

```bash
npx wrangler deployments list
```

**Step 2: Rollback to previous version**

```bash
npx wrangler rollback
```

**Step 3: Verify rollback**

```bash
/backend-health
curl https://api-worker.your-domain.workers.dev/v1/batch-scan/progress/test-id
```

Expected: Old response format (without envelope)

---

### If iOS Issues Detected

**Step 1: Revert iOS commits**

```bash
git log --oneline -20  # Find commit before envelope migration
git revert <commit-hash-range>
```

**Step 2: Build hotfix**

```bash
/build
```

Expected: Build succeeds with reverted code

**Step 3: Deploy hotfix to TestFlight**

Follow normal release process with reverted client code.

---

## Success Criteria

✅ All backend tests pass (100% pass rate)
✅ All iOS tests pass (zero warnings)
✅ Manual testing: CSV import works
✅ Manual testing: Bookshelf scan works
✅ Manual testing: Batch enrichment works
✅ No decoding errors in app logs
✅ Backend deployed successfully
✅ Health check returns enveloped response
✅ CHANGELOG.md updated
✅ All commits pushed to main

---

## Estimated Time

- Phase 1 (Utilities): 15 minutes
- Phase 2 (CSV Import): 20 minutes
- Phase 3 (Batch Enrich): 20 minutes
- Phase 4 (Batch Scan): 30 minutes
- Phase 5 (Validation): 30 minutes

**Total: ~2 hours** (with testing and validation)

---

## Notes for Engineer

- **DRY**: The `createSuccessResponse` and `createErrorResponse` utilities eliminate code duplication
- **YAGNI**: We're only migrating the 5 endpoints that actually need it, not all legacy endpoints
- **TDD**: We wrote tests for response utilities FIRST, then implemented them
- **Frequent Commits**: Each task ends with a commit, creating a clear audit trail
- **Rollback Safety**: Backend and iOS changes paired per endpoint, easy to revert together

**Error Code Conventions:**
- `E_INVALID_*` - Validation failures (400)
- `E_NOT_FOUND` - Resource not found (404)
- `E_INTERNAL` - Unexpected server errors (500)
- `E_MISSING_*` - Missing required fields (400)

**Testing Strategy:**
- Backend: Validate envelope structure in all responses
- iOS: Mock enveloped responses, test unwrapping logic
- Manual: End-to-end user flows to catch integration issues
