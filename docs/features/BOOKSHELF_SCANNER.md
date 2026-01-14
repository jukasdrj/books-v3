# Bookshelf AI Scanner

**Feature Status:** Production (iOS)
**Last Updated:** January 6, 2026

## Overview

The Bookshelf AI Scanner enables users to digitize physical libraries by photographing bookshelves. It utilizes VisionKit for text detection and Gemini 2.0 Flash for semantic understanding of spines (Title/Author extraction).

## Architecture

### Components

*   **`BookshelfScannerView`**: Main container view orchestration.
*   **`VisionProcessingActor`**: (Actor-isolated) Handles local image preprocessing (cropping, resizing) to prepare for upload.
*   **`BookshelfAIService`**: Manages the API communication with the `/api/scan-bookshelf` endpoints.
*   **`ScanResultsView`**: Displays the identified books and allows for manual correction.

### Logic Flow

1.  **Capture**: User takes 1-5 photos using `UIImagePickerController`.
2.  **Preprocessing (`VisionProcessingActor`)**:
    *   Images are resized to max 3072px.
    *   Quality compressed to 90% JPEG (~500KB).
3.  **Upload & Analysis**:
    *   Images are uploaded in batch.
    *   Job ID is returned.
4.  **Streaming Results**:
    *   SSE connection listens for `book_detected` events.
5.  **Review Queue**:
    *   Books with confidence < 60% (`ConfidenceThresholds.swift`) are flagged.

## Key Classes

### `DetectedBook`
Model representing a potential match.
```swift
struct DetectedBook: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String?
    let confidence: Double // 0.0 to 1.0
    var needsReview: Bool { confidence < 0.6 }
}
```

### `VisionProcessingActor`
Ensures image manipulation happens off the main thread to prevent UI stutter during the "Processing..." phase.

## Configuration

*   **Endpoint**: `/api/scan-bookshelf/batch`
*   **Max Photos**: 5 per session
*   **Timeout**: 60s per photo

## Related Documentation

*   [Batch Scanning Logic](./BATCH_BOOKSHELF_SCANNING.md)
*   [Product Requirements](../archive/Bookshelf-AI-Scanner-PRD.md)
