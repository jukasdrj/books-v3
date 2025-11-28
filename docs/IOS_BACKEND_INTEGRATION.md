# iOS Backend Integration Plan

**BooksTrack v3.7.5 → Backend API v3.2**

**Status:** Planning Complete ✅
**Date:** November 28, 2025
**Backend API:** https://api.oooefam.net
**API Contract:** `docs/API_CONTRACT.md`

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Architecture Recommendations](#architecture-recommendations)
3. [Integration Phases](#integration-phases)
4. [Implementation Guide](#implementation-guide)
5. [Testing Strategy](#testing-strategy)
6. [Migration Checklist](#migration-checklist)

---

## Current State Analysis

### Existing iOS Networking Code

**Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/SSEClient.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentResultsClient.swift`

**What Works Well:**
- ✅ `EnrichmentAPIClient` (actor) - Handles batch enrichment with ResponseEnvelope
- ✅ `SSEClient` (actor) - CSV import SSE progress streaming with reconnection
- ✅ Custom `ResponseEnvelope<T>` - Generic wrapper for success/error discrimination
- ✅ `ApiErrorCode` enum - Structured error handling
- ✅ Circuit breaker error handling in enrichment (`CIRCUIT_OPEN`)
- ✅ Rate limit detection (`429` status)
- ✅ CORS error detection (`X-Custom-Error` header)
- ✅ Job cancellation with Bearer auth (`DELETE /v1/jobs/{jobId}`)

**What Needs Improvement:**
- ❌ **Architecture scattered** - 3 separate API clients instead of unified service
- ❌ **@MainActor constraint** - `BookSearchAPIService` unnecessarily tied to main thread
- ❌ **Inconsistent error handling** - Mix of `ApiErrorCode`, `SearchError`, `EnrichmentError`
- ❌ **Missing CSV import results** - SSE streams progress, but results aren't saved to SwiftData
- ❌ **No automatic retry logic** - Circuit breaker errors require manual retry
- ❌ **Duplicate code** - ResponseEnvelope decoding repeated across files

### Backend API Capabilities (v3.2)

**Production Endpoints:**
- ✅ `GET /v1/search/isbn` - ISBN lookup (7-day cache)
- ✅ `GET /v1/search/title` - Title search
- ✅ `GET /v1/search/author` - Author search
- ✅ `GET /v1/search/similar` - Similar books (vector embeddings)
- ✅ `GET /api/v2/search?mode=semantic` - Semantic search (BGE-M3)
- ✅ `POST /api/v2/books/enrich` - Single book enrichment (sync)
- ✅ `POST /api/batch-enrich` - Batch enrichment (async job)
- ✅ `POST /api/v2/imports` - CSV import (async job, multipart/form-data)
- ✅ `GET /api/v2/imports/{jobId}/stream` - SSE progress stream
- ✅ `GET /api/v2/imports/{jobId}/results` - Job results with book array
- ✅ `DELETE /v1/jobs/{jobId}` - Job cancellation (requires Bearer token)

**Response Format (Canonical):**
```json
{
  "success": true,
  "data": { /* endpoint-specific */ },
  "metadata": { "source": "google_books", "cached": true }
}
```

**Error Format:**
```json
{
  "success": false,
  "error": {
    "code": "CIRCUIT_OPEN",
    "message": "Provider google-books temporarily unavailable",
    "retryable": true,
    "retryAfterMs": 60000
  }
}
```

**Error Codes:**
- `NOT_FOUND` (404) - Book not found
- `RATE_LIMIT_EXCEEDED` (429) - Too many requests
- `CIRCUIT_OPEN` (503) - External provider down (retry after N seconds)
- `API_ERROR` (502) - External API failure
- `INTERNAL_ERROR` (500) - Server error

---

## Architecture Recommendations

### Expert Recommendations (Gemini 2.5 Pro via Zen MCP)

**Source:** `mcp__zen__clink` consultation on November 28, 2025

#### 1. **Single Actor with Domain Extensions**

**Recommendation:**
Start with a single `actor BooksTrackAPI` that internally organizes methods by domain using extensions. This provides a unified interface while keeping code organized.

**Benefits:**
- Thread-safe by default (actor isolation)
- Single entry point for all API calls
- Easy to refactor into separate services later
- Clean separation of concerns via extensions

**Structure:**
```swift
// BooksTrackAPI.swift
public actor BooksTrackAPI {
    private let baseURL = URL(string: "https://api.oooefam.net")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }
}

// BooksTrackAPI+Search.swift
extension BooksTrackAPI {
    public func search(isbn: String) async throws -> BookDTO { ... }
    public func search(title: String, limit: Int = 20) async throws -> [BookDTO] { ... }
    public func searchSemantic(query: String) async throws -> [BookDTO] { ... }
}

// BooksTrackAPI+Enrichment.swift
extension BooksTrackAPI {
    public func enrichBook(barcode: String) async throws -> EnrichedBookDTO { ... }
    public func enrichBatch(barcodes: [String]) async throws -> (jobId: String, authToken: String) { ... }
}

// BooksTrackAPI+Import.swift
extension BooksTrackAPI {
    public func importCSV(data: Data) async throws -> (jobId: String, authToken: String) { ... }
    public func getImportResults(jobId: String) async throws -> [BookDTO] { ... }
}
```

#### 2. **Generic ResponseEnvelope (Already Exists!)**

**Current Implementation:**
✅ Already implemented in `EnrichmentAPIClient.swift` and used throughout codebase.

**Recommendation:**
Keep existing `ResponseEnvelope<T>` implementation, move to shared location.

```swift
public struct ResponseEnvelope<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let error: APIError?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decode(Bool.self, forKey: .success)

        if success {
            self.data = try container.decode(T.self, forKey: .data)
            self.error = nil
        } else {
            self.data = nil
            self.error = try container.decode(APIError.self, forKey: .error)
        }
    }
}
```

#### 3. **Unified APIError Enum**

**Recommendation:**
Consolidate existing `ApiErrorCode`, `SearchError`, `EnrichmentError` into single `APIError` enum.

```swift
public enum APIError: Error, Decodable {
    case circuitOpen(provider: String, retryAfterMs: Int)
    case rateLimitExceeded(retryAfter: Int?)
    case notFound(message: String)
    case serverError(message: String)
    case decodingError(message: String)
    case networkError(Error)
    case invalidURL
    case invalidResponse
    case corsBlocked

    private enum CodingKeys: String, CodingKey {
        case code, message, retryable, retryAfterMs, provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)

        switch code {
        case "CIRCUIT_OPEN":
            let provider = try container.decode(String.self, forKey: .provider)
            let retryAfterMs = try container.decode(Int.self, forKey: .retryAfterMs)
            self = .circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
        case "RATE_LIMIT_EXCEEDED":
            let retryAfter = try? container.decode(Int.self, forKey: .retryAfterMs)
            self = .rateLimitExceeded(retryAfter: retryAfter)
        case "NOT_FOUND":
            self = .notFound(message: message)
        default:
            self = .serverError(message: message)
        }
    }
}
```

#### 4. **SSE with AsyncThrowingStream (Already Implemented!)**

**Current Implementation:**
✅ `SSEClient` already uses `AsyncThrowingStream` pattern with reconnection logic.

**Recommendation:**
Keep existing `SSEClient` as-is. It's already well-designed:
- Actor-isolated for thread safety
- Automatic reconnection with exponential backoff
- Handles `Last-Event-ID` for resumption
- Network transition resilience

#### 5. **DTOs + Repository Pattern**

**Recommendation:**
- API client returns DTOs (plain structs)
- Repository layer maps DTOs → SwiftData models
- Keeps API client decoupled from persistence

**Flow:**
1. `View` calls `BookRepository.search(isbn:)`
2. `BookRepository` calls `BooksTrackAPI.search(isbn:)`
3. `BooksTrackAPI` returns `BookDTO`
4. `BookRepository` maps `BookDTO` → SwiftData `Work`, `Edition`, `Author`
5. `BookRepository` saves to SwiftData
6. `View` updates from SwiftData

**Benefits:**
- Clean separation of concerns
- API client is testable without SwiftData
- Easy to swap backend providers
- Repository handles deduplication logic

---

## Integration Phases

### Phase 1: Refactor Existing Code ⚙️

**Goal:** Consolidate networking into unified `BooksTrackAPI` actor

**Priority:** Medium
**Risk:** Low (refactoring, no new features)
**Timeline:** 1-2 days

**Tasks:**

1. **Create Core API Client**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI.swift`
   - Actor with `URLSession` dependency injection
   - Shared base URL, headers, timeout configuration

2. **Migrate Search Endpoints**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Search.swift`
   - Move methods from `BookSearchAPIService`:
     - `search(query:maxResults:scope:persist:)`
     - `getTrendingBooks(timeRange:)`
     - `advancedSearch(author:title:isbn:)`
     - `getTrendingSearches(limit:)`
     - `searchV2(query:mode:limit:)`
     - `findSimilarBooks(isbn:limit:)`
   - Remove `@MainActor` constraint (use actor instead)

3. **Migrate Enrichment Endpoints**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Enrichment.swift`
   - Move methods from `EnrichmentAPIClient`:
     - `enrichBookV2(barcode:idempotencyKey:preferProvider:)`
     - `startEnrichment(jobId:books:)`
     - `cancelJob(jobId:authToken:)`
   - Preserve endpoint fallback logic (`/v1` → `/api`)

4. **Migrate Import Endpoints**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Import.swift`
   - New methods:
     - `importCSV(data:) async throws -> (jobId: String, authToken: String)`
     - `getImportResults(jobId:) async throws -> [BookDTO]`
   - Integration with existing `SSEClient` (keep separate)

5. **Unify Error Handling**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/APIError.swift`
   - Consolidate `ApiErrorCode`, `SearchError`, `EnrichmentError` → `APIError`
   - Preserve existing error messages for user-facing alerts

6. **Create Shared DTOs**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/API/DTOs.swift`
   - Move existing DTO types: `BookDTO`, `WorkDTO`, `EditionDTO`, `AuthorDTO`, `EnrichedBookDTO`
   - Add missing: `ImportResultsDTO`, `JobStatusDTO`

**Files to Delete:**
- `EnrichmentAPIClient.swift` (migrated to `BooksTrackAPI+Enrichment.swift`)
- `BookSearchAPIService.swift` (migrated to `BooksTrackAPI+Search.swift`)

**Files to Keep:**
- `SSEClient.swift` (already well-designed, no changes needed)
- `EnrichmentResultsClient.swift` (review for consolidation)

**Testing:**
- Unit tests for each domain extension
- Integration tests against production API
- Verify existing functionality preserved (no regressions)

---

### Phase 2: Add Missing Backend Integrations 🆕

**Goal:** Implement CSV import results saving to SwiftData

**Priority:** High
**Risk:** Medium (new feature, SwiftData integration)
**Timeline:** 2-3 days

**Tasks:**

1. **Implement CSV Import Results Endpoint**
   - Endpoint: `GET /api/v2/imports/{jobId}/results`
   - Method: `BooksTrackAPI.getImportResults(jobId:) async throws -> [BookDTO]`
   - Returns: Array of canonical book objects from successful import

2. **Create BookRepository Layer**
   - File: `BooksTrackerPackage/Sources/BooksTrackerFeature/Repositories/BookRepository.swift`
   - Methods:
     - `saveImportResults(jobId: String) async throws -> Int` (returns count saved)
     - `saveSearchResult(dto: BookDTO) async throws -> Work`
     - `saveEnrichment(dto: EnrichedBookDTO, for work: Work) async throws`
   - Handles DTO → SwiftData mapping with deduplication

3. **Update CSV Import Flow**
   - Current: `GeminiCSVImportView` → `SSEClient` (progress only)
   - New: On SSE `completed` event → `BookRepository.saveImportResults(jobId:)`
   - UI: Show "Saving X books..." progress indicator
   - Error handling: Show alert if results fetch/save fails

4. **Add JobStatus Polling (Fallback)**
   - Endpoint: `GET /api/v2/imports/{jobId}`
   - Method: `BooksTrackAPI.getJobStatus(jobId:) async throws -> JobStatusDTO`
   - Use case: When SSE connection fails, poll every 2 seconds

**API Contract Reference:**

**Import Results Response:**
```json
{
  "success": true,
  "data": {
    "booksCreated": 145,
    "booksUpdated": 0,
    "duplicatesSkipped": 5,
    "enrichmentSucceeded": 140,
    "enrichmentFailed": 5,
    "errors": [
      {"row": 15, "isbn": "1234567890", "error": "Invalid ISBN"}
    ],
    "books": [
      {
        "isbn": "9780439708180",
        "title": "Harry Potter and the Sorcerer's Stone",
        "authors": ["J.K. Rowling"],
        "publisher": "Scholastic",
        "publishedDate": "1998-09-01",
        "description": "...",
        "pageCount": 320,
        "categories": ["Fiction", "Fantasy"],
        "language": "en",
        "coverUrl": "https://..."
      }
    ]
  }
}
```

**Critical:** iOS clients MUST parse the `books` array to save to SwiftData. This is the complete list of successfully imported books.

**Testing:**
- Upload sample CSV → verify books appear in library
- Test duplicate detection (same ISBN)
- Test error cases (invalid CSV, network failure)
- Verify SwiftData deduplication (don't create duplicate Works)

---

### Phase 3: Circuit Breaker & Retry Logic 🔄

**Goal:** User-friendly error handling with automatic retries

**Priority:** High
**Risk:** Low (UI polish)
**Timeline:** 1 day

**Tasks:**

1. **Extend APIError with Retry Logic**
   - Add `isRetryable: Bool` computed property
   - Add `retryDelay: TimeInterval?` for circuit breaker cases
   - Example: `.circuitOpen` → retryable after `retryAfterMs / 1000` seconds

2. **Automatic Retry with Exponential Backoff**
   - Helper: `func retryWithBackoff<T>(_ operation: () async throws -> T, maxAttempts: Int = 3) async throws -> T`
   - Use for transient errors: `CIRCUIT_OPEN`, `RATE_LIMIT_EXCEEDED`, `503`
   - Don't retry: `NOT_FOUND`, `400`, `401`, `403`

3. **User-Facing Error Messages**
   - Circuit breaker: "Google Books temporarily unavailable. Retrying in 60 seconds..."
   - Rate limit: "Too many requests. Please wait 30 seconds."
   - Network error: "Connection lost. Retrying..."
   - Not found: "Book not found. Try a different search."

4. **UI Indicators**
   - Loading spinner with retry count ("Retrying 2/3...")
   - Error banners with countdown timer ("Retry in 45s...")
   - Manual retry button for failed requests

**Example Implementation:**
```swift
func enrichBookWithRetry(barcode: String) async throws -> EnrichedBookDTO {
    return try await retryWithBackoff(maxAttempts: 3) {
        do {
            return try await booksTrackAPI.enrichBook(barcode: barcode)
        } catch let error as APIError {
            switch error {
            case .circuitOpen(let provider, let retryAfterMs):
                print("⚠️ Circuit breaker open for \(provider), waiting \(retryAfterMs)ms")
                try await Task.sleep(for: .milliseconds(retryAfterMs))
                throw error // Retry after delay
            case .rateLimitExceeded(let retryAfter):
                if let retryAfter = retryAfter {
                    try await Task.sleep(for: .seconds(retryAfter))
                }
                throw error // Retry after delay
            case .notFound:
                throw error // Don't retry
            default:
                throw error
            }
        }
    }
}
```

**Testing:**
- Mock backend with 503 responses → verify retry logic
- Test rate limit handling (429 with Retry-After header)
- Test max retry limit (don't retry forever)

---

### Phase 4: Performance & Caching Optimization 🚀

**Goal:** Leverage backend caching, prefetch trending books

**Priority:** Low
**Risk:** Low
**Timeline:** 1-2 days

**Tasks:**

1. **Respect Backend Cache Headers**
   - Parse `Cache-Control`, `X-Cache` headers
   - Log cache hit rate for observability
   - Already implemented in `BookSearchAPIService` ✅

2. **Prefetch Trending Books**
   - On app launch → fetch trending books in background
   - Cache in SwiftData for offline access
   - Already implemented in `BookSearchAPIService.getTrendingBooks()` ✅

3. **Image Prefetching**
   - Prefetch cover images for trending/search results
   - Already implemented in `ImagePrefetcher` ✅

4. **Request Coalescing**
   - Deduplicate concurrent requests for same ISBN
   - Use `NSCache<String, Task<BookDTO, Error>>` for in-flight requests

**Testing:**
- Measure response times (should be <50ms for cached books)
- Verify cache hit rate in logs
- Test offline access (cached books should load)

---

## Implementation Guide

### Step-by-Step Migration

#### Step 1: Create BooksTrackAPI Actor

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI.swift`

```swift
import Foundation

/// Unified API client for BooksTrack backend
/// Thread-safe actor with domain-specific extensions
public actor BooksTrackAPI {
    // MARK: - Configuration

    private let baseURL: URL
    private let session: URLSession

    // MARK: - Initialization

    public init(
        baseURL: URL = URL(string: "https://api.oooefam.net")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Shared Helpers

    /// Decode ResponseEnvelope and extract data or throw error
    func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(ResponseEnvelope<T>.self, from: data)

        if let error = envelope.error {
            throw error
        }

        guard let result = envelope.data else {
            throw APIError.invalidResponse
        }

        return result
    }

    /// Create URLRequest with common headers
    func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        return request
    }
}
```

#### Step 2: Create Search Extension

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Search.swift`

```swift
import Foundation

// MARK: - Search Extension

extension BooksTrackAPI {
    /// Search for books by ISBN (7-day cache, most accurate)
    public func search(isbn: String) async throws -> BookDTO {
        let url = baseURL.appendingPathComponent("/v1/search/isbn")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "isbn", value: isbn)]

        guard let finalURL = components.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: finalURL)
        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        return try decodeEnvelope(BookDTO.self, from: data)
    }

    /// Search for books by title
    public func search(title: String, limit: Int = 20) async throws -> [BookDTO] {
        let url = baseURL.appendingPathComponent("/v1/search/title")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let finalURL = components.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: finalURL)
        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        let searchResponse = try decodeEnvelope(SearchResponseDTO.self, from: data)
        return searchResponse.books
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Rate limit detection
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.rateLimitExceeded(retryAfter: retryAfter)
        }

        // CORS detection
        if let customError = httpResponse.value(forHTTPHeaderField: "X-Custom-Error"),
           customError == "CORS_BLOCKED" {
            throw APIError.corsBlocked
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}
```

#### Step 3: Create Enrichment Extension

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Enrichment.swift`

```swift
import Foundation

// MARK: - Enrichment Extension

extension BooksTrackAPI {
    /// Enrich a book using the V2 sync API
    public func enrichBook(barcode: String, idempotencyKey: String? = nil) async throws -> EnrichedBookDTO {
        let url = baseURL.appendingPathComponent("/api/v2/books/enrich")
        var request = makeRequest(url: url, method: "POST")

        let key = idempotencyKey ?? "scan_\(barcode)"
        let payload = EnrichBookRequest(barcode: barcode, idempotencyKey: key)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(EnrichedBookDTO.self, from: data)
        case 404:
            throw APIError.notFound(message: "Book not found")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.rateLimitExceeded(retryAfter: retryAfter)
        case 503:
            // Parse circuit breaker error
            let errorResponse = try? JSONDecoder().decode(ResponseEnvelope<EnrichedBookDTO>.self, from: data)
            if let apiError = errorResponse?.error {
                throw apiError
            }
            throw APIError.serverError(message: "Service unavailable")
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    /// Start batch enrichment job (async)
    public func enrichBatch(barcodes: [String]) async throws -> (jobId: String, authToken: String) {
        let url = baseURL.appendingPathComponent("/api/batch-enrich")
        var request = makeRequest(url: url, method: "POST")

        let payload = BatchEnrichmentRequest(barcodes: barcodes)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw APIError.invalidResponse
        }

        let result = try decodeEnvelope(BatchEnrichmentResponse.self, from: data)
        return (result.jobId, result.authToken)
    }

    /// Cancel enrichment job
    public func cancelJob(jobId: String, authToken: String) async throws -> JobCancellationResponse {
        let url = baseURL.appendingPathComponent("/v1/jobs/\(jobId)")
        var request = makeRequest(url: url, method: "DELETE")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized(message: "Invalid or expired token")
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try decodeEnvelope(JobCancellationResponse.self, from: data)
    }
}
```

#### Step 4: Create Import Extension

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/BooksTrackAPI+Import.swift`

```swift
import Foundation

// MARK: - Import Extension

extension BooksTrackAPI {
    /// Import CSV file (async job)
    public func importCSV(data: Data) async throws -> (jobId: String, authToken: String) {
        let url = baseURL.appendingPathComponent("/api/v2/imports")

        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = makeRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw APIError.invalidResponse
        }

        let result = try decodeEnvelope(ImportJobResponse.self, from: responseData)
        return (result.jobId, result.authToken)
    }

    /// Get import job results
    public func getImportResults(jobId: String) async throws -> ImportResults {
        let url = baseURL.appendingPathComponent("/api/v2/imports/\(jobId)/results")
        let request = makeRequest(url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return try decodeEnvelope(ImportResults.self, from: data)
    }

    /// Get import job status (polling fallback)
    public func getJobStatus(jobId: String) async throws -> JobStatus {
        let url = baseURL.appendingPathComponent("/api/v2/imports/\(jobId)")
        let request = makeRequest(url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return try decodeEnvelope(JobStatus.self, from: data)
    }
}
```

#### Step 5: Create Unified APIError

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/APIError.swift`

```swift
import Foundation

public enum APIError: Error, LocalizedError, Decodable {
    case circuitOpen(provider: String, retryAfterMs: Int)
    case rateLimitExceeded(retryAfter: Int?)
    case notFound(message: String)
    case serverError(message: String)
    case decodingError(message: String)
    case networkError(Error)
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case corsBlocked
    case unauthorized(message: String)

    // MARK: - Decodable

    private enum CodingKeys: String, CodingKey {
        case code, message, retryable, retryAfterMs, provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)

        switch code {
        case "CIRCUIT_OPEN":
            let provider = try container.decode(String.self, forKey: .provider)
            let retryAfterMs = try container.decode(Int.self, forKey: .retryAfterMs)
            self = .circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
        case "RATE_LIMIT_EXCEEDED":
            let retryAfter = try? container.decode(Int.self, forKey: .retryAfterMs)
            self = .rateLimitExceeded(retryAfter: retryAfter)
        case "NOT_FOUND":
            self = .notFound(message: message)
        default:
            self = .serverError(message: message)
        }
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .circuitOpen(let provider, let retryAfterMs):
            return "Provider \(provider) temporarily unavailable. Retry in \(retryAfterMs / 1000) seconds."
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Try again in \(retryAfter) seconds."
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        case .notFound(let message):
            return message
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .corsBlocked:
            return "Network security error. Check your connection or contact support."
        case .unauthorized(let message):
            return "Authentication failed: \(message)"
        }
    }

    // MARK: - Retry Logic

    public var isRetryable: Bool {
        switch self {
        case .circuitOpen, .rateLimitExceeded, .networkError:
            return true
        case .notFound, .invalidURL, .corsBlocked, .unauthorized:
            return false
        case .httpError(let code):
            return code >= 500 // Retry server errors
        default:
            return false
        }
    }

    public var retryDelay: TimeInterval? {
        switch self {
        case .circuitOpen(_, let retryAfterMs):
            return Double(retryAfterMs) / 1000.0
        case .rateLimitExceeded(let retryAfter):
            return retryAfter.map(Double.init)
        default:
            return nil
        }
    }
}
```

#### Step 6: Update View Layer

**Example: Search View Integration**

```swift
import SwiftUI
import SwiftData

struct SearchView: View {
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var error: APIError?

    private let api = BooksTrackAPI()

    var body: some View {
        VStack {
            SearchBar(text: $searchText, onSubmit: performSearch)

            if isLoading {
                ProgressView("Searching...")
            } else if let error = error {
                ErrorView(error: error, onRetry: performSearch)
            } else {
                ResultsList(results: results)
            }
        }
    }

    private func performSearch() {
        Task {
            isLoading = true
            error = nil

            do {
                let books = try await api.search(title: searchText)
                results = books.map { SearchResult(from: $0) }
            } catch let apiError as APIError {
                error = apiError

                // Automatic retry for retryable errors
                if apiError.isRetryable, let delay = apiError.retryDelay {
                    try? await Task.sleep(for: .seconds(delay))
                    performSearch() // Retry once
                }
            }

            isLoading = false
        }
    }
}
```

---

## Testing Strategy

### Unit Tests

**File:** `BooksTrackerPackageTests/API/BooksTrackAPITests.swift`

```swift
import XCTest
@testable import BooksTrackerFeature

final class BooksTrackAPITests: XCTestCase {
    var api: BooksTrackAPI!
    var mockSession: URLSession!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        api = BooksTrackAPI(session: mockSession)
    }

    func testSearchISBN_Success() async throws {
        // Mock response
        MockURLProtocol.mockResponse = """
        {
          "success": true,
          "data": {
            "isbn": "9780439708180",
            "title": "Harry Potter and the Sorcerer's Stone",
            "authors": ["J.K. Rowling"]
          }
        }
        """.data(using: .utf8)

        let book = try await api.search(isbn: "9780439708180")

        XCTAssertEqual(book.isbn, "9780439708180")
        XCTAssertEqual(book.title, "Harry Potter and the Sorcerer's Stone")
    }

    func testSearchISBN_CircuitBreakerOpen() async throws {
        // Mock circuit breaker response
        MockURLProtocol.mockResponse = """
        {
          "success": false,
          "error": {
            "code": "CIRCUIT_OPEN",
            "message": "Provider google-books temporarily unavailable",
            "provider": "google-books",
            "retryable": true,
            "retryAfterMs": 60000
          }
        }
        """.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 503

        do {
            _ = try await api.search(isbn: "9780439708180")
            XCTFail("Should throw circuit breaker error")
        } catch let error as APIError {
            guard case .circuitOpen(let provider, let retryAfterMs) = error else {
                XCTFail("Wrong error type")
                return
            }
            XCTAssertEqual(provider, "google-books")
            XCTAssertEqual(retryAfterMs, 60000)
            XCTAssertTrue(error.isRetryable)
            XCTAssertEqual(error.retryDelay, 60.0)
        }
    }

    func testRateLimitExceeded() async throws {
        MockURLProtocol.mockStatusCode = 429
        MockURLProtocol.mockHeaders = ["Retry-After": "30"]

        do {
            _ = try await api.search(isbn: "9780439708180")
            XCTFail("Should throw rate limit error")
        } catch let error as APIError {
            guard case .rateLimitExceeded(let retryAfter) = error else {
                XCTFail("Wrong error type")
                return
            }
            XCTAssertEqual(retryAfter, 30)
        }
    }
}
```

### Integration Tests

**File:** `BooksTrackerPackageTests/Integration/APIIntegrationTests.swift`

```swift
import XCTest
@testable import BooksTrackerFeature

final class APIIntegrationTests: XCTestCase {
    var api: BooksTrackAPI!

    override func setUp() async throws {
        // Use production API
        api = BooksTrackAPI(baseURL: URL(string: "https://api.oooefam.net")!)
    }

    func testLiveSearchISBN() async throws {
        let book = try await api.search(isbn: "9780439708180")

        XCTAssertEqual(book.isbn, "9780439708180")
        XCTAssertTrue(book.title.contains("Harry Potter"))
    }

    func testLiveSearchTitle() async throws {
        let books = try await api.search(title: "Harry Potter", limit: 10)

        XCTAssertFalse(books.isEmpty)
        XCTAssertTrue(books.count <= 10)
    }

    func testLiveEnrichBook() async throws {
        let enriched = try await api.enrichBook(barcode: "9780439708180")

        XCTAssertNotNil(enriched.work)
        XCTAssertNotNil(enriched.edition)
    }
}
```

---

## Migration Checklist

### Pre-Migration

- [ ] Read `docs/API_CONTRACT.md` (source of truth)
- [ ] Review `docs/FRONTEND_HANDOFF.md` (integration guide)
- [ ] Understand existing code:
  - [ ] `EnrichmentAPIClient.swift`
  - [ ] `BookSearchAPIService.swift`
  - [ ] `SSEClient.swift`
- [ ] Set up local backend for testing (optional):
  ```bash
  cd bendv3
  npm run dev  # http://localhost:8787
  ```

### Phase 1: Refactor

- [ ] Create `BooksTrackAPI.swift` actor
- [ ] Create `BooksTrackAPI+Search.swift` extension
- [ ] Create `BooksTrackAPI+Enrichment.swift` extension
- [ ] Create `BooksTrackAPI+Import.swift` extension
- [ ] Create `APIError.swift` enum
- [ ] Create `DTOs.swift` (shared types)
- [ ] Update views to use `BooksTrackAPI` instead of old services
- [ ] Delete old files:
  - [ ] `EnrichmentAPIClient.swift`
  - [ ] `BookSearchAPIService.swift`
- [ ] Run tests: `/test`
- [ ] Verify build: `/quick-validate`

### Phase 2: CSV Import Results

- [ ] Implement `BooksTrackAPI.getImportResults(jobId:)`
- [ ] Create `BookRepository.swift`
- [ ] Implement `BookRepository.saveImportResults(jobId:)`
- [ ] Update `GeminiCSVImportView`:
  - [ ] Call `getImportResults()` on SSE `completed` event
  - [ ] Save books to SwiftData via repository
  - [ ] Show progress indicator
- [ ] Add error handling for results fetch/save
- [ ] Test with sample CSV (upload → verify books in library)
- [ ] Test duplicate detection
- [ ] Run tests: `/test`

### Phase 3: Circuit Breaker & Retry

- [ ] Add `isRetryable`, `retryDelay` to `APIError`
- [ ] Implement `retryWithBackoff()` helper
- [ ] Update views with retry logic
- [ ] Add user-facing error messages
- [ ] Add UI indicators (retry countdown, manual retry button)
- [ ] Test with mock 503 responses
- [ ] Test rate limit handling (429)
- [ ] Run tests: `/test`

### Phase 4: Performance

- [ ] Verify cache hit rate logging
- [ ] Test prefetch on app launch
- [ ] Add request coalescing (deduplicate in-flight requests)
- [ ] Measure response times (should be <50ms for cached)
- [ ] Test offline access (cached books)
- [ ] Run tests: `/test`

### Post-Migration

- [ ] Update `AGENTS.md` with new API client patterns
- [ ] Update `CLAUDE.md` if needed
- [ ] Delete this document or mark as "COMPLETED ✅"
- [ ] Create PR with summary of changes
- [ ] Test on real device (`/device-deploy`)
- [ ] Submit to TestFlight

---

## Appendix A: API Endpoint Reference

**Base URL:** `https://api.oooefam.net`

### Search Endpoints

| Endpoint | Method | Description | Cache | Rate Limit |
|----------|--------|-------------|-------|------------|
| `/v1/search/isbn` | GET | ISBN lookup | 7 days | 100 req/min |
| `/v1/search/title` | GET | Title search | 24 hours | 100 req/min |
| `/v1/search/author` | GET | Author search | 24 hours | 100 req/min |
| `/v1/search/similar` | GET | Similar books | 24 hours | 10 req/min |
| `/api/v2/search` | GET | Semantic search | 24 hours | 5 req/min |

### Enrichment Endpoints

| Endpoint | Method | Description | Cache | Rate Limit |
|----------|--------|-------------|-------|------------|
| `/api/v2/books/enrich` | POST | Single enrichment (sync) | None | 5 req/min |
| `/api/batch-enrich` | POST | Batch enrichment (async job) | None | 10 req/min |
| `/v1/jobs/{jobId}` | DELETE | Cancel job | None | 30 req/min |

### Import Endpoints

| Endpoint | Method | Description | Cache | Rate Limit |
|----------|--------|-------------|-------|------------|
| `/api/v2/imports` | POST | CSV import (async job) | None | 5 req/min |
| `/api/v2/imports/{jobId}/stream` | GET | SSE progress stream | None | N/A |
| `/api/v2/imports/{jobId}` | GET | Job status (polling) | None | 30 req/min |
| `/api/v2/imports/{jobId}/results` | GET | Job results + books array | 1 hour | 30 req/min |

---

## Appendix B: Error Code Reference

**From API Contract v3.2:**

| Code | HTTP | Description | Retryable | Retry Strategy |
|------|------|-------------|-----------|----------------|
| `NOT_FOUND` | 404 | Resource not found | ❌ No | Show "not found" message |
| `INVALID_REQUEST` | 400 | Invalid parameters | ❌ No | Show validation error |
| `RATE_LIMIT_EXCEEDED` | 429 | Rate limit hit | ✅ Yes | Wait `retryAfter` seconds |
| `CIRCUIT_OPEN` | 503 | Provider circuit breaker open | ✅ Yes | Wait `retryAfterMs` milliseconds |
| `API_ERROR` | 502 | External API failure | ✅ Maybe | Check `retryable` field |
| `NETWORK_ERROR` | 504 | Timeout or network issue | ✅ Yes | Exponential backoff |
| `INTERNAL_ERROR` | 500 | Server error | ✅ Maybe | Retry once, then show error |

---

## Appendix C: DTOs Reference

**Shared Data Transfer Objects**

```swift
// BookDTO.swift
public struct BookDTO: Codable, Sendable {
    let isbn: String
    let isbn13: String?
    let title: String
    let authors: [String]
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let pageCount: Int?
    let categories: [String]?
    let language: String?
    let coverUrl: String?
    let averageRating: Double?
    let ratingsCount: Int?
}

// EnrichedBookDTO.swift
public struct EnrichedBookDTO: Codable, Sendable {
    let work: WorkDTO?
    let edition: EditionDTO?
    let authors: [AuthorDTO]?
}

// WorkDTO.swift
public struct WorkDTO: Codable, Sendable {
    let id: String
    let title: String
    let subjects: [String]?
    let firstPublishYear: Int?
}

// EditionDTO.swift
public struct EditionDTO: Codable, Sendable {
    let id: String
    let numberOfPages: Int?
    let physicalFormat: String?
    let publishers: [String]?
}

// AuthorDTO.swift
public struct AuthorDTO: Codable, Sendable {
    let name: String
    let key: String?
    let birthDate: String?
}

// ImportResults.swift
public struct ImportResults: Codable, Sendable {
    let booksCreated: Int
    let booksUpdated: Int
    let duplicatesSkipped: Int
    let enrichmentSucceeded: Int
    let enrichmentFailed: Int
    let errors: [ImportError]
    let books: [BookDTO]  // ⚠️ CRITICAL: Full book objects

    struct ImportError: Codable, Sendable {
        let row: Int
        let isbn: String
        let error: String
    }
}

// JobStatus.swift
public struct JobStatus: Codable, Sendable {
    let jobId: String
    let status: String  // "initialized", "processing", "completed", "failed"
    let progress: Double
    let totalCount: Int
    let processedCount: Int
    let pipeline: String
}
```

---

## Appendix D: Repository Pattern Example

**BookRepository.swift**

```swift
import SwiftData
import Foundation

@MainActor
public class BookRepository {
    private let modelContext: ModelContext
    private let api: BooksTrackAPI

    public init(modelContext: ModelContext, api: BooksTrackAPI = BooksTrackAPI()) {
        self.modelContext = modelContext
        self.api = api
    }

    /// Save CSV import results to SwiftData
    /// Returns count of books successfully saved
    public func saveImportResults(jobId: String) async throws -> Int {
        // Fetch results from API
        let results = try await api.getImportResults(jobId: jobId)

        var savedCount = 0

        // Process each book from results.books array
        for bookDTO in results.books {
            do {
                try saveBook(bookDTO)
                savedCount += 1
            } catch {
                print("⚠️ Failed to save book \(bookDTO.isbn): \(error)")
                // Continue with other books
            }
        }

        try modelContext.save()
        return savedCount
    }

    /// Save a single book DTO to SwiftData with deduplication
    private func saveBook(_ dto: BookDTO) throws {
        // Check if work already exists
        let workDescriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.title == dto.title && work.authors.contains { $0.name == dto.authors.first }
            }
        )

        let existingWork = try modelContext.fetch(workDescriptor).first

        let work: Work
        if let existingWork = existingWork {
            work = existingWork
        } else {
            work = Work(title: dto.title)
            modelContext.insert(work)
        }

        // Create/update edition
        let edition = Edition(isbn: dto.isbn)
        edition.isbn13 = dto.isbn13
        edition.publisher = dto.publisher
        edition.publishedDate = dto.publishedDate
        edition.pageCount = dto.pageCount
        edition.coverImageURL = dto.coverUrl
        edition.work = work

        modelContext.insert(edition)

        // Create/update authors
        for authorName in dto.authors {
            let authorDescriptor = FetchDescriptor<Author>(
                predicate: #Predicate { $0.name == authorName }
            )

            let author: Author
            if let existing = try modelContext.fetch(authorDescriptor).first {
                author = existing
            } else {
                author = Author(name: authorName)
                modelContext.insert(author)
            }

            if !work.authors.contains(where: { $0.name == authorName }) {
                work.authors.append(author)
            }
        }
    }
}
```

---

**End of Document**

**Last Updated:** November 28, 2025
**Maintained by:** oooe (jukasdrj)
**See Also:**
- `docs/API_CONTRACT.md` (backend contract)
- `docs/FRONTEND_HANDOFF.md` (integration package)
- `AGENTS.md` (universal project guide)
- `CLAUDE.md` (Claude Code setup)
