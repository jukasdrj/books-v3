# WebSocket Race Condition - Comprehensive Audit

**Date:** November 6, 2025
**Severity:** HIGH
**Status:** 🔴 Affects 3 of 3 WebSocket implementations

---

## Executive Summary

**All three WebSocket handlers** in the codebase have the same race condition: calling `send()` or `receive()` immediately after `resume()` without waiting for the WebSocket handshake to complete.

**Root Cause:** `URLSessionWebSocketTask.resume()` is **non-blocking** - it initiates the WebSocket handshake asynchronously but returns immediately. Any attempt to send/receive before the handshake completes throws:

```
Error Domain=NSPOSIXErrorDomain Code=57 "Socket is not connected"
```

---

## Affected Files

### ❌ 1. CSV Import WebSocket
**File:** `GeminiCSVImportView.swift:296-309`
**Bug Type:** Race on `send()`
**Impact:** CSV import fails with "Socket is not connected"

```swift
let webSocket = session.webSocketTask(with: wsURL)
webSocket.resume()                              // ❌ Non-blocking!
#if DEBUG
print("[CSV WebSocket] ✅ WebSocket connection established")  // ❌ MISLEADING!
#endif

// Send ready signal to backend (required for processing to start)
try await webSocket.send(.string(messageString))  // ❌ Fails if handshake incomplete
```

**Related PR:** #292
**User Report:** Issue #291

---

### ❌ 2. Bookshelf Scanner WebSocket
**File:** `BatchWebSocketHandler.swift:23-39`
**Bug Type:** Race on `receive()`
**Impact:** Bookshelf scan fails with "Socket is not connected"

```swift
webSocket = session.webSocketTask(with: wsURL)
webSocket?.resume()                    // ❌ Non-blocking!
isConnected = true                     // ❌ LIE!
print("[BatchWebSocket] Connected for job \(jobId)")  // ❌ MISLEADING!

await listenForMessages()              // ❌ Calls receive() immediately

// Inside listenForMessages():
while isConnected {
    let message = try await webSocket.receive()  // ❌ CRASHES HERE!
}
```

**User Report:** Error logs showing:
```
⚠️ WebSocket receive error: Error Domain=NSPOSIXErrorDomain Code=57 "Socket is not connected"
❌ WebSocket scan failed: networkError(...Code=57...)
```

---

### ❌ 3. Enrichment WebSocket
**File:** `EnrichmentWebSocketHandler.swift:26-34`
**Bug Type:** Race on `receive()`
**Impact:** Background enrichment may fail intermittently

```swift
webSocket = session.webSocketTask(with: url)
webSocket?.resume()                    // ❌ Non-blocking!
isConnected = true                     // ❌ LIE!
listenForMessages()                    // ❌ Calls receive() immediately

// Inside listenForMessages():
webSocket?.receive { [weak self] result in
    // ❌ May fail if handshake incomplete
}
```

**Note:** Uses callback-based `receive()` (not async/await), but same race condition applies.

---

## Root Cause Analysis

### URLSessionWebSocketTask.resume() Behavior

From Apple documentation:
> "Calling this method starts the WebSocket handshake. The handshake is performed asynchronously."

**Key Point:** `resume()` does NOT block. It returns immediately while the handshake proceeds in the background.

### Handshake Timeline

```
Time 0ms:    webSocket.resume()          ← Returns immediately
Time 1-50ms: [TCP connection establishing]
Time 50-100ms: [WebSocket handshake: HTTP Upgrade request/response]
Time 100ms:  ✅ Connection fully established

Our Code:
Time 0ms:    webSocket.resume()
Time 1ms:    webSocket.send() or receive()  ❌ HANDSHAKE NOT DONE YET!
```

**Result:** POSIX error 57 (ENOTCONN - "Socket is not connected")

---

## Why It's Intermittent

The race condition **depends on network speed**:

- **Fast WiFi/5G:** Handshake completes in <20ms → Bug rarely manifests
- **Slow connection:** Handshake takes >100ms → Bug happens frequently
- **Poor signal:** Handshake can take 500ms+ → Bug happens consistently

This explains why users see it "just now" - network conditions vary!

---

## Correct Implementation (Already Exists!)

### WebSocketProgressManager.swift ✅

**File:** `Common/WebSocketProgressManager.swift:83-86`

```swift
task.resume()
// Wait for successful connection (by sending/receiving ping)
try await waitForConnection(task, timeout: connectionTimeout)  // ✅ EXPLICIT WAIT!

self.webSocketTask = task
self.isConnected = true
```

**`waitForConnection()` Implementation (lines 186-205):**

```swift
private func waitForConnection(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws {
    let startTime = Date()
    var attempts = 0
    let maxAttempts = 5

    while attempts < maxAttempts {
        if Date().timeIntervalSince(startTime) > timeout {
            throw URLError(.timedOut)
        }

        do {
            // Send ping message to confirm connection is working
            try await task.send(.string("PING"))

            // Wait for any response (with timeout)
            _ = Task { try await task.receive() }

            return  // ✅ Success! Connection verified
        } catch {
            attempts += 1
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    throw URLError(.cannotConnectToHost)
}
```

**How it works:**
1. Attempts to send a PING message
2. If send succeeds, waits for any response
3. If both succeed, connection is verified
4. If either fails, waits 200ms and retries (up to 5 times)
5. Throws timeout error after all attempts exhausted

---

## Fix Strategy

### Recommended Approach: Extract to Shared Utility

**Create:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/WebSocketHelpers.swift`

```swift
import Foundation

/// Waits for WebSocket connection to be fully established before allowing send/receive operations.
///
/// URLSessionWebSocketTask.resume() is non-blocking - it starts the handshake asynchronously
/// but returns immediately. This function verifies the connection is ready by attempting to
/// send PING messages and waiting for responses.
///
/// - Parameters:
///   - task: The WebSocket task to verify
///   - timeout: Maximum time to wait for connection (default: 10 seconds)
/// - Throws: URLError if connection cannot be established within timeout
public func waitForWebSocketConnection(
    _ task: URLSessionWebSocketTask,
    timeout: TimeInterval = 10.0
) async throws {
    let startTime = Date()
    var attempts = 0
    let maxAttempts = 5

    while attempts < maxAttempts {
        // Check timeout
        if Date().timeIntervalSince(startTime) > timeout {
            throw URLError(.timedOut)
        }

        do {
            // Verify connection by sending PING and waiting for response
            try await task.send(.string("PING"))

            // If send succeeds, try to receive (verifies bidirectional communication)
            _ = try await withTimeout(seconds: 2) {
                try await task.receive()
            }

            // Success! Connection is fully established
            return

        } catch {
            // Connection not ready yet, retry
            attempts += 1
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    // All attempts exhausted
    throw URLError(.cannotConnectToHost)
}

/// Helper to add timeout to async operations
private func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw URLError(.timedOut)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

---

## Required Changes

### 1. GeminiCSVImportView.swift

```swift
// BEFORE (line 297):
webSocket.resume()
#if DEBUG
print("[CSV WebSocket] ✅ WebSocket connection established")
#endif

try await webSocket.send(.string(messageString))

// AFTER:
webSocket.resume()

// ✅ Wait for connection to be established
try await waitForWebSocketConnection(webSocket, timeout: 10.0)

#if DEBUG
print("[CSV WebSocket] ✅ WebSocket connection established")
#endif

try await webSocket.send(.string(messageString))
```

---

### 2. BatchWebSocketHandler.swift

```swift
// BEFORE (line 24):
webSocket?.resume()
isConnected = true
print("[BatchWebSocket] Connected for job \(jobId)")
await listenForMessages()

// AFTER:
webSocket?.resume()

// ✅ Wait for connection to be established
if let ws = webSocket {
    try await waitForWebSocketConnection(ws, timeout: 10.0)
}

isConnected = true
print("[BatchWebSocket] Connected for job \(jobId)")
await listenForMessages()
```

---

### 3. EnrichmentWebSocketHandler.swift

**Challenge:** This uses callback-based `receive()`, not async/await.

**Option A:** Convert to async/await (recommended):

```swift
// BEFORE:
func connect() {
    guard let url = URL(string: "...") else { return }
    let session = URLSession(configuration: .default)
    webSocket = session.webSocketTask(with: url)
    webSocket?.resume()
    isConnected = true
    listenForMessages()
}

// AFTER:
func connect() async throws {
    guard let url = URL(string: "...") else { throw EnrichmentError.invalidURL }
    let session = URLSession(configuration: .default)
    webSocket = session.webSocketTask(with: url)
    webSocket?.resume()

    // ✅ Wait for connection
    if let ws = webSocket {
        try await waitForWebSocketConnection(ws, timeout: 10.0)
    }

    isConnected = true
    await listenForMessages()  // Convert to async
}
```

**Option B:** Keep callbacks, use Task wrapper:

```swift
func connect() {
    guard let url = URL(string: "...") else { return }
    let session = URLSession(configuration: .default)
    webSocket = session.webSocketTask(with: url)
    webSocket?.resume()

    // ✅ Wait for connection before listening
    Task {
        do {
            if let ws = webSocket {
                try await waitForWebSocketConnection(ws, timeout: 10.0)
            }
            isConnected = true
            listenForMessages()
        } catch {
            print("[EnrichmentWebSocket] Connection failed: \(error)")
        }
    }
}
```

---

## Testing Strategy

### Unit Tests

**File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/WebSocketHelpersTests.swift`

```swift
import Testing
@testable import BooksTrackerFeature

@Test("waitForWebSocketConnection succeeds on valid connection")
func testWaitForConnectionSuccess() async throws {
    let mockWebSocket = MockURLSessionWebSocketTask()
    mockWebSocket.handshakeDelay = 0.1  // 100ms delay

    mockWebSocket.resume()
    try await waitForWebSocketConnection(mockWebSocket, timeout: 5.0)

    // Should succeed after handshake completes
    #expect(mockWebSocket.isConnected == true)
}

@Test("waitForWebSocketConnection times out on slow connection")
func testWaitForConnectionTimeout() async {
    let mockWebSocket = MockURLSessionWebSocketTask()
    mockWebSocket.handshakeDelay = 15.0  // 15 second delay (too slow)

    mockWebSocket.resume()

    await #expect(throws: URLError.self) {
        try await waitForWebSocketConnection(mockWebSocket, timeout: 2.0)
    }
}
```

### Integration Tests

Test actual WebSocket connections:

```swift
@Test("CSV import WebSocket connects successfully")
func testCSVImportWebSocketConnection() async throws {
    let service = GeminiCSVImportService.shared
    let jobId = await service.uploadCSV(csvText: "title,author\nBook,Author")

    // Monitor for connection errors
    var connectionError: Error?

    // Start WebSocket connection
    let task = Task {
        do {
            // ... connect and listen ...
        } catch {
            connectionError = error
        }
    }

    // Wait a bit
    try await Task.sleep(for: .seconds(2))

    // Verify no connection errors
    #expect(connectionError == nil)

    task.cancel()
}
```

---

## Rollout Plan

### Phase 1: Create Shared Utility (Day 1)
1. Create `WebSocketHelpers.swift` with `waitForWebSocketConnection()`
2. Add unit tests
3. Verify compiles

### Phase 2: Fix CSV Import (Day 1)
1. Update `GeminiCSVImportView.swift`
2. Test on real device with slow connection
3. Verify error no longer occurs

### Phase 3: Fix Bookshelf Scanner (Day 2)
1. Update `BatchWebSocketHandler.swift`
2. Test batch scanning on real device
3. Verify user's error no longer occurs

### Phase 4: Fix Enrichment (Day 2)
1. Update `EnrichmentWebSocketHandler.swift`
2. Consider converting to async/await (better long-term)
3. Test background enrichment

### Phase 5: Refactor WebSocketProgressManager (Day 3)
1. Replace private `waitForConnection()` with shared utility
2. Remove duplicate code
3. Verify existing enrichment/scan flows still work

---

## Prevention

### Code Review Checklist

When reviewing WebSocket code:
- [ ] `resume()` followed immediately by `waitForWebSocketConnection()`?
- [ ] No `send()` or `receive()` calls before connection verified?
- [ ] `isConnected` flag set AFTER connection verified, not before?
- [ ] Debug logs say "connected" AFTER verification, not after `resume()`?

### Linter Rule (Future)

Add SwiftLint custom rule:

```yaml
custom_rules:
  websocket_resume_without_wait:
    name: "WebSocket Resume Without Wait"
    regex: 'webSocket(?:Task)?\.resume\(\)\s*\n\s*(?!.*waitForConnection)'
    message: "WebSocket resume() must be followed by waitForConnection()"
    severity: error
```

---

## Related Issues

- **GitHub Issue #291:** "websocket - failed during csv import"
- **GitHub PR #292:** "Fix WebSocket race condition causing 'Socket is not connected' during CSV import"
- **User Report (Nov 6, 2025):** Bookshelf scanner error with Code=57

---

## References

- [Apple URLSessionWebSocketTask Documentation](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)
- [POSIX Error 57 (ENOTCONN)](https://www.man7.org/linux/man-pages/man3/errno.3.html)
- [WebSocket RFC 6455](https://datatracker.ietf.org/doc/html/rfc6455)

---

**Conclusion:**

This is a **systemic issue** affecting all WebSocket implementations in the codebase. The fix is straightforward (add `waitForWebSocketConnection()` after `resume()`), but requires updates to 3 files. The correct pattern already exists in `WebSocketProgressManager` - we just need to extract it to a shared utility and apply it consistently.
