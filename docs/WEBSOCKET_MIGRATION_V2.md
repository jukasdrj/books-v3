# WebSocket v2.0 Migration Guide - Summary-Only Completion Payloads

**Date:** November 20, 2025
**Breaking Change:** v2.0 (Deployed Nov 15, 2025)
**Migration Deadline:** January 15, 2026 (60 days)
**Status:** ⚠️ REQUIRED - All WebSocket clients must migrate

---

## 🔥 Critical Issue

**iOS Client Decoding Error:**
```
Could not decode any known JobCompletePayload type
```

**Root Cause:** iOS Swift structs are using the **old schema** (full data arrays) but backend migrated to **summary-only format** on Nov 15, 2025.

---

## What Changed

### Before (v1.x - DEPRECATED)

WebSocket `job_complete` messages included **full result arrays** (5-10 MB):

```json
{
  "type": "job_complete",
  "payload": {
    "type": "job_complete",
    "pipeline": "csv_import",
    "books": [/* 200+ book objects */],     // ❌ No longer sent
    "errors": [/* error objects */],        // ❌ No longer sent
    "successRate": "195/200"                // ❌ No longer sent
  }
}
```

**Problems:**
- 🐌 UI freezes (10+ seconds parsing 5-10 MB JSON on mobile)
- 🔋 Battery drain from intensive JSON parsing
- 📱 Memory pressure on low-end devices
- ⚠️ Risk of hitting Cloudflare 32 MiB message limit

### After (v2.0 - CURRENT)

WebSocket sends **lightweight summary** (< 1 KB), full results retrieved via HTTP:

```json
{
  "type": "job_complete",
  "payload": {
    "type": "job_complete",
    "pipeline": "csv_import",
    "summary": {                           // ✅ New summary object
      "totalProcessed": 200,
      "successCount": 195,
      "failureCount": 5,
      "duration": 2341,                    // Milliseconds
      "resourceId": "job-results:uuid"     // ✅ Key for HTTP fetch
    },
    "expiresAt": "2025-11-22T03:28:45Z"    // ✅ 24h expiry
  }
}
```

**Benefits:**
- ⚡ Instant WebSocket message parsing (< 1 KB)
- 🔋 Minimal battery impact
- 📦 Full results stored in KV cache (1-hour TTL)
- 🚀 Fetch only when needed (user taps to view details)

---

## Migration Steps

### Step 1: Add New Summary Structs

**File:** `WebSocketMessages.swift`

```swift
// ✅ NEW: Job Completion Summary (shared across all pipelines)
public struct JobCompletionSummary: Codable, Sendable {
    /// Total items processed (books parsed, photos scanned, etc.)
    public let totalProcessed: Int

    /// Number of successfully processed items
    public let successCount: Int

    /// Number of failed items
    public let failureCount: Int

    /// Job duration in milliseconds
    public let duration: Int

    /// KV cache key for fetching full results via HTTP
    /// Format: "job-results:{jobId}"
    /// Full results available at: GET /v1/jobs/{jobId}/results
    public let resourceId: String?
}

// ✅ NEW: AI Scan Summary (extends base summary with AI-specific stats)
public struct AIScanSummary: Codable, Sendable {
    // Base fields (same as JobCompletionSummary)
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int
    public let resourceId: String?

    // AI-specific fields
    public let totalDetected: Int?      // Books detected by Gemini Vision
    public let approved: Int?           // Auto-approved (high confidence)
    public let needsReview: Int?        // Requiring manual review (low confidence)
}
```

### Step 2: Update Completion Payload Structs

**Replace old structs** with new summary-based structs:

```swift
// ✅ CSV Import Completion (Summary-Only)
public struct CSVImportCompletePayload: Codable, Sendable {
    public let type: String                     // "job_complete"
    public let pipeline: String                 // "csv_import"
    public let summary: JobCompletionSummary    // ✅ NEW: Replaces books/errors/successRate
    public let expiresAt: String                // ISO 8601 timestamp (24h from completion)

    // ❌ REMOVED: These fields no longer exist
    // public let books: [ParsedBook]
    // public let errors: [ImportError]
    // public let successRate: String
}

// ✅ Batch Enrichment Completion (Summary-Only)
public struct BatchEnrichmentCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String                 // "batch_enrichment"
    public let summary: JobCompletionSummary    // ✅ NEW: Replaces enrichedBooks
    public let expiresAt: String

    // ❌ REMOVED:
    // public let totalProcessed: Int
    // public let successCount: Int
    // public let failureCount: Int
    // public let duration: Int
    // public let enrichedBooks: [EnrichedBookPayload]
}

// ✅ AI Scan Completion (Summary-Only with AI stats)
public struct AIScanCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String                 // "ai_scan"
    public let summary: AIScanSummary           // ✅ NEW: Extended summary with AI stats
    public let expiresAt: String

    // ❌ REMOVED:
    // public let totalDetected: Int
    // public let approved: Int
    // public let needsReview: Int
    // public let books: [DetectedBookPayload]
    // public let resultsUrl: String?
    // public let metadata: JobMetadata?
}
```

### Step 3: Update WebSocket Message Handler

**File:** Your WebSocket handler (e.g., `GenericWebSocketHandler.swift`)

```swift
func handleJobComplete(_ message: WebSocketMessage) async {
    guard case .jobComplete(let payload) = message.payload else { return }

    switch payload {
    case .csvImport(let csvPayload):
        await handleCSVImportComplete(
            jobId: message.jobId,
            summary: csvPayload.summary,
            expiresAt: csvPayload.expiresAt
        )

    case .batchEnrichment(let batchPayload):
        await handleBatchEnrichmentComplete(
            jobId: message.jobId,
            summary: batchPayload.summary,
            expiresAt: batchPayload.expiresAt
        )

    case .aiScan(let aiPayload):
        await handleAIScanComplete(
            jobId: message.jobId,
            summary: aiPayload.summary,
            expiresAt: aiPayload.expiresAt
        )
    }
}

// Example: CSV Import Handler
func handleCSVImportComplete(
    jobId: String,
    summary: JobCompletionSummary,
    expiresAt: String
) async {
    // Show summary UI immediately (no blocking parse)
    await MainActor.run {
        showCompletionSummary(
            total: summary.totalProcessed,
            success: summary.successCount,
            failed: summary.failureCount,
            duration: summary.duration
        )
    }

    // Fetch full results only when needed (e.g., user taps "View Details")
    if let resourceId = summary.resourceId {
        // Option 1: Fetch immediately
        await fetchAndDisplayFullResults(jobId: jobId)

        // Option 2: Lazy fetch (better UX)
        // Store jobId, fetch when user taps "View Books" button
        self.pendingJobId = jobId
    }
}

// Example: AI Scan Handler (with AI-specific stats)
func handleAIScanComplete(
    jobId: String,
    summary: AIScanSummary,
    expiresAt: String
) async {
    await MainActor.run {
        showAIScanSummary(
            detected: summary.totalDetected ?? 0,
            approved: summary.approved ?? 0,
            needsReview: summary.needsReview ?? 0
        )
    }

    // Fetch full book details when user opens review screen
    if let resourceId = summary.resourceId {
        self.pendingJobId = jobId
    }
}
```

### Step 4: Implement HTTP Results Fetching

**File:** New service (e.g., `JobResultsService.swift`)

```swift
import Foundation

public actor JobResultsService {
    private let baseURL = "https://api.oooefam.net"

    /// Fetch full job results via HTTP GET
    /// Results are cached in KV for 1 hour after job completion
    public func fetchResults(jobId: String) async throws -> JobResults {
        let url = URL(string: "\(baseURL)/v1/jobs/\(jobId)/results")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobError.invalidResponse
        }

        // Handle different status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - decode results
            let envelope = try JSONDecoder().decode(
                ResponseEnvelope<JobResults>.self,
                from: data
            )

            guard envelope.success, let results = envelope.data else {
                throw JobError.emptyResults
            }

            return results

        case 404:
            // Results expired (> 1 hour old)
            throw JobError.resultsExpired

        case 429:
            // Rate limited
            throw JobError.rateLimited

        default:
            throw JobError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// Job Results Container
public struct JobResults: Codable, Sendable {
    // CSV Import results
    public let books: [ParsedBook]?
    public let errors: [ImportError]?

    // Batch Enrichment results
    public let enrichedBooks: [EnrichedBookPayload]?

    // AI Scan results
    public let detectedBooks: [DetectedBookPayload]?
}

// Error types
public enum JobError: Error {
    case invalidResponse
    case emptyResults
    case resultsExpired          // Results no longer available in KV cache
    case rateLimited
    case httpError(statusCode: Int)
}
```

### Step 5: Handle Expiry Timestamp

The `expiresAt` field tells you when results expire from KV cache (24 hours):

```swift
func showExpiryCountdown(expiresAt: String) {
    guard let expiryDate = ISO8601DateFormatter().date(from: expiresAt) else {
        return
    }

    let timeRemaining = expiryDate.timeIntervalSinceNow

    if timeRemaining > 0 {
        // Results still available
        let hours = Int(timeRemaining / 3600)
        showMessage("Results available for \(hours) more hours")
    } else {
        // Results expired
        showMessage("Results expired. Please re-run the job.")
    }
}
```

---

## Migration Checklist

Use this checklist to ensure complete migration:

### WebSocket Structs
- [ ] Add `JobCompletionSummary` struct
- [ ] Add `AIScanSummary` struct (with AI-specific fields)
- [ ] Update `CSVImportCompletePayload` to use `summary` field
- [ ] Update `BatchEnrichmentCompletePayload` to use `summary` field
- [ ] Update `AIScanCompletePayload` to use `summary` field
- [ ] Remove all old direct fields (`books`, `errors`, `enrichedBooks`, etc.)

### Message Handling
- [ ] Update `handleJobComplete` to extract `summary` instead of direct fields
- [ ] Update CSV import handler to use `summary.totalProcessed`, `summary.successCount`, etc.
- [ ] Update batch enrichment handler to use `summary`
- [ ] Update AI scan handler to use `summary.totalDetected`, `summary.approved`, etc.
- [ ] Add `expiresAt` handling (show countdown timer or expiry warning)

### HTTP Results Fetching
- [ ] Create `JobResultsService` (or add to existing service)
- [ ] Implement `fetchResults(jobId:)` method
- [ ] Add error handling for 404 (expired), 429 (rate limited), etc.
- [ ] Create `JobResults` struct to hold full results
- [ ] Update UI to lazy-load full results (e.g., on "View Details" tap)

### Testing
- [ ] Test CSV import completion (verify summary decoding)
- [ ] Test batch enrichment completion
- [ ] Test AI scan completion (verify AI-specific stats)
- [ ] Test HTTP results fetching via `/v1/jobs/{jobId}/results`
- [ ] Test expired results (404 error after 1 hour)
- [ ] Test UI with summary-only data (no blocking parse)
- [ ] Test full results lazy loading (fetch on demand)

### Deployment
- [ ] Deploy updated iOS app with new structs
- [ ] Monitor crash logs for decoding errors
- [ ] Verify WebSocket messages decode successfully
- [ ] Verify HTTP results fetching works
- [ ] Complete migration before **January 15, 2026** deadline

---

## Testing Examples

### Test 1: CSV Import

```swift
// Send CSV import job, wait for completion
let jobId = await csvImportService.startImport(file: csvFile)

// WebSocket receives job_complete
// Verify: summary object exists and decodes correctly
XCTAssertNotNil(csvPayload.summary)
XCTAssertEqual(csvPayload.summary.totalProcessed, 200)
XCTAssertEqual(csvPayload.summary.successCount, 195)

// Fetch full results via HTTP
let results = try await jobResultsService.fetchResults(jobId: jobId)
XCTAssertEqual(results.books?.count, 195)
```

### Test 2: AI Scan

```swift
// Send photo scan job
let jobId = await aiScanService.startScan(photos: photos)

// WebSocket receives job_complete with AI stats
XCTAssertNotNil(aiPayload.summary.totalDetected)
XCTAssertEqual(aiPayload.summary.approved, 45)
XCTAssertEqual(aiPayload.summary.needsReview, 5)

// Fetch full book details
let results = try await jobResultsService.fetchResults(jobId: jobId)
XCTAssertEqual(results.detectedBooks?.count, 50)
```

---

## Rollback Plan (If Migration Blocked)

If you cannot migrate by the deadline (Jan 15, 2026), **you MUST contact the backend team immediately**.

**Temporary workaround (NOT RECOMMENDED):**
1. Backend team can enable a feature flag to send old format
2. This will re-introduce 5-10 MB WebSocket payloads (performance degradation)
3. You will have 30 additional days to migrate (final deadline: Feb 15, 2026)

**Contact:** Backend Team @ backend-team@bookstrack.com

---

## FAQ

**Q: Why can't we just update the structs without HTTP fetching?**
A: You'll get decoding errors because the backend no longer sends `books`, `errors`, or `enrichedBooks` fields. The summary is intentionally lightweight.

**Q: What if I need full results immediately?**
A: Fetch them via HTTP in `handleJobComplete`. The KV cache is fast (< 50ms P95). You can show a loading indicator.

**Q: How long are results available?**
A: 1 hour (3600 seconds) from job completion. Check `expiresAt` timestamp.

**Q: What happens after 1 hour?**
A: Results are purged from KV cache. HTTP GET returns 404. User must re-run the job.

**Q: Does this affect batch photo scanning?**
A: No! `batch-complete` messages still include full book arrays (1-5 photos only, not 200+).

**Q: Can I request a longer TTL than 1 hour?**
A: Yes, contact backend team. We can extend to 24 hours for specific use cases (uses more storage).

---

## Support

**Issues:** https://github.com/yourusername/bookstrack-backend/issues
**Slack:** #bookstrack-backend
**Email:** backend-team@bookstrack.com
**Migration Deadline:** January 15, 2026

---

**Last Updated:** November 20, 2025
**Document Owner:** Backend Team
**Version:** 1.0.0
