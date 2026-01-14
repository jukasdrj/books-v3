# Batch Bookshelf Scanning Strategy

**Last Updated:** January 6, 2026

## Overview

Batch scanning allows users to capture multiple bookshelf photos (up to 5) in a single session. This document details the concurrency and rate-limiting strategy used to handle this load without crashing the app or the backend.

## Parallel vs. Serial Execution

To balance performance and reliability, we use a hybrid approach:

1.  **Parallel Uploads**: Photos are uploaded concurrently using `TaskGroup` to maximize bandwidth usage.
2.  **Serial Processing**: The backend processes images sequentially per job to avoid hitting Gemini API rate limits (TPM).

## Client-Side Logic

The `BookshelfScannerView` maintains a temporary `photoBuffer`.

```swift
// Logic flow
await withTaskGroup(of: String?.self) { group in
    for photo in photoBuffer {
        group.addTask {
            return try? await service.upload(photo)
        }
    }
}
```

## Duplicate Detection

Since a user might photograph the same book twice (overlap between shelf photos), the backend implements deduplication:

1.  **ISBN Match**: If two detected books have the same ISBN, they are merged.
2.  **Title/Author Fuzzy Match**: If confidence is high (>90%) and Title/Author match fuzzily, they are considered duplicates.

## Error Handling in Batches

If one photo fails (e.g., too blurry), the batch job **continues**. The final report includes a list of `failedImages` so the user knows which shelf to retake.

## Limits

*   **Max Batch Size**: 5 Images
*   **Total Payload Limit**: 50MB
