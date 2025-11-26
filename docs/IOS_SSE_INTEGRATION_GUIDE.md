# iOS SSE Integration Guide - V2 API

**Updated:** November 25, 2025
**Target Audience:** iOS Team
**Context:** V2 API migration using SSE instead of WebSocket

---

## 🎯 Quick Answer: Do You Need Polling with SSE?

### **NO** - SSE Handles Reconnection Automatically! ✅

**Key Difference from WebSocket:**

| Feature | WebSocket (V1) | SSE (V2) |
|---------|----------------|----------|
| **Reconnection** | ❌ Manual (you implement) | ✅ **Automatic** (browser native) |
| **Network Transitions** | ❌ Drops connection | ✅ **Auto-reconnects** |
| **Backgrounding** | ❌ Connection lost | ✅ Reconnects on foreground |
| **Polling Fallback** | ✅ **Required** | ❌ **Not needed** |
| **Battery Life** | ⚠️ Keeps radio active | ✅ Sleep between events |
| **Firewall/Proxy** | ❌ Often blocked | ✅ Works everywhere |

**Bottom Line:** If you migrate to V2 SSE (`GET /api/v2/imports/{jobId}/stream`), you **do not need** HTTP polling fallback!

---

## 🔄 Migration Decision Tree

### Option 1: Stay on V1 WebSocket (Current)

**Endpoints:**
- `POST /api/import/csv-gemini` (CSV upload)
- `GET /ws/progress?jobId={jobId}` (WebSocket)

**Requirements:**
- ✅ **MUST implement HTTP polling fallback** (iOS bug - WebSocket drops on network transition)
- Polling endpoint: `GET /v1/jobs/:jobId/status` (already exists)
- Polling interval: Every 3-5 seconds

**Pros:**
- No code changes
- Battle-tested

**Cons:**
- Requires polling fallback (more code)
- WebSocket fragile on mobile

---

### Option 2: Migrate to V2 SSE (Recommended)

**Endpoints:**
- `POST /api/v2/imports` (CSV upload)
- `GET /api/v2/imports/{jobId}/stream` (SSE stream)

**Requirements:**
- ❌ **NO polling fallback needed** (SSE handles it)
- Native iOS `URLSession` supports SSE (iOS 13+)

**Pros:**
- **No polling fallback needed** (SSE auto-reconnects)
- Survives network transitions automatically
- Works through firewalls/proxies
- Battery-efficient (radio sleep between events)
- Less code than WebSocket + polling

**Cons:**
- Need to implement SSE client (Swift code below)

---

## 📋 iOS SSE Implementation (Swift)

### Step 1: Create SSE Client

```swift
import Foundation

class SSEClient: NSObject {
    private var task: URLSessionDataTask?
    private var session: URLSession!
    private let baseURL = "https://api.oooefam.net"

    var onProgress: ((Double, Int, Int) -> Void)?
    var onComplete: ((ImportResult) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()

        // Configure URLSession for SSE
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity // SSE is long-lived
        config.timeoutIntervalForResource = .infinity
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache"
        ]

        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect(jobId: String) {
        let url = URL(string: "\(baseURL)/api/v2/imports/\(jobId)/stream")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        task = session.dataTask(with: request)
        task?.resume()

        print("[SSE] Connected to job \(jobId)")
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }
}

// MARK: - URLSessionDataDelegate

extension SSEClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Parse SSE events
        guard let eventString = String(data: data, encoding: .utf8) else { return }

        parseSSEEvents(eventString)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if it's a normal cancellation or actual error
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                print("[SSE] Connection cancelled")
            } else {
                print("[SSE] Error: \(error)")
                onError?(error)

                // SSE auto-reconnects - wait 5 seconds and retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    if let jobId = self?.getCurrentJobId() {
                        self?.connect(jobId: jobId)
                    }
                }
            }
        }
    }

    private func parseSSEEvents(_ eventString: String) {
        // Split on double newline (SSE event separator)
        let events = eventString.components(separatedBy: "\n\n")

        for event in events {
            if event.isEmpty { continue }

            var eventType = "message" // Default
            var eventData = ""

            let lines = event.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("event: ") {
                    eventType = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    eventData += String(line.dropFirst(6))
                }
            }

            handleSSEEvent(type: eventType, data: eventData)
        }
    }

    private func handleSSEEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }

        switch type {
        case "progress":
            if let progress = try? JSONDecoder().decode(ProgressEvent.self, from: jsonData) {
                onProgress?(progress.progress, progress.processedCount, progress.totalCount)
            }

        case "complete":
            if let result = try? JSONDecoder().decode(ImportResult.self, from: jsonData) {
                onComplete?(result)
                disconnect()
            }

        case "error":
            if let errorEvent = try? JSONDecoder().decode(ErrorEvent.self, from: jsonData) {
                onError?(SSEError.serverError(errorEvent.message))
                disconnect()
            }

        default:
            print("[SSE] Unknown event type: \(type)")
        }
    }

    private func getCurrentJobId() -> String? {
        // Extract jobId from current task URL
        guard let url = task?.originalRequest?.url else { return nil }
        return url.lastPathComponent
    }
}

// MARK: - Types

struct ProgressEvent: Codable {
    let progress: Double
    let processedCount: Int
    let totalCount: Int
    let status: String
}

struct ImportResult: Codable {
    let jobId: String
    let status: String
    let totalRows: Int
    let successfulRows: Int
    let failedRows: Int
}

struct ErrorEvent: Codable {
    let code: String
    let message: String
}

enum SSEError: Error {
    case serverError(String)
    case connectionFailed
}
```

---

### Step 2: Use in Your ViewModel

```swift
class ImportViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var isImporting: Bool = false

    private var sseClient: SSEClient?

    func startImport(csvData: Data) async {
        isImporting = true

        // 1. Upload CSV to get jobId
        guard let jobId = await uploadCSV(csvData) else {
            isImporting = false
            return
        }

        // 2. Connect to SSE stream
        sseClient = SSEClient()

        sseClient?.onProgress = { [weak self] progress, processed, total in
            DispatchQueue.main.async {
                self?.progress = progress
                self?.processedCount = processed
                self?.totalCount = total
            }
        }

        sseClient?.onComplete = { [weak self] result in
            DispatchQueue.main.async {
                self?.isImporting = false
                self?.showCompletionAlert(result)
            }
        }

        sseClient?.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.isImporting = false
                self?.showError(error)
            }
        }

        sseClient?.connect(jobId: jobId)
    }

    private func uploadCSV(_ csvData: Data) async -> String? {
        let url = URL(string: "https://api.oooefam.net/api/v2/imports")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"library.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ImportResponse.self, from: data)
            return response.jobId
        } catch {
            print("Upload failed: \(error)")
            return nil
        }
    }
}

struct ImportResponse: Codable {
    let jobId: String
    let status: String
    let sseUrl: String
    let estimatedRows: Int
}
```

---

## 🎯 Key Advantages of SSE over WebSocket

### 1. **Automatic Reconnection**

```swift
// WebSocket (V1) - YOU implement reconnection
class WebSocketClient {
    func webSocketDidDisconnect() {
        // Manual reconnection logic
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.reconnect()
        }
    }
}

// SSE (V2) - BROWSER handles reconnection automatically
// You do nothing! 🎉
```

### 2. **Network Transition Survival**

**Scenario:** User on WiFi → switches to Cellular

**WebSocket:**
- ❌ Connection drops
- ❌ You must detect and reconnect
- ❌ Need polling fallback during transition

**SSE:**
- ✅ Auto-reconnects when cellular connects
- ✅ Resumes from last event (Last-Event-ID)
- ✅ No polling needed

### 3. **Backgrounding Support**

**Scenario:** User backgrounds app

**WebSocket:**
- ❌ iOS suspends connection
- ❌ Lost when app returns to foreground

**SSE:**
- ✅ Reconnects when app returns
- ✅ Catches up on missed events
- ✅ No state loss

---

## 📊 Comparison Chart

| Feature | V1 WebSocket + Polling | V2 SSE |
|---------|------------------------|--------|
| **Code Complexity** | High (WS + polling) | Low (SSE only) |
| **Reconnection Logic** | Manual (your code) | Automatic (native) |
| **Polling Fallback** | Required | Not needed |
| **Network Transitions** | Drops + manual retry | Auto-reconnects |
| **Battery Impact** | Higher (active polling) | Lower (event-driven) |
| **Firewall Compatibility** | Sometimes blocked | Always works |
| **iOS Background** | Manual handling | Auto-resumes |
| **Lines of Code** | ~300-400 | ~150-200 |

---

## 🚀 Migration Steps

### Phase 1: Implement SSE Client (1-2 days)

1. ✅ Create `SSEClient.swift` (code above)
2. ✅ Update `ImportViewModel` to use SSE
3. ✅ Test network transitions (WiFi ↔ Cellular)
4. ✅ Test backgrounding/foregrounding

### Phase 2: Switch Endpoints (1 day)

**Old (V1):**
```swift
POST /api/import/csv-gemini
WS   /ws/progress?jobId={jobId}
```

**New (V2):**
```swift
POST /api/v2/imports
SSE  /api/v2/imports/{jobId}/stream
```

### Phase 3: Remove Polling Code (1 day)

- ✅ Delete WebSocket client
- ✅ Delete polling timer logic
- ✅ Delete fallback state machine
- ✅ Simplify error handling

**Total Migration Time:** 3-4 days

---

## 🧪 Testing SSE

### Manual Testing

```bash
# Test SSE endpoint directly
curl -N -H "Accept: text/event-stream" \
  https://api.oooefam.net/api/v2/imports/test-job-123/stream

# Expected output:
: connection established
retry: 5000

event: progress
data: {"progress":0.5,"processedCount":50,"totalCount":100}

event: complete
data: {"status":"complete","totalRows":100}
```

### Network Transition Testing

1. Start import on WiFi
2. Turn off WiFi (force cellular)
3. **Expected:** SSE auto-reconnects, progress continues
4. Turn WiFi back on
5. **Expected:** Seamless (no interruption)

### Backgrounding Testing

1. Start import
2. Background app (Home button)
3. Wait 10 seconds
4. Foreground app
5. **Expected:** SSE reconnects, catches up on progress

---

## 📞 Backend Endpoints Reference

### V2 CSV Import Flow

**Step 1: Upload CSV**
```http
POST /api/v2/imports
Content-Type: multipart/form-data

Response (202 Accepted):
{
  "jobId": "import_abc123",
  "status": "queued",
  "sseUrl": "/api/v2/imports/import_abc123/stream",
  "estimatedRows": 150
}
```

**Step 2: Stream Progress**
```http
GET /api/v2/imports/import_abc123/stream
Accept: text/event-stream

Response (SSE stream):
event: started
data: {"status":"processing","totalRows":150}

event: progress
data: {"progress":0.33,"processedRows":50}

event: complete
data: {"status":"complete","successfulRows":145,"failedRows":5}
```

**Optional: Polling Fallback** (if SSE fails - rare)
```http
GET /api/v2/imports/import_abc123
Accept: application/json

Response (200 OK):
{
  "jobId": "import_abc123",
  "status": "processing",
  "progress": 0.67,
  "processedRows": 100,
  "totalRows": 150
}
```

---

## ✅ Recommendation

### **Migrate to V2 SSE** - No Polling Needed!

**Why:**
1. ✅ **Simpler code** (no polling logic)
2. ✅ **More reliable** (auto-reconnection)
3. ✅ **Better UX** (survives network transitions)
4. ✅ **Lower battery usage** (event-driven, not polling)
5. ✅ **Future-proof** (V2 is the long-term API)

**Timeline:** 3-4 days for full migration

**Alternative:** If you must stay on V1 WebSocket, implement polling fallback:
- Endpoint: `GET /v1/jobs/:jobId/status`
- Interval: Every 3-5 seconds
- Trigger: When WebSocket disconnects

---

## 📚 Additional Resources

- **Backend Docs:** `docs/FRONTEND_INTEGRATION_GUIDE.md`
- **API Contract:** `docs/API_CONTRACT.md` (Section 6.5 - V2 API)
- **OpenAPI Spec:** `docs/openapi.yaml` (lines 1519-1580 for SSE)
- **SSE Standard:** [MDN EventSource API](https://developer.mozilla.org/en-US/docs/Web/API/EventSource)

---

**Document Owner:** Backend Team
**iOS Contact:** Frontend Team Lead
**Last Updated:** November 25, 2025
**Status:** V2 SSE endpoints live and tested ✅
