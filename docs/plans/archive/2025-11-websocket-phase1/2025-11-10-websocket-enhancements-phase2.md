# WebSocket Enhancements - Phase 2 Implementation Plan

**Date:** November 10, 2025
**Status:** 🚧 Draft for Expert Review
**Priority:** HIGH
**Estimated Effort:** 5-6 days

## Executive Summary

Phase 2 focuses on connection resilience and user experience improvements identified through multi-expert consensus. This phase ensures WebSocket connections remain stable on mobile networks and provides user-friendly feedback during long-running operations.

## Dependencies

**Must Complete First:**
- ✅ Phase 1 Task 1: Token authentication for CSV/AI pipelines (Issue #362)
- ✅ Phase 1 Task 2: Unified message schema (Issue #363)
- ✅ Phase 1 Task 3: DO state persistence

## Expert Consensus Summary

### Connection Resilience (Priority #1)

**Gemini 2.5 Pro:**
> "Not optional for a mobile application. The iOS client should send a ping frame every 30-60 seconds. Auto-reconnect with exponential backoff and state sync."

**Grok-4:**
> "Absolutely—prioritize this... networks flake on iOS. Implement client-side logic with exponential backoff. Include the job ID in reconnect queries to resume state."

**Impact:** Mobile networks are unreliable; connections drop frequently without resilience mechanisms.

### Message Throttling (Priority #2)

**Gemini 2.5 Pro:**
> "Server-side throttling is crucial for performance. Sending an update at most once every 500-1000ms prevents flooding the client."

**Grok-4:**
> "For high-frequency updates, batch multiple progress events into one message. If throttling isn't enough, add server-side rate limiting."

**Impact:** Large imports (100+ books) generate excessive WebSocket traffic, degrading iOS UI responsiveness.

---

## Phase 2 Tasks

### Task 1: Implement Heartbeat Mechanism (Ping/Pong)
**Priority:** CRITICAL
**Effort:** 8-10 hours

#### Problem Statement

Cloudflare Workers terminate idle WebSocket connections after ~100 seconds. Mobile networks also silently drop connections. Without periodic keep-alive messages, long-running jobs (CSV imports, batch enrichment) lose connection, and users see no progress updates.

#### Architecture

**Heartbeat Flow:**
```
iOS Client                    Cloudflare DO
    |                              |
    |---- ping (every 30s) ------> |
    |                              | (validate connection)
    | <-------- pong ------------- |
    |                              |
    | (calculate RTT)              |
    | (detect dead connection)     |
```

**Timing Strategy:**
- **Client sends ping:** Every 30 seconds
- **Server responds pong:** Within 5 seconds
- **Connection timeout:** If no pong after 3 attempts (90s), trigger reconnect

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Add ping handler to WebSocket message receiver:**

```javascript
/**
 * Handle incoming WebSocket messages from iOS client
 * Dispatches to appropriate handler based on message type
 */
handleWebSocketMessage(message) {
  try {
    const parsed = JSON.parse(message);

    switch (parsed.type) {
      case 'ping':
        this.handlePing(parsed);
        break;

      case 'sync_request':
        this.handleSyncRequest(parsed);
        break;

      default:
        console.warn(`[${this.jobId}] Unknown message type: ${parsed.type}`);
    }
  } catch (error) {
    console.error(`[${this.jobId}] Failed to parse WebSocket message:`, error);
  }
}

/**
 * Handle ping from client - respond with pong
 * Keeps connection alive and allows RTT calculation
 */
async handlePing(pingMessage) {
  if (!this.webSocket) {
    console.warn(`[${this.jobId}] Received ping but no WebSocket connection`);
    return;
  }

  const clientTime = pingMessage.payload?.clientTime;

  const pong = WebSocketMessageFactory.createPong(
    this.jobId,
    pingMessage.pipeline || 'batch_enrichment',
    clientTime
  );

  try {
    this.webSocket.send(JSON.stringify(pong));
    console.log(`[${this.jobId}] Pong sent (client RTT: ${clientTime ? Date.now() - clientTime : 'N/A'}ms)`);
  } catch (error) {
    console.error(`[${this.jobId}] Failed to send pong:`, error);
  }
}
```

**Update WebSocket receiver in fetch() handler:**

```javascript
// In fetch() method, after WebSocket connection is established
webSocket.accept();
this.webSocket = webSocket;

// Listen for messages from client
webSocket.addEventListener('message', (event) => {
  this.handleWebSocketMessage(event.data);
});
```

#### iOS Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/GenericWebSocketHandler.swift`

**Add heartbeat properties and timer:**

```swift
@MainActor
public final class GenericWebSocketHandler {
    // ... existing properties ...

    // Heartbeat mechanism
    private var heartbeatTimer: Task<Void, Never>?
    private let heartbeatInterval: Duration = .seconds(30)
    private var lastPongReceived: Date = Date()
    private var missedPongs = 0
    private let maxMissedPongs = 3

    // ... existing init ...

    public func startHeartbeat() {
        heartbeatTimer?.cancel()

        heartbeatTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)

                guard !Task.isCancelled else { break }

                await sendPing()
                await checkHeartbeatHealth()
            }
        }

        #if DEBUG
        print("💓 Heartbeat started (interval: 30s)")
        #endif
    }

    public func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        #if DEBUG
        print("💓 Heartbeat stopped")
        #endif
    }

    private func sendPing() {
        guard isConnected, let webSocket = webSocket else {
            #if DEBUG
            print("⚠️ Cannot send ping - not connected")
            #endif
            return
        }

        let ping: [String: Any] = [
            "type": "ping",
            "jobId": jobId,
            "pipeline": pipeline.rawValue,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "version": "1.0.0",
            "payload": ["clientTime": Int64(Date().timeIntervalSince1970 * 1000)]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: ping) {
            webSocket.send(.data(data)) { [weak self] error in
                if let error = error {
                    #if DEBUG
                    print("⚠️ Failed to send ping: \(error)")
                    #endif
                    self?.missedPongs += 1
                } else {
                    #if DEBUG
                    print("💓 Ping sent")
                    #endif
                }
            }
        }
    }

    private func checkHeartbeatHealth() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)

        if timeSinceLastPong > (Double(maxMissedPongs) * 30) {
            #if DEBUG
            print("❌ Heartbeat timeout - no pong received in \(Int(timeSinceLastPong))s")
            #endif

            // Trigger reconnect
            disconnect()
            Task {
                await connectWithRetry()
            }
        }
    }

    // Update handleMessage to process pong
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let data = message.data else { return }

        do {
            let typedMessage = try TypedWebSocketMessage(from: data)

            switch typedMessage {
            // ... existing cases ...

            case .heartbeat(let msg):
                if msg.type == .pong {
                    lastPongReceived = Date()
                    missedPongs = 0

                    // Calculate RTT if clientTime provided
                    if let clientTime = msg.payload.clientTime {
                        let rtt = Date().timeIntervalSince1970 * 1000 - Double(clientTime)
                        #if DEBUG
                        print("💓 Pong received (RTT: \(Int(rtt))ms)")
                        #endif
                    }
                }

            // ... other cases ...
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to parse WebSocket message: \(error)")
            #endif
        }
    }
}
```

**Update connect() to start heartbeat:**

```swift
public func connect() async {
    // ... existing connection logic ...

    if let webSocket = webSocket {
        do {
            try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
            isConnected = true
            lastPongReceived = Date() // Reset on connect
            missedPongs = 0

            #if DEBUG
            print("✅ WebSocket connected for \(pipeline.rawValue) job: \(jobId)")
            #endif

            startHeartbeat() // NEW: Start heartbeat after connection
            listenForMessages()
        } catch {
            // ... existing error handling ...
        }
    }
}

public func disconnect() {
    stopHeartbeat() // NEW: Stop heartbeat on disconnect
    guard isConnected else { return }
    isConnected = false
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
}
```

#### Testing

**Backend Tests:**
```javascript
describe('Heartbeat Mechanism', () => {
  it('responds to ping with pong', async () => {
    const doStub = getDoStub();
    const webSocket = mockWebSocket();

    await doStub.handlePing({
      type: 'ping',
      jobId: 'test-123',
      pipeline: 'batch_enrichment',
      payload: { clientTime: Date.now() }
    });

    expect(webSocket.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"pong"')
    );
  });
});
```

**iOS Tests:**
```swift
@Test("Heartbeat sends ping every 30s")
func testHeartbeatInterval() async throws {
    let handler = GenericWebSocketHandler(...)
    await handler.connect()

    // Wait 31 seconds
    try await Task.sleep(for: .seconds(31))

    // Verify at least 1 ping sent
    // (Use mock WebSocket or intercept URLSession traffic)
}

@Test("Reconnect after 3 missed pongs")
func testHeartbeatTimeout() async throws {
    let handler = GenericWebSocketHandler(...)
    await handler.connect()

    // Simulate 90s without pong response
    // Verify reconnect triggered
}
```

**Manual Testing:**
1. Start CSV import on iOS
2. Monitor console for "💓 Ping sent" every 30s
3. Verify "💓 Pong received (RTT: Xms)" responses
4. Kill Worker process mid-import
5. Verify "❌ Heartbeat timeout" after 90s
6. Verify auto-reconnect triggered

#### Success Criteria
- [ ] Backend handles ping messages
- [ ] Backend responds with pong including client timestamp
- [ ] iOS sends ping every 30 seconds
- [ ] iOS tracks missed pongs (max 3)
- [ ] iOS triggers reconnect after 90s without pong
- [ ] RTT calculation works correctly
- [ ] Tests pass (backend + iOS)
- [ ] Manual testing confirms 30s interval

---

### Task 2: Implement Server-Side Message Throttling
**Priority:** HIGH
**Effort:** 6-8 hours

#### Problem Statement

**Gemini:** "Sending an update at most once every 500-1000ms prevents flooding the client and rendering the UI unresponsive."

Large batch operations (100+ book imports) generate 100+ WebSocket messages in rapid succession. iOS processes each message on the main thread, causing UI lag and dropped frames.

#### Architecture

**Throttling Strategy:**
- **Time-based:** Send updates at most once per 500ms
- **Significance-based:** Always send first update, 25%, 50%, 75%, 100%
- **Keep-alive:** Don't throttle if >10s since last update (prevent timeout)

**Implementation:**
```
Progress Updates Stream:
1% → 2% → 3% → 4% → 5% → ... → 100%
         ↓ Throttle
1% → [skip] → [skip] → [skip] → 5% → ...
(only send every 500ms or significant milestones)
```

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Add throttling state:**

```javascript
class ProgressWebSocketDO {
  constructor(state, env) {
    this.state = state;
    this.storage = state.storage;
    this.env = env;
    this.webSocket = null;
    this.jobId = null;

    // Throttling state
    this.lastProgressSentTime = 0;
    this.pendingProgress = null;
    this.throttleInterval = 500; // 500ms
    this.flushTimer = null;
  }

  /**
   * Update progress with server-side throttling
   * Queues updates and sends at most once per 500ms
   */
  async updateProgressV2Throttled(pipeline, payload) {
    const now = Date.now();
    const timeSinceLastSend = now - this.lastProgressSentTime;

    // Always send if:
    // 1. First update (lastProgressSentTime === 0)
    // 2. Significant milestone (processedCount % 25 === 0)
    // 3. More than 10s since last update (keep-alive)
    // 4. More than 500ms since last update (throttle interval)
    const isFirstUpdate = this.lastProgressSentTime === 0;
    const isSignificantMilestone = payload.processedCount % 25 === 0;
    const isKeepAlive = timeSinceLastSend > 10000;
    const isThrottleIntervalPassed = timeSinceLastSend >= this.throttleInterval;

    if (isFirstUpdate || isSignificantMilestone || isKeepAlive || isThrottleIntervalPassed) {
      // Send immediately
      await this.sendProgressUpdate(pipeline, payload);
      this.lastProgressSentTime = now;
      this.pendingProgress = null;

      // Cancel any pending flush
      if (this.flushTimer) {
        clearTimeout(this.flushTimer);
        this.flushTimer = null;
      }
    } else {
      // Queue for later
      this.pendingProgress = { pipeline, payload };

      // Schedule flush after throttle interval
      if (!this.flushTimer) {
        this.flushTimer = setTimeout(() => {
          if (this.pendingProgress) {
            this.sendProgressUpdate(
              this.pendingProgress.pipeline,
              this.pendingProgress.payload
            );
            this.lastProgressSentTime = Date.now();
            this.pendingProgress = null;
          }
          this.flushTimer = null;
        }, this.throttleInterval - timeSinceLastSend);
      }

      console.log(`[${this.jobId}] Progress update throttled (pending: ${payload.processedCount})`);
    }
  }

  /**
   * Internal method to actually send progress update
   * Called by throttled update logic
   */
  async sendProgressUpdate(pipeline, payload) {
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection for job_progress`);
      return { success: false };
    }

    const message = WebSocketMessageFactory.createJobProgress(
      this.jobId,
      pipeline,
      payload
    );

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] job_progress sent`, {
        processedCount: payload.processedCount,
        currentTitle: payload.currentTitle
      });
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send job_progress:`, error);
      return { success: false };
    }
  }

  /**
   * Ensure final update is sent on job completion
   * Flushes any pending throttled update
   */
  async completeV2(pipeline, payload) {
    // Flush pending progress before completing
    if (this.pendingProgress) {
      await this.sendProgressUpdate(
        this.pendingProgress.pipeline,
        this.pendingProgress.payload
      );
      this.pendingProgress = null;
    }

    // Cancel flush timer
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }

    // Send completion message (existing logic)
    // ...
  }
}
```

**Update batch enrichment handler:**

```javascript
// In batch-enrichment.js
async function processBatchEnrichment(books, doStub, env) {
  const startTime = Date.now();

  const enrichedBooks = await enrichBooksParallel(
    books,
    async (book) => {
      // ... enrichment logic ...
    },
    async (completed, total, title, hasError) => {
      // Use throttled update
      await doStub.updateProgressV2Throttled('batch_enrichment', {
        processedCount: completed,
        currentTitle: title,
        currentItem: {
          isbn: book.isbn,
          author: book.author
        },
        userMessage: hasError ? `Failed: ${title}` : undefined
      });
    },
    10 // Concurrency limit
  );

  await doStub.completeV2('batch_enrichment', {
    successCount: enrichedBooks.filter(b => b.success).length,
    failureCount: enrichedBooks.filter(b => !b.success).length,
    duration: Math.floor((Date.now() - startTime) / 1000),
    results: { books: enrichedBooks },
    summary: `Enriched ${successCount} of ${total} books`
  });
}
```

#### iOS Considerations

**No iOS changes needed!** Throttling is server-side only. iOS benefits from:
- Fewer messages to parse (reduces CPU load)
- Smoother UI updates (less main thread blocking)
- Lower battery consumption (fewer wake-ups)

#### Testing

**Backend Tests:**
```javascript
describe('Message Throttling', () => {
  it('sends first update immediately', async () => {
    const doStub = getDoStub();

    await doStub.updateProgressV2Throttled('batch_enrichment', {
      processedCount: 1
    });

    expect(doStub.webSocket.send).toHaveBeenCalledTimes(1);
  });

  it('throttles rapid updates', async () => {
    const doStub = getDoStub();

    // Send 10 updates rapidly (< 500ms apart)
    for (let i = 1; i <= 10; i++) {
      await doStub.updateProgressV2Throttled('batch_enrichment', {
        processedCount: i
      });
    }

    // Only first update should be sent immediately
    expect(doStub.webSocket.send).toHaveBeenCalledTimes(1);
  });

  it('sends significant milestones', async () => {
    const doStub = getDoStub();

    // Send updates for 1, 24, 25, 26
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 1 });
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 24 });
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 25 });
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 26 });

    // 1 and 25 should be sent (first + milestone)
    expect(doStub.webSocket.send).toHaveBeenCalledTimes(2);
  });

  it('flushes pending update on completion', async () => {
    const doStub = getDoStub();

    // Send rapid updates
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 1 });
    await doStub.updateProgressV2Throttled('batch_enrichment', { processedCount: 2 });

    // Complete job
    await doStub.completeV2('batch_enrichment', { /* ... */ });

    // Should send: 1 (immediate) + 2 (flushed) + complete
    expect(doStub.webSocket.send).toHaveBeenCalledTimes(3);
  });
});
```

**Performance Tests:**
```javascript
describe('Throttling Performance', () => {
  it('handles 1000 updates efficiently', async () => {
    const doStub = getDoStub();
    const startTime = Date.now();

    for (let i = 1; i <= 1000; i++) {
      await doStub.updateProgressV2Throttled('batch_enrichment', {
        processedCount: i
      });
    }

    const duration = Date.now() - startTime;

    // Should complete in < 2 seconds (throttling overhead minimal)
    expect(duration).toBeLessThan(2000);

    // Should send ~40 messages (1 every 500ms over ~20s simulation)
    // Actual count depends on timing
    expect(doStub.webSocket.send).toHaveBeenCalledTimes(expect.any(Number));
  });
});
```

**Manual Testing:**
1. Import 100+ book CSV
2. Monitor Worker logs for "Progress update throttled"
3. iOS should see ~2 updates per second (vs 10-20 without throttling)
4. Verify UI remains responsive during import
5. Verify final progress reaches 100%

#### Success Criteria
- [ ] Throttling sends at most 1 message per 500ms
- [ ] First update sent immediately
- [ ] Significant milestones (25%, 50%, 75%, 100%) always sent
- [ ] Keep-alive sends after 10s of silence
- [ ] Pending updates flushed on job completion
- [ ] iOS UI remains responsive during large imports
- [ ] Tests pass (backend performance tests)
- [ ] No messages lost (final count accurate)

---

### Task 3: Enhanced Error Messages with Structured Codes
**Priority:** MEDIUM
**Effort:** 4-6 hours

#### Problem Statement

Current error messages lack structure:
- No error codes (can't programmatically handle specific errors)
- No affected item context (which books failed?)
- No retry guidance (should user try again?)
- No success/failure breakdown (partial success invisible)

#### Architecture

**Structured Error Payload:**
```typescript
{
  code: "E_ENRICHMENT_FAILED",
  message: "Failed to enrich 5 books: API timeout",  // Technical
  userMessage: "Some books couldn't be found. You can retry these manually.", // User-facing
  affectedItems: ["The Great Gatsby", "1984", ...],  // Up to 10 items
  retryable: true,
  details: {
    failureCount: 5,
    successCount: 45,
    provider: "Google Books",
    statusCode: 503
  }
}
```

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`

**Update error handling in enrichment loop:**

```javascript
async function processBatchEnrichment(books, doStub, env) {
  const startTime = Date.now();
  const failedBooks = [];

  try {
    const enrichedBooks = await enrichBooksParallel(
      books,
      async (book) => {
        try {
          const enriched = await enrichSingleBook(
            { title: book.title, author: book.author, isbn: book.isbn },
            env
          );

          if (enriched) {
            return { ...book, enriched, success: true };
          } else {
            // Track failure
            failedBooks.push(book.title);
            return {
              ...book,
              enriched: null,
              success: false,
              error: 'Book not found in any provider'
            };
          }
        } catch (error) {
          failedBooks.push(book.title);
          return {
            ...book,
            enriched: null,
            success: false,
            error: error.message
          };
        }
      },
      async (completed, total, title, hasError) => {
        await doStub.updateProgressV2Throttled('batch_enrichment', {
          processedCount: completed,
          currentTitle: title,
          userMessage: hasError ? `⚠️ Could not find: ${title}` : undefined
        });
      },
      10
    );

    const successCount = enrichedBooks.filter(b => b.success).length;
    const failureCount = enrichedBooks.filter(b => !b.success).length;

    // Send completion with success/failure breakdown
    await doStub.completeV2('batch_enrichment', {
      successCount,
      failureCount,
      duration: Math.floor((Date.now() - startTime) / 1000),
      results: { books: enrichedBooks },
      summary: failureCount > 0
        ? `Added ${successCount} books. ${failureCount} couldn't be found.`
        : `Added ${successCount} books to your library.`
    });

  } catch (error) {
    // Catastrophic failure - send structured error
    await doStub.sendError('batch_enrichment', {
      code: ErrorCodes.ENRICHMENT_FAILED,
      message: `Batch enrichment failed: ${error.message}`,
      userMessage: 'Something went wrong during enrichment. Please try again.',
      affectedItems: failedBooks.slice(0, 10), // Max 10 items
      retryable: true,
      details: {
        failureCount: failedBooks.length,
        successCount: books.length - failedBooks.length,
        provider: 'Multiple',
        stack: error.stack
      }
    });
  }
}
```

**Update CSV import handler:**

```javascript
// In csv-import.js
try {
  const parsedBooks = await parseCSVWithGemini(csvContent, env);

  // ... existing logic ...
} catch (error) {
  await doStub.sendError('csv_import', {
    code: error.code || ErrorCodes.CSV_PARSE_FAILED,
    message: error.message,
    userMessage: error.code === ErrorCodes.GEMINI_TIMEOUT
      ? 'AI parsing took too long. Try a smaller file.'
      : 'Could not parse your CSV file. Please check the format.',
    retryable: error.code !== ErrorCodes.INVALID_CSV_FORMAT,
    details: {
      fileName: metadata.fileName,
      fileSize: metadata.fileSize,
      provider: 'Gemini 2.0 Flash'
    }
  });
}
```

**Update AI scanner handler:**

```javascript
// In bookshelf-scanner.js
try {
  const detectedBooks = await scanBookshelfWithGemini(imageBuffer, env);

  if (detectedBooks.length === 0) {
    await doStub.sendError('ai_scan', {
      code: ErrorCodes.NO_BOOKS_DETECTED,
      message: 'Gemini did not detect any books in the image',
      userMessage: 'No books found. Try a clearer photo with better lighting.',
      retryable: true,
      details: {
        imageSize: imageBuffer.length,
        provider: 'Gemini 2.0 Flash'
      }
    });
    return;
  }

  // ... existing logic ...
} catch (error) {
  const isTimeout = error.message.includes('timeout');

  await doStub.sendError('ai_scan', {
    code: isTimeout ? ErrorCodes.GEMINI_TIMEOUT : ErrorCodes.GEMINI_API_ERROR,
    message: error.message,
    userMessage: isTimeout
      ? 'AI analysis took too long. Try a smaller photo.'
      : 'AI analysis failed. Please try again.',
    retryable: true,
    details: {
      imageSize: imageBuffer.length,
      provider: 'Gemini 2.0 Flash',
      apiEndpoint: 'generateContent'
    }
  });
}
```

#### iOS Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/GenericWebSocketHandler.swift`

**Update error handling:**

```swift
case .error(let msg):
    let payload = msg.payload

    #if DEBUG
    print("❌ Job error: [\(payload.code)] \(payload.userMessage)")
    if let affectedItems = payload.affectedItems, !affectedItems.isEmpty {
        print("   Affected items: \(affectedItems.joined(separator: ", "))")
    }
    #endif

    // Display user-friendly alert with retry option
    if payload.retryable {
        // Show alert with "Retry" button
    } else {
        // Show alert with "OK" button
    }

    onError(payload)
    disconnect()
```

**Add error display in views:**

```swift
// In EnrichmentQueueView or similar
.alert("Enrichment Error", isPresented: $showingError) {
    if errorPayload?.retryable == true {
        Button("Retry") {
            // Retry logic
        }
    }
    Button("OK", role: .cancel) { }
} message: {
    Text(errorPayload?.userMessage ?? "An error occurred")

    if let affectedItems = errorPayload?.affectedItems, !affectedItems.isEmpty {
        Text("\n\nAffected books:\n\(affectedItems.joined(separator: "\n"))")
            .font(.caption)
    }
}
```

#### Testing

**Backend Tests:**
```javascript
describe('Enhanced Error Messages', () => {
  it('sends structured error with all fields', async () => {
    const doStub = getDoStub();

    await doStub.sendError('batch_enrichment', {
      code: ErrorCodes.ENRICHMENT_FAILED,
      message: 'Technical error message',
      userMessage: 'User-friendly message',
      affectedItems: ['Book 1', 'Book 2'],
      retryable: true,
      details: { failureCount: 2 }
    });

    const sent = JSON.parse(doStub.webSocket.send.mock.calls[0][0]);
    expect(sent.payload.code).toBe('E_ENRICHMENT_FAILED');
    expect(sent.payload.affectedItems).toHaveLength(2);
    expect(sent.payload.retryable).toBe(true);
  });
});
```

**iOS Tests:**
```swift
@Test("Parse error message with affected items")
func testErrorMessageParsing() async throws {
    let json = """
    {
      "type": "error",
      "jobId": "test-123",
      "pipeline": "batch_enrichment",
      "timestamp": 1699564820000,
      "version": "1.0.0",
      "payload": {
        "code": "E_ENRICHMENT_FAILED",
        "message": "Technical message",
        "userMessage": "Some books couldn't be found",
        "affectedItems": ["Book 1", "Book 2"],
        "retryable": true
      }
    }
    """

    let data = json.data(using: .utf8)!
    let message = try TypedWebSocketMessage(from: data)

    if case .error(let msg) = message {
        #expect(msg.payload.code == "E_ENRICHMENT_FAILED")
        #expect(msg.payload.affectedItems?.count == 2)
        #expect(msg.payload.retryable == true)
    } else {
        Issue.record("Expected error message")
    }
}
```

#### Success Criteria
- [ ] All error messages include structured codes
- [ ] Affected items listed (max 10)
- [ ] Retry guidance provided (`retryable` flag)
- [ ] Success/failure breakdown in details
- [ ] iOS displays user-friendly alerts
- [ ] iOS shows retry button when applicable
- [ ] Tests pass (backend + iOS)
- [ ] Error codes documented

---

### Task 4: User-Friendly Status Messages
**Priority:** MEDIUM
**Effort:** 4-6 hours

#### Problem Statement

Current status messages are technical:
- `"Enriching (5/10): The Great Gatsby"` → Too verbose, not user-friendly
- No context about what's happening
- No estimated time remaining
- No pipeline-specific messaging

#### Improved Messages

**Batch Enrichment:**
- Old: `"Enriching (5/10): The Great Gatsby"`
- New: `"Finding details for The Great Gatsby... 5 of 10 books complete"`

**CSV Import:**
- Old: `"Parsing CSV (50%)"`
- New: `"📄 Reading your library export... 50% complete"`

**AI Scanner:**
- Old: `"Processing image"`
- New: `"🔍 Analyzing bookshelf photo with AI..."`

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/utils/status-messages.js` (NEW)

```javascript
/**
 * Generate user-friendly status messages for different pipelines
 */

export class StatusMessageFormatter {
  /**
   * Format batch enrichment progress message
   */
  static formatEnrichmentProgress(processedCount, totalCount, currentTitle, hasError = false) {
    if (hasError) {
      return {
        userMessage: `⚠️ Couldn't find details for ${currentTitle}`,
        technicalMessage: `Enrichment failed (${processedCount}/${totalCount}): ${currentTitle}`
      };
    }

    const percentage = Math.floor((processedCount / totalCount) * 100);
    const remaining = totalCount - processedCount;

    return {
      userMessage: `Finding details for ${currentTitle}... ${processedCount} of ${totalCount} books complete`,
      technicalMessage: `Enriching (${processedCount}/${totalCount}): ${currentTitle}`,
      metadata: {
        percentage,
        remaining,
        estimatedTimeRemaining: this.estimateTimeRemaining(processedCount, totalCount)
      }
    };
  }

  /**
   * Format CSV import progress message
   */
  static formatCSVImportProgress(progress, phase = 'parsing') {
    const percentage = Math.floor(progress * 100);

    const phaseMessages = {
      parsing: `📄 Reading your library export... ${percentage}% complete`,
      validating: `✅ Validating book data... ${percentage}% complete`,
      saving: `💾 Adding books to your library... ${percentage}% complete`
    };

    return {
      userMessage: phaseMessages[phase] || phaseMessages.parsing,
      technicalMessage: `CSV ${phase} (${percentage}%)`,
      metadata: { percentage, phase }
    };
  }

  /**
   * Format AI scanner progress message
   */
  static formatAIScanProgress(phase = 'analyzing') {
    const phaseMessages = {
      uploading: '📤 Uploading photo...',
      analyzing: '🔍 Analyzing bookshelf with AI...',
      extracting: '📚 Detecting book titles...',
      enriching: '✨ Finding cover art and details...',
      complete: '✅ Scan complete!'
    };

    return {
      userMessage: phaseMessages[phase] || phaseMessages.analyzing,
      technicalMessage: `AI scan: ${phase}`,
      metadata: { phase }
    };
  }

  /**
   * Estimate time remaining based on current progress
   * Returns seconds
   */
  static estimateTimeRemaining(processedCount, totalCount, startTime = null) {
    if (processedCount === 0) return null;
    if (!startTime) return null;

    const elapsed = Date.now() - startTime;
    const avgTimePerItem = elapsed / processedCount;
    const remaining = totalCount - processedCount;

    return Math.ceil((remaining * avgTimePerItem) / 1000); // Convert to seconds
  }
}
```

**Update batch enrichment handler:**

```javascript
// In batch-enrichment.js
async (completed, total, title, hasError) => {
  const { userMessage, technicalMessage } = StatusMessageFormatter.formatEnrichmentProgress(
    completed,
    total,
    title,
    hasError
  );

  await doStub.updateProgressV2Throttled('batch_enrichment', {
    processedCount: completed,
    currentTitle: title,
    userMessage // NEW: User-friendly message
  });

  console.log(`[Enrichment] ${technicalMessage}`); // Keep technical log
}
```

**Update CSV import handler:**

```javascript
// In csv-import.js
await doStub.updateProgressV2Throttled('csv_import', {
  processedCount: Math.floor(progress * totalRows),
  userMessage: StatusMessageFormatter.formatCSVImportProgress(progress, 'parsing').userMessage
});
```

**Update AI scanner handler:**

```javascript
// In bookshelf-scanner.js

// Phase 1: Analyzing
await doStub.updateProgressV2Throttled('ai_scan', {
  processedCount: 0,
  userMessage: StatusMessageFormatter.formatAIScanProgress('analyzing').userMessage
});

// Phase 2: Extracting
await doStub.updateProgressV2Throttled('ai_scan', {
  processedCount: 50,
  userMessage: StatusMessageFormatter.formatAIScanProgress('extracting').userMessage
});

// Phase 3: Enriching
await doStub.updateProgressV2Throttled('ai_scan', {
  processedCount: 75,
  userMessage: StatusMessageFormatter.formatAIScanProgress('enriching').userMessage
});
```

#### iOS Implementation

**Display user messages in UI:**

```swift
// In enrichment views
if let userMessage = progressPayload.userMessage {
    Text(userMessage)
        .font(.body)
        .foregroundColor(.secondary)
} else {
    // Fallback to count-based message
    Text("Processing \(processedCount) of \(totalCount) items...")
}
```

#### Testing

**Backend Tests:**
```javascript
describe('Status Message Formatter', () => {
  it('formats enrichment progress', () => {
    const msg = StatusMessageFormatter.formatEnrichmentProgress(5, 10, 'The Great Gatsby');
    expect(msg.userMessage).toContain('Finding details');
    expect(msg.userMessage).toContain('5 of 10');
  });

  it('formats error messages', () => {
    const msg = StatusMessageFormatter.formatEnrichmentProgress(5, 10, 'Bad Title', true);
    expect(msg.userMessage).toContain('⚠️');
    expect(msg.userMessage).toContain("Couldn't find");
  });
});
```

#### Success Criteria
- [ ] User-friendly messages for all pipelines
- [ ] Messages include emojis and context
- [ ] Technical logs remain for debugging
- [ ] iOS displays formatted messages
- [ ] Tests pass
- [ ] User feedback positive

---

## Phase 2 Timeline

| Task | Effort | Start | End |
|------|--------|-------|-----|
| Heartbeat Mechanism | 10h | Day 1 | Day 2 |
| Message Throttling | 8h | Day 2 | Day 3 |
| Enhanced Errors | 6h | Day 3 | Day 4 |
| User-Friendly Messages | 6h | Day 4 | Day 5 |
| Integration Testing | 8h | Day 5 | Day 6 |
| **Total** | **38h** | | **6 days** |

## Success Metrics

- ✅ Zero connection timeouts (heartbeat working)
- ✅ <2 progress messages per second (throttling working)
- ✅ 100% of errors include structured codes
- ✅ 90%+ user satisfaction with status messages
- ✅ All tests passing

## Dependencies for Phase 3

Phase 2 completion enables:
- Message batching (builds on throttling)
- Performance monitoring (needs error codes)
- A/B testing user messages

---

**Prepared by:** Claude Code
**Expert Review:** Pending (Gemini 2.5 Pro, Grok-4)
