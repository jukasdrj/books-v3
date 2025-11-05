# Documentation Verification Tasks

**Created:** November 5, 2025
**Purpose:** Track accuracy verification for all active documentation after 2025-11 cleanup

## ✅ Root Documentation (4 files)

- [ ] **CLAUDE.md** - Primary development guide
  - Verify Swift 6.2 concurrency patterns current
  - Check MCP setup instructions accurate
  - Validate all slash commands listed
  - Confirm architectural patterns match current code

- [ ] **README.md** - Project overview
  - Update version numbers if stale
  - Verify feature list complete
  - Check setup instructions

- [ ] **CHANGELOG.md** - Version history
  - Ensure recent commits documented
  - Check format consistency

- [ ] **GEMINI.md** - AI provider config
  - Verify Gemini API keys/setup current
  - Check model versions (Gemini 2.0 Flash)

---

## 📐 Architecture Docs (6 files)

- [ ] **docs/architecture/2025-10-22-sendable-audit.md**
  - Verify Sendable patterns still current
  - Check against latest Swift 6.2 changes

- [ ] **docs/architecture/2025-10-26-data-model-breakdown.md**
  - Validate SwiftData model structure matches code
  - Check relationship diagrams accurate

- [ ] **docs/architecture/enrichment-service.md**
  - Verify enrichment flow matches EnrichmentService.swift
  - Check API endpoints current

- [ ] **docs/architecture/nested-types-pattern.md**
  - Confirm pattern examples match codebase usage

- [ ] **docs/architecture/SyncCoordinator-Architecture.md**
  - Verify CloudKit sync architecture current

- [ ] **docs/architecture/WEBSOCKET_ARCHITECTURE.md**
  - Check WebSocket patterns match ProgressWebSocketDO
  - Verify message formats accurate

---

## 🎯 Feature Documentation (6 files)

- [ ] **docs/features/BATCH_BOOKSHELF_SCANNING.md**
  - Test batch scan flow matches docs
  - Verify max photos limit (5)
  - Check Gemini 2.0 Flash references

- [ ] **docs/features/BOOKSHELF_SCANNER.md**
  - Verify VisionKit integration accurate
  - Check Gemini provider details
  - Validate confidence thresholds (60%)

- [ ] **docs/features/DIVERSITY_INSIGHTS.md**
  - Check diversity calculation formulas
  - Verify cultural regions list complete

- [ ] **docs/features/GEMINI_CSV_IMPORT.md**
  - **CRITICAL:** Update with UserLibraryEntry fix (commit 086384b)
  - Verify unified enrichment pipeline docs
  - Check WebSocket message formats

- [ ] **docs/features/REVIEW_QUEUE.md**
  - Verify review queue UI patterns
  - Check low-confidence handling (< 60%)

- [ ] **docs/features/WEBSOCKET_FALLBACK_ARCHITECTURE.md**
  - Validate fallback polling patterns
  - Check timeout values

---

## 📚 Product Requirements (14 PRDs)

- [ ] **docs/product/Bookshelf-Scanner-PRD.md**
  - Success metrics still relevant?
  - User stories match current UX

- [ ] **docs/product/Canonical-Data-Contracts-PRD.md**
  - Verify canonical DTO schemas current
  - Check `/v1/*` endpoint docs

- [ ] **docs/product/CloudKit-Sync-PRD.md**
  - CloudKit sync status (planned/implemented?)

- [ ] **docs/product/Diversity-Insights-PRD.md**
  - Check cultural region definitions

- [ ] **docs/product/DTOMapper-PRD.md**
  - Verify deduplication logic docs

- [ ] **docs/product/Enrichment-Pipeline-PRD.md**
  - **CRITICAL:** Update with Issue #255 (enrichment failures)
  - Verify batch enrichment flow

- [ ] **docs/product/Gemini-CSV-Import-PRD.md**
  - **CRITICAL:** Update with UserLibraryEntry requirement
  - Check SHA-256 caching docs

- [ ] **docs/product/Genre-Normalization-PRD.md**
  - Verify genre mapping tables current

- [ ] **docs/product/Library-Reset-PRD.md**
  - Update with PR #251 fix (deleted object validation)

- [ ] **docs/product/PRD-Template.md**
  - Template structure still useful?

- [ ] **docs/product/Reading-Statistics-PRD.md**
  - Check ReadingStats calculation formulas

- [ ] **docs/product/Review-Queue-PRD.md**
  - Verify confidence thresholds

- [ ] **docs/product/Search-PRD.md**
  - Validate `/v1/search/*` endpoints

- [ ] **docs/product/Settings-PRD.md**
  - Check settings options complete

- [ ] **docs/product/VisionKit-Barcode-Scanner-PRD.md**
  - Verify VisionKit API patterns

---

## 🔄 Workflows (6 Mermaid Diagrams)

- [ ] **docs/workflows/barcode-scanner-workflow.md**
  - Diagram matches VisionKit implementation

- [ ] **docs/workflows/bookshelf-scanner-workflow.md**
  - Flow matches Gemini 2.0 Flash integration

- [ ] **docs/workflows/canonical-contracts-workflow.md**
  - DTO transformation steps accurate

- [ ] **docs/workflows/csv-import-workflow.md**
  - **CRITICAL:** Add UserLibraryEntry creation step
  - Verify unified enrichment pipeline

- [ ] **docs/workflows/enrichment-workflow.md**
  - Update with Issue #255 findings

- [ ] **docs/workflows/search-workflow.md**
  - Validate search flow matches SearchModel

---

## 📖 Guides (5 files)

- [ ] **docs/guides/performance-optimization.md**
  - SwiftData query patterns current?
  - Check caching strategies

- [ ] **docs/guides/privacy-strings.md**
  - Info.plist keys complete
  - Camera/photo permissions current

- [ ] **docs/guides/logging/LOGGING_DOCUMENTATION_INDEX.md**
  - Cloudflare Worker logging cmds accurate

- [ ] **docs/guides/logging/LOGGING_EXAMPLES.md**
  - Example sessions still relevant

- [ ] **docs/guides/logging/README_LOGGING.md**
  - Quick start steps current

---

## 📊 Performance & Testing (2 files)

- [ ] **docs/performance/2025-11-04-app-launch-optimization-results.md**
  - Results snapshot (archive after 2 months?)

- [ ] **docs/testing/2025-10-17-platform-compatibility-progress.md**
  - Platform support still accurate?

---

## 📝 Active Plans (5 files in docs/plans/)

- [ ] **docs/plans/2025-11-04-api-contract-envelope-refactoring.md**
  - Implementation complete? Move to archive?

- [ ] **docs/plans/2025-11-04-app-launch-optimization-implementation.md**
  - Implementation complete? Move to archive?

- [ ] **docs/plans/2025-11-04-batch-endpoints-response-envelope-migration.md**
  - Migration complete? Move to archive?

- [ ] **docs/plans/2025-11-04-bookshelf-scan-data-loss-fix.md**
  - Fix deployed? Move to archive?

- [ ] **docs/plans/2025-11-04-issues-197-147-217-implementation.md**
  - Issues resolved? Move to archive?

- [ ] **docs/plans/2025-11-04-test-suite-api-migration-design.md**
  - Migration complete? Move to archive?

- [ ] **docs/plans/2025-11-04-test-suite-api-migration-implementation.md**
  - Implementation complete? Move to archive?

- [ ] **docs/plans/2025-11-05-csv-enrichment-error-diagnosis.md**
  - Related to Issue #255 - mark as superseded by GH issue?

---

## 🔍 High Priority Verification (Do These First)

1. **GEMINI_CSV_IMPORT.md** - Update with commit 086384b UserLibraryEntry fix
2. **csv-import-workflow.md** - Add UserLibraryEntry step to diagram
3. **Gemini-CSV-Import-PRD.md** - Document UserLibraryEntry requirement
4. **Enrichment-Pipeline-PRD.md** - Reference Issue #255 for known failures
5. **CLAUDE.md** - Verify all architectural patterns current

---

## 📦 Archive Candidates (Review in 2 Months)

- Performance snapshots older than 2 months
- Completed implementation plans in docs/plans/
- Fixed bug investigation docs in archive/root-docs-2025-11/

---

**Next Steps:**
1. Schedule doc verification sprint (2-3 hour block)
2. Create GH issues for inaccurate docs found
3. Archive completed implementation plans
4. Update CLAUDE.md with recent architectural changes

**Last Cleanup:** November 5, 2025
**Next Scheduled Review:** January 2026
