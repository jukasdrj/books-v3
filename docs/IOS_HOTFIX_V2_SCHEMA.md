# iOS Hotfix: WebSocket v2.0 Schema Compatibility

**Issue:** iOS app crashes on `job_complete` messages due to missing `expiresAt` field in Swift decoders
**Status:** 🔥 **CRITICAL** - Production crash affecting all CSV imports
**Fix Type:** Backward-compatible hotfix (makes `expiresAt` optional)
**Timeline:** Deploy immediately to restore iOS functionality

---

## The Problem

**Backend (v2.0 - deployed Nov 15, 2025):**
```json
{
  "type": "job_complete",
  "payload": {
    "summary": {...},
    "expiresAt": "2025-11-22T03:49:51.876Z"  // ✅ Backend sends this
  }
}
```

**iOS App (v1.0 - current production):**
```swift
struct CSVImportCompletePayload: Codable {
    let summary: JobCompletionSummary
    // ❌ Missing expiresAt field → decoder crashes
}
```

**Error:**
```
dataCorrupted: Could not decode any known JobCompletePayload type
Raw message: {...,"expiresAt":"2025-11-22T03:49:51.876Z"}
```

---

## The Fix: Make `expiresAt` Optional

Update all job completion payload structs to make `expiresAt` **optional**. This allows the iOS app to work with both old and new backend versions.

### Step 1: Update Shared Summary Struct

```swift
// ✅ HOTFIX: Job Completion Summary (backward compatible)
public struct JobCompletionSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int           // Milliseconds
    public let resourceId: String?     // KV key for HTTP fetch (optional)
}
```

### Step 2: Update All Completion Payload Structs

**CSV Import:**
```swift
// ✅ HOTFIX: CSV Import Completion (backward compatible)
public struct CSVImportCompletePayload: Codable, Sendable {
    public let type: String            // "job_complete"
    public let pipeline: String        // "csv_import"
    public let summary: JobCompletionSummary
    public let expiresAt: String?      // ✅ HOTFIX: Make optional (was required)
}
```

**Batch Enrichment:**
```swift
// ✅ HOTFIX: Batch Enrichment Completion (backward compatible)
public struct BatchEnrichmentCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: JobCompletionSummary
    public let expiresAt: String?      // ✅ HOTFIX: Make optional
}
```

**AI Scan:**
```swift
// ✅ HOTFIX: AI Scan Completion (backward compatible)
public struct AIScanCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: AIScanSummary  // Extended summary
    public let expiresAt: String?      // ✅ HOTFIX: Make optional
}

// AI Scan Summary (unchanged)
public struct AIScanSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int
    public let resourceId: String?

    // AI-specific stats
    public let totalDetected: Int?
    public let approved: Int?
    public let needsReview: Int?
}
```

### Step 3: Update WebSocket Message Handler (Optional Enhancement)

You can optionally use `expiresAt` to show TTL warnings in the UI:

```swift
func handleJobComplete(_ message: WebSocketMessage) async {
    guard case .jobComplete(let payload) = message.payload else { return }

    switch payload {
    case .csvImport(let csvPayload):
        let summary = csvPayload.summary
        print("CSV import complete: \(summary.successCount)/\(summary.totalProcessed) books")

        // ✅ OPTIONAL: Use expiresAt for TTL warnings
        if let expiresAt = csvPayload.expiresAt {
            let expiryDate = ISO8601DateFormatter().date(from: expiresAt)
            print("Results expire at: \(expiryDate)")
        }

        // Fetch full results via HTTP if available
        if let resourceId = summary.resourceId {
            await fetchJobResults(jobId: message.jobId)
        }

    case .batchEnrichment(let batchPayload):
        // Same pattern...

    case .aiScan(let aiPayload):
        // Same pattern...
    }
}
```

---

## Testing Checklist

- [ ] **Backward Compatibility:** iOS app decodes old messages (without `expiresAt`)
- [ ] **Forward Compatibility:** iOS app decodes new messages (with `expiresAt`)
- [ ] **CSV Import:** Test full CSV import flow end-to-end
- [ ] **Batch Enrichment:** Test batch enrichment completion
- [ ] **AI Scan:** Test bookshelf scan completion
- [ ] **Error Handling:** Verify no crashes on malformed messages

---

## Verification

After deploying the hotfix, verify with these test cases:

**Test 1: Old Backend (v1.0) - No expiresAt**
```json
{
  "payload": {
    "summary": {"totalProcessed": 48, "successCount": 48, "failureCount": 0, "duration": 349}
    // No expiresAt field
  }
}
```
**Expected:** ✅ Decodes successfully (optional field is nil)

**Test 2: New Backend (v2.0) - With expiresAt**
```json
{
  "payload": {
    "summary": {...},
    "expiresAt": "2025-11-22T03:49:51.876Z"
  }
}
```
**Expected:** ✅ Decodes successfully (optional field has value)

---

## Migration Timeline

| Date | Action |
|------|--------|
| **Nov 15, 2025** | Backend v2.0 deployed (breaking change announced) |
| **Nov 20, 2025** | iOS crash discovered in production |
| **Nov 20, 2025** | **🔥 Deploy this hotfix immediately** |
| **Jan 15, 2026** | Migration deadline (60 days) - remove optional `?` if desired |

---

## Why This Fix Works

### Backward Compatibility ✅
```swift
// Old backend sends: { "summary": {...} }
// iOS decodes: expiresAt = nil (optional)
```

### Forward Compatibility ✅
```swift
// New backend sends: { "summary": {...}, "expiresAt": "..." }
// iOS decodes: expiresAt = "2025-11-22T03:49:51.876Z" (has value)
```

### Future-Proof ✅
```swift
// After migration deadline (Jan 15, 2026), you can:
// 1. Keep it optional (safest)
// 2. Make it required: public let expiresAt: String (if all backends are v2.0+)
```

---

## Alternative: Custom Decoder (Advanced)

If you want more control, implement a custom decoder:

```swift
public struct CSVImportCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: JobCompletionSummary
    public let expiresAt: String?

    // Custom decoder for backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        pipeline = try container.decode(String.self, forKey: .pipeline)
        summary = try container.decode(JobCompletionSummary.self, forKey: .summary)

        // ✅ Gracefully handle missing expiresAt
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
    }

    enum CodingKeys: String, CodingKey {
        case type, pipeline, summary, expiresAt
    }
}
```

**Note:** This is **optional** - Swift's `Codable` handles optional fields automatically.

---

## Related Documentation

- **API Contract:** `/docs/API_CONTRACT.md` (lines 66-219)
- **WebSocket Migration Guide:** `/docs/API_CONTRACT.md` (lines 124-219)
- **Backend Implementation:** `src/durable-objects/progress-socket.js:401`

---

## Support

**Questions?** Contact backend team or file an issue in the BooksTrack repo.

**Rollback Option:** If iOS hotfix cannot be deployed quickly, we can add a backend feature flag to temporarily disable `expiresAt` (see Option 2 in analysis).
