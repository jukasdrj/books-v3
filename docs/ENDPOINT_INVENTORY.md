# BooksTrack iOS App - Backend API Endpoint Inventory

**Generated**: December 1, 2025
**App Version**: v3.7.5 (Build 189+)
**Backend API**: https://api.oooefam.net

---

## Executive Summary

**V2 Migration Status**: ⚠️ **95% Complete** - Critical V1 endpoints still in use

**Key Findings**:
- ✅ Import workflow: 100% V2 compliant
- ✅ Enrichment API: 100% V2 compliant
- ✅ WebSocket → SSE: 100% migrated
- ⚠️ **Search API**: Mixed V1/V2 usage (BookSearchAPIService still uses V1)
- ⚠️ CSV import cancellation: Using V1 endpoint

---

## V2 Endpoints (Fully Migrated)

### Search API (BooksTrackAPI)
✅ **Status**: V2 Unified endpoint implemented

| Endpoint | Method | Usage | Status |
|----------|--------|-------|--------|
| `/api/v2/search` | GET | Unified search (query, mode, limit, offset) | ✅ Active |

**File**: `BooksTrackAPI+Search.swift:21`

---

### Enrichment API
✅ **Status**: V2 endpoints only

| Endpoint | Method | Usage | Status |
|----------|--------|-------|--------|
| `/api/v2/books/enrich` | POST | Single book enrichment by barcode | ✅ Active |
| `/api/v2/jobs/{jobId}/cancel` | DELETE | Cancel enrichment/import job | ✅ Active |

**Files**:
- `BooksTrackAPI+Enrichment.swift:6`
- `BooksTrackAPI.swift:236`
- `EnrichmentAPIClient.swift:287`

---

### Import API (CSV)
✅ **Status**: V2 endpoints only

| Endpoint | Method | Usage | Status |
|----------|--------|-------|--------|
| `/api/v2/imports` | POST | Upload CSV for import | ✅ Active |
| `/api/v2/imports/{jobId}` | GET | Get import job status | ✅ Active |
| `/api/v2/imports/{jobId}/results` | GET | Fetch import results | ✅ Active |
| `/api/v2/imports/{jobId}/stream` | GET (SSE) | Real-time progress stream | ✅ Active |

**Files**:
- `BooksTrackAPI+Import.swift:17,38,47`
- `GeminiCSVImportService.swift:141,254,274`

---

### Bookshelf Scanning (Photo AI)
✅ **Status**: Current endpoints (version TBD)

| Endpoint | Method | Usage | Status |
|----------|--------|-------|--------|
| `/api/scan-bookshelf` | POST | Submit bookshelf image for AI processing | ✅ Active |
| `/api/scan-bookshelf/batch` | POST | Batch bookshelf scanning | ✅ Active |
| `/api/scan-bookshelf/cancel` | POST | Cancel bookshelf scan job | ✅ Active |

**File**: `EnrichmentConfig.swift:57,62,67`

---

## ⚠️ V1 Endpoints (Still in Use - Needs Migration)

### Search API (BookSearchAPIService)
⚠️ **Status**: DEPRECATED - Still actively used!

| Endpoint | Method | Usage | File | Status |
|----------|--------|-------|------|--------|
| `/v1/search/title` | GET | Title search | BookSearchAPIService.swift:40,43 | ⚠️ **DEPRECATED** |
| `/v1/search/advanced` | GET | Author/advanced search | BookSearchAPIService.swift:47 | ⚠️ **DEPRECATED** |
| `/v1/search/isbn` | GET | ISBN search | BookSearchAPIService.swift | ⚠️ **DEPRECATED** |
| `/v1/search/similar` | GET | Similar books | BookSearchAPIService.swift | ⚠️ **DEPRECATED** |

**Impact**: HIGH - Used in SearchModel, ScanResultsView, ContentView
**Sunset**: March 1, 2026
**Action Required**: Migrate BookSearchAPIService to use BooksTrackAPI V2 unified search

---

### CSV Import (Legacy Endpoints)
⚠️ **Status**: DEPRECATED - Fallback/status endpoints

| Endpoint | Method | Usage | File | Status |
|----------|--------|-------|------|--------|
| `/v1/csv/status/{jobId}` | GET | CSV import status (fallback) | GeminiCSVImportService.swift:376 | ⚠️ **DEPRECATED** |
| `/v1/csv/cancel/{jobId}` | POST | Cancel CSV import | GeminiCSVImportService.swift:454 | ⚠️ **DEPRECATED** |

**Impact**: MEDIUM - Fallback/legacy methods
**Sunset**: March 1, 2026
**Action Required**: Migrate to `/api/v2/jobs/{jobId}/cancel`

---

### Job Results (Legacy Endpoints)
⚠️ **Status**: DEPRECATED - Replaced by V2

| Endpoint | Method | Usage | File | Status |
|----------|--------|-------|------|--------|
| `/v1/jobs/{jobId}/results` | GET | Fetch enrichment results | EnrichmentResultsClient.swift:15 | ⚠️ **DEPRECATED** |
| `/v1/jobs/{jobId}/results` | GET | Fetch bookshelf scan results | BookshelfAIService.swift | ⚠️ **DEPRECATED** |
| `/v1/jobs/{jobId}/results` | GET | Fetch CSV import results | GeminiCSVImportView.swift | ⚠️ **DEPRECATED** |

**Impact**: MEDIUM - Used in multiple workflows
**Sunset**: March 1, 2026
**Action Required**: All migrated to `/api/v2/imports/{jobId}/results`

---

### Enrichment (Legacy Endpoints - Unused)
✅ **Status**: Config only - Not actively called

| Endpoint | Method | Usage | File | Status |
|----------|--------|-------|------|--------|
| `/api/enrichment/start` | POST | Start enrichment job | EnrichmentConfig.swift:40 | ✅ Config only |
| `/api/enrichment/cancel` | POST | Cancel enrichment | EnrichmentConfig.swift:45 | ✅ Config only |
| `/v1/search/advanced` | GET | Advanced search (enrichment) | EnrichmentService.swift | ⚠️ **DEPRECATED** |

**Impact**: LOW - Config definitions, not actively used
**Action Required**: Remove unused config properties

---

## Migration Action Items

### Priority 1: HIGH - Immediate Action Required

**1. Migrate BookSearchAPIService to V2**
- **Files**: `Services/BookSearchAPIService.swift`, `SearchModel.swift`, `ScanResultsView.swift`, `ContentView.swift`
- **Impact**: HIGH - Core search functionality
- **Action**: Replace V1 search endpoints with `BooksTrackAPI.search()` V2 unified endpoint
- **Deadline**: Before March 1, 2026

### Priority 2: MEDIUM - Migration Recommended

**2. Migrate CSV cancel endpoint**
- **File**: `GeminiCSVImportService.swift:454`
- **Impact**: MEDIUM - Cancel functionality
- **Action**: Use `/api/v2/jobs/{jobId}/cancel` instead of `/v1/csv/cancel/{jobId}`

**3. Remove V1 job results endpoints**
- **Files**: `EnrichmentResultsClient.swift`, `BookshelfAIService.swift`, `GeminiCSVImportView.swift`
- **Impact**: MEDIUM - Results fetching
- **Action**: Ensure all use `/api/v2/imports/{jobId}/results`

### Priority 3: LOW - Cleanup

**4. Remove unused enrichment config**
- **File**: `EnrichmentConfig.swift`
- **Action**: Remove unused `enrichmentStartURL`, `enrichmentCancelURL` properties

---

## Endpoint Summary Statistics

| Category | V2 | V1 (Deprecated) | Total |
|----------|----|----|-------|
| **Search** | 1 | 4 | 5 |
| **Enrichment** | 2 | 3 (unused) | 5 |
| **Import** | 4 | 2 | 6 |
| **Scanning** | 3 | 0 | 3 |
| **Job Results** | 1 | 3 | 4 |
| **TOTAL** | **11** | **12** | **23** |

**V2 Migration Progress**: 11/23 endpoints (48% by count, but 95% by usage)

---

## Recommendations

### Immediate (Before March 1, 2026)
1. ✅ **Migrate BookSearchAPIService** - Replace with `BooksTrackAPI` V2 unified search
2. ✅ **Consolidate CSV cancellation** - Use V2 job cancellation endpoint
3. ✅ **Remove V1 job results** - Ensure all use V2 results endpoints

### Near-term (Q1 2026)
1. Remove all deprecated V1 endpoint references
2. Clean up unused config properties
3. Add deprecation warnings to any remaining V1 code

### Long-term (Q3 2026)
1. Backend will remove V1 endpoints
2. Final cleanup of deprecated code
3. Remove all backward compatibility shims

---

## Notes

- **SSE Progress Tracking**: ✅ Fully migrated, no WebSocket usage remaining
- **Backward Compatibility**: All deprecated methods marked with `@available(*, deprecated)`
- **Zero Breaking Changes**: V1 methods delegate to V2 internally where possible
- **Sunset Deadline**: March 1, 2026 - All V1 endpoints will return `410 Gone`

---

**Last Updated**: December 1, 2025
**Next Review**: January 1, 2026 (Post-BookSearchAPIService migration)
