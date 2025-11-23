# Search & Enrichment Pipeline – Product Requirements Document

## Executive Summary
The Search feature enables users to locate books quickly via title, ISBN, author, or advanced combined queries. The Enrichment Pipeline enriches imported or scanned books with metadata (covers, author details, genre normalization) using backend services. Combining these documents clarifies their interdependency: search results feed the enrichment pipeline, and enrichment results improve future search relevance.

## Problem Statement
- **User Pain**: Users struggle to find books without exact titles or ISBNs, and imported data often lacks complete metadata, leading to poor search relevance.
- **Developer Pain**: Maintaining separate docs for Search and Enrichment leads to duplicated information about shared components (DTOs, caching, backend endpoints).

## Target Users
| Persona | Use Cases |
|---------|-----------|
| End User | Search by title/ISBN, scan barcode, view enriched book details. |
| Developer | Test CSV import, ensure enrichment runs correctly, validate search integration. |
| Beta Tester | Verify new search filters and enrichment accuracy. |

## User Stories & Acceptance Criteria
### Search
- **US-1 Title Search**: Type partial title, see fuzzy matches within <2 s.
- **US-2 ISBN Scan**: Scan barcode, get book details in <3 s.
- **US-3 Author Discovery**: Search author name, see all works.
- **US-4 Advanced Filtering**: Combine title & author to narrow results.
- **US-5 Error Recovery**: Show friendly error on network failure.

### Enrichment Pipeline
- **UE-1 Auto‑Enrich on Import**: When CSV import adds a new work, backend fetches cover, author bios, genre tags.
- **UE-2 Real‑time Enrichment**: After scanning a barcode, enrichment runs asynchronously and updates UI when complete.
- **UE-3 Failure Handling**: If enrichment fails, show placeholder and allow retry.
- **UE-4 Idempotent Processing**: Re‑importing the same ISBN does not duplicate enrichment jobs.

## Success Metrics
| Metric | Target |
|--------|--------|
| Search Latency | Title <2 s, ISBN <3 s |
| Enrichment Completion | 90% of jobs finish <5 s |
| Cache Hit Rate | 95% for title & ISBN queries |
| Error Rate | <1% user‑visible failures |

## Technical Implementation
### Shared Architecture
- **Canonical DTOs**: `WorkDTO`, `EditionDTO`, `AuthorDTO` used by both Search and Enrichment endpoints.
- **DTOMapper** converts DTOs to SwiftData models on iOS.
- **KV Caching**: Title cache 6 h, ISBN cache 7 d, enrichment results cached 24 h.
- **Genre Normalization** performed server‑side, stored in `GenreNormalizationService`.

### Search Endpoints
- `GET /v1/search/title?q={query}` – fuzzy, 6 h cache.
- `GET /v1/search/isbn?isbn={isbn}` – exact, 7 d cache.
- `GET /v1/search/advanced?title={title}&author={author}` – combined filters, 6 h cache.

### Enrichment Pipeline Flow
```
1. CSV Import / Barcode Scan creates a `Work` placeholder (minimal fields).
2. iOS calls `POST /v1/enrich/work` with ISBN or partial metadata.
3. Backend fetches external sources (Google Books, Open Library).
4. Applies genre normalization, cover image selection, author bio lookup.
5. Stores enriched DTOs in cache and returns to client.
6. iOS `EnrichmentQueue` updates SwiftData models and UI.
```
- **Endpoints**: `POST /v1/enrich/work`, `GET /v1/enrich/status/{jobId}`.
- **Job Tracking**: `EnrichmentQueue` assigns a UUID, stores status in Durable Object, supports cancellation (used by Library Reset).

## UI Specification
### Search View (SwiftUI)
- Search bar with dynamic debounce (0.1 s for ISBN, up to 0.8 s for short queries).
- Scope selector (Title, ISBN, Author, Advanced).
- Results list showing cover, title, author, genre tags.
- Empty state shows trending books.

### Enrichment Indicators
- Placeholder cards show spinner until enrichment completes.
- Toast on success: "Metadata enriched".
- Retry button on failure.

## Testing & Validation
### Manual QA
- Title, ISBN, author, advanced searches across edge cases.
- CSV import of 100 books triggers enrichment, verify all metadata populated.
- Simulate network loss during enrichment, ensure retry flow.
- Verify cache hit behavior by repeating same ISBN search.

### Automated Tests (XCTest)
- Unit tests for `BookSearchAPIService` response parsing.
- Integration tests for `EnrichmentQueue` job lifecycle.
- Mock backend responses for success/failure scenarios.

## Future Enhancements
- **Search History Sync** via CloudKit.
- **Autocomplete Endpoint** `/v1/search/autocomplete`.
- **Filter UI** (genre, year, language).
- **Batch ISBN Enrichment** for bookshelf scanner.
- **User‑controlled Enrichment Settings** (opt‑out of auto‑enrich).

## Dependencies
- SwiftUI, SwiftData, UserDefaults (search prefs).
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift`
- Backend `/v1/*` endpoints, KV cache, Durable Objects.

## Success Criteria (Shipped)
- ✅ Search latency targets met.
- ✅ Enrichment jobs complete within 5 s for 90% of cases.
- ✅ Cache hit rates >95%.
- ✅ No unhandled errors in UI.
- ✅ Documentation reflects combined flow.

---
*Documentation generated on 2025‑11‑19.*
