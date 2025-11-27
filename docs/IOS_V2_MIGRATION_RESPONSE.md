# iOS V2 Migration - Backend Response

**Date:** November 27, 2025
**Backend Version:** 3.0.0
**Status:** ✅ All V2 endpoints live and ready

---

## Summary of Changes

### ✅ Completed (Backend)
1. **Last-Event-ID Support:** SSE handler now supports reconnection with `Last-Event-ID` header
2. **V2 Results Endpoint:** `GET /api/v2/imports/{jobId}/results` now available
3. **API Contract Condensed:** Reduced from 3526 to 646 lines (82% reduction, current state only)
4. **OpenAPI Updated:** Version 3.0.0 with all V2 endpoints documented

---

## Critical Corrections for iOS Team

### 🚨 **1. CSV Upload Format - MISMATCH FOUND**

**Your Expectation (INCORRECT):**
```swift
// JSON payload
let body = [
  "csvContent": "Title,Author,ISBN\n...",
  "delimiter": ",",
  "hasHeader": true
]
```

**Backend Reality (CORRECT):**
```swift
// multipart/form-data with 'file' field
let formData = MultipartFormData()
formData.append(csvData, withName: "file", fileName: "import.csv", mimeType: "text/csv")
// POST to /api/v2/imports
```

**Action Required:** Keep using `multipart/form-data` in `GeminiCSVImportService.swift`. Do NOT switch to JSON payload.

---

### 🚨 **2. SSE Event Names - MISMATCH FOUND**

**Your Expectation (INCORRECT):**
```swift
case queued   // ❌ Backend does NOT send this
case started  // ❌ Backend sends "initialized" instead
```

**Backend Reality (CORRECT):**
```swift
// Event types the backend actually sends:
case initialized  // Job created (NOT "queued")
case processing   // Progress update (NOT "started")
case completed    // Job finished
case failed       // Job failed
case error        // Stream error
case timeout      // No progress for 5 minutes
```

**Action Required:** Update `SSEEvent` enum in iOS code to match backend event names.

---

### 🚨 **3. SSE Field Names - MISMATCH FOUND**

**Your Expectation (INCORRECT):**
```swift
struct ProgressData {
  let processedRows: Int    // ❌ Backend uses "processedCount"
  let totalRows: Int        // ❌ Backend uses "totalCount"
  let resultSummary: {...}  // ❌ NOT in SSE events
}
```

**Backend Reality (CORRECT):**
```swift
struct ProgressData {
  let processedCount: Int  // ✅ Correct field name
  let totalCount: Int      // ✅ Correct field name
  // No resultSummary in SSE - fetch from /api/v2/imports/{jobId}/results
}
```

**Action Required:**
1. Change field names to `processedCount` and `totalCount`
2. Remove `resultSummary` from SSE event models
3. Fetch full results from `/api/v2/imports/{jobId}/results` after receiving `completed` event

---

## ✅ Confirmed Correct

### 1. Endpoints
- ✅ `POST /api/v2/imports` - CSV upload (multipart/form-data)
- ✅ `GET /api/v2/imports/{jobId}/stream` - SSE progress
- ✅ `GET /api/v2/imports/{jobId}` - Job status (polling fallback)
- ✅ `GET /api/v2/imports/{jobId}/results` - **NEW** (completed Nov 27)

### 2. Authentication
- ✅ SSE streams require NO authentication (jobId is sufficient)
- ✅ Upload response still includes `authToken` for WebSocket fallback

### 3. Reconnection
- ✅ Last-Event-ID support **NOW LIVE** (completed Nov 27)
- ✅ Retry interval: 5000ms (5 seconds)
- ✅ Heartbeat: `: heartbeat` comment every 30 seconds

### 4. Rate Limiting
- ✅ Upload endpoint: 5 req/min per IP
- ✅ SSE stream: NO rate limiting (connection-based)
- ✅ HTTP 429 with `Retry-After` header on rate limit

### 5. Job Results Storage
- ✅ KV cache with 1-hour TTL after completion
- ✅ V2 endpoint available: `/api/v2/imports/{jobId}/results`

---

## Updated iOS Integration Guide

### Step 1: Upload CSV
```swift
// GeminiCSVImportService.swift
func uploadCSV(_ csvData: Data) async throws -> CSVImportResponse {
  var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/imports")!)
  request.httpMethod = "POST"

  let boundary = UUID().uuidString
  request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

  var body = Data()
  body.append("--\(boundary)\r\n".data(using: .utf8)!)
  body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.csv\"\r\n".data(using: .utf8)!)
  body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
  body.append(csvData)
  body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

  request.httpBody = body

  let (data, _) = try await URLSession.shared.data(for: request)
  let response = try JSONDecoder().decode(CSVImportResponse.self, from: data)
  return response
}

struct CSVImportResponse: Codable {
  let success: Bool
  let data: ImportData

  struct ImportData: Codable {
    let jobId: String
    let authToken: String  // For WebSocket fallback only
    let sseUrl: String
    let statusUrl: String
  }
}
```

### Step 2: Connect to SSE Stream
```swift
// SSEClient.swift
actor SSEClient {
  private let baseURL: String
  private var eventSource: URLSessionDataTask?
  private var lastEventId: String?

  func connect(jobId: String, onEvent: @escaping @MainActor (SSEEvent) -> Void) async {
    var request = URLRequest(url: URL(string: "\(baseURL)/api/v2/imports/\(jobId)/stream")!)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    // Resume from last event if reconnecting
    if let lastEventId = lastEventId {
      request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
    }

    // Stream SSE events
    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let data = data else { return }
      let text = String(data: data, encoding: .utf8) ?? ""

      // Parse SSE events
      self?.parseSSEEvents(text) { event in
        await onEvent(event)
      }
    }
    task.resume()
    self.eventSource = task
  }

  private func parseSSEEvents(_ text: String, onEvent: (SSEEvent) -> Void) {
    // Parse SSE format: "event: {type}\ndata: {json}\n\n"
    let lines = text.split(separator: "\n")
    var currentEvent: String?
    var currentData: String?
    var currentId: String?

    for line in lines {
      if line.hasPrefix("event:") {
        currentEvent = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
      } else if line.hasPrefix("data:") {
        currentData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
      } else if line.hasPrefix("id:") {
        currentId = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
      } else if line.isEmpty, let event = currentEvent, let data = currentData {
        // End of event
        if let id = currentId {
          self.lastEventId = id
        }
        onEvent(SSEEvent(type: event, data: data))
        currentEvent = nil
        currentData = nil
        currentId = nil
      }
    }
  }
}

enum SSEEvent {
  case initialized(InitializedData)
  case processing(ProgressData)
  case completed(CompletedData)
  case failed(FailedData)
  case error(ErrorData)
  case timeout(TimeoutData)

  struct InitializedData: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let processedCount: Int  // ✅ NOT "processedRows"
    let totalCount: Int      // ✅ NOT "totalRows"
  }

  struct ProgressData: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let processedCount: Int  // ✅ NOT "processedRows"
    let totalCount: Int      // ✅ NOT "totalRows"
  }

  struct CompletedData: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let processedCount: Int
    let totalCount: Int
    let completedAt: String?
    // NO resultSummary - fetch from /api/v2/imports/{jobId}/results
  }

  struct FailedData: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let error: String
  }

  struct ErrorData: Codable {
    let error: String
    let message: String
    let jobId: String?
  }

  struct TimeoutData: Codable {
    let error: String
    let message: String
    let jobId: String
    let lastStatus: String
    let lastProgress: Double
  }
}
```

### Step 3: Fetch Results After Completion
```swift
// GeminiCSVImportService.swift
func fetchResults(jobId: String) async throws -> ImportResults {
  let url = URL(string: "\(baseURL)/api/v2/imports/\(jobId)/results")!
  let (data, _) = try await URLSession.shared.data(from: url)
  let response = try JSONDecoder().decode(ResultsResponse.self, from: data)
  return response.data
}

struct ResultsResponse: Codable {
  let success: Bool
  let data: ImportResults

  struct ImportResults: Codable {
    let booksCreated: Int
    let booksUpdated: Int
    let duplicatesSkipped: Int
    let enrichmentSucceeded: Int
    let enrichmentFailed: Int
    let errors: [ImportError]

    struct ImportError: Codable {
      let row: Int
      let isbn: String
      let error: String
    }
  }
}
```

---

## Updated SSE Event Examples (From Backend)

### Event 1: Initialized
```
event: initialized
id: 1732713000123-initial
data: {"jobId":"abc123","status":"initialized","progress":0,"processedCount":0,"totalCount":100}

```

### Event 2-N: Processing
```
event: processing
id: 1732713002456-progress
data: {"jobId":"abc123","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

```

### Event N+1: Completed
```
event: completed
id: 1732713010789-final
data: {"jobId":"abc123","status":"completed","progress":1.0,"processedCount":100,"totalCount":100,"completedAt":"2025-11-27T10:30:10Z"}

```

### Error Event
```
event: error
data: {"error":"stream_error","message":"An error occurred while streaming progress","details":"..."}

```

### Timeout Event
```
event: timeout
data: {"error":"stream_timeout","message":"No progress for 5 minutes. Use polling endpoint to check status.","jobId":"abc123","lastStatus":"processing","lastProgress":0.75}

```

---

## Testing Checklist

- [ ] Update `SSEEvent` enum to use `initialized`, `processing`, `completed`, `failed`, `error`, `timeout`
- [ ] Change field names from `processedRows`/`totalRows` to `processedCount`/`totalCount`
- [ ] Remove `resultSummary` from SSE event models
- [ ] Add `fetchResults()` call after receiving `completed` event
- [ ] Keep `multipart/form-data` for CSV upload (do NOT use JSON)
- [ ] Test reconnection with `Last-Event-ID` header
- [ ] Test heartbeat handling (`: heartbeat` comments every 30s)
- [ ] Test network transition (WiFi → Cellular)
- [ ] Verify results fetching from `/api/v2/imports/{jobId}/results`

---

## Updated Architecture Flow

```
1. Upload CSV (multipart/form-data)
   POST /api/v2/imports
   → Response: { jobId, authToken, sseUrl, statusUrl }

2. Connect to SSE stream
   GET /api/v2/imports/{jobId}/stream
   Accept: text/event-stream
   Last-Event-ID: {lastEventId}  (if reconnecting)

3. Receive SSE events
   event: initialized → Job created
   event: processing → Progress updates (every 2s or on change)
   : heartbeat → Heartbeat comment (every 30s during idle)
   event: completed → Job finished

4. Fetch full results
   GET /api/v2/imports/{jobId}/results
   → Response: { booksCreated, booksUpdated, duplicatesSkipped, ... }
```

---

## API Contract Reference

**Full Documentation:** `/docs/API_CONTRACT.md` (v3.0, 646 lines)
**OpenAPI Spec:** `/docs/openapi.yaml` (v3.0)

**Key Sections:**
- Section 7.1: CSV Import
- Section 7.2: SSE Progress Stream
- Section 7.3: Job Status (Polling Fallback)
- Section 7.4: Job Results

---

## Backend Team Contact

- **API Issues:** https://github.com/yourusername/bookstrack/issues
- **Questions:** api-support@oooefam.net
- **Status Page:** https://status.oooefam.net

---

**Last Updated:** November 27, 2025
**Backend Version:** 3.0.0
**iOS Migration Status:** Ready for testing
