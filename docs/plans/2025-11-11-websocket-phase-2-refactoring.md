# WebSocket Phase 2: Refactoring & Standardization

**Date:** November 11, 2025
**Status:** 📋 Backlog
**Priority:** Medium (Post-Production Stabilization)
**Depends On:** Phase 1 completion

## Overview

Phase 2 focuses on refactoring and standardization of WebSocket handlers after Phase 1 critical fixes are production-stable. These improvements will reduce code duplication, improve maintainability, and establish consistent patterns.

**Timeline:** Defer until after Phase 1 is validated in production (2-4 weeks post-deployment)

---

## Deferred Fixes from Phase 1

### Fix #5: Refactor to Single WebSocket Handler Base Class

**Priority:** Medium
**Complexity:** Medium
**Estimated Effort:** 2-3 days

**Current State:**

We have **4 separate WebSocket handler implementations** with significant code duplication:

1. **WebSocketProgressManager** (Common/)
   - Generic progress tracking for any job type
   - Polls for initial connection, then switches to WebSocket
   - Handles all 3 pipelines: ai_scan, csv_import, batch_enrichment

2. **BatchWebSocketHandler** (BookshelfScanning/Services/)
   - Specialized for batch scan progress
   - Uses BatchProgress model
   - Actor-isolated for thread safety

3. **EnrichmentWebSocketHandler** (Enrichment/)
   - Legacy handler for batch enrichment
   - Predates unified schema migration

4. **GenericWebSocketHandler** (Common/)
   - Generic handler for any WebSocket connection
   - Used by GeminiCSVImportView

**Code Duplication:**
- WebSocket connection logic (resume, handshake wait)
- Message parsing (JSON decoding, type checking)
- Error handling (disconnection, timeout)
- Ready signal sending
- Callback patterns

**Proposed Solution:**

Create a **base actor class** that all handlers inherit from:

```swift
actor WebSocketHandlerBase {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private var isConnected = false

    // Abstract methods (subclasses override)
    func handleMessage(_ message: TypedWebSocketMessage) async
    func onDisconnect() async

    // Shared implementation
    func connect(wsURL: URL, timeout: TimeInterval = 10.0) async throws {
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: wsURL)
        webSocket?.resume()

        if let webSocket = webSocket {
            try await WebSocketHelpers.waitForConnection(webSocket, timeout: timeout)
        }

        isConnected = true
        await sendReadySignal()
        await listenForMessages()
    }

    func sendReadySignal() async throws {
        let readyMessage: [String: Any] = [
            "type": "ready",
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        // ... send logic
    }

    private func listenForMessages() async {
        // ... message loop with error handling
    }

    func disconnect() {
        // ... cleanup
    }
}
```

**Subclass Example:**

```swift
actor BatchWebSocketHandler: WebSocketHandlerBase {
    private let onProgress: @MainActor (BatchProgress) -> Void
    private var totalPhotos: Int = 0

    override func handleMessage(_ message: TypedWebSocketMessage) async {
        guard message.pipeline == .aiScan else { return }

        switch message.payload {
        case .jobStarted(let payload):
            await initializeBatchProgress(totalPhotos: payload.totalCount ?? 0)
        case .jobProgress(let payload):
            await processProgressUpdate(payload)
        // ...
        }
    }
}
```

**Benefits:**
- 70% less code duplication
- Consistent connection/disconnection patterns
- Single source of truth for WebSocket behavior
- Easier to add new handlers
- Reduced test surface area

**Risks:**
- Breaking changes to existing handlers
- Requires thorough testing of all 3 workflows
- Potential Swift actor inheritance complexity

**Testing Strategy:**
- Unit tests for base class methods
- Integration tests for each subclass
- Manual testing of all 3 workflows
- Compare logs with Phase 1 behavior

---

### Fix #6: Standardize Callback Patterns

**Priority:** Low
**Complexity:** Low
**Estimated Effort:** 1 day

**Current State:**

**Inconsistent callback patterns** across handlers:

1. **BatchWebSocketHandler:**
   - Creates fresh `BatchProgress` instances per callback
   - Callback replaces entire object

2. **WebSocketProgressManager:**
   - Creates fresh `JobProgress` instances per callback
   - Callback replaces entire object

3. **EnrichmentWebSocketHandler:**
   - Updates existing `EnrichedBook` objects
   - Callback passes reference

**Proposed Solution:**

**Adopt consistent "replace entire object" pattern:**

```swift
// ✅ STANDARD PATTERN: Create fresh instance per callback
await MainActor.run {
    let progress = ProgressType(jobId: jobId, state: currentState)
    onProgress(progress)
}

// ❌ AVOID: Mutating shared state
await MainActor.run {
    sharedProgress.status = newStatus
    onProgress(sharedProgress)  // Observers might miss updates
}
```

**Rationale:**
- SwiftUI observes object replacement more reliably
- Avoids actor isolation issues with shared state
- Clearer data flow (functional pattern)
- Easier to reason about concurrency

**Implementation:**
- Update EnrichmentWebSocketHandler to match BatchWebSocketHandler pattern
- Document pattern in code comments
- Add unit tests verifying callback invocation

**Benefits:**
- Consistent behavior across all handlers
- Reduced cognitive load for developers
- Fewer concurrency bugs

---

## Additional Phase 2 Tasks

### Documentation

**Priority:** High (before next feature work)
**Effort:** 1 day

**Tasks:**
1. **WebSocket Architecture Documentation**
   - Overall system design
   - Message flow diagrams (Mermaid)
   - Pipeline routing rules
   - Error handling strategies

2. **Handler Development Guide**
   - When to create new handlers vs. reuse existing
   - Actor isolation best practices
   - Callback pattern guidelines
   - Testing checklist

3. **Troubleshooting Guide**
   - Common WebSocket errors and solutions
   - Debugging techniques
   - Log interpretation guide

**Deliverables:**
- `docs/architecture/websocket-architecture.md`
- `docs/guides/websocket-handler-development.md`
- `docs/guides/websocket-troubleshooting.md`

---

### Automated Testing

**Priority:** Medium
**Effort:** 2-3 days

**Current State:**
- Zero automated tests for WebSocket handlers
- Manual testing only

**Proposed Tests:**

**Unit Tests:**
```swift
@Test("WebSocketProgressManager calculates progress correctly")
func testProgressCalculation() async throws {
    let manager = WebSocketProgressManager()
    let result = manager.calculateProgress(current: 0.5, total: 1.0)
    #expect(result == 0)  // Binary logic for single-item
}

@Test("BatchWebSocketHandler invokes callback on job_started")
func testBatchCallbackInvocation() async throws {
    var callbackInvoked = false
    let handler = BatchWebSocketHandler(
        jobId: "test",
        onProgress: { _ in callbackInvoked = true }
    )
    // ... simulate job_started message
    #expect(callbackInvoked == true)
}
```

**Integration Tests:**
```swift
@Test("End-to-end single scan WebSocket flow")
func testSingleScanFlow() async throws {
    // 1. Connect to WebSocket
    // 2. Send ready signal
    // 3. Receive job_started
    // 4. Receive job_progress
    // 5. Receive job_complete
    // 6. Verify final state
}
```

**Mock Backend:**
- Simulate Durable Object responses
- Test all message types (job_started, job_progress, job_complete, error)
- Test error scenarios (timeout, disconnection)

**Benefits:**
- Catch regressions early
- CI/CD integration
- Faster development cycles
- Confidence in refactoring

---

### Performance Monitoring

**Priority:** Low
**Effort:** 1 day

**Current State:**
- Debug print statements only
- No metrics collection

**Proposed Enhancements:**

**Add metrics tracking:**
```swift
actor WebSocketMetrics {
    var connectionTime: TimeInterval = 0
    var messageCount: Int = 0
    var errorCount: Int = 0
    var lastMessageTimestamp: Date?

    func recordConnection(duration: TimeInterval) { /* ... */ }
    func recordMessage() { /* ... */ }
    func recordError() { /* ... */ }

    func generateReport() -> String {
        """
        WebSocket Metrics:
        - Connection time: \(connectionTime)s
        - Messages received: \(messageCount)
        - Errors: \(errorCount)
        - Average message rate: \(messageCount / totalTime) msg/s
        """
    }
}
```

**Benefits:**
- Identify performance bottlenecks
- Track error rates in production
- Optimize message processing
- Better debugging insights

---

## Implementation Plan

### Phase 2.1: Foundation (Week 1)

**Goals:**
- Document current architecture
- Write unit tests for existing handlers
- Establish metrics baseline

**Deliverables:**
- Architecture documentation complete
- 80% unit test coverage
- Metrics tracking integrated

---

### Phase 2.2: Refactoring (Week 2-3)

**Goals:**
- Implement `WebSocketHandlerBase` class
- Migrate all handlers to new base class
- Standardize callback patterns

**Deliverables:**
- `WebSocketHandlerBase` complete
- All 4 handlers migrated
- Zero regressions (manual testing)

**Validation Checklist:**
- [ ] Single scan works (compare logs with Phase 1)
- [ ] Batch scan works (all photos processed)
- [ ] CSV import works (parsing + enrichment)
- [ ] Error handling works (simulate disconnection)
- [ ] Build succeeds with zero warnings

---

### Phase 2.3: Testing & Stabilization (Week 4)

**Goals:**
- Integration tests complete
- Beta testing on TestFlight
- Performance benchmarking

**Deliverables:**
- Integration test suite
- Performance report
- Bug fixes from beta testing

---

## Success Metrics

**Code Quality:**
- 70% reduction in WebSocket handler code duplication
- 90%+ unit test coverage
- Zero compiler warnings

**Reliability:**
- Zero WebSocket connection failures in beta (7 days)
- 100% message delivery rate
- <5s average connection time

**Maintainability:**
- New handler creation takes <2 hours (vs. current 1 day)
- Onboarding doc reduces ramp-up time by 50%

---

## Risks & Mitigations

**Risk:** Refactoring breaks existing functionality

**Mitigation:**
- Comprehensive unit tests before refactoring
- Manual testing checklist
- Phased rollout (1 handler at a time)
- Feature flag to enable/disable new base class

---

**Risk:** Swift actor inheritance complexity

**Mitigation:**
- Prototype base class design first
- Consult Swift concurrency experts
- Consider composition over inheritance if needed

---

## Decision Log

**Why defer Phase 2?**
- Phase 1 fixes are critical for production stability
- Refactoring requires thorough testing (2-3 weeks)
- Risk of introducing new bugs during refactoring
- Better to validate Phase 1 in production first

**Why not use protocol instead of base class?**
- Actors can inherit from other actors (Swift 6+)
- Base class allows shared implementation (not just interface)
- Reduces code duplication more effectively

**Why standardize on "replace object" pattern?**
- SwiftUI observation works more reliably
- Avoids actor isolation issues with shared mutable state
- Functional pattern is easier to reason about

---

## Related Issues

- #347 - WebSocket connection failures (fixed in Phase 1)
- #378 - Batch scan UI not updating (fixed in Phase 1)
- #379 - CSV import progress stuck (fixed in Phase 1)

---

## References

- Phase 1 completion summary: `2025-11-11-websocket-phase-1-completion-summary.md`
- Unified schema design: `2025-10-30-unified-websocket-schema.md`
- Swift concurrency guide: `docs/CONCURRENCY_GUIDE.md`

---

**Status:** Backlog (defer until Phase 1 is production-stable for 2-4 weeks)
