# iOS WebSocket Migration Guide: v1 → v2

**Audience:** iOS Development Team  
**Effective Date:** December 1, 2025  
**Migration Deadline:** November 28, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Breaking Changes Summary](#breaking-changes-summary)
3. [Migration Steps](#migration-steps)
4. [Code Examples (Before & After)](#code-examples-before--after)
5. [Message Type Reference](#message-type-reference)
6. [Migration Checklist](#migration-checklist)
7. [Testing Guide](#testing-guide)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The BooksTrack API is upgrading from WebSocket protocol v1 to v2 with **breaking changes** to the message format. This migration is part of the larger API v2.0 upgrade that improves type safety, analytics, and error handling.

### What's Changing

| Aspect | v1 (OLD) | v2 (NEW) |
|--------|----------|----------|
| **Message Schema** | Flat structure with `data` field | Envelope with `payload` field |
| **Pipeline Awareness** | ❌ Not supported | ✅ Pipeline-specific tracking |
| **Version Field** | ❌ No versioning | ✅ `version: "1.0.0"` |
| **Timestamp** | ❌ Optional | ✅ Always included |
| **Progress Details** | Basic progress number | Rich progress (booksProcessed, totalBooks) |
| **RPC Methods** | v1 RPC methods (deprecated) | Removed - event-driven only |

### Why This Matters

**v1 RPC methods have been removed:**
- ❌ `updateProgress(progress, status)` - REMOVED
- ❌ `complete(result)` - REMOVED  
- ❌ `fail(error)` - REMOVED

**v2 uses event-driven pattern:**
- ✅ Listen for `job_progress` messages
- ✅ Listen for `job_complete` messages
- ✅ Listen for `error` messages

---

## Breaking Changes Summary

### 1. Removed: RPC-Style Polling

**OLD v1 Pattern (DEPRECATED):**
```swift
// ❌ This pattern no longer works
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    webSocket.send("getJobStatus")  // Method removed
}
```

**NEW v2 Pattern (REQUIRED):**
```swift
// ✅ Event-driven - server pushes updates to client
webSocket.receive { result in
    if case .success(let message) = result {
        handleMessage(message)  // Process server push
    }
    webSocket.receive()  // Continue listening
}
```

### 2. New Message Format

**OLD v1 Message:**
```json
{
  "type": "progress",
  "jobId": "abc123",
  "data": {
    "progress": 0.5,
    "status": "Processing batch 5 of 10"
  }
}
```

**NEW v2 Message:**
```json
{
  "type": "job_progress",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_progress",
    "progress": 0.5,
    "status": "Processing batch 5 of 10",
    "booksProcessed": 50,
    "totalBooks": 100
  }
}
```

### 3. Pipeline-Aware Messages

All messages now include a `pipeline` field identifying the job type:

- `csv_import` - CSV file import
- `batch_enrichment` - Batch metadata enrichment
- `ai_scan` - AI-powered bookshelf scanning

This enables better analytics, debugging, and UI customization per pipeline.

---

## Migration Steps

### Step 1: Update Data Models

**Replace your v1 models with v2 models:**

```swift
// REMOVE OLD v1 MODELS ❌
struct ProgressMessageV1: Decodable {
    let type: String
    let jobId: String
    let data: ProgressData
}

struct ProgressData: Decodable {
    let progress: Double
    let status: String
}

// ADD NEW v2 MODELS ✅
struct WebSocketMessageV2: Decodable {
    let type: String
    let jobId: String
    let pipeline: String
    let timestamp: Int64
    let version: String
    let payload: MessagePayload
}

struct MessagePayload: Decodable {
    let type: String
    let progress: Double?
    let status: String?
    let booksProcessed: Int?
    let totalBooks: Int?
    let result: JobResult?
    let error: ErrorInfo?
}

struct JobResult: Decodable {
    let totalBooks: Int
    let successCount: Int
    let failureCount: Int
}

struct ErrorInfo: Decodable {
    let code: String
    let message: String
}
```

### Step 2: Remove RPC Polling Logic

**REMOVE polling timers and RPC calls:**

```swift
// ❌ DELETE THIS CODE
class WebSocketManager {
    var pollTimer: Timer?
    
    func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.requestStatus()
        }
    }
    
    func requestStatus() {
        let request = ["action": "getJobStatus", "jobId": jobId]
        webSocket.send(JSONEncoder().encode(request))
    }
}
```

### Step 3: Implement Event-Driven Message Handling

**ADD event-driven listener:**

```swift
// ✅ ADD THIS CODE
class WebSocketManager {
    var webSocket: URLSessionWebSocketTask?
    
    func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // IMPORTANT: Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket error: \(error)")
                self.handleConnectionError(error)
            }
        }
    }
    
    func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebSocketMessageV2.self, from: data) else {
            print("Failed to decode message")
            return
        }
        
        // Dispatch based on message type
        switch message.type {
        case "job_progress":
            handleProgress(message)
        case "job_complete":
            handleCompletion(message)
        case "error":
            handleError(message)
        default:
            print("Unknown message type: \(message.type)")
        }
    }
}
```

### Step 4: Update Message Handlers

**Replace v1 handlers with v2 handlers:**

```swift
// OLD v1 Handler ❌
func updateProgress(progress: Double, status: String) {
    DispatchQueue.main.async {
        self.progressBar.progress = Float(progress)
        self.statusLabel.text = status
    }
}

// NEW v2 Handler ✅
func handleProgress(_ message: WebSocketMessageV2) {
    guard let progress = message.payload.progress,
          let status = message.payload.status else {
        return
    }
    
    DispatchQueue.main.async {
        // Update progress bar
        self.progressBar.progress = Float(progress)
        
        // Update status with rich details
        if let processed = message.payload.booksProcessed,
           let total = message.payload.totalBooks {
            self.statusLabel.text = "\(status) (\(processed)/\(total))"
        } else {
            self.statusLabel.text = status
        }
        
        // Optional: Show pipeline-specific UI
        self.updatePipelineIndicator(message.pipeline)
    }
}

func handleCompletion(_ message: WebSocketMessageV2) {
    guard let result = message.payload.result else { return }
    
    DispatchQueue.main.async {
        self.showCompletionAlert(
            total: result.totalBooks,
            success: result.successCount,
            failed: result.failureCount
        )
        self.cleanup()
    }
}

func handleError(_ message: WebSocketMessageV2) {
    guard let error = message.payload.error else { return }
    
    DispatchQueue.main.async {
        self.showErrorAlert(
            code: error.code,
            message: error.message
        )
        self.cleanup()
    }
}
```

---

## Code Examples (Before & After)

### Complete iOS Migration Example

#### BEFORE (v1 - RPC Polling):

```swift
import Foundation

class WebSocketManagerV1 {
    var webSocket: URLSessionWebSocketTask?
    var jobId: String?
    var pollTimer: Timer?
    
    func connect(jobId: String, token: String) {
        let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)&token=\(token)")!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        
        self.jobId = jobId
        startPolling()
    }
    
    func startPolling() {
        // ❌ OLD PATTERN: Client polls server every second
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.requestJobStatus()
        }
    }
    
    func requestJobStatus() {
        let request = [
            "action": "getJobStatus",
            "jobId": jobId ?? ""
        ]
        
        guard let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocket?.send(.string(json)) { error in
            if let error = error {
                print("Send failed: \(error)")
            }
        }
        
        // Wait for response
        receiveMessage()
    }
    
    func receiveMessage() {
        webSocket?.receive { [weak self] result in
            if case .success(.string(let text)) = result {
                self?.handleV1Message(text)
            }
        }
    }
    
    func handleV1Message(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(ProgressMessageV1.self, from: data) else {
            return
        }
        
        // ❌ OLD: Simple progress update
        updateProgress(message.data.progress, status: message.data.status)
    }
    
    func updateProgress(_ progress: Double, status: String) {
        DispatchQueue.main.async {
            // Update UI
        }
    }
    
    func disconnect() {
        pollTimer?.invalidate()
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
}

struct ProgressMessageV1: Decodable {
    let type: String
    let jobId: String
    let data: ProgressData
}

struct ProgressData: Decodable {
    let progress: Double
    let status: String
}
```

#### AFTER (v2 - Event-Driven):

```swift
import Foundation

class WebSocketManagerV2 {
    var webSocket: URLSessionWebSocketTask?
    var jobId: String?
    
    // Callbacks for UI updates
    var onProgress: ((Double, String, Int?, Int?) -> Void)?
    var onComplete: ((JobResult) -> Void)?
    var onError: ((String, String) -> Void)?
    
    func connect(jobId: String, token: String) {
        let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)&token=\(token)")!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        
        self.jobId = jobId
        
        // ✅ NEW PATTERN: Server pushes updates to client
        receiveMessage()
    }
    
    func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleV2Message(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleV2Message(text)
                    }
                @unknown default:
                    break
                }
                
                // IMPORTANT: Continue listening for more messages
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket error: \(error)")
                self.onError?("CONNECTION_ERROR", error.localizedDescription)
            }
        }
    }
    
    func handleV2Message(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebSocketMessageV2.self, from: data) else {
            print("Failed to decode v2 message")
            return
        }
        
        // ✅ NEW: Dispatch based on message type
        switch message.type {
        case "job_progress":
            handleProgress(message)
        case "job_complete":
            handleCompletion(message)
        case "error":
            handleError(message)
        default:
            print("Unknown message type: \(message.type)")
        }
    }
    
    func handleProgress(_ message: WebSocketMessageV2) {
        guard let progress = message.payload.progress,
              let status = message.payload.status else {
            return
        }
        
        // ✅ NEW: Rich progress information
        onProgress?(
            progress,
            status,
            message.payload.booksProcessed,
            message.payload.totalBooks
        )
    }
    
    func handleCompletion(_ message: WebSocketMessageV2) {
        guard let result = message.payload.result else { return }
        
        onComplete?(result)
        disconnect()
    }
    
    func handleError(_ message: WebSocketMessageV2) {
        guard let error = message.payload.error else { return }
        
        onError?(error.code, error.message)
        disconnect()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }
}

// ✅ NEW v2 Data Models
struct WebSocketMessageV2: Decodable {
    let type: String
    let jobId: String
    let pipeline: String
    let timestamp: Int64
    let version: String
    let payload: MessagePayload
}

struct MessagePayload: Decodable {
    let type: String
    let progress: Double?
    let status: String?
    let booksProcessed: Int?
    let totalBooks: Int?
    let result: JobResult?
    let error: ErrorInfo?
}

struct JobResult: Decodable {
    let totalBooks: Int
    let successCount: Int
    let failureCount: Int
}

struct ErrorInfo: Decodable {
    let code: String
    let message: String
}
```

### Usage in View Controller

```swift
class ImportViewController: UIViewController {
    let wsManager = WebSocketManagerV2()
    
    func startImport(jobId: String, token: String) {
        // Setup callbacks
        wsManager.onProgress = { [weak self] progress, status, processed, total in
            DispatchQueue.main.async {
                self?.progressBar.progress = Float(progress)
                
                if let processed = processed, let total = total {
                    self?.statusLabel.text = "\(status) (\(processed)/\(total) books)"
                } else {
                    self?.statusLabel.text = status
                }
            }
        }
        
        wsManager.onComplete = { [weak self] result in
            DispatchQueue.main.async {
                self?.showSuccessAlert(
                    total: result.totalBooks,
                    success: result.successCount,
                    failed: result.failureCount
                )
            }
        }
        
        wsManager.onError = { [weak self] code, message in
            DispatchQueue.main.async {
                self?.showErrorAlert(title: code, message: message)
            }
        }
        
        // Connect and start receiving
        wsManager.connect(jobId: jobId, token: token)
    }
}
```

---

## Message Type Reference

### 1. job_progress

**Purpose:** Progress updates during batch processing

**Structure:**
```json
{
  "type": "job_progress",
  "jobId": "abc123",
  "pipeline": "csv_import" | "batch_enrichment" | "ai_scan",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_progress",
    "progress": 0.5,
    "status": "Processing batch 5 of 10",
    "booksProcessed": 50,
    "totalBooks": 100
  }
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | String | ✅ | Always `"job_progress"` |
| `jobId` | String | ✅ | Unique job identifier |
| `pipeline` | String | ✅ | Pipeline type (csv_import, batch_enrichment, ai_scan) |
| `timestamp` | Int64 | ✅ | Unix timestamp (milliseconds) |
| `version` | String | ✅ | Protocol version (`"1.0.0"`) |
| `payload.progress` | Double | ✅ | Progress 0.0 to 1.0 |
| `payload.status` | String | ✅ | Human-readable status message |
| `payload.booksProcessed` | Int | ⚠️ | Books processed so far (optional) |
| `payload.totalBooks` | Int | ⚠️ | Total books to process (optional) |

### 2. job_complete

**Purpose:** Job completed successfully

**Structure:**
```json
{
  "type": "job_complete",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_complete",
    "result": {
      "totalBooks": 100,
      "successCount": 98,
      "failureCount": 2
    }
  }
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | String | ✅ | Always `"job_complete"` |
| `payload.result.totalBooks` | Int | ✅ | Total books processed |
| `payload.result.successCount` | Int | ✅ | Books processed successfully |
| `payload.result.failureCount` | Int | ✅ | Books that failed processing |

### 3. error

**Purpose:** Error occurred during processing

**Structure:**
```json
{
  "type": "error",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "error",
    "error": {
      "code": "PROCESSING_FAILED",
      "message": "Failed to process CSV file: Invalid format"
    }
  }
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | String | ✅ | Always `"error"` |
| `payload.error.code` | String | ✅ | Error code (see Error Codes table) |
| `payload.error.message` | String | ✅ | Human-readable error message |

### Error Codes

| Code | Description | Action |
|------|-------------|--------|
| `CONNECTION_FAILED` | WebSocket connection failed | Retry connection |
| `INVALID_TOKEN` | Authentication token invalid | Re-authenticate |
| `TOKEN_EXPIRED` | Authentication token expired | Refresh token via `/api/token/refresh` |
| `JOB_NOT_FOUND` | Job ID does not exist | Check jobId validity |
| `PROCESSING_FAILED` | Job processing failed | Show error to user, allow retry |
| `CSV_PARSE_ERROR` | CSV file format invalid | Show validation error |
| `AI_SCAN_ERROR` | AI scan failed | Retry or use manual entry |

---

## Migration Checklist

### Code Changes
- [ ] Remove v1 data models (`ProgressMessageV1`, `ProgressData`)
- [ ] Add v2 data models (`WebSocketMessageV2`, `MessagePayload`, etc.)
- [ ] Remove RPC polling logic (`Timer`, `getJobStatus` calls)
- [ ] Implement event-driven `receiveMessage()` loop
- [ ] Update progress handler to use v2 payload structure
- [ ] Add completion handler for `job_complete` messages
- [ ] Add error handler for `error` messages
- [ ] Handle optional fields (`booksProcessed`, `totalBooks`)
- [ ] Update UI to show pipeline-specific information (optional)

### Testing
- [ ] Test against staging: `wss://staging-api.oooefam.net`
- [ ] Verify connection with valid jobId + token
- [ ] Confirm `job_progress` messages received
- [ ] Confirm `job_complete` message at end
- [ ] Confirm error messages handled correctly
- [ ] Test token expiration and refresh flow
- [ ] Test network interruption recovery
- [ ] Test with large datasets (1000+ books)

### Deployment
- [ ] Update app to use v2 protocol
- [ ] Test in staging environment
- [ ] Submit to TestFlight for beta testing
- [ ] Monitor crash reports for WebSocket issues
- [ ] Deploy to production **before November 28, 2025**

---

## Testing Guide

### Test in Staging Environment

**Staging WebSocket URL:**
```
wss://staging-api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**Steps:**

1. **Update Configuration:**
```swift
#if STAGING
let wsBaseURL = "wss://staging-api.oooefam.net"
#else
let wsBaseURL = "wss://api.oooefam.net"
#endif
```

2. **Start a Test Job:**
```swift
// Trigger CSV import or batch enrichment
let jobId = startImportJob()  // Returns jobId and token
let token = getAuthToken()

wsManager.connect(jobId: jobId, token: token)
```

3. **Verify Messages:**
- Check console logs for incoming messages
- Verify message structure matches v2 schema
- Confirm progress updates UI correctly

### Manual Testing with wscat

```bash
# Install wscat
npm install -g wscat

# Connect to staging
wscat -c "wss://staging-api.oooefam.net/ws/progress?jobId=test-123&token=test-token"

# You'll receive v2 messages
```

### Unit Testing

```swift
import XCTest

class WebSocketV2Tests: XCTestCase {
    func testProgressMessageDecoding() {
        let json = """
        {
          "type": "job_progress",
          "jobId": "test-123",
          "pipeline": "csv_import",
          "timestamp": 1700000000000,
          "version": "1.0.0",
          "payload": {
            "type": "job_progress",
            "progress": 0.5,
            "status": "Processing...",
            "booksProcessed": 50,
            "totalBooks": 100
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try! JSONDecoder().decode(WebSocketMessageV2.self, from: data)
        
        XCTAssertEqual(message.type, "job_progress")
        XCTAssertEqual(message.pipeline, "csv_import")
        XCTAssertEqual(message.payload.progress, 0.5)
        XCTAssertEqual(message.payload.booksProcessed, 50)
    }
    
    func testCompleteMessageDecoding() {
        let json = """
        {
          "type": "job_complete",
          "jobId": "test-123",
          "pipeline": "csv_import",
          "timestamp": 1700000000000,
          "version": "1.0.0",
          "payload": {
            "type": "job_complete",
            "result": {
              "totalBooks": 100,
              "successCount": 98,
              "failureCount": 2
            }
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try! JSONDecoder().decode(WebSocketMessageV2.self, from: data)
        
        XCTAssertEqual(message.type, "job_complete")
        XCTAssertEqual(message.payload.result?.totalBooks, 100)
        XCTAssertEqual(message.payload.result?.successCount, 98)
    }
}
```

---

## Troubleshooting

### Issue: Messages not received

**Symptom:** WebSocket connects but no messages arrive

**Diagnosis:**
```swift
webSocket?.receive { result in
    print("Receive result: \(result)")
    // Check if this is being called
}
```

**Solution:**
- Ensure you call `receiveMessage()` after connection
- Ensure you call `receiveMessage()` again after each message
- Check jobId and token are valid

### Issue: JSON decode fails

**Symptom:** `JSONDecoder` throws error

**Diagnosis:**
```swift
do {
    let message = try JSONDecoder().decode(WebSocketMessageV2.self, from: data)
} catch {
    print("Decode error: \(error)")
    print("Raw message: \(text)")
}
```

**Solution:**
- Verify message structure matches v2 schema
- Check for typos in struct property names
- Ensure all required fields are present
- Handle optional fields with `?`

### Issue: Token expired

**Symptom:** 401 error on WebSocket connection

**Solution:**
```swift
// Refresh token before connecting
func refreshToken(jobId: String, oldToken: String, completion: @escaping (String?) -> Void) {
    let url = URL(string: "https://api.oooefam.net/api/token/refresh")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body = ["jobId": jobId, "oldToken": oldToken]
    request.httpBody = try? JSONEncoder().encode(body)
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data,
              let json = try? JSONDecoder().decode([String: String].self, from: data),
              let newToken = json["token"] else {
            completion(nil)
            return
        }
        
        completion(newToken)
    }.resume()
}
```

### Issue: Connection drops frequently

**Symptom:** WebSocket disconnects unexpectedly

**Solution:**
- Implement automatic reconnection
- Add ping/pong keep-alive (server handles this)
- Check network stability

```swift
func connectWithRetry(jobId: String, token: String, retries: Int = 3) {
    connect(jobId: jobId, token: token)
    
    webSocket?.receive { [weak self] result in
        if case .failure = result, retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.connectWithRetry(jobId: jobId, token: token, retries: retries - 1)
            }
        }
    }
}
```

---

## Support

### Resources

- **Staging Testing Guide:** `/docs/STAGING_TESTING_GUIDE.md`
- **API Migration Notice:** `/docs/API_V2_MIGRATION_NOTICE.md`
- **Server Implementation:** `/src/durable-objects/progress-socket.js`

### Contact

- **Slack:** `#bookstrack-api-support`
- **Email:** api-support@oooefam.net
- **GitHub Issues:** https://github.com/jukasdrj/bookstrack-backend/issues
- **Emergency:** engineering-oncall@oooefam.net

---

**Document Version:** 1.0  
**Last Updated:** November 15, 2025  
**Maintainer:** BooksTrack Backend Team
