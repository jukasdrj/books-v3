# WebSocket → SSE Migration Plan

**Status:** In Progress
**Created:** November 29, 2025
**Deadline:** Q3 2026 (Backend WebSocket Removal)
**Owner:** iOS Team
**Related Issue:** #103

---

## Executive Summary

Comprehensive migration plan to transition from WebSocket to Server-Sent Events (SSE) for real-time progress tracking across all job types before the Q3 2026 backend removal deadline.

**Scope:** 3 job types (CSV Import, Photo Scan, Batch Enrichment)
**Timeline:** 18 months (NOW → Q3 2026)
**Strategy:** Phased migration with feature flags for safety
**Critical Path:** Backend batch enrichment SSE support (Q2 2026)

---

## Migration Timeline

```
NOW          Q4 2025      Q1 2026       Q2 2026         Q3 2026
 |              |            |             |               |
 |-- Phase 1 ---|            |             |               |
 |  Foundation  |            |             |               |
 |              |            |             |               |
 |              |-- Phase 2--|             |               |
 |              | CSV Import |             |               |
 |              |            |             |               |
 |              |            |-- Phase 3 --|               |
 |              |            | Photo Scan  |               |
 |              |            |             |               |
 |              |            |             |-- Phase 4 ----|
 |              |            |             |  Batch Enrich |
 |              |            |             |               |
 |              |            |             |               |-- Phase 5 --|
 |              |            |             |               |   Cleanup   |
 |              |            |             |               |             |
                                           ^               ^
                                      CRITICAL:         DEADLINE:
                                   Backend Batch      WebSocket
                                   SSE Support        Removal
```

---

## Phase Breakdown

### Phase 1: Foundation (NOW - Dec 2025)

**Objective:** Build infrastructure for SSE-based progress tracking

**Tasks:**
1. Create SSEProgressHandler
   - Match GenericWebSocketHandler API surface
   - Adapter pattern for AsyncStream → callback conversion
   - @MainActor isolation for UI updates

2. Implement Feature Flag System
   - `FeatureFlags.useSSEForCSVImport`
   - `FeatureFlags.useSSEForPhotoScan`
   - `FeatureFlags.useSSEForBatchEnrichment`
   - Actor-based, thread-safe

3. Add Deprecation Warnings
   ```swift
   @available(*, deprecated, message: "Use SSEProgressHandler for V2 endpoints. WebSocket support ends Q3 2026.")
   @MainActor
   public final class GenericWebSocketHandler {
       // ... existing implementation ...
   }
   ```

4. Comprehensive Testing
   - Unit tests for SSEProgressHandler
   - Mock SSE events for testing
   - Verify callback behavior matches WebSocket

**Dependencies:** SSEClient (✅ COMPLETE - commit a7a6f4b)
**Deliverable:** Production-ready SSEProgressHandler
**GitHub Issue:** #106

**Acceptance Criteria:**
- [ ] SSEProgressHandler API matches GenericWebSocketHandler
- [ ] All tests pass
- [ ] Feature flags implemented
- [ ] Deprecation warnings added
- [ ] Zero warnings build

---

### Phase 2: CSV Import Migration (Jan 2026)

**Objective:** Migrate CSV Import to SSE (already required by API Contract v3.3)

**Migration Steps:**
1. Update CSV Import service to check feature flag
2. Use SSEProgressHandler when flag enabled
3. Keep GenericWebSocketHandler as fallback

**Rollout Plan:**
```
Week 1:  10% rollout -> Monitor for issues
Week 2:  50% rollout -> Validate stability
Week 3: 100% rollout -> Full SSE adoption
Week 4-5: Monitor (2 weeks stability period)
Week 6: Remove dual protocol support
```

**Monitoring:**
- Track SSE connection failures
- Compare progress event delivery vs WebSocket baseline
- Monitor reconnection frequency

**Dependencies:** Phase 1 complete
**Deliverable:** CSV Import fully on SSE
**GitHub Issue:** #107

**Acceptance Criteria:**
- [ ] Feature flag controls protocol selection
- [ ] 2 weeks of stable 100% SSE operation
- [ ] Zero regressions vs WebSocket
- [ ] Dual protocol code removed

---

### Phase 3: Photo Scan Migration (Feb-Mar 2026)

**Objective:** Migrate Photo Scan to SSE

**Special Considerations:**
- Requires real device testing (camera workflows)
- Photo scan jobs are longer-running (40-70s)
- More complex event structure (stage metadata)

**Migration Steps:**
1. Verify Photo Scan SSE event structure matches API contract
2. Update BookshelfAIService to use SSEProgressHandler
3. Real device testing with feature flag
4. Gradual rollout (10% → 50% → 100%)
5. Remove dual protocol support

**Testing Requirements:**
- Physical iPhone for camera scanning tests
- Validate stage progress updates (uploading, analyzing, enriching)
- Test reconnection during long-running jobs

**Dependencies:** CSV Import stable
**Deliverable:** Photo Scan fully on SSE
**GitHub Issue:** #108

**Acceptance Criteria:**
- [ ] Real device testing complete
- [ ] Stage metadata parsing correct
- [ ] 2 weeks of stable operation
- [ ] Dual protocol code removed

---

### Phase 4: Batch Enrichment Migration (Apr-Jun 2026)

**Objective:** Migrate batch enrichment (last WebSocket usage)

**⚠️ CRITICAL DEPENDENCY:** Backend must provide batch enrichment SSE by Q2 2026

**Migration Steps:**
1. **WAIT** for backend SSE support confirmation
2. Review batch enrichment SSE event structure
3. Update EnrichmentQueue to use SSEProgressHandler
4. Thorough validation (handles 100+ books)
5. Gradual rollout
6. Remove dual protocol support

**Complexity Factors:**
- Most complex job type (batch processing)
- Handles large book counts (100+)
- Progress updates every 2s
- Critical for user workflow (library enrichment)

**Dependencies:** Backend batch enrichment SSE (EXTERNAL)
**Deliverable:** All job types on SSE
**GitHub Issue:** #109

**Acceptance Criteria:**
- [ ] Backend SSE support confirmed and delivered
- [ ] Batch jobs handle 100+ books correctly
- [ ] Progress updates at correct frequency
- [ ] 2 weeks of stable operation
- [ ] Last WebSocket usage removed

---

### Phase 5: Cleanup (Jul-Sep 2026)

**Objective:** Remove all WebSocket code before backend removal

**Tasks:**
1. Remove GenericWebSocketHandler.swift (305 lines)
2. Remove WebSocket dependencies
3. Update documentation
   - AGENTS.md (remove WebSocket references)
   - API documentation
   - Migration notes

4. Final verification
   - Grep for "WebSocket" in codebase
   - Verify zero references
   - Build succeeds with zero warnings

**Pre-Deadline Checklist:**
- [ ] All 3 job types using SSE
- [ ] GenericWebSocketHandler removed
- [ ] No WebSocket imports
- [ ] Documentation updated
- [ ] Build clean (zero errors/warnings)

**Dependencies:** Phase 4 complete
**Deadline:** Before Q3 2026 backend WebSocket removal
**Deliverable:** Zero WebSocket code
**GitHub Issue:** #110

---

## Critical Path & Dependencies

```
Phase 1 (Foundation)
    |
    v
Phase 2 (CSV Import) ----+
    |                    |
    v                    |
Phase 3 (Photo Scan) ----+----> Can proceed in parallel
    |                    |
    |                    v
    |              Backend Batch SSE
    |              (Q2 2026 - EXTERNAL)
    |                    |
    +--------------------+
             |
             v
    Phase 4 (Batch Enrichment)
             |
             v
    Phase 5 (Cleanup)
             |
             v
    Q3 2026 DEADLINE
```

**CRITICAL PATH:** Backend batch enrichment SSE support (longest lead time, external dependency)

---

## Risk Mitigation

### Technical Risks

**Risk:** SSEProgressHandler doesn't match GenericWebSocketHandler behavior
**Mitigation:** Comprehensive testing in Phase 1, adapter pattern for API compatibility

**Risk:** SSE connection issues in production
**Mitigation:** Feature flags allow immediate rollback to WebSocket

**Risk:** AsyncStream → callback conversion has edge cases
**Mitigation:** Extensive unit tests, gradual rollout catches issues early

### Timeline Risks

**Risk:** Backend delays batch enrichment SSE past Q2 2026
**Mitigation:** Immediate coordination with backend team, get written commitment

**Risk:** Phase delays cascade to miss Q3 2026 deadline
**Mitigation:** Quarterly checkpoint reviews, adjust scope if needed

**Risk:** Complex edge cases discovered during migration
**Mitigation:** Dual protocol support allows extended transition period

---

## Immediate Next Steps

### Action 1: Backend Coordination (HIGHEST PRIORITY)
**What:** Contact backend team TODAY
**Why:** External dependency with longest lead time
**Deliverable:** Written confirmation of Q2 2026 batch enrichment SSE timeline
**Impact if delayed:** Could miss entire Q3 2026 deadline

### Action 2: Analyze GenericWebSocketHandler
**What:** Read GenericWebSocketHandler.swift (305 lines)
**Why:** Inform SSEProgressHandler API design
**Deliverable:** API specification document
**Needed before:** SSEProgressHandler implementation

### Action 3: Verify FeatureFlags System
**What:** Search codebase for existing FeatureFlags actor
**Why:** Determine if feature flag system needs creation
**Deliverable:** Feature flag implementation plan
**Needed before:** Any migration work

---

## Quarterly Checkpoints

**Q4 2025 Review:**
- Phase 1 complete? (SSEProgressHandler, feature flags)
- If behind: Reduce scope to CSV only
- If major issues: Escalate, extend timeline

**Q1 2026 Review:**
- CSV Import migrated and stable?
- Photo Scan in progress?
- If CSV unstable: Pause Photo Scan, fix CSV
- If backend silent: ESCALATE immediately

**Q2 2026 Review (CRITICAL):**
- Backend batch enrichment SSE available?
- Migration in progress?
- If backend not ready: Emergency timeline discussion
- If blocked: Consider keeping WebSocket longer

**Q3 2026 Pre-Deadline:**
- All migrations complete?
- GenericWebSocketHandler removed?
- If not ready: CRITICAL - backend may remove WebSocket anyway

---

## Success Metrics

- **Zero downtime** during all migrations
- **Feature parity** - all SSE events match WebSocket behavior
- **Completed on time** - before Q3 2026 backend removal
- **Clean build** - zero errors, zero warnings (except expected deprecation warnings)
- **Validated at scale** - handles 100+ book batch enrichment

---

## Change Log

| Date | Phase | Change | Author |
|------|-------|--------|--------|
| 2025-11-29 | All | Initial migration plan created | Claude Code |

---

## References

- API Contract v3.3: `docs/API_CONTRACT.md` §8 (WebSocket Deprecation)
- SSEClient Implementation: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/SSEClient.swift`
- GenericWebSocketHandler: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/GenericWebSocketHandler.swift`
- Related Issues: #99 (SSE support), #101 (SSE client), #103 (Migration plan)
