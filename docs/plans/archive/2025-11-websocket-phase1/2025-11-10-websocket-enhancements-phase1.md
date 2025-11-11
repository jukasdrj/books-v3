# WebSocket Enhancements - Phase 1 Implementation Plan

**Date:** November 10, 2025
**Status:** 🚧 Ready for Implementation
**Priority:** CRITICAL
**Estimated Effort:** 3-4 days

## Executive Summary

Phase 1 addresses critical security vulnerabilities and architectural foundations identified through multi-expert consensus (Claude, Gemini 2.5 Pro, Grok-4). This phase establishes the groundwork for all future WebSocket improvements.

## Expert Consensus Summary

### Security (Priority #1)
- **Gemini:** "Security vulnerability... critical risk that should be addressed immediately"
- **Grok:** "Unauthenticated endpoints are an exploit vector... could inflate costs"
- **Impact:** CSV import and AI scanner pipelines currently lack authentication

### Architecture (Priority #2)
- **Gemini:** "Define a unified message schema... prevents similar bugs in the future"
- **Grok:** "Use a unified envelope... reduces iOS parsing branches"
- **Impact:** Current format mismatch blocks iOS parsing

### Resilience (Priority #3)
- **Gemini:** "Not optional for a mobile application"
- **Grok:** "Absolutely—prioritize this... networks flake on iOS"
- **Impact:** DO state loss on eviction, no reconnect strategy

---

## Phase 1 Tasks

### Task 1: Implement Token Authentication for CSV/AI Pipelines
**Issue:** #362
**Priority:** CRITICAL
**Effort:** 4-6 hours

#### Problem Statement
CSV import (`/api/import/csv-gemini`) and AI bookshelf scanner (`/api/scan-bookshelf`) lack WebSocket authentication, creating security vulnerabilities and potential cost inflation through DDoS attacks.

#### Backend Changes

**1.1 Update CSV Import Handler**

**File:** `cloudflare-workers/api-worker/src/handlers/csv-import.js`

**Location:** After Durable Object stub creation (around line 50-60)

```javascript
// SECURITY: Generate authentication token for WebSocket connection
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

console.log(`[CSV Import] Auth token generated for job ${jobId}`);
```

**Response Update:**
```javascript
return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW: Token for WebSocket authentication
  message: 'CSV parsing started'
}, {}, 202);
```

**1.2 Update Bookshelf Scanner Handler**

**File:** `cloudflare-workers/api-worker/src/handlers/bookshelf-scanner.js`

**Single Photo Scan (around line 100-120):**
```javascript
// SECURITY: Generate authentication token for WebSocket connection
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW: Token for WebSocket authentication
  message: 'Scan started'
}, {}, 202);
```

**Batch Scan (around line 200-220):**
```javascript
// SECURITY: Generate authentication token for WebSocket connection
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW: Token for WebSocket authentication
  totalPhotos: photos.length,
  message: 'Batch scan started'
}, {}, 202);
```

#### iOS Changes

**1.3 Update CSV Import Service**

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`

**Response Struct Update (around line 20-25):**
```swift
struct CSVImportResponse: Codable, Sendable {
    let success: Bool
    let jobId: String
    let token: String  // NEW: Auth token for WebSocket
    let message: String?
}
```

**WebSocket Handler Initialization (around line 80-100):**
```swift
// Extract token from response
guard let token = response.token else {
    #if DEBUG
    print("⚠️ No auth token received - WebSocket may fail")
    #endif
    throw CSVImportError.missingToken
}

#if DEBUG
print("🔐 Auth token received: \(token.prefix(8))...")
#endif

// Create WebSocket handler with token
let wsHandler = CSVWebSocketHandler(
    jobId: jobId,
    token: token,  // NEW: Pass token
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

**1.4 Update Bookshelf Scanner Service**

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Scanner/BookshelfScannerService.swift`

**Response Struct Update (around line 15-20):**
```swift
struct ScanResponse: Codable, Sendable {
    let success: Bool
    let jobId: String
    let token: String  // NEW: Auth token for WebSocket
    let message: String?
}
```

**WebSocket Handler Initialization (around line 60-80):**
```swift
// Extract token from response
guard let token = scanResponse.token else {
    #if DEBUG
    print("⚠️ No auth token received - WebSocket may fail")
    #endif
    throw ScanError.missingToken
}

#if DEBUG
print("🔐 Auth token received for scan job: \(jobId)")
#endif

// Create WebSocket handler with token
let wsHandler = ScanWebSocketHandler(
    jobId: jobId,
    token: token,  // NEW: Pass token
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

#### Testing

**Backend Tests:**
```bash
# Test CSV import token generation
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/import/csv-gemini \
  -F "file=@docs/testImages/goodreads_library_export.csv" \
  | jq '.data.token'

# Test bookshelf scanner token generation
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/scan-bookshelf \
  -F "image=@docs/testImages/bookshelf-test.jpg" \
  | jq '.data.token'

# Test WebSocket authentication (should fail without token)
wscat -c "wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123"
# Expected: 401 Unauthorized

# Test WebSocket authentication (should succeed with token)
wscat -c "wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123&token=valid-token"
# Expected: 101 Switching Protocols
```

**iOS Tests:**
1. Settings → Library Management → AI-Powered CSV Import
2. Upload test CSV
3. Verify console logs:
   - ✅ "🔐 Auth token received: [8 chars]..."
   - ✅ "✅ WebSocket connected with authentication"
   - ✅ Progress updates received
4. Shelf tab → Capture photo
5. Verify same token flow

#### Success Criteria
- [ ] CSV import endpoint generates tokens
- [ ] Bookshelf scanner endpoint generates tokens
- [ ] iOS CSV service uses token authentication
- [ ] iOS scanner service uses token authentication
- [ ] WebSocket connections fail with 401 if token missing/invalid
- [ ] Zero warnings in iOS build
- [ ] Manual testing confirms progress updates work

---

### Task 2: Define Unified Message Schema
**Priority:** CRITICAL (Foundation for all future work)
**Effort:** 6-8 hours

#### Problem Statement
Current WebSocket messages lack consistency:
- Backend sends: `{type, data: {progress, status}}`
- iOS expects: `{type, processedCount, totalCount, currentTitle}`
- No support for concurrent jobs
- No versioning or pipeline identification

#### Unified Schema Design

**Base Message Envelope:**
```typescript
interface WebSocketMessage {
  type: MessageType;
  jobId: string;           // Client correlation
  pipeline: PipelineType;  // Source identification
  timestamp: number;       // Server time (ms since epoch)
  version: string;         // Schema version (e.g., "1.0.0")
  payload: MessagePayload; // Type-specific data
}

type MessageType =
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"
  | "ping"
  | "pong";

type PipelineType =
  | "batch_enrichment"
  | "csv_import"
  | "ai_scan";
```

**Message Type Payloads:**

**1. job_started:**
```typescript
interface JobStartedPayload {
  totalCount: number;      // Total items to process
  estimatedDuration?: number; // Seconds (optional)
  metadata?: {
    fileName?: string;      // CSV filename
    fileSize?: number;      // Bytes
    photoCount?: number;    // For batch scans
  };
}
```

**Example:**
```json
{
  "type": "job_started",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "pipeline": "csv_import",
  "timestamp": 1699564800000,
  "version": "1.0.0",
  "payload": {
    "totalCount": 150,
    "estimatedDuration": 45,
    "metadata": {
      "fileName": "my_library.csv",
      "fileSize": 245678
    }
  }
}
```

**2. job_progress:**
```typescript
interface JobProgressPayload {
  processedCount: number;  // Items completed so far
  currentTitle?: string;   // Current item being processed
  currentItem?: {          // Optional detailed context
    isbn?: string;
    author?: string;
  };
  userMessage?: string;    // Optional user-facing message
}
```

**Example:**
```json
{
  "type": "job_progress",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "pipeline": "batch_enrichment",
  "timestamp": 1699564815000,
  "version": "1.0.0",
  "payload": {
    "processedCount": 15,
    "currentTitle": "The Great Gatsby",
    "currentItem": {
      "isbn": "9780743273565",
      "author": "F. Scott Fitzgerald"
    },
    "userMessage": "Finding cover art and details..."
  }
}
```

**3. job_complete:**
```typescript
interface JobCompletePayload {
  successCount: number;
  failureCount: number;
  duration: number;        // Actual duration in seconds
  results: any;            // Pipeline-specific results
  summary?: string;        // User-facing summary
}
```

**Example:**
```json
{
  "type": "job_complete",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "pipeline": "csv_import",
  "timestamp": 1699564845000,
  "version": "1.0.0",
  "payload": {
    "successCount": 145,
    "failureCount": 5,
    "duration": 43,
    "results": {
      "books": [...],
      "errors": [...]
    },
    "summary": "Added 145 books to your library"
  }
}
```

**4. error:**
```typescript
interface ErrorPayload {
  code: string;            // E_ENRICHMENT_FAILED, E_GEMINI_TIMEOUT, etc.
  message: string;         // Technical error message
  userMessage: string;     // User-friendly message
  affectedItems?: string[]; // Item IDs/titles that failed
  retryable: boolean;      // Can user retry?
  details?: any;           // Additional context
}
```

**Example:**
```json
{
  "type": "error",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "pipeline": "ai_scan",
  "timestamp": 1699564820000,
  "version": "1.0.0",
  "payload": {
    "code": "E_GEMINI_TIMEOUT",
    "message": "Gemini API request timed out after 60s",
    "userMessage": "AI analysis took too long. Please try again with a clearer photo.",
    "retryable": true,
    "details": {
      "apiEndpoint": "gemini.generateContent",
      "photoSize": "4.2MB"
    }
  }
}
```

**5. ping/pong (Heartbeat):**
```typescript
interface HeartbeatPayload {
  clientTime?: number;  // Client timestamp (for RTT calc)
}
```

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/types/websocket-messages.ts` (NEW)

```typescript
/**
 * Unified WebSocket Message Schema v1.0.0
 *
 * All WebSocket messages follow this structure for consistency
 * across batch enrichment, CSV import, and AI scan pipelines.
 */

export interface WebSocketMessage<T = any> {
  type: MessageType;
  jobId: string;
  pipeline: PipelineType;
  timestamp: number;
  version: string;
  payload: T;
}

export type MessageType =
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"
  | "ping"
  | "pong";

export type PipelineType =
  | "batch_enrichment"
  | "csv_import"
  | "ai_scan";

export interface JobStartedPayload {
  totalCount: number;
  estimatedDuration?: number;
  metadata?: Record<string, any>;
}

export interface JobProgressPayload {
  processedCount: number;
  currentTitle?: string;
  currentItem?: {
    isbn?: string;
    author?: string;
  };
  userMessage?: string;
}

export interface JobCompletePayload {
  successCount: number;
  failureCount: number;
  duration: number;
  results: any;
  summary?: string;
}

export interface ErrorPayload {
  code: string;
  message: string;
  userMessage: string;
  affectedItems?: string[];
  retryable: boolean;
  details?: any;
}

export interface HeartbeatPayload {
  clientTime?: number;
}

/**
 * Factory for creating schema-compliant messages
 */
export class WebSocketMessageFactory {
  private static VERSION = "1.0.0";

  static createJobStarted(
    jobId: string,
    pipeline: PipelineType,
    payload: JobStartedPayload
  ): WebSocketMessage<JobStartedPayload> {
    return {
      type: "job_started",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload
    };
  }

  static createJobProgress(
    jobId: string,
    pipeline: PipelineType,
    payload: JobProgressPayload
  ): WebSocketMessage<JobProgressPayload> {
    return {
      type: "job_progress",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload
    };
  }

  static createJobComplete(
    jobId: string,
    pipeline: PipelineType,
    payload: JobCompletePayload
  ): WebSocketMessage<JobCompletePayload> {
    return {
      type: "job_complete",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload
    };
  }

  static createError(
    jobId: string,
    pipeline: PipelineType,
    payload: ErrorPayload
  ): WebSocketMessage<ErrorPayload> {
    return {
      type: "error",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload
    };
  }

  static createPong(
    jobId: string,
    pipeline: PipelineType,
    clientTime?: number
  ): WebSocketMessage<HeartbeatPayload> {
    return {
      type: "pong",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload: { clientTime }
    };
  }
}
```

**Update ProgressWebSocketDO:**

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Add imports:**
```javascript
import { WebSocketMessageFactory } from '../types/websocket-messages';
```

**Update methods:**
```javascript
/**
 * Send job started notification
 * @param {string} pipeline - Pipeline type (batch_enrichment, csv_import, ai_scan)
 * @param {Object} payload - JobStartedPayload
 */
async sendJobStarted(pipeline, payload) {
  if (!this.webSocket) {
    console.warn(`[${this.jobId}] No WebSocket connection for job_started`);
    return { success: false };
  }

  const message = WebSocketMessageFactory.createJobStarted(
    this.jobId,
    pipeline,
    payload
  );

  try {
    this.webSocket.send(JSON.stringify(message));
    console.log(`[${this.jobId}] job_started sent`, { totalCount: payload.totalCount });
    return { success: true };
  } catch (error) {
    console.error(`[${this.jobId}] Failed to send job_started:`, error);
    return { success: false };
  }
}

/**
 * Update progress with new schema
 * @param {string} pipeline - Pipeline type
 * @param {Object} payload - JobProgressPayload
 */
async updateProgressV2(pipeline, payload) {
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
 * Complete job with new schema
 * @param {string} pipeline - Pipeline type
 * @param {Object} payload - JobCompletePayload
 */
async completeV2(pipeline, payload) {
  if (!this.webSocket) {
    console.warn(`[${this.jobId}] No WebSocket connection for job_complete`);
    return { success: false };
  }

  const message = WebSocketMessageFactory.createJobComplete(
    this.jobId,
    pipeline,
    payload
  );

  try {
    this.webSocket.send(JSON.stringify(message));
    console.log(`[${this.jobId}] job_complete sent`);

    // Close connection after completion
    setTimeout(() => {
      if (this.webSocket) {
        this.webSocket.close(1000, 'Job completed');
        this.cleanup();
      }
    }, 1000);

    return { success: true };
  } catch (error) {
    console.error(`[${this.jobId}] Failed to send job_complete:`, error);
    return { success: false };
  }
}

/**
 * Send error with new schema
 * @param {string} pipeline - Pipeline type
 * @param {Object} payload - ErrorPayload
 */
async sendError(pipeline, payload) {
  if (!this.webSocket) {
    console.warn(`[${this.jobId}] No WebSocket connection for error`);
    return { success: false };
  }

  const message = WebSocketMessageFactory.createError(
    this.jobId,
    pipeline,
    payload
  );

  try {
    this.webSocket.send(JSON.stringify(message));
    console.error(`[${this.jobId}] error sent`, { code: payload.code });

    // Close connection after error
    setTimeout(() => {
      if (this.webSocket) {
        this.webSocket.close(1000, 'Job failed');
        this.cleanup();
      }
    }, 1000);

    return { success: true };
  } catch (error) {
    console.error(`[${this.jobId}] Failed to send error:`, error);
    return { success: false };
  }
}
```

**Backward Compatibility Layer:**

Keep old methods for gradual migration:
```javascript
/**
 * DEPRECATED: Use updateProgressV2 instead
 * Legacy method for backward compatibility
 */
async updateProgress(progress, status, keepAlive = false) {
  console.warn(`[${this.jobId}] Using deprecated updateProgress - migrate to updateProgressV2`);

  // Parse legacy status format "Enriching (5/10): Title"
  const match = status.match(/\((\d+)\/(\d+)\): (.+)/);

  if (match) {
    return await this.updateProgressV2('batch_enrichment', {
      processedCount: parseInt(match[1]),
      currentTitle: match[3]
    });
  }

  // Fallback for non-standard formats
  return await this.updateProgressV2('batch_enrichment', {
    processedCount: Math.floor(progress * 100),
    userMessage: status
  });
}
```

#### iOS Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/WebSocketMessages.swift` (NEW)

```swift
import Foundation

// MARK: - Unified WebSocket Message Schema v1.0.0

/// Base message envelope for all WebSocket communications
public struct WebSocketMessage<T: Decodable>: Decodable {
    public let type: MessageType
    public let jobId: String
    public let pipeline: PipelineType
    public let timestamp: Int64
    public let version: String
    public let payload: T
}

/// Message type discriminator
public enum MessageType: String, Decodable {
    case jobStarted = "job_started"
    case jobProgress = "job_progress"
    case jobComplete = "job_complete"
    case error
    case ping
    case pong
}

/// Pipeline identification
public enum PipelineType: String, Decodable {
    case batchEnrichment = "batch_enrichment"
    case csvImport = "csv_import"
    case aiScan = "ai_scan"
}

// MARK: - Payload Types

public struct JobStartedPayload: Decodable, Sendable {
    public let totalCount: Int
    public let estimatedDuration: Int?
    public let metadata: [String: AnyCodable]?
}

public struct JobProgressPayload: Decodable, Sendable {
    public let processedCount: Int
    public let currentTitle: String?
    public let currentItem: CurrentItem?
    public let userMessage: String?

    public struct CurrentItem: Decodable, Sendable {
        public let isbn: String?
        public let author: String?
    }
}

public struct JobCompletePayload: Decodable, Sendable {
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int
    public let results: AnyCodable
    public let summary: String?
}

public struct ErrorPayload: Decodable, Sendable {
    public let code: String
    public let message: String
    public let userMessage: String
    public let affectedItems: [String]?
    public let retryable: Bool
    public let details: AnyCodable?
}

public struct HeartbeatPayload: Decodable, Sendable {
    public let clientTime: Int64?
}

// MARK: - Helper for decoding heterogeneous JSON

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Discriminated Union for Type-Safe Message Handling

/// Type-safe wrapper for handling different message types
public enum TypedWebSocketMessage {
    case jobStarted(WebSocketMessage<JobStartedPayload>)
    case jobProgress(WebSocketMessage<JobProgressPayload>)
    case jobComplete(WebSocketMessage<JobCompletePayload>)
    case error(WebSocketMessage<ErrorPayload>)
    case heartbeat(WebSocketMessage<HeartbeatPayload>)
    case unknown

    public init(from data: Data) throws {
        // First, decode just the type field
        let container = try JSONDecoder().decode(TypeContainer.self, from: data)

        switch container.type {
        case .jobStarted:
            let message = try JSONDecoder().decode(WebSocketMessage<JobStartedPayload>.self, from: data)
            self = .jobStarted(message)
        case .jobProgress:
            let message = try JSONDecoder().decode(WebSocketMessage<JobProgressPayload>.self, from: data)
            self = .jobProgress(message)
        case .jobComplete:
            let message = try JSONDecoder().decode(WebSocketMessage<JobCompletePayload>.self, from: data)
            self = .jobComplete(message)
        case .error:
            let message = try JSONDecoder().decode(WebSocketMessage<ErrorPayload>.self, from: data)
            self = .error(message)
        case .ping, .pong:
            let message = try JSONDecoder().decode(WebSocketMessage<HeartbeatPayload>.self, from: data)
            self = .heartbeat(message)
        }
    }

    private struct TypeContainer: Decodable {
        let type: MessageType
    }
}
```

**Update Generic WebSocket Handler:**

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/GenericWebSocketHandler.swift` (NEW)

```swift
import Foundation

/// Generic WebSocket handler supporting unified message schema
@MainActor
public final class GenericWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let token: String
    private let pipeline: PipelineType
    private var isConnected = false

    // Callbacks for different message types
    private let onJobStarted: @MainActor (JobStartedPayload) -> Void
    private let onJobProgress: @MainActor (JobProgressPayload) -> Void
    private let onJobComplete: @MainActor (JobCompletePayload) -> Void
    private let onError: @MainActor (ErrorPayload) -> Void

    public init(
        jobId: String,
        token: String,
        pipeline: PipelineType,
        onJobStarted: @escaping @MainActor (JobStartedPayload) -> Void,
        onJobProgress: @escaping @MainActor (JobProgressPayload) -> Void,
        onJobComplete: @escaping @MainActor (JobCompletePayload) -> Void,
        onError: @escaping @MainActor (ErrorPayload) -> Void
    ) {
        self.jobId = jobId
        self.token = token
        self.pipeline = pipeline
        self.onJobStarted = onJobStarted
        self.onJobProgress = onJobProgress
        self.onJobComplete = onJobComplete
        self.onError = onError
    }

    public func connect() async {
        guard let url = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)&token=\(token)") else {
            #if DEBUG
            print("❌ Invalid WebSocket URL")
            #endif
            return
        }

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        if let webSocket = webSocket {
            do {
                try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
                isConnected = true
                #if DEBUG
                print("✅ WebSocket connected for \(pipeline.rawValue) job: \(jobId)")
                #endif
                listenForMessages()
            } catch {
                if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                    #if DEBUG
                    print("❌ WebSocket authentication failed: Invalid or expired token")
                    #endif
                } else {
                    #if DEBUG
                    print("❌ WebSocket connection failed: \(error)")
                    #endif
                }
                isConnected = false
            }
        }
    }

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self, self.isConnected else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.listenForMessages()
                case .failure(let error):
                    #if DEBUG
                    print("❌ WebSocket error: \(error)")
                    #endif
                    self.disconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let data = message.data else { return }

        do {
            let typedMessage = try TypedWebSocketMessage(from: data)

            switch typedMessage {
            case .jobStarted(let msg):
                #if DEBUG
                print("📢 Job started: \(msg.payload.totalCount) items")
                #endif
                onJobStarted(msg.payload)

            case .jobProgress(let msg):
                #if DEBUG
                print("📊 Progress: \(msg.payload.processedCount) - \(msg.payload.currentTitle ?? "processing...")")
                #endif
                onJobProgress(msg.payload)

            case .jobComplete(let msg):
                #if DEBUG
                print("✅ Job complete: \(msg.payload.successCount) succeeded, \(msg.payload.failureCount) failed")
                #endif
                onJobComplete(msg.payload)
                disconnect()

            case .error(let msg):
                #if DEBUG
                print("❌ Job error: \(msg.payload.code) - \(msg.payload.userMessage)")
                #endif
                onError(msg.payload)
                disconnect()

            case .heartbeat(let msg):
                #if DEBUG
                print("💓 Heartbeat: \(msg.type)")
                #endif
                // Handle pong - calculate RTT if needed

            case .unknown:
                #if DEBUG
                print("⚠️ Unknown message type received")
                #endif
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to parse WebSocket message: \(error)")
            #endif
        }
    }

    public func sendPing() {
        guard isConnected, let webSocket = webSocket else { return }

        let ping: [String: Any] = [
            "type": "ping",
            "jobId": jobId,
            "pipeline": pipeline.rawValue,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "version": "1.0.0",
            "payload": ["clientTime": Int64(Date().timeIntervalSince1970 * 1000)]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: ping) {
            webSocket.send(.data(data)) { error in
                if let error = error {
                    #if DEBUG
                    print("⚠️ Failed to send ping: \(error)")
                    #endif
                }
            }
        }
    }

    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }
}
```

#### Migration Strategy

**Phase 2.1: Add New Schema (Week 1)**
1. Backend: Add `websocket-messages.ts` type definitions
2. Backend: Add factory methods to ProgressWebSocketDO
3. Backend: Keep legacy methods for compatibility
4. iOS: Add `WebSocketMessages.swift` types
5. iOS: Add `GenericWebSocketHandler` class

**Phase 2.2: Migrate Batch Enrichment (Week 1)**
1. Update `batch-enrichment.js` handler to use new methods
2. Test with iOS enrichment flow
3. Monitor for errors, rollback if needed

**Phase 2.3: Migrate CSV Import (Week 2)**
1. Update `csv-import.js` handler
2. Update `CSVImportService.swift`
3. Test end-to-end

**Phase 2.4: Migrate AI Scanner (Week 2)**
1. Update `bookshelf-scanner.js` handler
2. Update `BookshelfScannerService.swift`
3. Test single and batch scans

**Phase 2.5: Remove Legacy Methods (Week 3)**
1. Deprecation warnings in console
2. Monitor usage metrics
3. Remove old methods after 2 weeks

#### Testing

**Schema Validation Tests:**
```typescript
// Backend: test message structure
describe('WebSocket Message Factory', () => {
  it('creates valid job_started message', () => {
    const msg = WebSocketMessageFactory.createJobStarted(
      'test-job-123',
      'batch_enrichment',
      { totalCount: 50 }
    );

    expect(msg.type).toBe('job_started');
    expect(msg.jobId).toBe('test-job-123');
    expect(msg.pipeline).toBe('batch_enrichment');
    expect(msg.version).toBe('1.0.0');
    expect(msg.payload.totalCount).toBe(50);
    expect(msg.timestamp).toBeGreaterThan(0);
  });
});
```

```swift
// iOS: test message parsing
func testJobStartedMessageParsing() async throws {
    let json = """
    {
      "type": "job_started",
      "jobId": "test-123",
      "pipeline": "batch_enrichment",
      "timestamp": 1699564800000,
      "version": "1.0.0",
      "payload": {
        "totalCount": 50,
        "estimatedDuration": 30
      }
    }
    """

    let data = json.data(using: .utf8)!
    let message = try TypedWebSocketMessage(from: data)

    if case .jobStarted(let msg) = message {
        #expect(msg.payload.totalCount == 50)
        #expect(msg.payload.estimatedDuration == 30)
    } else {
        Issue.record("Expected job_started message")
    }
}
```

**Integration Tests:**
1. Backend sends all message types
2. iOS parses without errors
3. Callbacks fire with correct data
4. Heartbeat mechanism works
5. Error messages display properly

#### Success Criteria
- [ ] TypeScript types defined and validated
- [ ] Swift Codable structs defined and tested
- [ ] Factory methods create valid messages
- [ ] iOS parses all message types correctly
- [ ] Backward compatibility maintained
- [ ] Unit tests pass (100% coverage on schema)
- [ ] Integration tests pass
- [ ] Documentation updated

---

### Task 3: Implement Durable Object State Persistence
**Priority:** HIGH
**Effort:** 4-6 hours

#### Problem Statement
**Gemini's Critical Finding:**
> "Does the ProgressWebSocketDO persist its state to storage? If a DO is evicted from memory due to inactivity or a platform update, its in-memory state is lost. For long-running jobs, you should periodically persist the state."

Currently, all state is in-memory only:
- `processedCount`, `totalCount`, `currentTitle` lost on eviction
- Reconnecting clients can't resume job state
- No recovery from DO restarts

#### Architecture

**State to Persist:**
```typescript
interface PersistedJobState {
  jobId: string;
  pipeline: PipelineType;
  totalCount: number;
  processedCount: number;
  currentTitle?: string;
  startTime: number;
  lastUpdateTime: number;
  status: 'running' | 'paused' | 'complete' | 'failed' | 'canceled';
  results?: any;
  error?: ErrorPayload;
}
```

**Persistence Strategy:**
1. **Immediate writes:** Job start, completion, error
2. **Periodic writes:** Every 5 progress updates OR every 10 seconds
3. **Read on demand:** WebSocket connect, state sync requests

#### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Add state management methods:**
```javascript
/**
 * Initialize job state in Durable Storage
 * Call this when job starts
 */
async initializeJobState(pipeline, totalCount) {
  const state = {
    jobId: this.jobId,
    pipeline,
    totalCount,
    processedCount: 0,
    startTime: Date.now(),
    lastUpdateTime: Date.now(),
    status: 'running'
  };

  await this.storage.put('jobState', state);
  console.log(`[${this.jobId}] Job state initialized in storage`);

  return state;
}

/**
 * Update job state in Durable Storage
 * Throttled to avoid excessive writes
 */
async updateJobState(updates) {
  const state = await this.storage.get('jobState') || {};

  const updatedState = {
    ...state,
    ...updates,
    lastUpdateTime: Date.now()
  };

  // Throttle: Only persist every 5 updates or 10 seconds
  const shouldPersist =
    !this._lastPersistTime ||
    (Date.now() - this._lastPersistTime) > 10000 ||
    (this._updatesSinceLastPersist >= 5);

  if (shouldPersist) {
    await this.storage.put('jobState', updatedState);
    this._lastPersistTime = Date.now();
    this._updatesSinceLastPersist = 0;
    console.log(`[${this.jobId}] Job state persisted to storage`);
  } else {
    this._updatesSinceLastPersist = (this._updatesSinceLastPersist || 0) + 1;
  }

  return updatedState;
}

/**
 * Get current job state from Durable Storage
 * Used for reconnect/resume scenarios
 */
async getJobState() {
  const state = await this.storage.get('jobState');

  if (!state) {
    console.warn(`[${this.jobId}] No persisted state found`);
    return null;
  }

  console.log(`[${this.jobId}] Retrieved state from storage`, {
    processedCount: state.processedCount,
    totalCount: state.totalCount,
    status: state.status
  });

  return state;
}

/**
 * Mark job as complete in storage
 */
async completeJobState(results) {
  const state = await this.storage.get('jobState') || {};

  const finalState = {
    ...state,
    processedCount: state.totalCount,
    status: 'complete',
    lastUpdateTime: Date.now(),
    results
  };

  await this.storage.put('jobState', finalState);
  console.log(`[${this.jobId}] Job marked as complete in storage`);

  // Set expiration alarm to clean up after 24 hours
  await this.storage.setAlarm(Date.now() + (24 * 60 * 60 * 1000));

  return finalState;
}

/**
 * Mark job as failed in storage
 */
async failJobState(error) {
  const state = await this.storage.get('jobState') || {};

  const failedState = {
    ...state,
    status: 'failed',
    lastUpdateTime: Date.now(),
    error
  };

  await this.storage.put('jobState', failedState);
  console.log(`[${this.jobId}] Job marked as failed in storage`);

  return failedState;
}

/**
 * Alarm handler for state cleanup
 * Called 24 hours after job completion
 */
async alarm() {
  console.log(`[${this.jobId}] Alarm triggered - cleaning up old job state`);

  await this.storage.delete('jobState');
  await this.storage.delete('authToken');
  await this.storage.delete('authTokenExpiration');
  await this.storage.delete('status'); // Legacy canceled status

  console.log(`[${this.jobId}] State cleanup complete`);
}
```

**Update existing methods to use persistence:**

```javascript
// In sendJobStarted()
async sendJobStarted(pipeline, payload) {
  // Initialize state in storage
  await this.initializeJobState(pipeline, payload.totalCount);

  // ... existing WebSocket send logic ...
}

// In updateProgressV2()
async updateProgressV2(pipeline, payload) {
  // Update persisted state
  await this.updateJobState({
    processedCount: payload.processedCount,
    currentTitle: payload.currentTitle
  });

  // ... existing WebSocket send logic ...
}

// In completeV2()
async completeV2(pipeline, payload) {
  // Mark as complete in storage
  await this.completeJobState(payload.results);

  // ... existing WebSocket send logic ...
}

// In sendError()
async sendError(pipeline, payload) {
  // Mark as failed in storage
  await this.failJobState(payload);

  // ... existing WebSocket send logic ...
}
```

**Add state sync RPC method:**

```javascript
/**
 * RPC Method: Get current job state for reconnecting clients
 * Called when iOS app reconnects after network drop
 *
 * @returns {Promise<Object>} Current job state or null
 */
async syncJobState() {
  const state = await this.getJobState();

  if (!state) {
    return { success: false, error: 'No state found' };
  }

  // Send current state as job_progress message if still running
  if (state.status === 'running' && this.webSocket) {
    const message = WebSocketMessageFactory.createJobProgress(
      this.jobId,
      state.pipeline,
      {
        processedCount: state.processedCount,
        currentTitle: state.currentTitle,
        userMessage: 'Resuming...'
      }
    );

    this.webSocket.send(JSON.stringify(message));
  }

  return {
    success: true,
    state
  };
}
```

#### iOS Implementation

**Add reconnect logic to GenericWebSocketHandler:**

```swift
// In GenericWebSocketHandler class

private var reconnectAttempts = 0
private let maxReconnectAttempts = 5
private var reconnectTimer: Task<Void, Never>?

public func connectWithRetry() async {
    reconnectAttempts = 0
    await attemptConnection()
}

private func attemptConnection() async {
    do {
        try await connect()
        reconnectAttempts = 0 // Reset on success
    } catch {
        guard reconnectAttempts < maxReconnectAttempts else {
            #if DEBUG
            print("❌ Max reconnect attempts reached for job: \(jobId)")
            #endif
            onError(ErrorPayload(
                code: "E_MAX_RETRIES",
                message: "Connection failed after \(maxReconnectAttempts) attempts",
                userMessage: "Unable to connect. Please try again later.",
                retryable: true,
                details: nil
            ))
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s

        #if DEBUG
        print("⚠️ Connection failed, retrying in \(delay)s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        #endif

        reconnectTimer = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await attemptConnection()
        }
    }
}

public func requestStateSync() async {
    // After reconnect, request current state from DO
    let syncRequest: [String: Any] = [
        "type": "sync_request",
        "jobId": jobId,
        "pipeline": pipeline.rawValue,
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        "version": "1.0.0",
        "payload": [:]
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: syncRequest),
          let webSocket = webSocket else {
        return
    }

    webSocket.send(.data(data)) { error in
        if let error = error {
            #if DEBUG
            print("⚠️ Failed to send sync request: \(error)")
            #endif
        } else {
            #if DEBUG
            print("📡 State sync requested for job: \(jobId)")
            #endif
        }
    }
}

public func cancelReconnection() {
    reconnectTimer?.cancel()
    reconnectTimer = nil
}
```

**Handle network transitions:**

```swift
// Add network monitoring
import Network

@MainActor
public class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published public var isConnected = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// In your WebSocket manager, observe network changes
private var cancellables = Set<AnyCancellable>()

init() {
    NetworkMonitor.shared.$isConnected
        .sink { [weak self] isConnected in
            Task { @MainActor [weak self] in
                if isConnected {
                    await self?.handleNetworkRestored()
                } else {
                    self?.handleNetworkLost()
                }
            }
        }
        .store(in: &cancellables)
}

private func handleNetworkLost() {
    #if DEBUG
    print("📡 Network lost - pausing operations")
    #endif
}

private func handleNetworkRestored() async {
    #if DEBUG
    print("📡 Network restored - attempting reconnect")
    #endif
    await attemptConnection()
    await requestStateSync()
}
```

#### Testing

**Backend Tests:**
```javascript
// Test state persistence
describe('ProgressWebSocketDO State Persistence', () => {
  it('persists job state on initialization', async () => {
    const doStub = getDoStub();
    await doStub.initializeJobState('batch_enrichment', 100);

    const state = await doStub.getJobState();
    expect(state.totalCount).toBe(100);
    expect(state.processedCount).toBe(0);
    expect(state.status).toBe('running');
  });

  it('throttles state updates', async () => {
    const doStub = getDoStub();
    await doStub.initializeJobState('csv_import', 50);

    // Send 4 updates - should not persist yet
    for (let i = 1; i <= 4; i++) {
      await doStub.updateJobState({ processedCount: i });
    }

    // 5th update should trigger persistence
    await doStub.updateJobState({ processedCount: 5 });

    const state = await doStub.getJobState();
    expect(state.processedCount).toBe(5);
  });

  it('cleans up state after 24 hours', async () => {
    const doStub = getDoStub();
    await doStub.completeJobState({ books: [] });

    // Fast-forward 24 hours
    await simulateAlarm(doStub, Date.now() + (24 * 60 * 60 * 1000));

    const state = await doStub.getJobState();
    expect(state).toBeNull();
  });
});
```

**iOS Tests:**
```swift
@Test("Reconnect with exponential backoff")
func testReconnectBackoff() async throws {
    let handler = GenericWebSocketHandler(...)

    // Simulate connection failure
    await handler.attemptConnection()

    // Verify backoff delays: 2s, 4s, 8s, 16s, 30s (capped)
    // Use TestScheduler or mock Task.sleep for timing
}

@Test("State sync after reconnect")
func testStateSyncRequest() async throws {
    let handler = GenericWebSocketHandler(...)

    await handler.connectWithRetry()
    await handler.requestStateSync()

    // Verify sync_request message sent
    // Verify job_progress received with latest state
}
```

**Manual Testing:**
1. Start large CSV import (100+ books)
2. Kill Worker process (simulate DO eviction)
3. Reconnect - verify progress resumes from correct point
4. Toggle airplane mode during enrichment
5. Verify auto-reconnect and state sync
6. Complete job - verify cleanup after 24h

#### Success Criteria
- [ ] Job state persisted to Durable Storage
- [ ] State survives DO evictions/restarts
- [ ] Throttling prevents excessive writes
- [ ] iOS auto-reconnects with exponential backoff
- [ ] State sync request returns latest progress
- [ ] Cleanup alarm removes old state after 24h
- [ ] Network transitions handled gracefully
- [ ] Tests pass (backend + iOS)

---

## Phase 1 Timeline

| Task | Effort | Dependencies | Start | End |
|------|--------|--------------|-------|-----|
| Token Auth (CSV/AI) | 6h | None | Day 1 | Day 1 |
| Unified Schema Design | 4h | None | Day 1 | Day 2 |
| Schema Backend Impl | 6h | Schema design | Day 2 | Day 2 |
| Schema iOS Impl | 6h | Schema design | Day 2 | Day 3 |
| DO State Persistence | 6h | None | Day 3 | Day 3 |
| Integration Testing | 8h | All above | Day 4 | Day 4 |
| **Total** | **36h** | | | **4 days** |

## Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Schema migration breaks existing clients | HIGH | LOW | Maintain backward compatibility, gradual rollout |
| DO state persistence degrades performance | MEDIUM | LOW | Throttle writes, monitor metrics |
| iOS auto-reconnect drains battery | MEDIUM | MEDIUM | Cap retries, exponential backoff |
| Token auth blocks legitimate users | HIGH | LOW | Clear error messages, retry logic |

## Success Metrics

- ✅ Zero 401 errors from authenticated clients
- ✅ <1% message parsing failures (iOS)
- ✅ 100% state recovery after DO restart
- ✅ <2% reconnect failures
- ✅ Zero warnings in iOS build
- ✅ All tests passing (backend + iOS)

## Next Steps After Phase 1

**Phase 2: Connection Resilience & UX**
- Implement heartbeat mechanism (ping/pong every 30s)
- Server-side message throttling
- Enhanced error messages with codes
- User-friendly status text

**Phase 3: Performance & Monitoring**
- Message batching for high-frequency updates
- Analytics Engine integration
- Performance dashboards
- A/B testing framework

---

**Prepared by:** Claude Code + Multi-Expert Consensus (Gemini 2.5 Pro, Grok-4)
**Review Required:** iOS Team, Backend Team
**Approval Required:** Yes (Security-critical changes)
