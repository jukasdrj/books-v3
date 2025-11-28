# WebSocket → SSE Migration Plan
# BooksTrack iOS v3 - Complete Implementation Guide

**Version:** 1.0
**Created:** November 27, 2025
**Last Updated:** November 27, 2025
**Status:** Ready for Implementation
**Reviewed By:** Gemini Pro (Code Review Agent)

---

## Executive Summary

### Current State
- **CSV Import:** Already migrated to SSE (production-ready)
- **Batch Enrichment:** Using WebSocket (requires SSE migration)
- **Bookshelf Scan:** Using WebSocket (requires SSE migration)

### Migration Timeline
- **March 1, 2026:** WebSocket deprecated (backend team deadline)
- **June 1, 2026:** WebSocket endpoints removed (hard cutoff)
- **Implementation Window:** 8-12 weeks (January-March 2026)

### Risk Level
- **Overall Risk:** MEDIUM (with mitigation strategies in place)
- **Critical Dependencies:** Backend SSE endpoints ready by Q1 2026
- **Success Probability:** HIGH (CSV Import proves SSE viability)

---

## Table of Contents

1. [Verification Report Summary](#verification-report-summary)
2. [Migration Strategy](#migration-strategy)
3. [Implementation Plan (5 Phases)](#implementation-plan)
4. [Expert Review Findings](#expert-review-findings)
5. [Risk Analysis & Mitigation](#risk-analysis--mitigation)
6. [Testing Strategy](#testing-strategy)
7. [Rollout Plan](#rollout-plan)
8. [Questions for Backend Team](#questions-for-backend-team)
9. [Success Criteria](#success-criteria)
10. [Next Steps](#next-steps)

---

## Verification Report Summary

**See:** `docs/IOS_VERIFICATION_REPORT.md`

### Key Findings

#### CSV Import Service - COMPLIANT
- Already using SSE (v2 API)
- Last-Event-ID reconnection: IMPLEMENTED
- Automatic retry (3 attempts, 5s delay): IMPLEMENTED
- Event buffering for chunked streams: IMPLEMENTED
- Network transition handling: IMPLEMENTED

#### Batch Enrichment - REQUIRES MIGRATION
- Current: WebSocket (`EnrichmentWebSocketHandler.swift`)
- Target: SSE (`/api/v2/enrichments/{jobId}/stream`)
- Complexity: MEDIUM (queue-based system, SwiftData integration)

#### Bookshelf Scan - REQUIRES MIGRATION
- Current: WebSocket (`BookshelfAIService.processViaWebSocket()`)
- Target: SSE (`/api/v2/scans/{jobId}/stream`)
- Complexity: HIGH (authentication, real-time progress, multi-stage)

#### Critical Issues Identified
1. **Books Array Parsing:** API contract mentions `books[]` in results, iOS only uses summary counts
2. **TTL Handling:** No explicit 2-hour TTL validation (backend enforces, but no client-side check)
3. **Authentication Scheme:** Unclear how SSE will handle auth tokens (query param? header?)

---

## Migration Strategy

### Approach: Phased Migration with Dual-Mode Support

**Why This Approach?**
- **Lowest Risk:** Feature flags allow instant rollback
- **Real Validation:** Gradual rollout validates SSE in production before full commitment
- **Proven Pattern:** CSV Import already demonstrates SSE viability
- **Timeline Fits:** 8-12 weeks aligns with March 1, 2026 deadline

### Alternative Approaches Considered

**Big Bang Migration (REJECTED):**
- Pro: Faster completion (1-2 sprints)
- Con: High risk if SSE has issues, difficult rollback

**WebSocket Forever (NOT VIABLE):**
- Con: Backend deprecating June 1, 2026 (hard deadline)

---

## Implementation Plan

### Phase 1: Foundation (Weeks 1-2)

**Goal:** Create reusable SSE infrastructure

**Deliverables:**
- `GenericSSEClient<EventHandler>` (actor-isolated, reusable)
- Event schemas (`EnrichmentSSEModels`, `ScanSSEModels`)
- Feature flags (`useBatchEnrichmentSSE`, `useBookshelfScanSSE`, `sseRolloutPercentage`)
- V2 endpoint configuration
- Test infrastructure (`MockSSEServer`, unit tests with 90%+ coverage)

**Files to Create:**
```
Common/GenericSSEClient.swift          (~400 lines)
Common/SSEEventHandling.swift          (protocol)
Common/EnrichmentSSEModels.swift       (~150 lines)
Common/ScanSSEModels.swift             (~150 lines)
Tests/GenericSSEClientTests.swift      (~500 lines)
Tests/MockSSEServer.swift              (~200 lines)
```

**Files to Update:**
```
Common/FeatureFlags.swift              (+30 lines - SSE flags)
Common/EnrichmentConfig.swift          (+20 lines - V2 endpoints)
```

**Key Components:**
```swift
// Generic SSE Client (reusable across features)
actor GenericSSEClient<EventHandler: SSEEventHandling> {
    private var lastEventId: String?      // Reconnection support
    private var eventBuffer: String = ""  // Chunked event handling
    private var isCancelled: Bool = false // Clean disconnection

    func connect(to endpoint: String)
    func disconnect()
    private func parseSSEEvents(_ eventString: String)
    private func attemptReconnection()
}

protocol SSEEventHandling: Sendable {
    func handleEvent(type: String, data: String)
    func handleError(_ error: SSEClientError)
}
```

**Success Criteria:**
- All tests pass with zero warnings
- Feature flags toggle between SSE and WebSocket (stub implementations)
- CSV Import optionally uses `GenericSSEClient` (backward compatible refactor)

---

### Phase 2: Batch Enrichment Migration (Weeks 3-4)

**Goal:** Migrate `EnrichmentWebSocketHandler` to SSE

**Dependencies:**
- Phase 1 complete
- Backend endpoint ready: `GET /api/v2/enrichments/{jobId}/stream`
- Backend endpoint ready: `GET /api/v2/enrichments/{jobId}/results`

**Deliverables:**
- `EnrichmentSSEClient` (feature parity with WebSocket)
- `EnrichmentQueue` with dual-mode support (protocol-based abstraction)
- V2 API results fetching
- Integration tests (90%+ coverage)
- Real device validation

**Files to Create:**
```
Enrichment/EnrichmentSSEClient.swift         (~300 lines)
Tests/EnrichmentSSEClientTests.swift         (~400 lines)
Tests/EnrichmentSSEIntegrationTests.swift    (~300 lines)
```

**Files to Update:**
```
Enrichment/EnrichmentQueue.swift             (~10 lines changed - protocol abstraction)
Tests/EnrichmentQueueTests.swift             (+50 lines - SSE test cases)
```

**Implementation Pattern:**
```swift
@MainActor
final class EnrichmentSSEClient {
    private var sseClient: GenericSSEClient<EnrichmentEventHandler>?
    private let jobId: String
    private let progressHandler: @MainActor (Int, Int, String) -> Void
    private let completionHandler: @MainActor ([EnrichedBookPayload]) -> Void

    init(jobId: String, progressHandler: ..., completionHandler: ...) { }

    func connect() async {
        // 1. Initialize SSE stream
        // 2. Parse enrichment events (progress, complete, error)
        // 3. Fetch results on completion
    }

    func disconnect() { }
}

// EnrichmentQueue uses protocol for dual-mode support
protocol ProgressHandling: Sendable {
    func connect(jobId: String) async
    func disconnect()
}

private func createProgressHandler() -> any ProgressHandling {
    if FeatureFlags.shared.useBatchEnrichmentSSE {
        return EnrichmentSSEClient(jobId: currentJobId, ...)
    } else {
        return GenericWebSocketHandler(jobId: currentJobId, ...)  // Existing
    }
}
```

**Results Fetching:**
```swift
private func fetchEnrichmentResults(jobId: String) async throws -> [EnrichedBookPayload] {
    let url = EnrichmentConfig.enrichmentResultsURL(jobId: jobId)
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw EnrichmentError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200:
        let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentResults>.self, from: data)
        guard let results = envelope.data else {
            throw EnrichmentError.apiError("No enrichment results")
        }
        return results.enrichedBooks
    case 404:
        throw EnrichmentError.resultsExpired  // 2-hour TTL
    case 429:
        throw EnrichmentError.rateLimitExceeded
    default:
        throw EnrichmentError.httpError(httpResponse.statusCode)
    }
}
```

**Testing:**
- Full enrichment flow (upload → SSE stream → results fetch → SwiftData save)
- Network transition mid-enrichment (WiFi → Cellular)
- SSE reconnection with Last-Event-ID
- Timeout scenarios (2-hour TTL)
- Error handling (404, 429, 500)
- Feature flag toggle (SSE ↔ WebSocket)

**Success Criteria:**
- All tests pass with zero warnings
- Feature flag toggles seamlessly
- Real device testing confirms network transition handling
- Performance parity with WebSocket (within 10% latency)
- No regressions in enrichment success rate

---

### Phase 3: Bookshelf Scan Migration (Weeks 5-6 OR 3-4 if parallel)

**Goal:** Migrate `BookshelfAIService.processViaWebSocket()` to SSE

**Dependencies:**
- Phase 1 complete
- Backend endpoint ready: `GET /api/v2/scans/{jobId}/stream`
- Backend endpoint ready: `GET /api/v2/scans/{jobId}/results`
- **CRITICAL:** Authentication scheme clarified (token in query param? header?)

**Note:** Phase 3 can run in PARALLEL with Phase 2 (different engineers, independent code paths)

**Deliverables:**
- `BookshelfScanSSEClient` (feature parity with WebSocket)
- `BookshelfAIService` with dual-mode support
- V2 API results fetching with authentication
- Integration tests (90%+ coverage)
- Real device validation (authentication, network transitions)

**Files to Create:**
```
BookshelfScanning/Services/BookshelfScanSSEClient.swift   (~350 lines)
Tests/BookshelfScanSSEClientTests.swift                   (~500 lines)
Tests/BookshelfScanSSEIntegrationTests.swift              (~400 lines)
```

**Files to Update:**
```
BookshelfScanning/Services/BookshelfAIService.swift       (~30 lines changed)
Tests/BookshelfAIServiceTests.swift                       (+50 lines - SSE cases)
```

**Authentication Handling:**
Two possible approaches (NEEDS BACKEND CLARIFICATION):
1. **Query Parameter:** `GET /api/v2/scans/{jobId}/stream?token={authToken}`
2. **Authorization Header:** `Authorization: Bearer {authToken}`

**Implementation Pattern:**
```swift
actor BookshelfScanSSEClient {
    private var sseClient: GenericSSEClient<ScanEventHandler>?
    private let jobId: String
    private let authToken: String  // NEW: Required for authenticated SSE
    private let progressHandler: @MainActor (Double, String) -> Void

    init(jobId: String, authToken: String, progressHandler: ...) { }

    func connect() async throws -> ([DetectedBook], [SuggestionViewModel]) {
        // 1. Connect to SSE stream with authentication
        // 2. Stream progress updates (uploading → processing → enriching)
        // 3. Fetch results on completion
        // 4. Return detected books + suggestions
    }

    func disconnect() { }
}

// BookshelfAIService dual-mode support
func processBookshelfImageWithWebSocket(...) async throws -> (...) {
    let jobId = UUID().uuidString

    if FeatureFlags.shared.useBookshelfScanSSE {
        // SSE Path
        let scanResponse = try await startScanJob(...)
        let sseClient = BookshelfScanSSEClient(
            jobId: jobId,
            authToken: scanResponse.token,
            progressHandler: progressHandler
        )
        let result = try await sseClient.connect()
        return (image, result.0, result.1)
    } else {
        // WebSocket Path (existing)
        let result = try await processViaWebSocket(...)
        return (image, result.0, result.1)
    }
}
```

**Testing:**
- Full scan flow (image upload → SSE stream → results fetch → DetectedBook conversion)
- Multi-stage progress (uploading → processing → enriching)
- Network transition during scan (WiFi → Cellular)
- Authentication token expiry/refresh
- SSE reconnection with Last-Event-ID
- Error handling (404, 429, 500)
- Feature flag toggle (SSE ↔ WebSocket)

**Critical Bugs to Watch:**
- Authentication failures (token not passed correctly)
- SSE stream drops during long scans (>60 seconds)
- Image upload succeeds but SSE never connects
- Memory leaks from large scan results

**Success Criteria:**
- All tests pass with zero warnings
- Feature flag toggles seamlessly
- Real device testing confirms authentication works
- Scan latency within 10% of WebSocket baseline
- No regressions in detection accuracy or enrichment success rate

---

### Phase 4: Gradual Rollout & Monitoring (Weeks 7-8)

**Goal:** Safely migrate 100% of users from WebSocket to SSE

**Rollout Schedule:**
```
Week 7, Day 1-2:  5% rollout (internal team + beta testers)
Week 7, Day 3-4:  Monitor metrics, fix critical bugs
Week 7, Day 5-7:  25% rollout (early adopters)
Week 8, Day 1-2:  Monitor metrics, fix issues
Week 8, Day 3-4:  50% rollout (general users)
Week 8, Day 5:    Monitor metrics, final validation
Week 8, Day 6-7:  100% rollout (all users)
```

**Feature Flag Control:**
```swift
// Update FeatureFlags.swift
public var sseRolloutPercentage: Int {
    get { UserDefaults.standard.integer(forKey: "feature.sse.rollout") }
    set { UserDefaults.standard.set(newValue, forKey: "feature.sse.rollout") }
}

// User in SSE rollout group?
public var isInSSERollout: Bool {
    let userId = UUID().uuidString.hash
    return abs(userId % 100) < sseRolloutPercentage
}
```

**Metrics & Monitoring:**

**Performance Metrics:**
- SSE connection time (baseline: <100ms)
- SSE reconnection time (baseline: <5s)
- Progress update latency (baseline: <50ms)
- Memory usage (baseline: same as WebSocket)
- **NEW (Gemini Review):** CPU usage (<10% above WebSocket)
- **NEW (Gemini Review):** Time-to-first-message (<500ms)

**Reliability Metrics:**
- SSE connection success rate (target: >99%)
- Reconnection success rate (target: >95%)
- Results fetch success rate (target: >99%)
- Error rate by error type (404, 429, 5xx)

**Business Metrics:**
- CSV Import completion rate (target: no regression)
- Batch Enrichment success rate (target: no regression)
- Bookshelf Scan detection accuracy (target: no regression)
- User complaints/support tickets (target: no increase)

**Rollback Procedure:**

**Trigger Rollback If:**
- Error rate >5% for any feature
- Connection success rate <95%
- User complaints spike >2x baseline
- Critical bug discovered (data loss, crashes)

**Rollback Steps:**
1. Set `sseRolloutPercentage = 0` (instant rollback to WebSocket)
2. Monitor error rate decrease (should drop immediately)
3. Investigate root cause in logs
4. Fix bug, test thoroughly
5. Re-attempt rollout (start at 5% again)

**Documentation Updates:**
- `docs/IOS_VERIFICATION_REPORT.md` - Mark migration complete
- `docs/API_CONTRACT.md` - Update to reflect V2 endpoints only
- `AGENTS.md` - Update architecture diagrams (remove WebSocket)
- `CLAUDE.md` - Update development patterns

---

### Phase 5: Cleanup (Q2 2026 - April-May)

**Goal:** Remove all WebSocket code after June 1, 2026 deadline

**Files to Delete:**
```
Enrichment/EnrichmentWebSocketHandler.swift
Common/WebSocketProgressManager.swift
Common/GenericWebSocketHandler.swift
BookshelfScanning/Services/BatchWebSocketHandler.swift
Tests/WebSocketHelpersTests.swift
Tests/WebSocketProgressManagerTests.swift
Tests/BookshelfAIServiceWebSocketTests.swift
```

**Code Size Reduction:**
- ~2000 lines of WebSocket code removed
- ~1500 lines of WebSocket tests removed
- ~500 lines of dual-mode support removed
- **Total:** ~4000 lines removed

**Feature Flag Removal:**
```swift
// Delete from FeatureFlags.swift
- useBatchEnrichmentSSE
- useBookshelfScanSSE
- sseRolloutPercentage
- isInSSERollout
```

**Final Testing:**
- All existing tests still pass (WebSocket tests removed, SSE tests remain)
- Zero compiler warnings
- Real device testing (final validation)
- Performance benchmarks (confirm no regressions)

---

## Expert Review Findings

**Reviewed By:** Gemini Pro (Code Review Agent)
**Review Date:** November 27, 2025
**Overall Assessment:** "Technically sound, follows best practices"

### High Priority Issues

#### 1. Missing API Contract (CRITICAL)
**Risk:** Building a client against an undefined or poorly specified backend

**Gemini's Feedback:**
> "Critical details seem missing: Is there a formal OpenAPI/AsyncAPI spec for the new SSE endpoints? How does the server handle connection lifecycle, error conditions (e.g., auth failure, malformed requests), and heartbeats to prevent idle timeouts from proxies or load balancers?"

**Recommendations:**
- **BEFORE Phase 1:** Obtain detailed SSE API specification from backend team
- **Required Documentation:**
  - OpenAPI/AsyncAPI spec for SSE endpoints
  - Connection lifecycle handling (timeouts, heartbeats, idle detection)
  - Error response formats (auth failure, malformed requests, rate limits)
  - Event schema documentation (all event types, required/optional fields)

**Action Items:**
1. Schedule meeting with backend team (Week 1, Day 1)
2. Request formal API specification document
3. Review and validate against iOS requirements
4. Document assumptions in `docs/SSE_API_CONTRACT.md`

#### 2. Incomplete Testing Strategy
**Risk:** Server error states and network conditions not adequately tested

**Gemini's Feedback:**
> "The testing plan misses two key areas: validating server-sent error states and automated network condition simulation. Manual testing isn't scalable or consistently reproducible."

**Recommendations:**
1. **Add Integration Tests for Server Errors:**
   - Simulate server-side errors (auth failure, malformed events, timeouts)
   - Verify client handles them gracefully (error messages, reconnection logic)
   - Test edge cases (SSE stream drops mid-event, incomplete JSON, etc.)

2. **Automated Network Simulation:**
   - Use Xcode's `NetworkLinkConditioner` in tests
   - Simulate poor connectivity, high latency, packet loss
   - Ensure SSE client remains resilient across network conditions

**Updated Testing Strategy:**
```swift
// New test file: Tests/SSENetworkConditionTests.swift
@MainActor
final class SSENetworkConditionTests: XCTestCase {
    func testPoorConnectivity() async throws {
        // Simulate high latency, packet loss
        NetworkLinkConditioner.enable(profile: .poor3G)
        // Verify SSE client reconnects successfully
    }

    func testServerErrorRecovery() async throws {
        // Simulate server sending error event
        mockServer.sendEvent(type: "error", data: "{\"code\":\"AUTH_FAILURE\"}")
        // Verify client handles error gracefully
    }
}
```

### Medium Priority Issues

#### 3. Ambiguous Performance Goals
**Risk:** Subtle regressions in CPU, memory, battery consumption

**Gemini's Feedback:**
> "Performance parity is too vague. Define concrete Service Level Objectives (SLOs) with specific metrics."

**Updated Performance SLOs:**

**Performance Metrics (Concrete SLOs):**
- **Connection Time:** <100ms on stable connection
- **Reconnection Time:** <5s after network transition
- **Progress Update Latency:** <50ms from SSE event to UI update
- **Memory Footprint:** Within 5% of WebSocket baseline
- **CPU Usage:** <10% above WebSocket during active SSE connection
- **Time-to-First-Message:** <500ms after connection established
- **Battery Impact:** <5% increase over WebSocket (measured via Xcode Instruments)

**Measurement Plan:**
- Baseline WebSocket performance in Phase 1 (before migration)
- Measure SSE performance in Phase 2-3 (during implementation)
- Compare metrics in Phase 4 (rollout)
- Document results in `docs/PERFORMANCE_BENCHMARKS.md`

#### 4. Timeline Aggressiveness
**Risk:** 8-week timeline may hide complexity in Phases 2-3

**Gemini's Feedback:**
> "An 8-week timeline seems optimistic. Phases 2 and 3 could hide significant complexity, especially around state management and UI updates tailored to WebSocket's bidirectional nature."

**Revised Timeline:**
- **Phase 1:** 2 weeks (Foundation - realistic)
- **Phase 2:** 2-3 weeks (Batch Enrichment - add 1 week buffer for complexity)
- **Phase 3:** 2-3 weeks (Bookshelf Scan - add 1 week buffer for auth complexity)
- **Phase 4:** 2 weeks (Rollout - realistic)
- **Phase 5:** 1-2 weeks (Cleanup - integrated into phases or shortened)

**Total:** 9-12 weeks (more realistic)

**Risk Mitigation:**
- Time-box initial investigation (1-2 days per feature) BEFORE Phase 2-3
- Identify complexities early (state management, UI updates, error handling)
- Adjust timeline after technical spike

### Positives (Strengths)

**Gemini's Feedback:**
> "The 5-phase approach is excellent. It correctly isolates foundational work, de-risks the migration by tackling features sequentially, and ensures technical debt is addressed."

- Strategy: Phased approach with dual-mode support
- Backward Compatibility: Feature flags for gradual rollout
- Swift 6 Concurrency: Actor isolation, @Sendable compliance
- Real-World Testing: Prioritizing real device testing for network transitions

---

## Risk Analysis & Mitigation

### Critical Risks

#### Risk 1: Backend SSE Endpoints Delayed
**Probability:** MEDIUM
**Impact:** HIGH (blocks entire migration)

**Mitigation:**
- Weekly check-ins with backend team (confirm delivery dates)
- Prototype SSE client against mock server (Phase 1 can proceed without backend)
- Have backend commit to delivery dates in writing
- Escalate to management if delays threaten March 1 deadline

#### Risk 2: API Contract Mismatch
**Probability:** MEDIUM
**Impact:** HIGH (significant rework required)

**Mitigation:**
- Obtain formal API specification BEFORE Phase 1 implementation
- Review API contract with backend team (weekly syncs)
- Validate event schemas against backend implementation
- Document assumptions in `docs/SSE_API_CONTRACT.md`

#### Risk 3: Performance Regression
**Probability:** LOW (SSE typically faster than WebSocket)
**Impact:** HIGH (poor UX, user complaints)

**Mitigation:**
- Benchmark SSE vs WebSocket in Phase 2-3 (before rollout)
- Monitor latency metrics in production (Phase 4)
- Instant rollback via feature flags if performance degrades
- Optimize SSE client if needed (connection pooling, buffering)

### High Risks

#### Risk 4: Network Transition Failures
**Probability:** MEDIUM
**Impact:** HIGH (scan/enrichment jobs fail mid-process)

**Mitigation:**
- Extensive real device testing (WiFi ↔ Cellular)
- Last-Event-ID reconnection (already proven in CSV Import)
- Retry logic with exponential backoff
- Automated network simulation tests (`NetworkLinkConditioner`)

#### Risk 5: Authentication Issues (Bookshelf Scan)
**Probability:** MEDIUM
**Impact:** HIGH (scans fail to connect)

**Mitigation:**
- Clarify auth scheme with backend early (query param? header?)
- Test token expiry and refresh scenarios
- Implement token refresh logic if needed
- Fallback error messaging if auth fails

### Medium Risks

#### Risk 6: Integration Bugs (SwiftData Corruption)
**Probability:** LOW
**Impact:** HIGH (data loss, user complaints)

**Mitigation:**
- Extensive testing (unit + integration + real device)
- Gradual rollout (5% → 100%) to catch issues early
- Monitor error rates during rollout
- Instant rollback if data corruption detected

#### Risk 7: Incomplete WebSocket Removal
**Probability:** LOW
**Impact:** MEDIUM (technical debt, confusing codebase)

**Mitigation:**
- Comprehensive search for WebSocket references (Phase 5)
- Deprecation warnings in code
- Final audit before June 1, 2026 deadline
- Code review before cleanup PR

---

## Testing Strategy

### Unit Tests (90%+ Coverage)

**Generic SSE Client:**
- SSE event parsing (initialized, processing, completed, failed)
- Last-Event-ID reconnection
- Network error handling
- Event buffering (chunked SSE streams)
- Timeout scenarios
- Concurrent connections

**Feature-Specific Clients:**
- `EnrichmentSSEClient` event handling
- `BookshelfScanSSEClient` authentication
- Results fetching (200, 404, 429, 5xx)
- Error propagation to UI

### Integration Tests

**Full Flow Testing:**
- CSV Import: Upload → SSE stream → Results fetch (already exists)
- Batch Enrichment: Upload → SSE stream → Results fetch → SwiftData save
- Bookshelf Scan: Image upload → SSE stream → Results fetch → DetectedBook conversion

**Error Scenarios:**
- Server-side errors (auth failure, malformed events, timeouts)
- Network errors (disconnection, reconnection, timeout)
- Rate limiting (429 with retry-after)
- Results expiry (404 after 2-hour TTL)

**Network Simulation:**
```swift
// NEW: Automated network condition testing
@MainActor
final class SSENetworkConditionTests: XCTestCase {
    func testPoor3G() async throws {
        NetworkLinkConditioner.enable(profile: .poor3G)
        // Verify SSE client reconnects successfully
    }

    func testHighLatency() async throws {
        NetworkLinkConditioner.enable(profile: .highLatency)
        // Verify progress updates still arrive
    }

    func testPacketLoss() async throws {
        NetworkLinkConditioner.enable(profile: .lossyNetwork)
        // Verify SSE client retries correctly
    }
}
```

### Real Device Testing

**Devices:**
- iPhone 15 Pro (iOS 18.1+)
- iPad Pro (iOS 18.1+)

**Network Scenarios:**
- WiFi → Cellular mid-operation
- Airplane mode → WiFi reconnection
- Low signal strength (throttled connection)
- Background app → foreground resume

**Critical Bugs to Watch:**
- SSE stream drops without reconnection
- Data loss during network transition
- Memory leaks (long-running SSE connections)
- UI freezes (actor isolation violations)
- Authentication failures (Bookshelf Scan)

### Performance Testing

**Metrics to Measure:**
- Connection time (<100ms)
- Reconnection time (<5s)
- Progress update latency (<50ms)
- Memory footprint (within 5% of WebSocket)
- CPU usage (<10% above WebSocket)
- Time-to-first-message (<500ms)
- Battery impact (<5% increase)

**Tools:**
- Xcode Instruments (Time Profiler, Allocations, Network)
- Real device monitoring (WiFi/Cellular data usage)
- Analytics (Firebase, Mixpanel) for production metrics

---

## Rollout Plan

### Rollout Schedule

```
[Phase 4: Gradual Rollout - Weeks 7-8]

Week 7:
  Day 1-2:  5% rollout  (internal team + beta testers)
            ├─ Enable feature flag for 5% of users
            ├─ Monitor dashboards for errors/performance
            └─ Slack alert channel for critical issues

  Day 3-4:  Monitor      (5% cohort metrics analysis)
            ├─ Review connection success rate (target: >99%)
            ├─ Check error rates (target: <1%)
            ├─ Validate performance SLOs
            └─ Fix critical bugs if found

  Day 5-7:  25% rollout (early adopters)
            ├─ Increase rollout percentage to 25%
            ├─ Continue monitoring
            └─ Collect user feedback

Week 8:
  Day 1-2:  Monitor      (25% cohort metrics analysis)
            ├─ Review business metrics (no regression)
            ├─ Check user complaints (target: no increase)
            └─ Validate performance SLOs

  Day 3-4:  50% rollout (general users)
            ├─ Increase rollout percentage to 50%
            ├─ High-alert monitoring (majority of users)
            └─ Prepare rollback plan

  Day 5:    Monitor      (50% cohort final validation)
            ├─ Review all metrics
            ├─ Confirm stability
            └─ Get stakeholder approval for 100%

  Day 6-7:  100% rollout (all users)
            ├─ Enable SSE for all users
            ├─ Monitor for 48 hours
            └─ Mark migration COMPLETE
```

### Monitoring Dashboard

**Real-Time Metrics (Phase 4):**
- SSE connection success rate (by feature)
- Error rate (404, 429, 5xx breakdown)
- Performance metrics (latency, memory, CPU)
- User cohort breakdown (5%, 25%, 50%, 100%)

**Alerts:**
- Error rate >5% for any feature → Slack alert
- Connection success rate <95% → Slack alert
- Performance SLO violation → Slack alert
- Critical bug reported → Page on-call engineer

**Dashboard Tools:**
- Firebase Analytics (user cohorts, error rates)
- Mixpanel (business metrics, user behavior)
- Xcode Organizer (crash reports, energy usage)
- Backend logs (SSE stream errors, rate limits)

### Rollback Procedure

**Trigger Conditions:**
- Error rate >5% for any feature
- Connection success rate <95%
- User complaints spike >2x baseline
- Critical bug discovered (data loss, crashes)

**Rollback Steps:**
1. **Immediate:** Set `sseRolloutPercentage = 0` (instant rollback to WebSocket)
2. **Monitor:** Error rate should drop within 5 minutes
3. **Investigate:** Review logs, crash reports, user feedback
4. **Fix:** Patch bug, test thoroughly in staging
5. **Retry:** Re-attempt rollout (start at 5% again after fix)

**Rollback Tool:**
```swift
// Admin-only function (remote config trigger)
func emergencyRollback(reason: String) {
    FeatureFlags.shared.sseRolloutPercentage = 0
    FeatureFlags.shared.useBatchEnrichmentSSE = false
    FeatureFlags.shared.useBookshelfScanSSE = false

    // Log for post-mortem
    Analytics.log(event: "sse_rollback", parameters: [
        "reason": reason,
        "timestamp": Date(),
        "rollout_percentage_at_rollback": FeatureFlags.shared.sseRolloutPercentage
    ])

    // Alert engineering team
    NotificationCenter.default.post(name: .sseRollbackTriggered, object: reason)
}
```

---

## Questions for Backend Team

### Priority 1 (Blocking Implementation)

1. **SSE Endpoint Timeline:**
   - When will `/api/v2/enrichments/{jobId}/stream` be ready?
   - When will `/api/v2/scans/{jobId}/stream` be ready?
   - Can we get a formal commitment date (for project planning)?

2. **API Specification:**
   - Is there a formal OpenAPI/AsyncAPI spec for SSE endpoints?
   - What event types will be sent (initialized, processing, completed, failed)?
   - What fields are required/optional in each event?
   - How does the server handle heartbeats/idle timeouts?

3. **Authentication for Bookshelf Scan:**
   - How will SSE handle authentication tokens?
   - Query parameter: `?token={authToken}`?
   - Authorization header: `Authorization: Bearer {authToken}`?
   - Token expiry/refresh strategy?

4. **Books Array in Results:**
   - API contract §7.4 mentions `books[]` array in CSV import results
   - Current iOS implementation only uses summary counts
   - Is `books[]` required for detailed import results?
   - What fields are included in each book object?

5. **TTL Enforcement:**
   - Is 2-hour TTL enforced server-side for all results endpoints?
   - Should iOS perform client-side validation using `expiresAt` field?
   - Do batch enrichment and scan results have the same TTL?

### Priority 2 (Future Planning)

6. **Error Handling:**
   - What error codes/messages will SSE send (auth failure, rate limit, etc.)?
   - How should iOS handle malformed SSE events?
   - What retry strategy is recommended for 5xx errors?

7. **Semantic Search:**
   - Confirm December 2025 timeline for Bearer token auth
   - Rate limit details: 20 req/min per user or per token?
   - Will there be a `/api/v2/search/semantic` endpoint?

8. **WebSocket Deprecation:**
   - Confirm March 1, 2026 deprecation date
   - Confirm June 1, 2026 removal date
   - Will deprecation warnings be sent via WebSocket events?

---

## Success Criteria

### Technical Success

- Zero compiler warnings (Swift 6 strict concurrency)
- >99% SSE connection success rate (production metrics)
- <10% latency variance vs WebSocket baseline
- Zero data loss during network transitions
- 100% feature parity (no regressions in functionality)
- All tests pass (unit, integration, real device)

### Performance Success

**Service Level Objectives (SLOs):**
- Connection time: <100ms on stable connection
- Reconnection time: <5s after network transition
- Progress update latency: <50ms from event to UI
- Memory footprint: Within 5% of WebSocket baseline
- CPU usage: <10% above WebSocket during active connection
- Time-to-first-message: <500ms after connection
- Battery impact: <5% increase over WebSocket

### Business Success

- Migration complete by March 1, 2026 (deprecation deadline)
- No production incidents during rollout
- No regression in feature usage metrics
- Positive or neutral user feedback
- WebSocket code removed by June 1, 2026

---

## Next Steps

### Immediate Actions (This Week)

1. **Day 1:** Kickoff meeting with backend team
   - Confirm SSE endpoint delivery timeline (Q1 2026)
   - Request formal API specification (OpenAPI/AsyncAPI)
   - Clarify authentication scheme for Bookshelf Scan
   - Review TTL handling and books array requirements

2. **Day 2:** Create project structure
   - Set up feature branches (`feature/sse-foundation`, `feature/sse-enrichment`, `feature/sse-scan`)
   - Create placeholder files for Phase 1 deliverables
   - Set up test infrastructure (`MockSSEServer`, test suites)

3. **Day 3-5:** Phase 1 Foundation (Week 1)
   - Extract `GenericSSEClient` from CSV Import `SSEClient`
   - Define event schemas (`EnrichmentSSEModels`, `ScanSSEModels`)
   - Add feature flags to `FeatureFlags.swift`
   - Write unit tests (90%+ coverage target)

### Phase 1 Checklist (Weeks 1-2)

- [ ] Backend meeting complete (API contract, timelines, auth scheme)
- [ ] `GenericSSEClient.swift` created and tested
- [ ] `SSEEventHandling` protocol defined
- [ ] `EnrichmentSSEModels.swift` created (event schemas)
- [ ] `ScanSSEModels.swift` created (event schemas)
- [ ] Feature flags added (`useBatchEnrichmentSSE`, `useBookshelfScanSSE`, `sseRolloutPercentage`)
- [ ] V2 endpoints configured (`EnrichmentConfig.swift`)
- [ ] Test infrastructure complete (`MockSSEServer`, unit tests)
- [ ] All tests pass with zero warnings
- [ ] CSV Import refactored to use `GenericSSEClient` (optional, backward compatible)

### Phase 2 Checklist (Weeks 3-4)

- [ ] Backend SSE endpoint ready (`/api/v2/enrichments/{jobId}/stream`)
- [ ] `EnrichmentSSEClient.swift` implemented
- [ ] `EnrichmentQueue.swift` updated with protocol abstraction
- [ ] V2 results fetching implemented
- [ ] Integration tests written (full enrichment flow)
- [ ] Real device testing complete (network transitions)
- [ ] Performance benchmarks captured (baseline vs SSE)
- [ ] All tests pass with zero warnings
- [ ] Feature flag toggle validated (SSE ↔ WebSocket)

### Phase 3 Checklist (Weeks 5-6 OR 3-4 if parallel)

- [ ] Backend SSE endpoint ready (`/api/v2/scans/{jobId}/stream`)
- [ ] Authentication scheme clarified (query param vs header)
- [ ] `BookshelfScanSSEClient.swift` implemented
- [ ] `BookshelfAIService.swift` updated with dual-mode support
- [ ] V2 results fetching with auth implemented
- [ ] Integration tests written (full scan flow, auth)
- [ ] Real device testing complete (auth, network transitions)
- [ ] Performance benchmarks captured (baseline vs SSE)
- [ ] All tests pass with zero warnings
- [ ] Feature flag toggle validated (SSE ↔ WebSocket)

### Phase 4 Checklist (Weeks 7-8)

- [ ] Monitoring dashboard configured (Firebase, Mixpanel)
- [ ] Rollout plan documented and approved
- [ ] 5% rollout complete (internal team + beta testers)
- [ ] Metrics reviewed (connection success >99%, error rate <1%)
- [ ] 25% rollout complete (early adopters)
- [ ] Metrics reviewed (business metrics, user feedback)
- [ ] 50% rollout complete (general users)
- [ ] Metrics reviewed (final validation)
- [ ] 100% rollout complete (all users)
- [ ] Migration marked COMPLETE in documentation

### Phase 5 Checklist (April-May 2026)

- [ ] WebSocket code removed (7 files deleted, ~4000 lines)
- [ ] Feature flags removed (`FeatureFlags.swift`)
- [ ] Final testing complete (all tests pass, zero warnings)
- [ ] Documentation updated (remove WebSocket references)
- [ ] Retrospective conducted (lessons learned)
- [ ] Migration retrospective added to docs

---

## Appendix

### File Structure Changes

**New Files (Phase 1):**
```
BooksTrackerPackage/Sources/BooksTrackerFeature/
  ├── Common/
  │   ├── GenericSSEClient.swift                 (+400 lines)
  │   ├── SSEEventHandling.swift                 (protocol)
  │   ├── EnrichmentSSEModels.swift              (+150 lines)
  │   └── ScanSSEModels.swift                    (+150 lines)
  └── Tests/
      ├── GenericSSEClientTests.swift            (+500 lines)
      └── MockSSEServer.swift                    (+200 lines)
```

**New Files (Phase 2):**
```
BooksTrackerPackage/Sources/BooksTrackerFeature/
  ├── Enrichment/
  │   └── EnrichmentSSEClient.swift              (+300 lines)
  └── Tests/
      ├── EnrichmentSSEClientTests.swift         (+400 lines)
      └── EnrichmentSSEIntegrationTests.swift    (+300 lines)
```

**New Files (Phase 3):**
```
BooksTrackerPackage/Sources/BooksTrackerFeature/
  ├── BookshelfScanning/Services/
  │   └── BookshelfScanSSEClient.swift           (+350 lines)
  └── Tests/
      ├── BookshelfScanSSEClientTests.swift      (+500 lines)
      └── BookshelfScanSSEIntegrationTests.swift (+400 lines)
```

**Updated Files:**
```
BooksTrackerPackage/Sources/BooksTrackerFeature/
  ├── Common/
  │   ├── FeatureFlags.swift                     (+30 lines)
  │   └── EnrichmentConfig.swift                 (+20 lines)
  ├── Enrichment/
  │   └── EnrichmentQueue.swift                  (~10 lines changed)
  └── BookshelfScanning/Services/
      └── BookshelfAIService.swift               (~30 lines changed)
```

**Deleted Files (Phase 5):**
```
BooksTrackerPackage/Sources/BooksTrackerFeature/
  ├── Enrichment/
  │   └── EnrichmentWebSocketHandler.swift       (-200 lines)
  ├── Common/
  │   ├── WebSocketProgressManager.swift         (-800 lines)
  │   └── GenericWebSocketHandler.swift          (-600 lines)
  └── BookshelfScanning/Services/
      └── BatchWebSocketHandler.swift            (-400 lines)

Tests:
  ├── WebSocketHelpersTests.swift                (-500 lines)
  ├── WebSocketProgressManagerTests.swift        (-600 lines)
  └── BookshelfAIServiceWebSocketTests.swift     (-400 lines)
```

### Code Size Impact

**Added:**
- Phase 1: ~1400 lines (foundation)
- Phase 2: ~1000 lines (enrichment)
- Phase 3: ~1250 lines (scan)
- **Total Added:** ~3650 lines

**Removed (Phase 5):**
- WebSocket code: ~2000 lines
- WebSocket tests: ~1500 lines
- Dual-mode support: ~500 lines
- **Total Removed:** ~4000 lines

**Net Change:** -350 lines (cleaner codebase)

---

## Document History

**Version 1.0 (November 27, 2025):**
- Initial plan created with Zen Planner (Gemini 2.5 Pro)
- Expert review by Gemini Pro (Code Review Agent)
- Incorporated feedback on API contract, testing strategy, performance SLOs
- Revised timeline from 8 to 9-12 weeks based on complexity analysis

**Next Review:** January 15, 2026 (after backend SSE endpoints delivered)

---

**Plan Status:** READY FOR IMPLEMENTATION
**Owner:** iOS Team (jukasdrj)
**Stakeholders:** Backend Team, Product Team, QA Team
**Deadline:** March 1, 2026 (WebSocket deprecation)
**Hard Cutoff:** June 1, 2026 (WebSocket removal)
