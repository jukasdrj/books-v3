# BooksTrack API v2.0 Contract

**Status:** ✅ Approved by Multi-Model Consensus (Gemini Pro 9/10, Grok-4 9/10)
**Created:** November 14, 2025
**Effective:** December 1, 2025

---

## Executive Summary

This contract defines the **canonical response format** for all BooksTrack API endpoints and internal services. It resolves inconsistencies between PR #70 (response builders) and PR #71 (type definitions) by establishing clear boundaries between internal service logic and HTTP transport.

### Key Principles

1. **Separation of Concerns**: Internal services return domain objects; HTTP handlers wrap in transport envelopes
2. **Nullable Data Pattern**: Use `data: T | null` with optional `error` field (modern, Swift-friendly)
3. **Type Safety**: Strict TypeScript types prevent runtime errors
4. **Client Simplicity**: iOS Codable parsing with no discriminator boilerplate

---

## Layer 1: HTTP Response Envelope

### Interface Definition

```typescript
/**
 * Universal HTTP Response Envelope
 * Used by ALL /v1/* endpoints
 */
export interface ResponseEnvelope<T> {
  data: T | null;           // Payload (null on error)
  metadata: ResponseMetadata; // Always present
  error?: ApiError;          // Present only on error
}

export interface ResponseMetadata {
  timestamp: string;        // ISO 8601 (always present)
  processingTime?: number;  // Milliseconds
  provider?: DataProvider;  // 'google_books' | 'openlibrary' | 'isbndb'
  cached?: boolean;         // true if served from cache
}

export interface ApiError {
  message: string;          // Human-readable
  code?: string;            // Machine-readable (e.g., 'NOT_FOUND')
  details?: any;            // Optional context
}
```

### Success Response Example

```json
{
  "data": {
    "works": [...],
    "editions": [...],
    "authors": [...]
  },
  "metadata": {
    "timestamp": "2025-11-14T23:00:00.000Z",
    "processingTime": 145,
    "provider": "google_books",
    "cached": false
  }
}
```

### Error Response Example

```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-14T23:00:00.000Z",
    "processingTime": 12
  },
  "error": {
    "message": "Book not found for ISBN 9780000000000",
    "code": "NOT_FOUND",
    "details": { "isbn": "9780000000000" }
  }
}
```

---

## Layer 2: Internal Service Return Types

### Rule: Services Return Domain Objects, NOT Envelopes

**✅ Correct:**
```typescript
// Internal service function
export async function enrichSingleBook(
  params: { isbn?: string; title?: string; author?: string },
  env: any
): Promise<WorkDTO | null> {
  // Business logic
  return workDTO; // or null if not found
}
```

**❌ Incorrect:**
```typescript
// DON'T wrap internal results in ResponseEnvelope
export async function enrichSingleBook(...): Promise<ResponseEnvelope<WorkDTO>> {
  return { data: workDTO, metadata: {...} }; // NO!
}
```

### Error Handling Strategy

| Scenario | Return Value | Example |
|----------|-------------|---------|
| **Not Found** (expected) | `null` | Book not in Google Books API |
| **Validation Error** | `null` | Invalid ISBN format |
| **Network Error** (unexpected) | `throw new Error(...)` | Google Books API timeout |
| **System Error** (unexpected) | `throw new Error(...)` | KV cache unavailable |

**Rationale:**
- `null` = "I looked, but nothing there" (expected, not exceptional)
- `throw` = "Something broke, I can't continue" (unexpected, exceptional)

**Future Consideration (Phase 3):**
Migrate to `Result<T, Error>` pattern for full type safety. Documented as technical debt in issue #XXX.

---

## Layer 3: HTTP Handler Pattern

### Standard Handler Template

```typescript
export async function handleSearchISBN(
  isbn: string,
  env: any,
  ctx: ExecutionContext
): Promise<ResponseEnvelope<BookSearchResponse>> {
  const startTime = Date.now();

  try {
    // 1. Call internal service (returns domain object or null)
    const work = await enrichSingleBook({ isbn }, env);

    // 2. Handle not found (null case)
    if (!work) {
      return {
        data: null,
        metadata: {
          timestamp: new Date().toISOString(),
          processingTime: Date.now() - startTime,
        },
        error: {
          message: `Book not found for ISBN ${isbn}`,
          code: 'NOT_FOUND',
          details: { isbn }
        }
      };
    }

    // 3. Wrap success result in envelope
    return {
      data: {
        works: [work],
        editions: work.editions || [],
        authors: work.authors || []
      },
      metadata: {
        timestamp: new Date().toISOString(),
        processingTime: Date.now() - startTime,
        provider: work.primaryProvider,
        cached: false
      }
    };

  } catch (error: any) {
    // 4. Handle unexpected errors (thrown exceptions)
    console.error('ISBN search error:', error);
    return {
      data: null,
      metadata: {
        timestamp: new Date().toISOString(),
        processingTime: Date.now() - startTime,
      },
      error: {
        message: error.message || 'Internal server error',
        code: 'INTERNAL_ERROR',
        details: { error: error.toString() }
      }
    };
  }
}
```

---

## Migration Checklist

### Phase 2.1: Update Response Builders (src/utils/response-builder.ts)

```typescript
// OLD (from PR #70)
export function createSuccessResponseObject<T>(data: T, meta: any = {}) {
  return {
    success: true,  // ❌ Remove discriminator
    data,
    meta: { timestamp: new Date().toISOString(), ...meta }
  };
}

// NEW (compliant with this contract)
export function createSuccessEnvelope<T>(
  data: T,
  metadata: Partial<ResponseMetadata> = {}
): ResponseEnvelope<T> {
  return {
    data,
    metadata: {
      timestamp: new Date().toISOString(),
      ...metadata
    }
  };
}

export function createErrorEnvelope(
  message: string,
  code?: string,
  details?: any,
  metadata: Partial<ResponseMetadata> = {}
): ResponseEnvelope<null> {
  return {
    data: null,
    metadata: {
      timestamp: new Date().toISOString(),
      ...metadata
    },
    error: { message, code, details }
  };
}
```

### Phase 2.2: Update Internal Services (src/services/enrichment.ts)

**Remove 7 instances of `.success` checks:**

```typescript
// OLD (line 141)
if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
  return googleResult.works[0];
}

// NEW
const works = await searchGoogleBooks(query, env);
if (works && works.length > 0) {
  return works[0];
}
```

**Update function signatures:**

```typescript
// OLD
export async function searchGoogleBooks(...): Promise<{success: boolean, works: WorkDTO[]}>

// NEW
export async function searchGoogleBooks(...): Promise<WorkDTO[] | null>
```

### Phase 2.3: Update External APIs (src/services/external-apis.ts)

**Remove envelope wrapping from internal functions:**

```typescript
// OLD
export async function searchOpenLibrary(...): Promise<SearchResult> {
  return {
    success: true,
    works: [...],
    meta: { provider: 'openlibrary' }
  };
}

// NEW
export async function searchOpenLibrary(...): Promise<WorkDTO[] | null> {
  return [...];  // Just return the domain objects
}
```

### Phase 2.4: Update All HTTP Handlers (src/handlers/v1/*.ts)

Ensure every handler:
1. ✅ Returns `ResponseEnvelope<T>` type
2. ✅ Calls internal services (which return domain objects)
3. ✅ Wraps results in envelope using helper functions or manual construction
4. ✅ Handles null (not found) vs exceptions (errors) correctly

**Files to update:**
- `src/handlers/v1/search-isbn.ts` ✅ Already updated
- `src/handlers/v1/search-title.ts`
- `src/handlers/v1/search-advanced.ts` ✅ Partially updated
- `src/handlers/batch-enrichment.ts`
- `src/handlers/csv-import.ts`
- `src/handlers/batch-scan-handler.ts`

### Phase 2.5: Update Tests (tests/**/*.test.js)

**Replace assertions:**

```javascript
// OLD
expect(response.success).toBe(true);
expect(response.data.works).toHaveLength(1);
expect(response.meta.provider).toBe('google_books');

// NEW
expect(response.data).toBeDefined();
expect(response.data.works).toHaveLength(1);
expect(response.metadata.provider).toBe('google_books');
expect(response.error).toBeUndefined();
```

**Error case assertions:**

```javascript
// OLD
expect(response.success).toBe(false);
expect(response.error.code).toBe('NOT_FOUND');

// NEW
expect(response.data).toBeNull();
expect(response.error).toBeDefined();
expect(response.error.code).toBe('NOT_FOUND');
```

---

## WebSocket Contract (Separate from HTTP)

**Decision:** WebSocket messages use a **different envelope** (pipeline-aware, from PR #71).

```typescript
export interface WebSocketMessageV2 {
  type: 'job_progress' | 'job_complete' | 'error';
  jobId: string;
  pipeline: 'csv_import' | 'batch_enrichment' | 'bookshelf_scan';
  timestamp: string;
  version: string;
  payload: MessagePayload;
}
```

**Rationale:** WebSocket is stateful, bidirectional communication (not request/response). The pipeline-aware envelope provides better observability for long-running jobs.

---

## Breaking Changes Summary

### For API Consumers (iOS, Flutter)

1. **Response shape changed:**
   - ❌ Old: `{success: boolean, data: T, meta: {...}}`
   - ✅ New: `{data: T | null, metadata: {...}, error?: {...}}`

2. **Error detection changed:**
   - ❌ Old: `if (response.success === false)`
   - ✅ New: `if (response.error !== undefined)` or `if (response.data === null)`

3. **Metadata renamed:**
   - ❌ Old: `response.meta.timestamp`
   - ✅ New: `response.metadata.timestamp`

4. **WebSocket messages:**
   - ❌ Old: `{type: 'progress', jobId, data: {...}}`
   - ✅ New: `{type: 'job_progress', jobId, pipeline, timestamp, version, payload: {...}}`

### Migration Support

- **Staging environment:** `https://staging-api.oooefam.net` (available Nov 21)
- **Migration window:** Nov 21 - Nov 28 (7 days)
- **Production cutover:** Dec 1, 2025
- **Documentation:** `docs/API_V2_MIGRATION_NOTICE.md`

---

## Implementation Order (Phase 2)

```
Day 1 (Nov 14):
├─ ✅ Update src/utils/response-builder.ts
├─ ✅ Update src/types/responses.ts (already done in PR #71)
└─ ✅ Create this contract document

Day 2 (Nov 15):
├─ Update src/services/external-apis.ts (remove envelopes)
├─ Update src/services/enrichment.ts (remove .success checks)
└─ Run tests, fix service layer errors

Day 3 (Nov 16):
├─ Update all HTTP handlers (6 files)
├─ Update tests (38 assertions)
└─ Run full test suite

Day 4 (Nov 17):
├─ Configure staging in wrangler.toml
├─ Deploy to staging
└─ Create iOS migration documentation

Day 5-11 (Nov 18-24):
└─ iOS/Flutter teams test against staging

Day 12 (Nov 25):
├─ Open consolidated PR
└─ Code review

Day 13 (Nov 26):
└─ Address review feedback

Day 14 (Nov 27):
└─ Go/No-Go decision

Day 15 (Nov 28):
└─ Merge to main + production deploy
```

---

## Validation Criteria

Before merging to main:

- [ ] All TypeScript compiles without errors
- [ ] `npm test` passes with 0 failures
- [ ] No `.success` checks remain in service layer
- [ ] All HTTP handlers return `ResponseEnvelope<T>`
- [ ] Staging deployment healthy (error rate < 1%)
- [ ] iOS team confirms compatibility
- [ ] Flutter team confirms compatibility (if applicable)
- [ ] Documentation complete:
  - [ ] `docs/API_V2_MIGRATION_NOTICE.md`
  - [ ] `docs/IOS_WEBSOCKET_MIGRATION_V2.md`
  - [ ] This contract document
- [ ] Monitoring dashboard configured for:
  - [ ] Error rate by endpoint
  - [ ] Response time P95/P99
  - [ ] WebSocket connection count

---

## Success Metrics (Post-Deploy)

**Week 1 (Dec 1-7):**
- Error rate < 1% across all endpoints
- P95 latency < 500ms
- Zero client-reported parsing errors
- WebSocket connection stability > 95%

**Month 1 (Dec 1-31):**
- Test coverage > 75%
- Zero API contract violations
- Client integration issues resolved < 2 days

---

## Phase 3: Future Improvements (Post-Production)

Documented as technical debt for Q1 2026:

1. **Result<T, Error> Pattern** - Replace null/exceptions with typed Result for internal services
2. **OpenAPI Spec** - Generate OpenAPI 3.1 spec from TypeScript types
3. **Client SDK Generation** - Auto-generate Swift/Dart SDKs from spec
4. **Response Compression** - Enable Brotli/Gzip for large responses
5. **Rate Limiting Metadata** - Add `metadata.rateLimit` fields

---

## Questions & Support

- **Technical:** #bookstrack-api-support (Slack)
- **Breaking Changes:** api-support@oooefam.net
- **Escalation:** @jukasdrj (GitHub)

---

**Contract Version:** 1.0
**Last Updated:** November 14, 2025
**Approved By:** Multi-Model Consensus (Gemini Pro, Grok-4)
**Maintained By:** Backend Team (@jukasdrj)
