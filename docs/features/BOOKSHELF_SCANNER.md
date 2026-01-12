# Bookshelf AI Scanner

**Status:** ✅ Production Ready
**Implementation:** `BookshelfScannerView.swift`, `BookshelfAIService.swift`
**Backend:** Cloudflare Workers + Gemini 2.0 Flash Vision

## Overview

The Bookshelf AI Scanner uses computer vision to identify books from a single photo of a bookshelf. It leverages Gemini 2.0 Flash's multimodal capabilities to detect spines, read titles/authors, and match them to ISBNs.

## Key Features

- **Instant Recognition:** Identifies multiple books in a single pass.
- **Spine Reading:** Extracts text from varied spine orientations and fonts.
- **Format Detection:** Distinguishes between Hardcover, Paperback, and Mass Market (via `format` field).
- **Review Queue:** Low-confidence matches (<60%) are flagged for user review.

## Technical Implementation

### Frontend Flow

1. **Capture:** User takes a photo using `BookshelfScannerView`.
2. **Preprocessing:** Image is resized to max 3072px (long edge) and compressed to ~90% quality.
3. **Upload:** Image is uploaded to `/api/scan-bookshelf`.
4. **Processing:** Server sends image to Gemini Vision API.
5. **Updates:** Real-time WebSocket updates (`job_started`, `job_progress`, `job_complete`).

### Data Model

The scanner returns a list of `ScannedBook` objects:

```swift
struct ScannedBook: Codable {
    let title: String
    let author: String
    let isbn: String?
    let confidence: Float // 0.0 - 1.0
    let format: String?   // "hardcover", "paperback", "mass-market"
}
```

## Related Code

- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/BookshelfScannerView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
