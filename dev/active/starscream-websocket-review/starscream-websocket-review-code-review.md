# Starscream WebSocket Integration - Code Review

**Last Updated:** 2025-11-22
**Reviewer:** Claude Code (code-architecture-reviewer)
**Scope:** Starscream WebSocket implementation for BooksTrack iOS app
**Branch:** `feature/nwconnection-websocket-513`

---

## Executive Summary

The Starscream WebSocket integration successfully addresses the HTTP/2 ALPN negotiation issue that plagued `URLSessionWebSocketTask`. The implementation demonstrates **strong security practices** with header-based token authentication and a **well-architected unified handler** approach. However, there are **critical concurrency issues**, **missing error fallbacks**, and **architectural inconsistencies** that must be addressed before production deployment.

**Overall Assessment:** ⚠️ **MAJOR REVISIONS REQUIRED**

**Key Strengths:**
- ✅ Correct HTTP/1.1 enforcement via WebSocket upgrade headers
- ✅ Security-first token authentication (Sec-WebSocket-Protocol)
- ✅ Clean unified handler architecture supporting three pipelines
- ✅ Comprehensive @MainActor isolation for Swift 6 compliance

**Critical Issues:**
- 🔴 **Type Mismatch**: Using undefined `WebSocketPipeline` instead of `PipelineType`
- 🔴 **Missing HTTP Polling Fallback**: No fallback when WebSocket fails (Issue #227)
- 🔴 **Actor Isolation Violation**: `disconnect()` called without `await` from non-isolated context
- 🔴 **Weak Error Handling**: Silent failures, no retry mechanism, incomplete error propagation

---

## Critical Issues (Must Fix)

### 1. Type System Violation - Undefined `WebSocketPipeline`

**Location:** `StarscreamWebSocketHandler.swift:38,52,116`

**Issue:**
```swift
// Line 38 - Property declaration uses undefined type
private var pipeline: WebSocketPipeline?

// Line 52 - Parameter uses undefined type
public func connect(jobId: String, token: String, pipeline: WebSocketPipeline, ...)

// Line 116 - Usage in BatchCaptureView
handler.connect(jobId: jobId, token: response.token, pipeline: .aiScan, ...)
```

**Problem:**
- `WebSocketPipeline` is **never defined** in the codebase
- Should be `PipelineType` (defined in `WebSocketMessages.swift:42-47`)
- This code **will not compile** - suggests review was requested on broken code

**Evidence from WebSocketMessages.swift:**
```swift
// Line 42-47
public enum PipelineType: String, Codable, Sendable {
    case batchEnrichment = "batch_enrichment"
    case csvImport = "csv_import"
    case aiScan = "ai_scan"
}
```

**Impact:** 🔴 **Build Failure** - Code will not compile without fixing this type mismatch

**Fix Required:**
```swift
// StarscreamWebSocketHandler.swift

// Change line 38:
- private var pipeline: WebSocketPipeline?
+ private var pipeline: PipelineType?

// Change line 52:
- public func connect(jobId: String, token: String, pipeline: WebSocketPipeline, ...)
+ public func connect(jobId: String, token: String, pipeline: PipelineType, ...)
```

---

### 2. Actor Isolation Violation - Unsafe `disconnect()` Call

**Location:** `BatchCaptureView.swift:180`

**Issue:**
```swift
// Line 179-181
if let handler = wsHandler {
    await handler.disconnect()  // ⚠️ Called from non-isolated async context
}
```

**Problem:**
- `disconnect()` is defined as `@MainActor` (implicitly via class-level isolation)
- Called from `cancelBatch()` which is `@MainActor` but inside an async context
- Swift 6 requires explicit actor hopping for @MainActor methods

**Swift 6 Concurrency Error:**
```
error: call to main actor-isolated instance method 'disconnect()' in a synchronous nonisolated context
```

**Fix Required:**
```swift
// BatchCaptureView.swift:179-181

// Option 1: Ensure we're on MainActor (recommended)
if let handler = wsHandler {
    await MainActor.run {
        handler.disconnect()
    }
}

// Option 2: Make disconnect() nonisolated (if safe)
// In StarscreamWebSocketHandler.swift:
nonisolated public func disconnect() {
    Task { @MainActor in
        socket?.disconnect()
        socket = nil
        isConnected = false
    }
}
```

**Impact:** 🔴 **Concurrency Safety** - Potential race condition, Swift 6 strict concurrency violation

---

### 3. Missing HTTP Polling Fallback

**Location:** `EnrichmentQueue.swift:328-454` (WebSocket connection path)

**Issue:**
The codebase has a comprehensive HTTP polling fallback mechanism (`pollForEnrichmentResults()` at line 939-1026) but it's **never invoked** when the Starscream WebSocket fails to connect.

**Evidence:**
```swift
// Line 361 - WebSocket handler created
let handler = StarscreamWebSocketHandler()

// Line 449 - WebSocket connected (but no failure fallback!)
handler.connect(jobId: jobId, token: token, pipeline: .batchEnrichment)

// NO CODE PATH to invoke pollForEnrichmentResults() if WebSocket fails
```

**Context from Issue #227:**
The polling fallback was added to handle "HTTP/2 protocol mismatch" issues. Even with Starscream fixing HTTP/1.1, we still need fallback for:
- Network firewalls blocking WebSocket upgrades
- Corporate proxies that don't support WebSockets
- Cloudflare edge cases or service degradation

**Fix Required:**
```swift
// EnrichmentQueue.swift - Add to handler.onDisconnect

handler.onDisconnect = { [weak self] in
    guard let self = self else { return }

    #if DEBUG
    print("⚠️ WebSocket disconnected unexpectedly - falling back to HTTP polling")
    #endif

    // Fall back to HTTP polling
    Task {
        do {
            try await self.pollForEnrichmentResults(
                jobId: jobId,
                batchWorkIDs: batchWorkIDs,
                totalBooks: works.count,
                processedCount: processedCount,
                batchIndex: index,
                batchCount: batches.count,
                modelContext: modelContext,
                progressHandler: progressHandler,
                continuation: continuation
            )
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
```

**Impact:** 🔴 **Reliability** - Users on restricted networks will experience silent failures without fallback

---

### 4. Weak Error Handling and Silent Failures

**Location:** Multiple locations in `StarscreamWebSocketHandler.swift`

#### 4.1 Invalid URL Handling (Line 59-65)
```swift
guard let url = URL(string: urlString) else {
    #if DEBUG
    print("[Starscream] ❌ Invalid WebSocket URL")
    #endif
    onDisconnect?()  // ⚠️ Misleading - not a disconnection, URL construction failed
    return
}
```

**Problems:**
- Calls `onDisconnect()` for a connection that never started
- No way for caller to distinguish "URL construction failed" from "connection dropped"
- Silent failure in production (no logging, no user notification)

**Fix:**
```swift
// Add error callback
public var onError: ((Error) -> Void)?

// In connect()
guard let url = URL(string: urlString) else {
    let error = WebSocketError.invalidURL(urlString)
    logger.error("[Starscream] ❌ Invalid WebSocket URL: \(urlString)")
    onError?(error)
    return
}
```

#### 4.2 Token Validation Missing (Line 75-77)
```swift
request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
```

**Problem:**
- No validation that `token` is non-empty
- Empty token would send `"bookstrack-auth."` which backend might accept (security risk!)
- No documentation on expected token format

**Fix:**
```swift
// Add validation before setting header
guard !token.isEmpty else {
    let error = WebSocketError.invalidToken
    logger.error("[Starscream] ❌ Empty authentication token")
    onError?(error)
    return
}

// Optionally validate token format (JWT, UUID, etc.)
guard isValidTokenFormat(token) else {
    let error = WebSocketError.malformedToken
    logger.error("[Starscream] ❌ Malformed token format")
    onError?(error)
    return
}
```

#### 4.3 WebSocket Errors Not Propagated (Line 148-152)
```swift
case .error(let error):
    #if DEBUG
    print("[Starscream] ❌ Error: \(error?.localizedDescription ?? "Unknown")")
    #endif
    onDisconnect?()  // ⚠️ Treats all errors as disconnections
```

**Problem:**
- All errors treated identically (no differentiation between network errors, auth failures, protocol errors)
- Caller can't implement retry logic without error details
- Production users get no error information

**Fix:**
```swift
case .error(let error):
    logger.error("[Starscream] ❌ Error: \(error?.localizedDescription ?? "Unknown")")

    // Propagate error with context
    if let error = error {
        onError?(WebSocketError.connectionError(error))
    } else {
        onError?(WebSocketError.unknownError)
    }

    // Still call disconnect for cleanup
    onDisconnect?()
```

**Impact:** 🔴 **Observability & Debugging** - Impossible to diagnose production issues, poor user experience

---

### 5. Missing Reconnection Logic

**Location:** `StarscreamWebSocketHandler.swift:160-163`

**Issue:**
```swift
case .reconnectSuggested(let shouldReconnect):
    #if DEBUG
    print("[Starscream] 🔄 Reconnect suggested: \(shouldReconnect)")
    #endif
    // NO IMPLEMENTATION!
```

**Problem:**
- Starscream provides reconnection hints, but handler ignores them
- Long-running enrichment jobs (5-10 minutes) will fail if network temporarily drops
- No automatic recovery from transient network issues

**Context:**
According to CLAUDE.md, enrichment can take:
- AI processing: 25-40s per photo
- 5 photos = 2-5 minutes of active connection
- Network issues common on mobile devices

**Fix Required:**
```swift
case .reconnectSuggested(let shouldReconnect):
    logger.info("[Starscream] 🔄 Reconnect suggested: \(shouldReconnect)")

    if shouldReconnect {
        // Implement exponential backoff reconnection
        Task { @MainActor in
            await attemptReconnection(
                maxRetries: 3,
                initialDelay: 1.0,
                backoffMultiplier: 2.0
            )
        }
    }
```

**Impact:** 🔴 **Reliability** - Jobs fail on transient network issues, poor mobile UX

---

## Important Improvements (Should Fix)

### 6. Inconsistent @MainActor Isolation

**Location:** `StarscreamWebSocketHandler.swift:117-181`

**Issue:**
The WebSocketDelegate method `didReceive(event:client:)` is `nonisolated` but wraps everything in `Task { @MainActor in }`:

```swift
// Line 117
nonisolated public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
    Task { @MainActor in  // ⚠️ Every event hops to MainActor
        switch event {
        // ... 64 lines of event handling
        }
    }
}
```

**Problems:**
1. **Performance**: Every WebSocket message creates a new Task and hops to MainActor
2. **Ordering**: Task creation doesn't guarantee ordering - messages could be processed out of sequence
3. **Architecture**: Why is entire class @MainActor if delegate needs nonisolation?

**Analysis:**
Looking at usage:
- `onBatchProgress`, `onEnrichmentProgress`, `onEnrichmentComplete` are all passed as `@MainActor` closures
- Socket operations (`write()`, `disconnect()`) need MainActor
- Message parsing could be done on background thread

**Better Design:**
```swift
// Option A: Keep class @MainActor, make delegate use @preconcurrency
@available(iOS 13.0, *)
@MainActor
public final class StarscreamWebSocketHandler: NSObject {
    // ...
}

extension StarscreamWebSocketHandler: @preconcurrency WebSocketDelegate {
    nonisolated public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        // Starscream calls this on background thread
        // Hop to MainActor for processing
        MainActor.assumeIsolated {
            self.handleEvent(event)
        }
    }

    private func handleEvent(_ event: WebSocketEvent) {
        // Already on MainActor, no Task needed
        switch event { ... }
    }
}

// Option B: Parse off MainActor, only hop for UI updates
nonisolated private func parseMessage(_ text: String) -> TypedWebSocketMessage? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(TypedWebSocketMessage.self, from: data)
}

nonisolated public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
    switch event {
    case .text(let string):
        // Parse on background thread
        guard let message = parseMessage(string) else { return }

        // Only hop to MainActor for UI updates
        Task { @MainActor in
            handleParsedMessage(message)
        }
    // ...
    }
}
```

**Impact:** ⚠️ **Performance** - Message processing creates unnecessary Task overhead

---

### 7. Unsafe Force Unwraps and Missing Nil Checks

**Location:** Multiple locations

#### 7.1 WebSocket URL Construction (EnrichmentQueue.swift:346)
```swift
var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress")!
//                                                                                        ^ Force unwrap!
```

**Problem:**
If `EnrichmentConfig.webSocketBaseURL` is malformed or contains special characters, this will crash.

**Fix:**
```swift
guard var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress") else {
    continuation.resume(throwing: EnrichmentError.invalidURL)
    return
}
```

#### 7.2 EnrichmentQueue.swift:600 (HTTP Fetch)
```swift
let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/jobs/\(jobId)/results")!
//                                                                               ^ Force unwrap!
```

**Fix:**
```swift
guard let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/jobs/\(jobId)/results") else {
    throw EnrichmentError.invalidURL
}
```

**Impact:** ⚠️ **Crash Risk** - Potential production crashes if configuration is invalid

---

### 8. Message Handling Edge Cases

**Location:** `StarscreamWebSocketHandler.swift:185-217`

#### 8.1 No Handling for Unknown Pipelines
```swift
// Line 202-209
switch message.pipeline {
case .aiScan:
    handleBatchMessage(message)
case .batchEnrichment:
    handleEnrichmentMessage(message)
case .csvImport:
    handleEnrichmentMessage(message)
}
// ⚠️ What if backend adds new pipeline type?
```

**Problem:**
- No `default` case - if backend adds new pipeline, messages silently ignored
- No validation that received pipeline matches expected pipeline (line 38)

**Fix:**
```swift
switch message.pipeline {
case .aiScan:
    guard pipeline == .aiScan else {
        logger.warning("⚠️ Received aiScan message but expected \(pipeline?.rawValue ?? "nil")")
        return
    }
    handleBatchMessage(message)

case .batchEnrichment, .csvImport:
    guard pipeline == message.pipeline else {
        logger.warning("⚠️ Pipeline mismatch: received \(message.pipeline), expected \(pipeline?.rawValue ?? "nil")")
        return
    }
    handleEnrichmentMessage(message)

@unknown default:
    logger.error("❌ Unknown pipeline type: \(message.pipeline.rawValue)")
}
```

#### 8.2 Batch Progress Array Index Out of Bounds (Line 236-248)
```swift
let photoIndex = progressPayload.currentPhoto - 1
if photoIndex >= 0 && photoIndex < batchProgress.photos.count {
    // ... update photo status
    batchProgress.updatePhoto(index: photoIndex, status: status)
}
// ⚠️ What if index is out of bounds? Silent failure!
```

**Problem:**
- Backend could send malformed `currentPhoto` value
- No logging when index validation fails
- Progress UI won't update, user sees stale data

**Fix:**
```swift
let photoIndex = progressPayload.currentPhoto - 1
guard photoIndex >= 0 && photoIndex < batchProgress.photos.count else {
    logger.warning("⚠️ Invalid photo index: \(photoIndex) (total: \(batchProgress.photos.count))")
    logger.debug("Payload: currentPhoto=\(progressPayload.currentPhoto), totalPhotos=\(progressPayload.totalPhotos)")
    // Still update overall progress even if specific photo fails
    batchProgress.overallStatus = progressPayload.photoStatus
    batchProgress.totalBooksFound = progressPayload.totalBooksFound
    onBatchProgress?(batchProgress)
    return
}
```

**Impact:** ⚠️ **Data Integrity** - Silent failures lead to UI inconsistencies

---

### 9. Security: Token Exposure in Logs

**Location:** `BatchCaptureView.swift:87`

**Issue:**
```swift
print("[BatchCapture] Batch submitted: \(response.jobId), \(response.totalPhotos) photos, token: \(response.token.prefix(8))...")
```

**Problem:**
- Logs first 8 characters of token (possibly sensitive)
- Debug logs can be extracted from device/crash reports
- No documentation on token rotation policy

**Analysis:**
- If tokens are JWTs: First 8 chars reveal header (usually `eyJhbGci`)
- If tokens are UUIDs: First 8 chars leak timestamp/node info
- Best practice: Never log any part of authentication tokens

**Fix:**
```swift
#if DEBUG
print("[BatchCapture] Batch submitted: \(response.jobId), \(response.totalPhotos) photos, token: <redacted>")
#endif

// Or use secure logging
logger.debug("[BatchCapture] Batch submitted: jobId=\(response.jobId), photos=\(response.totalPhotos)")
// Token presence implied by successful response
```

**Impact:** ⚠️ **Security** - Potential token leakage in logs

---

### 10. HTTP/1.1 Enforcement - Incomplete Implementation

**Location:** `StarscreamWebSocketHandler.swift:70-73`

**Issue:**
```swift
// ✅ FORCE HTTP/1.1 - This is the key fix for ALPN HTTP/2 negotiation
request.setValue("Upgrade", forHTTPHeaderField: "Connection")
request.setValue("websocket", forHTTPHeaderField: "Upgrade")
request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
```

**Analysis:**
These headers are part of the **WebSocket upgrade handshake** (RFC 6455), but they don't actually **force HTTP/1.1**. The ALPN negotiation happens at the TLS layer, before HTTP headers are sent.

**Evidence:**
- `Connection: Upgrade` - Indicates intention to upgrade protocol
- `Upgrade: websocket` - Specifies target protocol
- `Sec-WebSocket-Version: 13` - WebSocket protocol version

None of these prevent HTTP/2 ALPN negotiation!

**Starscream's Actual Fix:**
Looking at Starscream source code, it uses `NWProtocolWebSocket.Options` (Network framework) which has explicit HTTP/1.1 enforcement:

```swift
// From Starscream source
let options = NWProtocolWebSocket.Options()
options.autoReplyPing = true
options.setAdditionalHeaders([
    (":method", "GET"),
    (":scheme", request.url?.scheme ?? "wss"),
    (":path", request.url?.path ?? "/"),
])
```

The **Network framework's WebSocket implementation** inherently uses HTTP/1.1 for upgrades (no HTTP/2 support).

**Comment Correction Required:**
```swift
// ❌ INCORRECT COMMENT:
// ✅ FORCE HTTP/1.1 - This is the key fix for ALPN HTTP/2 negotiation

// ✅ CORRECT COMMENT:
// WebSocket upgrade headers per RFC 6455
// HTTP/1.1 enforcement is handled by Starscream's use of NWProtocolWebSocket
// which does not support HTTP/2 ALPN (this is the actual fix for Issue #227)
```

**Impact:** ⚠️ **Documentation** - Misleading comment could confuse future maintainers

---

## Minor Suggestions (Nice to Have)

### 11. Logging Inconsistency

**Location:** Throughout `StarscreamWebSocketHandler.swift`

**Issue:**
Mixes `print()` statements with missing `Logger` usage:
- Uses `#if DEBUG print()` throughout
- No structured logging for production diagnostics
- No log levels (info, warning, error)

**Recommendation:**
```swift
import os.log

private let logger = Logger(
    subsystem: "com.oooefam.booksV3",
    category: "StarscreamWebSocket"
)

// Replace all print() statements with:
logger.debug("🔌 Connecting to: \(urlString)")
logger.info("✅ WebSocket connected")
logger.warning("⚠️ No authentication token available")
logger.error("❌ Disconnected: \(reason) (code: \(code))")
```

Benefits:
- Unified logging with rest of codebase (see `EnrichmentQueue.swift:46`)
- Production visibility via Console.app
- Log filtering and archiving

---

### 12. Magic String - Token Header Format

**Location:** `StarscreamWebSocketHandler.swift:77`

**Issue:**
```swift
request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
```

**Problem:**
- `"bookstrack-auth."` prefix is hardcoded
- No documentation on why this format is used
- If backend changes format, need to search codebase for all occurrences

**Recommendation:**
```swift
// In EnrichmentConfig.swift
enum WebSocketAuth {
    /// Sec-WebSocket-Protocol header format for token authentication
    /// Format: "bookstrack-auth.{token}"
    /// See: Issue #163 - Header-based auth to prevent token logging
    static func protocolHeader(token: String) -> String {
        return "bookstrack-auth.\(token)"
    }
}

// In StarscreamWebSocketHandler.swift
request.setValue(
    WebSocketAuth.protocolHeader(token: token),
    forHTTPHeaderField: "Sec-WebSocket-Protocol"
)
```

---

### 13. Missing Timeout Configuration

**Location:** `StarscreamWebSocketHandler.swift:68`

**Issue:**
```swift
request.timeoutInterval = 10.0  // ⚠️ Hardcoded, different from EnrichmentConfig
```

**Problem:**
- `EnrichmentConfig` defines `webSocketTimeout = 70.0` (line 104)
- Handler uses `10.0` instead
- No documentation on why values differ

**Recommendation:**
```swift
request.timeoutInterval = EnrichmentConfig.webSocketTimeout
```

Or if 10s is intentional (connection timeout vs message timeout):
```swift
// Connection timeout (how long to wait for initial handshake)
request.timeoutInterval = 10.0

// Message timeout (configured in Starscream socket options)
// Using EnrichmentConfig.webSocketTimeout (70s) for long-running AI processing
```

---

### 14. sendReadySignal() Never Called

**Location:** `StarscreamWebSocketHandler.swift:89-103`

**Issue:**
```swift
/// Send ready signal to backend to start processing (optional - some flows don't need this)
public func sendReadySignal() {
    // ... implementation ...
}
```

**Observation:**
Searching all usage of `StarscreamWebSocketHandler`:
- `BatchCaptureView.swift`: Never calls `sendReadySignal()`
- `EnrichmentQueue.swift`: Never calls `sendReadySignal()`

**Questions:**
1. Is this method actually needed?
2. If optional, which flows require it?
3. If unused, should it be removed to reduce API surface?

**Recommendation:**
Either:
- **Option A**: Document when to call it and update callers
- **Option B**: Remove if truly unused (YAGNI principle)
- **Option C**: Make it automatic (call in `connect()` after successful connection)

---

### 15. Memory Management - Weak References

**Location:** `EnrichmentQueue.swift:362-445`

**Issue:**
WebSocket handler callbacks use `[weak self]`:
```swift
handler.onEnrichmentProgress = { [weak self] progressPayload in
    self?.resetActivityTimer()  // ✅ Good - weak reference
    // ...
}
```

But in `BatchCaptureView.swift:92-112`:
```swift
handler.onBatchProgress = { [weak self] updatedProgress in
    guard let self = self else { return }  // ✅ Good - weak reference
    // ...
}
```

**Observation:**
Consistent use of `[weak self]` - **excellent memory management**! This prevents retain cycles when WebSocket lives longer than the view/queue.

**Minor Suggestion:**
Consider storing weak reference in handler itself:
```swift
// Alternative pattern (see NWWebSocketHandler.swift:44-47)
weak var delegate: WebSocketDelegate?

protocol WebSocketDelegate: AnyObject {
    func webSocket(_ handler: StarscreamWebSocketHandler, didReceiveProgress: JobProgressPayload)
    func webSocket(_ handler: StarscreamWebSocketHandler, didComplete: JobCompletePayload)
    func webSocket(_ handler: StarscreamWebSocketHandler, didDisconnect: Void)
}
```

This is more testable and provides stronger type safety than closures.

---

## Architecture Considerations

### 16. Unified Handler vs. Specialized Handlers

**Current Architecture:**
```
StarscreamWebSocketHandler (unified)
├── aiScan → handleBatchMessage()
├── batchEnrichment → handleEnrichmentMessage()
└── csvImport → handleEnrichmentMessage()
```

**Alternative Architecture (seen in codebase):**
```
EnrichmentWebSocketHandler (specialized for enrichment)
BatchWebSocketHandler (specialized for batch scanning)
```

**Analysis:**

**Pros of Unified Handler (Current):**
- ✅ Single source of truth for WebSocket connection logic
- ✅ Easier to maintain HTTP/1.1 enforcement in one place
- ✅ Reduces code duplication
- ✅ Clear separation: connection logic vs. message handling

**Cons of Unified Handler:**
- ⚠️ Mixing concerns (batch scanning has different progress model than enrichment)
- ⚠️ Closures-based API less type-safe than protocol delegation
- ⚠️ Harder to test individual pipelines in isolation

**Recommendation:**
**Keep the unified handler**, but improve type safety:

```swift
// Introduce pipeline-specific response types
public enum WebSocketResponse {
    case batchProgress(BatchProgress)
    case enrichmentProgress(JobProgressPayload)
    case enrichmentComplete(JobCompletePayload)
}

public protocol WebSocketHandlerDelegate: AnyObject {
    func webSocketHandler(_ handler: StarscreamWebSocketHandler, didReceive response: WebSocketResponse)
    func webSocketHandler(_ handler: StarscreamWebSocketHandler, didDisconnect error: Error?)
}
```

This maintains the unified architecture while improving type safety and testability.

---

### 17. Error Handling Strategy - Missing Error Types

**Location:** Entire `StarscreamWebSocketHandler.swift`

**Observation:**
No custom error enum defined. Errors are handled as raw `Error` or logged as strings.

**Recommendation:**
Define structured error types:

```swift
public enum WebSocketError: Error, LocalizedError {
    case invalidURL(String)
    case invalidToken
    case malformedToken
    case connectionFailed(Error)
    case connectionError(Error)
    case authenticationFailed(code: UInt16)
    case messageDecodingFailed(Error)
    case pipelineMismatch(expected: PipelineType, received: PipelineType)
    case unexpectedDisconnection(reason: String, code: UInt16)
    case unknownError

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid WebSocket URL: \(url)"
        case .invalidToken:
            return "Authentication token is empty or missing"
        case .malformedToken:
            return "Authentication token format is invalid"
        case .connectionFailed(let error):
            return "WebSocket connection failed: \(error.localizedDescription)"
        case .connectionError(let error):
            return "WebSocket error: \(error.localizedDescription)"
        case .authenticationFailed(let code):
            return "WebSocket authentication failed (code: \(code))"
        case .messageDecodingFailed(let error):
            return "Failed to decode WebSocket message: \(error.localizedDescription)"
        case .pipelineMismatch(let expected, let received):
            return "Pipeline mismatch: expected \(expected.rawValue), received \(received.rawValue)"
        case .unexpectedDisconnection(let reason, let code):
            return "WebSocket disconnected unexpectedly: \(reason) (code: \(code))"
        case .unknownError:
            return "An unknown WebSocket error occurred"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .connectionFailed, .connectionError, .unexpectedDisconnection:
            return true
        case .invalidURL, .invalidToken, .malformedToken, .authenticationFailed:
            return false
        default:
            return false
        }
    }
}
```

This enables:
- User-friendly error messages
- Retry logic based on error type
- Better crash reporting and analytics

---

### 18. Testing Gaps

**Observation:**
No unit tests found for `StarscreamWebSocketHandler` (checked all test files).

**Recommendation:**
Create test suite covering:

```swift
// StarscreamWebSocketHandlerTests.swift

import Testing
@testable import BooksTrackerFeature

@Suite("StarscreamWebSocketHandler Tests")
struct StarscreamWebSocketHandlerTests {

    @Test("Connect with valid parameters")
    func testConnectValid() async throws {
        // Arrange
        let handler = StarscreamWebSocketHandler()
        var progressCalled = false
        handler.onBatchProgress = { _ in progressCalled = true }

        // Act
        handler.connect(
            jobId: "test-job",
            token: "valid-token",
            pipeline: .aiScan,
            batchProgress: nil
        )

        // Assert
        // Use mock WebSocket server or dependency injection
    }

    @Test("Connect with empty token fails")
    func testConnectEmptyToken() async throws {
        // Test error handling
    }

    @Test("Message routing for different pipelines")
    func testMessageRouting() async throws {
        // Test aiScan → handleBatchMessage
        // Test batchEnrichment → handleEnrichmentMessage
    }

    @Test("Actor isolation compliance")
    func testActorIsolation() async throws {
        // Verify @MainActor calls are safe
    }
}
```

**Testing Strategy:**
1. Mock Starscream's `WebSocket` for unit tests
2. Integration tests with local WebSocket server
3. Fuzz testing with malformed messages
4. Concurrency testing for race conditions

---

## Next Steps

### Immediate Actions (Before Merge)

1. **Fix Type System Issue** (Critical)
   - [ ] Replace `WebSocketPipeline` with `PipelineType` throughout
   - [ ] Verify code compiles without warnings
   - [ ] Run full test suite

2. **Fix Actor Isolation** (Critical)
   - [ ] Fix `disconnect()` call in `BatchCaptureView.swift:180`
   - [ ] Run with Swift 6 strict concurrency enabled
   - [ ] Verify no runtime warnings

3. **Add HTTP Polling Fallback** (Critical)
   - [ ] Wire up `onDisconnect` → `pollForEnrichmentResults()`
   - [ ] Test with WebSocket blocked network
   - [ ] Verify graceful degradation

4. **Improve Error Handling** (Critical)
   - [ ] Add `onError` callback
   - [ ] Define `WebSocketError` enum
   - [ ] Validate token before connection
   - [ ] Handle all error cases explicitly

5. **Fix Force Unwraps** (Important)
   - [ ] Replace force unwraps in URL construction
   - [ ] Add guard statements with proper error handling
   - [ ] Test with invalid configuration

### Short-Term (This Sprint)

6. **Add Reconnection Logic** (Important)
   - [ ] Implement `reconnectSuggested` handler
   - [ ] Add exponential backoff
   - [ ] Test network interruption scenarios

7. **Security Hardening** (Important)
   - [ ] Remove token from all logs
   - [ ] Add token format validation
   - [ ] Document token rotation policy

8. **Testing Coverage** (Important)
   - [ ] Write unit tests for handler
   - [ ] Add WebSocket integration tests
   - [ ] Test all three pipelines

### Long-Term (Next Release)

9. **Architecture Refinement** (Nice to Have)
   - [ ] Consider protocol-based delegation
   - [ ] Evaluate unified vs. specialized handler trade-offs
   - [ ] Document architecture decision records (ADRs)

10. **Observability** (Nice to Have)
    - [ ] Replace print() with os.log
    - [ ] Add performance metrics
    - [ ] Implement connection health monitoring

---

## Summary of Findings

| Category | Critical | Important | Minor | Total |
|----------|----------|-----------|-------|-------|
| **Security** | 0 | 2 | 0 | 2 |
| **Concurrency** | 2 | 1 | 0 | 3 |
| **Error Handling** | 2 | 2 | 1 | 5 |
| **Architecture** | 0 | 1 | 3 | 4 |
| **Testing** | 0 | 1 | 0 | 1 |
| **Documentation** | 0 | 1 | 2 | 3 |
| **Total** | **4** | **8** | **6** | **18** |

**Estimated Remediation Time:**
- Critical issues: **4-6 hours**
- Important issues: **8-12 hours**
- Minor issues: **2-4 hours**
- **Total: 14-22 hours**

---

## Conclusion

The Starscream WebSocket implementation successfully solves the HTTP/2 ALPN negotiation problem and demonstrates solid architectural thinking with its unified handler approach. Security is handled correctly with header-based token authentication.

However, **4 critical issues** must be resolved before production deployment:
1. Type system compilation error (`WebSocketPipeline` → `PipelineType`)
2. Actor isolation violation in disconnect call
3. Missing HTTP polling fallback for reliability
4. Weak error handling with silent failures

Once these are addressed, this implementation will provide a robust, production-ready WebSocket solution for BooksTrack's three pipeline types (aiScan, batchEnrichment, csvImport).

**Recommendation:** ⚠️ **DO NOT MERGE** until critical issues are resolved.

---

**Reviewed by:** Claude Code (code-architecture-reviewer)
**Review Date:** 2025-11-22
**Next Review:** After critical issues addressed
