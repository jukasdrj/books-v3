# Gemini CSV Import

**Status:** ✅ Production Ready (v3.1.0+)
**Implementation:** `GeminiCSVImportService.swift`, `GeminiCSVImportView.swift`
**Backend:** Cloudflare Workers + Gemini 2.0 Flash

## Overview

The Gemini CSV Import feature leverages Google's Gemini 2.0 Flash model to intelligently parse CSV files without requiring user-defined column mapping. The system automatically detects headers, data types, and relationships (title, author, ISBN) and inserts them into the library.

## Key Features

- **Zero Configuration:** Users do not need to map columns (e.g., "Title" -> "book_title"). Gemini infers the schema.
- **Unified Enrichment:** Imported books enter the standard enrichment pipeline (metadata fetch, cover art).
- **Real-time Progress:** Server-Sent Events (SSE) provide row-by-row progress updates.
- **Error Handling:** Graceful handling of malformed rows or encoding issues.

## Technical Implementation

### Frontend Flow (`GeminiCSVImportView`)

1. **File Selection:** User selects a CSV file (max 10MB).
2. **Upload:** File is POSTed to `/v1/import/csv`.
3. **Job Creation:** Server returns a `jobId`.
4. **Progress Tracking:** Client connects to `wss://api.oooefam.net/ws/progress?jobId={jobId}`.
5. **Completion:** On `job_complete`, client fetches full results from `/v1/csv/results/{jobId}`.

### Backend Processing (Gemini 2.0 Flash)

1. **Parsing:** Gemini analyzes the first few rows to determine the schema.
2. **Extraction:** The entire CSV is processed to extract structured JSON data.
3. **Normalization:** Author names and genres are normalized against the canonical database.
4. **Persistence:** Books are inserted into the user's library.

### Constraints

- **File Size:** Max 10MB.
- **Row Limit:** ~5000 rows (soft limit based on timeout).
- **Format:** RFC 4180 compliant CSV.

## Related Code

- `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportView.swift`
