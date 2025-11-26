# V2 Sync Book Enrichment Integration Guide

## Overview

The V2 book enrichment API (`POST /api/v2/books/enrich`) provides a synchronous, HTTP-based alternative to the WebSocket-based batch enrichment system. It's optimized for single-book lookups like barcode scanning.

## Benefits

✅ **Synchronous response** - No WebSocket tracking needed  
✅ **Simpler error handling** - Standard HTTP status codes  
✅ **Idempotency support** - Safe retries with duplicate detection  
✅ **Provider preference** - Choose between Google Books, OpenLibrary, or auto  
✅ **User-friendly errors** - 404 for "book not found", 429 for rate limits

## API Endpoint

```
POST https://api.oooefam.net/api/v2/books/enrich
Content-Type: application/json
```

### Request Payload

```json
{
  "barcode": "9780747532743",
  "prefer_provider": "auto",
  "idempotency_key": "scan_20251125_abc123"
}
```

### Success Response (200 OK)

```json
{
  "isbn": "9780747532743",
  "title": "Harry Potter and the Philosopher's Stone",
  "authors": ["J.K. Rowling"],
  "publisher": "Bloomsbury",
  "published_date": "1997-06-26",
  "page_count": 223,
  "cover_url": "https://...",
  "description": "Harry Potter has never been...",
  "provider": "orchestrated:google+openlibrary",
  "enriched_at": "2025-11-25T10:30:00Z"
}
```

### Error Responses

**404 Not Found:**
```json
{
  "error": "BOOK_NOT_FOUND",
  "message": "No book data found for ISBN",
  "providers_checked": ["google", "openlibrary"]
}
```

**429 Rate Limit:**
```json
{
  "error": "rate_limit_exceeded",
  "message": "Rate limit of 1000 requests per hour exceeded",
  "retry_after": 3600
}
```

## Usage Examples

### Example 1: Using EnrichmentAPIClient (Actor)

```swift
import Foundation

let apiClient = EnrichmentAPIClient()

Task {
    do {
        let response = try await apiClient.enrichBookV2(
            barcode: "9780747532743",
            preferProvider: "auto"
        )
        
        print("✅ Found: \(response.title) by \(response.authors.joined(separator: ", "))")
        
    } catch let error as EnrichmentV2Error {
        switch error {
        case .bookNotFound(let message, let providers):
            print("❌ \(message) (checked: \(providers.joined(separator: ", ")))")
            
        case .rateLimitExceeded(let retryAfter, let message):
            print("⏳ \(message) - retry in \(retryAfter)s")
            
        case .serviceUnavailable(let message):
            print("🚨 \(message)")
            
        case .invalidBarcode(let barcode):
            print("⚠️ Invalid ISBN: \(barcode)")
            
        case .invalidResponse, .httpError:
            print("🔥 Server error")
        }
    }
}
```

### Example 2: Using EnrichmentService (MainActor)

```swift
import SwiftData

@MainActor
func enrichAndAddBook(isbn: String, modelContext: ModelContext) async {
    let result = await EnrichmentService.shared.enrichWorkByISBN(
        isbn,
        in: modelContext
    )
    
    switch result {
    case .success:
        print("✅ Book enriched and added to library")
        
    case .failure(let error):
        switch error {
        case .noMatchFound:
            print("❌ Book not found in any provider")
            
        case .invalidQuery:
            print("⚠️ Invalid ISBN format")
            
        case .httpError(let statusCode):
            print("🚨 HTTP error: \(statusCode)")
            
        case .apiError(let message):
            print("🔥 API error: \(message)")
            
        default:
            print("❌ Enrichment failed")
        }
    }
}
```

### Example 3: Barcode Scanner Integration

Use the `ISBNScannerCoordinator` for a complete scan-to-add flow:

```swift
import SwiftUI

struct LibraryView: View {
    @State private var showingScanner = false
    
    var body: some View {
        Button("Scan Barcode") {
            showingScanner = true
        }
        .fullScreenCover(isPresented: $showingScanner) {
            ISBNScannerCoordinator()
        }
    }
}
```

Flow:
1. User scans ISBN barcode
2. V2 enrichment fetches book metadata (3-10 seconds)
3. QuickAddBookView shows enriched book details
4. User selects reading status and adds to library

### Example 4: Manual ISBN Entry

```swift
import SwiftUI

struct ManualISBNView: View {
    @State private var isbn = ""
    @State private var isEnriching = false
    @State private var enrichmentResponse: V2EnrichmentResponse?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            TextField("ISBN", text: $isbn)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
            
            Button("Look Up") {
                lookupISBN()
            }
            .disabled(isbn.isEmpty || isEnriching)
            
            if isEnriching {
                ProgressView("Looking up book...")
            }
            
            if let response = enrichmentResponse {
                Text(response.title)
                Text(response.authors.joined(separator: ", "))
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    private func lookupISBN() {
        isEnriching = true
        errorMessage = nil
        
        Task {
            let apiClient = EnrichmentAPIClient()
            do {
                let response = try await apiClient.enrichBookV2(barcode: isbn)
                enrichmentResponse = response
            } catch let error as EnrichmentV2Error {
                errorMessage = error.localizedDescription
            }
            isEnriching = false
        }
    }
}
```

## Error Handling Best Practices

### 1. User-Friendly Messages

```swift
func handleEnrichmentError(_ error: EnrichmentV2Error) -> String {
    switch error {
    case .bookNotFound(let message, let providers):
        return "We couldn't find this book in our databases (\(providers.joined(separator: ", "))). Try entering the details manually."
        
    case .rateLimitExceeded(let retryAfter, _):
        let minutes = retryAfter / 60
        return "You've scanned too many books! Please wait \(minutes) minute\(minutes == 1 ? "" : "s") and try again."
        
    case .serviceUnavailable:
        return "Our book database is temporarily unavailable. Please try again in a few minutes."
        
    case .invalidBarcode(let barcode):
        return "'\(barcode)' is not a valid ISBN. Make sure you're scanning the barcode on the back of the book."
        
    case .invalidResponse, .httpError:
        return "Something went wrong. Please try again."
    }
}
```

### 2. Retry Logic

```swift
func enrichWithRetry(isbn: String, maxAttempts: Int = 3) async throws -> V2EnrichmentResponse {
    let apiClient = EnrichmentAPIClient()
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await apiClient.enrichBookV2(barcode: isbn)
        } catch let error as EnrichmentV2Error {
            // Don't retry 404 (book not found) or 400 (invalid barcode)
            if case .bookNotFound = error { throw error }
            if case .invalidBarcode = error { throw error }
            
            lastError = error
            
            if attempt < maxAttempts {
                // Exponential backoff: 1s, 2s, 4s
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
            }
        }
    }
    
    throw lastError ?? EnrichmentV2Error.invalidResponse
}
```

### 3. Rate Limit Handling

```swift
actor RateLimitTracker {
    private var nextAvailableTime: Date?
    
    func canMakeRequest() -> Bool {
        guard let nextTime = nextAvailableTime else { return true }
        return Date() >= nextTime
    }
    
    func recordRateLimit(retryAfter: Int) {
        nextAvailableTime = Date().addingTimeInterval(TimeInterval(retryAfter))
    }
    
    func timeUntilAvailable() -> Int {
        guard let nextTime = nextAvailableTime else { return 0 }
        return max(0, Int(nextTime.timeIntervalSinceNow))
    }
}

let rateLimiter = RateLimitTracker()

func enrichWithRateLimitCheck(isbn: String) async throws -> V2EnrichmentResponse {
    // Check if we're rate limited
    if !await rateLimiter.canMakeRequest() {
        let waitTime = await rateLimiter.timeUntilAvailable()
        throw EnrichmentV2Error.rateLimitExceeded(
            retryAfter: waitTime,
            message: "Rate limit in effect"
        )
    }
    
    let apiClient = EnrichmentAPIClient()
    do {
        return try await apiClient.enrichBookV2(barcode: isbn)
    } catch let error as EnrichmentV2Error {
        if case .rateLimitExceeded(let retryAfter, _) = error {
            await rateLimiter.recordRateLimit(retryAfter: retryAfter)
        }
        throw error
    }
}
```

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Average Response Time | 3-10 seconds |
| p95 Response Time | < 15 seconds |
| Timeout | 30 seconds |
| Success Rate | > 95% |
| Rate Limit (Free) | 500 requests/hour |
| Rate Limit (Premium) | 5,000 requests/hour |

## Comparison: V2 vs V1 Batch Enrichment

| Feature | V2 Sync | V1 Batch (WebSocket) |
|---------|---------|----------------------|
| **Use Case** | Single book scan | Multi-book import |
| **Response Type** | Synchronous HTTP | Asynchronous WebSocket |
| **Latency** | 3-10 seconds | 5-60 seconds |
| **Progress Tracking** | Not needed | Real-time events |
| **Error Handling** | HTTP status codes | WebSocket messages |
| **Idempotency** | Built-in | Manual |
| **Connection Management** | Stateless | Stateful (reconnection) |
| **Battery Impact** | Minimal | Higher (persistent connection) |
| **Best For** | Barcode scanner, quick lookups | CSV imports, batch operations |

## Migration Path

### Current Code (V1 Batch)
```swift
// Old: Uses WebSocket for single book
let books = [Book(title: "", author: "", isbn: "9780747532743")]
let result = try await apiClient.startEnrichment(jobId: uuid, books: books)
// ... wait for WebSocket events ...
```

### New Code (V2 Sync)
```swift
// New: Direct HTTP request
let response = try await apiClient.enrichBookV2(barcode: "9780747532743")
// Immediate response with book data
```

## Testing

Run the test suite:
```bash
swift test --filter V2EnrichmentTests
```

Tests cover:
- DTO encoding/decoding
- Error message formatting
- Sendable conformance
- Rate limit calculations

## Security Considerations

### 1. Idempotency Keys

Idempotency keys are automatically generated with format:
```
scan_YYYYMMDD_<barcode>_<timestamp>
```

This prevents duplicate enrichments when retrying failed requests.

### 2. Rate Limiting

The backend enforces tiered rate limits:
- **Free users:** 500 requests/hour
- **Premium users:** 5,000 requests/hour

The client should track rate limit headers and show user-friendly countdown timers.

### 3. Input Validation

Always validate ISBNs before sending to the API:
```swift
switch ISBNValidator.validate(barcode) {
case .valid(let isbn):
    // Send to API
    try await apiClient.enrichBookV2(barcode: isbn.normalizedValue)
    
case .invalid:
    // Show error to user
    throw EnrichmentV2Error.invalidBarcode(barcode: barcode)
}
```

## Future Enhancements

### Planned Features
- ✅ Synchronous HTTP enrichment (LIVE)
- 🚧 Batch enrichment via V2 (planned)
- 🚧 Semantic search integration (planned)
- 🚧 Weekly recommendations (planned)

### Deprecation Timeline
- **V1 WebSocket:** Supported until March 2026
- **V2 HTTP:** Primary endpoint (current)
- **Migration deadline:** All clients must migrate by March 2026

## Support

For issues or questions:
1. Check the [API Contract V2 Spec](../../docs/API_CONTRACT_V2_PROPOSAL.md)
2. Review backend logs in Cloudflare Workers dashboard
3. Open an issue in the GitHub repository

## Example: Complete Barcode Scanner Flow

```swift
import SwiftUI
import SwiftData

@MainActor
struct BarcodeToLibraryFlow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingScanner = false
    
    var body: some View {
        Button("Scan & Add Book") {
            showingScanner = true
        }
        .fullScreenCover(isPresented: $showingScanner) {
            ISBNScannerCoordinator()
        }
    }
}
```

This provides:
1. Native barcode scanner (VisionKit)
2. V2 enrichment (3-10s)
3. Book preview with cover
4. Reading status selection
5. One-tap add to library
6. Automatic navigation to library

**Total time from scan to library: ~15 seconds** 🚀
