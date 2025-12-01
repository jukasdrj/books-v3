# iOS API Migration Guide - V2 Priority

**Date:** December 1, 2025  
**Sunset:** March 1, 2026  
**Status:** 🔴 CRITICAL - Migration Required

---

## Overview

The backend is moving to V2 API exclusively. This document outlines the required changes
for the books-v3 iOS app to migrate from mixed V1/V2 usage to V2-only.

---

## Migration Checklist

### Phase 1: Search API (Week 1)

#### ❌ Remove: Multiple Search Endpoints
```swift
// FILE: API/BooksTrackAPI+Search.swift

// DELETE THIS (line 5-15):
func search(isbn: String) async throws -> BookDTO {
    // Uses /v1/search/isbn - DEPRECATED
}

// DELETE THIS (line 17-32):
func search(title: String, limit: Int = 20) async throws -> [BookDTO] {
    // Uses /v1/search/title - DEPRECATED
}

// DELETE THIS (line 53-70):
func findSimilarBooks(isbn: String, limit: Int = 10) async throws -> [BookDTO] {
    // Uses /v1/search/similar - DEPRECATED
}

// DELETE THIS (line 72-95):
func advancedSearch(author: String?, title: String?, isbn: String?) async throws -> [BookDTO] {
    // Uses /v1/search/advanced - DEPRECATED
}
```

#### ✅ Add: Unified Search
```swift
// FILE: API/BooksTrackAPI+Search.swift

enum SearchMode: String {
    case text = "text"
    case semantic = "semantic"
    case hybrid = "hybrid"
}

/// Unified V2 search - replaces all V1 search endpoints
func search(
    query: String,
    mode: SearchMode = .text,
    limit: Int = 20,
    offset: Int = 0
) async throws -> SearchResults {
    guard var urlComponents = URLComponents(
        url: baseURL.appendingPathComponent("/api/v2/search"),
        resolvingAgainstBaseURL: true
    ) else {
        throw APIError.invalidURL
    }
    
    urlComponents.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "mode", value: mode.rawValue),
        URLQueryItem(name: "limit", value: String(limit)),
        URLQueryItem(name: "offset", value: String(offset))
    ]
    
    guard let url = urlComponents.url else {
        throw APIError.invalidURL
    }
    
    let request = makeRequest(url: url)
    let (data, _) = try await performRequest(request: request)
    return try decodeEnvelope(SearchResults.self, from: data)
}

// Convenience methods for migration
func searchByISBN(_ isbn: String) async throws -> BookDTO? {
    let results = try await search(query: "isbn:\(isbn)", mode: .text, limit: 1)
    return results.results.first
}

func searchByTitle(_ title: String, limit: Int = 20) async throws -> [BookDTO] {
    let results = try await search(query: title, mode: .text, limit: limit)
    return results.results
}

func findSimilarBooks(to isbn: String, limit: Int = 10) async throws -> [BookDTO] {
    let results = try await search(
        query: "similar:\(isbn)",
        mode: .semantic,
        limit: limit
    )
    return results.results
}
```

---

### Phase 2: Enrichment API (Week 1)

#### ❌ Remove: Batch Enrich Fallback Logic
```swift
// FILE: API/BooksTrackAPI+Enrichment.swift

// DELETE THIS ENTIRE FUNCTION (line 25-55):
func enrichBatch(barcodes: [String]) async throws -> (jobId: String, authToken: String) {
    // Has fallback from /api/batch-enrich to /api/enrichment/batch
    // Both are DEPRECATED - use import workflow instead
}
```

#### ❌ Remove: Old Cancel Endpoint
```swift
// FILE: API/BooksTrackAPI+Enrichment.swift

// DELETE THIS (line 57-70):
func cancelJob(jobId: String, authToken: String) async throws -> JobCancellationResponse {
    // Uses /v1/jobs/:id - DEPRECATED
}
```

#### ✅ Update: Use V2 Cancel
```swift
// Already exists in BooksTrackAPI.swift - verify it uses V2 endpoint:
public func cancelEnrichmentJob(jobId: String) async throws -> JobCancellationResponse {
    // Should use: /api/v2/jobs/{jobId}/cancel
    // Currently using: /api/v2/jobs/{jobId}/cancel ✅
}
```

---

### Phase 3: Import Workflow (Week 2)

The import workflow is already using V2 endpoints. Verify and ensure SSE is working.

#### ✅ Keep: Current V2 Import Endpoints
```swift
// FILE: API/BooksTrackAPI+Import.swift

// These are correct ✅
func importCSV(data csvData: Data) async throws -> (jobId: String, authToken: String)
// Uses: POST /api/v2/imports

func getImportResults(jobId: String) async throws -> ImportResults
// Uses: GET /api/v2/imports/:jobId/results

func getJobStatus(jobId: String) async throws -> ImportJobStatus
// Uses: GET /api/v2/imports/:jobId
```

#### ✅ Add: SSE Progress Stream
```swift
// FILE: API/SSEClient.swift (NEW or UPDATE existing)

/// Server-Sent Events client for real-time progress
class SSEProgressClient {
    private let session: URLSession
    private var task: URLSessionDataTask?
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func connect(to url: URL, onEvent: @escaping (SSEEvent) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        task = session.dataTask(with: request)
        // ... implement SSE parsing
    }
    
    func disconnect() {
        task?.cancel()
        task = nil
    }
}

struct SSEEvent {
    let type: String  // "progress", "book_enriched", "complete", "error"
    let data: String  // JSON payload
}
```

---

### Phase 4: WebSocket Removal (Week 2)

WebSocket is replaced by SSE for progress tracking.

#### ❌ Remove: WebSocket Infrastructure
```swift
// FILES TO REMOVE OR DEPRECATE:
// - Common/GenericWebSocketHandler.swift
// - Common/WebSocketHelpers.swift
// - Common/WebSocketProgressManager.swift

// If these are still needed for other features, mark WebSocket progress as deprecated
```

#### ❌ Remove: Token Refresh
```swift
// The following endpoint is no longer needed with SSE:
// POST /api/token/refresh
// 
// SSE connections don't require token refresh - they're stateless HTTP
```

---

## DTO Updates

### Add: SearchResults DTO
```swift
// FILE: DTOs/SearchResultsDTO.swift (NEW)

struct SearchResults: Decodable {
    let results: [BookDTO]
    let total: Int
    let mode: String
    let query: String
}
```

### Update: Verify ResponseEnvelope
```swift
// FILE: DTOs/ResponseEnvelope.swift

// Ensure this matches the V2 contract:
struct ResponseEnvelope<T: Decodable>: Decodable {
    let success: Bool      // Discriminator
    let data: T?           // Null on error
    let metadata: ResponseMetadata
    let error: ApiErrorInfo?
}

struct ResponseMetadata: Decodable {
    let timestamp: String
    let source: String?
    let cached: Bool?
    let processingTime: Int?
}

struct ApiErrorInfo: Decodable {
    let code: String
    let message: String
    let details: AnyCodable?
    let retryable: Bool?
    let retryAfterMs: Int?
}
```

---

## Testing Checklist

### Before Deployment
- [ ] All V1 search endpoints removed
- [ ] Unified search working with all modes
- [ ] ISBN search returns correct results
- [ ] Semantic search working
- [ ] Single book enrichment working
- [ ] CSV import working
- [ ] SSE progress streaming working
- [ ] Job cancellation working
- [ ] No WebSocket code for progress
- [ ] No fallback endpoints in code

### API Contract Verification
```bash
# Test unified search
curl "https://api.oooefam.net/api/v2/search?q=harry+potter&mode=text&limit=5"

# Test ISBN search
curl "https://api.oooefam.net/api/v2/search?q=isbn:9780439064873"

# Test enrichment
curl -X POST "https://api.oooefam.net/api/v2/books/enrich" \
  -H "Content-Type: application/json" \
  -d '{"barcode":"9780439064873"}'

# Test capabilities
curl "https://api.oooefam.net/api/v2/capabilities"
```

---

## Timeline

| Week | Task | Owner |
|------|------|-------|
| Week 1 | Search API migration | iOS Team |
| Week 1 | Enrichment cleanup | iOS Team |
| Week 2 | SSE implementation | iOS Team |
| Week 2 | WebSocket removal | iOS Team |
| Week 3 | Testing & QA | Both |
| Week 4 | Production rollout | Both |

---

## Support

Questions? Issues?
- Backend: Check `docs/API_SYNC_V2.md` in bendv3
- OpenAPI: Use `docs/openapi-v2.yaml` for SDK generation
- Slack: #bookstrack-api channel

---

**Remember:** V1 endpoints will return `410 Gone` after March 1, 2026.
