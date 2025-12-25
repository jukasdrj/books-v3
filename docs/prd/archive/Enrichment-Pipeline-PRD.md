# Enrichment Pipeline - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** iOS Developer
**Target Release:** v3.1.0+ (Build 47+)
**Last Updated:** November 24, 2025

---

## Executive Summary

The Enrichment Pipeline is a background service that fetches complete book metadata (covers, genres, descriptions, publisher info) after books are initially saved with minimal data. This allows books to appear instantly in the user's library while comprehensive metadata loads asynchronously, creating a responsive user experience across all import methods (CSV, bookshelf scanning, manual search).

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

When users import books via CSV, bookshelf scanning, or search, fetching full metadata inline creates long wait times (60-120 seconds for batch imports). Users experience:
- Blocking UI during enrichment (can't browse library while waiting)
- Frustration with slow imports ("Why is this taking so long?")
- Inconsistent behavior across import methods (some fast, some slow)

### Current Experience (Before Enrichment Pipeline)

**How did users experience imports before this feature?**

- **CSV Import:** User waited 60-120s while each book was enriched inline before seeing library
- **Bookshelf Scan:** AI detection + enrichment happened sequentially, blocking for 40-60s per photo
- **Manual Search:** Enrichment happened during search, causing variable response times
- **Result:** Poor UX with no visibility into what's happening

---

## Target Users

### Primary Persona

**Who benefits from this feature?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | All users (CSV importers, bookshelf scanners, manual entry users) |
| **Usage Frequency** | Every book import action |
| **Tech Savvy** | All levels (transparent background service) |
| **Primary Goal** | Fast, responsive book imports with rich metadata |

**Example User Story:**

> "As a **user importing 50 books via CSV**, I want to **see my books appear immediately** so that I can **start browsing while enrichment happens in background**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Time to Library** | Books appear in <20s (vs 60-120s inline) | Instrumentation (save timestamp) |
| **Background Enrichment** | Full metadata in 1-5 min (depends on batch size) | WebSocket completion events |
| **Zero Blocking** | User can browse library during enrichment | UI responsiveness metrics |
| **Consistency** | All import methods use same pipeline | Code audit |

**Actual Results (Production):**
- ✅ Books appear in 12-17s (CSV import with 50 books)
- ✅ Zero UI blocking during enrichment
- ✅ WebSocket progress updates (real-time visibility)
- ✅ 100% code reuse across CSV, bookshelf, manual add

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Immediate Library Visibility

**As a** user importing books
**I want to** see books appear in my library immediately
**So that** I don't wait for slow enrichment to complete

**Acceptance Criteria:**
- [x] Given user imports CSV with 50 books, when parsing completes, then books appear in library within 20s
- [x] Given books are saved with minimal metadata (title, author, ISBN), when enrichment runs in background, then user can browse library
- [x] Given enrichment is running, when user navigates to book detail, then placeholder data shown (no crashes)

#### User Story 2: Background Metadata Fetching

**As a** user with books in library
**I want** comprehensive metadata (covers, genres, descriptions) to load automatically
**So that** I have rich book information without manual effort

**Acceptance Criteria:**
- [x] Given book saved with ISBN only, when enrichment pipeline processes it, then cover image, genres, description, publisher fetched
- [x] Given enrichment fails for a book, when retry occurs, then user sees updated metadata eventually
- [x] Given enrichment completes, when user views book detail, then all metadata fields populated

#### User Story 3: Real-Time Progress Visibility

**As a** user importing large batches
**I want** to see enrichment progress in real-time
**So that** I know how long to wait and can monitor success

**Acceptance Criteria:**
- [x] Given enrichment job started, when backend processes books, then WebSocket sends "Processing book 3/50" messages
- [x] Given enrichment completes, when final book processed, then WebSocket sends completion event
- [x] Given enrichment fails, when error occurs, then WebSocket sends error message with details

---

## Technical Implementation

### Architecture Overview

**Component Structure:**

```
iOS: EnrichmentQueue (Singleton)
  ├─ Queue Management: Track pending, in-progress, failed enrichment jobs
  ├─ Backend Communication: POST /api/enrichment/start with ISBN list
  └─ WebSocket Listener: Subscribe to /ws/progress?jobId={uuid}

Backend: /api/enrichment/start
  ├─ Input: { isbns: string[], jobId: uuid }
  ├─ Processing: For each ISBN, fetch Google Books + OpenLibrary data
  ├─ Normalization: Convert to canonical DTOs (WorkDTO, EditionDTO)
  └─ Progress Reporting: Send WebSocket updates to ProgressWebSocketDO

ProgressWebSocketDO (Durable Object)
  ├─ Real-time updates: Send "book X/Y" progress messages
  ├─ Job tracking: Store job status (pending, processing, completed, failed)
  └─ Cancellation support: Allow iOS to cancel in-flight jobs
```

**Integration Points:**

- **CSV Import:** After Gemini parses CSV, save books with minimal metadata → Trigger EnrichmentQueue
- **Bookshelf Scanner:** After AI detects books, save high-confidence detections → Trigger EnrichmentQueue
- **Manual Search:** User adds book from search → Immediate save → Trigger EnrichmentQueue

**Data Flow:**

1. User imports books (CSV, bookshelf, search)
2. iOS saves books to SwiftData with minimal metadata (title, author, ISBN)
3. Books appear in library immediately (<20s)
4. iOS calls `EnrichmentQueue.shared.enqueue(isbns)`
5. EnrichmentQueue sends POST /api/enrichment/start with jobId
6. Backend processes books sequentially, sends WebSocket updates
7. iOS receives updates, refreshes book detail views
8. Enrichment completes, all metadata populated

---

## Decision Log

### October 2025 Decisions

#### **Decision:** Background Enrichment Over Inline Enrichment

**Context:** CSV import and bookshelf scanning had 60-120s wait times because enrichment happened inline.

**Options Considered:**
1. Keep inline enrichment (simple, but slow UX)
2. Background enrichment with WebSocket progress (complex, but fast UX)
3. Lazy enrichment on-demand (only enrich when user views book)

**Decision:** Option 2 (Background enrichment with WebSocket progress)

**Rationale:**
- **Better UX:** Books appear in 12-17s instead of 60-120s
- **Consistent behavior:** All import sources use same pipeline (CSV, bookshelf, manual)
- **Real-time feedback:** WebSocket updates keep user informed
- **Scalability:** Can enrich 100+ books without blocking UI

**Tradeoffs:**
- Added complexity (WebSocket management, job tracking)
- Network dependency (enrichment can fail, need retry logic)

---

#### **Decision:** Singleton EnrichmentQueue Pattern

**Context:** Multiple import sources (CSV, bookshelf, search) need centralized enrichment logic.

**Options Considered:**
1. Per-feature enrichment services (duplicated code)
2. Singleton EnrichmentQueue (centralized, shared state)
3. Actor-based queue (Swift 6 concurrency, complex)

**Decision:** Option 2 (Singleton EnrichmentQueue)

**Rationale:**
- **Code reuse:** All import sources call same `enqueue()` method
- **Job tracking:** Centralized `currentJobId` prevents duplicate enrichment requests
- **Cancellation:** Single source of truth for canceling backend jobs (Library Reset feature)

**Tradeoffs:**
- Global mutable state (requires careful concurrency handling with @MainActor)
- Singleton testing challenges (need careful setup/teardown)

---

#### **Decision:** Structured JSON Decoding for WebSocket Keep-Alive (November 23, 2025)

**Context:** WebSocket keep-alive detection used fragile string parsing (`json.contains("\"type\":\"ready_ack\"")`), creating maintenance risk.

**Options Considered:**
1. Keep string-based detection (simple, brittle)
2. Structured JSON decoding via TypedWebSocketMessage (robust, maintainable)

**Decision:** Option 2 (Structured JSON decoding)

**Rationale:**
- **Type safety:** Compiler-verified message type handling
- **Maintainability:** Backend schema changes don't break detection
- **Consistency:** Uses same decoding path as all other message types
- **Debugging:** Clearer error messages for malformed messages

**Implementation:**
```swift
// Before (fragile)
if json.contains("\"type\":\"ready_ack\"") {
    print("✅ Backend acknowledged ready signal")
    return
}

// After (structured)
case .readyAck:
    #if DEBUG
    print("✅ Backend acknowledged ready signal (structured decoding)")
    #endif
```

**Impact:**
- Eliminates false positives/negatives
- Better handling of protocol evolution
- Clearer debug logging

**Outcome:** ✅ Shipped in commit `2c0c386` (November 23, 2025)

**Files Modified:**
- `WebSocketProgressManager.swift` - Removed fragile string check (Issue #4)

**Closes:** Issue #4

---

#### **Decision:** WebSocket Progress Over HTTP Polling

**Context:** Users need visibility into long-running enrichment jobs.

**Options Considered:**
1. HTTP polling every 2s (simple, high latency)
2. WebSocket real-time updates (complex, low latency)
3. No progress (bad UX, users think app is frozen)

**Decision:** Option 2 (WebSocket real-time updates)

**Rationale:**
- **Performance:** 8ms latency vs 500ms polling (62x faster)
- **Battery efficiency:** No repeated HTTP requests
- **Real-time:** Users see progress immediately ("Processing book 5/50")

**Tradeoffs:**
- WebSocket connection management (reconnection logic needed)
- Durable Object costs (minimal for our scale)

**Security & Protocol Updates (November 23, 2025):**
- Structured JSON decoding for keep-alive detection (replaced fragile string parsing)
- Prevents false positives/negatives as backend schema evolves
- See commit `2c0c386` for implementation details

---

#### **Decision:** Minimal Metadata Save, Full Enrichment Later

**Context:** Need to balance "time to library visibility" with "complete metadata".

**Options Considered:**
1. Save nothing until full enrichment completes (slow, 60-120s wait)
2. Save minimal metadata (title, author, ISBN), enrich later (fast, 12-17s)
3. Save everything inline (blocks UI, poor UX)

**Decision:** Option 2 (Minimal metadata save, full enrichment later)

**Rationale:**
- **Fast UX:** Books appear in library immediately
- **Graceful degradation:** If enrichment fails, user still has basic book info
- **Consistent with iOS HIG:** Apps should feel responsive, background work invisible

**Tradeoffs:**
- Book details initially incomplete (covers, genres missing until enrichment completes)
- Need placeholder UI for missing data

---

## Workflow Integration

**Related Workflow Diagram:** `docs/workflows/enrichment-workflow.md`

**Key User Flows:**

1. **CSV Import → Enrichment:**
   - User uploads CSV → Gemini parses → Books saved to SwiftData → EnrichmentQueue.enqueue() → WebSocket progress → Full metadata

2. **Bookshelf Scan → Enrichment:**
   - User scans bookshelf → Gemini detects ISBNs → High-confidence books saved → EnrichmentQueue.enqueue() → Background enrichment

3. **Manual Search → Enrichment:**
   - User searches book → Adds to library → Book saved with search metadata → EnrichmentQueue.enrich() (optional if already enriched)

---

## API Specification

### POST /api/enrichment/start

**Request:**
```json
{
  "isbns": ["9780374533557", "9780143127741"],
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "totalBooks": 2,
    "estimatedTime": "30-60s"
  },
  "meta": {
    "timestamp": "2025-10-31T14:30:00Z",
    "provider": "enrichment-service"
  }
}
```

**WebSocket Progress Messages:**

```json
{
  "type": "progress",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1698764400000,
  "data": {
    "progress": 0.5,
    "processedItems": 1,
    "totalItems": 2,
    "currentStatus": "Processing: The Three-Body Problem"
  }
}
```

**WebSocket Completion:**

```json
{
  "type": "complete",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1698764430000,
  "data": {
    "successCount": 2,
    "failedCount": 0,
    "enrichedWorks": [
      {
        "isbn": "9780374533557",
        "title": "The Three-Body Problem",
        "coverUrl": "https://...",
        "genres": ["Science Fiction", "Fiction"],
        "description": "..."
      }
    ]
  }
}
```

---

## Implementation Files

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/CSVImportService.swift` (uses EnrichmentQueue)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookshelfScannerService.swift` (uses EnrichmentQueue)

**Backend:**
- `cloudflare-workers/api-worker/src/handlers/enrichment.ts`
- `cloudflare-workers/api-worker/src/durable-objects/ProgressWebSocketDO.ts`
- `cloudflare-workers/api-worker/src/services/google-books.ts` (metadata fetching)

---

## Error Handling

### iOS Error States

| Error Condition | User Experience | Recovery Action |
|----------------|-----------------|-----------------|
| Network timeout | Toast: "Enrichment failed, will retry" | Auto-retry in background |
| Backend 500 error | Toast: "Server error, try again later" | Manual retry button |
| Invalid ISBN | Skip book, continue enrichment | Log error, don't block pipeline |
| WebSocket disconnect | Reconnect automatically | Resume from last processed book |

### Backend Error Handling

- **Google Books API failure:** Fall back to OpenLibrary
- **OpenLibrary failure:** Save partial metadata, mark for retry
- **Invalid ISBN format:** Skip book, log error, continue pipeline
- **Durable Object unavailable:** Degrade to no progress updates (enrichment still works)

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Automatic Retry for Failed Enrichment**
   - Store failed ISBNs in persistent queue
   - Retry with exponential backoff (1hr, 4hr, 24hr)
   - User notification: "We found more metadata for 3 books"

2. **Manual "Enrich Now" Button**
   - Allow users to trigger enrichment for individual books
   - Useful for books with incomplete metadata
   - Show progress spinner during enrichment

3. **Batch Priority Management**
   - User-triggered enrichment (manual search) = high priority
   - Background enrichment (CSV import) = low priority
   - Prevents backend overload during large imports

4. **Enrichment Analytics**
   - Track enrichment success rate per provider
   - Identify ISBNs that consistently fail
   - Add "Report Missing Metadata" button for users

---

## Testing Strategy

### Unit Tests

- ✅ EnrichmentQueue: enqueue, dequeue, job tracking
- ✅ WebSocket message parsing (progress, complete, error)
- ✅ Backend: enrichment handler with mocked Google Books API

### Integration Tests

- ✅ CSV Import → Enrichment pipeline end-to-end
- ✅ Bookshelf Scan → Enrichment pipeline end-to-end
- ✅ WebSocket reconnection after network loss

### Manual QA Scenarios

- [ ] Import 100-book CSV, verify all books enriched
- [ ] Cancel enrichment mid-process (Library Reset), verify backend stops
- [ ] Disconnect WiFi during enrichment, verify reconnection + resume
- [ ] Import books with invalid ISBNs, verify graceful skipping

---

## Dependencies

**iOS:**
- SwiftData (persistent storage for enriched metadata)
- WebSocket client (real-time progress updates)
- DTOMapper (convert canonical DTOs to SwiftData models)

**Backend:**
- Google Books API (primary metadata source)
- OpenLibrary API (fallback metadata source)
- ProgressWebSocketDO (Durable Object for real-time progress)

**External:**
- Network connectivity (enrichment requires internet)
- Backend availability (graceful degradation if offline)

---

## Success Criteria (Shipped)

- ✅ Books appear in library in <20s (CSV import with 50 books)
- ✅ Enrichment happens in background (zero UI blocking)
- ✅ WebSocket progress updates (real-time visibility)
- ✅ All import methods use same pipeline (CSV, bookshelf, manual)
- ✅ Backend job cancellation (Library Reset feature)
- ✅ Graceful error handling (failed enrichment doesn't block pipeline)

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
**Documentation:** See `docs/workflows/enrichment-workflow.md` for visual flow diagram
