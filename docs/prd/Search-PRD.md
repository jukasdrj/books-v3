# Book Search - Product Requirements Document

**Feature:** Multi-Mode Book Search (Title, ISBN, Author, Advanced)
**Status:** ✅ Production (v3.0.0+)
**Last Updated:** November 24, 2025
**Owner:** iOS & Backend Engineering
**Related Docs:**
- Workflow: [Search Workflow](../workflows/search-workflow.md)
- Parent: [Canonical Data Contracts PRD](Canonical-Data-Contracts-PRD.md)
- Barcode Scanner: [VisionKit Barcode Scanner PRD](VisionKit-Barcode-Scanner-PRD.md)

---

## Problem Statement

**Core Pain Point:**
Users need to find books quickly to add to their library, but don't always know the exact title or have the book physically present. Different search modes (title, author, ISBN) serve different user contexts.

**User Contexts:**
1. **Browsing bookstore:** Scan ISBN barcode (fastest, 3s scan-to-results)
2. **Remembering book name:** Search by title (partial match, fuzzy search)
3. **Exploring author:** Search by author name (discover all works)
4. **Specific edition:** Search by title + author (filter results)

**Why Now:**
- VisionKit barcode scanner launched (ISBN search critical)
- Canonical data contracts deployed (consistent search results)
- Multiple entry points (SearchView, enrichment, CSV import, bookshelf scanner)

---

## Solution Overview

**V1 Search (Legacy & Barcode):**
1. **Title Search:** `/v1/search/title?q={query}` - Fuzzy matching, partial titles
2. **ISBN Search:** `/v1/search/isbn?isbn={isbn}` - Exact match, barcode scanner integration
3. **Advanced Search:** `/v1/search/advanced?title={title}&author={author}` - Combined filters

**V2 Search & Discovery (Intelligence Layer):**
1. **Unified Search:** `GET /api/v2/search` with `mode=text` (replaces V1 title/advanced) and `mode=semantic` for conceptual search.
2. **Weekly Recommendations:** `GET /api/v2/recommendations/weekly` for AI-curated picks.
3. **Similar Books:** `GET /v1/search/similar?isbn={isbn}` to find related works.

**Key Features:**
- Canonical DTOs (WorkDTO, EditionDTO, AuthorDTO) from all V1 endpoints
- DTOMapper converts to SwiftData models (zero provider-specific logic)
- 6-hour cache for title/advanced, 7-day cache for ISBN
- Genre normalization built-in (backend)

---

## User Stories

**US-1: Quick Title Search**
As a user, I want to search "Harry Potter" and see all matching books, so I can find the specific title I'm looking for.
- **AC:** Type "harry" (lowercase, partial) → Results include "Harry Potter and the Philosopher's Stone"
- **Implementation:** `/v1/search/title?q=harry`, fuzzy matching on backend

**US-2: ISBN Barcode Scan**
As a user in a bookstore, I want to scan a barcode and see the book details in <3s, so I can quickly add it to my wishlist.
- **AC:** Scan ISBN → VisionKit scanner → `/v1/search/isbn` → Book details in 1-3s
- **Implementation:** ISBNScannerView integration, 7-day KV cache

**US-3: Author Discovery**
As a user, I want to search "George Orwell" and see all his books, so I can explore his other works.
- **AC:** Search "George Orwell" (author scope) → Results include "1984", "Animal Farm", etc.
- **Implementation:** `/v1/search/advanced?author=George+Orwell`

**US-4: Advanced Filtering**
As a user, I want to search "1984" (title) by "Orwell" (author) to avoid seeing other books titled "1984".
- **AC:** Advanced search: title="1984", author="Orwell" → Only Orwell's "1984"
- **Implementation:** `/v1/search/advanced?title=1984&author=Orwell`

**US-5: Error Recovery**
As a user with poor network, I want clear error messages when search fails, so I know whether to retry or switch to manual entry.
- **AC:** Network timeout → Show "Search failed. Please try again." with retry button
- **Implementation:** ResponseEnvelope error handling, user-friendly messages

**US-6: AI-Powered Semantic Search**
As a user, I want to search for "books about dystopian futures with a strong female lead" and get relevant results like "The Hunger Games", so I can find books based on themes and concepts, not just keywords.
- **AC:** Search "dystopian futures" → Results include "1984", "Brave New World", "The Handmaid's Tale".
- **Implementation:** `GET /api/v2/search?q=...&mode=semantic`

**US-7: Weekly Recommendations**
As a user looking for something new, I want to see a curated list of weekly recommendations on the search screen, so I can discover books I might not find otherwise.
- **AC:** Open Search tab → See "Weekly Picks" section with 3-5 recommended books.
- **Implementation:** `GET /api/v2/recommendations/weekly`

**US-8: Finding Similar Books**
As a user who just finished a book I loved, I want to find similar books from the book details page, so I can explore other works I might enjoy.
- **AC:** View details for "Dune" → See "Similar Books" section with titles like "Hyperion" and "Foundation".
- **Implementation:** `GET /v1/search/similar?isbn={isbn}`

---

## Technical Implementation

### iOS Components

**Files:**
- `SearchView.swift` - Main search UI
- `SearchModel.swift` - @Observable model managing search state
- `SearchViewState.swift` - State enum (initial, searching, results, error, empty)
- `BookSearchAPIService.swift` - API client for `/v1/*` and `/v2/*` endpoints
- `DTOMapper.swift` - Converts DTOs to SwiftData models

**Search Flow:**
```swift
SearchView (UI)
  ↓ user types query
SearchModel.updateSearchQuery("Harry Potter")
  ↓ debounced 300ms
BookSearchAPIService.searchByTitle("Harry Potter")
  ↓ GET /v1/search/title?q=Harry+Potter or /api/v2/search?q=...
ResponseEnvelope<WorkDTO[], EditionDTO[], AuthorDTO[]>
  ↓ parse JSON
DTOMapper.mapToWorks(data, modelContext)
  ↓ convert to SwiftData
[Work] array
  ↓ update state
SearchViewState.results(query, scope, items, provider, cached)
  ↓ render
SearchView displays results
```

### Backend Endpoints (V1)

**1. Title Search:**
```
GET /v1/search/title?q={query}
```
- Fuzzy matching (partial titles, case-insensitive)
- Cache: 6 hours (KV)
- Returns: Canonical WorkDTO[], EditionDTO[], AuthorDTO[]

**2. ISBN Search:**
```
GET /v1/search/isbn?isbn={isbn}
```
- Exact match (ISBN-10 or ISBN-13)
- Validation: Checksum, format
- Cache: 7 days (KV)
- Returns: Canonical DTOs

**3. Advanced Search:**
```
GET /v1/search/advanced?title={title}&author={author}
```
- Combined filters (both optional, but at least one required)
- Cache: 6 hours (KV)
- Returns: Canonical DTOs

**Response Format (All V1 Endpoints):**
```json
{
  "success": true,
  "data": {
    "works": [
      {
        "title": "Harry Potter and the Philosopher's Stone",
        "subjectTags": ["Fiction", "Fantasy", "Young Adult"],
        "synthetic": true,
        "primaryProvider": "google-books"
      }
    ],
    "editions": [...],
    "authors": [...]
  },
  "meta": {
    "timestamp": "2025-10-31T12:00:00Z",
    "processingTime": 450,
    "provider": "google-books",
    "cached": false
  }
}
```

### V2 Endpoints (Intelligence Layer)

**1. Unified Search:**
```
GET /api/v2/search?q={query}&mode={text|semantic}
```
- **mode=text:** Replaces `/v1/search/title` and `/v1/search/advanced`.
- **mode=semantic:** AI-powered conceptual search using vector embeddings.
- **Rate Limit:** 5 req/min for semantic search.
- **Returns:** Simplified search results DTO.

**2. Weekly Recommendations:**
```
GET /api/v2/recommendations/weekly
```
- Returns a pre-generated, cached list of AI-curated book recommendations.
- **Returns:** List of recommendation DTOs with a "reason" for each pick.

**3. Similar Books:**
```
GET /v1/search/similar?isbn={isbn}
```
- Finds books similar to a given ISBN using vector embeddings.
- **Returns:** List of similar book DTOs with a similarity score.

### Integration Points

**VisionKit Barcode Scanner:**
```swift
.sheet(isPresented: $showingScanner) {
    ISBNScannerView { isbn in
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
    }
}
```

**SearchView Scopes:**
- `.title` - Default scope, searches `/v1/search/title`
- `.isbn` - Triggered by barcode scanner, searches `/v1/search/isbn`
- `.author` - User-selected scope, searches `/v1/search/advanced?author={query}`

---

## Success Metrics

**Performance:**
- ✅ **Title search <2s** (avg 800ms uncached, <50ms cached)
- ✅ **ISBN search <3s** (scan + API, avg 1.3s total)
- ✅ **Semantic Search <800ms** P95
- ✅ **95% cache hit rate** (7-day ISBN, 6-hour title)

**Reliability:**
- ✅ **Zero crashes from malformed ISBNs** (backend validation)
- ✅ **100% error handling** (network failures, empty results, invalid queries)
- ✅ **Structured error codes** (INVALID_QUERY, INVALID_ISBN, PROVIDER_ERROR)

**User Experience:**
- ✅ **Smart Debounce** (Dynamic 0.1s-0.8s delay based on query type)
- ✅ **Trending books on empty state** (engaging landing page)
- ✅ **Recent searches** (quick re-search, persisted)
- ✅ **Genre normalization** (consistent tags: "Fiction" not "fiction")

---

## Decision Log

### [October 29, 2025] Decision: Migrate to `/v1/*` Endpoints

**Context:** Legacy endpoints (`/search/title`, `/search/isbn`) returned provider-specific responses.

**Decision:** Migrate all iOS search to `/v1/*` endpoints with canonical DTOs.

**Rationale:**
1. Consistent response structure (WorkDTO, EditionDTO, AuthorDTO)
2. Genre normalization built-in (backend)
3. Provenance tracking (primaryProvider, contributors)
4. Zero iOS provider-specific logic

**Outcome:** ✅ Implemented October 29, 2025

---

### [October 30, 2025] Decision: VisionKit Integration for ISBN

**Context:** ISBN search needed physical barcode scanning.

**Decision:** Integrate VisionKit ISBNScannerView in SearchView.

**Rationale:**
1. Zero custom camera code (200+ lines eliminated)
2. Built-in tap-to-scan, pinch-to-zoom, guidance
3. iOS 26 HIG compliant

**Outcome:** ✅ Shipped v3.0.0, 90%+ device coverage

---

### [October 2025] Decision: Smart Debounce Strategy

**Context:** Fixed 300ms debounce was too slow for ISBNs and too fast for short queries.

**Decision:** Implement dynamic debounce delay.
- ISBN patterns: 0.1s (immediate)
- Short queries (1-3 chars): 0.8s (wait for more input)
- Medium queries (4-6 chars): 0.5s
- Long queries (>6 chars): 0.3s

**Rationale:**
1. Optimizes API usage by waiting longer for short, ambiguous queries
2. Provides instant feedback for ISBN pastes/scans
3. Feels more responsive for specific long queries

**Outcome:** ✅ Implemented in `SearchModel.swift`

---

### [November 24, 2025] Decision: Comprehensive UX Improvements for 2025 iOS Best Practices

**Context:** Search experience didn't align with modern iOS patterns (App Store, Apple Music, Spotify). Deep analysis by Gemini 2.5 Pro identified performance and visual design gaps.

**Decision:** Implement Phase 1 (Performance) and Phase 2 (Visual Redesign) improvements.

**Phase 1 - Performance & Scannability:**
1. **Faster Debounce Timing** (Issue #19)
   - Reduced delays: 0.8s→0.3s, 0.5s→0.2s, 0.3s→0.15s
   - 2.5x faster response time (aligns with industry 100-300ms best practice)

2. **Bold Text in Suggestions** (Issue #17)
   - Added `highlightedSuggestion()` helper using AttributedString
   - Matching text now bolded (e.g., "Step**hen King**")
   - Improved scannability and reduced cognitive load

**Phase 2 - Visual Redesign:**
1. **Trending Search Chips** (Issue #16)
   - Replaced trending books grid with trending search query chips
   - Pill-shaped buttons with `.ultraThinMaterial` background
   - Matches App Store/Music/Spotify patterns
   - 8 trending queries in adaptive grid

2. **Simplified Initial State** (Issue #18)
   - Removed Quick Tips section (reduced cognitive overload)
   - Streamlined from 4 sections to 3: Welcome → Trending Searches → Recent
   - Cleaner visual hierarchy

**Additional Fix:**
- **Cover Image Prefetching** (Issue #14)
  - Fixed prefetching to work during normal scrolling
  - Removed throttling guard that prevented prefetch

**Rationale:**
1. Industry best practices show 100-300ms optimal debounce for mobile
2. Bold matching text standard in modern search UIs (improves scannability)
3. Trending chips reduce friction vs. full book previews
4. Simplified initial state reduces cognitive load by 25%

**Impact:**
- 4 files changed, 66 insertions(+), 94 deletions(-)
- Net -28 lines (simpler, more maintainable)
- Search 2.5x more responsive
- Visual design matches 2025 iOS standards

**Outcome:** ✅ Shipped in commit `24a3bed` (November 24, 2025)

**Files Modified:**
- `SearchModel.swift:191-209` - Faster debounce timing
- `SearchView.swift:269-291` - Bold suggestion helper
- `SearchView+InitialState.swift:111-146` - Trending chips
- `SearchView+Results.swift:178-193` - Prefetch fix

**Closes:** Issues #14, #16, #17, #18, #19

---

## Future Enhancements

### High Priority (Next 3 Months)

**1. Search History Persistence**
- ✅ **Done:** Stored in UserDefaults, last 10 searches
- **Enhancement:** Sync across devices via CloudKit
- Estimated effort: 2 days

**2. Autocomplete Suggestions**
- ✅ **Partial:** Local suggestions for "King", "Weir", etc.
- **Full:** Backend endpoint `/v1/search/autocomplete?q={prefix}`
- Estimated effort: 3-4 days (backend integration)

**3. Filters (Genre, Year, Language)**
- Filter results by genre, publication year, language
- UI: Filter chips below search bar
- Estimated effort: 2-3 days

### Medium Priority (6 Months)

**4. Multi-ISBN Batch Search**
- Search 5+ ISBNs at once (bookshelf scanner use case)
- POST `/v1/search/isbn/batch` with `{ isbns: [...] }`
- Estimated effort: 2 days

**5. Author Disambiguation**
- "George Orwell" → Suggest "Eric Arthur Blair (George Orwell)"
- Handle pen names, multiple authors with same name
- Estimated effort: 5-7 days

---

## Testing & Validation

### Manual Test Scenarios

**Scenario 1: Title Search (Happy Path)**
1. Open SearchView, type "Harry Potter"
2. Verify: Results appear <2s, include all Harry Potter books
3. Tap first result → Navigate to WorkDetailView
4. Verify: Genres normalized ("Fiction", "Fantasy", "Young Adult")

**Scenario 2: ISBN Barcode Scan**
1. Tap "Scan ISBN" button
2. Scan barcode (EAN-13)
3. Verify: Scanner dismisses, book details appear <3s
4. Verify: Correct book metadata (title, author, cover)

**Scenario 3: Advanced Search**
1. Type "1984" (title), select "Author" scope
2. Type "Orwell" (author)
3. Verify: Only Orwell's "1984" in results (no other books)

**Scenario 4: Empty Results**
1. Search "asdfghjkl" (nonsense query)
2. Verify: "No results found" message
3. Verify: Trending books still shown

**Scenario 5: Network Error**
1. Enable Airplane Mode
2. Search "Harry Potter"
3. Verify: "Search failed. Please try again." with retry button
4. Disable Airplane Mode, tap retry
5. Verify: Results appear

---

## Related Features

**Upstream Dependencies:**
- Canonical Data Contracts (WorkDTO, EditionDTO, AuthorDTO)
- Genre Normalization (backend service)
- VisionKit Barcode Scanner (ISBN search)

**Downstream Dependents:**
- Enrichment Pipeline (uses `/v1/search/isbn`)
- Bookshelf Scanner (uses `/v1/search/isbn` after AI detection)
- CSV Import (uses `/v1/search/title` for metadata lookup)

---

**PRD Status:** ✅ Complete
**Implementation:** ✅ Production (v3.0.0+)
**Last Review:** November 24, 2025
