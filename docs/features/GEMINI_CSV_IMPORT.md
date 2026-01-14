# Gemini AI CSV Import

**Feature Status:** Production (iOS)
**Last Updated:** January 6, 2026

## Overview

The Gemini AI CSV Import module (`GeminiCSVImport`) allows users to import book libraries from any CSV source without manual configuration. It uses Gemini 2.0 Flash to infer the schema of the uploaded file and map it to our internal `Book` model.

## Architecture

### Core Components

*   **`GeminiCSVImportView`**: The primary SwiftUI view managing the state machine (Upload -> Parsing -> Enrichment -> Review).
*   **`GeminiCSVImportService`**: Handles the multipart upload of the CSV file to the backend.
*   **`SSEClient`**: (Shared) Manages the Server-Sent Events connection to stream progress from the Cloudflare Worker backend.

### Data Flow

1.  **Selection**: User selects a CSV file via `UIDocumentPickerViewController`.
2.  **Upload**: File is uploaded to `/api/import/csv-gemini` via `GeminiCSVImportService`.
3.  **Parsing (Server-Side)**:
    *   Backend sends the CSV header and sample rows to Gemini 2.0 Flash.
    *   Gemini returns a mapped JSON structure.
4.  **Streaming**: The app listens to SSE events (`job_progress`, `job_complete`) to update the UI progress bar.
5.  **Enrichment**: Once parsed, the backend enriches ISBNs against Google Books/OpenLibrary.
6.  **Completion**: Results are returned, and the user can review/save.

## Technical Implementation

### Upload Service

The `GeminiCSVImportService` constructs a `multipart/form-data` request.

```swift
// Pseudocode representation
func uploadCSV(url: URL) async throws -> String {
    let request = URLRequest(url: Endpoint.csvImport)
    // ... boundary generation ...
    let (data, _) = try await URLSession.shared.upload(for: request, from: body)
    return jobId
}
```

### Zero-Config Logic

The "Zero Configuration" aspect is handled entirely by the backend prompt engineering. The iOS client is agnostic to the CSV structure. It expects a standardized `ParsedBook` array in the response.

## Error Handling

*   **`FILE_TOO_LARGE`**: Handled by checking file size before upload (< 10MB).
*   **`SSE_CONNECTION_LOST`**: The `SSEClient` attempts auto-reconnection with `Last-Event-ID`.

## Related Files

*   `GeminiCSVImport/GeminiCSVImportView.swift`
*   `GeminiCSVImport/GeminiCSVImportService.swift`
