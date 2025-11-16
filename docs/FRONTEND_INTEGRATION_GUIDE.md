# BooksTrack API - Frontend Integration Guide

**Version:** 2.0
**Last Updated:** November 15, 2025
**Audience:** iOS and Flutter Development Teams
**Status:** Production-Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [HTTP API Contracts](#http-api-contracts)
4. [WebSocket API Contracts](#websocket-api-contracts)
5. [Canonical Data Models](#canonical-data-models)
6. [Authentication & Authorization](#authentication--authorization)
7. [Error Handling](#error-handling)
8. [Rate Limiting & Quotas](#rate-limiting--quotas)
9. [Caching Strategy](#caching-strategy)
10. [Performance Best Practices](#performance-best-practices)
11. [Testing & Environments](#testing--environments)
12. [Migration Guides](#migration-guides)
13. [Support & Resources](#support--resources)

---

## Overview

The BooksTrack API provides book metadata enrichment, ISBN lookups, bookshelf scanning, and batch processing capabilities. This guide covers all client integration patterns for mobile applications.

### Base URLs

| Environment | HTTP API | WebSocket API |
|-------------|----------|---------------|
| **Production** | `https://api.oooefam.net` | `wss://api.oooefam.net/ws/progress` |
| **Staging** | `https://staging-api.oooefam.net` | `wss://staging-api.oooefam.net/ws/progress` |
| **Local Dev** | `http://localhost:8787` | `ws://localhost:8787/ws/progress` |

### API Versions

- **Current:** v2.0 (December 1, 2025+)
- **Legacy:** v1.0 (Deprecated - sunset March 1, 2026)

---

## Quick Start

### 1. HTTP API Example (Book Search)

**Swift:**
```swift
struct SearchClient {
    func searchByISBN(_ isbn: String) async throws -> BookSearchResponse {
        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(isbn)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        // Check for error
        if let error = envelope.error {
            throw APIError.serverError(error.message)
        }

        // Extract data
        guard let data = envelope.data else {
            throw APIError.noData
        }

        return data
    }
}
```

**Flutter/Dart:**
```dart
class SearchClient {
  Future<BookSearchResponse> searchByISBN(String isbn) async {
    final url = 'https://api.oooefam.net/v1/search/isbn?isbn=$isbn';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw ApiException('HTTP ${response.statusCode}');
    }

    final envelope = ResponseEnvelope<BookSearchResponse>.fromJson(
      jsonDecode(response.body)
    );

    if (envelope.error != null) {
      throw ApiException(envelope.error!.message);
    }

    if (envelope.data == null) {
      throw ApiException('No data returned');
    }

    return envelope.data!;
  }
}
```

### 2. WebSocket Example (CSV Import Progress)

**Swift:**
```swift
class CSVImportClient {
    var webSocket: URLSessionWebSocketTask?

    func startImport(jobId: String, token: String, onProgress: @escaping (Double) -> Void) {
        let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)&token=\(token)")!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()

        receiveMessage(onProgress: onProgress)
    }

    private func receiveMessage(onProgress: @escaping (Double) -> Void) {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let message = try? JSONDecoder().decode(WebSocketMessage.self, from: data) {

                    switch message.type {
                    case "job_progress":
                        if let progress = message.payload.progress {
                            onProgress(progress)
                        }
                    case "job_complete":
                        print("Import complete!")
                    case "error":
                        print("Error: \(message.payload.error?.message ?? "Unknown")")
                    default:
                        break
                    }
                }
                self?.receiveMessage(onProgress: onProgress)
            case .failure(let error):
                print("WebSocket error: \(error)")
            default:
                break
            }
        }
    }
}
```

---

## HTTP API Contracts

### Universal Response Envelope

All `/v1/*` endpoints return responses in this format:

```typescript
{
  data: T | null,           // Payload (null on error)
  metadata: {
    timestamp: string,       // ISO 8601
    processingTime?: number, // Milliseconds
    provider?: string,       // "google_books" | "openlibrary" | "isbndb"
    cached?: boolean         // true if served from cache
  },
  error?: {                  // Present only on error
    message: string,         // Human-readable
    code?: string,           // Machine-readable (e.g., "NOT_FOUND")
    details?: any            // Optional context
  }
}
```

### Success Response Example

```json
{
  "data": {
    "works": [
      {
        "title": "The Great Gatsby",
        "subjectTags": ["fiction", "classic"],
        "firstPublicationYear": 1925,
        "coverImageURL": "https://..."
      }
    ],
    "editions": [...],
    "authors": [...]
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 145,
    "provider": "google_books",
    "cached": false
  }
}
```

### Error Response Example

```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 12
  },
  "error": {
    "message": "Book not found for ISBN 9780000000000",
    "code": "NOT_FOUND",
    "details": { "isbn": "9780000000000" }
  }
}
```

### Client-Side Error Detection

**Check for errors using EITHER pattern:**

1. **Check `error` field presence:**
   ```swift
   if let error = envelope.error {
       throw APIError.serverError(error.message)
   }
   ```

2. **Check `data` field for null:**
   ```swift
   guard let data = envelope.data else {
       throw APIError.noData
   }
   ```

### Key HTTP Endpoints

| Endpoint | Method | Description | Response Type |
|----------|--------|-------------|---------------|
| `/v1/search/isbn` | GET | Search by ISBN | `ResponseEnvelope<BookSearchResponse>` |
| `/v1/search/title` | GET | Search by title | `ResponseEnvelope<BookSearchResponse>` |
| `/v1/search/advanced` | GET | Combined search | `ResponseEnvelope<BookSearchResponse>` |
| `/v1/enrichment/batch` | POST | Batch enrichment | `ResponseEnvelope<EnrichmentJobInitResponse>` |
| `/v1/csv/import` | POST | CSV import | `ResponseEnvelope<CSVImportInitResponse>` |
| `/v1/scan/bookshelf` | POST | AI scan | `ResponseEnvelope<BookshelfScanInitResponse>` |
| `/v1/scan/results/{jobId}` | GET | Fetch scan results | `ResponseEnvelope<AIScanResults>` |
| `/v1/csv/results/{jobId}` | GET | Fetch CSV results | `ResponseEnvelope<CSVImportResults>` |

---

## WebSocket API Contracts

### Connection & Authentication

**WebSocket URL Pattern:**
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**Parameters:**
- `jobId`: Unique job identifier (returned from HTTP POST endpoints)
- `token`: WebSocket authentication token (returned from HTTP POST endpoints, expires in 2 hours)

### Message Envelope (All WebSocket Messages)

```typescript
{
  type: "job_started" | "job_progress" | "job_complete" | "error" | "ping" | "pong",
  jobId: string,
  pipeline: "batch_enrichment" | "csv_import" | "ai_scan",
  timestamp: number,        // Unix timestamp (milliseconds)
  version: string,          // "1.0.0"
  payload: MessagePayload   // Type-specific data
}
```

### Message Types

#### 1. `job_started`

**When:** Sent immediately after WebSocket connection established

```json
{
  "type": "job_started",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_started",
    "totalCount": 100,
    "estimatedDuration": 120
  }
}
```

#### 2. `job_progress`

**When:** Sent periodically during processing (throttled to avoid spam)

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
    "processedCount": 50,
    "currentItem": "Processing: The Great Gatsby"
  }
}
```

**Fields:**
- `progress`: 0.0 to 1.0 (for progress bar)
- `status`: Human-readable status message
- `processedCount`: Optional - items processed so far
- `currentItem`: Optional - current item being processed

#### 3. `job_complete` (Summary-Only)

**When:** Sent when job completes successfully

**⚠️ IMPORTANT:** Completion messages are **summary-only** (no large arrays). Full results are stored in KV and retrieved via HTTP GET.

```json
{
  "type": "job_complete",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_complete",
    "booksCount": 100,
    "resultsUrl": "/v1/csv/results/abc123",
    "successRate": "98/100"
  }
}
```

**Client Action:** Fetch full results via HTTP GET:
```
GET https://api.oooefam.net/v1/csv/results/abc123
```

**Why Summary-Only?**
- Large result arrays (5-10 MB) cause UI freezes on mobile
- WebSocket payloads are kept < 1 KB for instant parsing
- Results stored in KV with 24-hour TTL

#### 4. `error`

**When:** Sent when job fails

```json
{
  "type": "error",
  "jobId": "abc123",
  "pipeline": "csv_import",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "error",
    "code": "E_CSV_PROCESSING_FAILED",
    "message": "Invalid CSV format: Missing title column",
    "retryable": true,
    "details": {
      "lineNumber": 42
    }
  }
}
```

### WebSocket Close Codes

The server uses standard RFC 6455 close codes:

| Code | Name | Description | Client Action |
|------|------|-------------|---------------|
| 1000 | NORMAL_CLOSURE | Job completed successfully | No action needed |
| 1001 | GOING_AWAY | Server shutting down | Retry after 5 seconds |
| 1002 | PROTOCOL_ERROR | Malformed message | Fix client implementation |
| 1008 | POLICY_VIOLATION | Invalid token, auth failure | Re-authenticate |
| 1009 | MESSAGE_TOO_BIG | Payload > 32 MiB | Reduce payload size |
| 1011 | INTERNAL_ERROR | Server error | Retry with exponential backoff |
| 1013 | TRY_AGAIN_LATER | Server overload | Retry after 30 seconds |

---

## Canonical Data Models

All API responses use these canonical DTOs. **iOS Swift Codable structs should mirror these interfaces exactly.**

### WorkDTO (Abstract Creative Work)

```typescript
{
  title: string,                    // Required
  subjectTags: string[],            // Normalized genres (required, can be empty)

  // Optional metadata
  originalLanguage?: string,
  firstPublicationYear?: number,
  description?: string,
  coverImageURL?: string,

  // Provenance
  synthetic?: boolean,              // True if inferred from EditionDTO
  primaryProvider?: "google_books" | "openlibrary" | "isbndb",
  contributors?: string[],          // All providers that contributed data

  // External IDs (legacy - single values)
  openLibraryID?: string,
  openLibraryWorkID?: string,
  isbndbID?: string,
  googleBooksVolumeID?: string,
  goodreadsID?: string,

  // External IDs (modern - arrays)
  goodreadsWorkIDs: string[],
  amazonASINs: string[],
  librarythingIDs: string[],
  googleBooksVolumeIDs: string[],

  // Quality metrics
  lastISBNDBSync?: string,          // ISO 8601
  isbndbQuality: number,            // 0-100

  // Review metadata (for AI-detected books)
  reviewStatus: "pending" | "approved" | "rejected" | "needs_review",
  originalImagePath?: string,
  boundingBox?: {
    x: number,
    y: number,
    width: number,
    height: number
  }
}
```

### EditionDTO (Physical/Digital Manifestation)

```typescript
{
  // Identifiers
  isbn?: string,                    // Primary ISBN
  isbns: string[],                  // All ISBNs (required, can be empty)

  // Core metadata
  title?: string,
  publisher?: string,
  publicationDate?: string,         // YYYY-MM-DD or YYYY
  pageCount?: number,
  format: "hardcover" | "paperback" | "ebook" | "audiobook" | "unknown",
  coverImageURL?: string,
  editionTitle?: string,
  editionDescription?: string,      // Note: Not 'description' (Swift @Model reserved keyword)
  language?: string,

  // Provenance
  primaryProvider?: string,
  contributors?: string[],

  // External IDs
  openLibraryID?: string,
  openLibraryEditionID?: string,
  isbndbID?: string,
  googleBooksVolumeID?: string,
  goodreadsID?: string,
  amazonASINs: string[],
  googleBooksVolumeIDs: string[],
  librarythingIDs: string[],

  // Quality metrics
  lastISBNDBSync?: string,
  isbndbQuality: number             // 0-100
}
```

### AuthorDTO

```typescript
{
  // Required
  name: string,
  gender: "male" | "female" | "non_binary" | "unknown",

  // Optional
  culturalRegion?: "western" | "eastern" | "african" | "latin_american" | "middle_eastern" | "other",
  nationality?: string,
  birthYear?: number,
  deathYear?: number,

  // External IDs
  openLibraryID?: string,
  isbndbID?: string,
  googleBooksID?: string,
  goodreadsID?: string,

  // Statistics
  bookCount?: number
}
```

### BookSearchResponse

```typescript
{
  works: WorkDTO[],
  editions: EditionDTO[],
  authors: AuthorDTO[],
  totalResults?: number             // For pagination (future)
}
```

---

## Authentication & Authorization

### WebSocket Token Authentication

1. **Obtain Token:** POST endpoints return `{ jobId, token }` in response
2. **Connect:** Use token in WebSocket URL query parameter
3. **Token Expiration:** 2 hours (7200 seconds)
4. **Token Refresh:** Available within 30-minute window before expiration

**Token Refresh Example (Swift):**
```swift
func refreshToken(jobId: String, oldToken: String) async throws -> String {
    let url = URL(string: "https://api.oooefam.net/v1/token/refresh")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["jobId": jobId, "oldToken": oldToken]
    request.httpBody = try JSONEncoder().encode(body)

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode([String: String].self, from: data)

    guard let newToken = response["token"] else {
        throw APIError.invalidResponse
    }

    return newToken
}
```

### API Key Authentication (Future)

⚠️ Not yet implemented. Currently, all HTTP endpoints are public (rate-limited by IP).

---

## Error Handling

### HTTP Error Codes

| Code | Meaning | Client Action |
|------|---------|---------------|
| 200 | Success | Parse `data` field |
| 202 | Accepted | Job started, listen on WebSocket |
| 400 | Bad Request | Fix request parameters |
| 401 | Unauthorized | Re-authenticate |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 429 | Too Many Requests | Back off, retry after header value |
| 500 | Internal Server Error | Retry with exponential backoff |
| 503 | Service Unavailable | Server overload, retry after 30s |

### Error Codes (envelope.error.code)

| Code | Description | Retryable |
|------|-------------|-----------|
| `NOT_FOUND` | Resource not found | No |
| `INVALID_ISBN` | Invalid ISBN format | No |
| `INVALID_QUERY` | Invalid query parameters | No |
| `E_CSV_PROCESSING_FAILED` | CSV parsing failed | Yes |
| `E_AI_SCAN_FAILED` | AI vision processing failed | Yes |
| `E_BATCH_PROCESSING_FAILED` | Batch enrichment failed | Yes |
| `E_PROVIDER_TIMEOUT` | External API timeout | Yes |
| `E_RATE_LIMIT_EXCEEDED` | Rate limit exceeded | Yes (with backoff) |

### Error Handling Best Practices

**Swift:**
```swift
enum APIError: Error {
    case noData
    case invalidResponse
    case serverError(String)
    case rateLimit(retryAfter: Int)
    case networkError(Error)
}

func handleAPIError(_ envelope: ResponseEnvelope<Any>) throws {
    guard let error = envelope.error else { return }

    // Check if retryable
    if let retryable = error.details?["retryable"] as? Bool, retryable {
        // Retry with exponential backoff
        throw APIError.serverError("Retryable error: \(error.message)")
    } else {
        // Show error to user
        throw APIError.serverError(error.message)
    }
}
```

---

## Rate Limiting & Quotas

### Rate Limits (Per IP)

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Search endpoints | 100 requests | 1 minute |
| Batch endpoints | 10 requests | 1 minute |
| AI scan endpoints | 5 requests | 1 minute |
| Global limit | 1000 requests | 1 hour |

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1700000060
```

### Handling Rate Limits

**Swift:**
```swift
func handleRateLimit(response: HTTPURLResponse) -> Int? {
    guard response.statusCode == 429 else { return nil }

    if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
       let seconds = Int(retryAfter) {
        return seconds
    }

    return 60  // Default 60 seconds
}
```

---

## Caching Strategy

### Server-Side Caching

- **Book metadata:** 24 hours (KV cache)
- **ISBN lookups:** 7 days
- **Cover images:** 30 days
- **CSV parsing:** 7 days (by file hash)
- **AI scan results:** 24 hours

### Client-Side Caching Recommendations

1. **HTTP Responses:** Cache for 1 hour (honor `Cache-Control` headers)
2. **Images:** Cache cover images indefinitely (they don't change)
3. **Search Results:** Cache for 5 minutes
4. **WebSocket Results:** Fetch once, cache locally for session

**Swift URLSession Cache Example:**
```swift
let config = URLSessionConfiguration.default
config.urlCache = URLCache(
    memoryCapacity: 50 * 1024 * 1024,  // 50 MB memory
    diskCapacity: 100 * 1024 * 1024,   // 100 MB disk
    directory: nil
)
config.requestCachePolicy = .returnCacheDataElseLoad

let session = URLSession(configuration: config)
```

---

## Performance Best Practices

### 1. Summary-Only WebSocket Completions

**❌ Old Pattern (Don't Do This):**
```swift
// Waiting for 5 MB JSON array in WebSocket message
let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
let books = message.payload.books  // UI freezes for 10+ seconds
```

**✅ New Pattern (Do This):**
```swift
// Step 1: Receive lightweight summary via WebSocket
let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
let resultsUrl = message.payload.resultsUrl

// Step 2: Fetch full results via HTTP GET (async, paginated)
let results = try await fetchResults(url: resultsUrl)
```

### 2. Pagination (Future)

Currently, all results are returned in a single response. Pagination will be added in Q1 2026.

### 3. Batch Requests

For bulk operations, use batch endpoints instead of looping individual requests:

**❌ Don't:**
```swift
for isbn in isbns {
    let book = try await searchByISBN(isbn)  // 100 requests
}
```

**✅ Do:**
```swift
let jobId = try await startBatchEnrichment(isbns: isbns)  // 1 request
listenForProgress(jobId: jobId)
```

### 4. Connection Pooling

Reuse `URLSession` instances across requests (default behavior in iOS).

---

## Testing & Environments

### Staging Environment

**Purpose:** Test API integration before production deployment

**Base URL:** `https://staging-api.oooefam.net`

**Differences from Production:**
- Same API contract
- May have newer features
- May have test data
- Faster deployment cycle

**Configuration Example:**
```swift
#if STAGING
let baseURL = "https://staging-api.oooefam.net"
#else
let baseURL = "https://api.oooefam.net"
#endif
```

### Unit Testing

**Mock Response Example (Swift):**
```swift
let mockResponse = """
{
  "data": {
    "works": [{"title": "Test Book", "subjectTags": ["test"]}],
    "editions": [],
    "authors": []
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "provider": "google_books",
    "cached": false
  }
}
"""

let data = mockResponse.data(using: .utf8)!
let envelope = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)
```

---

## Migration Guides

### HTTP API v1 → v2 Migration

**Breaking Changes:**
1. Response envelope changed from `{success, data, meta}` to `{data, metadata, error}`
2. Error detection: `response.error !== undefined` instead of `response.success === false`
3. Metadata renamed: `meta` → `metadata`

**Migration Steps:**
1. Update response models to use `ResponseEnvelope<T>`
2. Change error detection logic
3. Update metadata field access
4. Test against staging environment

**See:** `/docs/API_CONTRACT_V2.md` for full migration details

### WebSocket v1 → v2 Migration

**Breaking Changes:**
1. RPC methods removed (event-driven only)
2. Message format changed (added `pipeline`, `version`, `timestamp`)
3. Completion messages are summary-only (full results via HTTP GET)

**Migration Steps:**
1. Remove polling logic
2. Update message models
3. Implement HTTP GET for full results
4. Test against staging WebSocket

**See:** `/docs/WEBSOCKET_MIGRATION_IOS.md` for full migration guide

---

## Support & Resources

### Documentation

- **API Contract:** `/docs/API_CONTRACT_V2.md`
- **WebSocket Migration:** `/docs/WEBSOCKET_MIGRATION_IOS.md`
- **Canonical Models:** `/src/types/canonical.ts`
- **WebSocket Messages:** `/src/types/websocket-messages.ts`
- **Response Envelopes:** `/src/types/responses.ts`

### Testing Tools

- **Staging API:** `https://staging-api.oooefam.net`
- **WebSocket Testing:** `wscat -c "wss://staging-api.oooefam.net/ws/progress?jobId=test&token=test"`
- **HTTP Testing:** Postman collection (available on request)

### Contact & Support

| Channel | Purpose | Response Time |
|---------|---------|---------------|
| **Slack:** `#bookstrack-api-support` | General questions, integration help | < 4 hours (business hours) |
| **Email:** api-support@oooefam.net | Non-urgent technical issues | < 24 hours |
| **GitHub Issues:** [bookstrack-backend/issues](https://github.com) | Bug reports, feature requests | < 48 hours |
| **Emergency:** engineering-oncall@oooefam.net | Production outages only | < 15 minutes |

### Status Page

**Production Monitoring:** `https://status.oooefam.net` (coming soon)

---

## Appendix A: Complete Swift Example

**SearchClient.swift:**
```swift
import Foundation

// MARK: - Models

struct ResponseEnvelope<T: Decodable>: Decodable {
    let data: T?
    let metadata: ResponseMetadata
    let error: APIError?
}

struct ResponseMetadata: Decodable {
    let timestamp: String
    let processingTime: Int?
    let provider: String?
    let cached: Bool?
}

struct APIError: Decodable {
    let message: String
    let code: String?
    let details: [String: AnyCodable]?
}

struct BookSearchResponse: Decodable {
    let works: [WorkDTO]
    let editions: [EditionDTO]
    let authors: [AuthorDTO]
}

struct WorkDTO: Decodable {
    let title: String
    let subjectTags: [String]
    let coverImageURL: String?
    let firstPublicationYear: Int?
}

struct EditionDTO: Decodable {
    let isbn: String?
    let publisher: String?
    let publicationDate: String?
}

struct AuthorDTO: Decodable {
    let name: String
}

// MARK: - Client

class BooksTrackClient {
    let baseURL: String

    init(baseURL: String = "https://api.oooefam.net") {
        self.baseURL = baseURL
    }

    func searchByISBN(_ isbn: String) async throws -> BookSearchResponse {
        let url = URL(string: "\(baseURL)/v1/search/isbn?isbn=\(isbn)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BooksTrackError.invalidResponse
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        if let error = envelope.error {
            throw BooksTrackError.serverError(error.message)
        }

        guard let data = envelope.data else {
            throw BooksTrackError.noData
        }

        return data
    }
}

enum BooksTrackError: Error {
    case invalidResponse
    case serverError(String)
    case noData
}
```

---

**Document Version:** 2.0
**Last Updated:** November 15, 2025
**Maintainer:** BooksTrack Backend Team (@jukasdrj)
