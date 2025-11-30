# TODO: books-v3 - iOS CSV Import SSE Client Fixes

**Sprint Goal:** Fix iOS SSE client to properly receive real-time CSV import progress  
**Owner:** Justin (User)  
**Time Estimate:** 2-3 hours  
**Status:** 🔴 Not Started  
**Priority:** P0 - BLOCKING cache validation

---

## 🎯 Objective

Fix the iOS EventSource (SSE) client implementation to:
1. Connect to bendv3 SSE endpoint properly
2. Handle reconnection with Last-Event-ID
3. Process progress events in real-time
4. Update UI without blocking main thread
5. Handle completion/error states gracefully

**Success Metric:** CSV import progress bar updates in < 1 second

---

## 📋 Current State

### What's Working
- ✅ CSV file picker and upload
- ✅ Initial import request (POST /api/import/csv-gemini)
- ✅ Job ID and auth token received

### What's Broken
- ❌ SSE connection not receiving events
- ❌ Progress bar stuck at 0%
- ❌ No real-time updates
- ❌ Timeout after 5 minutes
- **Root Cause:** SSE client implementation needs fixes

---

## 🚀 Implementation Tasks

### Task 1: Locate SSE Client Implementation (10 minutes)

**Goal:** Find the iOS code handling CSV import SSE connection

**Files to Check:**
- `BooksTrackerPackage/Sources/*/Services/*ImportService.swift`
- `BooksTrackerPackage/Sources/*/ViewModels/*ImportViewModel.swift`
- `BooksTrackerPackage/Sources/*/Views/*ImportView.swift`
- `BooksTrackerPackage/Sources/*/Network/*APIClient.swift`

**Search Commands:**
```bash
cd /Users/juju/dev_repos/books-v3

# Find SSE/EventSource references
grep -r "EventSource" BooksTrackerPackage/
grep -r "text/event-stream" BooksTrackerPackage/
grep -r "csv.*import" BooksTrackerPackage/
grep -r "SSE\|sse" BooksTrackerPackage/

# Find import-related files
find BooksTrackerPackage -name "*Import*" -type f
```

**Acceptance Criteria:**
- [ ] Found file containing SSE client code
- [ ] Found file containing CSV import view model
- [ ] Identified current SSE implementation approach
- [ ] Documented file paths for next tasks

---

### Task 2: Implement Proper SSE Client (60 minutes)

**Goal:** Create robust SSE client following Swift best practices

**File:** Create `/Users/juju/dev_repos/books-v3/BooksTrackerPackage/Sources/[Module]/Network/SSEClient.swift`

**Implementation:**

```swift
import Foundation

/// Server-Sent Events (SSE) client for real-time progress updates
/// Handles connection, reconnection, and event parsing per SSE spec
actor SSEClient {
    
    // MARK: - Types
    
    struct Event {
        let id: String?
        let event: String?
        let data: String
        let retry: Int?
    }
    
    typealias EventHandler = (Event) -> Void
    
    // MARK: - Properties
    
    private let url: URL
    private var task: URLSessionDataTask?
    private var lastEventId: String?
    private let eventHandler: EventHandler
    
    private var buffer = ""
    
    // MARK: - Initialization
    
    init(url: URL, eventHandler: @escaping EventHandler) {
        self.url = url
        self.eventHandler = eventHandler
    }
    
    // MARK: - Connection Management
    
    func connect() {
        // Cancel existing connection
        task?.cancel()
        
        // Create request with SSE headers
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.timeoutInterval = 300 // 5 minutes
        
        // Add Last-Event-ID for reconnection
        if let lastEventId = lastEventId {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }
        
        // Create streaming task
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task {
                await self?.handleResponse(data: data, response: response, error: error)
            }
        }
        
        task?.resume()
        print("[SSEClient] Connected to \(url)")
    }
    
    func disconnect() {
        task?.cancel()
        task = nil
        buffer = ""
        print("[SSEClient] Disconnected")
    }
    
    // MARK: - Response Handling
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            print("[SSEClient] Error: \(error)")
            // Don't auto-reconnect on error - let caller decide
            return
        }
        
        guard let data = data,
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        
        // Append to buffer and process
        buffer += text
        processBuffer()
    }
    
    // MARK: - Event Parsing
    
    private func processBuffer() {
        // SSE events are separated by double newlines
        let events = buffer.components(separatedBy: "\n\n")
        
        // Keep last incomplete event in buffer
        buffer = events.last ?? ""
        
        // Process complete events
        for eventText in events.dropLast() where !eventText.isEmpty {
            if let event = parseEvent(eventText) {
                eventHandler(event)
                
                // Update last event ID for reconnection
                if let id = event.id {
                    lastEventId = id
                }
            }
        }
    }
    
    private func parseEvent(_ text: String) -> Event? {
        var id: String?
        var eventType: String?
        var data: [String] = []
        var retry: Int?
        
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(":") {
                // Comment line - ignore
                continue
            }
            
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            
            let field = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            switch field {
            case "id":
                id = value
            case "event":
                eventType = value
            case "data":
                data.append(value)
            case "retry":
                retry = Int(value)
            default:
                break
            }
        }
        
        // Data field is required
        guard !data.isEmpty else { return nil }
        
        return Event(
            id: id,
            event: eventType,
            data: data.joined(separator: "\n"),
            retry: retry
        )
    }
}

// MARK: - URLSessionDataDelegate for Streaming

/// Custom URLSession delegate for handling streaming responses
class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    
    let onData: (Data) -> Void
    
    init(onData: @escaping (Data) -> Void) {
        self.onData = onData
    }
    
    func urlSession(_ session: URLSession, 
                   dataTask: URLSessionDataTask, 
                   didReceive data: Data) {
        onData(data)
    }
}
```

**Acceptance Criteria:**
- [ ] SSEClient.swift file created
- [ ] Proper SSE event parsing (id, event, data, retry)
- [ ] Buffer handling for incomplete events
- [ ] Last-Event-ID support for reconnection
- [ ] Comment line handling (lines starting with :)
- [ ] Actor isolation for thread safety
- [ ] Compiles without errors

---

### Task 3: Integrate SSE Client into Import Flow (45 minutes)

**Goal:** Use SSEClient in CSV import view model

**File:** Find and update import view model (likely `*ImportViewModel.swift`)

**Implementation:**

```swift
import Foundation
import Combine

@MainActor
class CSVImportViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isImporting = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var error: Error?
    @Published var isComplete = false
    
    // MARK: - Private Properties
    
    private var sseClient: SSEClient?
    private var jobId: String?
    
    // MARK: - Import Methods
    
    func importCSV(fileURL: URL) async {
        isImporting = true
        progress = 0.0
        statusMessage = "Uploading CSV..."
        error = nil
        isComplete = false
        
        do {
            // Step 1: Upload CSV and get job ID
            let response = try await uploadCSV(fileURL: fileURL)
            jobId = response.jobId
            
            statusMessage = "Processing books..."
            
            // Step 2: Connect to SSE stream
            guard let sseURL = URL(string: "https://api.oooefam.net\(response.sseUrl)") else {
                throw ImportError.invalidURL
            }
            
            // Create SSE client with event handler
            sseClient = SSEClient(url: sseURL) { [weak self] event in
                Task { @MainActor in
                    await self?.handleSSEEvent(event)
                }
            }
            
            await sseClient?.connect()
            
        } catch {
            self.error = error
            self.isImporting = false
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func handleSSEEvent(_ event: SSEClient.Event) async {
        // Parse event data as JSON
        guard let data = event.data.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            
            switch event.event {
            case "progress":
                let update = try decoder.decode(ProgressUpdate.self, from: data)
                progress = Double(update.progress) / 100.0
                statusMessage = "Processing: \(update.processedCount)/\(update.totalCount) books"
                
            case "completed":
                let completion = try decoder.decode(CompletionUpdate.self, from: data)
                progress = 1.0
                statusMessage = "Import complete! Processed \(completion.processedCount) books"
                isComplete = true
                isImporting = false
                
                // Disconnect SSE
                await sseClient?.disconnect()
                
            case "failed":
                let failure = try decoder.decode(FailureUpdate.self, from: data)
                error = ImportError.serverError(failure.error.message)
                statusMessage = "Import failed: \(failure.error.message)"
                isImporting = false
                
                // Disconnect SSE
                await sseClient?.disconnect()
                
            case "error":
                let errorData = try decoder.decode(ErrorUpdate.self, from: data)
                error = ImportError.serverError(errorData.message)
                statusMessage = "Error: \(errorData.message)"
                
            default:
                // Unknown event type - log but continue
                print("[Import] Unknown SSE event: \(event.event ?? "nil")")
            }
            
        } catch {
            print("[Import] Failed to parse SSE event: \(error)")
        }
    }
    
    private func uploadCSV(fileURL: URL) async throws -> ImportResponse {
        // Create multipart form data request
        var request = URLRequest(url: URL(string: "https://api.oooefam.net/api/import/csv-gemini")!)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Read CSV data
        let csvData = try Data(contentsOf: fileURL)
        
        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"library.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw ImportError.uploadFailed
        }
        
        return try JSONDecoder().decode(ImportResponse.self, from: data)
    }
    
    func cancelImport() {
        Task {
            await sseClient?.disconnect()
            isImporting = false
            statusMessage = "Import cancelled"
        }
    }
}

// MARK: - Response Types

struct ImportResponse: Codable {
    let jobId: String
    let authToken: String
    let sseUrl: String
    let statusUrl: String
}

struct ProgressUpdate: Codable {
    let jobId: String
    let status: String
    let progress: Int
    let processedCount: Int
    let totalCount: Int
}

struct CompletionUpdate: Codable {
    let jobId: String
    let status: String
    let progress: Int
    let processedCount: Int
    let totalCount: Int
    let completedAt: String
}

struct FailureUpdate: Codable {
    let jobId: String
    let status: String
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let code: String
        let message: String
    }
}

struct ErrorUpdate: Codable {
    let error: String
    let message: String
}

enum ImportError: LocalizedError {
    case invalidURL
    case uploadFailed
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .uploadFailed:
            return "Failed to upload CSV file"
        case .serverError(let message):
            return message
        }
    }
}
```

**Acceptance Criteria:**
- [ ] View model uses SSEClient
- [ ] Progress updates published to UI
- [ ] Completion handled properly
- [ ] Error states handled
- [ ] SSE cleanup on completion/error
- [ ] Thread-safe (@MainActor)
- [ ] Compiles without errors

---

### Task 4: Update Import UI (20 minutes)

**Goal:** Display real-time progress in SwiftUI view

**File:** Find and update import view (likely `*ImportView.swift`)

**Implementation:**

```swift
import SwiftUI

struct CSVImportView: View {
    
    @StateObject private var viewModel = CSVImportViewModel()
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Title
            Text("Import CSV")
                .font(.title)
                .fontWeight(.bold)
            
            if viewModel.isImporting {
                // Progress UI
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.progress) {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .progressViewStyle(.linear)
                    
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()
                    
                    Button("Cancel") {
                        viewModel.cancelImport()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
            } else if viewModel.isComplete {
                // Success UI
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text(viewModel.statusMessage)
                        .font(.headline)
                    
                    Button("Import Another") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
            } else {
                // Initial state
                VStack(spacing: 16) {
                    Button("Select CSV File") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                // Import CSV
                Task {
                    await viewModel.importCSV(fileURL: url)
                }
                
            case .failure(let error):
                viewModel.error = error
            }
        }
    }
}
```

**Acceptance Criteria:**
- [ ] Progress bar shows real-time updates
- [ ] Status message updates with counts
- [ ] Percentage shown (0-100%)
- [ ] Cancel button works
- [ ] Success state shows checkmark
- [ ] Error states show error message
- [ ] File picker launches on button tap
- [ ] Compiles without errors

---

### Task 5: Test CSV Import SSE (30 minutes)

**Goal:** Verify iOS app receives real-time progress

**Test Steps:**

1. Build and run app on simulator/device:
```bash
cd /Users/juju/dev_repos/books-v3
open BooksTracker.xcworkspace

# In Xcode: Cmd+R to build and run
```

2. Prepare test CSV:
   - Use `testImages/goodreads_library_export.csv` (10-20 books)
   - Or create small CSV with 5 books

3. Test import flow:
   - Tap "Import CSV" button
   - Select CSV file
   - Watch progress bar update in real-time
   - Verify completion shows success
   - Check logs for SSE events

4. Verify timing:
   - Progress updates should appear within 1 second
   - No 5-second delays between updates
   - Completion event appears promptly

5. Test error handling:
   - Try with invalid CSV (empty file)
   - Verify error message shown
   - Try cancelling mid-import
   - Verify cleanup happens

6. Check Xcode console logs:
```
[SSEClient] Connected to https://api.oooefam.net/api/v2/imports/...
[Import] Progress: 25% (5/20 books)
[Import] Progress: 50% (10/20 books)
[Import] Progress: 75% (15/20 books)
[Import] Complete: 100% (20/20 books)
[SSEClient] Disconnected
```

**Acceptance Criteria:**
- [ ] Progress bar updates in < 1 second
- [ ] Status message shows real counts
- [ ] Percentage accurate (0-100%)
- [ ] Completion shows success state
- [ ] Errors handled gracefully
- [ ] Cancel button works
- [ ] No crashes or hangs
- [ ] Logs show SSE events

---

## 🎯 Definition of Done

**All tasks complete when:**
- [ ] All 5 tasks completed and checked off
- [ ] SSEClient.swift implemented and working
- [ ] Import view model integrated with SSE
- [ ] Import UI shows real-time progress
- [ ] CSV import completes successfully
- [ ] Progress updates arrive in < 1 second
- [ ] Error handling works
- [ ] Cancel functionality works
- [ ] No memory leaks or crashes
- [ ] Cache validation unblocked (can test ISBN lookups)

---

## 📊 Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| SSE connection time | < 2s | Time from upload to first event |
| Progress update latency | < 1s | Time between server update and UI update |
| UI responsiveness | 60 FPS | Monitor during import (Instruments) |
| Memory usage | < 50MB | Peak memory during import |
| Success rate | 100% | Import completes without errors |

---

## 🚨 Rollback Plan

If SSE client breaks existing functionality:

1. Comment out SSE code in view model
2. Revert to old import flow (if exists)
3. Add TODO comment for future fix

If import completely broken:

1. Disable CSV import feature in UI
2. Show "Coming soon" message
3. Focus on other features

---

## 📚 Reference Documentation

- SSE Specification: https://html.spec.whatwg.org/multipage/server-sent-events.html
- bendv3 SSE endpoint: `/api/v2/imports/{jobId}/stream`
- bendv3 TODO: `/Users/juju/dev_repos/bendv3/TODO-USER-SSE-AND-COVERS.md`
- API Contract: `/Users/juju/dev_repos/books-v3/docs/API_CONTRACT.md`

---

## 💡 Tips & Best Practices

### SSE Best Practices
- Always set `Accept: text/event-stream` header
- Handle incomplete events with buffer
- Support reconnection with Last-Event-ID
- Parse events line-by-line
- Ignore comment lines (starting with :)

### iOS Best Practices
- Use `@MainActor` for UI updates
- Use `async/await` for network calls
- Handle errors gracefully
- Clean up resources (disconnect SSE)
- Test on device (not just simulator)

### Debugging Tips
- Check Xcode console for logs
- Use Charles Proxy to inspect SSE traffic
- Test with small CSV first (5 books)
- Verify bendv3 logs match iOS logs
- Use breakpoints in event handler

---

**Created:** November 30, 2025  
**Owner:** Justin (User)  
**Status:** Ready to Execute 🚀
