# Canonical Data Contracts Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate backend enrichment services and iOS search/enrichment layers to use canonical WorkDTO/EditionDTO/AuthorDTO format.

**Architecture:** Bottom-up migration - backend services first (return canonical format), then iOS integration (parse canonical responses), finally conservative cleanup (remove unused legacy code).

**Tech Stack:**
- Backend: Cloudflare Workers, TypeScript canonical handlers
- iOS: Swift 6.2, SwiftUI, SwiftData, Codable DTOs
- Testing: Backend unit tests, iOS Swift Testing, real device validation

---

## Phase 1: Backend Migration (3-4 hours)

### Task 1: Update parallel-enrichment.js to use v1 handler

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/parallel-enrichment.js`

**Step 1: Read current implementation**

Run: `cat cloudflare-workers/api-worker/src/services/parallel-enrichment.js | head -50`
Understand: Current code calls `handleAdvancedSearch` (legacy)

**Step 2: Update import to use v1 handler**

In `parallel-enrichment.js`, change:
```javascript
// OLD
import { handleAdvancedSearch } from '../handlers/search-handlers.js';

// NEW
import { handleSearchAdvanced } from '../handlers/v1/search-advanced.js';
```

**Step 3: Update function call to v1 handler**

Find where `handleAdvancedSearch` is called, replace with:
```javascript
// OLD
const result = await handleAdvancedSearch({ bookTitle: title, authorName: author }, { maxResults: 1 }, env);

// NEW
const result = await handleSearchAdvanced(title, author, env);
```

**Step 4: Update response parsing for canonical format**

The v1 handler returns `ApiResponse<BookSearchResponse>` instead of raw results. Update parsing:

```javascript
// OLD
if (result && result.items && result.items.length > 0) {
  return result.items[0];
}

// NEW
if (result.success && result.data && result.data.works && result.data.works.length > 0) {
  return {
    work: result.data.works[0],
    editions: result.data.works[0].editions || [],
    authors: result.data.authors || []
  };
}
```

**Step 5: Commit**

```bash
cd cloudflare-workers/api-worker
git add src/services/parallel-enrichment.js
git commit -m "refactor(enrichment): use v1 canonical handler for parallel enrichment

- Import handleSearchAdvanced from v1 handler
- Parse ApiResponse<BookSearchResponse> canonical format
- Return structured { work, editions, authors } instead of raw items

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Update enrichment.js enrichBatch to return canonical format

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/enrichment.js:68-180`

**Step 1: Read current enrichBatch implementation**

Run: `sed -n '68,180p' cloudflare-workers/api-worker/src/services/enrichment.js`
Understand: Currently returns `enrichedWorks` array with raw Google Books format

**Step 2: Update enrichment loop to use canonical response**

In the `for (const workId of workIds)` loop (around line 85-150), the enrichment calls `handleAdvancedSearch` indirectly. Since `parallel-enrichment.js` now returns canonical format, update the enrichedWorks accumulation:

```javascript
// OLD (around line 118-125)
const enriched = await enrichBook(workId, env);
if (enriched) {
  enrichedWorks.push(enriched);
}

// NEW - enrichBook now returns { work, editions, authors }
const enriched = await enrichBook(workId, env);
if (enriched) {
  // Accumulate canonical DTOs
  enrichedWorks.push({
    work: enriched.work,
    editions: enriched.editions,
    authors: enriched.authors
  });
}
```

**Step 3: Update final WebSocket response format**

Change the final progress update (around line 157-172) to send canonical format:

```javascript
// OLD
await doStub.pushProgress({
  progress: 1.0,
  processedItems: processedCount,
  totalItems: totalCount,
  currentStatus: 'Enrichment complete',
  jobId,
  result: {
    success: true,
    processedCount: processedCount,
    totalCount: totalCount,
    enrichedCount: enrichedWorks.length,
    errorCount: errors.length,
    enrichedWorks: enrichedWorks,  // <- Legacy format
    errors: errors
  }
});

// NEW
await doStub.pushProgress({
  progress: 1.0,
  processedItems: processedCount,
  totalItems: totalCount,
  currentStatus: 'Enrichment complete',
  jobId,
  result: {
    success: true,
    processedCount: processedCount,
    totalCount: totalCount,
    enrichedCount: enrichedWorks.length,
    errorCount: errors.length,
    works: enrichedWorks.map(item => item.work),  // Canonical WorkDTO array
    editions: enrichedWorks.flatMap(item => item.editions),  // All EditionDTOs
    authors: enrichedWorks.flatMap(item => item.authors),  // All AuthorDTOs
    errors: errors
  }
});
```

**Step 4: Commit**

```bash
git add src/services/enrichment.js
git commit -m "refactor(enrichment): return canonical WorkDTO/EditionDTO format via WebSocket

- Update enrichBatch to send works/editions/authors arrays
- Replace enrichedWorks (legacy) with canonical DTO structure
- iOS EnrichmentService can now parse canonical format

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Update ai-scanner.js to use canonical enrichment

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/ai-scanner.js:98-162`

**Step 1: Read current AI scanner enrichment**

Run: `sed -n '98,162p' cloudflare-workers/api-worker/src/services/ai-scanner.js`
Understand: Calls `enrichBooksParallel` which now returns canonical format

**Step 2: Update enrichedBooks handling**

Since `enrichBooksParallel` (in `parallel-enrichment.js`) now returns canonical format, update how we process the results (around line 100-150):

```javascript
// OLD
const enrichedBooks = await enrichBooksParallel(
  detectedBooks,
  env,
  doStub,
  jobId
);

// enrichedBooks is array of Google Books items

// NEW - enrichedBooks now has { work, editions, authors } structure
const enrichmentResults = await enrichBooksParallel(
  detectedBooks,
  env,
  doStub,
  jobId
);

// Extract canonical DTOs
const enrichedBooks = enrichmentResults.map(result => ({
  ...result.detection,  // Original AI detection data
  work: result.enrichment.work,
  editions: result.enrichment.editions,
  authors: result.enrichment.authors
}));
```

**Step 3: Update final WebSocket result format**

Change the completion message (around line 140-160) to send canonical format:

```javascript
// OLD
await doStub.pushProgress({
  progress: 1.0,
  processedItems: 3,
  totalItems: 3,
  currentStatus: 'Scan complete',
  jobId,
  result: {
    status: 'completed',
    totalBooks: detectedBooks.length,
    approved: approved.length,
    needsReview: review.length,
    books: enrichedBooks,  // <- Legacy Google Books format
    metadata: { processingTime, enrichedCount, timestamp, modelUsed }
  }
});

// NEW
await doStub.pushProgress({
  progress: 1.0,
  processedItems: 3,
  totalItems: 3,
  currentStatus: 'Scan complete',
  jobId,
  result: {
    status: 'completed',
    totalBooks: detectedBooks.length,
    approved: approved.length,
    needsReview: review.length,
    works: enrichedBooks.map(b => b.work),  // Canonical WorkDTO array
    editions: enrichedBooks.flatMap(b => b.editions),  // All EditionDTOs
    authors: enrichedBooks.flatMap(b => b.authors),  // All AuthorDTOs
    detections: detectedBooks,  // Original AI detection data
    metadata: { processingTime, enrichedCount, timestamp, modelUsed }
  }
});
```

**Step 4: Commit**

```bash
git add src/services/ai-scanner.js
git commit -m "refactor(ai-scanner): return canonical format from bookshelf scanning

- Update enrichment result handling for canonical DTOs
- Send works/editions/authors arrays via WebSocket
- Preserve original AI detection data alongside enrichment

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Write backend integration test for canonical enrichment

**Files:**
- Create: `cloudflare-workers/api-worker/tests/canonical-enrichment.test.js`

**Step 1: Write failing test for enrichment canonical format**

```javascript
// tests/canonical-enrichment.test.js
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { unstable_dev } from 'wrangler';

describe('Canonical Enrichment Format', () => {
  let worker;

  beforeAll(async () => {
    worker = await unstable_dev('src/index.js', {
      experimental: { disableExperimentalWarning: true }
    });
  });

  afterAll(async () => {
    await worker.stop();
  });

  it('should return canonical WorkDTO/EditionDTO format from enrichment', async () => {
    // Start enrichment job
    const jobId = crypto.randomUUID();
    const response = await worker.fetch('http://localhost/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        workIds: ['isbn:9780451524935']  // 1984 by George Orwell
      })
    });

    expect(response.status).toBe(202);

    // Connect to WebSocket and wait for completion
    // (This is simplified - real test would use WebSocket client)

    // Verify response has canonical structure
    // Expected: { works: [WorkDTO], editions: [EditionDTO], authors: [AuthorDTO] }
    // NOT: { enrichedWorks: [GoogleBooksItem] }
  });

  it('should return canonical format from AI bookshelf scanning', async () => {
    // Upload test bookshelf image
    const jobId = crypto.randomUUID();

    // (Simplified test structure)
    // Verify AI scan result has: { works, editions, authors, detections, metadata }
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test -- canonical-enrichment.test.js`
Expected: Test runner finds file, tests may fail or be incomplete (we need actual WebSocket testing)

**Step 3: Note: Full WebSocket testing requires mock DO**

Add comment in test file:
```javascript
// TODO: Full WebSocket testing requires mocking ProgressWebSocketDO
// For now, validate structure manually with curl + wscat
// Manual test: npm run dev, then wscat -c ws://localhost:8787/ws/progress?jobId=test
```

**Step 4: Commit test skeleton**

```bash
git add tests/canonical-enrichment.test.js
git commit -m "test(enrichment): add canonical format integration test skeleton

- Test structure for enrichment WebSocket format
- Test structure for AI scanning format
- Note: Full WebSocket testing requires DO mocking

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Manual backend validation

**Files:**
- None (manual testing)

**Step 1: Start Wrangler dev server**

Run: `cd cloudflare-workers/api-worker && npx wrangler dev --port 8787`
Expected: Server starts on http://localhost:8787

**Step 2: Test v1 search endpoint returns canonical format**

Run: `curl "http://localhost:8787/v1/search/title?q=1984" | jq '.data.works[0].title'`
Expected: Returns "1984" (confirms canonical WorkDTO structure)

**Step 3: Test enrichment WebSocket (manual with wscat)**

Terminal 1:
```bash
wscat -c "ws://localhost:8787/ws/progress?jobId=test-enrichment"
# Wait for connection
```

Terminal 2:
```bash
curl -X POST http://localhost:8787/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test-enrichment","workIds":["isbn:9780451524935"]}'
```

Expected in Terminal 1: WebSocket messages with `{ works: [WorkDTO], editions: [...], authors: [...] }` structure

**Step 4: Document validation results**

Create validation notes:
```bash
echo "# Backend Canonical Format Validation

Date: $(date)

✅ /v1/search/title returns ApiResponse<BookSearchResponse>
✅ WorkDTO structure: title, authors, googleBooksVolumeIDs
✅ Enrichment WebSocket sends canonical format
✅ AI scanner WebSocket sends canonical format

Manual testing complete." > docs/validation-backend-canonical.md

git add docs/validation-backend-canonical.md
git commit -m "docs(validation): backend canonical format manual testing complete"
```

---

### Task 6: Deploy backend to Cloudflare Workers

**Files:**
- None (deployment)

**Step 1: Run all backend tests**

Run: `cd cloudflare-workers/api-worker && npm test`
Expected: All tests pass (18 existing + new tests)

**Step 2: Deploy to production**

Run: `npx wrangler deploy`
Expected: Deployment succeeds, shows new version URL

**Step 3: Verify production endpoints**

Run: `curl "https://books-api-proxy.jukasdrj.workers.dev/v1/search/title?q=test" | jq '.success'`
Expected: Returns `true`

**Step 4: Tag backend release**

```bash
git tag -a backend-canonical-v1.0 -m "Backend canonical contracts migration complete

- Enrichment returns WorkDTO/EditionDTO format
- AI scanning uses canonical handlers
- WebSocket messages have structured DTOs

Phase 1 complete. Ready for iOS integration."

git push origin backend-canonical-v1.0
```

---

## Phase 2: iOS Migration (4-5 hours)

### Task 7: Update BookSearchAPIService to use /v1/search/title

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift:31-121`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookSearchAPIServiceTests.swift` (if exists)

**Step 1: Read current search() method**

Run: `sed -n '31,121p' BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
Understand: Currently calls `/search/title` and decodes `APISearchResponse`

**Step 2: Update endpoint URL to v1**

Change line 31 (endpoint URL):
```swift
// OLD
let endpoint = "\(baseURL)/search/title?q=\(encodedQuery)&maxResults=\(maxResults)"

// NEW
let endpoint = "\(baseURL)/v1/search/title?q=\(encodedQuery)"
```

**Step 3: Update response decoding to canonical format**

Replace lines 73-78 (response parsing):
```swift
// OLD
let response = try JSONDecoder().decode(APISearchResponse.self, from: data)
let results = response.items.map { convertAPIBookItemToSearchResult($0) }
return results

// NEW - Parse canonical ApiResponse<BookSearchResponse>
let envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)

switch envelope {
case .success(let searchData, let meta):
    // Map WorkDTOs to SwiftData models using DTOMapper
    let works = searchData.works.compactMap { workDTO in
        try? DTOMapper.mapToWork(dto: workDTO, context: modelContext)
    }
    return works

case .failure(let error, let meta):
    // Handle structured error codes
    throw mapApiError(error)
}
```

**Step 4: Add error mapping helper**

Add new method after search():
```swift
private func mapApiError(_ error: ApiError) -> Error {
    switch error.code {
    case .invalidQuery:
        return SearchError.invalidQuery(error.message)
    case .invalidISBN:
        return SearchError.invalidISBN(error.message)
    case .providerError:
        return SearchError.providerUnavailable(error.message)
    case .internalError:
        return SearchError.serverError(error.message)
    }
}

enum SearchError: LocalizedError {
    case invalidQuery(String)
    case invalidISBN(String)
    case providerUnavailable(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuery(let msg): return msg
        case .invalidISBN(let msg): return msg
        case .providerUnavailable(let msg): return msg
        case .serverError(let msg): return msg
        }
    }
}
```

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(search): migrate search() to /v1/search/title with canonical DTOs

- Use /v1/search/title endpoint
- Parse ApiResponse<BookSearchResponse> envelope
- Map WorkDTO to SwiftData Work via DTOMapper
- Add structured error handling for ApiError codes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Update BookSearchAPIService searchByISBN to use /v1/search/isbn

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift` (searchByISBN method)

**Step 1: Locate searchByISBN method**

Run: `grep -n "func searchByISBN" BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
Understand: Method signature and current implementation

**Step 2: Update endpoint URL**

Change endpoint to v1:
```swift
// OLD
let endpoint = "\(baseURL)/search/isbn?isbn=\(isbn)&maxResults=1"

// NEW
let endpoint = "\(baseURL)/v1/search/isbn?isbn=\(isbn)"
```

**Step 3: Update response parsing (same as Task 7)**

Replace response decoding:
```swift
let envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)

switch envelope {
case .success(let searchData, _):
    let works = searchData.works.compactMap { workDTO in
        try? DTOMapper.mapToWork(dto: workDTO, context: modelContext)
    }
    return works.first

case .failure(let error, _):
    throw mapApiError(error)
}
```

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(search): migrate searchByISBN to /v1/search/isbn

- Use /v1/search/isbn endpoint
- Parse canonical ApiResponse envelope
- Map EditionDTO → SwiftData Edition via DTOMapper

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Update BookSearchAPIService advancedSearch to use /v1/search/advanced

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift:154-250`

**Step 1: Locate advancedSearch method**

Run: `sed -n '154,250p' BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`

**Step 2: Update endpoint URL**

Change lines 154, 159:
```swift
// OLD
let endpoint = "\(baseURL)/search/advanced?title=\(encodedTitle)&author=\(encodedAuthor)&maxResults=\(maxResults)"

// NEW
let endpoint = "\(baseURL)/v1/search/advanced?title=\(encodedTitle)&author=\(encodedAuthor)"
```

**Step 3: Update response parsing**

Same pattern as Tasks 7-8:
```swift
let envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)

switch envelope {
case .success(let searchData, _):
    return searchData.works.compactMap { workDTO in
        try? DTOMapper.mapToWork(dto: workDTO, context: modelContext)
    }

case .failure(let error, _):
    throw mapApiError(error)
}
```

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(search): migrate advancedSearch to /v1/search/advanced

- Use /v1/search/advanced endpoint
- Consistent canonical DTO parsing across all search methods

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Remove legacy response types from BookSearchAPIService

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift` (bottom of file)

**Step 1: Identify legacy types to remove**

Run: `grep -n "private struct API" BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
Expected: Find `APISearchResponse`, `APIBookItem`, `APIVolumeInfo`, etc. (lines 388-430)

**Step 2: Remove legacy type definitions**

Delete these structs (lines ~388-430):
- `APISearchResponse`
- `APIBookItem`
- `APIVolumeInfo`
- `APIIndustryIdentifier`
- `APIImageLinks`

**Step 3: Remove legacy conversion method**

Delete `convertEnhancedItemToSearchResult()` method (lines 328-382)

**Step 4: Verify no references remain**

Run: `grep -n "APISearchResponse\|APIBookItem\|convertEnhancedItem" BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
Expected: No matches (all removed)

**Step 5: Build to verify no compilation errors**

Run: `/build`
Expected: Clean build, zero errors

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(search): remove legacy response types

Removed (~200 lines):
- APISearchResponse, APIBookItem, APIVolumeInfo
- APIIndustryIdentifier, APIImageLinks
- convertEnhancedItemToSearchResult() method

All search methods now use canonical DTOs exclusively.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Update EnrichmentService to parse canonical WebSocket format

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift:138-250`

**Step 1: Read current WebSocket response parsing**

Run: `sed -n '138,250p' BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift`
Understand: Currently decodes `EnrichmentSearchResponse` (legacy Google Books)

**Step 2: Update WebSocket message parsing**

Find where WebSocket result is parsed (around line 141-143), change:

```swift
// OLD
let response = try JSONDecoder().decode(EnrichmentSearchResponse.self, from: resultData)
let items = response.items

// NEW - Parse canonical format: { works: [WorkDTO], editions: [EditionDTO], authors: [AuthorDTO] }
struct CanonicalEnrichmentResult: Codable {
    let works: [WorkDTO]
    let editions: [EditionDTO]
    let authors: [AuthorDTO]
    let processedCount: Int
    let totalCount: Int
}

let result = try JSONDecoder().decode(CanonicalEnrichmentResult.self, from: resultData)
```

**Step 3: Update model mapping to use DTOMapper**

Replace the conversion logic:

```swift
// OLD
for item in items {
    let work = convertVolumeItemToWork(item)
    // ... save to SwiftData
}

// NEW
for workDTO in result.works {
    let work = try DTOMapper.mapToWork(dto: workDTO, context: modelContext)
    // work is already inserted and deduplication handled by DTOMapper
}
```

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift
git commit -m "refactor(enrichment): parse canonical WebSocket format

- Parse { works, editions, authors } from WebSocket
- Use DTOMapper for WorkDTO → SwiftData Work conversion
- Deduplication automatically handled by mapper

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 12: Remove legacy types from EnrichmentService

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift:323-415`

**Step 1: Identify legacy types**

Run: `sed -n '323,415p' BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift`
Expected: Find `EnrichmentSearchResponse`, `VolumeItem`, `VolumeInfo`, etc.

**Step 2: Delete legacy type definitions**

Remove these structs (lines ~323-415):
- `EnrichmentSearchResponse`
- `VolumeItem`
- `VolumeInfo`
- `ImageLinks`
- `CrossReferenceIds`
- `IndustryIdentifier`
- `EnrichmentSearchResult`
- `EnrichmentSearchResponseFlat`

**Step 3: Verify no references remain**

Run: `grep -n "EnrichmentSearchResponse\|VolumeItem\|VolumeInfo" BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift`
Expected: No matches

**Step 4: Build and verify**

Run: `/build`
Expected: Clean build

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentService.swift
git commit -m "refactor(enrichment): remove legacy response types

Removed:
- EnrichmentSearchResponse and nested types (~90 lines)
- Legacy Google Books response parsing

Enrichment now uses canonical DTOs exclusively.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 13: Write iOS integration test for canonical parsing

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/DTOTests.swift`

**Step 1: Add real API response test**

Append to `DTOTests.swift`:

```swift
@Test("Parse real v1 API response")
func testRealV1APIResponse() async throws {
    let url = URL(string: "https://books-api-proxy.jukasdrj.workers.dev/v1/search/title?q=1984")!
    let (data, _) = try await URLSession.shared.data(from: url)

    let envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)

    switch envelope {
    case .success(let searchData, let meta):
        #expect(searchData.works.count > 0, "Should find works for '1984'")
        #expect(searchData.works[0].title.contains("1984"), "First work should be 1984")
        #expect(meta.provider == "google-books", "Should use Google Books provider")

    case .failure(let error, _):
        Issue.record("API returned error: \(error.message)")
    }
}
```

**Step 2: Run test**

Run: `/test`
Expected: Test passes, confirms real API returns parseable canonical format

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/DTOTests.swift
git commit -m "test(dto): add real API response validation test

- Test v1 endpoint returns parseable ApiResponse<BookSearchResponse>
- Validates WorkDTO structure from live API
- Confirms production API compatibility

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 14: Real device testing validation

**Files:**
- None (manual testing)

**Step 1: Deploy to device**

Run: `/device-deploy`
Expected: App installs on physical iPhone

**Step 2: Test search flow**

Manual test:
1. Open app
2. Go to Search tab
3. Search for "Harry Potter"
4. Verify: Results appear correctly
5. Tap a book → Verify: Detail view loads
6. Add to library → Verify: Book saves successfully

**Step 3: Test ISBN scanning**

Manual test:
1. Scan a book barcode
2. Verify: Book found by ISBN
3. Check library → Verify: No duplicate Works (deduplication working)

**Step 4: Test enrichment**

Manual test:
1. Import CSV with minimal data (title + author only)
2. Watch enrichment progress
3. Verify: Books appear with cover images and full metadata
4. Check WebSocket logs → Verify: Canonical format received

**Step 5: Test AI scanning**

Manual test:
1. Upload bookshelf photo
2. Watch scan progress
3. Verify: Books detected and enriched
4. Check results → Verify: Canonical WorkDTO structure

**Step 6: Document validation**

```bash
echo "# iOS Canonical Format Validation

Date: $(date)

✅ Search by title returns canonical DTOs
✅ ISBN search works with deduplication
✅ Background enrichment parses WebSocket canonical format
✅ AI bookshelf scanning returns canonical results
✅ Error codes display user-friendly messages
✅ No SwiftData crashes (insert-before-relate working)

Real device testing complete. iOS migration successful." > docs/validation-ios-canonical.md

git add docs/validation-ios-canonical.md
git commit -m "docs(validation): iOS canonical format real device testing complete"
```

---

### Task 15: Update CLAUDE.md documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update API endpoint examples**

Find references to `/search/title`, `/search/isbn`, etc. Replace with `/v1/` versions:

```markdown
<!-- OLD -->
GET /search/title?q={query} - Title search (6h cache)
GET /search/isbn?isbn={isbn} - ISBN lookup (7-day cache)

<!-- NEW -->
GET /v1/search/title?q={query} - Title search (canonical WorkDTO format)
GET /v1/search/isbn?isbn={isbn} - ISBN lookup (canonical EditionDTO format)
```

**Step 2: Add canonical response format documentation**

Add section:
```markdown
### Canonical Data Contracts (v1.0.0)

All `/v1/*` endpoints return structured responses:

**Response Envelope:**
\`\`\`json
{
  "success": true,
  "data": { "works": [WorkDTO], "authors": [AuthorDTO] },
  "meta": { "timestamp": "...", "provider": "google-books", "cached": false }
}
\`\`\`

**Error Handling:**
- `INVALID_QUERY` - Empty/invalid search parameters
- `INVALID_ISBN` - Malformed ISBN format
- `PROVIDER_ERROR` - Upstream API failure
- `INTERNAL_ERROR` - Server error
```

**Step 3: Remove legacy format references**

Delete documentation for:
- `APISearchResponse` structure
- Legacy Google Books response format
- Old enrichment response types

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): update for canonical data contracts

- Document /v1/ endpoint usage
- Add ApiResponse<T> envelope structure
- Document error codes and handling
- Remove legacy response format docs

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 16: Add CHANGELOG.md entry

**Files:**
- Modify: `CHANGELOG.md`

**Step 1: Add new version entry**

Prepend to CHANGELOG.md:

```markdown
## [3.3.0] - 2025-10-30

### Changed
- **Backend:** Enrichment and AI scanning now return canonical WorkDTO/EditionDTO format via WebSocket
- **iOS:** Search services migrated to /v1/ endpoints with structured error codes
- **Response Format:** All search results use canonical data contracts (WorkDTO, EditionDTO, AuthorDTO)
- **Error Handling:** Structured ApiError with codes (INVALID_QUERY, INVALID_ISBN, PROVIDER_ERROR, INTERNAL_ERROR)

### Removed
- **iOS:** Legacy Google Books response parsing (~200 lines)
  - APISearchResponse, APIBookItem, APIVolumeInfo, APIImageLinks, APIIndustryIdentifier
  - EnrichmentSearchResponse, VolumeItem, VolumeInfo, ImageLinks, CrossReferenceIds
  - convertEnhancedItemToSearchResult() method
- **Backend:** Unused transformGoogleBooksResponse() helper

### Deprecated
- **Backend:** Legacy /search/* endpoints remain for backward compatibility (no removal planned)
  - /search/title, /search/isbn, /search/advanced, /search/author still functional

### Technical Details
- Bottom-up migration: backend canonical format first, then iOS integration
- DTOMapper handles deduplication by googleBooksVolumeIDs
- Insert-before-relate pattern prevents SwiftData crashes
- Conservative cleanup preserves public API backward compatibility

---

```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): canonical data contracts migration v3.3.0

Bottom-up migration complete:
- Backend services return canonical DTOs
- iOS parses ApiResponse<BookSearchResponse> envelopes
- Legacy response types removed (~290 lines)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 3: Conservative Cleanup (Deferred 2-4 weeks)

**Note:** Execute this phase ONLY after 2-4 weeks of production validation with zero issues.

### Task 17: Verify legacy public endpoints still functional

**Files:**
- None (validation only)

**Step 1: Test legacy /search/title endpoint**

Run: `curl "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=test"`
Expected: Returns legacy Google Books format (still works)

**Step 2: Test legacy /search/isbn endpoint**

Run: `curl "https://books-api-proxy.jukasdrj.workers.dev/search/isbn?isbn=9780451524935"`
Expected: Returns legacy format

**Step 3: Document decision to keep legacy endpoints**

```bash
echo "# Legacy Endpoint Preservation Decision

Date: $(date)

DECISION: Keep legacy /search/* endpoints indefinitely for backward compatibility.

Rationale:
- Unknown external clients may depend on these
- Breaking changes require major version bump (v2.0.0)
- Minimal maintenance cost
- Canonical /v1/* endpoints available for new clients

Status: Legacy endpoints will remain functional." > docs/legacy-endpoints-decision.md

git add docs/legacy-endpoints-decision.md
git commit -m "docs(decision): preserve legacy /search/* endpoints for backward compatibility"
```

---

### Task 18: Remove unused backend transformation helpers

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/enrichment.js:10-48`

**Step 1: Verify transformGoogleBooksResponse is unused**

Run: `grep -r "transformGoogleBooksResponse" cloudflare-workers/api-worker/src/`
Expected: Only definition found, no callers

**Step 2: Remove function**

Delete `transformGoogleBooksResponse()` function (lines 10-48 in enrichment.js)

**Step 3: Verify tests still pass**

Run: `cd cloudflare-workers/api-worker && npm test`
Expected: All pass (function was unused)

**Step 4: Commit**

```bash
git add src/services/enrichment.js
git commit -m "refactor(cleanup): remove unused transformGoogleBooksResponse helper

Function unused after canonical format migration.
Safe to remove - all services now use v1 handlers directly.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Summary

**Phase 1 (Backend):** 6 tasks, ~3-4 hours
- Update parallel-enrichment, enrichment.js, ai-scanner.js
- Write backend tests
- Manual validation + deployment

**Phase 2 (iOS):** 10 tasks, ~4-5 hours
- Migrate BookSearchAPIService (3 search methods)
- Update EnrichmentService WebSocket parsing
- Remove legacy types (~290 lines)
- Real device testing + documentation

**Phase 3 (Cleanup):** 2 tasks, ~1-2 hours (defer 2-4 weeks)
- Verify legacy endpoints
- Remove unused backend helpers

**Total Effort:** 18 tasks, 8-11 hours development + 2-4 week validation period

---

## Success Criteria

**Backend:**
- ✅ All tests pass
- ✅ WebSocket sends canonical { works, editions, authors }
- ✅ Legacy /search/* endpoints unchanged

**iOS:**
- ✅ All search flows work end-to-end
- ✅ Deduplication prevents duplicate Works
- ✅ Error codes display correctly
- ✅ Real device validation passes

**Cleanup:**
- ✅ Zero runtime errors
- ✅ Documentation reflects current API
- ✅ Legacy endpoints functional

---

**Ready to execute!** Use `superpowers:executing-plans` to implement task-by-task with review checkpoints.
