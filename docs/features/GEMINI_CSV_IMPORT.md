# Gemini CSV Import

**Status:** Production | **AI Model:** Gemini 2.0 Flash | **Capacity:** 10MB Files

The Gemini CSV Import feature uses Generative AI to parse and import unstructured or non-standard CSV files. Unlike traditional importers that require strict column mapping, this feature auto-detects schemas and handles data cleaning on the fly.

---

## 🚀 Core Features

### 1. "Zero-Config" Import
- **Input:** Any CSV/TSV file (up to 10MB).
- **Schema Detection:** Gemini 2.0 analyzes the first 50 rows to infer column headers (e.g., mapping "Book Name" -> `title`).
- **Data Cleaning:** Normalizes ISBNs (removes dashes), formats dates, and fixes common encoding errors.

### 2. Real-Time Progress
- **WebSocket/SSE:** The backend streams row-by-row progress updates.
- **Visual Feedback:** A progress bar shows the current stage: `Uploading` -> `Analyzing` -> `Processing` -> `Enriching`.

### 3. Unified Enrichment
- Imported records are immediately queued for background enrichment (cover images, metadata).
- Uses the `Insert-Before-Relate` pattern to ensure data integrity during high-volume writes.

---

## 🏗️ Architecture

### Client-Side (iOS)
- **`GeminiCSVImportView`**: UI for file selection and progress monitoring.
- **`GeminiCSVImportService`**: Handles file upload and SSE connection.
    - **Retry Logic:** 3-attempt exponential backoff for connection failures.
    - **Fallback:** Polling mechanism if WebSocket is blocked.

### Backend (Cloudflare Workers)
- **Endpoint:** `POST /v2/import/csv`.
- **Flow:**
    1.  **Upload:** File is stored in R2 (temp bucket).
    2.  **Analyze:** Gemini reads the header and sample rows to generate a parsing schema.
    3.  **Process:** Workers durable objects process the file in chunks.
    4.  **Stream:** Progress events sent via `POST /ws/progress` channel.

---

## 🛡️ Security & Limits

- **File Size:** Max 10MB.
- **Validation:** Server checks MIME type and scans for malicious payloads.
- **Privacy:** User data is processed transiently and deleted after import.

---

## 🛠️ Usage

### User Flow
1.  Go to **Settings** -> **Import/Export**.
2.  Select **Import from CSV**.
3.  Pick a file from the iOS Files app.
4.  Watch the AI magic happen.

### Code Snippet (Service)
```swift
func importCSV(url: URL) async throws {
    let jobId = try await uploadFile(url)

    // Connect to progress stream
    for try await event in SSEClient.connect(jobId: jobId) {
        handleProgress(event)
    }
}
```
