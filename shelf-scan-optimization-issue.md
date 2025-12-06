# Optimize Shelf Scan Workflow: Remove Batch Upload, Enhance Single-Photo Experience

## 📋 Summary

The shelf scanning feature currently has infrastructure for both single-photo and batch (5-photo) workflows, but the batch path appears underutilized and adds unnecessary complexity. This issue proposes removing batch upload support and focusing on optimizing the single-photo scanning experience.

## 🔍 Current State Analysis

### Code Review Findings

**BookshelfAIService.swift (1069 lines):**
- **Line 393-464**: `processBookshelfImageWithProgress()` - SSE-first with WebSocket fallback (PRIMARY workflow)
- **Line 822-853**: `submitBatch()` - Batch scanning support (**DEPRECATED path**)
- **Line 160-268**: WebSocket processing
- **Line 279-383**: SSE processing (API v3.2)
- **Line 746-786**: `startScanJob()` - uploads single image, gets auth token

**BatchCaptureView.swift:**
- **Line 14**: `capturedPhotos: [CapturedPhoto] = []`
- **Line 28**: Enforces `maxPhotosPerBatch` limit (5 photos)
- **Line 84**: Calls `service.submitBatch(jobId:photos:)`

### Current Workflow Modes

| Mode | Endpoint | Status | Notes |
|------|----------|--------|-------|
| **Single-photo scan** | `/api/v3.2/scan-bookshelf` | ✅ Active | SSE-first, WebSocket fallback |
| **Batch scan** | Unknown (via `submitBatch()`) | ⚠️ Unclear | Infrastructure exists, usage unclear |

## 🎯 Proposed Changes

### 1. **Remove Batch Scanning Infrastructure**

**Files to modify:**
- `BookshelfAIService.swift`:
  - Remove `submitBatch()` method (lines 822-853)
  - Remove batch-related properties
  - Simplify to single-photo workflow only

- `BatchCaptureView.swift`:
  - **Option A**: Remove entirely if only used for batch scanning
  - **Option B**: Repurpose as "multi-photo sequential scanning" (scan one photo at a time, 5 photos max)

**Rationale:**
- Reduces codebase complexity (200+ lines removed)
- Simplifies testing and maintenance
- Focuses development effort on single-photo UX optimization

### 2. **Enhance Single-Photo Scanning Experience**

**UX Improvements:**

**A. Real-Time Progress Feedback**
- Leverage existing SSE/WebSocket progress streaming
- Show granular status:
  - "Uploading image..." (0-20%)
  - "Analyzing bookshelf..." (20-60%)
  - "Extracting ISBNs..." (60-80%)
  - "Enriching book data..." (80-100%)

**B. Image Compression Optimization**
- Current: 10MB max size (line 95)
- Proposal: Adaptive compression based on network conditions
- Pre-flight check: Warn if image >5MB on cellular

**C. Retry/Fallback Logic**
- SSE-first with WebSocket fallback ✅ (already implemented)
- Add retry logic for transient failures
- Graceful degradation if both SSE/WebSocket fail

**D. Multi-Photo Sequential Workflow** (Optional)
- Allow users to scan multiple shelves sequentially
- Each photo scanned immediately (no batching)
- Aggregate results in UI
- Pattern: "Scan → Results → Scan Next Shelf → Aggregate"

### 3. **API Alignment with V3 Migration**

**Current API Usage:**
- Shelf scan: `/api/v3.2/scan-bookshelf` ✅ (newer than V3!)
- Enrichment: `/api/v2/books/enrich` (needs V3 migration)

**V3 Migration Path:**
1. Shelf scan returns ISBNs
2. Use `POST /v3/books/enrich` with `{ isbns: [String], includeEmbedding: false }`
3. Transform V3 unified Book model → SwiftData Work/Edition/Author entities

**Integration Points:**
- **BookshelfAIService.swift line 746**: `startScanJob()` uploads image
- **BookshelfAIService.swift line 881**: `fetchScanResults()` gets ISBNs
- **EnrichmentService.swift line 114**: `startEnrichment()` needs V3 migration

## 🧪 Testing Strategy

### Before Removal (Validation)
1. **Confirm batch scanning usage**:
   - Analytics: Check if `submitBatch()` is ever called in production
   - User interviews: Do users scan multiple photos at once?
   - Telemetry: Track batch vs single-photo scan frequency

2. **If batch scanning IS used**:
   - Migrate to sequential single-photo workflow
   - Provide migration guide for users
   - A/B test new UX before full rollout

3. **If batch scanning is NOT used**:
   - Safe to remove immediately
   - Document removal in release notes

### After Implementation
1. **Unit Tests**:
   - Single-photo upload
   - SSE progress streaming
   - WebSocket fallback
   - Network failure scenarios

2. **Integration Tests**:
   - Scan → Enrich → SwiftData persistence
   - Multi-photo sequential scanning
   - Cellular vs WiFi compression

3. **Real Device Testing**:
   - Large images (8-10MB)
   - Poor network conditions
   - Background app transitions

## 📊 Success Metrics

**Performance:**
- Scan-to-results time <5 seconds (target)
- Image compression <2 seconds
- 95th percentile success rate

**UX:**
- User completes scan without errors
- Clear progress feedback throughout
- Graceful error handling

**Code Quality:**
- 200+ lines removed (batch infrastructure)
- Reduced cognitive complexity
- Simplified test matrix

## 🚧 Migration Checklist

- [ ] Validate batch scanning usage in production (analytics/telemetry)
- [ ] If batch scanning used: Design sequential multi-photo UX
- [ ] If batch scanning unused: Remove `submitBatch()` and BatchCaptureView
- [ ] Implement adaptive image compression
- [ ] Add retry logic for transient failures
- [ ] Integrate V3 enrichment API (`POST /v3/books/enrich`)
- [ ] Update BookshelfAIService to use V3 response mapping
- [ ] Write unit tests for single-photo workflow
- [ ] Write integration tests for scan→enrich→persist flow
- [ ] Real device testing (large images, poor network)
- [ ] Update documentation and release notes
- [ ] Monitor post-deployment metrics

## 🔗 Related Context

**Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/BatchCaptureView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentService.swift`

**Documentation:**
- `/docs/OPENAPI_V3_SPEC_CORRECTIONS.md` - V3 API migration guide
- `/docs/openapi-v3.json` - V3 API specification

**Related Issues:**
- V3 API Migration (pending)
- EnrichmentService V3 integration (pending)

## 💡 Open Questions

1. **What is the actual usage of batch scanning?** (Analytics needed)
2. **Should we preserve multi-photo scanning as sequential workflow?** (UX decision)
3. **What's the priority: V3 migration or batch removal first?** (Sequencing)
4. **Do we need to maintain V2 compatibility during transition?** (Deployment strategy)

---

**Priority:** Medium
**Effort:** 3-5 days (depending on batch scanning usage validation)
**Impact:** Reduces complexity, improves single-photo UX, aligns with V3 API migration
**Assignee:** TBD
**Labels:** enhancement, tech-debt, shelf-scanning, v3-migration
