# books-v3 (iOS) Contract Compliance TODOs

**Created:** November 29, 2025  
**Context:** API Contract v3.2 updates and bendv3 compliance fixes  
**Related:** `bendv3/docs/API_CONTRACT.md`, `bendv3/TODO_CONTRACT_COMPLIANCE.md`  
**Goal:** Align iOS client with backend API contract

---

## Priority Legend

- **P0 (CRITICAL):** Blocking integration - must fix before testing with updated backend
- **P1 (HIGH):** Required for production readiness
- **P2 (MEDIUM):** Should fix but not blocking
- **P3 (LOW):** Nice to have, future improvement

---

## P0: Update Response Parsing for Success Discriminator

**Impact:** Backend now includes `success: boolean` field in ALL responses  
**Contract Reference:** API_CONTRACT.md Section 3.1, 3.2  
**Breaking Change:** Yes (if iOS expects old format)

### Current Response Format (Old)

```json
{
  "data": { ... },
  "metadata": { ... }
}
```

### New Response Format (Contract Compliant)

```json
{
  "success": true,
  "data": { ... },
  "metadata": { ... }
}
```

### Required Swift Model Updates

**Find existing response models:**
```bash
# Search for response decodable structs
rg "struct.*Response.*Codable" --type swift
rg "struct.*Metadata.*Codable" --type swift
```

**Update Base Response Protocol:**

```swift
// BEFORE (if exists)
protocol APIResponse: Codable {
    associatedtype DataType: Codable
    var data: DataType { get }
    var metadata: ResponseMetadata { get }
}

// AFTER
protocol APIResponse: Codable {
    associatedtype DataType: Codable
    var success: Bool { get }  // ← ADD THIS
    var data: DataType { get }
    var metadata: ResponseMetadata { get }
}
```

**Or create discriminated response types:**

```swift
// Success Response
struct SuccessResponse<T: Codable>: Codable {
    let success: Bool  // Always true
    let data: T
    let metadata: ResponseMetadata
}

// Error Response  
struct ErrorResponse: Codable {
    let success: Bool  // Always false
    let error: APIError
    // Note: No data or metadata in error responses
}

// Error Object
struct APIError: Codable {
    let code: String
    let message: String
    let retryable: Bool  // ← NEW FIELD
    let details: [String: AnyCodable]?
}
```

**Generic Response Handler:**

```swift
func handleAPIResponse<T: Codable>(
    data: Data,
    expecting type: T.Type
) throws -> T {
    // First, check if response is success or error
    let decoder = JSONDecoder()
    
    // Decode just the success field first
    struct SuccessCheck: Codable {
        let success: Bool
    }
    
    let successCheck = try decoder.decode(SuccessCheck.self, from: data)
    
    if successCheck.success {
        // Parse as success response
        let response = try decoder.decode(SuccessResponse<T>.self, from: data)
        return response.data
    } else {
        // Parse as error response
        let errorResponse = try decoder.decode(ErrorResponse.self, from: data)
        throw APIClientError.apiError(errorResponse.error)
    }
}
```

### Testing

```swift
// Test success response parsing
let jsonData = """
{
    "success": true,
    "data": { "isbn": "9780439064873", "title": "..." },
    "metadata": { "timestamp": "...", "source": "alexandria" }
}
""".data(using: .utf8)!

do {
    let book = try handleAPIResponse(data: jsonData, expecting: Book.self)
    print("✅ Success response parsed")
} catch {
    print("❌ Failed to parse success response: \(error)")
}

// Test error response parsing
let errorData = """
{
    "success": false,
    "error": {
        "code": "NOT_FOUND",
        "message": "Book not found",
        "retryable": false
    }
}
""".data(using: .utf8)!

do {
    let _ = try handleAPIResponse(data: errorData, expecting: Book.self)
    print("❌ Should have thrown error")
} catch let APIClientError.apiError(error) {
    print("✅ Error response parsed: \(error.code)")
    print("✅ Retryable: \(error.retryable)")
}
```

---

## P0: Migrate V2 Endpoints from WebSocket to SSE

**Impact:** CSV Import and Photo Scan now use SSE instead of WebSocket  
**Contract Reference:** API_CONTRACT.md Section 7.1, 7.2, 8  
**Breaking Change:** Yes - WebSocket no longer supported for V2 endpoints  
**Timeline:** WebSocket fully removed Q3 2026

### Affected Endpoints

- **CSV Import:** `POST /api/v2/imports` → returns `sseUrl` + `statusUrl`
- **Photo Scan:** `POST /api/batch-scan` → returns `sseUrl` + `statusUrl`
- **Legacy:** Batch enrichment still uses WebSocket (migrating Q2 2026)

### New Response Format

```json
{
  "success": true,
  "data": {
    "jobId": "import_abc123",
    "authToken": "uuid-token",       // ← NEW (canonical)
    "token": "uuid-token",            // ← DEPRECATED (remove by March 2026)
    "sseUrl": "/api/v2/imports/import_abc123/stream",  // ← NEW
    "statusUrl": "/api/v2/imports/import_abc123"       // ← NEW
  }
}
```

### SSE Client Implementation

**Option A: Use existing EventSource library**

```swift
import Foundation

// Using: https://github.com/inaka/EventSource (or similar)
class SSEProgressMonitor {
    private var eventSource: EventSource?
    private let baseURL: String
    
    func connect(to sseUrl: String, onProgress: @escaping (JobProgress) -> Void) {
        let url = URL(string: "\(baseURL)\(sseUrl)")!
        
        eventSource = EventSource(url: url, headers: [
            "Accept": "text/event-stream"
        ])
        
        // Handle progress events
        eventSource?.addEventListener("processing") { id, event, data in
            guard let data = data?.data(using: .utf8),
                  let progress = try? JSONDecoder().decode(JobProgress.self, from: data) else {
                return
            }
            onProgress(progress)
        }
        
        // Handle completion
        eventSource?.addEventListener("completed") { id, event, data in
            guard let data = data?.data(using: .utf8),
                  let result = try? JSONDecoder().decode(JobComplete.self, from: data) else {
                return
            }
            self.handleCompletion(result)
        }
        
        // Handle errors
        eventSource?.addEventListener("failed") { id, event, data in
            guard let data = data?.data(using: .utf8),
                  let error = try? JSONDecoder().decode(JobFailed.self, from: data) else {
                return
            }
            self.handleError(error)
        }
        
        // Connection error handling
        eventSource?.onComplete { statusCode, reconnect, error in
            if let error = error {
                print("SSE connection error: \(error)")
            }
        }
        
        eventSource?.connect()
    }
    
    func disconnect() {
        eventSource?.disconnect()
        eventSource = nil
    }
}
```

**Option B: Manual URLSession implementation**

```swift
class ManualSSEClient {
    private var task: URLSessionDataTask?
    private var buffer = ""
    
    func connect(to sseUrl: String, onEvent: @escaping (SSEEvent) -> Void) {
        let url = URL(string: sseUrl)!
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            
            self?.buffer += chunk
            self?.parseEvents(onEvent: onEvent)
        }
        
        task?.resume()
    }
    
    private func parseEvents(onEvent: @escaping (SSEEvent) -> Void) {
        let lines = buffer.components(separatedBy: "\n\n")
        
        for eventBlock in lines.dropLast() {
            var eventType: String?
            var eventData: String?
            var eventId: String?
            
            for line in eventBlock.components(separatedBy: "\n") {
                if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                } else if line.hasPrefix("data:") {
                    eventData = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                } else if line.hasPrefix("id:") {
                    eventId = String(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
                }
            }
            
            if let type = eventType, let data = eventData {
                onEvent(SSEEvent(id: eventId, event: type, data: data))
            }
        }
        
        buffer = lines.last ?? ""
    }
}

struct SSEEvent {
    let id: String?
    let event: String
    let data: String
}
```

### SSE Event Types

```swift
// Processing event
struct JobProgress: Codable {
    let jobId: String
    let status: String
    let progress: Double  // 0.0 - 1.0
    let processedCount: Int
    let totalCount: Int
}

// Completed event
struct JobComplete: Codable {
    let type: String  // "job_complete"
    let pipeline: String
    let summary: JobSummary
    let expiresAt: String
}

struct JobSummary: Codable {
    let totalProcessed: Int?
    let successCount: Int?
    let failureCount: Int?
    
    // For photo scan
    let photosProcessed: Int?
    let booksDetected: Int?
    let booksUnique: Int?
    let booksEnriched: Int?
    
    let duration: Int
    let resourceId: String
}

// Failed event
struct JobFailed: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let processedCount: Int
    let totalCount: Int
    let error: JobError
}

struct JobError: Codable {
    let code: String
    let message: String
    let retryable: Bool
    let details: [String: AnyCodable]?
}
```

### Migration Strategy

```swift
// Detect which progress mechanism to use
func startJob(endpoint: String, body: Data) async throws -> JobResponse {
    let response = try await apiClient.post(endpoint, body: body)
    
    if let sseUrl = response.sseUrl {
        // V2 endpoint - use SSE
        return .sse(
            jobId: response.jobId,
            sseUrl: sseUrl,
            statusUrl: response.statusUrl
        )
    } else if let websocketUrl = response.websocketUrl {
        // Legacy endpoint - use WebSocket
        return .websocket(
            jobId: response.jobId,
            websocketUrl: websocketUrl,
            token: response.authToken ?? response.token
        )
    } else {
        throw JobError.invalidResponse
    }
}

enum JobResponse {
    case sse(jobId: String, sseUrl: String, statusUrl: String)
    case websocket(jobId: String, websocketUrl: String, token: String)
}
```

### Testing

```swift
// Test SSE connection
func testSSEProgress() async {
    let monitor = SSEProgressMonitor()
    
    monitor.connect(to: "/api/v2/imports/test123/stream") { progress in
        print("Progress: \(progress.processedCount)/\(progress.totalCount)")
        XCTAssertGreaterThanOrEqual(progress.progress, 0.0)
        XCTAssertLessThanOrEqual(progress.progress, 1.0)
    }
    
    // Wait for completion
    try await Task.sleep(nanoseconds: 30_000_000_000)  // 30 seconds
    monitor.disconnect()
}
```

---

## P0: Update Parameter Names (barcode vs isbn)

**Impact:** Backend now accepts `"barcode"` parameter (matches contract)  
**Contract Reference:** API_CONTRACT.md Section 6.1  
**Breaking Change:** No - backend accepts both, but prefer "barcode"

### Enrichment Request

```swift
// BEFORE
struct EnrichmentRequest: Codable {
    let isbn: String
    let vectorize: Bool
}

// AFTER
struct EnrichmentRequest: Codable {
    let barcode: String  // ← Renamed from isbn
    let vectorize: Bool
}

// Usage
let request = EnrichmentRequest(
    barcode: "9780439064873",  // Use barcode now
    vectorize: false
)
```

### Backward Compatibility

Backend accepts both during transition period:
```swift
// This still works (backward compatible)
let legacyRequest = """
{
    "isbn": "9780439064873",
    "vectorize": false
}
"""

// But prefer this (contract-compliant)
let newRequest = """
{
    "barcode": "9780439064873",
    "vectorize": false
}
"""
```

### Testing

```swift
func testEnrichmentWithBarcode() async throws {
    let request = EnrichmentRequest(
        barcode: "9780439064873",
        vectorize: false
    )
    
    let response = try await apiClient.enrich(request)
    
    XCTAssertTrue(response.success)
    XCTAssertNotNil(response.data)
    print("✅ Enrichment with 'barcode' parameter works")
}
```

---

## P1: Handle error.retryable Field

**Impact:** Errors now include `retryable: Bool` for retry logic  
**Contract Reference:** API_CONTRACT.md Section 3.2

### Error Model Update

```swift
// BEFORE
struct APIError: Codable {
    let code: String
    let message: String
    let details: [String: AnyCodable]?
}

// AFTER
struct APIError: Codable {
    let code: String
    let message: String
    let retryable: Bool  // ← ADD THIS
    let details: [String: AnyCodable]?
}
```

### Retry Logic Implementation

```swift
extension APIClient {
    func fetchWithRetry<T: Codable>(
        request: URLRequest,
        maxRetries: Int = 3
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxRetries {
            do {
                return try await fetch(request)
            } catch let APIClientError.apiError(error) {
                lastError = APIClientError.apiError(error)
                
                // Only retry if error is retryable
                if !error.retryable {
                    throw lastError!
                }
                
                // Exponential backoff
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                
                attempt += 1
            } catch {
                // Network or decoding errors - don't retry
                throw error
            }
        }
        
        throw lastError ?? APIClientError.maxRetriesExceeded
    }
}
```

### Retry Decision Matrix

```swift
enum ErrorRetryability {
    case retry(after: TimeInterval)
    case doNotRetry
    case retryWithBackoff
    
    init(from error: APIError) {
        switch (error.code, error.retryable) {
        case ("RATE_LIMIT_EXCEEDED", true):
            // Check Retry-After header if available
            self = .retry(after: 60)
            
        case ("CIRCUIT_OPEN", true):
            // Provider down, retry with backoff
            if let retryAfterMs = error.details?["retryAfterMs"]?.intValue {
                self = .retry(after: Double(retryAfterMs) / 1000.0)
            } else {
                self = .retryWithBackoff
            }
            
        case (_, true):
            // Retryable but no specific timing
            self = .retryWithBackoff
            
        case (_, false):
            // Not retryable
            self = .doNotRetry
        }
    }
}
```

### User Feedback for Retryable Errors

```swift
func handleAPIError(_ error: APIError) {
    let retryability = ErrorRetryability(from: error)
    
    switch retryability {
    case .retry(let after):
        showAlert(
            title: "Temporary Issue",
            message: "\(error.message)\n\nPlease try again in \(Int(after)) seconds.",
            primaryAction: "Retry Later"
        )
        
    case .retryWithBackoff:
        showAlert(
            title: "Connection Issue",
            message: error.message,
            primaryAction: "Retry",
            onRetry: { [weak self] in
                await self?.retryLastOperation()
            }
        )
        
    case .doNotRetry:
        showAlert(
            title: "Error",
            message: error.message,
            primaryAction: "OK"
        )
    }
}
```

---

## P2: Update SwiftData Models for Enriched Structure

**Impact:** Backend may return nested work/edition/authors structure  
**Contract Reference:** API_CONTRACT.md Section 4.2  
**Note:** Check if backend actually returns this yet (P2 item on backend)

### Current Canonical Structure

```swift
struct Book: Codable {
    let isbn: String
    let title: String
    let authors: [String]  // Just names
    let publisher: String?
    let publishedDate: String?
    let coverUrl: String?
    // ... other flat fields
}
```

### Enriched Structure (If Implemented)

```swift
struct EnrichedBook: Codable {
    // Canonical fields
    let isbn: String
    let title: String
    let authors: [String]
    let publisher: String?
    let publishedDate: String?
    let coverUrl: String?
    
    // Enriched nested objects
    let work: WorkMetadata?
    let edition: EditionMetadata?
    let enrichedAuthors: [AuthorMetadata]?
    
    enum CodingKeys: String, CodingKey {
        case isbn, title, authors, publisher, publishedDate, coverUrl
        case work, edition
        case enrichedAuthors = "authors"  // Conflicts with string array!
    }
}

struct WorkMetadata: Codable {
    let id: String
    let title: String
    let subjects: [String]
    let firstPublishYear: Int?
}

struct EditionMetadata: Codable {
    let id: String
    let numberOfPages: Int?
    let physicalFormat: String?
    let publishers: [String]
}

struct AuthorMetadata: Codable {
    let name: String
    let key: String
    let birthDate: String?
    
    enum CodingKeys: String, CodingKey {
        case name, key
        case birthDate = "birth_date"
    }
}
```

**Note:** There's a naming conflict - `authors` is both a `[String]` array (canonical) and `[AuthorMetadata]` array (enriched). Backend needs to resolve this, or use different field names.

### SwiftData Persistence

```swift
@Model
class BookEntity {
    @Attribute(.unique) var isbn: String
    var title: String
    var authorNames: [String]  // Canonical
    
    // Optional enriched data
    var workId: String?
    var workSubjects: [String]?
    var firstPublishYear: Int?
    
    var editionId: String?
    var physicalFormat: String?
    
    @Relationship(deleteRule: .cascade)
    var enrichedAuthors: [AuthorEntity]?
    
    init(from enrichedBook: EnrichedBook) {
        self.isbn = enrichedBook.isbn
        self.title = enrichedBook.title
        self.authorNames = enrichedBook.authors
        
        // Map enriched data if present
        if let work = enrichedBook.work {
            self.workId = work.id
            self.workSubjects = work.subjects
            self.firstPublishYear = work.firstPublishYear
        }
        
        if let edition = enrichedBook.edition {
            self.editionId = edition.id
            self.physicalFormat = edition.physicalFormat
        }
        
        if let authors = enrichedBook.enrichedAuthors {
            self.enrichedAuthors = authors.map { AuthorEntity(from: $0) }
        }
    }
}
```

---

## P3: Update Token Field Usage (authToken vs token)

**Impact:** Backend returns both `authToken` (new) and `token` (deprecated)  
**Timeline:** `token` removed March 1, 2026  
**Action:** Prefer `authToken`, fall back to `token`

### Job Response Parsing

```swift
struct JobResponse: Codable {
    let jobId: String
    let authToken: String?  // ← NEW (canonical)
    let token: String?       // ← DEPRECATED
    let sseUrl: String?
    let statusUrl: String?
    let websocketUrl: String?  // Legacy
    
    var effectiveToken: String? {
        // Prefer authToken, fall back to token
        return authToken ?? token
    }
}

// Usage
if let token = response.effectiveToken {
    // Use for authentication
    connectToProgressStream(jobId: response.jobId, token: token)
}
```

### Migration Timeline

```swift
// Phase 1 (Now - March 2026): Accept both
let token = response.authToken ?? response.token ?? {
    throw JobError.missingToken
}()

// Phase 2 (After March 2026): Only authToken
guard let token = response.authToken else {
    throw JobError.missingToken
}
```

---

## Testing Checklist

After implementing fixes, verify:

- [ ] **App parses success responses correctly**
  ```swift
  // Should not crash on success field
  let response = try JSONDecoder().decode(SuccessResponse<Book>.self, from: data)
  XCTAssertTrue(response.success)
  ```

- [ ] **App parses error responses correctly**
  ```swift
  // Should extract error object with retryable field
  let response = try JSONDecoder().decode(ErrorResponse.self, from: data)
  XCTAssertFalse(response.success)
  XCTAssertNotNil(response.error.retryable)
  ```

- [ ] **SSE connection works for CSV import**
  ```swift
  // Should receive processing events
  let monitor = SSEProgressMonitor()
  monitor.connect(to: sseUrl) { progress in
      XCTAssertGreaterThanOrEqual(progress.progress, 0.0)
  }
  ```

- [ ] **Enrichment uses "barcode" parameter**
  ```swift
  let request = EnrichmentRequest(barcode: "9780439064873", vectorize: false)
  let response = try await apiClient.enrich(request)
  XCTAssertTrue(response.success)
  ```

- [ ] **Retry logic respects retryable field**
  ```swift
  // Non-retryable error should not retry
  do {
      try await apiClient.fetchWithRetry(request)
      XCTFail("Should have thrown")
  } catch let APIClientError.apiError(error) {
      XCTAssertFalse(error.retryable)
  }
  ```

---

## Integration Testing with Backend

Once backend contract compliance is complete:

1. **Point app to staging backend**
   ```swift
   let config = APIConfiguration(
       baseURL: "https://api-staging.oooefam.net"
   )
   ```

2. **Test key flows**
   - ISBN search
   - Book enrichment  
   - CSV import with SSE progress
   - Photo scan with SSE progress

3. **Verify data persistence**
   - Check SwiftData saves correctly
   - Verify enriched metadata stored
   - Test offline access

4. **Check error handling**
   - Invalid ISBN → non-retryable error
   - Rate limit → retryable error with delay
   - Circuit breaker → retryable error

---

## Notes for Claude Code

When implementing these fixes:

1. **Run Swift build after each change**
   ```bash
   xcodebuild -scheme BooksTrack -sdk iphonesimulator build
   ```

2. **Run tests**
   ```bash
   xcodebuild test -scheme BooksTrack -sdk iphonesimulator
   ```

3. **Test on simulator**
   ```bash
   # Launch simulator
   open -a Simulator
   
   # Run app
   xcodebuild -scheme BooksTrack -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
     run
   ```

4. **Check console for errors**
   - Watch for JSONDecoder errors
   - Check for SSE connection failures
   - Verify retry logic fires correctly

5. **Commit incrementally**
   ```bash
   git add -p
   git commit -m "feat: add success discriminator to response parsing"
   ```

---

**Created by:** Claude (Assistant)  
**For:** Justin (via Claude Code execution)  
**Next:** Coordinate with backend team, implement fixes, test end-to-end
