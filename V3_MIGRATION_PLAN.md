# V3 API Migration Plan

**Version:** 1.0
**Date:** December 5, 2025
**Status:** Phase 4 - Cleanup & Optimization (In Progress)
**Strategy:** Clean, Direct Migration (No Production Traffic)

---

## Executive Summary

This document outlines the complete migration from V2 to V3 API for the BooksTrack iOS application. Since there is **no production traffic**, we can implement a clean, straightforward migration without feature flags, gradual rollouts, or dual-client complexity.

**Key Principle:** Preserve SwiftData architecture (Work/Edition/Author separation) via a V3→V2 mapping layer.

---

## V2 vs V3 API Differences

### Endpoint Changes

| Feature | V2 Endpoint | V3 Endpoint |
|---------|-------------|-------------|
| **Search** | `GET /api/v2/search` | `GET /v3/books/search` |
| **ISBN Lookup** | `GET /books/isbn/{isbn}` | `GET /v3/books/{isbn}` |
| **Batch Enrich** | `POST /api/v2/books/enrich` | `POST /v3/books/enrich` |
| **CSV Import** | `POST /api/v2/imports` | ⚠️ Not documented (TBD) |
| **Shelf Scan** | N/A | ✅ Already on `/api/v3.2/scan-bookshelf` |

### Data Model Changes

| Aspect | V2 API | V3 API |
|--------|--------|--------|
| **Response Structure** | `{ works: [], editions: [], authors: [] }` | `{ books: [], total: number }` |
| **Book Model** | Separate Work/Edition/Author entities | Unified `Book` model |
| **Authors Field** | `authors: [AuthorDTO]` (objects) | `authors: [String]` (simple array) |
| **Enrich Request** | `{ books: [Book], jobId: string }` | `{ isbns: [String], includeEmbedding: boolean }` |
| **Error Format** | Custom error responses | RFC 9457 Problem Details |

### New V3 Features

- ✅ **HATEOAS Links** - `_links` object for discoverability
- ✅ **ETag Support** - Conditional requests for caching
- ✅ **Request Tracing** - `X-Request-ID` header
- ✅ **Unified Book Model** - Simpler, flatter structure
- ✅ **RFC 9457 Errors** - Standardized error responses

---

## Migration Strategy

### Phase 1: V3 DTOs & Client (Week 1)

**Goal:** Create V3 data models and API client without touching existing code.

#### 1.1 Create V3 DTOs

**New Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/V3/`
  - `V3Book.swift` - Unified book model
  - `V3SearchResponse.swift` - Search response envelope
  - `V3EnrichRequest.swift` - Enrich request payload
  - `V3EnrichResponse.swift` - Enrich response envelope
  - `V3ErrorResponse.swift` - RFC 9457 error format
  - `V3ResponseMetadata.swift` - Request metadata
  - `V3Pagination.swift` - Pagination data
  - `V3Link.swift` - HATEOAS link model

**V3Book Schema (Reference):**
```swift
struct V3Book: Codable {
    let isbn: String
    let isbn10: String?
    let title: String
    let subtitle: String?
    let authors: [String]  // ✅ Simple string array
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let pageCount: Int?
    let categories: [String]?
    let language: String?
    let coverUrl: String?
    let thumbnailUrl: String?
    let workKey: String?
    let editionKey: String?
    let provider: String
    let quality: Double
}
```

#### 1.2 Create V3 API Client

**New File:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/V3APIClientActual.swift`

**Methods:**
```swift
@MainActor
final class V3APIClient {
    // Search
    func search(query: String, limit: Int, offset: Int) async throws -> V3SearchResponse

    // ISBN Lookup
    func getBook(isbn: String) async throws -> V3Book

    // Batch Enrich
    func enrichBooks(isbns: [String], includeEmbedding: Bool) async throws -> V3EnrichResponse
}
```

**Features:**
- ETag caching support
- Request ID tracking (`X-Request-ID`)
- RFC 9457 error parsing
- Timeout handling
- Retry logic for transient failures

#### 1.3 Testing

**Unit Tests:**
- `V3APIClientTests.swift`
  - Mock JSON responses from openapi-v3.json examples
  - Test all three endpoints (search, lookup, enrich)
  - Test error handling (RFC 9457 format)
  - Test ETag caching logic

**Deliverables:**
- ✅ 8 new DTO files
- ✅ V3APIClient implementation
- ✅ Comprehensive unit tests
- ✅ Zero impact on existing V2 code

---

### Phase 2: V3→V2 Mapping Layer (Week 2)

**Goal:** Transform V3 responses into V2 DTOs to preserve SwiftData architecture.

#### 2.1 Create Mapping Service

**New File:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/V3ToV2Mapper.swift`

**Core Mapping Logic:**
```swift
struct V3ToV2Mapper {
    /// Transform V3 unified Book into Work/Edition/Author DTOs
    func mapSearchResponse(_ v3Response: V3SearchResponse) -> BookSearchResponse {
        var works: [WorkDTO] = []
        var editions: [EditionDTO] = []
        var authors: [AuthorDTO] = []
        var authorCache: [String: String] = [:]  // name → openLibraryID

        for v3Book in v3Response.data.books {
            // 1. Create or reuse AuthorDTOs
            let authorDTOs = mapAuthors(v3Book.authors, cache: &authorCache)
            authors.append(contentsOf: authorDTOs)

            // 2. Create WorkDTO
            let work = WorkDTO(
                openLibraryID: v3Book.workKey ?? generateWorkID(from: v3Book.isbn),
                title: v3Book.title,
                authorIDs: authorDTOs.map(\.openLibraryID),
                // ... map remaining fields
            )
            works.append(work)

            // 3. Create EditionDTO
            let edition = EditionDTO(
                openLibraryID: v3Book.editionKey ?? generateEditionID(from: v3Book.isbn),
                isbn13: v3Book.isbn,
                isbn10: v3Book.isbn10,
                workID: work.openLibraryID,
                // ... map remaining fields
            )
            editions.append(edition)
        }

        return BookSearchResponse(
            works: works.uniqued(),
            editions: editions,
            authors: authors.uniqued()
        )
    }

    /// Transform V3 author strings into AuthorDTOs
    private func mapAuthors(_ names: [String], cache: inout [String: String]) -> [AuthorDTO] {
        names.map { name in
            let id = cache[name] ?? generateAuthorID(from: name)
            cache[name] = id
            return AuthorDTO(
                openLibraryID: id,
                name: name,
                photoUrl: nil  // V3 doesn't provide author photos
            )
        }
    }

    /// Generate stable OpenLibrary-style IDs for missing keys
    private func generateWorkID(from isbn: String) -> String {
        "OL\(isbn.hashValue)W"
    }

    private func generateEditionID(from isbn: String) -> String {
        "OL\(isbn.hashValue)M"
    }

    private func generateAuthorID(from name: String) -> String {
        "OL\(name.hashValue)A"
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self))
    }
}
```

**Key Design Decisions:**

1. **Synthetic IDs**: Generate OpenLibrary-style IDs when V3 doesn't provide `workKey`/`editionKey`
   - Stable hashing ensures same ISBN always produces same ID
   - Format: `OL{hash}W` (Work), `OL{hash}M` (Edition), `OL{hash}A` (Author)

2. **Author Deduplication**: Cache author names to prevent duplicates
   - Same author name → same AuthorDTO across all books

3. **Preserve Relationships**: Link Work↔Edition↔Author via IDs
   - Edition.workID → Work.openLibraryID
   - Work.authorIDs → [AuthorDTO.openLibraryID]

#### 2.2 Testing

**Unit Tests:**
- `V3ToV2MapperTests.swift`
  - Map V3 search response with 10 books
  - Verify Work/Edition/Author relationships
  - Test author deduplication
  - Test synthetic ID generation
  - Test edge cases (missing fields, empty arrays)

**Integration Tests:**
- Fetch from V3 API → Map to V2 DTOs → Verify structure
- Ensure SwiftData can persist mapped DTOs

**Deliverables:**
- ✅ V3ToV2Mapper implementation
- ✅ Comprehensive unit tests
- ✅ Integration test with live V3 API
- ✅ Documentation on synthetic ID generation

---

### Phase 3: Integration & Migration (Week 3)

**Goal:** Replace V2 API calls with V3 API + mapping layer.

#### 3.1 Update Services

**Files to Modify:**

**A. SearchService.swift** (or equivalent)
```swift
// Before
let response = try await v2APIClient.search(query: query)

// After
let v3Response = try await v3APIClient.search(query: query, limit: 20, offset: 0)
let v2Response = V3ToV2Mapper().mapSearchResponse(v3Response)
```

**B. EnrichmentService.swift**
```swift
// Before (line 114)
func startEnrichment(jobId: String, books: [Book]) async throws {
    let payload = BatchEnrichmentPayload(books: books, jobId: jobId)
    // ... POST to /api/v2/books/enrich
}

// After
func startEnrichment(isbns: [String]) async throws {
    let v3Response = try await v3APIClient.enrichBooks(
        isbns: isbns,
        includeEmbedding: false
    )
    let v2Response = V3ToV2Mapper().mapEnrichResponse(v3Response)
    // ... process v2Response
}
```

**C. V3APIClient.swift (rename existing file)**
```swift
// Rename current V3APIClient.swift → V2APIClient.swift
// Update all references to use new V3APIClientActual
```

#### 3.2 Update Workflow Services

**A. BookshelfAIService.swift** (Already on v3.2!)
- No changes needed for shelf scanning
- Update enrichment integration:
  ```swift
  // After shelf scan returns ISBNs (line 881)
  let isbns = scanResults.detectedBooks.map(\.isbn)
  let enriched = try await v3APIClient.enrichBooks(isbns: isbns)
  ```

**B. GeminiCSVImportService.swift**
- ⚠️ **Blocked**: No V3 CSV import endpoint documented
- **Options:**
  1. Keep using `/api/v2/imports` (backend maintains V2 endpoint)
  2. Wait for V3 specification
  3. Implement client-side CSV parsing → V3 batch enrich
- **Decision Required**: Clarify with backend team

#### 3.3 Update Error Handling

**Files to Modify:**
- Error handling throughout app to support RFC 9457 format
- Add retry logic for `retryable: true` errors
- Respect `retryAfterMs` for rate limiting

**Example:**
```swift
do {
    let response = try await v3APIClient.search(query: query)
} catch let error as V3ErrorResponse {
    if error.retryable {
        try await Task.sleep(nanoseconds: UInt64(error.retryAfterMs ?? 1000) * 1_000_000)
        // Retry
    } else {
        // Show user-facing error
    }
}
```

#### 3.4 Testing

**Integration Tests:**
- End-to-end search flow (UI → V3 API → Mapping → SwiftData)
- Enrichment flow (ISBNs → V3 Enrich → Mapping → SwiftData)
- Shelf scan flow (Image → Scan → V3 Enrich → SwiftData)
- Error handling (RFC 9457 errors)

**Real Device Testing:**
- Search for books
- Enrich library
- Scan bookshelf
- Import CSV (if V3 endpoint available)
- Network failure scenarios
- Rate limiting behavior

**Deliverables:**
- ✅ All services migrated to V3 API
- ✅ V2APIClient renamed (old V3APIClient)
- ✅ Integration tests passing
- ✅ Real device validation

---

### Phase 4: Cleanup & Optimization (Week 4)

**Goal:** Remove V2 code, optimize V3 integration, ship to production.

#### 4.1 Remove V2 Infrastructure

**Files to Delete:**
- `V2APIClient.swift` (old V3APIClient.swift)
- `BatchEnrichmentPayload.swift` (V2 enrich payload)
- V2-specific error handling code

**Files to Keep:**
- `WorkDTO.swift`, `EditionDTO.swift`, `AuthorDTO.swift` (SwiftData models)
- `BookSearchResponse.swift` (used by mapping layer)
- V3ToV2Mapper (core mapping logic)

#### 4.2 Optimize Caching

**ETag Support:**
- Implement ETag caching for ISBN lookups
- Cache V3 responses in memory (short-term)
- Respect `Cache-Control` headers

**Example:**
```swift
class V3APIClient {
    private var etagCache: [String: String] = [:]  // ISBN → ETag

    func getBook(isbn: String) async throws -> V3Book {
        var request = URLRequest(url: url)
        if let etag = etagCache[isbn] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 304 {
                // Use cached data
                return cachedBook(for: isbn)
            }
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                etagCache[isbn] = etag
            }
        }

        return try JSONDecoder().decode(V3Book.self, from: data)
    }
}
```

#### 4.3 Monitor Performance

**Metrics to Track:**
- API response time (P50, P95, P99)
- Mapping layer overhead
- Cache hit rate (ETag)
- Error rate (RFC 9457 errors)
- Retry frequency

**Tools:**
- OSLog for structured logging
- MetricKit for performance tracking
- Network Link Conditioner for testing

#### 4.4 Documentation

**Update:**
- `AGENTS.md` - Remove V2 references, update API examples
- `CLAUDE.md` - Update workflow examples
- `README.md` - Update API version
- OpenAPI spec validation steps

**Create:**
- Migration guide for future reference
- V3 API integration guide
- Troubleshooting common issues

#### 4.5 Final Testing

**Pre-Release Checklist:**
- [ ] Zero warnings build (`-Werror`)
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Real device testing (iPhone, iPad)
- [ ] Network failure scenarios tested
- [ ] Rate limiting tested
- [ ] ETag caching verified
- [ ] Performance benchmarks met
- [ ] Error handling validated
- [ ] SwiftData persistence verified

**Deliverables:**
- ✅ V2 code removed
- ✅ ETag caching implemented
- ✅ Performance monitoring in place
- ✅ Documentation updated
- ✅ Ready for production

#### Phase 4 Status Update (December 5, 2025)

**Completed:**
- ✅ Cover URL fallback fix (V3ToV2Mapper lines 137, 181)
- ✅ Deleted unused `V3APIClient.swift` (legacy ResponseEnvelope-based wrapper)
- ✅ Added `typealias V3APIError = V3ActualAPIError` for compatibility
- ✅ Moved `enableV3Search` feature flag to FeatureFlags.swift
- ✅ Updated `FeatureFlags.resetToDefaults()` to include V3Search
- ✅ Build validation: Zero warnings

**Files Modified:**
- `V3APIClientActual.swift` (+3 lines)
- `FeatureFlags.swift` (+18 lines)
- `V3BooksService.swift` (-22 lines)

**Files Deleted:**
- `V3APIClient.swift` (unused legacy code)

**V2 Code Retained (Mapping Layer):**
- `ResponseEnvelope.swift` - V2 response wrapper
- `WorkDTO.swift`, `EditionDTO.swift`, `AuthorDTO.swift` - V2 DTOs
- `BookSearchResponse.swift` - V2 search response
- `V3ToV2Mapper.swift` - Critical mapping layer
- `BookSearchAPIService.swift` - V2 fallback (feature-flag controlled)

**Remaining Tasks:**
- [ ] ETag persistence (optional - UserDefaults)
- [ ] Update AGENTS.md (remove V2 references)
- [ ] Create migration summary document
- [ ] Final Grok code review
- [ ] Comprehensive device testing

---

## Workflow-Specific Migration Notes

### 1. Enrichment Workflow

**Current State:**
- Single-book: `GET /api/v2/search?q={query}&mode=text`
- Batch: `POST /api/v2/books/enrich` with `{ books: [Book], jobId: string }`

**V3 Migration:**
- Single-book: `GET /v3/books/search?q={query}`
- Batch: `POST /v3/books/enrich` with `{ isbns: [String], includeEmbedding: false }`

**Key Changes:**
- Remove `jobId` from batch enrichment (V3 handles job management server-side)
- Extract ISBNs from books before calling V3 enrich
- Map V3 unified Book → SwiftData Work/Edition/Author

**Code Impact:**
- `EnrichmentService.swift` (560 lines) - Medium refactor
- `EnrichmentAPIClient.swift` - Replace with V3APIClient

---

### 2. CSV Import Workflow

**Current State:**
- `POST /api/v2/imports` (multipart/form-data)
- SSE streaming at `/api/v2/imports/{jobId}/stream`
- Results from `/api/v2/imports/{jobId}/results`

**V3 Migration:**
- ⚠️ **BLOCKED** - No V3 CSV import endpoint in openapi-v3.json

**Options:**
1. **Keep V2 Endpoint** (Short-term)
   - Backend maintains `/api/v2/imports` for backwards compatibility
   - Migrate later when V3 CSV endpoint available

2. **Client-Side CSV Parsing** (Alternative)
   - Parse CSV in Swift (using Swift's CSV libraries)
   - Extract ISBNs → Call `POST /v3/books/enrich`
   - Stream results to user incrementally

3. **Wait for V3 Spec** (Recommended)
   - Request V3 CSV import specification from backend team
   - Implement once endpoint documented

**Decision Required:** Clarify with backend team CSV import V3 roadmap

**Code Impact:**
- `GeminiCSVImportService.swift` (483 lines) - Blocked until decision

---

### 3. Shelf Scan Workflow

**Current State:**
- ✅ Already using `/api/v3.2/scan-bookshelf` (newer than V3!)
- SSE-first with WebSocket fallback
- Returns ISBNs from shelf image

**V3 Migration:**
- No changes needed for shelf scanning itself
- Update enrichment integration:
  ```swift
  // After shelf scan (line 881)
  let isbns = scanResults.detectedBooks.map(\.isbn)
  let enriched = try await v3APIClient.enrichBooks(isbns: isbns)
  let mapped = V3ToV2Mapper().mapEnrichResponse(enriched)
  ```

**Optimization Opportunity:**
- Remove batch scanning infrastructure (see shelf-scan-optimization-issue.md)
- Focus on single-photo UX improvements

**Code Impact:**
- `BookshelfAIService.swift` (1069 lines) - Small update (enrichment integration)
- Optional: Remove `submitBatch()` method (lines 822-853)

---

## Risk Assessment

### High Risk

**1. SwiftData Relationship Integrity**
- **Risk:** Mapping V3 → V2 DTOs could break Work↔Edition↔Author relationships
- **Mitigation:** Comprehensive integration tests, synthetic ID stability testing
- **Fallback:** Keep V2 API client as emergency rollback

**2. Missing V3 Endpoints**
- **Risk:** CSV import not documented in V3 spec
- **Mitigation:** Clarify with backend team before Phase 3
- **Fallback:** Keep V2 CSV endpoint, migrate later

### Medium Risk

**3. Performance Regression**
- **Risk:** Mapping layer adds latency
- **Mitigation:** Benchmark before/after, optimize hot paths
- **Fallback:** Implement caching to offset mapping overhead

**4. Synthetic ID Collisions**
- **Risk:** Hash-based IDs could collide (unlikely but possible)
- **Mitigation:** Use strong hash function (SHA256), monitor for duplicates
- **Fallback:** Switch to UUID-based IDs if collisions detected

### Low Risk

**5. API Contract Changes**
- **Risk:** V3 API evolves, breaks client
- **Mitigation:** OpenAPI spec validation, versioned endpoints
- **Fallback:** Backend maintains backwards compatibility

**6. Caching Issues**
- **Risk:** ETag caching serves stale data
- **Mitigation:** Respect Cache-Control headers, implement cache invalidation
- **Fallback:** Disable caching if issues arise

---

## Timeline

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| **Phase 1: V3 DTOs & Client** | Week 1 | V3 models, API client, unit tests |
| **Phase 2: Mapping Layer** | Week 2 | V3→V2 mapper, integration tests |
| **Phase 3: Integration** | Week 3 | All services migrated, real device testing |
| **Phase 4: Cleanup** | Week 4 | V2 code removed, ETag caching, production ready |

**Total Effort:** 4 weeks (single developer)

**Parallelization Opportunities:**
- Phase 1 & 2 can overlap (DTO creation + mapping logic)
- Multiple services can be migrated in parallel during Phase 3

---

## Success Criteria

### Functional
- ✅ All search queries return correct results
- ✅ Batch enrichment works with 50+ ISBNs
- ✅ Shelf scanning enrichment integrates seamlessly
- ✅ Error handling graceful (RFC 9457)
- ✅ SwiftData persistence unchanged

### Performance
- ✅ API response time ≤ V2 performance
- ✅ Mapping layer overhead <100ms P95
- ✅ ETag cache hit rate >50%
- ✅ Zero crashes related to V3 migration

### Code Quality
- ✅ Zero warnings build (`-Werror`)
- ✅ 100% test coverage on V3ToV2Mapper
- ✅ All integration tests passing
- ✅ Real device validation complete

---

## Open Questions

1. **CSV Import V3 Endpoint:**
   - Will backend provide `/v3/imports` endpoint?
   - Timeline for V3 CSV import?
   - Should we implement client-side CSV parsing instead?

2. **Batch Scanning:**
   - Is batch scanning used in production? (Analytics needed)
   - Should we remove batch infrastructure? (See shelf-scan-optimization-issue.md)

3. **Backwards Compatibility:**
   - Does backend need to maintain V2 endpoints?
   - What's the V2 sunset timeline?

4. **Author Metadata:**
   - V3 returns `authors: [String]` - any plans to add author IDs/photos?
   - Should we fetch author details separately if needed?

---

## References

**Documentation:**
- `/docs/openapi-v3.json` - V3 API specification
- `/docs/OPENAPI_V3_SPEC_CORRECTIONS.md` - Backend clarifications
- `/shelf-scan-optimization-issue.md` - Shelf scan optimization proposal

**Key Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/V3APIClient.swift` (to be renamed V2APIClient.swift)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/ResponseEnvelope.swift` (V2 DTOs)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentService.swift` (560 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImportService.swift` (483 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift` (1069 lines)

**External:**
- OpenAPI 3.1.0 Specification: https://spec.openapis.org/oas/v3.1.0
- RFC 9457 Problem Details: https://www.rfc-editor.org/rfc/rfc9457.html
- Swift CSV Libraries: https://github.com/topics/csv-parser?l=swift

---

**Last Updated:** December 5, 2025
**Author:** Claude Code (Sonnet 4.5)
**Review Status:** Draft - Pending User & Backend Team Review
**Next Steps:** Address open questions, begin Phase 1 implementation
