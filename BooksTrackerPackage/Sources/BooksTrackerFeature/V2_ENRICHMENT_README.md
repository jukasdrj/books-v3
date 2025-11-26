# V2 Book Enrichment Integration

Quick reference for using V2 synchronous book enrichment in BooksTrack.

## Quick Start

### 1. Barcode Scanner (Recommended)

Use the pre-built `ISBNScannerCoordinator` for the complete flow:

```swift
@State private var showingScanner = false

Button("Scan Book") {
    showingScanner = true
}
.fullScreenCover(isPresented: $showingScanner) {
    ISBNScannerCoordinator()
}
```

**Flow:**
1. User scans ISBN barcode
2. V2 API enriches book (3-10s)
3. Shows book preview with cover
4. User adds to library

### 2. Manual ISBN Lookup

For programmatic enrichment:

```swift
let apiClient = EnrichmentAPIClient()

Task {
    do {
        let book = try await apiClient.enrichBookV2(
            barcode: "9780747532743"
        )
        print("Found: \(book.title)")
    } catch let error as EnrichmentV2Error {
        print("Error: \(error.localizedDescription)")
    }
}
```

### 3. Add to Library

Use `EnrichmentService` to enrich and save to SwiftData:

```swift
@MainActor
func addBook(isbn: String) async {
    let result = await EnrichmentService.shared.enrichWorkByISBN(
        isbn,
        in: modelContext
    )
    
    if case .success = result {
        print("Added to library!")
    }
}
```

## Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| `EnrichmentAPIClient` | V2 API calls (actor) | `Common/EnrichmentAPIClient.swift` |
| `EnrichmentService` | Library integration (@MainActor) | `Enrichment/EnrichmentService.swift` |
| `ISBNScannerCoordinator` | Complete scan flow | `ISBNScannerCoordinator.swift` |
| `QuickAddBookView` | Add book UI | `QuickAddBookView.swift` |
| `V2EnrichmentDTOs.swift` | Request/response types | `DTOs/V2EnrichmentDTOs.swift` |

## Error Handling

V2 enrichment uses `EnrichmentV2Error`:

```swift
enum EnrichmentV2Error {
    case bookNotFound(message: String, providersChecked: [String])
    case rateLimitExceeded(retryAfter: Int, message: String)
    case serviceUnavailable(message: String)
    case invalidBarcode(barcode: String)
    case invalidResponse
    case httpError(statusCode: Int)
}
```

All cases conform to `LocalizedError` for user-friendly messages.

## Testing

Run V2 enrichment tests:

```bash
swift test --filter V2EnrichmentTests
```

Tests cover:
- DTO encoding/decoding
- Error messages
- Sendable compliance

## Backend Endpoint

```
POST https://api.oooefam.net/api/v2/books/enrich
```

See `docs/V2_ENRICHMENT_INTEGRATION_GUIDE.md` for full API documentation.

## When to Use V2 vs V1

**Use V2 (sync HTTP):**
- ✅ Barcode scanner (single book)
- ✅ Manual ISBN entry
- ✅ Quick book lookup
- ✅ Refresh existing book

**Use V1 (batch WebSocket):**
- ✅ CSV import (many books)
- ✅ Bulk operations
- ✅ Progress tracking needed

## Migration Status

- ✅ V2 endpoint: LIVE
- ✅ Client integration: Complete
- ⏳ V1 WebSocket: Supported until March 2026
