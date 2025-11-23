# Book Search - Product Requirements Document

**Feature:** Multi-Mode Book Search (Title, ISBN, Author, Advanced)
**Status:** ✅ Production (v3.0.0+)
**Last Updated:** October 31, 2025
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

**Multi-Mode Search:**
1. **Title Search:** `/v1/search/title?q={query}` - Fuzzy matching, partial titles
2. **ISBN Search:** `/v1/search/isbn?isbn={isbn}` - Exact match, barcode scanner integration
3. **Advanced Search:** `/v1/search/advanced?title={title}&author={author}` - Combined filters

**Key Features:**
- Canonical DTOs (WorkDTO, EditionDTO, AuthorDTO) from all endpoints
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

---

## Technical Implementation

### iOS Components

**Files:**
- `SearchView.swift` - Main search UI
- `SearchModel.swift` - @Observable model managing search state
- `SearchViewState.swift` - State enum (initial, searching, results, error, empty)
- `BookSearchAPIService.swift` - API client for `/v1/*` endpoints
- `DTOMapper.swift` - Converts DTOs to SwiftData models

**Search Flow:**
```swift
SearchView (UI)
  ↓ user types query
SearchModel.updateSearchQuery("Harry Potter")
  ↓ debounced 300ms
BookSearchAPIService.searchByTitle("Harry Potter")
  ↓ GET /v1/search/title?q=Harry+Potter
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

### Backend Endpoints

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

**Response Format (All Endpoints):**
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
**Implementation:** ✅ Production (v3.0.0)
**Last Review:** October 31, 2025
