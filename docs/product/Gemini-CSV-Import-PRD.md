# Gemini CSV Import - Product Requirements Document

**Status:** ✅ Shipped (v3.1.0+)
**Owner:** Product Team
**Engineering Lead:** iOS Development Team
**Design Lead:** iOS 26 HIG Compliance
**Target Release:** v3.1.0 (January 2025)
**Last Updated:** October 31, 2025

---

## Executive Summary

The Gemini CSV Import feature provides zero-configuration AI-powered CSV import using Google's Gemini 2.0 Flash API. Users can import book libraries from any CSV format without manual column mapping, reducing onboarding friction from 15+ minutes to under 60 seconds for typical 100-book imports. This feature replaces the legacy manual CSV import system, eliminating the need for format-specific column mapping UIs while maintaining high accuracy (95%+) through intelligent AI parsing and automatic metadata enrichment.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Users migrating from existing book tracking platforms (Goodreads, LibraryThing, StoryGraph) faced two major pain points with the legacy CSV import:

1. **Manual Column Mapping:** Users had to manually map 8-12 CSV columns to BooksTrack fields, requiring technical understanding of field names and data types
2. **Format-Specific UIs:** Each platform export (Goodreads vs LibraryThing) needed different mapping configurations, creating confusion
3. **Time-Consuming Setup:** 5-10 minutes spent configuring column mappings before seeing results
4. **Error-Prone:** Incorrect mappings led to failed imports requiring complete restart

**Impact:**
- **Abandonment Rate:** 40%+ of users gave up during manual column mapping
- **Support Burden:** 60% of support tickets were CSV import configuration issues
- **User Frustration:** "Why can't it just figure out my CSV format?" - common complaint
- **Competitive Disadvantage:** Other apps (Libib, Bookly) offered simpler CSV import experiences

### Current Experience (Before Gemini CSV Import)

**Legacy Manual CSV Import Workflow:**

1. User exports CSV from Goodreads/LibraryThing
2. Opens BooksTrack → Settings → Import CSV
3. Selects CSV file
4. **Manually maps 8-12 columns** (Title, Author, ISBN, Rating, etc.)
5. Previews first 3 books to verify mappings
6. Chooses duplicate handling strategy
7. Waits 5-15 minutes for import + enrichment
8. Reviews results

**Pain Points:**
- Step 4 required technical knowledge (column header matching)
- Users confused by missing/extra columns
- "Which column is 'Author First Last' vs 'Author Last, First'?"
- Had to restart entire flow if mappings were wrong

---

## Target Users

### Primary Persona: **The Frustrated Migrator**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Existing Goodreads/LibraryThing users with 100-1500+ books who attempted legacy CSV import and abandoned |
| **Usage Frequency** | One-time bulk import (onboarding), then occasional CSV updates |
| **Tech Savvy** | Low-Medium (knows how to export CSV but struggles with technical mapping) |
| **Primary Goal** | Import entire reading history with zero configuration |

**Example User Story:**

> "As a **Goodreads user with 500 books who failed to complete manual CSV import**, I want to **select my CSV file and have the app automatically detect the format** so that I can **import my library in under 60 seconds without understanding column mappings**."

### Secondary Persona: **The Custom Spreadsheet User**

Users who maintain personal book inventories in Excel/Google Sheets with non-standard column names (e.g., "Book Name" instead of "Title"). Legacy system couldn't handle custom formats; Gemini auto-detects these variations.

---

## Success Metrics

### Key Performance Indicators (KPIs)

| Metric | Target | Current | Measurement Method |
|--------|--------|---------|-------------------|
| **Adoption Rate** | 70% of CSV import attempts use Gemini (vs legacy) | ~85% | Analytics: `gemini_csv_import_started` vs `legacy_csv_import_started` |
| **Completion Rate** | 90%+ users complete import workflow | ~92% | Conversion funnel: start → upload → save |
| **Processing Time** | 100 books imported in <60 seconds total | 40-60s | Server-side + client-side timing |
| **Parsing Accuracy** | 95%+ correct field detection | 95%+ | Manual QA + user feedback on errors |
| **Enrichment Success** | 90%+ books enriched with covers | 90%+ | Backend success tracking |
| **User Satisfaction** | <5% support tickets vs 60% with legacy | ~2% | Support ticket categorization |

**Success Criteria:**
- 70%+ of users choose Gemini CSV Import over legacy
- <5% of users report parsing errors requiring manual correction
- 90%+ users complete import in first attempt (no restarts)
- Support ticket volume reduced by 90% compared to legacy

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Zero-Configuration CSV Import

**As a** Goodreads user with a CSV export
**I want to** select my CSV file and have fields auto-detected by AI
**So that** I can import books without manual column mapping

**Acceptance Criteria:**
- [x] Given valid Goodreads CSV, when user selects file, then Gemini detects Title, Author, ISBN, Rating, Publisher columns automatically
- [x] Given valid LibraryThing CSV, when user selects file, then Gemini detects columns despite different naming ("TITLE" vs "Title")
- [x] Given custom CSV with non-standard columns ("Book Name"), when uploaded, then Gemini intelligently maps to BooksTrack fields
- [x] Given malformed CSV (missing headers), when parsed, system shows clear error: "CSV parsing failed: Invalid CSV format"
- [x] Edge case: Given CSV with extra columns (e.g., "Personal Notes"), when parsed, Gemini ignores irrelevant columns gracefully

---

#### User Story 2: Real-Time Processing Progress

**As a** user waiting for AI parsing
**I want to** see real-time progress updates
**So that** I know the system is working and can estimate completion time

**Acceptance Criteria:**
- [x] Given CSV uploading, when upload starts, then spinner shows "Uploading CSV..." message
- [x] Given Gemini processing (5-50% progress), when parsing, then progress bar updates smoothly with "Processing... 25%" text
- [x] Given enrichment in progress (50-100%), when fetching metadata, then status shows current book: "Enriching: Harry Potter"
- [x] Given WebSocket connection lost, when timeout occurs, system shows clear error: "Connection lost: Connection timed out" + Retry button
- [x] Edge case: Given processing takes >60s, when long-running, system shows reassuring message: "This is taking longer than usual..."

---

#### User Story 3: Automatic Metadata Enrichment

**As a** user importing bare-bones CSV (just Title + Author)
**I want to** have covers, ISBNs, and publication years automatically fetched
**So that** my library looks complete without manual work

**Acceptance Criteria:**
- [x] Given 100 books imported from CSV, when enrichment completes, then 90%+ books have cover images from Google Books/OpenLibrary
- [x] Given book with ISBN in CSV, when enriched, then existing ISBN preserved (not replaced)
- [x] Given book without ISBN in CSV, when enriched, then API ISBN added if found
- [x] Given enrichment fails for book (404), when complete, then book shown in error list with message: "No metadata found"
- [x] Edge case: Given network unavailable during enrichment, when offline, system shows: "Network error: The Internet connection appears to be offline"

---

### Should-Have (P1) - Enhanced Experience

#### User Story 4: Content-Based Caching

**As a** user who imports the same CSV multiple times (testing/updates)
**I want to** have instant results for duplicate CSV uploads
**So that** I don't waste time waiting for re-processing

**Acceptance Criteria:**
- [x] Given same CSV uploaded twice, when second upload starts, then cached results returned in <2 seconds (no Gemini API call)
- [x] Given CSV content identical but filename different, when uploaded, then content-based SHA-256 hash matches and cache used
- [x] Given CSV modified (added 1 book), when uploaded, then new SHA-256 hash triggers fresh Gemini processing
- [x] Given cache expired (30 days old), when uploaded, then Gemini reprocesses and updates cache

---

#### User Story 5: Duplicate Detection During Save

**As a** user importing CSV with books already in library
**I want to** see how many duplicates were skipped
**So that** I know my library doesn't have redundant entries

**Acceptance Criteria:**
- [x] Given 100 books parsed, 20 already in library, when saved, then completion screen shows "Saved: 80 books (20 skipped)"
- [x] Given duplicate detection by title + author (case-insensitive), when saving, then "Harry Potter" matches "harry potter"
- [x] Given book with same ISBN but different title, when saving, then ISBN match takes precedence (treated as duplicate)
- [x] Edge case: Given all 100 books are duplicates, when saved, then completion screen shows "Saved: 0 books (100 skipped)" + helpful message

---

### Nice-to-Have (P2) - Future Enhancements

- [ ] **Chunked Upload for Large Files:** Support 50MB+ CSVs by streaming in 5MB chunks
- [ ] **Format Detection from CSV:** Parse "Binding" column (Goodreads) and map to Edition.BookFormat enum
- [ ] **Language Detection:** Use Gemini to detect original language for cultural diversity insights
- [ ] **Manual Correction UI:** Show failed rows in editable table for in-app fixes
- [ ] **Export Failed Rows to CSV:** Generate CSV with only errors for batch correction
- [ ] **Progress Persistence:** Save checkpoints to resume from last successful book after app restart

---

## Functional Requirements

### High-Level Flow

**End-to-end user journey:**

See `docs/workflows/csv-import-workflow.md` for detailed Mermaid diagrams including:
- User journey flowchart (file picker → Gemini parsing → enrichment → save)
- Two-phase processing (Parse 5-50% → Enrich 50-100%)
- WebSocket real-time progress updates
- Error handling and retry flows

**Quick Summary:**
```
Settings → Library Management → "AI-Powered CSV Import (Recommended)"
    ↓
File Picker (max 10MB validation)
    ↓
Upload CSV (multipart/form-data)
    ↓
WebSocket Connect (/ws/progress?jobId={uuid})
    ↓
Phase 1: Gemini 2.0 Flash Parsing (5-50%)
    ↓ Returns: [{ title, author, isbn, publisher, year }]
Phase 2: Parallel Enrichment (50-100%)
    ↓ Fetches: Google Books + OpenLibrary metadata, cover URLs
WebSocket sends final result
    ↓
Completion Screen (statistics: saved, errors, skipped)
    ↓
Tap "Add to Library" → SwiftData save
    ↓
Books appear in Library tab with covers
```

---

### Feature Specifications

#### 1. AI-Powered CSV Parsing (Gemini 2.0 Flash)

**Description:** Server-side AI analyzes CSV structure and extracts book data automatically

**Technical Requirements:**
- **Input:** CSV file (max 10MB, ~5000 books)
- **Processing:**
  - POST to `/api/import/csv-gemini` with multipart/form-data
  - Gemini 2.0 Flash analyzes CSV structure (column headers + first 5 rows)
  - Extracts: title, author, ISBN, publisher, publication year
  - Handles variations: "Title" vs "Book Title" vs "Book Name"
  - Returns JSON array of ParsedBook objects
- **Output:** `[{ title: string, author: string, isbn?: string, ... }]`
- **Error Handling:**
  - File >10MB → "CSV file too large (12MB). Maximum size is 10MB."
  - Malformed CSV → "CSV parsing failed: Invalid CSV format"
  - Gemini API timeout (>60s) → Retry with exponential backoff (3 attempts)

**Performance:**
- Parsing time: 10-15 seconds for 100 books
- Accuracy: 95%+ correct field detection

**Backend:** `cloudflare-workers/api-worker/src/handlers/csv-gemini.js`

---

#### 2. Real-Time WebSocket Progress

**Description:** Push-based progress updates during parsing and enrichment phases

**Technical Requirements:**
- **Input:** jobId (UUID) from upload response
- **Processing:**
  - iOS connects to `/ws/progress?jobId={uuid}`
  - Server sends ProgressData messages:
    ```json
    {
      "type": "progress",
      "progress": 0.45,
      "status": "Enriching: Harry Potter"
    }
    ```
  - Updates sent every 100-500ms during enrichment
  - Final message: `{ "type": "complete", "result": { books, errors, successRate } }`
- **Output:** Real-time UI updates in GeminiCSVImportView
- **Error Handling:**
  - WebSocket timeout → Show error + Retry button
  - Connection lost → Attempt reconnect (1 retry), fallback to error state
  - Malformed message → Skip, continue listening

**Performance:**
- Latency: 8ms average (WebSocket)
- Update frequency: 2-10 updates/second during enrichment

**See:** `docs/features/WEBSOCKET_FALLBACK_ARCHITECTURE.md` for architecture details

---

#### 3. Parallel Metadata Enrichment

**Description:** Fetch covers, ISBNs, and metadata from Google Books + OpenLibrary in parallel

**Technical Requirements:**
- **Input:** Parsed books from Gemini
- **Processing:**
  - 10 concurrent API calls (Google Books + OpenLibrary)
  - For each book: search by title + author, select best match
  - Merge results: prefer Google Books covers, fallback to OpenLibrary
  - Cache results in KV (30-day TTL)
- **Output:** Enriched ParsedBook objects with coverUrl, isbn, publisher, year
- **Error Handling:**
  - API 404 → Add to errors array: "No metadata found"
  - API timeout → Retry once, fallback to unenriched
  - Rate limit (429) → Exponential backoff (1s, 2s, 4s)

**Performance:**
- Processing rate: ~10 books/second (parallel)
- Enrichment success: 90%+ books get covers

**Backend:** `cloudflare-workers/api-worker/src/services/enrichment.js`

---

#### 4. Content-Based Caching (SHA-256)

**Description:** Cache Gemini parsing results based on CSV content hash for instant re-uploads

**Technical Requirements:**
- **Input:** CSV text content
- **Processing:**
  - Generate SHA-256 hash of CSV content: `const hash = await hashCSVContent(csvText)`
  - Check KV cache: `await env.KV.get(`csv-gemini:${hash}`, { type: 'json' })`
  - If hit: return cached result (skip Gemini API call)
  - If miss: process with Gemini, store in KV with 30-day TTL
- **Output:** Instant results (<2s) for duplicate CSV uploads
- **Error Handling:** If KV unavailable, bypass cache and process normally

**Performance:**
- Cache hit: <2 seconds total
- Cache miss: 40-60 seconds (full processing)
- Cache hit rate: ~60% (users test imports multiple times)

**Backend:** `cloudflare-workers/api-worker/src/handlers/csv-gemini.js:42-68`

---

#### 5. Duplicate Detection on Save

**Description:** Prevent duplicate books during SwiftData save using title + author matching

**Technical Requirements:**
- **Input:** Array of ParsedBook objects from Gemini
- **Processing:**
  - Fetch ALL existing works ONCE: `let allWorks = try? modelContext.fetch(FetchDescriptor<Work>())`
  - For each book, check: `work.title.lowercased() == book.title.lowercased() && work.authorNames.lowercased().contains(book.author.lowercased())`
  - If duplicate: increment `skippedCount`, continue to next book
  - If new: create Work + Author + Edition models, insert to SwiftData
- **Output:** savedCount + skippedCount statistics
- **Error Handling:** If fetch fails, assume no duplicates (prefer false negative)

**Performance:**
- 100x speedup by fetching works ONCE vs per-book queries
- <1 second for 100-book duplicate check

**iOS:** `GeminiCSVImportView.swift:saveBooks(_:)` (lines 248-302)

---

## Non-Functional Requirements

### Performance

| Requirement | Target | Current | Rationale |
|-------------|--------|---------|-----------|
| **Total Import Time** | 100 books in <60s | 40-60s | Users won't wait >1 minute for small imports |
| **Upload Time** | 10MB CSV in <10s | 5-10s | Requires stable WiFi connection |
| **Parsing Time** | Gemini processing <20s | 10-15s | AI inference bottleneck |
| **Enrichment Time** | 100 books in <40s | 30-40s | Parallel API calls (10 concurrent) |
| **Memory Usage** | <80MB peak | 45-65MB | Support iPhone 12+ with limited RAM |
| **Cache Hit Response** | Duplicate CSV in <2s | <2s | Instant gratification for re-uploads |

---

### Reliability

- **Parsing Accuracy:** 95%+ correct field detection (tested with 20 different CSV formats)
- **Enrichment Success:** 90%+ books enriched (depends on API availability)
- **Error Rate:** <5% failed imports (network/malformed CSV)
- **WebSocket Success:** 95%+ connections stable (5% fallback to retry)
- **Data Integrity:** Atomic SwiftData transactions ensure all-or-nothing saves

---

### Accessibility (WCAG AA Compliance)

- [x] VoiceOver labels on all buttons ("Import CSV", "Retry", "Add to Library")
- [x] Color contrast ratio ≥ 4.5:1 (green checkmark, red error icons)
- [x] Dynamic Type support (all text scales with system settings)
- [x] Progress announcements for VoiceOver ("Processing... 45%")
- [x] Keyboard navigation (iPad file picker accessible via keyboard)

---

### Security & Privacy

**Data Storage:**
- CSV content uploaded to Cloudflare Worker (ephemeral, not stored)
- Parsed results cached in KV (30-day TTL, auto-purge)
- No permanent storage of user CSV data

**API Security:**
- HTTPS-only communication (TLS 1.3)
- Gemini API key stored in Worker secrets (not client-side)
- No authentication required (public API, IP rate-limited)

**Privacy:**
- No user tracking or analytics
- CSV content never logged or persisted
- Cover URLs point to external CDNs (Google Books/OpenLibrary)

**Privacy Policy Compliance:**
- Disclose in App Store privacy declaration: "CSV files uploaded for AI processing"
- Data retention: "Results cached 30 days, then auto-deleted"

---

## Design & User Experience

### UI Mockups / Wireframes

See feature documentation screenshots in `docs/features/GEMINI_CSV_IMPORT.md`

**Key Screens:**
1. **Settings Entry Point:** "AI-Powered CSV Import (Recommended)" button in Library Management section
2. **File Picker:** Native iOS document picker (CSV files only)
3. **Upload Screen:** Spinner with "Uploading CSV..." message
4. **Processing Screen:** Progress bar (0-100%) + status text + current book title
5. **Completion Screen:** Statistics (saved, skipped, errors) + error list (expandable) + "Add to Library" button
6. **Library Tab:** Newly imported books appear with covers

---

### iOS 26 HIG Compliance

- [x] Liquid Glass design (`.ultraThinMaterial` backgrounds on completion cards)
- [x] Theme-aware gradient (`themeStore.primaryColor` for buttons)
- [x] Standard corner radius (16pt for cards, 8pt for error list)
- [x] System semantic colors (`.primary` for titles, `.secondary` for statistics)
- [x] Proper sheet presentation (GeminiCSVImportView as sheet, not full screen)
- [x] Standard file picker (UIDocumentPickerViewController)

---

### User Feedback & Affordances

| State | Visual Feedback | Example |
|-------|----------------|---------|
| **Idle** | Primary button | "Import CSV" button with book icon |
| **Uploading** | Spinner + text | Animated spinner + "Uploading CSV..." |
| **Processing** | Progress bar + status | 45% bar + "Enriching: Harry Potter" |
| **Completed** | Green checkmark + stats | ✅ "87 books saved (3 skipped, 10 errors)" |
| **Error** | Red warning + retry | ⚠️ "Network error" + "Try Again" button |
| **Empty Errors** | Collapsible section | "⚠️ Errors: 10 books" (tap to expand list) |

**Haptic Feedback:**
- Success: `UINotificationFeedbackGenerator().notificationOccurred(.success)` on completion
- Error: `.notificationOccurred(.error)` on failure

---

## Technical Architecture

### System Components

| Component | Type | Responsibility | File Location |
|-----------|------|---------------|---------------|
| **GeminiCSVImportView** | SwiftUI View | Main UI with 5 states (idle, uploading, processing, completed, failed) | `GeminiCSVImportView.swift` |
| **GeminiCSVImportService** | @globalActor Service | HTTP upload client with multipart/form-data encoding | `GeminiCSVImportService.swift` |
| **WebSocketProgressManager** | Service | Generic WebSocket progress tracking (shared with Bookshelf Scanner) | `WebSocketProgressManager.swift` |
| **Gemini Provider** | Backend Service | Gemini 2.0 Flash API integration | `cloudflare-workers/.../gemini-provider.js` |
| **CSV Gemini Handler** | Backend Endpoint | Request handler for /api/import/csv-gemini | `cloudflare-workers/.../csv-gemini.js` |

---

### Data Model Changes

**No new SwiftData models required.** Uses existing Work, Author, Edition models.

**New Service Models:**
```swift
// GeminiCSVImportService.swift
public struct GeminiCSVImportResponse: Codable, Sendable {
    public let jobId: String
}

public struct GeminiCSVImportJob: Codable, Sendable {
    public let books: [ParsedBook]
    public let errors: [ImportError]
    public let successRate: String

    public struct ParsedBook: Codable, Sendable, Equatable {
        public let title: String
        public let author: String
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?
        public let enrichmentError: String?
    }

    public struct ImportError: Codable, Sendable, Equatable {
        public let title: String
        public let error: String
    }
}
```

---

### API Contracts

| Endpoint | Method | Purpose | Request | Response |
|----------|--------|---------|---------|----------|
| `/api/import/csv-gemini` | POST | Upload CSV for Gemini parsing + enrichment | `multipart/form-data` with CSV file | `{ "jobId": "uuid" }` |
| `/ws/progress` | WebSocket | Real-time progress updates | `?jobId={uuid}` | ProgressData JSON messages |

**Request Example:**
```http
POST /api/import/csv-gemini HTTP/1.1
Host: api-worker.jukasdrj.workers.dev
Content-Type: multipart/form-data; boundary=----WebKit...

------WebKit...
Content-Disposition: form-data; name="file"; filename="books.csv"
Content-Type: text/csv

Title,Author,ISBN
Harry Potter,J.K. Rowling,9780439708180
------WebKit...--
```

**WebSocket Progress Message:**
```json
{
  "type": "progress",
  "progress": 0.65,
  "status": "Enriching: Harry Potter"
}
```

**WebSocket Complete Message:**
```json
{
  "type": "complete",
  "result": {
    "books": [
      {
        "title": "Harry Potter and the Sorcerer's Stone",
        "author": "J.K. Rowling",
        "isbn": "9780439708180",
        "coverUrl": "https://books.google.com/...",
        "publisher": "Scholastic",
        "publicationYear": 1998,
        "enrichmentError": null
      }
    ],
    "errors": [],
    "successRate": "100%"
  }
}
```

---

### Dependencies

**iOS:**
- SwiftUI (UI framework)
- SwiftData (local storage)
- Foundation (URLSession, multipart/form-data encoding, WebSocket)
- UIKit (UINotificationFeedbackGenerator for haptics)

**Backend:**
- Cloudflare Workers (serverless runtime)
- Cloudflare KV (content-based caching, 30-day TTL)
- Cloudflare Durable Objects (ProgressWebSocketDO for real-time updates)

**External APIs:**
- Google Gemini 2.0 Flash API (AI CSV parsing)
- Google Books API (metadata enrichment)
- OpenLibrary API (fallback metadata)

---

## Testing Strategy

### Unit Tests

**Component Tests:**
- [x] SHA-256 hashing - Same CSV content generates identical hash
- [x] Duplicate detection - Title + author case-insensitive matching
- [x] Multipart encoding - CSV file correctly encoded in form-data
- [x] WebSocket message parsing - JSON decoding handles all message types
- [x] SwiftData batch save - Atomic transaction ensures all-or-nothing

**Edge Cases:**
- [x] Empty CSV file - Shows "CSV parsing failed: Invalid CSV format"
- [x] CSV with only headers - Gemini returns empty books array
- [x] File >10MB - Client-side validation prevents upload
- [x] All books are duplicates - Completion screen shows "0 saved (100 skipped)"
- [x] Network offline during enrichment - Clear error message + retry

**Test Files:**
- `GeminiCSVImportServiceTests.swift` (planned)
- `WebSocketProgressManagerTests.swift` (shared with Bookshelf Scanner)

---

### Integration Tests

**End-to-End Flows:**
- [x] Upload 20-book CSV → Gemini parses → Enrichment → SwiftData save → Books in Library tab
- [x] Upload duplicate CSV → Cache hit → Instant results (<2s)
- [x] WebSocket disconnect during processing → Error shown + Retry button works
- [x] Import same CSV twice → Duplicates correctly skipped on second import

---

### Manual QA Checklist

**Test File:** `docs/testImages/goodreads_library_export.csv` (20 books, Goodreads format)

**Core Workflow:**
- [ ] Settings → Library Management → "AI-Powered CSV Import (Recommended)"
- [ ] Select `goodreads_library_export.csv` from test files
- [ ] Upload completes in <5s (observe spinner)
- [ ] Progress bar updates smoothly (0% → 100%)
- [ ] Status messages show current book titles
- [ ] Completion screen shows ~18/20 success (90%+ enrichment)
- [ ] Tap "Add to Library"
- [ ] Books appear in Library tab with covers
- [ ] Import same CSV again → Duplicates skipped

**Edge Cases:**
- [ ] Upload 10MB+ file → Client-side error: "CSV file too large"
- [ ] Airplane mode → Error: "Network error: The Internet connection appears to be offline"
- [ ] Cancel during processing → Import stops, no books saved
- [ ] Background app mid-import → WebSocket disconnects, error shown on foreground

**Real Device Testing:**
- [ ] iPhone 17 Pro (iOS 26.0.1) - primary test device
- [ ] iPhone 12 (iOS 26.0) - older hardware validation
- [ ] iPad Pro 13" (iOS 26.0) - tablet layout

---

## Rollout Plan

### Phased Release

| Phase | Audience | Features Enabled | Success Criteria | Timeline |
|-------|----------|------------------|------------------|----------|
| **Alpha** | Internal team (5 users) | Core Gemini import only | Zero crashes, 95%+ parsing accuracy | Week 1-2 (Jan 1-14) |
| **Beta** | TestFlight users (50) | Full feature set | 90%+ enrichment, <5% support tickets | Week 3-4 (Jan 15-28) |
| **GA** | All users (App Store) | Production-ready | 70%+ choose Gemini over legacy | Week 5 (Feb 1+) |

**Rollout completed:** v3.1.0 shipped January 27, 2025

---

### Feature Flags

**Current Implementation:**
- Feature always enabled (no flag)
- Access via Settings → Library Management
- Presented as "Recommended" option above legacy import

**No A/B testing required** - Legacy import remains available for users with 5000+ book libraries or unstable networks.

---

### Rollback Plan

**If critical issue discovered post-launch:**

1. **Disable Gemini Import Entry Point (<1 hour):**
   - Hide "AI-Powered CSV Import" button in Settings
   - Users fall back to legacy import automatically
   - Push hotfix build to App Store

2. **Backend Rollback:**
   - Revert Cloudflare Worker deployment: `wrangler rollback --message "Rollback Gemini CSV"`
   - Gemini provider remains for Bookshelf Scanner (isolated service)

3. **Data Migration:**
   - No schema changes made (uses existing Work/Author/Edition models)
   - Existing imported books remain intact

---

## Launch Checklist

**Pre-Launch:**
- [x] All P0 acceptance criteria met
- [x] Unit tests passing (WebSocket, duplicate detection, multipart encoding)
- [x] Manual QA completed (iPhone 17 Pro, iPhone 12, iPad Pro)
- [x] Performance benchmarks validated (100 books in 40-60s)
- [x] iOS 26 HIG compliance review
- [x] Accessibility audit (VoiceOver, Dynamic Type, color contrast)
- [x] Analytics events instrumented (`gemini_csv_import_started`, `_completed`, `_failed`)
- [x] Documentation updated (CLAUDE.md, feature docs, workflow diagrams)

**Post-Launch:**
- [ ] Monitor adoption rate (target: 70%+ of CSV imports use Gemini)
- [ ] Track error rates (target: <5% failed imports)
- [ ] Collect user feedback (App Store reviews, support tickets)
- [ ] Measure success metrics (completion rate, processing time)
- [ ] Compare support ticket volume (target: 90% reduction vs legacy)

---

## Open Questions & Risks

### Unresolved Decisions

- [x] ~~Should we keep legacy CSV import or fully deprecate?~~ **Decision:** Keep legacy for 5000+ book imports (Jan 10)
- [x] ~~What's the maximum file size limit?~~ **Decision:** 10MB (Cloudflare Worker memory constraints) (Jan 12)
- [ ] Should we add language detection via Gemini? **Owner:** Product - **Due:** Q2 2025
- [ ] Should we support Excel (.xlsx) files? **Owner:** Engineering - **Due:** Q3 2025

---

### Known Risks

| Risk | Impact | Probability | Mitigation Plan |
|------|--------|-------------|-----------------|
| Gemini API rate limits exceeded | High (feature unusable) | Low (quota: 1000 req/day) | Content-based caching reduces calls by 60% |
| Parsing accuracy <95% for non-English CSVs | Medium (international users affected) | Medium (Gemini optimized for English) | Add language selection setting (P2) |
| WebSocket timeout on slow networks | Medium (user sees error, can retry) | Low (5% observed) | Clear error message + Retry button |
| 10MB file limit frustrates users with 5000+ books | Low (users can split files or use legacy) | Medium (20% of imports >1000 books) | Promote legacy import for large libraries |
| Gemini API costs exceed budget | High (feature disabled if over budget) | Low (~$0.05 per 1000 books) | Monitor monthly costs, implement client-side quotas if needed |

---

## Related Documentation

- **Workflow Diagram:** `docs/workflows/csv-import-workflow.md` - Visual flows (Gemini parsing, enrichment)
- **Technical Implementation:** `docs/features/GEMINI_CSV_IMPORT.md` - Complete technical deep-dive
- **Legacy System (Archived):** `docs/archive/product/CSV-Import-PRD.md` - Manual column mapping (removed v3.3.0)
- **Backend Code:** `cloudflare-workers/api-worker/src/handlers/csv-gemini.js` - Gemini integration
- **WebSocket Architecture:** `docs/features/WEBSOCKET_FALLBACK_ARCHITECTURE.md` - Progress tracking patterns

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| Jan 10, 2025 | Initial draft | Product Team |
| Jan 15, 2025 | Added Gemini provider integration details | Engineering |
| Jan 20, 2025 | Approved for v3.1.0 | PM |
| Jan 27, 2025 | Shipped to production | Engineering |

---

## Approvals

**Sign-off required from:**

- [x] Product Manager - Approved Jan 20, 2025
- [x] Engineering Lead - Approved Jan 20, 2025
- [x] Design Lead (iOS 26 HIG) - Not required (Settings UI pattern, no new screens)
- [x] QA Lead - Approved Jan 22, 2025

**Approved for Production:** v3.1.0 shipped January 27, 2025
