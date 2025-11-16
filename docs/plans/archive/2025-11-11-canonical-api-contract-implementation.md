# Canonical API Contract Implementation - 3-Phase Migration Plan

**Date:** November 11, 2025
**Status:** Planning Complete
**Owner:** Backend & iOS Engineering
**Estimated Effort:** 15-20 hours total

---

## Executive Summary

This 3-phase implementation plan will achieve **100% canonical contract compliance** for the Cloudflare Workers API, migrating from 3 of 17 endpoints compliant to 17 of 17 compliant.

### Current State
- 3 of 17 endpoints compliant (V1 search endpoints only)
- 3 competing response formats in production
- AI endpoints bypass canonical system
- WebSocket messages lack type contracts

### Target State
- 100% endpoint compliance (17 of 17)
- Single unified response envelope format
- All WebSocket messages typed with discriminated unions
- iOS can generate Swift types from TypeScript definitions

### Key Milestone
After completion, iOS can add new data providers (OpenLibrary, ISBNDB) with **zero iOS code changes** - achieving the core goal of canonical contracts.

---

## Migration Strategy: Incremental Approach

```
Phase 1: Foundation (3h)          Phase 2: AI Handlers (5-7h)       Phase 3: Envelope (4-6h)
[Zero Breaking Changes]           [Backward Compatible]             [Coordinated Deploy]
         |                                  |                                |
         v                                  v                                v
  Add Type Definitions    →      Refactor AI Endpoints     →      Unify Response Format
  Deprecation Warnings                                            iOS Integration
```

**Decision Rationale:** Incremental migration minimizes production risk compared to "big bang" approach. Each phase can be validated independently before proceeding.

---

## Phase 1: Foundation & Quick Wins

**Duration:** 3 hours
**Risk Level:** None (additive changes only)
**Breaking Changes:** No

### Objectives
1. Define WebSocket message contracts (discriminated union)
2. Add AI response types to canonical system
3. Add deprecation warnings to legacy endpoints
4. Document official response envelope format

### Implementation Tasks

#### Task 1.1: Create WebSocket Contracts (1 hour)

**File:** `cloudflare-workers/api-worker/src/types/websockets.ts` (NEW FILE)

```typescript
import type { DetectedBookDTO, ParsedBookDTO, EnrichedBookDTO } from './responses.js';

// Discriminated union for all WebSocket messages
export type WebSocketMessage =
  | WebSocketProgress
  | WebSocketComplete
  | WebSocketError;

export interface WebSocketProgress {
  type: 'progress';
  pipeline: 'ai_scan' | 'csv_import' | 'batch_enrichment';
  progress: number;  // 0.0-1.0
  status: string;
  processedCount?: number;
  currentItem?: string;
}

export interface WebSocketComplete {
  type: 'complete';
  pipeline: string;
  payload: AIScanCompletePayload | CSVImportCompletePayload | EnrichmentCompletePayload;
}

export interface AIScanCompletePayload {
  totalDetected: number;
  approved: number;  // confidence >= 0.6
  needsReview: number;  // confidence < 0.6
  books: DetectedBookDTO[];
}

export interface CSVImportCompletePayload {
  books: ParsedBookDTO[];
  errors: string[];
  successRate: string;
}

export interface EnrichmentCompletePayload {
  totalProcessed: number;
  successCount: number;
  failureCount: number;
  duration: number;
  enrichedBooks: EnrichedBookDTO[];
}

export interface WebSocketError {
  type: 'error';
  pipeline: string;
  error: {
    code: string;
    message: string;
    retryable: boolean;
    details?: any;
  };
}
```

**Validation:** Run `npm run build` - TypeScript should compile with zero errors.

#### Task 1.2: Add AI Response Types (1.5 hours)

**File:** `cloudflare-workers/api-worker/src/types/responses.ts`

Add the following interfaces:

```typescript
// === AI SCAN RESPONSES ===

export interface BookshelfScanInitResponse {
  jobId: string;
  token: string;
  status: 'started' | 'processing';
  websocketReady: boolean;
  stages: StageInfo[];
  estimatedRange: [number, number];
}

export interface StageInfo {
  name: string;
  typicalDuration: number;  // seconds
  progress: number;  // 0.0-1.0
}

export interface BoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DetectedBookDTO {
  title: string;
  author?: string;
  isbn?: string;
  confidence: number;  // 0.0-1.0
  boundingBox?: BoundingBox;
  enrichmentStatus: 'pending' | 'success' | 'not_found' | 'error';
  // Flattened edition fields (not nested)
  coverUrl?: string;
  publisher?: string;
  publicationYear?: number;
}

// === CSV IMPORT RESPONSES ===

export interface CSVImportInitResponse {
  jobId: string;
  token: string;
}

export interface ParsedBookDTO {
  title: string;
  author: string;
  isbn?: string;
}

// === ENRICHMENT RESPONSES ===

export interface EnrichmentJobInitResponse {
  success: boolean;
  processedCount: number;
  totalCount: number;
  token: string;
}

export interface EnrichedBookDTO {
  title: string;
  author?: string;
  isbn?: string;
  enrichmentStatus: 'success' | 'not_found' | 'error';
  // Flattened canonical fields (not nested)
  work?: WorkDTO;
  editions?: EditionDTO[];
  authors?: AuthorDTO[];
  provider?: DataProvider;
  error?: string;
}
```

**Validation:** Import types in a test file to confirm no circular dependencies.

#### Task 1.3: Add Deprecation Warnings (30 minutes)

**Files:**
- `cloudflare-workers/api-worker/src/handlers/book-search.js`
- `cloudflare-workers/api-worker/src/handlers/author-search.js`
- `cloudflare-workers/api-worker/src/handlers/search-handlers.js`

Add before return statement in each handler:

```javascript
console.warn('[DEPRECATED] /search/title called - migrate to /v1/search/title');

return new Response(JSON.stringify(result), {
  headers: {
    'Content-Type': 'application/json',
    'Warning': '299 - "Deprecated: Use /v1/search/title instead. This endpoint will be removed in 6 weeks."'
  }
});
```

**Validation:** Test legacy endpoint, verify `Warning` header appears in response.

#### Task 1.4: Update PRD Documentation (15 minutes)

**File:** `docs/product/Canonical-Data-Contracts-PRD.md`

Add after line 90:

```markdown
## Response Envelope Standard (Updated: November 11, 2025)

**Official Format:** ResponseEnvelope<T>
```typescript
{
  data: T | null;
  metadata: {
    timestamp: string;  // ISO 8601
    processingTime?: number;  // milliseconds
    provider?: DataProvider;
    cached?: boolean;
  };
  error?: {
    message: string;
    code?: string;
    details?: any;
  };
}
```

**Migration Timeline:**
- Phase 1 (Complete): Type definitions added
- Phase 2 (In Progress): AI handlers migrated
- Phase 3 (Scheduled): V1 search handlers migrated
```

### Phase 1 Success Criteria

- [ ] `src/types/websockets.ts` created with discriminated union (~150 lines)
- [ ] 8 new interfaces added to `src/types/responses.ts` (~80 lines)
- [ ] 4 legacy handlers have HTTP `Warning: 299` headers
- [ ] PRD documents official envelope format
- [ ] TypeScript compiles with zero errors
- [ ] Zero breaking changes in production

---

## Phase 2: AI Endpoint Contract Implementation

**Duration:** 5-7 hours
**Risk Level:** Low (JSON structure unchanged)
**Breaking Changes:** No

### Objectives
1. Refactor AI handlers to use canonical DTOs
2. Update Durable Object to send typed WebSocket messages
3. Maintain backward compatibility with production iOS

### Implementation Tasks

#### Task 2.1: Batch Scan Handler (2 hours)

**File:** `cloudflare-workers/api-worker/src/handlers/batch-scan-handler.js`

**Changes:**

1. Import canonical types:
```javascript
import type { DetectedBookDTO, BookshelfScanInitResponse } from '../types/responses.js';
```

2. Replace `mapToDetectedBook()` internal format:

```javascript
// BEFORE (line 18):
function mapToDetectedBook(book) {
  return {
    title: book?.title,
    author: book?.author,
    // ... internal format
  };
}

// AFTER:
function mapToDetectedBook(book): DetectedBookDTO {
  return {
    title: book?.title,
    author: book?.author,
    isbn: book?.isbn,
    confidence: book?.confidence,
    boundingBox: book?.boundingBox,
    enrichmentStatus: book?.enrichment?.status || 'pending',
    coverUrl: book?.enrichment?.work?.coverImageURL || null,
    publisher: book?.enrichment?.editions?.[0]?.publisher || null,
    publicationYear: book?.enrichment?.editions?.[0]?.publicationYear || null
  };
}
```

3. Use `BookshelfScanInitResponse` type for initial response (line 85)

**Validation:** Test bookshelf scan end-to-end, verify JSON structure unchanged.

#### Task 2.2: CSV Import Handler (1.5 hours)

**File:** `cloudflare-workers/api-worker/src/handlers/csv-import.js`

**Changes:**

1. Migrate from `createSuccessResponseObject` (legacy) to `createSuccessResponse` (new envelope):

```javascript
// BEFORE (line 62):
return Response.json(
  createSuccessResponseObject({ jobId, token }, {}),
  { status: 202 }
);

// AFTER:
import { createSuccessResponse } from '../utils/api-responses.js';
import type { CSVImportInitResponse } from '../types/responses.js';

return createSuccessResponse(
  { jobId, token } as CSVImportInitResponse,
  {},
  202
);
```

2. Update completion payload to use `CSVImportCompletePayload` (line 157)

**Validation:** Test CSV import, verify parsed books match canonical structure.

#### Task 2.3: Batch Enrichment Handler (2 hours)

**File:** `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`

**Changes:**

1. Use `EnrichmentJobInitResponse` type for initial response (line 148)

2. Refactor nested `{ enriched: { work, edition, authors } }` to flat `EnrichedBookDTO`:

```javascript
// BEFORE (processBatchEnrichment function):
return {
  ...book,
  enriched: {
    status: 'success',
    work: enrichedData.work,
    edition: enrichedData.edition,
    authors: enrichedData.authors
  }
};

// AFTER:
import type { EnrichedBookDTO } from '../types/responses.js';

return {
  title: book.title,
  author: book.author,
  isbn: book.isbn,
  enrichmentStatus: 'success',
  work: enrichedData.work,
  editions: enrichedData.editions,
  authors: enrichedData.authors,
  provider: enrichedData.provider
} as EnrichedBookDTO;
```

**Validation:** Test batch enrichment, verify iOS can parse flattened structure.

#### Task 2.4: Durable Object WebSocket Updates (30 minutes)

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Changes:**

1. Import WebSocket types:
```javascript
import type { WebSocketProgress, WebSocketComplete, WebSocketError } from '../types/websockets.js';
```

2. Update methods to accept typed parameters:
```javascript
async updateProgressV2(pipeline: string, payload: any) {
  const message: WebSocketProgress = {
    type: 'progress',
    pipeline,
    progress: payload.progress,
    status: payload.status,
    processedCount: payload.processedCount,
    currentItem: payload.currentItem
  };

  this.broadcast(JSON.stringify(message));
}
```

**Validation:** Test WebSocket messages match `websockets.ts` discriminated union.

#### Task 2.5: Integration Testing (1 hour)

**Test Cases:**
1. Bookshelf scan: Upload → AI → Enrichment → WebSocket → Completion
2. CSV import: Upload → Parse → WebSocket → Completion
3. Batch enrichment: Queue → Process → WebSocket → Completion

**Test Script:**
```bash
# Test bookshelf scan
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/scan-bookshelf/batch \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test-123","images":[...]}'

# Expected: 202 response with BookshelfScanInitResponse structure
# WebSocket connection receives typed messages
```

### Phase 2 Success Criteria

- [ ] `batch-scan-handler.js` uses `DetectedBookDTO`
- [ ] `csv-import.js` uses `CSVImportInitResponse`
- [ ] `batch-enrichment.js` uses `EnrichedBookDTO`
- [ ] Durable Object sends typed WebSocket messages
- [ ] Zero breaking changes in JSON structure
- [ ] Integration tests pass
- [ ] Production iOS build works against staging

---

## Phase 3: Response Envelope Unification & iOS Integration

**Duration:** 4-6 hours
**Risk Level:** Medium (coordinated deployment required)
**Breaking Changes:** Yes (V1 endpoints only)

### Objectives
1. Migrate V1 search endpoints to unified envelope format
2. Deprecate legacy helper functions
3. Generate iOS Swift types from TypeScript
4. Coordinate backend + iOS deployment

### Implementation Tasks

#### Task 3.1: V1 Handler Migration (2 hours)

**Files:**
- `cloudflare-workers/api-worker/src/handlers/v1/search-title.ts`
- `cloudflare-workers/api-worker/src/handlers/v1/search-isbn.ts`
- `cloudflare-workers/api-worker/src/handlers/v1/search-advanced.ts`

**Changes (apply to all 3 handlers):**

```typescript
// BEFORE (e.g., search-title.ts line 66):
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';

return createSuccessResponseObject(
  { works: cleanWorks, editions, authors },
  { processingTime, provider, cached: false }
);

// AFTER:
import { createSuccessResponse, createErrorResponse } from '../../utils/api-responses.js';

return createSuccessResponse(
  { works: cleanWorks, editions, authors },
  { processingTime, provider, cached: false },
  200
);
```

**Response format changes from:**
```json
{
  "success": true,
  "data": { "works": [...], "editions": [...], "authors": [...] },
  "meta": { "timestamp": "...", "processingTime": 150, "provider": "google-books" }
}
```

**To:**
```json
{
  "data": { "works": [...], "editions": [...], "authors": [...] },
  "metadata": { "timestamp": "...", "processingTime": 150, "provider": "google-books", "cached": false }
}
```

**Validation:** Test all 3 V1 endpoints, verify new format structure.

#### Task 3.2: Helper Consolidation (1 hour)

**File:** `cloudflare-workers/api-worker/src/types/responses.ts`

Add deprecation markers:

```typescript
/**
 * @deprecated Use createSuccessResponse from utils/api-responses.ts instead
 * This helper will be removed in v2.0.0 (after iOS migration)
 */
export function createSuccessResponseObject<T>(
  data: T,
  meta: Partial<ResponseMeta> = {}
): SuccessResponse<T> {
  // ... existing implementation
}

/**
 * @deprecated Use createErrorResponse from utils/api-responses.ts instead
 * This helper will be removed in v2.0.0 (after iOS migration)
 */
export function createErrorResponseObject(
  message: string,
  code?: ApiErrorCode,
  details?: any,
  meta: Partial<ResponseMeta> = {}
): ErrorResponse {
  // ... existing implementation
}
```

**Schedule removal:** 4-6 weeks after iOS migration confirms (around January 2026).

#### Task 3.3: iOS Swift Type Generation (2 hours)

**Process:**

1. Create generation script:
```bash
# File: BooksTrackerPackage/Scripts/generate-swift-types.sh
#!/bin/bash
echo "Generating Swift types from TypeScript..."

# Use quicktype.io or custom TypeScript → Swift converter
npx quicktype \
  --src cloudflare-workers/api-worker/src/types/websockets.ts \
  --out BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/WebSocketMessage.swift \
  --lang swift

npx quicktype \
  --src cloudflare-workers/api-worker/src/types/responses.ts \
  --out BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/AIResponseTypes.swift \
  --lang swift

echo "Swift types generated successfully!"
```

2. Update `ResponseEnvelope.swift` for new format:
```swift
public struct ResponseEnvelope<T: Codable>: Codable {
    public let data: T?
    public let metadata: ResponseMetadata
    public let error: APIError?
}

public struct ResponseMetadata: Codable {
    public let timestamp: String
    public let processingTime: Int?
    public let provider: String?
    public let cached: Bool?
}
```

3. Update `DTOMapper.swift`:
```swift
// Simplify mapper (single canonical path)
public func mapToWorks(_ envelope: ResponseEnvelope<BookSearchResponse>) throws -> [Work] {
    guard let data = envelope.data else {
        throw DTOMapperError.missingData
    }

    return data.works.map { workDTO in
        // Map canonical WorkDTO → SwiftData Work
        createWork(from: workDTO, editions: data.editions, authors: data.authors)
    }
}
```

**Validation:** Generate types, compile iOS project with zero warnings.

#### Task 3.4: iOS Integration Testing (1 hour)

**Test Cases:**
```swift
func testV1SearchWithNewEnvelope() async throws {
    let response = try await searchService.searchByTitle("The Great Gatsby")
    XCTAssertNotNil(response.data)
    XCTAssertEqual(response.metadata.provider, "google-books")
}

func testWebSocketMessageParsing() throws {
    let json = """
    {"type":"progress","pipeline":"ai_scan","progress":0.5,"status":"Processing..."}
    """
    let message = try JSONDecoder().decode(WebSocketMessage.self, from: json.data(using: .utf8)!)

    if case .progress(let progressMsg) = message {
        XCTAssertEqual(progressMsg.pipeline, "ai_scan")
        XCTAssertEqual(progressMsg.progress, 0.5)
    } else {
        XCTFail("Expected progress message")
    }
}
```

**Validation:** All iOS integration tests pass.

### Phase 3 Success Criteria

- [ ] All 3 V1 handlers use unified envelope (`{data, metadata, error}`)
- [ ] Deprecated helpers marked with `@deprecated` in TypeScript
- [ ] iOS Swift types generated from TypeScript definitions
- [ ] `DTOMapper.swift` updated for new envelope structure
- [ ] iOS integration tests pass
- [ ] Zero crashes in production after 48h

---

## Risk Assessment & Mitigation

### Risk Matrix

| Risk | Severity | Probability | Impact | Mitigation |
|------|----------|-------------|--------|------------|
| Phase 3 iOS coordination failure | HIGH | Medium | Production app crashes on search | Feature flag + rollback script (<5min) |
| WebSocket message breaking changes | MEDIUM | Low | Real-time progress UI freezes | Staging testing + TestFlight validation |
| TypeScript compilation errors | LOW | Low | Build failures | Incremental testing + zero-warnings policy |
| iOS Swift type generation mismatch | MEDIUM | Medium | Runtime crashes on iOS | Automated generation + integration tests |

### Detailed Mitigation Strategies

#### Risk 1: Phase 3 Deployment Coordination (HIGH SEVERITY)

**Problem:** V1 search endpoints changing response format requires iOS app update within 24 hours.

**Impact:** If iOS update delayed, production app crashes on search.

**Mitigation:**
1. Deploy backend on Friday afternoon (minimal traffic window)
2. Have iOS build ready for App Store submission BEFORE backend deploy
3. Implement feature flag: `USE_LEGACY_V1_FORMAT` environment variable
4. Create rollback script: `cloudflare-workers/scripts/deploy-rollback.sh`
5. Monitor error rates in real-time (Cloudflare Analytics)

**Rollback Script:**
```bash
#!/bin/bash
# File: cloudflare-workers/scripts/deploy-rollback.sh
echo "Rolling back V1 handlers to legacy format..."
git revert <v1-migration-commit>
npm run build
npx wrangler deploy --env production
echo "Rollback complete. V1 endpoints restored to legacy format."
# Estimated time: 5 minutes
```

#### Risk 2: WebSocket Message Breaking Changes (MEDIUM SEVERITY)

**Problem:** Durable Object sends messages iOS can't parse.

**Impact:** Real-time progress breaks, users see frozen UI.

**Mitigation:**
1. Deploy Phase 2 changes to staging first
2. Test with production iOS build (TestFlight)
3. Add message schema validation in Durable Object (log warnings for unknown fields)
4. Keep backward-compatible message structure for 2 releases

#### Risk 3: TypeScript Compilation Errors (LOW SEVERITY)

**Problem:** New types conflict with existing code.

**Impact:** Build failures, deployment blocked.

**Mitigation:**
1. Run `npm run build` after each phase
2. Use `@ts-expect-error` temporarily for gradual migration
3. Zero-warnings policy catches issues early

#### Risk 4: iOS Swift Type Generation Mismatch (MEDIUM SEVERITY)

**Problem:** Generated Swift types don't match TypeScript exactly.

**Impact:** Runtime crashes on iOS when parsing responses.

**Mitigation:**
1. Use automated code generation tool (quicktype.io or custom script)
2. Add integration tests: Send TypeScript JSON → Parse with Swift types
3. Validate all enum cases match exactly (case-sensitive!)

### Rollback Plan

**Phase 1 Rollback:** Not needed (additive changes only)

**Phase 2 Rollback:**
```bash
git revert <phase-2-commit>
npx wrangler deploy
# Estimated time: 3-5 minutes
```

**Phase 3 Rollback (Critical):**
```bash
./cloudflare-workers/scripts/deploy-rollback.sh
# Estimated time: 5 minutes
```

**Rollback Triggers:**
- Error rate >1% for >5 minutes
- iOS crash rate increases >50%
- WebSocket connection failures >10%

---

## Testing Strategy

### Phase 1 Testing
- [ ] TypeScript compiles with no errors (`npm run build`)
- [ ] Deprecation warnings appear in logs (test legacy endpoints)
- [ ] PRD updated with correct format specification

### Phase 2 Testing
- [ ] Unit tests for `DetectedBookDTO` mapping
- [ ] Integration test: Bookshelf scan → WebSocket → Completion (end-to-end)
- [ ] Test with production iOS build (TestFlight)
- [ ] Verify JSON structure unchanged (compare before/after payloads)

### Phase 3 Testing
- [ ] Staging deployment with new envelope format
- [ ] Test iOS build against staging backend
- [ ] Rollback script tested (can revert in <5 min)
- [ ] Monitor error rates for 24 hours post-deploy
- [ ] Confirm zero crashes related to API parsing

---

## Post-Deployment Monitoring

### Metrics Dashboard (24-48 hours)

**Track the following:**

1. **Error Rate:** Should remain <0.1% (Cloudflare Analytics)
2. **Response Time:** V1 endpoints should stay <200ms p99
3. **WebSocket Errors:** Monitor for parsing failures
4. **iOS Crash Rate:** Should remain <0.01% (App Store Connect)

**Monitoring Commands:**
```bash
# Check Cloudflare Analytics
wrangler tail books-api-proxy --search "error"

# Check specific endpoint
curl https://books-api-proxy.jukasdrj.workers.dev/v1/search/title?q=test

# Check WebSocket health
wscat -c wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123
```

### Alert Thresholds

- **Critical:** Error rate >1% for >5 minutes → Execute rollback
- **High:** iOS crash rate increases >50% → Execute rollback
- **Medium:** WebSocket failures >10% → Investigate, consider rollback

---

## File Deliverables Summary

### Backend Files Modified (11 files)

1. `src/types/websockets.ts` (NEW - ~150 lines)
2. `src/types/responses.ts` (+80 lines)
3. `src/handlers/book-search.js` (+3 lines deprecation)
4. `src/handlers/author-search.js` (+3 lines deprecation)
5. `src/handlers/search-handlers.js` (+3 lines deprecation)
6. `src/handlers/batch-scan-handler.js` (refactor 50 lines)
7. `src/handlers/csv-import.js` (refactor 30 lines)
8. `src/handlers/batch-enrichment.js` (refactor 40 lines)
9. `src/handlers/v1/search-title.ts` (migrate 10 lines)
10. `src/handlers/v1/search-isbn.ts` (migrate 10 lines)
11. `src/handlers/v1/search-advanced.ts` (migrate 10 lines)

### iOS Files Modified (4 files)

1. `DTOs/WebSocketMessage.swift` (NEW - generated)
2. `DTOs/AIResponseTypes.swift` (NEW - generated)
3. `DTOs/ResponseEnvelope.swift` (modified - new format)
4. `Services/DTOMapper.swift` (simplified - single path)

### Documentation Files Modified (2 files)

1. `docs/product/Canonical-Data-Contracts-PRD.md` (+20 lines)
2. `cloudflare-workers/scripts/deploy-rollback.sh` (NEW - rollback script)

---

## Post-Completion Maintenance

### 6-Week Deprecation Period

**Actions:**
- Monitor legacy endpoint usage via Cloudflare Analytics
- Send email notifications to any identified clients
- Track deprecation warning header appearances in logs

**Monitoring Query:**
```bash
wrangler tail books-api-proxy --search "DEPRECATED"
```

### After 6 Weeks (Around January 2026)

**Cleanup Tasks:**
- [ ] Remove legacy handlers: `book-search.js`, `author-search.js`, `search-handlers.js`
- [ ] Remove routes from `index.js` (lines 558, 609, 683)
- [ ] Remove deprecated helper functions from `responses.ts`
- [ ] Update documentation to reflect V1-only endpoints
- [ ] Update API health check endpoint to remove legacy routes

---

## Next Steps

### Immediate Actions

1. **Create feature branch:**
   ```bash
   git checkout -b feature/canonical-api-contracts
   ```

2. **Start Phase 1:**
   - Implement WebSocket types (1 hour task)
   - Run `npm run build` to validate

3. **Track progress:**
   - Update PRD with "Phase 1 In Progress" status
   - Create tracking issue in GitHub

### Approval Checklist

Before starting implementation:
- [ ] Plan reviewed by backend team
- [ ] Plan reviewed by iOS team
- [ ] Deployment coordination scheduled (Friday afternoon)
- [ ] Rollback script location confirmed
- [ ] Monitoring dashboard access confirmed

---

## References

**Related Documentation:**
- `docs/product/Canonical-Data-Contracts-PRD.md` - Original requirements
- `docs/workflows/canonical-contracts-workflow.md` - Visual flow diagram
- `cloudflare-workers/api-worker/src/types/canonical.ts` - Core DTO definitions
- Analysis report that generated this plan (November 11, 2025)

**Key Decisions:**
- Response envelope format: `{data, metadata, error}` (Format B)
- Migration strategy: Incremental (not big bang)
- iOS coordination: Backend → iOS within 24h
- Deprecation period: 6 weeks

---

**Plan Status:** Ready for implementation
**Estimated Completion:** 15-20 hours total (12-16h backend + 3-4h iOS)
**Next Review:** After Phase 1 completion
