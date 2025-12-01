# Books-v3 V2 API Migration Guide

**Date:** December 1, 2025
**Priority:** 🚨 CRITICAL - Complete before March 1, 2026
**Status:** ✅ COMPLETED - BookSearchAPIService Migrated to V2

---

## Overview

This guide migrates `BookSearchAPIService` from V1 endpoints to the unified V2 API. After this migration, books-v3 will be **100% V2 compliant**.

### Key Changes
1. All cover URLs now come from Alexandria (`https://alexandria.ooheynerds.com/covers/...`)
2. Single unified search endpoint replaces multiple V1 endpoints
3. Response format uses `ResponseEnvelope` with `data` wrapper
4. Field renamed: `coverImageURL` → `coverUrl`

---

## API Base URLs

```swift
// Production
let baseURL = "https://api.oooefam.net"

// Cover images (NEW - Alexandria CDN)
let coverBaseURL = "https://alexandria.ooheynerds.com/covers"
```

---

## Endpoint Migration Map

| Old V1 Endpoint | New V2 Endpoint | Notes |
|-----------------|-----------------|-------|
| `GET /v1/search/title?q=X` | `GET /api/v2/search?q=X` | Default mode is text |
| `GET /v1/search/isbn?isbn=X` | `GET /api/v2/search?q=isbn:X` | Use `isbn:` prefix |
| `GET /v1/search/advanced?title=X&author=Y` | `GET /api/v2/search?q=X&author=Y` | Combined query |
| `GET /v1/search/similar?isbn=X` | `GET /api/v2/search?q=X&mode=semantic` | Semantic search |
| `GET /v1/jobs/{jobId}/results` | `GET /api/v2/imports/{jobId}/results` | Unified results |
| `GET /v1/csv/status/{jobId}` | `GET /api/v2/imports/{jobId}` | Job status |
| `POST /v1/csv/cancel/{jobId}` | `DELETE /api/v2/jobs/{jobId}/cancel` | Cancel job |

---

## V2 Search API

### Endpoint
```
GET /api/v2/search
```

### Query Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | ✅ | Search query (supports prefixes) |
| `mode` | string | ❌ | `text` (default), `semantic`, `hybrid` |
| `limit` | int | ❌ | Max results (default: 20, max: 50) |
| `offset` | int | ❌ | Pagination offset |
| `author` | string | ❌ | Filter by author name |

### Query Prefixes
```
isbn:9780439064873     → ISBN lookup
author:rowling         → Author search  
title:harry potter     → Title search (explicit)
harry potter           → Title search (default)
```

### Response Format
```json
{
  "success": true,
  "data": {
    "results": [
      {
        "isbn": "9780439064873",
        "title": "Harry Potter and the Sorcerer's Stone",
        "author": "J.K. Rowling",
        "coverUrl": "https://alexandria.ooheynerds.com/covers/9780439064873/large",
        "publisher": "Scholastic",
        "publishedDate": "1998-09-01",
        "pageCount": 309,
        "description": "...",
        "subjects": ["Fantasy", "Young Adult"],
        "workKey": "/works/OL82563W"
      }
    ],
    "totalCount": 1,
    "query": "isbn:9780439064873",
    "mode": "text"
  },
  "metadata": {
    "timestamp": "2025-12-01T12:00:00Z",
    "cached": true,
    "provider": "alexandria"
  }
}
```

---

## Swift Implementation

### 1. Update BookDTO Model

```swift
// Models/BookDTO.swift

struct BookDTO: Codable, Identifiable {
    let isbn: String
    let title: String
    let author: String?
    let coverUrl: String?  // ← RENAMED from coverImageURL
    let publisher: String?
    let publishedDate: String?
    let pageCount: Int?
    let description: String?
    let subjects: [String]?
    let workKey: String?
    
    var id: String { isbn }
    
    // Convenience for SwiftUI Image loading
    var coverURL: URL? {
        guard let urlString = coverUrl else { return nil }
        return URL(string: urlString)
    }
    
    // Cover size variants (Alexandria CDN)
    func coverURL(size: CoverSize) -> URL? {
        guard let isbn = isbn.nilIfEmpty else { return nil }
        return URL(string: "https://alexandria.ooheynerds.com/covers/\(isbn)/\(size.rawValue)")
    }
    
    enum CoverSize: String {
        case small = "small"    // 100px width
        case medium = "medium"  // 200px width  
        case large = "large"    // 400px width
    }
}
```

### 2. Update ResponseEnvelope

```swift
// Models/ResponseEnvelope.swift

struct ResponseEnvelope<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: APIError?
    let metadata: ResponseMetadata?
}

struct ResponseMetadata: Codable {
    let timestamp: String?
    let cached: Bool?
    let provider: String?
}

struct APIError: Codable {
    let code: String
    let message: String
    let details: [String: String]?
}

// Search-specific response
struct SearchResponse: Codable {
    let results: [BookDTO]
    let totalCount: Int
    let query: String
    let mode: String?
}
```

### 3. Migrate BookSearchAPIService

```swift
// Services/BookSearchAPIService.swift

import Foundation

actor BookSearchAPIService {
    static let shared = BookSearchAPIService()
    
    private let baseURL = "https://api.oooefam.net"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Unified V2 Search
    
    /// Search books using V2 unified endpoint
    /// - Parameters:
    ///   - query: Search query (supports prefixes: isbn:, author:, title:)
    ///   - mode: Search mode (text, semantic, hybrid)
    ///   - limit: Max results (default 20)
    ///   - offset: Pagination offset
    func search(
        query: String,
        mode: SearchMode = .text,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SearchResponse {
        var components = URLComponents(string: "\(baseURL)/api/v2/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        guard let url = components.url else {
            throw SearchError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let envelope = try JSONDecoder().decode(
            ResponseEnvelope<SearchResponse>.self,
            from: data
        )
        
        guard envelope.success, let searchData = envelope.data else {
            throw SearchError.apiError(envelope.error?.message ?? "Unknown error")
        }
        
        return searchData
    }
    
    // MARK: - Convenience Methods
    
    /// Search by ISBN
    func searchByISBN(_ isbn: String) async throws -> BookDTO? {
        let response = try await search(query: "isbn:\(isbn)", limit: 1)
        return response.results.first
    }
    
    /// Search by title
    func searchByTitle(_ title: String, limit: Int = 20) async throws -> [BookDTO] {
        let response = try await search(query: title, limit: limit)
        return response.results
    }
    
    /// Search by author
    func searchByAuthor(_ author: String, limit: Int = 20) async throws -> [BookDTO] {
        let response = try await search(query: "author:\(author)", limit: limit)
        return response.results
    }
    
    /// Advanced search with title and author
    func advancedSearch(
        title: String?,
        author: String?,
        limit: Int = 20
    ) async throws -> [BookDTO] {
        var query = ""
        if let title = title, !title.isEmpty {
            query = title
        }
        if let author = author, !author.isEmpty {
            query += query.isEmpty ? "author:\(author)" : " author:\(author)"
        }
        
        guard !query.isEmpty else {
            throw SearchError.emptyQuery
        }
        
        let response = try await search(query: query, limit: limit)
        return response.results
    }
    
    /// Similar books (semantic search)
    func findSimilar(to isbn: String, limit: Int = 10) async throws -> [BookDTO] {
        let response = try await search(
            query: "isbn:\(isbn)",
            mode: .semantic,
            limit: limit
        )
        return response.results
    }
    
    // MARK: - Types
    
    enum SearchMode: String {
        case text
        case semantic
        case hybrid
    }
    
    enum SearchError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int)
        case apiError(String)
        case emptyQuery
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid search URL"
            case .invalidResponse:
                return "Invalid server response"
            case .httpError(let code):
                return "HTTP error: \(code)"
            case .apiError(let message):
                return message
            case .emptyQuery:
                return "Search query cannot be empty"
            }
        }
    }
}
```

### 4. Update SearchModel (SwiftUI)

```swift
// ViewModels/SearchModel.swift

import SwiftUI

@MainActor
class SearchModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [BookDTO] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var searchMode: BookSearchAPIService.SearchMode = .text
    
    private let searchService = BookSearchAPIService.shared
    private var searchTask: Task<Void, Never>?
    
    func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        
        // Cancel previous search
        searchTask?.cancel()
        
        searchTask = Task {
            isLoading = true
            error = nil
            
            do {
                let response = try await searchService.search(
                    query: query,
                    mode: searchMode
                )
                
                if !Task.isCancelled {
                    results = response.results
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    results = []
                }
            }
            
            isLoading = false
        }
    }
    
    func searchByISBN(_ isbn: String) async -> BookDTO? {
        do {
            return try await searchService.searchByISBN(isbn)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
```

### 5. Update Cover Image Loading

```swift
// Views/Components/BookCoverImage.swift

import SwiftUI

struct BookCoverImage: View {
    let book: BookDTO
    var size: BookDTO.CoverSize = .medium
    
    var body: some View {
        AsyncImage(url: book.coverURL(size: size)) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: frameWidth, height: frameHeight)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                // Fallback placeholder
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .frame(width: frameWidth, height: frameHeight)
                    .background(Color.gray.opacity(0.1))
            @unknown default:
                EmptyView()
            }
        }
        .cornerRadius(8)
    }
    
    private var frameWidth: CGFloat {
        switch size {
        case .small: return 50
        case .medium: return 100
        case .large: return 200
        }
    }
    
    private var frameHeight: CGFloat {
        frameWidth * 1.5  // Book aspect ratio
    }
}

// Usage in BookRow
struct BookRow: View {
    let book: BookDTO
    
    var body: some View {
        HStack(spacing: 12) {
            BookCoverImage(book: book, size: .small)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
```

---

## Migration Checklist

### Files Updated

**Search API Migration:**
- [x] `Services/BookSearchAPIService.swift` - Migrated to V2 unified endpoint
- [x] `SearchModel.swift` - Removed V1 feature flag logic
- [x] `FeatureFlags.swift` - V2 search enabled by default
- [x] V2 ResponseEnvelope format support added
- [x] Alexandria CDN cover URLs preserved

**Import/Job API Migration:**
- [x] `GeminiCSVImport/GeminiCSVImportView.swift` - Job results → `/api/v2/imports/{jobId}/results`
- [x] `GeminiCSVImport/GeminiCSVImportService.swift` - Status → `/api/v2/imports/{jobId}`, Cancel → `DELETE /api/v2/jobs/{jobId}/cancel`
- [x] `BookshelfScanning/Services/BookshelfAIService.swift` - Job results → `/api/v2/imports/{jobId}/results`
- [x] `Common/EnrichmentResultsClient.swift` - Job results → `/api/v2/imports/{jobId}/results`
- [x] `DTOs/WebSocketMessages.swift` - Updated deprecation comments

### Testing Checklist

- [ ] ISBN search returns book with Alexandria cover URL
- [ ] Title search returns paginated results
- [ ] Author search works with prefix
- [ ] Cover images load from Alexandria CDN
- [ ] Fallback placeholder shows on cover load failure
- [ ] Error states handled gracefully
- [ ] Offline/network error handling
- [ ] CSV import job status works
- [ ] CSV import job cancel works
- [ ] Bookshelf scan results fetch works

### Removed V1 Code

The following V1 code has been removed:
- `/v1/search/title` endpoint calls
- `/v1/search/isbn` endpoint calls
- `/v1/search/advanced` endpoint calls
- `/v1/search/similar` endpoint calls
- `/v1/jobs/{jobId}/results` endpoint calls
- `/v1/csv/status/{jobId}` endpoint calls
- `/v1/csv/cancel/{jobId}` endpoint calls (now DELETE method)
- `convertToSearchResults()` method (used V1 DTOs)
- V1 feature flag branching in SearchModel

---

## Cover URL Format

### Alexandria CDN URLs
```
https://alexandria.ooheynerds.com/covers/{isbn}/{size}

Sizes:
- small   (100px width)
- medium  (200px width)
- large   (400px width)
```

### Examples
```
https://alexandria.ooheynerds.com/covers/9780439064873/small
https://alexandria.ooheynerds.com/covers/9780439064873/medium
https://alexandria.ooheynerds.com/covers/9780439064873/large
```

### Fallback Behavior
If a cover doesn't exist in Alexandria R2 storage, the endpoint returns a 302 redirect to a placeholder image. The `AsyncImage` component handles this automatically.

---

## Error Handling

### HTTP Status Codes
| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Parse response |
| 400 | Bad request | Check query params |
| 404 | Not found | Show "no results" |
| 429 | Rate limited | Retry with backoff |
| 500+ | Server error | Show error, allow retry |

### Rate Limits
- Search: 100 req/min
- Enrichment: 30 req/min
- Cover images: Unlimited (CDN cached)

---

## Questions?

Contact backend team or see:
- `bendv3/docs/API_CONTRACT_V2.md`
- `alex/docs/COVER_API.md`
- OpenAPI spec: `https://api.oooefam.net/doc/openapi.json`
