# Sprint 4: iOS Intelligence Integration

**Status:** PLANNING COMPLETE
**Date:** November 25, 2025
**Target:** February 2026
**Team:** iOS Development
**Prerequisite:** Sprint 3 Backend Complete (V2 API Live)

---

## Executive Summary

Sprint 4 integrates the backend V2 API intelligence features into the iOS app:
- Semantic search with natural language queries
- Similar books discovery via vector embeddings
- Weekly AI-generated recommendations
- WebSocket to SSE migration for imports

**Scope:** 6 features, 4 weeks, ~20 tasks
**Critical Path:** SSE Migration (Week 3)
**Key Risk:** SSE stability on mobile networks

---

## Sprint Overview

```
+------------------+     +------------------+     +------------------+     +------------------+
|     WEEK 1       |     |     WEEK 2       |     |     WEEK 3       |     |     WEEK 4       |
| Foundation +     | --> | Search           | --> | SSE Migration    | --> | Polish +         |
| Quick Wins       |     | Intelligence     |     | (Critical Path)  |     | Testing          |
+------------------+     +------------------+     +------------------+     +------------------+
| - Capabilities   |     | - Semantic Search|     | - SSEClient      |     | - Integration    |
| - V2 Enrichment  |     | - Rate Limiting  |     | - Import Service |     |   Tests          |
| - Recommendations|     | - Similar Books  |     | - Polling        |     | - Edge Cases     |
|   Widget         |     |   Section        |     |   Fallback       |     | - Documentation  |
+------------------+     +------------------+     +------------------+     +------------------+
```

---

## Backend Endpoints (from openapi.yaml v2.7.0)

| Method | Endpoint | Description | Rate Limit |
|--------|----------|-------------|------------|
| `GET` | `/api/v2/capabilities` | Feature discovery | - |
| `GET` | `/api/v2/search?mode=semantic` | Semantic search | 5 req/min |
| `GET` | `/api/v2/search?mode=text` | Text search | 100 req/min |
| `GET` | `/v1/search/similar?isbn=` | Similar books | - |
| `GET` | `/api/v2/recommendations/weekly` | Weekly picks | - |
| `POST` | `/api/v2/books/enrich` | V2 enrichment | 1000 req/hr |
| `POST` | `/api/v2/imports` | CSV import init | 10/hr |
| `GET` | `/api/v2/imports/{jobId}/stream` | SSE progress | - |
| `GET` | `/api/v2/imports/{jobId}` | Polling fallback | - |

---

## Feature Specifications

### Feature 1: Capabilities Detection Service

**Priority:** P0 (Foundation)
**Complexity:** S
**Dependencies:** None (must complete first)

**Description:**
Create `APICapabilitiesService` to detect available backend features on app launch.

**Implementation:**
```
App Launch --> GET /api/v2/capabilities --> Cache in UserDefaults (1hr TTL)
                                                    |
                    +-------------------------------+
                    |               |               |
            isSemanticSearch  isSimilarBooks  isRecommendations
               Enabled           Enabled          Enabled
```

**Tasks:**
- [ ] Create `APICapabilitiesService` actor
- [ ] Define `APICapabilities` model matching response schema
- [ ] Implement caching with 1-hour TTL in UserDefaults
- [ ] Expose feature flags as published properties
- [ ] Handle offline gracefully (use cached or disable features)
- [ ] Call on app launch in `BooksTrackerApp.swift`

**Response Schema:**
```json
{
  "features": {
    "semantic_search": true,
    "similar_books": true,
    "weekly_recommendations": true
  },
  "limits": {
    "semantic_search_rpm": 5,
    "text_search_rpm": 100
  },
  "version": "2.7.0"
}
```

---

### Feature 2: Semantic Search Integration

**Priority:** P0
**Complexity:** M
**Dependencies:** Capabilities Service

**Description:**
Add semantic (AI-powered) search mode to existing SearchView.

**UI Flow:**
```
SearchView
    |
    +-- [Text | Semantic] Toggle (Picker)
    |
    +-- Rate Limit Indicator (5 req/min)
    |       |
    |       +-- [====----] 3/5 remaining
    |       +-- "Resets in 45s" when exhausted
    |
    +-- Results with relevance_score
            |
            +-- "AI-powered" badge on semantic results
```

**Tasks:**
- [ ] Create `SemanticSearchService` calling `/api/v2/search?mode=semantic`
- [ ] Add search mode toggle (Picker) to SearchView
- [ ] Implement rate limit tracking (5 req/min window)
- [ ] Create rate limit indicator component
- [ ] Show "AI-powered" badge on semantic results
- [ ] Display `relevance_score` in result cells
- [ ] Handle 429 errors with retry countdown
- [ ] Persist search mode preference in UserDefaults

**Edge Cases:**
- Rate limit exceeded: Show countdown, disable semantic toggle
- Empty results: Show "No AI matches found, try text search"
- Offline: Disable semantic mode, show text-only

---

### Feature 3: Similar Books Section

**Priority:** P1
**Complexity:** M
**Dependencies:** Capabilities Service, BookDetailView exists

**Description:**
Add "Similar Books" horizontal scroll section to BookDetailView using vector similarity.

**UI Flow:**
```
BookDetailView
    |
    +-- [Existing Content: Cover, Title, Author, etc.]
    |
    +-- "Similar Books" Section
            |
            +-- Horizontal ScrollView
            |       |
            |       +-- BookCard (cover + title)
            |       +-- BookCard
            |       +-- BookCard...
            |
            +-- "Based on AI analysis"
```

**Tasks:**
- [ ] Create `SimilarBooksService` calling `/v1/search/similar?isbn=`
- [ ] Create `SimilarBooksSection` SwiftUI component
- [ ] Add section to BookDetailView (below existing content)
- [ ] Implement lazy loading (load on appear, don't block render)
- [ ] Show skeleton loading state
- [ ] Cache results in memory (per-session)
- [ ] Handle 404 (book not vectorized) - hide section gracefully
- [ ] Tap navigates to book detail

**Response Schema:**
```json
{
  "results": [
    {
      "isbn": "9780439064866",
      "title": "Harry Potter and the Chamber of Secrets",
      "authors": ["J.K. Rowling"],
      "similarity_score": 0.94,
      "cover_url": "https://..."
    }
  ],
  "source_isbn": "9780747532743",
  "total": 5
}
```

---

### Feature 4: Recommendations Widget

**Priority:** P1
**Complexity:** M
**Dependencies:** Capabilities Service, InsightsView exists

**Description:**
Display weekly AI-generated book recommendations in InsightsView.

**UI Flow:**
```
InsightsView
    |
    +-- [Existing: DiversityCompletionWidget]
    +-- [Existing: RepresentationRadarChart]
    +-- [Existing: StreakVisualizationView]
    |
    +-- WeeklyRecommendationsWidget
            |
            +-- "This Week's Picks" header
            +-- Horizontal ScrollView
            |       |
            |       +-- RecommendationCard
            |               +-- Cover image
            |               +-- Title
            |               +-- AI reason text
            |
            +-- "Next refresh: Sunday" footer
```

**Tasks:**
- [ ] Create `RecommendationsService` calling `/api/v2/recommendations/weekly`
- [ ] Create `WeeklyRecommendation` SwiftData model
- [ ] Create `WeeklyRecommendationsWidget` SwiftUI component
- [ ] Create `RecommendationCard` subcomponent
- [ ] Add widget to InsightsView
- [ ] Cache in SwiftData with `week_of` as key
- [ ] Show "Next refresh" date from response
- [ ] Handle 404 (not generated yet) - show placeholder

**Response Schema:**
```json
{
  "week_of": "2026-02-03",
  "books": [
    {
      "isbn": "9780747532743",
      "title": "Harry Potter...",
      "authors": ["J.K. Rowling"],
      "cover_url": "https://...",
      "reason": "A beloved fantasy classic perfect for readers seeking magical escapism"
    }
  ],
  "generated_at": "2026-02-02T00:00:00Z",
  "next_refresh": "2026-02-09T00:00:00Z"
}
```

---

### Feature 5: SSE Import Migration

**Priority:** P0 (Critical Path)
**Complexity:** L
**Dependencies:** None (independent track)

**Description:**
Migrate CSV import from WebSocket to HTTP/SSE pattern for improved reliability.

**Flow:**
```
                    +---------------+
                    | POST /imports |
                    +-------+-------+
                            |
                            v
                    +-------+-------+
                    |   202 Accepted |
                    |   { job_id }   |
                    +-------+-------+
                            |
            +---------------+---------------+
            |                               |
            v                               v
    +-------+-------+               +-------+-------+
    | SSE Stream    |   (fallback)  | Polling       |
    | /stream       | ------------> | GET /{jobId}  |
    +-------+-------+  after 3 fail +-------+-------+
            |                               |
            +---------------+---------------+
                            |
                            v
                    +-------+-------+
                    | ImportProgress |
                    | View updated   |
                    +---------------+
```

**Tasks:**
- [ ] Create `SSEClient` using native URLSession
  - Parse `text/event-stream` format
  - Handle `event:`, `data:`, `id:` fields
  - Support `Last-Event-ID` header for reconnection
- [ ] Create `V2ImportService` to replace WebSocket-based service
  - `startImport(file:)` -> POST /imports
  - `streamProgress(jobId:)` -> SSE stream
  - `pollProgress(jobId:)` -> GET fallback
- [ ] Implement automatic fallback after 3 SSE failures
- [ ] Update `ImportProgressView` to use new service
- [ ] Handle network transitions (WiFi <-> cellular)
- [ ] Remove WebSocket dependency for imports
- [ ] Add integration tests for full import flow

**SSE Event Format:**
```
event: started
data: {"status": "processing", "total_rows": 150}

event: progress
data: {"progress": 0.5, "processed_rows": 75}

event: complete
data: {"status": "complete", "result_summary": {...}}
```

---

### Feature 6: V2 Enrichment Migration

**Priority:** P1
**Complexity:** S
**Dependencies:** None (independent)

**Description:**
Update barcode enrichment to use new V2 HTTP endpoint.

**Tasks:**
- [ ] Update `BookEnrichmentService` to call `POST /api/v2/books/enrich`
- [ ] Add `idempotency_key` parameter for retry safety
- [ ] Handle new `vectorized` response field
- [ ] Update enriched book model to include vectorization status
- [ ] Remove any WebSocket enrichment code paths

**Request:**
```json
{
  "barcode": "9780747532743",
  "prefer_provider": "auto",
  "idempotency_key": "scan_20260215_abc123"
}
```

**Response includes:**
```json
{
  "isbn": "9780747532743",
  "title": "...",
  "vectorized": true
}
```

---

## Dependency Graph

```
                    +-------------------+
                    | Capabilities      |
                    | Service (Week 1)  |
                    +---------+---------+
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
+-------------------+ +-------------------+ +-------------------+
| Semantic Search   | | Similar Books     | | Recommendations   |
| (Week 2)          | | (Week 2)          | | (Week 1)          |
+-------------------+ +-------------------+ +-------------------+

+-------------------+ +-------------------+
| SSE Migration     | | V2 Enrichment     |
| (Week 3)          | | (Week 1)          |
| [Independent]     | | [Independent]     |
+-------------------+ +-------------------+
```

---

## Week-by-Week Schedule

### Week 1: Foundation + Quick Wins

| Task | Feature | Complexity |
|------|---------|------------|
| APICapabilitiesService | Capabilities | S |
| V2 Enrichment Migration | Enrichment | S |
| WeeklyRecommendationsWidget | Recommendations | M |
| RecommendationsService | Recommendations | S |

**Deliverable:** Capabilities detection live, recommendations widget in InsightsView

### Week 2: Search Intelligence

| Task | Feature | Complexity |
|------|---------|------------|
| SemanticSearchService | Search | M |
| Search mode toggle UI | Search | S |
| Rate limit indicator | Search | S |
| SimilarBooksService | Similar | M |
| Similar Books UI section | Similar | S |

**Deliverable:** Semantic search toggle working, similar books in BookDetailView

### Week 3: SSE Migration (Critical Path)

| Task | Feature | Complexity |
|------|---------|------------|
| SSEClient implementation | Import | M |
| V2ImportService | Import | L |
| Polling fallback | Import | S |
| ImportProgressView update | Import | S |

**Deliverable:** CSV import fully migrated to HTTP/SSE, WebSocket removed

### Week 4: Polish + Testing

| Task | Feature | Complexity |
|------|---------|------------|
| Integration tests | All | M |
| Edge case handling | All | S |
| Performance optimization | All | S |
| Documentation update | All | S |

**Deliverable:** All features tested, sprint complete

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| SSE connection instability on cellular | Medium | HIGH | Implement robust polling fallback, test on real devices |
| Semantic search rate limit UX confusion | Low | Medium | Clear visual indicator, countdown timer |
| Vectorize 404 for books without embeddings | High | Low | Graceful degradation, hide "Similar" section |
| Recommendations not generated yet | Low | Medium | Show "Coming soon" placeholder |
| Swift 6 concurrency issues with SSE | Medium | HIGH | Use @MainActor properly, test thoroughly |

---

## Success Criteria

### P0 - Must Have
- [ ] Semantic search returns results for natural language queries
- [ ] CSV import works via SSE without WebSocket
- [ ] Capabilities endpoint gates feature visibility
- [ ] Zero new warnings (Swift 6 compliance)

### P1 - Should Have
- [ ] Similar books shows relevant results
- [ ] Recommendations widget displays weekly picks
- [ ] Rate limit indicator prevents user frustration
- [ ] Offline mode degrades gracefully

### P2 - Nice to Have
- [ ] Search mode preference persisted
- [ ] Similar books cached across sessions
- [ ] Recommendations prefetched on app launch

---

## Test Plan

### Unit Tests
- [ ] APICapabilitiesService parsing
- [ ] SemanticSearchService response mapping
- [ ] SSEClient event parsing
- [ ] Rate limit tracking logic
- [ ] RecommendationsService caching

### Integration Tests
- [ ] Full search flow (text -> semantic toggle -> results)
- [ ] CSV import with SSE (start -> progress -> complete)
- [ ] Similar books lazy loading
- [ ] Recommendations fetch and display
- [ ] Capabilities gating features

### Real Device Testing
- [ ] SSE on WiFi, cellular, and network transitions
- [ ] Rate limit enforcement (actually hit 5 req/min)
- [ ] Background/foreground during import
- [ ] Offline mode behavior

---

## Files to Create/Modify

### New Files
```
Sources/BooksTrackerFeature/
├── Services/
│   ├── APICapabilitiesService.swift
│   ├── SemanticSearchService.swift
│   ├── SimilarBooksService.swift
│   ├── RecommendationsService.swift
│   ├── V2ImportService.swift
│   └── SSEClient.swift
├── Models/
│   ├── APICapabilities.swift
│   ├── SemanticSearchResult.swift
│   ├── SimilarBook.swift
│   └── WeeklyRecommendation.swift
└── Views/
    ├── Search/
    │   ├── SearchModeToggle.swift
    │   └── RateLimitIndicator.swift
    ├── BookDetail/
    │   └── SimilarBooksSection.swift
    └── Insights/
        ├── WeeklyRecommendationsWidget.swift
        └── RecommendationCard.swift
```

### Modified Files
```
- SearchView.swift (add mode toggle, rate limit)
- BookDetailView.swift (add similar books section)
- InsightsView.swift (add recommendations widget)
- BookEnrichmentService.swift (V2 endpoint)
- ImportProgressView.swift (SSE integration)
- BooksTrackerApp.swift (capabilities on launch)
```

---

## Related Documents

- [API_CONTRACT_V2_PROPOSAL.md](../../API_CONTRACT_V2_PROPOSAL.md) - V2 API specification
- [openapi.yaml](../../openapi.yaml) - OpenAPI 3.0 specification
- [SPRINT_3_BACKEND_HANDOFF.md](../../SPRINT_3_BACKEND_HANDOFF.md) - Backend implementation details
- [SPRINT_OVERVIEW.md](SPRINT_OVERVIEW.md) - Overall sprint roadmap

---

**Document Owner:** iOS Development Team
**Last Updated:** November 25, 2025
**Status:** Ready for Implementation
