# BooksTracker v2 - Sprint Planning Overview

**Planning Date:** November 20, 2025
**Last Updated:** November 25, 2025 (Consolidated V2 API + Intelligence Roadmap)
**Target Release:** Q4 2026
**Current Branch:** `main`

> **✅ Sprint 1 COMPLETE!** Shipped in PR #1 (Nov 21, 2025). See [sprint-01-REVISED.md](sprint-01-REVISED.md) for details.

---

## 3-Sprint Checkpoint: Intelligence Layer Live

**Goal:** Ship semantic search + weekly recommendations in 3 sprints

```
Sprint 2 (Current)     Sprint 3              Sprint 4
================       ================      ================
iOS Polish &           Backend Foundation    Intelligence Live
Analytics              + V2 API

- Cascade metadata     - Vectorize index     - Semantic search UI
- Session analytics    - D1 schema           - Recommendations widget
- Real device test     - Unified V2 API      - SSE client (CSV)
- Documentation        - Enrichment pipeline - End-to-end testing

Target: Dec 2025       Target: Jan 2026      Target: Feb 2026

                       🎯 CHECKPOINT: Semantic Search +
                          Weekly Recommendations LIVE
```

**Key Decision:** Ship with **global recommendations** first (non-personalized), add personalization in Phase 2 after user data sync infrastructure.

---

## Sprint Structure

Each sprint is **2 weeks** with the following structure:
- **Week 1:** Implementation & unit tests
- **Week 2:** Integration, testing, documentation

---

## Release Phases

### Phase 1: Engagement Foundation (Q1 2026) - IN PROGRESS

**Goal:** Enable diversity tracking, reading habit analytics, and AI-powered search/recommendations

**Sprint Status:**

- **✅ Sprint 1:** EnhancedDiversityStats + ReadingSession Model & Timer UI **[COMPLETE - Nov 21, 2025]**
  - ✅ `EnhancedDiversityStats` model (5-dimension tracking)
  - ✅ `ReadingSession` model with timer
  - ✅ `RepresentationRadarChart` visualization
  - ✅ Progressive profiling prompts
  - ✅ `DiversityCompletionWidget`
  - ✅ Timer UI in `EditionMetadataView`
  - ✅ 26 tests (unit + integration + performance)

- **✅ Sprint 2:** Cascade Metadata + Session Analytics **[COMPLETE - Nov 25, 2025]**
  - ✅ `DiversityCompletionWidget` integrated into InsightsView
  - ✅ `RepresentationRadarChart` integrated into InsightsView
  - ✅ Session analytics with `StreakVisualizationView`
  - ✅ All Sprint 2 views wired into app navigation
  - ✅ Build passes with zero errors

- **✅ Sprint 3:** Backend Foundation + V2 API **[COMPLETE - Nov 25, 2025]**
  - ✅ **Vectorize Infrastructure:** `book-embeddings` index (1024 dims, cosine)
  - ✅ **D1 Database:** `bookstrack-library` with 8 migrations
  - ✅ **Workers AI:** BGE-M3 binding for embeddings
  - ✅ **All V2 API Endpoints Implemented:**
    - `POST /api/v2/books/enrich` - Barcode enrichment (sync HTTP)
    - `POST /api/v2/imports` - CSV upload (async job + SSE)
    - `GET /api/v2/imports/{jobId}/stream` - SSE progress
    - `GET /api/v2/search?q=&mode=text|semantic` - Unified search
    - `GET /api/v2/recommendations/weekly` - Global recommendations
    - `GET /api/v2/capabilities` - Feature discovery
    - `GET /v1/search/similar?isbn=` - Similar books (bonus!)
  - ✅ **Enrichment Pipeline:** Queue-based async processing with auto-vectorization
  - ✅ **Cron Job:** Weekly recommendation generation (Gemini) - Sunday midnight UTC
  - ✅ **KV Cache:** `RECOMMENDATIONS_CACHE` namespace
  - **Completed:** November 25, 2025
  - **Docs:** See [SPRINT_3_BACKEND_HANDOFF.md](../../SPRINT_3_BACKEND_HANDOFF.md), [API_CONTRACT_V2_PROPOSAL.md](../../API_CONTRACT_V2_PROPOSAL.md), [openapi.yaml](../../openapi.yaml)

- **📋 Sprint 4:** Intelligence v2 - iOS Integration **[PLANNING COMPLETE]**
  - **Week 1:** Capabilities Service + Recommendations Widget + V2 Enrichment
  - **Week 2:** Semantic Search UI + Similar Books Section
  - **Week 3:** SSE Client + CSV Import Migration (Critical Path)
  - **Week 4:** Polish + Integration Testing
  - **Features:**
    - `APICapabilitiesService` - Feature detection on app launch
    - `SemanticSearchService` - Natural language queries (5 req/min)
    - `SimilarBooksService` - Vector similarity recommendations
    - `WeeklyRecommendationsWidget` - AI-generated picks in InsightsView
    - `SSEClient` - Native URLSession SSE for import progress
    - `V2ImportService` - HTTP/SSE migration (remove WebSocket)
  - **Target:** February 2026
  - **Docs:** See [SPRINT_4_IOS_INTEGRATION.md](SPRINT_4_IOS_INTEGRATION.md)

**Key Deliverables (Phase 1):**
- ✅ Representation Radar chart (diversity visualization)
- ✅ Reading session tracking with timer
- ✅ Cascade metadata (add author info once, applies to all books)
- ✅ Session analytics and streak tracking
- ✅ V2 API Backend (semantic search, recommendations, SSE) - Backend Complete
- 📋 Semantic search UI (natural language queries)
- 📋 Weekly book recommendations widget
- 📋 HTTP/SSE API migration (from WebSocket)

---

### Phase 2: Personalization Layer (Q2 2026)

**Goal:** Evolve from global to personalized recommendations

**Prerequisite:** Intelligence checkpoint complete (Sprint 4)

- **Sprint 5:** User Data Sync Infrastructure
  - Design user activity sync API (`POST /api/v2/user/activity`)
  - SwiftData → D1 sync mechanism
  - D1 user reading history tables
  - Cold start handling (fallback to global recommendations)

- **Sprint 6:** Personalized Recommendations
  - Per-user recommendation generation
  - Reading pattern recognition
  - Preference learning from history

- **Sprint 7:** Advanced Insights Dashboard
  - Reading habit analytics
  - Genre/author affinity visualization
  - Goal tracking integration

- **Sprint 8:** Performance & Optimization
  - Recommendation quality tuning
  - Latency optimization
  - A/B testing framework

**Key Deliverables:**
- User reading history sync (iOS → D1)
- Personalized weekly recommendations
- Reading pattern insights
- Advanced analytics dashboard

---

### Phase 3: Social Features (Q3 2026) ⚠️ OPTIONAL

**Goal:** Privacy-first social reading features (IF validated by broader user research)

**User Interview Insight:** ReadingCircle ranked #5 (last). User has no social interest. May pivot this phase based on research.

- **Sprint 9:** ReadingCircle Foundation (IF validated)
- **Sprint 10:** Private Sharing & Invitations (IF validated)
- **Sprint 11:** Group Challenges & Goals (IF validated)
- **Sprint 12:** Community Recommendations (IF validated)

**Alternative Plan (if social features not validated):**
- Additional polish and performance optimization
- Advanced discovery features (wishlist, want-to-read shelves)
- Content warnings and accessibility enhancements
- Community-requested features from user research

---

### Phase 4: Discovery & Polish (Q4 2026)

**Goal:** Enhanced discovery features and final polish

- **Sprint 13:** Price Tracking & Format Discovery
- **Sprint 14:** Enhanced Content Metadata (Series, Awards)
- **Sprint 15:** Accessibility Features & Content Warnings
- **Sprint 16:** Final Polish & Performance Optimization

**Key Deliverables:**
- Multi-retailer price tracking
- Comprehensive content metadata
- Accessibility improvements
- Performance optimization

---

## Current Sprint Status

### ✅ Sprint 1 Complete (Nov 21, 2025)

**Shipped Features:**
- `EnhancedDiversityStats` model (5-dimension diversity tracking)
- `ReadingSession` model with timer UI
- `RepresentationRadarChart` (Canvas-based radar chart)
- Progressive profiling prompts
- `DiversityCompletionWidget` (progress ring)
- `ReadingSessionService` (@MainActor)
- `DiversityStatsService`
- `SessionAnalyticsService`

**Testing:**
- 15 unit tests (ReadingSession, EnhancedDiversityStats)
- 11 integration tests (DiversitySessionIntegration)
- Performance tests for radar chart (<200ms P95)

**Shipped in:** PR #1 - "Sprint 2: Cascade Metadata & Session Analytics (100% Complete)"

---

### ✅ Sprint 2: Complete (iOS Polish) - November 25, 2025

**Focus:** Complete cascade metadata + session analytics

**Tasks:**
- [x] Complete diversity completion widget integration ✅
- [x] Integrate RepresentationRadarChart into InsightsView ✅
- [x] Session analytics aggregation (weekly/monthly trends) ✅
- [x] Wire all Sprint 2 views into app navigation ✅
- [ ] Real device testing (keyboard input validation) - *Deferred to Sprint 3 prep*
- [x] Documentation updates ✅

**Completed:** November 25, 2025

**What Was Delivered:**
- `DiversityCompletionWidget` integrated into InsightsView (4th tab)
- `RepresentationRadarChart` integrated into InsightsView
- `StreakVisualizationView` displaying weekly/monthly session analytics
- `EnhancedDiversityStats` loaded alongside `DiversityStats` for radar chart
- All views accessible via Insights tab in main navigation
- Build passes with zero errors

---

### ✅ Sprint 3: Backend Foundation + V2 API - COMPLETE (November 25, 2025)

**Focus:** Unified V2 API infrastructure for Intelligence features

**Completed Infrastructure:**
- [x] Cloudflare Vectorize index `book-embeddings` (1024 dims, cosine)
- [x] Workers AI binding (BGE-M3 model)
- [x] D1 database `bookstrack-library` with 8 migrations
- [x] Async enrichment pipeline (Queue → Worker)
- [x] All V2 API endpoints:
  - [x] `POST /api/v2/books/enrich`
  - [x] `POST /api/v2/imports` + SSE stream
  - [x] `GET /api/v2/search?mode=text|semantic`
  - [x] `GET /api/v2/recommendations/weekly`
  - [x] `GET /api/v2/capabilities`
  - [x] `GET /v1/search/similar?isbn=` (bonus!)
- [x] Weekly cron job (Gemini recommendations) - Sunday midnight UTC
- [x] KV namespace `RECOMMENDATIONS_CACHE`
- [x] OpenAPI spec v2.7.0

**Exit Criteria - All Met:**
- ✅ All V2 endpoints deployed and live
- ✅ Semantic search returns relevant results
- ✅ Weekly recommendations cron configured
- ✅ API contract documented (openapi.yaml v2.7.0)

**Docs:** [SPRINT_3_BACKEND_HANDOFF.md](../../SPRINT_3_BACKEND_HANDOFF.md), [API_CONTRACT_V2_PROPOSAL.md](../../API_CONTRACT_V2_PROPOSAL.md), [openapi.yaml](../../openapi.yaml)

---

### 📋 Sprint 4: Intelligence Live (February 2026) - PLANNING COMPLETE

**Focus:** iOS integration + feature launch

**Week-by-Week Plan:**
- **Week 1:** Foundation + Quick Wins
  - [ ] `APICapabilitiesService` (feature detection)
  - [ ] V2 Enrichment migration
  - [ ] `WeeklyRecommendationsWidget` + service
- **Week 2:** Search Intelligence
  - [ ] `SemanticSearchService` (5 req/min rate limit)
  - [ ] Search mode toggle UI
  - [ ] `SimilarBooksService` + UI section
- **Week 3:** SSE Migration (Critical Path)
  - [ ] `SSEClient` (native URLSession)
  - [ ] `V2ImportService` (replace WebSocket)
  - [ ] Polling fallback
- **Week 4:** Polish + Testing
  - [ ] Integration tests
  - [ ] Edge case handling
  - [ ] Documentation

**Exit Criteria:**
- Semantic search live in App Store build
- Weekly recommendations visible to users
- CSV import uses SSE (WebSocket deprecated)
- P95 latency < 800ms for semantic search

**Risk:** SSE stability on mobile networks (mitigated by polling fallback)

**Docs:** [SPRINT_4_IOS_INTEGRATION.md](SPRINT_4_IOS_INTEGRATION.md)

---

## Sprint Documentation

Detailed sprint planning documents:

- ✅ [`sprint-01-REVISED.md`](sprint-01-REVISED.md) - Diversity Stats + Reading Sessions (COMPLETE)
- ✅ Sprint 2 - Cascade Metadata + Session Analytics (COMPLETE)
- ✅ [`SPRINT_3_BACKEND_HANDOFF.md`](../../SPRINT_3_BACKEND_HANDOFF.md) - Backend Foundation + V2 API (COMPLETE)
- 📋 [`SPRINT_4_IOS_INTEGRATION.md`](SPRINT_4_IOS_INTEGRATION.md) - iOS Intelligence Integration (PLANNING COMPLETE)

---

## Technical Design Docs

Detailed technical specifications by feature area:

- ✅ [`technical-design/reading-sessions.md`](../technical-design/reading-sessions.md) - ReadingSession architecture
- ✅ [`technical-design/cascade-metadata.md`](../technical-design/cascade-metadata.md) - Cascade metadata system
- ✅ [`technical-design/ratings-system.md`](../technical-design/ratings-system.md) - Ratings architecture
- 📋 [`../DATA_MODEL_SOUNDNESS.md`](../DATA_MODEL_SOUNDNESS.md) - Data model validation
- 📋 [`../DATA_STRUCTURE_ANALYSIS.md`](../DATA_STRUCTURE_ANALYSIS.md) - Structure analysis

---

## Success Metrics

### Phase 1 (Engagement Foundation)

**Sprint 1:**
- ✅ Users can track reading sessions with timer
- ✅ `EnhancedDiversityStats` model tracks 5 dimensions
- ✅ Radar chart visualizes diversity data
- ✅ Progressive profiling prompts post-session
- ✅ Zero warnings build (`-Werror` enforced)

**Sprint 2 (In Progress):**
- 🏃 Session analytics show weekly/monthly trends
- 🏃 Streak tracking shows daily patterns
- 🏃 Diversity completion widget functional
- 🏃 Real device testing validated

**Sprint 3-4 (Planned):**
- 📋 API orchestration layer operational
- 📋 Enhanced diversity analytics with ML insights
- 📋 Personalized recommendations functional

---

### Phase 2 (Intelligence Layer)
- [ ] Local AI provides personalized recommendations
- [ ] Pattern recognition identifies reading habits
- [ ] Insights dashboard shows actionable data
- [ ] Zero user data sent to cloud

---

### Phase 3 (Social Features)
- [ ] Users can create private reading circles (if validated)
- [ ] Secure sharing with E2E encryption (if validated)
- [ ] Group challenges track collective progress (if validated)
- [ ] Anonymous community insights available (if validated)

---

### Phase 4 (Discovery & Polish)
- [ ] Price tracking across multiple retailers
- [ ] Series and awards data integrated
- [ ] Content warnings and accessibility info available
- [ ] App performance optimized for large libraries

---

## Next Actions

### Immediate (Sprint 2 - December 2025)
1. **Complete iOS Polish**
   - Finalize diversity completion widget
   - Session analytics aggregation (weekly/monthly)
   - Real device keyboard testing

2. **Documentation Sync**
   - Update PRDs to reflect Sprint 1 completion
   - Verify architecture docs match codebase
   - Finalize V2 API contract (merge proposal)

### Sprint 3 Preparation (Late December)
1. **Backend Infrastructure Planning**
   - Finalize D1 schema (books, enrichment)
   - Vectorize index configuration
   - Unified V2 API endpoint design

2. **API Contract Finalization**
   - Merge V2 Proposal into API_CONTRACT.md
   - Define SSE event schema
   - Document rate limits for AI endpoints

### Sprint 4 Preparation (Late January)
1. **iOS Architecture**
   - Design SSEClient actor (Swift 6 concurrency)
   - Plan SearchView enhancements for semantic search
   - Recommendations widget mockups

---

## Critical Decisions Made

### Decision 1: Global Recommendations First
**Context:** Personalized recommendations require user data sync infrastructure (reading history from iOS to D1).

**Decision:** Ship with global, non-personalized recommendations in Sprint 4. Add personalization in Phase 2 (Sprint 5+).

**Rationale:** De-risks the project by decoupling immediate goal (shipping UI + AI infra) from the harder problem of data synchronization.

### Decision 2: Unified `/api/v2/*` Namespace
**Context:** V2 Proposal used `/api/v2/*` while Sprint 4 used `/v2/*`.

**Decision:** Standardize on `/api/v2/*` for all new endpoints.

**Endpoints:**
- `POST /api/v2/books/enrich`
- `POST /api/v2/imports`
- `GET /api/v2/search?mode=text|semantic`
- `GET /api/v2/recommendations/weekly`
- `GET /api/v2/capabilities`

### Decision 3: Proactive Enrichment Pipeline
**Context:** V2 Proposal had on-demand enrichment via GET request.

**Decision:** Implement proactive, async enrichment pipeline:
1. `POST /api/v2/imports` accepts raw book data
2. Queue job for background processing
3. Worker enriches + generates embeddings + inserts to Vectorize
4. Search/recommendations query pre-processed data

**Rationale:** Clients shouldn't trigger long-running processes via GET. Pre-processed data makes search/recommendations simpler and faster.

---

## Revision History

| Date | Change | Author |
|------|--------|--------|
| Nov 25, 2025 | **Sprint 4 Planning Complete**: Created SPRINT_4_IOS_INTEGRATION.md with 4-week implementation plan | Claude |
| Nov 25, 2025 | **Sprint 3 Complete**: Backend team delivered V2 API + openapi.yaml v2.7.0 | Backend Team |
| Nov 25, 2025 | **Sprint 2 Complete**: Integrated DiversityCompletionWidget + RepresentationRadarChart into InsightsView | Claude |
| Nov 25, 2025 | Consolidated V2 API Proposal + Sprint 4 into unified 3-sprint roadmap | Claude |
| Nov 23, 2025 | Updated with Sprint 1 completion, Sprint 2 in progress | oooe |
| Nov 20, 2025 | Revised Sprint 1 based on user interview (diversity priority) | oooe |
| Nov 20, 2025 | Initial v2 sprint planning | oooe |

---

**Last Updated:** November 25, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Sprint 2 ✅ | Sprint 3 ✅ | Sprint 4 Planning Complete 📋
**Next Checkpoint:** Intelligence Layer Live (Sprint 4, February 2026)
**Current Version:** v3.7.5 (Build 189)
