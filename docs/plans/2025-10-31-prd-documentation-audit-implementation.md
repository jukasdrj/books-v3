# PRD Documentation Audit & Update - Implementation Plan

**Date:** October 31, 2025
**Based on:** [Design Document](2025-10-30-prd-documentation-audit-design.md)
**Executor:** Engineering team (with Claude Code assistance)
**Estimated Duration:** 3-4 hours focused work
**Branch:** main (no worktree needed - documentation updates only)

## Overview

This plan executes the interactive audit designed in the brainstorming session. We'll systematically review each feature area, identify documentation gaps in real-time, and fix them immediately during the audit session.

**Philosophy:** Fix as we go, not batch-and-defer.

---

## Prerequisites

### Required Tools
- ✅ Text editor (VSCode, Xcode, or any Markdown editor)
- ✅ Git access (for commit history review)
- ✅ Terminal access (for file listing, grepping)
- ✅ Mermaid preview capability (VSCode plugin, GitHub web preview, or mermaid.live)

### Required Context
- ✅ Access to codebase (`BooksTrackerPackage/`, `cloudflare-workers/`)
- ✅ Familiarity with recent changes (VisionKit, canonical contracts, genre normalization)
- ✅ Understanding of documentation structure (`docs/product/`, `docs/workflows/`, `CLAUDE.md`)

---

## Phase 1: Inventory Current State (15 min)

**Goal:** Build master list of existing documentation and identify obvious gaps.

### Task 1.1: Scan Existing PRD Files (5 min)

**Commands:**
```bash
ls -lah docs/product/*.md
```

**Output:** Create checklist in `docs/audit-2025-10-31-inventory.md`:
```markdown
## Existing PRDs (Last Modified Date)
- [ ] Feature Name - YYYY-MM-DD
- [ ] Another Feature - YYYY-MM-DD
...
```

**Deliverable:** `docs/audit-2025-10-31-inventory.md` (section 1)

---

### Task 1.2: Scan Existing Workflow Diagrams (3 min)

**Commands:**
```bash
ls -lah docs/workflows/*.md
```

**Output:** Add to inventory file:
```markdown
## Existing Workflows
- [ ] feature-name-workflow.md
- [ ] another-workflow.md
...
```

**Deliverable:** `docs/audit-2025-10-31-inventory.md` (section 2)

---

### Task 1.3: Extract Features from CLAUDE.md (4 min)

**Commands:**
```bash
grep -A 20 "### Features" CLAUDE.md
```

**Output:** Add to inventory file:
```markdown
## Features Mentioned in CLAUDE.md
- Bookshelf AI Scanner
- Batch Bookshelf Scanning
- Gemini CSV Import
- Review Queue
- [list all mentioned features]
```

**Deliverable:** `docs/audit-2025-10-31-inventory.md` (section 3)

---

### Task 1.4: Review Recent Code Changes (3 min)

**Commands:**
```bash
git log --since="2 weeks ago" --oneline --name-only | grep -E "(Sources|cloudflare-workers)" | sort -u
```

**Output:** Add to inventory file:
```markdown
## Recently Modified Files (Last 2 Weeks)
- BooksTrackerPackage/Sources/BooksTrackerFeature/SearchView.swift
- cloudflare-workers/api-worker/src/services/genre-normalizer.ts
- [list all]

## Inferred Recent Feature Work
- VisionKit barcode scanner (SearchView.swift changes)
- Genre normalization (genre-normalizer.ts)
- Canonical contracts (DTOMapper.swift)
```

**Deliverable:** `docs/audit-2025-10-31-inventory.md` (section 4)

**Completion Check:** Inventory file exists with 4 sections, ready for feature-by-feature audit.

---

## Phase 2: Feature-by-Feature Audit & Fix

**Execution Strategy:** Tackle features in priority order, fix gaps immediately.

**Per-Feature Workflow:**
1. Check if PRD exists
2. If exists: Verify sections are complete and current
3. If missing/outdated: Create/update PRD using template
4. Check if workflow diagram exists
5. If missing: Create workflow diagram
6. Verify CLAUDE.md references are accurate
7. Mark feature complete in inventory checklist

---

### Category A: Recently Changed Features (Priority 1)

**Time Allocation:** 30-45 min per feature

---

#### Task 2.1: VisionKit Barcode Scanner (45 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*barcode* docs/product/*scanner* docs/product/*vision*

# Does workflow exist?
ls docs/workflows/*barcode* docs/workflows/*scanner*

# What does CLAUDE.md say?
grep -A 10 "Barcode Scanning" CLAUDE.md
```

**Expected Gap:** Missing PRD (design doc exists but not user-facing PRD)

**Action Items:**
- [ ] Create `docs/product/VisionKit-Barcode-Scanner-PRD.md`
  - Problem: Manual ISBN entry is slow and error-prone
  - Solution: Native Apple VisionKit DataScannerViewController
  - User Stories:
    - As a user, I want to scan book barcodes so I can add books quickly
    - As a user, I want clear guidance when scanning fails so I know what to fix
  - Success Metrics:
    - 95% of ISBN scans complete in <3s
    - Zero crashes from permission denial
    - Auto-highlighting improves first-try success rate
  - Technical Implementation:
    - DataScannerViewController (iOS 16+)
    - Symbologies: EAN-13, EAN-8, UPC-E
    - Capability checking: `isSupported`, `isAvailable`
    - Error states: UnsupportedDeviceView, PermissionDeniedView
  - Decision Log:
    - [Oct 30, 2025] **Decision:** VisionKit over AVFoundation. **Rationale:** Zero custom camera code, built-in gestures, automatic guidance UI, tap-to-scan, pinch-to-zoom.
    - [Oct 30, 2025] **Decision:** Remove AVFoundation implementation. **Rationale:** Maintenance burden, iOS 26 HIG violations, VisionKit covers all use cases.
  - Future Enhancements:
    - Multi-book batch scanning (scan 5+ books without leaving scanner)
    - Scan history with "Add All" button
- [ ] Create `docs/workflows/barcode-scanner-workflow.md` (Mermaid diagram)
  - User taps "Scan ISBN" button
  - Check device capability
  - Request camera permission
  - Launch DataScannerViewController
  - User taps recognized barcode
  - Extract ISBN
  - Trigger search by ISBN
  - Handle errors (unsupported device, permission denied)
- [ ] Update CLAUDE.md "Barcode Scanning" section
  - Reference PRD: `See docs/product/VisionKit-Barcode-Scanner-PRD.md`
  - Reference workflow: `See docs/workflows/barcode-scanner-workflow.md`
  - Remove AVFoundation references (keep deprecation note)
- [ ] Cross-reference design doc
  - Add note to `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md`:
    - "User-facing PRD: docs/product/VisionKit-Barcode-Scanner-PRD.md"

**Deliverables:**
- `docs/product/VisionKit-Barcode-Scanner-PRD.md`
- `docs/workflows/barcode-scanner-workflow.md`
- Updated CLAUDE.md section

**Completion Check:** PRD exists, workflow exists, CLAUDE.md references both, no AVFoundation references except deprecation note.

---

#### Task 2.2: Canonical Data Contracts (v1.0.0) (45 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*canonical* docs/product/*contract* docs/product/*dto*

# Does workflow exist?
ls docs/workflows/*canonical* docs/workflows/*v1-api*

# What does CLAUDE.md say?
grep -A 30 "Canonical Data Contracts" CLAUDE.md
```

**Expected Gap:** Missing PRD (design + implementation plans exist, but no user-facing PRD)

**Action Items:**
- [ ] Create `docs/product/Canonical-Data-Contracts-PRD.md`
  - Problem:
    - API responses inconsistent across providers (Google Books, OpenLibrary)
    - iOS code duplicates normalization logic (genre mapping, provenance tracking)
    - No clear source-of-truth for data structure
  - Solution:
    - TypeScript-first canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)
    - Backend normalizes all provider data to canonical format
    - iOS consumes consistent structure (zero provider-specific code)
  - User Stories:
    - As a developer, I want consistent API responses so I can write simple iOS parsing code
    - As a developer, I want genre normalization on backend so iOS doesn't duplicate logic
    - As a user, I want accurate book metadata regardless of which API found it
  - Success Metrics:
    - Zero provider-specific code in iOS search services
    - 100% genre consistency (Thriller → Thriller, not Suspense/Mystery/Thrillers)
    - Provenance tracking enables debugging ("Where did this genre come from?")
  - Technical Implementation:
    - TypeScript DTOs: `cloudflare-workers/api-worker/src/types/canonical.ts`
    - Normalizers: `normalizeGoogleBooksToWork`, `normalizeGoogleBooksToEdition`
    - Genre service: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`
    - iOS DTOMapper: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`
    - V1 Endpoints: `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`
  - Decision Log:
    - [Oct 28, 2025] **Decision:** Backend normalization over iOS normalization. **Rationale:** Single source of truth, easier to debug, consistent across all clients (future Android app).
    - [Oct 29, 2025] **Decision:** TypeScript-first DTOs. **Rationale:** Compiler enforces consistency, auto-generates OpenAPI docs, easier to version.
    - [Oct 29, 2025] **Decision:** Versioned endpoints (/v1/*). **Rationale:** Allows breaking changes without disrupting iOS, gradual migration from legacy endpoints.
    - [Oct 29, 2025] **Decision:** Synthetic works flag. **Rationale:** Some providers (Google Books) only return editions, iOS needs to dedupe inferred works.
  - Future Enhancements:
    - Deprecate legacy endpoints (deferred 2-4 weeks for iOS migration validation)
    - Add OpenLibrary provider normalizer
    - Structured error codes (INVALID_QUERY, INVALID_ISBN, PROVIDER_ERROR)
- [ ] Create `docs/workflows/canonical-contracts-workflow.md` (Mermaid diagram)
  - iOS sends search request to `/v1/search/title?q=...`
  - Worker calls Google Books API
  - Worker normalizes response to canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)
  - Worker applies genre normalization (Thrillers → Thriller)
  - Worker adds provenance tracking (`primaryProvider: "google-books"`)
  - Worker returns envelope: `{ success, data: { works, authors }, meta }`
  - iOS DTOMapper converts DTOs to SwiftData models
  - iOS deduplicates synthetic works (matches by ISBN)
  - Handle errors (invalid query, provider failure, timeout)
- [ ] Update CLAUDE.md "Canonical Data Contracts" section
  - Verify implementation status (all ✅ should be accurate)
  - Reference PRD: `See docs/product/Canonical-Data-Contracts-PRD.md`
  - Reference workflow: `See docs/workflows/canonical-contracts-workflow.md`
- [ ] Cross-reference design docs
  - Add note to `docs/plans/2025-10-29-canonical-data-contracts-design.md`:
    - "User-facing PRD: docs/product/Canonical-Data-Contracts-PRD.md"
  - Add note to `docs/plans/2025-10-30-canonical-contracts-implementation.md`:
    - "User-facing PRD: docs/product/Canonical-Data-Contracts-PRD.md"

**Deliverables:**
- `docs/product/Canonical-Data-Contracts-PRD.md`
- `docs/workflows/canonical-contracts-workflow.md`
- Updated CLAUDE.md section

**Completion Check:** PRD exists, workflow exists, CLAUDE.md ✅ checkboxes accurate, design docs cross-referenced.

---

#### Task 2.3: Genre Normalization Service (30 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*genre*

# Does workflow exist?
ls docs/workflows/*genre*

# What does CLAUDE.md say?
grep -i "genre" CLAUDE.md
```

**Expected Gap:** Missing PRD (service exists, no user-facing doc)

**Action Items:**
- [ ] Create `docs/product/Genre-Normalization-PRD.md`
  - Problem:
    - Different providers use different genre names (Thrillers vs Thriller vs Suspense)
    - iOS can't reliably filter by genre
    - Users see inconsistent genre tags on same book from different sources
  - Solution:
    - Backend normalizes all genre strings to canonical values
    - Case-insensitive matching
    - Pluralization handling (Thrillers → Thriller)
    - Unknown genres pass through unchanged (preserve data)
  - User Stories:
    - As a user, I want consistent genre tags so filtering works reliably
    - As a developer, I want canonical genres so I can build genre-based features
  - Success Metrics:
    - 100% of known genres normalized (Fiction → Fiction, not fiction/FICTION)
    - Zero data loss (unknown genres preserved)
    - Genre normalization runs on all /v1/* endpoints
  - Technical Implementation:
    - Service: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`
    - Canonical map: `CANONICAL_GENRES` constant
    - Applied in: `normalizeGoogleBooksToWork`, all v1 search endpoints
  - Decision Log:
    - [Oct 28, 2025] **Decision:** Backend normalization over iOS. **Rationale:** Single source of truth, consistent across all clients.
    - [Oct 28, 2025] **Decision:** Pass-through for unknown genres. **Rationale:** Preserve data, allow genre discovery, avoid false negatives.
  - Future Enhancements:
    - Expand canonical map with more genres (current: ~30 common genres)
    - Add genre hierarchy (Fiction > Mystery > Detective)
- [ ] Create `docs/workflows/genre-normalization-workflow.md` (Mermaid diagram)
  - Google Books returns `["Fiction", "Thrillers", "MYSTERY"]`
  - Genre normalizer applies case-insensitive matching
  - Normalizer depluralize (Thrillers → Thriller)
  - Normalizer maps to canonical values (MYSTERY → Mystery)
  - Returns `["Fiction", "Thriller", "Mystery"]`
  - Unknown genres pass through unchanged
- [ ] Update CLAUDE.md backend section
  - Add genre normalization mention under canonical contracts
  - Reference PRD: `See docs/product/Genre-Normalization-PRD.md`

**Deliverables:**
- `docs/product/Genre-Normalization-PRD.md`
- `docs/workflows/genre-normalization-workflow.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, workflow exists, CLAUDE.md references PRD.

---

#### Task 2.4: DTOMapper Integration (30 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*mapper* docs/product/*dto*

# Does workflow exist?
ls docs/workflows/*mapper*

# Is DTOMapper mentioned in CLAUDE.md?
grep -i "dtomapper" CLAUDE.md
```

**Expected Gap:** Missing PRD (code exists, no user-facing doc)

**Action Items:**
- [ ] Create `docs/product/DTOMapper-PRD.md`
  - Problem:
    - iOS receives canonical DTOs from /v1/* endpoints
    - Need to convert DTOs to SwiftData models (Work, Edition, Author)
    - Need to deduplicate synthetic works (multiple editions → single work)
  - Solution:
    - DTOMapper service converts canonical DTOs to SwiftData models
    - Deduplication by ISBN (multiple EditionDTOs → single Work)
    - Insert-before-relate lifecycle compliance
    - Genre normalization flows to SwiftData models
  - User Stories:
    - As a developer, I want automatic DTO-to-model conversion so I don't write repetitive parsing code
    - As a user, I want duplicate books merged so my library stays clean
  - Success Metrics:
    - Zero manual DTO parsing in search/enrichment services
    - 100% deduplication success (5 editions → 1 work with 5 editions)
    - Genre normalization preserved in SwiftData models
  - Technical Implementation:
    - Service: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`
    - Methods: `mapToWorks()`, `deduplicateSyntheticWorks()`, `insertAuthors()`
    - Insert-before-relate pattern enforced
    - Used in: SearchViewModel, EnrichmentService, BookshelfScannerService
  - Decision Log:
    - [Oct 29, 2025] **Decision:** Single DTOMapper class. **Rationale:** Centralize conversion logic, easier to test, consistent insert-before-relate enforcement.
    - [Oct 29, 2025] **Decision:** Deduplicate by ISBN. **Rationale:** Most reliable unique identifier for editions, handles synthetic works from Google Books.
  - Future Enhancements:
    - Add provenance tracking to SwiftData models (store primaryProvider field)
    - Improve deduplication with fuzzy title matching (handle typos)
- [ ] Create `docs/workflows/dtomapper-workflow.md` (Mermaid diagram)
  - iOS receives `/v1/search/title` response with WorkDTO[], EditionDTO[], AuthorDTO[]
  - DTOMapper.mapToWorks() called with ModelContext
  - For each WorkDTO:
    - Create Work model, insert immediately (gets permanent ID)
    - Create Author models, insert immediately
    - Create Edition models, insert immediately
    - Set relationships (work.authors = [...], work.editions = [...])
  - Deduplication step:
    - Group works by ISBN
    - Merge editions into single work
    - Delete duplicate works
  - Return Work[]
- [ ] Update CLAUDE.md
  - Add DTOMapper to Architecture section
  - Reference PRD: `See docs/product/DTOMapper-PRD.md`

**Deliverables:**
- `docs/product/DTOMapper-PRD.md`
- `docs/workflows/dtomapper-workflow.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, workflow exists, CLAUDE.md references PRD.

---

### Category B: Core User Workflows (Priority 2)

**Time Allocation:** 20-30 min per feature

---

#### Task 2.5: Search (Title/ISBN/Advanced) (30 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*search*

# Does workflow exist?
ls docs/workflows/*search*

# What does CLAUDE.md say?
grep -A 10 "Search" CLAUDE.md
```

**Expected Gap:** PRD might exist but likely outdated (pre-canonical contracts)

**Action Items:**
- [ ] Check existing PRD (if exists)
  - If references old endpoints: Update to /v1/* endpoints
  - If missing canonical contracts section: Add it
  - If missing decision log: Add it
- [ ] If no PRD exists, create `docs/product/Search-PRD.md`
  - Problem: Users need to find books by title, author, ISBN
  - Solution: Multi-mode search (title, ISBN, advanced) with canonical backend
  - User Stories:
    - As a user, I want to search by title so I can find books quickly
    - As a user, I want to search by ISBN so I can add exact editions
    - As a user, I want to search by author so I can discover their works
  - Success Metrics:
    - Search results appear in <2s for cached queries
    - 95% search success rate (non-empty results)
    - Zero crashes from malformed ISBNs
  - Technical Implementation:
    - iOS: SearchView.swift, SearchModel.swift
    - Backend: /v1/search/title, /v1/search/isbn, /v1/search/advanced
    - DTOMapper converts responses to SwiftData models
  - Decision Log:
    - [Oct 29, 2025] **Decision:** Migrate to /v1/* endpoints. **Rationale:** Canonical contracts ensure consistent data structure, genre normalization built-in.
- [ ] Update/create workflow diagram `docs/workflows/search-workflow.md`
  - Title search flow (User → iOS → /v1/search/title → Google Books → Normalize → iOS)
  - ISBN search flow (User → Barcode Scanner → /v1/search/isbn → Validate → Normalize → iOS)
  - Advanced search flow (Title + Author filters)
  - Error handling (invalid ISBN, no results, provider failure)
- [ ] Update CLAUDE.md
  - Verify V1 Endpoints section is accurate
  - Reference PRD and workflow

**Deliverables:**
- `docs/product/Search-PRD.md` (new or updated)
- `docs/workflows/search-workflow.md` (new or updated)
- Updated CLAUDE.md

**Completion Check:** PRD current, workflow current, no references to legacy endpoints.

---

#### Task 2.6: Gemini CSV Import (25 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*csv*

# Does feature doc exist?
ls docs/features/GEMINI_CSV_IMPORT.md

# Does workflow exist?
ls docs/workflows/*csv*
```

**Expected Gap:** Feature doc exists, PRD might be missing or outdated

**Action Items:**
- [ ] Check existing PRD (if exists)
  - If references old inline enrichment: Update to unified enrichment pipeline
  - If missing decision log: Add it
- [ ] If no PRD exists, create `docs/product/Gemini-CSV-Import-PRD.md`
  - Problem: Users have CSV exports from Goodreads/Library Thing, manual entry is tedious
  - Solution: AI-powered CSV parsing with Gemini 2.0 Flash, zero configuration
  - User Stories:
    - As a user, I want to import my Goodreads CSV so I can migrate to BooksTrack
    - As a user, I want zero column mapping so import is simple
    - As a user, I want background enrichment so books appear instantly
  - Success Metrics:
    - Parse CSV in 5-15s (Gemini inference time)
    - Books appear in library in <20s (parse + save, enrichment runs in background)
    - 95% parsing accuracy (correct title, author, ISBN detection)
  - Technical Implementation:
    - iOS: CSVImportService.swift
    - Backend: /api/import/csv-gemini, Gemini 2.0 Flash API
    - Unified enrichment: EnrichmentQueue handles background enrichment
    - WebSocket progress: Parsing phase only (enrichment is async)
  - Decision Log:
    - [Oct 2025] **Decision:** Gemini over manual column mapping. **Rationale:** Zero config UX, handles arbitrary CSV formats.
    - [Oct 2025] **Decision:** Unified enrichment pipeline. **Rationale:** Consistent behavior across all import sources (CSV, bookshelf, manual add).
    - [Oct 2025] **Decision:** Immediate save, background enrichment. **Rationale:** Books appear in 12-17s instead of 60-120s.
- [ ] Create workflow diagram `docs/workflows/csv-import-workflow.md`
  - User selects CSV file
  - iOS uploads to /api/import/csv-gemini
  - Worker calls Gemini API with CSV content
  - Gemini returns structured JSON (title, author, ISBN per row)
  - Worker validates and returns to iOS
  - iOS saves books to SwiftData with minimal metadata
  - EnrichmentQueue triggers background enrichment
  - WebSocket reports parsing progress only
  - User sees books in library immediately
- [ ] Update CLAUDE.md
  - Verify feature description is accurate
  - Reference PRD and workflow
  - Reference feature doc: `docs/features/GEMINI_CSV_IMPORT.md`

**Deliverables:**
- `docs/product/Gemini-CSV-Import-PRD.md` (new or updated)
- `docs/workflows/csv-import-workflow.md`
- Updated CLAUDE.md

**Completion Check:** PRD current, workflow current, references unified enrichment pipeline.

---

#### Task 2.7: Bookshelf Scanner (Single + Batch) (30 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*bookshelf* docs/product/*scanner*

# Does feature doc exist?
ls docs/features/BOOKSHELF_SCANNER.md docs/features/BATCH_BOOKSHELF_SCANNING.md

# Does workflow exist?
ls docs/workflows/*bookshelf* docs/workflows/*batch*
```

**Expected Gap:** Feature docs exist, PRD likely missing

**Action Items:**
- [ ] Create `docs/product/Bookshelf-Scanner-PRD.md`
  - Problem: Users have large book collections, manual entry is slow
  - Solution: AI-powered bookshelf scanning with Gemini 2.0 Flash, single or batch mode
  - User Stories:
    - As a user, I want to scan my bookshelf photo so I can add many books at once
    - As a user, I want to scan multiple shelves so I can catalog my entire collection
    - As a user, I want real-time progress so I know how long to wait
    - As a user, I want to review low-confidence detections so AI mistakes don't corrupt my library
  - Success Metrics:
    - Single photo: 25-40s processing time (AI inference + enrichment)
    - Batch: 5 photos in <3 minutes (parallel upload, sequential processing)
    - 70%+ detection confidence for automatic addition
    - <60% detections go to review queue (zero false positives)
  - Technical Implementation:
    - iOS: BookshelfScannerService.swift, BatchBookshelfScannerService.swift
    - Backend: /api/scan-bookshelf, /api/scan-bookshelf/batch
    - AI: Gemini 2.0 Flash (2M token context, optimized for ISBN detection)
    - WebSocket: Real-time progress via ProgressWebSocketDO
    - Review Queue: CorrectionView for low-confidence detections
  - Decision Log:
    - [Oct 2025] **Decision:** Gemini 2.0 Flash over Cloudflare Workers AI. **Rationale:** 2M token context (vs 8K-128K), handles 4-5MB images, better accuracy.
    - [Oct 2025] **Decision:** 60% confidence threshold. **Rationale:** Balances automation (high-confidence auto-add) with accuracy (low-confidence review).
    - [Oct 2025] **Decision:** Parallel upload, sequential processing. **Rationale:** Fast UX (uploads in <5s), reliable AI results (no rate limiting).
  - Future Enhancements:
    - Increase batch limit to 10 photos
    - Add manual ISBN correction in review queue (currently only shows detected ISBN)
- [ ] Create workflow diagram `docs/workflows/bookshelf-scanner-workflow.md`
  - Single photo flow: Capture → Preprocess → Upload → Gemini inference → Enrichment → WebSocket updates
  - Batch flow: Capture 5 photos → Parallel upload → Sequential Gemini processing → Per-photo progress → Deduplication → Review queue
  - Error handling: Invalid photo, AI timeout, enrichment failure
- [ ] Update CLAUDE.md
  - Verify feature descriptions are accurate
  - Reference PRD and workflow
  - Reference feature docs: `BOOKSHELF_SCANNER.md`, `BATCH_BOOKSHELF_SCANNING.md`

**Deliverables:**
- `docs/product/Bookshelf-Scanner-PRD.md`
- `docs/workflows/bookshelf-scanner-workflow.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, workflow exists, references both single and batch modes.

---

#### Task 2.8: Enrichment Pipeline (25 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*enrich*

# Does workflow exist?
ls docs/workflows/*enrich*

# Is enrichment documented in CLAUDE.md?
grep -i "enrich" CLAUDE.md
```

**Expected Gap:** PRD likely missing (implicit feature, no standalone doc)

**Action Items:**
- [ ] Create `docs/product/Enrichment-Pipeline-PRD.md`
  - Problem:
    - Books imported with minimal metadata (title, author only)
    - Users want full metadata (cover, genres, publisher, description)
    - Fetching metadata inline blocks user (60-120s wait)
  - Solution:
    - Background enrichment queue
    - Books saved with minimal metadata, appear instantly in library
    - EnrichmentQueue fetches full metadata asynchronously
    - WebSocket progress for long-running enrichment jobs
  - User Stories:
    - As a user, I want books to appear in my library immediately so I don't wait for enrichment
    - As a user, I want covers and genres to load in background so I can keep browsing
    - As a developer, I want unified enrichment logic so CSV/bookshelf/manual add all behave consistently
  - Success Metrics:
    - Books appear in library in <20s (save + minimal enrichment)
    - Full enrichment completes in background (1-5 min depending on batch size)
    - Zero blocking UI during enrichment
  - Technical Implementation:
    - iOS: EnrichmentQueue.swift (singleton)
    - Backend: /api/enrichment/start (batch enrichment with WebSocket)
    - Used by: CSV import, bookshelf scanner, manual add
    - WebSocket: Real-time progress via ProgressWebSocketDO
  - Decision Log:
    - [Oct 2025] **Decision:** Background enrichment over inline. **Rationale:** Better UX (books appear instantly), consistent behavior across all import sources.
    - [Oct 2025] **Decision:** Singleton EnrichmentQueue. **Rationale:** Centralize job tracking, prevent duplicate enrichment requests.
  - Future Enhancements:
    - Retry failed enrichment automatically
    - Add manual "Enrich Now" button for individual books
- [ ] Create workflow diagram `docs/workflows/enrichment-workflow.md`
  - User imports books (CSV, bookshelf, manual)
  - iOS saves books to SwiftData with minimal metadata (title, author, ISBN)
  - EnrichmentQueue triggers background enrichment
  - POST /api/enrichment/start with ISBN list
  - Worker fetches metadata from Google Books, OpenLibrary
  - Worker sends WebSocket progress updates (book 1/10, book 2/10, ...)
  - iOS receives updates, refreshes UI
  - Enrichment completes, books have full metadata
- [ ] Update CLAUDE.md
  - Add enrichment section to Backend Architecture
  - Reference PRD and workflow

**Deliverables:**
- `docs/product/Enrichment-Pipeline-PRD.md`
- `docs/workflows/enrichment-workflow.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, workflow exists, CLAUDE.md references PRD.

---

### Category C: Supporting Features (Priority 3)

**Time Allocation:** 15-20 min per feature

---

#### Task 2.9: Settings (Themes, AI Provider, Feature Flags) (20 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*settings* docs/product/*theme*

# Does workflow exist?
ls docs/workflows/*settings*
```

**Expected Gap:** PRD likely missing (implicit feature)

**Action Items:**
- [ ] Create `docs/product/Settings-PRD.md`
  - Problem: Users want to customize app (themes, AI provider, experimental features)
  - Solution: Settings sheet accessible from Library tab toolbar
  - User Stories:
    - As a user, I want to change app theme so it matches my aesthetic
    - As a user, I want to choose AI provider so I can optimize for speed/accuracy
    - As a user, I want to enable beta features so I can try new functionality
  - Success Metrics:
    - Settings accessible in <2 taps (Library → Gear icon)
    - Theme changes apply immediately (no restart)
    - Feature flags respected throughout app
  - Technical Implementation:
    - iOS: SettingsView.swift, iOS26ThemeStore.swift
    - 5 built-in themes: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
    - AI provider toggle: Gemini (default)
    - Feature flags: Experimental barcode scanner, batch upload limits
  - Decision Log:
    - [Oct 2025] **Decision:** Settings in Library tab toolbar. **Rationale:** iOS 26 HIG recommends 4-tab maximum, gear icon follows Books.app pattern.
- [ ] Create workflow diagram `docs/workflows/settings-workflow.md` (optional, simple feature)
- [ ] Update CLAUDE.md
  - Verify Settings Access section is accurate
  - Reference PRD

**Deliverables:**
- `docs/product/Settings-PRD.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, CLAUDE.md references PRD.

---

#### Task 2.10: CloudKit Sync (20 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*cloudkit* docs/product/*sync*

# Does workflow exist?
ls docs/workflows/*cloudkit* docs/workflows/*sync*
```

**Expected Gap:** PRD likely missing (SwiftData feature, no standalone doc)

**Action Items:**
- [ ] Create `docs/product/CloudKit-Sync-PRD.md`
  - Problem: Users have multiple devices (iPhone, iPad), want library synced
  - Solution: SwiftData CloudKit sync (automatic, zero configuration)
  - User Stories:
    - As a user, I want my library synced across devices so I can switch between iPhone/iPad
    - As a user, I want zero setup so sync just works
  - Success Metrics:
    - Changes sync within 5-10s (network permitting)
    - Zero data loss during sync conflicts
    - Sync works without user intervention
  - Technical Implementation:
    - SwiftData CloudKit integration (modelContainer configured in App.swift)
    - Inverse relationships declared correctly (to-many side only)
    - All attributes have defaults (CloudKit requirement)
    - All relationships optional (CloudKit requirement)
  - Decision Log:
    - [Oct 2025] **Decision:** SwiftData CloudKit over manual sync. **Rationale:** Zero maintenance, Apple handles conflicts, free for users.
  - Limitations:
    - Predicates can't filter on to-many relationships (filter in-memory)
    - Temporary IDs break relationships (must insert before relating)
- [ ] Create workflow diagram `docs/workflows/cloudkit-sync-workflow.md` (optional)
- [ ] Update CLAUDE.md
  - Verify CloudKit Rules section is accurate
  - Reference PRD

**Deliverables:**
- `docs/product/CloudKit-Sync-PRD.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, CLAUDE.md references PRD, CloudKit rules documented.

---

#### Task 2.11: Review Queue (15 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*review*

# Does feature doc exist?
ls docs/features/REVIEW_QUEUE.md

# Does workflow exist?
ls docs/workflows/*review*
```

**Expected Gap:** Feature doc exists, PRD likely missing

**Action Items:**
- [ ] Create `docs/product/Review-Queue-PRD.md`
  - Problem: AI detections <60% confidence might be wrong, users want to verify
  - Solution: Review queue with spine image cropping, manual correction
  - User Stories:
    - As a user, I want to review low-confidence detections so AI mistakes don't corrupt my library
    - As a user, I want to see the spine image so I can verify the detection
  - Success Metrics:
    - Review queue shows all <60% confidence detections
    - Users can accept/reject/correct detections
    - Temp files cleaned up after review
  - Technical Implementation:
    - iOS: CorrectionView.swift, ReviewQueueService.swift
    - Automatic temp file cleanup
    - Spine image cropping for visual verification
  - Decision Log:
    - [Oct 2025] **Decision:** 60% threshold. **Rationale:** Balances automation with accuracy.
- [ ] Update CLAUDE.md
  - Reference PRD and feature doc

**Deliverables:**
- `docs/product/Review-Queue-PRD.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, references feature doc.

---

#### Task 2.12: Library Reset (15 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*reset* docs/product/*library*
```

**Expected Gap:** PRD likely missing (utility feature)

**Action Items:**
- [ ] Create `docs/product/Library-Reset-PRD.md`
  - Problem: Users want to start fresh, developers need to clear test data
  - Solution: Comprehensive reset (SwiftData, enrichment queue, backend jobs, feature flags)
  - User Stories:
    - As a user, I want to reset my library so I can start over
    - As a developer, I want to clear test data so I can validate features cleanly
  - Success Metrics:
    - Reset completes in <2s
    - All data cleared (SwiftData, enrichment queue, search history)
    - Backend jobs canceled to prevent resource waste
  - Technical Implementation:
    - iOS: SettingsView.swift, EnrichmentQueue.cancelBackendJob()
    - Backend: /api/enrichment/cancel, ProgressWebSocketDO.cancelJob()
    - Deletes: Works, Editions, Authors, UserLibraryEntries
    - Clears: Enrichment queue, search history, feature flags
  - Decision Log:
    - [Oct 2025] **Decision:** Cancel backend jobs. **Rationale:** Prevent resource waste, avoid orphaned enrichment jobs.
- [ ] Update CLAUDE.md
  - Verify Library Reset section is accurate
  - Reference PRD

**Deliverables:**
- `docs/product/Library-Reset-PRD.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, CLAUDE.md references PRD, backend cancellation documented.

---

### Category D: Analytics & Insights (Priority 4)

**Time Allocation:** 20-30 min per feature

---

#### Task 2.13: Diversity Insights (25 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*diversity* docs/product/*insights*

# Does workflow exist?
ls docs/workflows/*diversity* docs/workflows/*insights*
```

**Expected Gap:** PRD likely missing (analytics feature)

**Action Items:**
- [ ] Create `docs/product/Diversity-Insights-PRD.md`
  - Problem: Users want to understand diversity in their reading habits
  - Solution: Author gender, cultural region, marginalized voice analytics
  - User Stories:
    - As a user, I want to see author gender distribution so I can diversify my reading
    - As a user, I want to see cultural region representation so I can read globally
  - Success Metrics:
    - Analytics update in real-time as library changes
    - Charts render in <1s
    - Accurate categorization (manual override available)
  - Technical Implementation:
    - iOS: InsightsView.swift, DiversityAnalyticsService.swift
    - Author metadata: AuthorGender, CulturalRegion, Marginalized Voice
    - Aggregation logic: Count by category, percentage calculation
  - Decision Log:
    - [Oct 2025] **Decision:** Manual categorization. **Rationale:** AI detection unreliable for sensitive categories.
- [ ] Create workflow diagram `docs/workflows/diversity-insights-workflow.md`
- [ ] Update CLAUDE.md
  - Verify Cultural Diversity section is accurate
  - Reference PRD

**Deliverables:**
- `docs/product/Diversity-Insights-PRD.md`
- `docs/workflows/diversity-insights-workflow.md` (optional)
- Updated CLAUDE.md

**Completion Check:** PRD exists, CLAUDE.md references PRD.

---

#### Task 2.14: Reading Statistics (20 min)

**Current State Check:**
```bash
# Does PRD exist?
ls docs/product/*statistics* docs/product/*reading*
```

**Expected Gap:** PRD likely missing (analytics feature)

**Action Items:**
- [ ] Create `docs/product/Reading-Statistics-PRD.md`
  - Problem: Users want to track reading progress and habits
  - Solution: Reading status tracking, completion metrics, page progress
  - User Stories:
    - As a user, I want to see how many books I've read this year
    - As a user, I want to track my current reading progress
  - Success Metrics:
    - Statistics update in real-time
    - Accurate completion tracking
  - Technical Implementation:
    - iOS: InsightsView.swift, ReadingStatisticsService.swift
    - UserLibraryEntry: status (wishlist, toRead, reading, read), currentPage, completionDate
  - Decision Log:
    - [Oct 2025] **Decision:** Manual status updates. **Rationale:** User controls reading state, no automatic completion detection.
- [ ] Update CLAUDE.md
  - Verify Reading Status section is accurate
  - Reference PRD

**Deliverables:**
- `docs/product/Reading-Statistics-PRD.md`
- Updated CLAUDE.md

**Completion Check:** PRD exists, CLAUDE.md references PRD.

---

## Phase 3: Cross-Reference Validation (30 min)

**Goal:** Ensure all PRDs, workflows, and CLAUDE.md are consistent.

### Task 3.1: Validate PRD ↔ Workflow Links (15 min)

**Action Items:**
- [ ] For each PRD in `docs/product/`:
  - Verify it links to corresponding workflow in `docs/workflows/`
  - Verify workflow links back to PRD
  - Fix broken links

**Script (optional):**
```bash
# Check for broken cross-references
for prd in docs/product/*.md; do
  echo "Checking $prd..."
  grep -q "docs/workflows/" "$prd" || echo "  WARNING: No workflow reference"
done

for workflow in docs/workflows/*.md; do
  echo "Checking $workflow..."
  grep -q "docs/product/" "$workflow" || echo "  WARNING: No PRD reference"
done
```

**Deliverable:** All PRDs and workflows have bidirectional links.

---

### Task 3.2: Validate CLAUDE.md References (15 min)

**Action Items:**
- [ ] For each feature in CLAUDE.md:
  - Verify it references correct PRD path
  - Verify it references correct workflow path (if applicable)
  - Fix outdated references

**Script (optional):**
```bash
# Extract PRD references from CLAUDE.md
grep -E "docs/(product|workflows)/" CLAUDE.md

# Verify each referenced file exists
# (manual check or script)
```

**Deliverable:** CLAUDE.md references all current PRDs and workflows.

---

## Phase 4: Audit Summary & Cleanup (45 min)

**Goal:** Document what we changed and establish future prevention measures.

### Task 4.1: Create Audit Summary Report (30 min)

**Action Items:**
- [ ] Create `docs/audit-2025-10-31-summary.md`
  - List all PRDs created (with filenames)
  - List all PRDs updated (with sections changed)
  - List all workflow diagrams created
  - List all CLAUDE.md updates
  - Count of gaps found and fixed
  - Recommendations for future prevention

**Template:**
```markdown
# PRD Documentation Audit Summary

**Date:** October 31, 2025
**Duration:** [X hours]
**Executor:** [Name]

## Changes Made

### New PRDs Created
- `docs/product/VisionKit-Barcode-Scanner-PRD.md`
- `docs/product/Canonical-Data-Contracts-PRD.md`
- [list all]

### PRDs Updated
- `docs/product/Search-PRD.md`
  - Updated Technical Implementation (canonical contracts)
  - Added Decision Log
- [list all]

### New Workflow Diagrams Created
- `docs/workflows/barcode-scanner-workflow.md`
- `docs/workflows/canonical-contracts-workflow.md`
- [list all]

### CLAUDE.md Updates
- Added PRD references to all features
- Removed AVFoundation references (deprecated)
- Updated implementation status checkboxes

## Gaps Found & Fixed

- **Missing PRDs:** 8 features had no PRDs (now all documented)
- **Outdated PRDs:** 3 PRDs referenced deprecated tech (now updated)
- **Missing Workflows:** 6 features had no workflow diagrams (now created)
- **Broken Cross-References:** 4 links were outdated (now fixed)

## Quality Metrics

- ✅ Zero production features without PRDs
- ✅ Zero PRDs without workflow diagrams
- ✅ Zero references to AVFoundation (replaced by VisionKit)
- ✅ Zero references to old API endpoints (pre-canonical contracts)
- ✅ 100% of PRDs include Decision Log sections
- ✅ All PRDs have "Last Updated" timestamps

## Recommendations for Future Prevention

1. **PRD-First Development**
   - Create/update PRD BEFORE starting implementation
   - Include PRD link in PR descriptions
   - Add "PRD updated?" to PR review checklist

2. **Regular Audits**
   - Quarterly documentation review (lighter version of this audit)
   - Tag PRDs with "last-reviewed" date
   - Archive PRDs for removed features

3. **Documentation CI Check** (future automation)
   - Script to detect features in CLAUDE.md without PRDs
   - Warn if PRD modified date is >3 months old
   - Flag TODOs in PRDs that reference completed work

## Lessons Learned

- [Add reflections on the audit process]
- [What worked well?]
- [What could be improved?]

---

**Audit Status:** ✅ Complete
**Next Steps:** Commit all changes, share summary with team
```

**Deliverable:** `docs/audit-2025-10-31-summary.md`

---

### Task 4.2: Cleanup & Final Verification (15 min)

**Action Items:**
- [ ] Delete inventory file (temporary artifact): `docs/audit-2025-10-31-inventory.md`
- [ ] Run final validation script:
  ```bash
  # Check for broken links
  for prd in docs/product/*.md; do
    grep -oE 'docs/(product|workflows)/[^)]+' "$prd" | while read link; do
      [ -f "$link" ] || echo "BROKEN LINK: $prd -> $link"
    done
  done

  # Check for deprecated tech references
  grep -r "AVFoundation" docs/product/ docs/workflows/ CLAUDE.md | grep -v "deprecated" | grep -v "removed"

  # Check for old API endpoint references
  grep -rE "/(search|api)/" docs/product/ docs/workflows/ | grep -v "/v1/" | grep -v "legacy"
  ```
- [ ] Fix any issues found
- [ ] Final quality gate: All success criteria met (Phase 2 completion checks)

**Deliverable:** Zero broken links, zero deprecated references.

---

## Phase 5: Commit & Review (15 min)

**Goal:** Commit all changes with clear messages.

### Task 5.1: Commit PRD Changes (10 min)

**Action Items:**
- [ ] Stage all new/updated PRD files:
  ```bash
  git add docs/product/*.md
  git commit -m "docs: add PRDs for VisionKit, canonical contracts, genre normalization, DTOMapper"
  ```
- [ ] Stage all new/updated workflow diagrams:
  ```bash
  git add docs/workflows/*.md
  git commit -m "docs: add workflow diagrams for barcode scanner, canonical contracts, CSV import, bookshelf scanner"
  ```
- [ ] Stage CLAUDE.md updates:
  ```bash
  git add CLAUDE.md
  git commit -m "docs: update CLAUDE.md with PRD references, remove deprecated tech mentions"
  ```
- [ ] Stage audit summary:
  ```bash
  git add docs/audit-2025-10-31-summary.md
  git commit -m "docs: add PRD audit summary report"
  ```

**Deliverable:** All changes committed with descriptive messages.

---

### Task 5.2: Final Review (5 min)

**Action Items:**
- [ ] Review git log to ensure commits are clean:
  ```bash
  git log --oneline -10
  ```
- [ ] Review changed files to ensure no accidental changes:
  ```bash
  git diff HEAD~4 HEAD --stat
  ```
- [ ] Push changes (if ready):
  ```bash
  git push origin main
  ```

**Deliverable:** All changes pushed to main branch.

---

## Success Criteria (Final Checklist)

Before marking this plan complete, verify:

- ✅ All production features have PRDs in `docs/product/`
- ✅ All PRDs have corresponding workflow diagrams in `docs/workflows/`
- ✅ All PRDs include Decision Log sections
- ✅ Zero references to AVFoundation (except deprecation notes)
- ✅ Zero references to old API endpoints (except legacy section in CLAUDE.md)
- ✅ All PRDs have "Last Updated: YYYY-MM-DD" timestamps
- ✅ CLAUDE.md references all current PRDs and workflows
- ✅ Audit summary report created and committed
- ✅ All changes committed with descriptive messages
- ✅ Zero broken cross-references (PRD ↔ Workflow ↔ CLAUDE.md)

---

## Timeline Summary

**Phase 1: Inventory (15 min)**
- Scan existing docs, build master list

**Phase 2: Feature-by-Feature Audit (3-4 hours)**
- Category A: Recently Changed (4 features × 35 min = 140 min)
- Category B: Core Workflows (4 features × 25 min = 100 min)
- Category C: Supporting (5 features × 17 min = 85 min)
- Category D: Analytics (2 features × 22 min = 44 min)
- **Total: ~6 hours (accounting for context switching)**

**Phase 3: Cross-Reference Validation (30 min)**
- Validate links, fix broken references

**Phase 4: Audit Summary (45 min)**
- Create summary report, cleanup, final verification

**Phase 5: Commit & Review (15 min)**
- Commit all changes, push to main

**Grand Total: ~7.5 hours** (includes breaks, context switching)

---

## Notes for Executor

**Mental Model:**
- This is NOT a batch report generation task
- This is an interactive audit + fix session
- Fix gaps immediately as you find them
- Don't defer documentation updates for later

**Common Pitfalls:**
- Skipping Decision Log sections (these are critical for actionability!)
- Creating workflow diagrams without error paths (always show failure cases)
- Copying old PRD content without verifying against current code
- Forgetting to update CLAUDE.md references

**Quality Over Speed:**
- Take time to make PRDs actionable (WHY built, WHO uses, WHAT success looks like)
- Decision Logs should explain technical choices, not just list them
- Workflow diagrams should reflect actual code paths, not ideal architecture

**When in Doubt:**
- Check actual code implementation (don't guess from memory)
- Reference recent git commits for decision context
- Look at GitHub issues for user pain points
- Verify caching layers, error handling, WebSocket flows in workflows

---

**Plan Status:** ✅ Ready for Execution
**Next Step:** Begin Phase 1 (Inventory Current State)
