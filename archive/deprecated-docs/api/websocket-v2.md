# WebSocket v2.4 Contract

**Version:** 2.4.1
**Last Updated:** November 20, 2025
**Source of Truth:** `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/WebSocketMessages.swift`

This document defines the Unified WebSocket Message Schema for real-time operations in BooksTracker (AI Scanning, CSV Import, Enrichment).

## 🔌 Connection

**URL:** `wss://api.oooefam.net/ws/progress?jobId={UUID}`

### Headers (MANDATORY)

Connections **MUST** use HTTP/1.1 and provide authentication via the `Sec-WebSocket-Protocol` header.

```http
GET /ws/progress?jobId={jobId} HTTP/1.1
Host: api.oooefam.net
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Protocol: bookstrack-auth.{token}
```

> **iOS Note:** You must explicitly set `assumesHTTP3Capable = false` on `URLRequest` to force HTTP/1.1.

## 🔄 Protocol Flow

1. **Connect**: Client connects with `jobId` and auth token.
2. **Ready Signal**: Client sends `{"type": "ready"}` immediately after connection.
3. **Processing**: Server sends `ready_ack`, then `job_started`, `job_progress` updates.
4. **Completion**: Server sends `job_complete` (summary only).
5. **Results Fetch**: Client closes socket and fetches full results via REST API.

---

## 📨 Message Types

### Client -> Server

#### `ready`
Signal that the client is ready to receive events.
```json
{
  "type": "ready"
}
```

### Server -> Client

All messages follow the base structure:
```json
{
  "type": "string",
  "jobId": "uuid",
  "pipeline": "batch_enrichment | csv_import | ai_scan",
  "timestamp": 1678900000000,
  "version": "1.0.0",
  "payload": { ... }
}
```

#### `ready_ack`
Acknowledgment of readiness.
```json
{
  "type": "ready_ack",
  "payload": {
    "type": "ready_ack",
    "timestamp": 1678900000000
  }
}
```

#### `job_started`
Job has entered the processing queue.
```json
{
  "type": "job_started",
  "payload": {
    "type": "job_started",
    "totalCount": 100,
    "estimatedDuration": 60
  }
}
```

#### `job_progress`
Progress update.
```json
{
  "type": "job_progress",
  "payload": {
    "type": "job_progress",
    "progress": 0.45,
    "status": "processing_images",
    "processedCount": 45,
    "totalCount": 100,
    "keepAlive": true
  }
}
```

#### `job_complete`
Job finished. **Payload is pipeline-specific.**

**Batch Enrichment:**
```json
{
  "type": "job_complete",
  "pipeline": "batch_enrichment",
  "payload": {
    "pipeline": "batch_enrichment",
    "summary": {
      "totalProcessed": 10,
      "successCount": 9,
      "failureCount": 1,
      "duration": 5000,
      "resourceId": "job-results:uuid"
    },
    "expiresAt": "2025-11-21T10:00:00Z"
  }
}
```

**AI Scan:**
```json
{
  "type": "job_complete",
  "pipeline": "ai_scan",
  "payload": {
    "pipeline": "ai_scan",
    "summary": {
      "totalProcessed": 5,
      "successCount": 4,
      "failureCount": 1,
      "duration": 12000,
      "resourceId": "job-results:uuid",
      "totalDetected": 15,
      "approved": 10,
      "needsReview": 5
    },
    "expiresAt": "2025-11-21T10:00:00Z"
  }
}
```

#### `error`
Fatal error occurred.
```json
{
  "type": "error",
  "payload": {
    "type": "error",
    "code": "PROVIDER_TIMEOUT",
    "message": "Gemini API timed out",
    "retryable": true
  }
}
```

#### `reconnected`
State sync after connection drop.
```json
{
  "type": "reconnected",
  "payload": {
    "type": "reconnected",
    "progress": 0.5,
    "status": "resuming",
    "processedCount": 50,
    "totalCount": 100,
    "message": "Resumed session"
  }
}
```

---

## 📸 Batch Scanning (Pipeline: `ai_scan`)

For uploading multiple photos for bookshelf scanning.

#### `batch-init`
Batch session started.
```json
{
  "type": "batch-init",
  "payload": {
    "type": "batch-init",
    "totalPhotos": 3,
    "status": "uploading"
  }
}
```

#### `batch-progress`
Progress for photo processing.
```json
{
  "type": "batch-progress",
  "payload": {
    "type": "batch-progress",
    "currentPhoto": 1,
    "totalPhotos": 3,
    "photoStatus": "analyzing",
    "booksFound": 5,
    "totalBooksFound": 5,
    "photos": [
      { "index": 0, "status": "complete", "booksFound": 5 },
      { "index": 1, "status": "processing" }
    ]
  }
}
```

#### `batch-complete`
All photos processed.
```json
{
  "type": "batch-complete",
  "payload": {
    "type": "batch-complete",
    "totalBooks": 15,
    "photoResults": [...],
    "books": [...] // Array of DetectedBookPayload
  }
}
```

---

## 📦 Data Structures

### DetectedBookPayload
Used in `batch-complete` and AI Scan results.
```json
{
  "title": "The Hobbit",
  "author": "J.R.R. Tolkien",
  "isbn": "9780547928227",
  "confidence": 0.95,
  "boundingBox": { "x1": 0.1, "y1": 0.1, "x2": 0.5, "y2": 0.5 },
  "enrichment": {
    "status": "success",
    "work": { ... },
    "editions": [ ... ]
  }
}
```

### JobCompletionSummary
Lightweight summary returned in `job_complete`.
```json
{
  "totalProcessed": 100,
  "successCount": 98,
  "failureCount": 2,
  "duration": 45000,
  "resourceId": "job-results:uuid"
}
```

## ⚠️ Deprecations

- **Token in URL:** Sending `?token=` in the query string is deprecated. Use headers.
- **Full Payloads:** `job_complete` no longer contains the full results list. You MUST fetch `resourceId` via REST.
- **Legacy Enums:** `ScanStatus` strings are now normalized in the backend.
