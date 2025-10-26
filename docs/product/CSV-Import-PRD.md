# CSV Import & Enrichment - Product Requirements Document

**Status:** ✅ Shipped (Build 45+)
**Owner:** Product Team
**Engineering Lead:** iOS Development Team
**Design Lead:** iOS 26 HIG Compliance
**Target Release:** Build 45 (October 2025)
**Last Updated:** October 25, 2025

---

## Executive Summary

The CSV Import feature allows users to bulk import their existing book libraries from Goodreads, LibraryThing, or StoryGraph exports. This eliminates the tedious manual entry process for users with 100-1500+ books, reducing onboarding time from 5+ hours to under 15 minutes and enabling immediate access to BooksTrack's reading insights and cultural diversity analytics.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Users migrating from existing book tracking platforms (Goodreads, LibraryThing, StoryGraph) or creating their first digital library face hours of manual data entry. For a typical collection of 500 books, manual search-and-add takes 8-16 hours (1-2 minutes per book), creating massive onboarding friction and preventing users from experiencing BooksTrack's core value proposition.

**Impact:**
- **Abandonment Rate:** 70%+ of users with existing digital libraries never complete migration
- **Time Investment:** 500 books × 2 min/book = 16+ hours of tedious data entry
- **Competitor Lock-in:** Users stay with inferior platforms due to switching cost
- **Data Quality:** Manual entry prone to errors, missing metadata

### Current Experience

**How do users currently solve this problem?**

1. **Manual Search (Current App Before Build 45):** Search each book → tap result → add to library. Unsustainable for 100+ books.
2. **Start Over:** Abandon existing library data and manually add new books as read. Lose historical reading data.
3. **Don't Migrate:** Continue using Goodreads despite wanting BooksTrack features (cultural diversity insights, better UI).
4. **Third-Party Tools:** No automated CSV import existed; users requested this feature in 40+ App Store reviews.

**User Quote (Beta Feedback):**
> "I have 1200 books in Goodreads but only 5 in BooksTrack. I want to switch but can't justify 20 hours of manual work."

---

## Target Users

### Primary Persona: **The Platform Migrator**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Existing Goodreads/LibraryThing users with 100-1500+ books |
| **Usage Frequency** | One-time bulk import, then ongoing individual additions |
| **Tech Savvy** | Medium (knows how to export CSV from platforms) |
| **Primary Goal** | Migrate entire reading history without manual re-entry |

**Example User Story:**

> "As a **Goodreads user with 800 books tracked over 10 years**, I want to **import my entire library via CSV export** so that I can **switch to BooksTrack and access cultural diversity insights on my historical reading without losing my data**."

### Secondary Persona: **The Spreadsheet Organizer**

Users who maintain personal book inventories in Excel/Google Sheets and want digital tracking with analytics.

---

## Success Metrics

### Key Performance Indicators (KPIs)

| Metric | Target | Current | Measurement Method |
|--------|--------|---------|-------------------|
| **Adoption Rate** | 50% of users with 50+ books use CSV import | TBD | Analytics event: `csv_import_completed` |
| **Processing Speed** | 100 books/min import rate | ~100 books/min | Server-side timing instrumentation |
| **Memory Efficiency** | <200MB peak for 1500 books | <200MB | iOS Instruments profiling |
| **Duplicate Detection Accuracy** | 95%+ duplicate prevention | 95%+ | Manual QA + user feedback |
| **Enrichment Success Rate** | 85%+ metadata enrichment | 90%+ | Backend success tracking |
| **Completion Rate** | 80%+ users complete import workflow | TBD | Funnel analytics |

**Success Criteria for GA:**
- 50%+ of new users with existing libraries use CSV import within first 24 hours
- 100 books imported in <60 seconds
- 90%+ enrichment success rate with title normalization
- Zero crashes on 1500+ book imports

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Import CSV from Goodreads/LibraryThing/StoryGraph

**As a** user with an existing digital library
**I want to** select my CSV export file and have BooksTrack auto-detect the format
**So that** I don't have to manually map columns or re-enter hundreds of books

**Acceptance Criteria:**
- [x] Given valid Goodreads CSV, when user selects file, then app auto-detects "Title", "Author", "ISBN", "My Rating", "Exclusive Shelf" columns
- [x] Given valid LibraryThing CSV, when user selects file, then app auto-detects "TITLE", "AUTHOR (first, last)", "ISBN", "RATING" columns
- [x] Given valid StoryGraph CSV, when user selects file, then app auto-detects "Title", "Authors", "ISBN/UID", "Star Rating", "Read Status" columns
- [x] Given unknown CSV format, when auto-detection fails, then app shows manual column mapping UI
- [x] Edge case: Given malformed CSV (missing headers), when parsed, system shows clear error message with format requirements

#### User Story 2: Handle Duplicate Books Intelligently

**As a** user importing CSV with books already in my library
**I want to** choose how duplicates are handled (skip, update, or smart merge)
**So that** I don't create duplicate entries or lose existing data

**Acceptance Criteria:**
- [x] Given duplicate strategy = "Smart", when exact title+author match found, then merge metadata (keep richer dataset)
- [x] Given duplicate strategy = "Skip", when duplicate detected, then skip new book and increment `duplicates` counter
- [x] Given duplicate strategy = "Replace All", when duplicate found, then delete old entry and insert new
- [x] Given books with ISBN match, when title differs slightly, then treat as duplicate (prefer ISBN matching)
- [x] Edge case: Given CSV has internal duplicates, when imported, system deduplicates before SwiftData insertion

#### User Story 3: Automatic Background Metadata Enrichment

**As a** user who imported bare-bones CSV data (just titles/authors)
**I want to** have book covers, ISBNs, and metadata automatically fetched in the background
**So that** my library looks complete without manual work

**Acceptance Criteria:**
- [x] Given 500 books imported from CSV, when import completes, then all works queued for enrichment via `EnrichmentQueue.shared`
- [x] Given enrichment in progress, when processing, then EnrichmentProgressBanner shows real-time progress ("15/500 books enriched")
- [x] Given network unavailable, when enrichment attempted, then jobs queued for retry when connectivity restored
- [x] Given title with series markers "(Series, #1)", when enrichment API called, then normalized title used for better matching
- [x] Edge case: Given API returns multiple candidates, when confidence low, system stores candidates for manual selection

### Should-Have (P1) - Enhanced Experience

#### User Story 4: Import Progress Visibility

**As a** user importing 1000+ books
**I want to** see real-time progress updates
**So that** I know the system is working and can estimate completion time

**Acceptance Criteria:**
- [x] Given large import (500+ books), when processing, then progress shown as "Imported 250/500 books (50%)"
- [x] Given batch processing, when SwiftData save completes, then progress updates immediately (not just at end)
- [x] Given import complete, when summary shown, then displays: imported count, duplicates skipped, errors encountered

---

## Functional Requirements

### High-Level Flow

**End-to-end user journey:**

See `docs/workflows/csv-import-workflow.md` for detailed Mermaid diagrams including:
- User journey flowchart (file picker → validation → preview → import)
- Title normalization before/after comparison
- Duplicate detection algorithm (3-tier matching)
- Background enrichment state machine
- Memory management (batch processing)

**Quick Summary:**
```
Settings → Import CSV → File Picker → Auto-Detect Format → Preview (first 3 books)
    ↓
Choose Duplicate Strategy (Smart / Skip / Replace)
    ↓
Start Import → Batch Processing (50 rows/batch) → SwiftData insertion
    ↓
Queue Enrichment → Background API calls → EnrichmentProgressBanner
    ↓
Import Complete (show summary: imported, duplicates, failed)
```

---

### Feature Specifications

#### 1. CSV Parsing (CSVParsingActor)

**Description:** High-performance streaming CSV parser with auto-format detection

**Technical Requirements:**
- **Input:** CSV file from UIDocumentPickerViewController
- **Processing:**
  - `CSVParsingActor` (@globalActor) isolates parsing from MainActor
  - Streaming parser processes 50 rows at a time (memory efficiency)
  - Auto-detect column mappings for Goodreads/LibraryThing/StoryGraph
  - Title normalization: strip series markers, subtitles, edition markers
- **Output:** `[ParsedRow]` array with normalized titles
- **Error Handling:**
  - Invalid file extension → Show "Please select a .csv file"
  - Malformed CSV (missing headers) → Show format requirements
  - Unrecognized format → Show manual mapping UI

**Performance:**
- Parsing speed: 1500 rows in ~5-7 seconds
- Memory usage: <50MB during parse (streaming, no full file load)

**Key Files:**
- `CSVParsingActor.swift` - Parsing logic
- `String+TitleNormalization.swift` - Title cleaning algorithm

#### 2. Duplicate Detection Algorithm

**Description:** Three-tier matching system to prevent duplicate entries

**Technical Requirements:**
- **Tier 1:** Exact title + author match (case-insensitive)
- **Tier 2:** ISBN match (if both books have ISBN)
- **Tier 3:** Normalized title + fuzzy author match (>80% similarity score)
- **Processing:** For each CSV row, query SwiftData for potential matches
- **Output:** DuplicateMatch enum (`.noDuplicate`, `.exactMatch(work)`, `.possibleMatch(work, score)`)
- **Error Handling:** If SwiftData query fails, assume no duplicate (prefer false negative over false positive)

**Success Rate:** 95%+ duplicate prevention (tested with 1500-book imports)

#### 3. Title Normalization for Better Enrichment

**Description:** Clean CSV titles for improved API search matching

**Algorithm:**
1. Remove series markers: `\s*\([^)]*,\s*#\d+\)` → `(Harry Potter, #1)` removed
2. Remove edition markers: `\s*\[[^\]]*\]` → `[Special Edition]` removed
3. Strip subtitles after `:` if title length > 10 chars → `Title: Subtitle` → `Title`
4. Remove abbreviation periods: `Dept.` → `Dept`
5. Normalize whitespace: multiple spaces → single space, trim

**Storage:**
- Original title stored in `work.title` (displayed to user)
- Normalized title used only for API searches via `.normalizedTitleForSearch` computed property

**Impact:** Enrichment success rate increased from ~70% to 90%+

**See:** `docs/features/CSV_IMPORT.md` lines 76-230 for detailed algorithm

#### 4. Background Enrichment Queue

**Description:** Asynchronous metadata fetching without blocking UI

**Technical Requirements:**
- **Input:** `[PersistentModelID]` of newly imported works
- **Processing:**
  - `EnrichmentQueue.shared.addMultiple()` queues all works
  - Process one work at a time (sequential, respects API rate limits)
  - For each work: fetch from Google Books + OpenLibrary, select best match
  - Update work with `coverUrl`, `isbn`, `publicationYear`, etc.
- **Output:** Updated SwiftData models + NotificationCenter progress updates
- **Error Handling:**
  - Network timeout → Retry with exponential backoff (1s, 2s, 4s, 8s)
  - API 404 → Mark as failed, don't retry
  - Stale PersistentID (work deleted) → Remove from queue silently

**Performance:**
- Processing rate: ~100 books/min (network-bound)
- Battery-optimized: AdaptivePollingStrategy reduces frequency when idle

**See:** `docs/workflows/enrichment-workflow.md` for state machine diagrams

---

## Non-Functional Requirements

### Performance

| Requirement | Target | Current | Rationale |
|-------------|--------|---------|-----------|
| **Import Speed** | 100 books/min | ~100 books/min | Users won't wait 30+ min for 1500 books |
| **Memory Usage** | <200MB peak | <200MB | Support older devices (iPhone 12+) |
| **Enrichment Speed** | 100 books/min | ~100 books/min | Background process, can be slower |
| **Batch Size** | 50 rows/batch | 50 rows | Balance memory vs save() overhead |

### Reliability

- **Duplicate Detection:** 95%+ accuracy (avoid duplicate entries)
- **Enrichment Success:** 90%+ with title normalization (metadata completeness)
- **Data Integrity:** Atomic SwiftData transactions ensure all-or-nothing imports
- **Error Recovery:** Failed enrichments retry automatically with exponential backoff

### Performance Benchmarks

| Book Count | Import Time | Enrichment Time | Total | Peak Memory |
|-----------|-------------|-----------------|-------|-------------|
| 100       | ~30s        | ~2-3 min        | ~3.5 min | <50MB |
| 500       | ~2.5 min    | ~10-12 min      | ~14 min | <120MB |
| 1500      | ~7.5 min    | ~30-35 min      | ~42 min | <200MB |

**See:** `docs/features/CSV_IMPORT.md` lines 388-418 for detailed benchmarks

---

## Technical Architecture

### System Components

| Component | Type | Responsibility | File Location |
|-----------|------|---------------|---------------|
| **CSVImportFlowView** | SwiftUI View | Multi-step import wizard UI | `CSVImportFlowView.swift` |
| **CSVParsingActor** | @globalActor Service | High-performance CSV parsing | `CSVParsingActor.swift` |
| **CSVImportService** | Service | SwiftData import orchestration | `CSVImportService.swift` |
| **EnrichmentService** | Service | API metadata enrichment | `EnrichmentService.swift` |
| **EnrichmentQueue** | @MainActor Singleton | Background enrichment queue | `EnrichmentQueue.swift` |
| **EnrichmentProgressBanner** | SwiftUI View | Real-time progress UI | `EnrichmentProgressBanner.swift` |
| **String+TitleNormalization** | Extension | Title cleaning algorithm | `String+TitleNormalization.swift` |

### Data Model Changes

**No new models required.** Existing `Work`, `Edition`, `Author`, `UserLibraryEntry` models used.

**New Extension:**
```swift
extension String {
    var normalizedTitleForSearch: String {
        // Title cleaning algorithm for API searches
        // See docs/features/CSV_IMPORT.md lines 89-131
    }
}
```

### API Contracts

**Backend Enrichment:**
- Uses existing `/search/title?q={title}` endpoint
- KV cache (6h TTL) reduces redundant API calls
- Google Books + OpenLibrary results merged server-side

**See:** `cloudflare-workers/api-worker/src/handlers/search.js`

---

## Testing Strategy

### Unit Tests

**Component Tests:**
- [x] Title normalization algorithm - `StringTitleNormalizationTests.swift` (13 test cases)
- [x] Duplicate detection - Match score calculation accuracy
- [x] CSV parsing - Goodreads/LibraryThing/StoryGraph format detection
- [x] Batch processing - Memory usage under 200MB for 1500 books
- [x] Queue self-cleaning - Stale PersistentID removal

**Edge Cases:**
- [x] Empty CSV file - Shows appropriate error
- [x] CSV with only headers - Shows "No books found"
- [x] CSV with internal duplicates - Deduplicates before insertion
- [x] All enrichment APIs fail - Gracefully falls back to unenriched entries

**Test Files:**
- `StringTitleNormalizationTests.swift`
- `CSVParsingActorTests.swift`
- `EnrichmentServiceTests.swift`

### Integration Tests

**End-to-End Flows:**
- [x] Import 100-book CSV → All books inserted → Enrichment queue populated
- [x] Import with duplicates → Smart strategy merges metadata correctly
- [x] Network offline during enrichment → Jobs queued for retry when online
- [x] App restart mid-enrichment → Queue persists and resumes

### Manual QA Checklist

**Real Device Testing:**
- [ ] iPhone 17 Pro (iOS 26.0.1) - primary test device
- [ ] iPhone 12 (iOS 26.0) - older hardware validation
- [ ] iPad Pro 13" (iOS 26.0) - tablet layout

**Test Scenarios:**
- [ ] Goodreads CSV (500 books) → 90%+ enrichment success
- [ ] LibraryThing CSV (100 books) → Correct column mapping
- [ ] StoryGraph CSV (1500 books) → Memory <200MB peak
- [ ] CSV with many duplicates → Skip/Replace strategies work correctly
- [ ] Import during airplane mode → Clear error, retry when online

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| Sep 15, 2025 | Initial draft | Product Team |
| Sep 20, 2025 | Added title normalization algorithm | Engineering |
| Sep 25, 2025 | Performance benchmarks validated | QA |
| Sep 28, 2025 | Approved for Build 45 | PM |
| Oct 15, 2025 | Post-launch: 90%+ enrichment success confirmed | Analytics |
| Oct 25, 2025 | Converted to PRD format from feature doc | Documentation |

## Approvals

**Sign-off required from:**

- [x] Product Manager - Approved Sep 28, 2025
- [x] Engineering Lead - Approved Sep 28, 2025
- [x] Design Lead (UI/UX) - Not required (existing Settings UI pattern)
- [x] QA Lead - Approved Sep 27, 2025

**Approved for Production:** Build 45 shipped October 2025

---

## Related Documentation

- **Workflow Diagram:** `docs/workflows/csv-import-workflow.md`
- **Technical Implementation:** `docs/features/CSV_IMPORT.md` - Complete technical deep-dive
- **Enrichment Workflow:** `docs/workflows/enrichment-workflow.md`
- **Title Normalization:** `BooksTrackerPackage/Sources/.../String+TitleNormalization.swift`
- **SyncCoordinator:** `docs/architecture/SyncCoordinator-Architecture.md`
- **Backend Code:** `cloudflare-workers/api-worker/src/handlers/search.js`
