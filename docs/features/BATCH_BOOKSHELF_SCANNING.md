# Batch Bookshelf Scanning

**Status:** ✅ Production Ready
**Implementation:** `CombinedImportView.swift`, `BookshelfAIService.swift`
**Backend:** Cloudflare Workers + Gemini 2.0 Flash Vision

## Overview

Batch Scanning allows users to digitize entire libraries by capturing multiple photos in sequence. The system handles parallel uploads and queues them for sequential processing to respect API rate limits.

## Key Features

- **Multi-Shot Capture:** Users can take up to 5 photos in one session.
- **Parallel Uploads:** Images are uploaded immediately in the background.
- **Sequential Processing:** The backend processes one image at a time per user session to ensure quality and avoid timeouts.
- **Deduplication:** Automatically removes duplicate books detected across overlapping photos.

## Workflow

1. **Session Start:** User enters "Batch Mode" in `CombinedImportView`.
2. **Capture Loop:** User takes photos (1/5, 2/5, etc.).
3. **Queueing:** Each photo is assigned a unique `batchId` and `photoId`.
4. **Processing:**
    - Images 1-5 are uploaded.
    - WebSocket channel subscribes to `batch-progress` events.
    - Results are aggregated locally as they arrive.
5. **Review:** User reviews a consolidated list of found books.

## Technical Details

- **Concurrency:** Uses Swift's `TaskGroup` for parallel uploads.
- **Rate Limiting:** Client-side throttling ensures we don't exceed the 5 req/min/IP limit for scanning endpoints.
- **State Management:** `BatchScanModel` (Observable) manages the state of multiple in-flight jobs.

## Related Code

- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/CombinedImportView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Models/BatchScanModel.swift` (Conceptual)
