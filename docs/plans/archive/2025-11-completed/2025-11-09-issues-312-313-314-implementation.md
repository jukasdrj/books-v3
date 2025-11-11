# Implementation Plan: Issues #312, #313, #314

**Date:** 2025-11-09
**Status:** Phase 1 - In Progress
**Related Issues:** #312, #313, #314

## Overview

Comprehensive fix for three P1-MEDIUM priority issues affecting the enrichment pipeline:
- **#312:** Enrichment job hangs forever if backend stalls (no timeout)
- **#313:** Fragile title-based matching causes data corruption
- **#314:** API endpoint URLs hardcoded across codebase

## Multi-Model Consensus

Plan reviewed by three AI models with **unanimous approval**:
- **Grok-4:** 8/10 confidence (pragmatic engineering perspective)
- **Gemini 2.5 Pro:** 9/10 confidence (critical analysis)
- **GPT-5 Pro:** 8/10 confidence (neutral technical analysis)

**Key Agreement:** Phased deployment is optimal; isolates behavioral changes from refactoring.

## Implementation Strategy

### Phase 1: URL Centralization + ID-Based Matching (LOW RISK)

**Files Modified:**
1. `EnrichmentConfig.swift` - Add 11 endpoint properties + WebSocket helper
2. `EnrichmentQueue.swift` - Enhanced ID-based matching with multi-field fallback
3. `BatchCaptureView.swift:139` - Use EnrichmentConfig.scanCancelURL
4. `BookshelfAIService.swift:84` - Use EnrichmentConfig.scanBookshelfURL
5. `BookSearchAPIService.swift` - Use search endpoint properties
6. `GeminiCSVImportService.swift` - Use EnrichmentConfig.csvImportURL
7. `WebSocketProgressManager.swift` - Use EnrichmentConfig.webSocketURL(jobId:)
8. `BatchWebSocketHandler.swift` - Use EnrichmentConfig.webSocketURL(jobId:)
9. `BookshelfAIService+Polling.swift` - Use config properties
10. Additional files (3+) identified via grep

**Key Changes:**

```swift
// EnrichmentConfig.swift expansion
enum EnrichmentConfig {
    static let baseURL = "https://api-worker.jukasdrj.workers.dev"
    static let webSocketBaseURL = "wss://api-worker.jukasdrj.workers.dev"

    // Computed properties for all endpoints
    static var searchTitleURL: URL { URL(string: "\(baseURL)/search/title")! }
    static var enrichmentCancelURL: URL { URL(string: "\(baseURL)/api/enrichment/cancel")! }
    static var scanBookshelfURL: URL { URL(string: "\(baseURL)/api/scan-bookshelf")! }
    static var scanCancelURL: URL { URL(string: "\(baseURL)/api/scan-bookshelf/cancel")! }
    // ... 7 more endpoints

    static func webSocketURL(jobId: String) -> URL {
        URL(string: "\(webSocketBaseURL)/ws/progress?jobId=\(jobId)")!
    }
}
```

**Enhanced ID-Based Matching:**

```swift
// EnrichmentQueue.applyEnrichedData() - Replace lines 337-348
// Primary: Use PersistentIdentifier
if let work = modelContext.model(for: enrichedBook.workPersistentID) as? Work {
    print("✅ Matched by PersistentIdentifier: \(work.title)")
} else {
    // Fallback: Multi-field validation (title + author + year)
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { work in
            work.title.localizedStandardContains(enrichedBook.title)
        }
    )
    guard let works = try? modelContext.fetch(descriptor),
          let work = works.first(where: { candidate in
              // Multi-field validation
              let titleMatch = candidate.title.localizedStandardContains(enrichedBook.title)
              let authorMatch = candidate.authors?.first?.name == enrichedBook.author
              let yearMatch = abs((candidate.firstPublicationYear ?? 0) - (enrichedBook.year ?? 0)) <= 1
              return titleMatch && (authorMatch || yearMatch)
          }) else {
        print("⚠️ No match found for '\(enrichedBook.title)' (potential data loss avoided)")
        continue
    }
    print("⚠️ Fell back to multi-field matching: \(work.title)")
}
```

### Phase 2: Activity-Based Timeout (MEDIUM RISK)

**Deferred to separate PR after Phase 1 monitoring.**

## Consensus Insights

### Critical Edge Cases (GPT-5 Pro)

1. **Temporary PersistentIdentifier Usage:**
   - MUST only use permanent IDs (after `save()`)
   - Add guards to prevent sending temp IDs

2. **Processing Flag CloudKit Sync:**
   - Flag must be per-device or non-synced
   - Prevents cross-device lock contention

3. **@MainActor Execution Context:**
   - Run network work OFF @MainActor
   - Avoids main-thread hangs and warnings

4. **Late-Arriving Results:**
   - Backend responses after timeout cause duplicate writes
   - Need idempotency checks (Phase 2)

5. **WebSocket Cleanup Guarantee:**
   - Use `defer` to ensure cleanup on ALL paths
   - Already implemented in current code

## Testing Strategy

### Phase 1 Tests

**Unit Tests:**
- [ ] All EnrichmentConfig endpoints resolve correctly
- [ ] ID-based matching with mock PersistentIdentifier
- [ ] Multi-field fallback validation (title + author + year)
- [ ] Fallback correctly rejects non-matching books

**Integration Tests:**
- [ ] Real enrichment with ID-based matching
- [ ] Fallback works when backend doesn't include workPersistentID
- [ ] Zero warnings after URL changes
- [ ] All 10+ files use EnrichmentConfig (grep verification)

**Manual Tests:**
- [ ] Enrich 10 books successfully
- [ ] Check logs for fallback usage rate (target <1%)
- [ ] Verify all URLs hit correct endpoints
- [ ] Run /build && /test with zero warnings

## Success Metrics

**Phase 1 KPIs:**
- ID match rate: >99% (log "✅ Matched by PersistentIdentifier")
- Fallback rate: <1% (log "⚠️ Fell back to multi-field matching")
- Zero data corruption incidents
- Zero hardcoded URLs remaining
- Enrichment success rate: ~95% (unchanged from baseline)

## Deployment Plan

**Phase 1 Timeline:**
1. Implement EnrichmentConfig expansion
2. Replace hardcoded URLs across 10 files
3. Implement enhanced ID-based matching
4. Run /build && /test (zero warnings required)
5. Deploy to TestFlight
6. Monitor 24-48 hours
7. Merge to main if stable

**Rollback Plan:**
- Simple `git revert` (single commit)
- Zero data loss (fallback ensures no breakage)
- All URLs are pure refactor (no logic changes)

## Backend Coordination

**Not Required for Phase 1:**
- iOS can deploy with multi-field fallback
- Backend can add workPersistentID field later (P2 priority)
- Once backend includes IDs, iOS automatically uses them (no code change needed)

**Future Backend Enhancement (P2):**
- Modify `EnrichedBookPayload` to include `workPersistentID` field
- Echo back in WebSocket progress messages
- Estimated effort: 30 minutes

## References

- **Planning Session:** Generated with Zen MCP planner tool (Gemini 2.5 Pro)
- **Consensus Analysis:** Multi-model validation (Grok-4, Gemini 2.5 Pro, GPT-5 Pro)
- **Related Issues:** #312, #313, #314
- **PR:** https://github.com/jukasdrj/books-tracker-v1/pull/328
