# iOS Team API Priorities - Backend Response

**Date:** November 27, 2025
**From:** BooksTrack Backend Team
**To:** iOS Development Team
**Status:** ✅ All clarifications provided

---

## Executive Summary

Thank you for the detailed priorities list. This document addresses all three priorities and provides actionable guidance for iOS implementation.

**Quick Actions Required:**
1. ✅ Parse `books` array from job results (already documented, see §1)
2. ⚠️ Update TTL handling to 2 hours (was incorrectly documented as 1 hour, see §1.2)
3. ✅ SSE is already production-ready for CSV imports (no WebSocket migration needed yet)
4. ⏳ Semantic search auth requirements clarified (see §3)

---

## 1. Priority #1: WebSocket Deprecation Timeline

### Current Status: CLARIFIED ✅

**IMPORTANT:** The deprecation notice in API_CONTRACT.md §8 applies **ONLY** to legacy WebSocket use for new job types. Existing integrations are safe.

### Timeline

| Date | Milestone | Impact on iOS |
|------|-----------|---------------|
| **Nov 21, 2025** | SSE Progress Stream (§7.2) launched for CSV Import (V2) | ✅ **iOS CSVImportService already uses SSE** - no action needed |
| **Nov 27, 2025** | WebSocket still supported for `batch_enrichment` legacy jobs | ✅ Existing iOS batch enrichment can continue using WebSocket |
| **March 1, 2026** | ⚠️ WebSocket API marked as fully deprecated | iOS MUST migrate all features to SSE by this date |
| **June 1, 2026** | WebSocket API sunset (removal) | All iOS features MUST use SSE or HTTP polling |

### Migration Strategy

**RECOMMENDED:** Migrate proactively during Q1 2026 (January-March)

**For iOS Team:**
1. **CSV Import:** ✅ Already using SSE (`/api/v2/imports/{jobId}/stream`) - no migration needed
2. **Batch Enrichment:** ⏳ Migrate from WebSocket to SSE by March 1, 2026
3. **Bookshelf Scan:** ⏳ Migrate from WebSocket to SSE by March 1, 2026

**SSE Advantages over WebSocket:**
- ✅ Automatic reconnection with `Last-Event-ID` (iOS `EventSource` library handles this)
- ✅ No authentication required (jobId is sufficient)
- ✅ HTTP/2 compatible (WebSocket requires HTTP/1.1)
- ✅ Better Cloudflare Workers integration (no Durable Object hibernation issues)
- ✅ Browser-native `EventSource` API (simpler than WebSocket lifecycle)

**Migration Guide:**
- See `docs/SSE_MIGRATION_GUIDE.md` (to be created, Issue #TBD)
- Example iOS implementation: See `CSVImportService.swift` (already uses SSE)

### Action Items for iOS

- [ ] **Immediate (This Week):**
  - Verify `CSVImportService` handles 2-hour TTL (updated from 1 hour)
  - Test late-connect SSE reconnection (server sends results immediately if job complete)

- [ ] **Q1 2026 (Before March 1):**
  - Migrate `BatchEnrichmentService` from WebSocket to SSE
  - Migrate `BookshelfScanService` from WebSocket to SSE
  - Remove all WebSocket connection code

- [ ] **Testing:**
  - Test SSE reconnection with `Last-Event-ID` (disconnect during job, reconnect)
  - Test late-connect (connect after job completes)
  - Test long-running jobs (>60 seconds, verify heartbeat handling)

---

## 2. Priority #2: Endpoint Inconsistencies

### Current Status: ACKNOWLEDGED ⚠️

You are correct - there are inconsistencies between V1 and V2 endpoints that need consolidation.

### Identified Inconsistencies

#### 2.1 Batch Enrichment

**Current (Inconsistent):**
- `/api/batch-enrich` (V1, WebSocket progress)
- `/api/v2/books/enrich` (V2, single book only)

**Issue:** No V2 batch enrichment endpoint with SSE support

**Backend Action:** Create Issue #TBD for `/api/v2/books/enrich-batch`

**Proposed V2 Endpoint:**
```http
POST /api/v2/books/enrich-batch
Content-Type: application/json

{
  "barcodes": ["9780439708180", "9780747532699"],
  "vectorize": true
}

Response:
{
  "success": true,
  "data": {
    "jobId": "batch_enrich_uuid",
    "sseUrl": "/api/v2/books/enrich-batch/{jobId}/stream",
    "statusUrl": "/api/v2/books/enrich-batch/{jobId}"
  }
}
```

**Timeline:** Target for Sprint 4 (December 2025)

#### 2.2 Semantic Search

**Current (Inconsistent):**
- `/api/v2/search?mode=semantic&q=...` (V2, documented in API_CONTRACT.md §5.4)
- No `/v1/search/semantic` equivalent

**Issue:** Mixed versioning (V2 only) and unclear auth requirements

**Backend Action:** See Priority #3 below

#### 2.3 Job Results

**Current (Acceptable):**
- `/api/v2/imports/{jobId}/results` (V2 CSV import)
- `/v1/jobs/{jobId}/results` (V1 generic job results)

**Status:** ✅ This is acceptable - both work for backward compatibility

**Recommendation for iOS:**
- Use V2 endpoints for new features (`/api/v2/imports/{jobId}/results`)
- Continue using V1 for legacy batch enrichment (`/v1/jobs/{jobId}/results`)

### Consolidation Roadmap

**Phase 1 (December 2025):**
- Create `/api/v2/books/enrich-batch` with SSE support
- Document all V2 endpoints in API_CONTRACT.md
- Add deprecation warnings to V1 batch endpoints

**Phase 2 (January 2026):**
- Migrate semantic search to `/v1/search/semantic` (see Priority #3)
- Standardize auth across all V2 endpoints

**Phase 3 (March 2026):**
- Sunset V1 batch endpoints (90-day notice: December 1, 2025)
- Remove WebSocket support entirely

### Action Items for iOS

- [ ] **Immediate:**
  - Continue using existing endpoints (no breaking changes)
  - Plan for `/api/v2/books/enrich-batch` migration in December

- [ ] **December 2025:**
  - Test new `/api/v2/books/enrich-batch` endpoint
  - Migrate `BatchEnrichmentService` to V2 + SSE

- [ ] **January 2026:**
  - Test semantic search auth changes (see Priority #3)

---

## 3. Priority #3: Semantic Search Auth & Rate Limits

### Current Status: CLARIFIED ✅

**Documented in API_CONTRACT.md §5.4:**
```http
GET /api/v2/search?mode=semantic&q=books+about+magic+schools&limit=10
```

**Rate Limit:** 5 req/min per IP (AI compute intensive)

### Authentication Requirements

**Current:** ❌ No authentication required (public API)
**Recommended:** ⚠️ Add authentication to prevent abuse (AI costs $$$)

**Backend Proposal (Issue #TBD):**
```http
GET /v1/search/semantic?q=query&limit=10
Authorization: Bearer <user-token>

Rate Limit:
- Authenticated: 20 req/min per user (higher limit)
- Unauthenticated: 5 req/min per IP (current)
```

**Rationale:**
- Semantic search uses Cloudflare AI embeddings (~$0.01 per 1000 requests)
- Current 5 req/min per IP can be abused by rotating IPs
- Authenticated users can have higher limits (20 req/min)

### iOS Implementation Guidance

**Option 1: Wait for Auth (Recommended)**
- Backend will implement auth in Sprint 4 (December 2025)
- iOS can implement semantic search UI now, but wait for auth before production

**Option 2: Implement Now (Risk)**
- Use current unauthenticated endpoint (`/api/v2/search?mode=semantic`)
- Implement aggressive client-side rate limiting (5 req/min)
- Migrate to authenticated endpoint when available (December)

**Example iOS Code (Option 1 - Recommended):**
```swift
func semanticSearch(query: String) async throws -> [Book] {
    // Wait for backend auth implementation before using
    throw SemanticSearchError.authNotImplemented
}
```

**Example iOS Code (Option 2 - Risky):**
```swift
func semanticSearch(query: String) async throws -> [Book] {
    let url = URL(string: "https://api.oooefam.net/api/v2/search?mode=semantic&q=\(query)&limit=10")!
    var request = URLRequest(url: url)
    // No auth for now - will add Bearer token in December 2025

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.invalidResponse
    }

    // Handle rate limiting (429)
    if httpResponse.statusCode == 429 {
        throw NetworkError.rateLimitExceeded
    }

    let result = try JSONDecoder().decode(SearchResponse.self, from: data)
    return result.data.books
}
```

### Rate Limit Handling

**iOS MUST implement:**
1. Exponential backoff on `429 Rate Limit Exceeded`
2. Respect `Retry-After` header (seconds until reset)
3. Local rate limiting (don't send more than 5 req/min)

**Example Rate Limit Handler:**
```swift
func handleRateLimitError(_ response: HTTPURLResponse) -> TimeInterval {
    // Read Retry-After header (seconds)
    if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
       let seconds = TimeInterval(retryAfter) {
        return seconds
    }
    // Fallback: 60 seconds
    return 60
}

// Usage
if httpResponse.statusCode == 429 {
    let delay = handleRateLimitError(httpResponse)
    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    // Retry request
}
```

### Semantic Search Feature Spec

**Backend Capabilities:**
- Model: BGE-M3 (multilingual, 1024 dimensions)
- Index: Cloudflare Vectorize (1M+ books)
- Latency: ~500ms P95 (cached), ~2s P95 (cold)
- Accuracy: 85%+ relevance for natural language queries

**iOS Use Cases:**
1. "Books about magic schools" → Returns Harry Potter, etc.
2. "Historical fiction set in WWII" → Returns WWII novels
3. "Self-help books for entrepreneurs" → Returns business/motivation books

**iOS UI Recommendations:**
- Add semantic search toggle in search bar
- Show "Powered by AI" badge
- Display confidence scores if available (future)
- Fallback to title search if semantic fails

### Action Items for iOS

- [ ] **Immediate:**
  - DO NOT implement semantic search in production yet
  - Plan UI/UX for semantic search feature

- [ ] **December 2025 (After Backend Auth Launch):**
  - Implement authenticated semantic search
  - Add rate limit handling (exponential backoff)
  - Test with production API keys

- [ ] **Testing:**
  - Test rate limiting (send >5 req/min, verify 429 response)
  - Test `Retry-After` header handling
  - Test semantic search accuracy (compare with title search)

---

## 4. Additional Recommendations for iOS

### 4.1 Parse `books` Array in Job Results

**CRITICAL:** API_CONTRACT.md §7.4 (lines 447-472) documents the `books` array in job results.

**Current iOS Issue:**
> "Parse books array in job results (docs/API_CONTRACT.md:447-462) - add to CSVImportService"

**Backend Clarification:**
The `books` array is ALREADY returned in `/api/v2/imports/{jobId}/results` and `/v1/jobs/{jobId}/results`.

**Example Response (API_CONTRACT.md:437-470):**
```json
{
  "success": true,
  "data": {
    "booksCreated": 145,
    "enrichmentSucceeded": 140,
    "books": [
      {
        "isbn": "9780439708180",
        "title": "Harry Potter and the Sorcerer's Stone",
        "authors": ["J.K. Rowling"],
        "publisher": "Scholastic",
        "publishedDate": "1998-09-01",
        "pageCount": 320,
        "coverUrl": "https://..."
      }
    ]
  }
}
```

**iOS Action Required:**
Add parsing logic to `CSVImportService.swift` to save `books` array to SwiftData:

```swift
func processJobResults(jobId: String) async throws {
    let url = URL(string: "https://api.oooefam.net/api/v2/imports/\(jobId)/results")!
    let (data, _) = try await URLSession.shared.data(from: url)

    let response = try JSONDecoder().decode(JobResultsResponse.self, from: data)

    // CRITICAL: Parse books array and save to SwiftData
    for book in response.data.books {
        let swiftDataBook = Book(
            isbn: book.isbn,
            title: book.title,
            authors: book.authors,
            publisher: book.publisher,
            publishedDate: book.publishedDate,
            pageCount: book.pageCount,
            coverUrl: book.coverUrl
        )
        modelContext.insert(swiftDataBook)
    }

    try modelContext.save()
}
```

### 4.2 TTL Handling - UPDATED

**CHANGE:** Results TTL changed from 1 hour to 2 hours (API_CONTRACT.md v3.1, line 19)

**Rationale:**
- WebSocket tokens expire after 2 hours
- Results should persist as long as tokens are valid
- iOS has 2 hours to fetch results after job completes

**iOS Action Required:**
Update `CSVImportService` to handle 2-hour TTL:

```swift
// OLD (incorrect)
let resultsTTL: TimeInterval = 3600  // 1 hour

// NEW (correct)
let resultsTTL: TimeInterval = 7200  // 2 hours

// Check if job results are still available
func areResultsExpired(completedAt: Date) -> Bool {
    let expiresAt = completedAt.addingTimeInterval(7200)  // 2 hours
    return Date() > expiresAt
}
```

**Backward Compatibility:**
API returns `expiresAt` timestamp in `job_complete` messages (API_CONTRACT.md:662):
```json
{
  "type": "job_complete",
  "payload": {
    "expiresAt": "2025-11-28T12:00:00.000Z"
  }
}
```

iOS should use `expiresAt` from API response instead of hardcoding TTL.

### 4.3 SSE Reconnection (Already Implemented?)

**Verify:** Does `CSVImportService` handle SSE reconnection with `Last-Event-ID`?

**API Contract (API_CONTRACT.md:395-399):**
```
Reconnection:
- Client sends `Last-Event-ID` header with last received event ID
- Server resumes from that point (skips duplicate events)
- Retry interval: 5000ms (5 seconds)
```

**iOS Recommended Implementation:**
Use `EventSource` library with automatic reconnection:

```swift
import EventSource

func streamJobProgress(jobId: String) {
    let url = URL(string: "https://api.oooefam.net/api/v2/imports/\(jobId)/stream")!

    let eventSource = EventSource(url: url)

    eventSource.onOpen {
        print("SSE connection opened")
    }

    eventSource.addEventListener("processing") { id, event, data in
        // id is the event ID (for Last-Event-ID)
        // Parse data and update UI
        if let progressData = data?.data(using: .utf8),
           let progress = try? JSONDecoder().decode(ProgressUpdate.self, from: progressData) {
            DispatchQueue.main.async {
                self.updateProgress(progress.progress)
            }
        }
    }

    eventSource.addEventListener("completed") { id, event, data in
        // Job finished - fetch results
        Task {
            try await self.processJobResults(jobId: jobId)
        }
    }

    eventSource.addEventListener("failed") { id, event, data in
        // Handle failure with structured error
        if let errorData = data?.data(using: .utf8),
           let error = try? JSONDecoder().decode(JobError.self, from: errorData) {
            self.handleJobError(error)
        }
    }

    // EventSource library handles Last-Event-ID automatically
}
```

---

## 5. Backend Action Items (Issues to Create)

Based on iOS priorities, backend will create the following issues:

### Issue #TBD-1: Semantic Search Authentication
**Priority:** P1 (High)
**Target:** Sprint 4 (December 2025)
**Description:** Add Bearer token authentication to semantic search endpoint
**Endpoint:** `/v1/search/semantic` (migrate from `/api/v2/search?mode=semantic`)
**Requirements:**
- Authenticated: 20 req/min per user
- Unauthenticated: 5 req/min per IP (backward compatible)
- Return 401 if token invalid, 429 if rate limit exceeded

### Issue #TBD-2: V2 Batch Enrichment Endpoint
**Priority:** P2 (Medium)
**Target:** Sprint 4 (December 2025)
**Description:** Create `/api/v2/books/enrich-batch` with SSE progress
**Requirements:**
- Same request format as `/api/batch-enrich`
- SSE progress stream (like CSV import)
- Deprecate `/api/batch-enrich` (90-day notice)

### Issue #TBD-3: SSE Migration Guide
**Priority:** P3 (Low)
**Target:** Sprint 4 (December 2025)
**Description:** Create `docs/SSE_MIGRATION_GUIDE.md` for iOS team
**Requirements:**
- Code examples (Swift + EventSource library)
- Migration checklist for batch enrichment and bookshelf scan
- Testing guide for reconnection and late-connect

---

## 6. Timeline Summary

| Date | Milestone | iOS Action |
|------|-----------|------------|
| **Nov 27, 2025** | Current state (all endpoints stable) | ✅ Verify TTL handling (2 hours) |
| **Dec 15, 2025** | Semantic search auth launched | Test authenticated semantic search |
| **Dec 31, 2025** | V2 batch enrichment endpoint | Migrate batch enrichment to V2 + SSE |
| **Jan 15, 2026** | SSE migration guide published | Review guide, plan migration |
| **Mar 1, 2026** | WebSocket fully deprecated | Complete all SSE migrations |
| **Jun 1, 2026** | WebSocket sunset (removal) | All features using SSE or polling |

---

## 7. Contact & Support

**Questions about this response:**
- GitHub Issue: TBD (create in `bookstrack-backend` repo)
- Slack: #api-backend-ios channel

**API Contract Updates:**
- Watch `docs/API_CONTRACT.md` for changes
- Subscribe to API changelog: https://api.oooefam.net/changelog

**Backend Team:**
- Lead: @jukasdrj
- Agents: cf-ops-monitor, cf-code-reviewer

---

**Document Version:** 1.0
**Last Updated:** November 27, 2025
**Next Review:** December 15, 2025 (after semantic search auth launch)
