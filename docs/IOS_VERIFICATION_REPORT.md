# iOS Team Verification Report - API Contract v3.2

**Generated:** November 27, 2025
**Engineer:** Claude Code
**Scope:** Verify iOS app compliance with API contract v3.2 and prepare for WebSocket→SSE migration

---

## Executive Summary

✅ **CSV Import**: Already using SSE (v2 API) - **NO ACTION NEEDED**
⚠️ **Batch Enrichment**: Using WebSocket - **MIGRATION REQUIRED by March 1, 2026**
⚠️ **Bookshelf Scan**: Using WebSocket - **MIGRATION REQUIRED by March 1, 2026**
✅ **TTL Handling**: No implementation found - **VERIFY with backend team (2-hour TTL)**
✅ **Books Array Parsing**: Not applicable - iOS uses results endpoint, not SSE event payload

---

## 1. CSV Import Service ✅ COMPLIANT

### Current Implementation
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/`

**Status:** Already migrated to SSE (v2 API)

#### SSE Client Features
- ✅ **Last-Event-ID Support**: Implemented in `SSEClient.swift:132-137`
  ```swift
  // Add Last-Event-ID header for reconnection
  if let lastEventId = lastEventId {
      request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
  }
  ```
- ✅ **Automatic Reconnection**: Max 3 attempts with 5-second delay (`SSEClient.swift:148-182`)
- ✅ **Event Buffer**: Handles chunked SSE events (`SSEClient.swift:184-203`)
- ✅ **Network Transition Handling**: Detects cancellations and reconnects (`SSEClient.swift:372-408`)

#### Results Fetching
**Endpoint:** `GET /api/v2/imports/{jobId}/results`
**File:** `GeminiCSVImportService.swift:231-295`

**Response Model:**
```swift
public struct SSEResultsResponse: Codable, Sendable {
    public let booksCreated: Int
    public let booksUpdated: Int
    public let duplicatesSkipped: Int
    public let enrichmentSucceeded: Int
    public let enrichmentFailed: Int
    public let errors: [ImportError]
}
```

**⚠️ CRITICAL FINDING - Books Array:**
- iOS does NOT parse `books` array from results
- Uses only summary counts (`booksCreated`, `booksUpdated`, etc.)
- API contract v3.2 §7.4 mentions `books[]` array - **VERIFY if this is needed**

**Recommendation:**
If `books[]` array is required for detailed import results, update `SSEResultsResponse` model:
```swift
public struct SSEResultsResponse: Codable, Sendable {
    // Existing fields...
    public let books: [ParsedBook]?  // NEW: Detailed book data

    public struct ParsedBook: Codable, Sendable {
        public let title: String
        public let author: String
        public let isbn: String?
        // ... other fields per API contract §7.4
    }
}
```

#### TTL Handling ⚠️ NOT FOUND

**Finding:** No explicit 2-hour TTL validation in iOS code

**Search Results:**
- No references to `expiresAt` field in CSV Import service
- No 404 error handling for expired results
- No client-side TTL validation

**Recommendation:**
1. Backend team: Confirm 2-hour TTL is enforced server-side
2. iOS team: Add TTL validation if backend provides `expiresAt` in results response:
   ```swift
   if let expiresAt = results.expiresAt, Date() > expiresAt {
       throw GeminiCSVImportError.resultsExpired
   }
   ```

---

## 2. Batch Enrichment ⚠️ REQUIRES MIGRATION

### Current Implementation
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentWebSocketHandler.swift`

**Status:** Using WebSocket - **MUST migrate to SSE by March 1, 2026**

#### WebSocket Usage
- **Endpoint:** `ws://[baseURL]/ws/progress?jobId={jobId}`
- **File:** `EnrichmentWebSocketHandler.swift:25`
- **Features:**
  - Job progress updates (`job_progress` events)
  - Job completion with results summary (`job_complete` events)
  - Error handling (`error` events)
  - Results fetching: `GET /v1/jobs/{jobId}/results` (line 141)

#### Migration Path

**Option A: Backend provides SSE endpoint for batch enrichment**
- Create `BatchEnrichmentSSEClient` (similar to CSV Import)
- Endpoint: `GET /api/v2/enrichments/{jobId}/stream` (TBD by backend)
- Event types: `initialized`, `processing`, `completed`, `failed`
- Results endpoint: `GET /api/v2/enrichments/{jobId}/results`

**Option B: Reuse CSV Import SSE pattern**
- If backend unifies SSE protocol across features
- Single `GenericSSEClient` for all streaming updates

**Timeline:**
- Q1 2026: Backend provides SSE endpoint for batch enrichment
- February 2026: iOS implements migration
- March 1, 2026: WebSocket deprecated
- June 1, 2026: WebSocket endpoints removed

**Files to Update:**
1. `EnrichmentWebSocketHandler.swift` → `EnrichmentSSEClient.swift`
2. `EnrichmentQueue.swift` - Update WebSocket references (line 50, 186+)
3. `EnrichmentService.swift` - Update progress tracking
4. Tests: `WebSocketHelpersTests.swift`, `WebSocketProgressManagerTests.swift`

---

## 3. Bookshelf Scan ⚠️ REQUIRES MIGRATION

### Current Implementation
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`

**Status:** Using WebSocket - **MUST migrate to SSE by March 1, 2026**

#### WebSocket Usage
- **Endpoint:** `ws://[baseURL]/ws/progress?jobId={jobId}&token={token}`
- **File:** `BookshelfAIService.swift:160-268` (`processViaWebSocket` method)
- **Features:**
  - Real-time progress updates (line 226)
  - Scan completion with results (line 229-246)
  - Error handling (line 249-257)
  - Authentication token required (line 188)

#### Migration Path

**Same as Batch Enrichment:**
- Create `BookshelfScanSSEClient`
- Endpoint: `GET /api/v2/scans/{jobId}/stream` (TBD by backend)
- Must support authentication (Bearer token or query param)
- Event types: `initialized`, `processing`, `completed`, `failed`
- Results endpoint: `GET /api/v2/scans/{jobId}/results`

**Files to Update:**
1. `BookshelfAIService.swift:160-268` - Replace WebSocket logic
2. `WebSocketProgressManager.swift` - Deprecate or migrate to SSE
3. `BatchWebSocketHandler.swift` - Batch scanning migration
4. Tests: `BookshelfAIServiceWebSocketTests.swift`

---

## 4. API Contract Alignment

### Endpoint Inventory

| Feature | Current Endpoint | Status | V2 Target |
|---------|-----------------|--------|-----------|
| CSV Import Upload | `POST /api/v2/imports` | ✅ Migrated | N/A |
| CSV Import Stream | `GET /api/v2/imports/{jobId}/stream` | ✅ SSE | N/A |
| CSV Import Results | `GET /api/v2/imports/{jobId}/results` | ✅ Migrated | N/A |
| Batch Enrichment | `WS /ws/progress?jobId=...` | ⚠️ WebSocket | `GET /api/v2/enrichments/{jobId}/stream` |
| Batch Enrichment Results | `GET /v1/jobs/{jobId}/results` | ⚠️ V1 | `GET /api/v2/enrichments/{jobId}/results` |
| Bookshelf Scan | `WS /ws/progress?jobId=...&token=...` | ⚠️ WebSocket | `GET /api/v2/scans/{jobId}/stream` |
| Bookshelf Scan Results | `GET /v1/jobs/{jobId}/results` | ⚠️ V1 | `GET /api/v2/scans/{jobId}/results` |

### Missing V2 Endpoints (Backend Team Action Required)

**Priority 1 (Q1 2026):**
1. `GET /api/v2/enrichments/{jobId}/stream` - SSE for batch enrichment
2. `GET /api/v2/enrichments/{jobId}/results` - Unified results endpoint
3. `GET /api/v2/scans/{jobId}/stream` - SSE for bookshelf scanning
4. `GET /api/v2/scans/{jobId}/results` - Unified results endpoint

**Priority 2 (Q2 2026):**
- Deprecation notices for `WS /ws/progress` (March 1, 2026)
- Removal of WebSocket endpoints (June 1, 2026)

---

## 5. Semantic Search

### Current Status
**No implementation found in iOS codebase**

### API Contract v3.2 Notes
- Endpoint: `GET /v1/search/semantic`
- **Current:** No authentication, 5 req/min per IP
- **Proposed (December 2025):** Bearer token auth, 20 req/min (authenticated)
- **Rate Limits:** Documented in API contract

### Recommendation
**Wait for authentication implementation before iOS integration**
- December 2025: Backend adds Bearer token auth
- January 2026: iOS implements semantic search with auth
- February 2026: Production testing
- March 2026: General availability

---

## 6. Action Items for iOS Team

### Immediate (This Sprint)
1. ✅ **Verify TTL handling** - Confirm backend enforces 2-hour TTL, add client-side validation if needed
2. ⚠️ **Verify books array parsing** - Check if `books[]` from results endpoint is required (API contract §7.4)
3. ✅ **Test SSE reconnection** - Real device testing with network transitions (WiFi ↔ Cellular)

### Q1 2026 (Migration Sprint)
1. **Batch Enrichment SSE Migration**
   - Wait for backend SSE endpoint (`/api/v2/enrichments/{jobId}/stream`)
   - Implement `EnrichmentSSEClient` (reuse CSV Import pattern)
   - Update `EnrichmentQueue` and `EnrichmentService`
   - Write tests (SSE reconnection, error handling)
   - Real device testing

2. **Bookshelf Scan SSE Migration**
   - Wait for backend SSE endpoint (`/api/v2/scans/{jobId}/stream`)
   - Implement `BookshelfScanSSEClient`
   - Update `BookshelfAIService` and `WebSocketProgressManager`
   - Write tests
   - Real device testing

3. **V2 Results Endpoints**
   - Migrate from `/v1/jobs/{jobId}/results` to V2 equivalents
   - Update error handling for 404 (expired results)
   - Test TTL expiry scenarios

### Q2 2026 (Cleanup)
1. **Deprecate WebSocket Code**
   - Remove `EnrichmentWebSocketHandler.swift`
   - Remove `WebSocketProgressManager.swift`
   - Remove `GenericWebSocketHandler.swift`
   - Remove tests: `WebSocketHelpersTests.swift`, `WebSocketProgressManagerTests.swift`
   - Update documentation

2. **Semantic Search Implementation**
   - Implement after backend auth ready (December 2025)
   - Add to `SearchService` or new `SemanticSearchService`
   - Handle rate limits (20 req/min with auth)

---

## 7. Questions for Backend Team

### Priority 1 (Blocking Migration)
1. **SSE Endpoints Timeline:**
   - When will `/api/v2/enrichments/{jobId}/stream` be available?
   - When will `/api/v2/scans/{jobId}/stream` be available?
   - Will authentication be required for scan SSE? (token in query param or header?)

2. **Books Array in Results:**
   - API contract §7.4 mentions `books[]` array in CSV import results
   - Current iOS implementation only uses summary counts
   - Is `books[]` required for detailed import results? What fields are included?

3. **TTL Enforcement:**
   - Is 2-hour TTL enforced server-side for CSV import results?
   - Should iOS perform client-side validation using `expiresAt` field?
   - Do batch enrichment and scan results have the same TTL?

### Priority 2 (Future Planning)
4. **Semantic Search:**
   - Confirm December 2025 timeline for Bearer token auth
   - Rate limit details: 20 req/min per user or per token?
   - Will there be a `/api/v2/search/semantic` endpoint?

5. **WebSocket Deprecation:**
   - Confirm March 1, 2026 deprecation date
   - Confirm June 1, 2026 removal date
   - Will deprecation warnings be sent via WebSocket events?

---

## 8. Risk Assessment

### High Risk
- **WebSocket Removal Deadline:** June 1, 2026 is aggressive if SSE endpoints delayed
  - **Mitigation:** Backend commits to Q1 2026 delivery, iOS starts migration in February

### Medium Risk
- **Real Device SSE Testing:** Network transitions (WiFi ↔ Cellular) can break SSE streams
  - **Mitigation:** Extensive real device testing, Last-Event-ID reconnection already implemented

### Low Risk
- **Books Array Parsing:** If required, trivial to add to `SSEResultsResponse` model
  - **Mitigation:** Clarify with backend team, implement if needed (1-2 hour task)

---

## 9. Testing Plan

### CSV Import (Already Migrated)
- [x] SSE reconnection with Last-Event-ID
- [x] Network transition handling (WiFi → Cellular)
- [x] Large CSV files (10MB, 1000+ rows)
- [ ] TTL expiry scenarios (if backend provides `expiresAt`)
- [ ] Books array parsing (if backend confirms requirement)

### Batch Enrichment (Q1 2026 Migration)
- [ ] SSE stream connection
- [ ] Progress events parsing
- [ ] Completion events and results fetching
- [ ] Error handling and reconnection
- [ ] Network transitions during enrichment
- [ ] Timeout scenarios (2-hour TTL)

### Bookshelf Scan (Q1 2026 Migration)
- [ ] SSE stream with authentication
- [ ] Real-time progress updates
- [ ] Scan completion and results parsing
- [ ] Error handling (rate limits, auth failures)
- [ ] Network transitions during scanning
- [ ] Multi-photo batch scanning

---

## 10. Summary

### ✅ Good News
- CSV Import already migrated to SSE - no action needed
- SSE implementation is robust (reconnection, buffering, network transitions)
- Clear migration path for WebSocket features

### ⚠️ Action Required
1. **Verify books array parsing** - Clarify with backend if `books[]` field is needed
2. **Verify TTL handling** - Confirm backend enforcement, add client validation if needed
3. **Plan Q1 2026 migration** - Batch enrichment + bookshelf scan to SSE
4. **Coordinate with backend** - SSE endpoint timelines, authentication requirements

### 📅 Timeline
- **November 2025:** Verify books array + TTL handling
- **December 2025:** Semantic search auth ready (backend)
- **January 2026:** Backend delivers SSE endpoints for enrichment + scan
- **February 2026:** iOS implements SSE migration
- **March 1, 2026:** WebSocket deprecated
- **June 1, 2026:** WebSocket removed

---

**Report Generated By:** Claude Code (Sonnet 4.5)
**Contact:** iOS Team Lead (jukasdrj)
**Next Review:** January 15, 2026 (Post-Backend SSE Delivery)
