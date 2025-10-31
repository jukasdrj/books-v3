# PRD Documentation Audit - Inventory

**Date:** October 31, 2025
**Purpose:** Master checklist of existing documentation and gaps

---

## Existing PRDs (Last Modified Date)

- [ ] Bookshelf-Scanner-PRD.md - Oct 25 22:10
- [ ] Diversity-Insights-PRD.md - Oct 27 19:45
- [ ] Gemini-CSV-Import-PRD.md - Oct 27 19:43
- [ ] Review-Queue-PRD.md - Oct 25 22:07
- [x] PRD-Template.md - Oct 25 21:43 (template only)

**Count:** 4 production PRDs + 1 template

---

## Existing Workflows

- [ ] bookshelf-scanner-workflow.md - Oct 25 21:39
- [ ] csv-import-workflow.md - Oct 27 19:33
- [ ] enrichment-workflow.md - Oct 27 19:34
- [ ] search-workflow.md - Oct 27 19:32

**Count:** 4 workflow diagrams

---

## Features Mentioned in CLAUDE.md

### Explicitly Documented Features
1. **Bookshelf AI Scanner** - Has PRD ✅, Has Workflow ✅
   - Reference: `docs/features/BOOKSHELF_SCANNER.md`

2. **Batch Bookshelf Scanning** - Needs PRD ❌ (covered by Bookshelf Scanner PRD?)
   - Reference: `docs/features/BATCH_BOOKSHELF_SCANNING.md`

3. **Gemini CSV Import** - Has PRD ✅, Has Workflow ✅
   - Reference: `docs/features/GEMINI_CSV_IMPORT.md`
   - Unified Enrichment Pipeline mentioned

4. **Review Queue** - Has PRD ✅, Needs Workflow ❌
   - Reference: `docs/features/REVIEW_QUEUE.md`

### Infrastructure/Backend Features in CLAUDE.md

5. **Canonical Data Contracts (v1.0.0)** - Needs PRD ❌, Needs Workflow ❌
   - WorkDTO, EditionDTO, AuthorDTO
   - V1 Endpoints: `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`
   - Design doc: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
   - Implementation doc: `docs/plans/2025-10-29-canonical-data-contracts-implementation.md`

6. **Genre Normalization Service** - Needs PRD ❌, Needs Workflow ❌
   - Backend service: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`

7. **DTOMapper Integration** - Needs PRD ❌, Needs Workflow ❌
   - iOS service: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`

8. **Enrichment Pipeline** - Has Workflow ✅, Needs PRD ❌
   - EnrichmentQueue, background enrichment
   - Unified across CSV/bookshelf/manual add

9. **Search (Title/ISBN/Advanced)** - Has Workflow ✅, Needs PRD ❌
   - SearchView.swift, SearchModel.swift
   - Legacy and V1 endpoints

### UI/UX Features

10. **VisionKit Barcode Scanner** - Needs PRD ❌, Needs Workflow ❌
    - Replaced AVFoundation implementation (Oct 30, 2025)
    - Design doc: `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md`
    - Implementation doc: `docs/plans/2025-10-30-visionkit-barcode-scanner-implementation.md`
    - ISBNScannerView.swift

11. **Settings** - Needs PRD ❌, Needs Workflow ❌
    - Theme selection, AI provider, feature flags
    - SettingsView.swift, iOS26ThemeStore.swift

12. **CloudKit Sync** - Needs PRD ❌, Needs Workflow ❌
    - SwiftData CloudKit integration
    - Zero-config sync

13. **Library Reset** - Needs PRD ❌, Needs Workflow ❌
    - Comprehensive reset (SwiftData, enrichment queue, backend jobs)
    - Backend cancellation flow

### Analytics Features

14. **Diversity Insights** - Has PRD ✅, Needs Workflow ❌
    - Author gender, cultural region, marginalized voice
    - InsightsView.swift, DiversityAnalyticsService.swift

15. **Reading Statistics** - Needs PRD ❌, Needs Workflow ❌
    - Reading status tracking (wishlist, toRead, reading, read)
    - Completion metrics, page progress

---

## Recent Code Changes (Last 2 Weeks)

### Major Feature Work Detected

1. **VisionKit Barcode Scanner**
   - ISBNScannerView.swift
   - Archived: BarcodeDetectionService.swift, CameraManager.swift, ModernCameraPreview.swift

2. **Canonical Contracts Implementation**
   - DTOs: WorkDTO.swift, EditionDTO.swift, AuthorDTO.swift, ResponseEnvelope.swift, DTOEnums.swift
   - DTOMapper.swift
   - Backend: canonical.ts, enums.ts, responses.ts, genre-normalizer.ts
   - V1 handlers: search-title.ts, search-isbn.ts, search-advanced.ts
   - Normalizers: google-books.ts

3. **Search Functionality**
   - SearchView.swift, SearchModel.swift, SearchViewState.swift
   - BookSearchAPIService.swift, SearchAPIService.swift

4. **Enrichment & CSV Import**
   - EnrichmentQueue.swift, EnrichmentService.swift
   - GeminiCSVImportService.swift, GeminiCSVImportView.swift
   - CSVImportService.swift, CSVParsingActor.swift

5. **Bookshelf Scanner**
   - BookshelfScannerView.swift, BatchCaptureView.swift
   - BookshelfAIService.swift, BatchWebSocketHandler.swift
   - Camera: BookshelfCameraView.swift, BookshelfCameraViewModel.swift, BookshelfCameraSessionManager.swift

6. **Review Queue**
   - CorrectionView.swift, ReviewQueueView.swift, ReviewQueueModel.swift

7. **Insights**
   - InsightsView.swift
   - Components: CulturalRegionsChart.swift, GenderDonutChart.swift, LanguageTagCloud.swift

8. **iOS 26 Design System**
   - iOS26ThemeSystem.swift, iOS26GlassModifiers.swift
   - iOS26LiquidLibraryView.swift, iOS26AdaptiveBookCard.swift

---

## Gap Analysis Summary

### Missing PRDs (Needs Creation)
1. VisionKit Barcode Scanner
2. Canonical Data Contracts
3. Genre Normalization Service
4. DTOMapper Integration
5. Enrichment Pipeline
6. Search (Title/ISBN/Advanced)
7. Settings
8. CloudKit Sync
9. Library Reset
10. Reading Statistics
11. Batch Bookshelf Scanning (or merge with existing Bookshelf Scanner PRD)

**Total: 11 missing PRDs**

### Missing Workflows (Needs Creation)
1. VisionKit Barcode Scanner
2. Canonical Data Contracts
3. Genre Normalization
4. DTOMapper
5. Review Queue
6. Settings (optional - simple feature)
7. CloudKit Sync (optional)
8. Library Reset (optional)
9. Diversity Insights (optional)
10. Reading Statistics (optional)
11. Batch Bookshelf Scanning (or merge with existing)

**Total: 11 missing workflows** (7 high-priority, 4 optional)

### Existing Documentation to Verify/Update
1. Bookshelf-Scanner-PRD.md - Verify covers batch scanning
2. Gemini-CSV-Import-PRD.md - Verify references unified enrichment pipeline
3. Diversity-Insights-PRD.md - Verify current implementation
4. Review-Queue-PRD.md - Verify current implementation
5. search-workflow.md - Verify shows V1 endpoints
6. enrichment-workflow.md - Verify shows unified pipeline
7. CLAUDE.md - Update with PRD/workflow cross-references

---

## Priority Categorization (from Design Doc)

### Category A: Recently Changed Features (Priority 1)
- VisionKit Barcode Scanner ❌ PRD, ❌ Workflow
- Canonical Data Contracts ❌ PRD, ❌ Workflow
- Genre Normalization ❌ PRD, ❌ Workflow
- DTOMapper Integration ❌ PRD, ❌ Workflow

### Category B: Core User Workflows (Priority 2)
- Search ❌ PRD, ✅ Workflow (verify V1 endpoints)
- Gemini CSV Import ✅ PRD (verify), ✅ Workflow (verify)
- Bookshelf Scanner ✅ PRD (verify batch), ✅ Workflow (verify)
- Enrichment Pipeline ❌ PRD, ✅ Workflow (verify unified)

### Category C: Supporting Features (Priority 3)
- Settings ❌ PRD, ❌ Workflow
- CloudKit Sync ❌ PRD, ❌ Workflow
- Review Queue ✅ PRD, ❌ Workflow
- Library Reset ❌ PRD, ❌ Workflow

### Category D: Analytics & Insights (Priority 4)
- Diversity Insights ✅ PRD (verify), ❌ Workflow
- Reading Statistics ❌ PRD, ❌ Workflow

---

## Next Steps

Following the implementation plan:
1. ✅ Phase 1 Complete: Inventory created
2. 🔄 Phase 2: Feature-by-Feature Audit & Fix (start with Category A)
3. ⏳ Phase 3: Cross-Reference Validation
4. ⏳ Phase 4: Audit Summary & Cleanup
5. ⏳ Phase 5: Commit & Review

---

**Inventory Status:** ✅ Complete
**Ready for:** Phase 2 (Feature-by-Feature Audit)
