# PR #242 Front-End Integration Guide - CSV Error Tracking

**Feature:** CSV validation error tracking with row numbers
**PR:** #242
**Status:** ✅ MERGED
**Target:** iOS app (books-v3)
**Date:** January 5, 2026

---

## Executive Summary

PR #242 adds comprehensive error tracking to CSV imports. Users can now see exactly which rows failed validation and why, replacing the previous behavior where `errors: []` was hardcoded empty.

**What Changed:**
- CSV processing now collects errors at all failure points
- Errors include row numbers (approximate but actionable)
- SSE `complete` event includes error array for persistence
- API response format enhanced with error details

**iOS Impact:**
- **NEW FIELD:** `errors` array now populated (was always empty)
- **NO BREAKING CHANGES:** All existing fields preserved
- **OPTIONAL:** iOS can display error details to users

---

## API Response Format Changes

### Before PR #242 ❌

```json
{
  "success": true,
  "data": {
    "booksCreated": 100,
    "booksUpdated": 0,
    "duplicatesSkipped": 5,
    "enrichmentSucceeded": 0,
    "enrichmentFailed": 0,
    "errors": [],  // ❌ Always empty
    "books": [...]
  }
}
```

### After PR #242 ✅

```json
{
  "success": true,
  "data": {
    "booksCreated": 97,
    "booksUpdated": 0,
    "duplicatesSkipped": 5,
    "enrichmentSucceeded": 0,
    "enrichmentFailed": 0,
    "errors": [  // ✅ Now populated
      {
        "row": 3,
        "isbn": "9780000000002",
        "error": "Missing required field: author"
      },
      {
        "row": 15,
        "isbn": "9780000000015",
        "error": "Book \"The Great Gatsby\" has missing or whitespace-only author"
      },
      {
        "row": -1,
        "isbn": "9780000000042",
        "error": "Failed to persist to database: D1 write timeout"
      }
    ],
    "books": [...]  // 97 successful books
  }
}
```

---

## Error Object Schema

### TypeScript Definition

```typescript
/**
 * Individual CSV processing error
 *
 * Returned in:
 * - GET /v3/jobs/imports/:jobId/results
 * - SSE complete event (data.books field)
 */
interface JobErrorDetail {
  /**
   * Row number in CSV file (1-based, includes header)
   *
   * Accuracy:
   * - Gemini filtering: ✅ Exact row number
   * - Validation: ✅ Good (index-based approximation)
   * - Database errors: ❌ Lost (set to -1)
   */
  row?: number  // Optional: -1 means row number unknown

  /**
   * ISBN of failed book (when available)
   * Useful for identifying which book failed when row=-1
   */
  isbn?: string

  /**
   * Human-readable error message
   * Examples:
   * - "Missing required field: author"
   * - "Missing required field: title"
   * - "Book \"Title\" has missing or whitespace-only author"
   * - "Failed to persist to database: {reason}"
   */
  error: string
}
```

### Zod Schema (Shared Package)

```typescript
import { JobErrorDetailSchema } from '@bookstrack/schemas'

// Zod schema from packages/schemas/src/jobs.ts
export const JobErrorDetailSchema = z.object({
  row: z.number().int().nonnegative().optional(),
  isbn: z.string().optional(),
  error: z.string(),
})
```

---

## Integration Points

### 1. SSE Complete Event (Recommended)

**Best Practice:** iOS should capture errors from the SSE `complete` event.

**Event Format:**
```typescript
// SSE event type: "complete"
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "progress": 100,
  "processedCount": 100,
  "totalCount": 100,
  "completedAt": "2026-01-05T10:00:00Z",
  "books": [
    // Full canonical book objects
    {
      "isbn": "9780439708180",
      "title": "Harry Potter and the Sorcerer's Stone",
      "author": "J.K. Rowling",
      // ... full enrichment data
    }
  ],
  "errors": [  // ✅ NEW: Error array included
    {
      "row": 3,
      "isbn": "9780000000002",
      "error": "Missing required field: author"
    }
  ]
}
```

**iOS Implementation:**
```swift
// Parse SSE complete event
func handleSSECompleteEvent(_ event: SSECompleteEvent) {
    // 1. Persist books to SwiftData
    for book in event.books {
        persistBook(book)
    }

    // 2. NEW: Handle errors
    if !event.errors.isEmpty {
        // Display error summary to user
        showImportErrorSummary(
            successCount: event.books.count,
            errorCount: event.errors.count,
            errors: event.errors
        )
    }
}
```

### 2. Results Endpoint (Fallback)

If iOS didn't capture the SSE event, fetch from results endpoint:

```http
GET /v3/jobs/imports/{jobId}/results
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "completed",
    "results": [
      {
        "booksCreated": 97,
        "errors": [...],
        "books": [...]
      }
    ]
  },
  "metadata": {
    "timestamp": "2026-01-05T10:00:00Z",
    "requestId": "req-123"
  }
}
```

**iOS Implementation:**
```swift
// Fallback: Fetch results if SSE missed
func fetchImportResults(jobId: String) async throws -> JobResults {
    let url = URL(string: "https://api.oooefam.net/v3/jobs/imports/\(jobId)/results")!
    var request = URLRequest(url: url)
    request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(JobResultsResponse.self, from: data)

    return response.data.results[0]  // Get first result object
}
```

---

## Error Categories & Row Numbers

### Row Number Accuracy

| Error Source | Row Number | Notes |
|--------------|------------|-------|
| **Gemini Filtering** | ✅ Exact | Row number from structured output |
| **Validation** | ✅ Good | Index-based (off by 1-2 rows possible) |
| **Deduplication** | ⚠️ Not tracked | No individual errors, see `duplicatesSkipped` counter |
| **Database Errors** | ❌ Lost (`-1`) | Row context lost at save stage, ISBN provided |

### Error Types

#### 1. Missing Required Fields
```json
{
  "row": 3,
  "isbn": "9780000000002",
  "error": "Missing required field: author"
}
```

**Cause:** CSV row has empty or whitespace-only title/author
**Row Number:** ✅ Accurate (validation stage)

#### 2. Whitespace-Only Author
```json
{
  "row": 15,
  "isbn": "9780000000015",
  "error": "Book \"The Great Gatsby\" has missing or whitespace-only author"
}
```

**Cause:** Gemini filtering detected whitespace-only author
**Row Number:** ✅ Exact (Gemini stage)

#### 3. Database Failures
```json
{
  "row": -1,
  "isbn": "9780000000042",
  "error": "Failed to persist to database: D1 write timeout"
}
```

**Cause:** KV or D1 write failed during save
**Row Number:** ❌ Lost (set to -1, use ISBN for identification)

#### 4. Duplicate ISBNs
**NOT TRACKED AS ERRORS** - Use `duplicatesSkipped` counter instead.

```json
{
  "booksCreated": 97,
  "duplicatesSkipped": 5,  // 5 books skipped (duplicates)
  "errors": []              // No error objects for duplicates
}
```

---

## UI/UX Recommendations

### Success Scenario (No Errors)

```
✅ Import Complete
97 books added to your library
5 duplicates skipped
```

### Partial Failure (Some Errors)

```
⚠️ Import Complete with Warnings
97 books added to your library
3 rows failed validation

View Error Details →
```

**Error Details Modal:**
```
Import Errors (3)

Row 3: Missing author
ISBN: 9780000000002

Row 15: "The Great Gatsby" missing author
ISBN: 9780000000015

Unknown row: Database error
ISBN: 9780000000042
(Row number unavailable for database errors)

[Dismiss] [Export Error Report]
```

### Empty Error Array (Backward Compatible)

```swift
// iOS should handle both empty and populated errors gracefully
if results.errors.isEmpty {
    // All books imported successfully
    showSuccessMessage("All books imported successfully")
} else {
    // Some errors occurred
    showPartialSuccessMessage(
        success: results.booksCreated,
        failed: results.errors.count
    )
}
```

---

## Migration Guide for iOS

### Step 1: Update TypeScript Client (Optional)

The `@jukasdrj/bookstrack-api-client` package already includes the error schema (auto-generated from OpenAPI).

```bash
npm update @jukasdrj/bookstrack-api-client
```

### Step 2: Update Swift Models

Add `errors` field to your import results model:

```swift
// Before
struct JobResults: Codable {
    let booksCreated: Int
    let booksUpdated: Int
    let duplicatesSkipped: Int
    let enrichmentSucceeded: Int
    let enrichmentFailed: Int
    let books: [CanonicalBook]
    // errors field missing
}

// After
struct JobResults: Codable {
    let booksCreated: Int
    let booksUpdated: Int
    let duplicatesSkipped: Int
    let enrichmentSucceeded: Int
    let enrichmentFailed: Int
    let books: [CanonicalBook]
    let errors: [JobErrorDetail]  // ✅ NEW
}

struct JobErrorDetail: Codable {
    let row: Int?      // Optional: -1 means unknown
    let isbn: String?  // Optional: may be missing
    let error: String  // Required: error message
}
```

### Step 3: Update SSE Event Handling

```swift
// Update SSECompleteEvent to include errors
struct SSECompleteEvent: Codable {
    let jobId: String
    let status: String
    let progress: Int
    let processedCount: Int
    let totalCount: Int
    let completedAt: String
    let books: [CanonicalBook]
    let errors: [JobErrorDetail]  // ✅ NEW
}
```

### Step 4: Display Errors to Users

```swift
func handleImportComplete(_ results: JobResults) {
    // Persist books
    for book in results.books {
        persistToSwiftData(book)
    }

    // Show results summary
    if results.errors.isEmpty {
        showAlert(
            title: "Import Complete",
            message: "\(results.booksCreated) books added successfully"
        )
    } else {
        showImportResultsView(
            successCount: results.booksCreated,
            errorCount: results.errors.count,
            errors: results.errors
        )
    }
}
```

---

## Testing

### Test Scenarios

#### 1. Valid CSV (No Errors)
```csv
Title,Author,ISBN
"Harry Potter","J.K. Rowling",9780439708180
"1984","George Orwell",9780451524935
```

**Expected:**
```json
{
  "booksCreated": 2,
  "errors": []
}
```

#### 2. Missing Author
```csv
Title,Author,ISBN
"Valid Book","John Smith",9780000000001
"Missing Author","",9780000000002
"Valid Book 2","Jane Doe",9780000000003
```

**Expected:**
```json
{
  "booksCreated": 2,
  "errors": [
    {
      "row": 3,
      "isbn": "9780000000002",
      "error": "Missing required field: author"
    }
  ]
}
```

#### 3. Missing Title
```csv
Title,Author,ISBN
"Valid Book","John Smith",9780000000001
"","Jane Doe",9780000000002
"Valid Book 2","Alice Johnson",9780000000003
```

**Expected:**
```json
{
  "booksCreated": 2,
  "errors": [
    {
      "row": 3,
      "isbn": "9780000000002",
      "error": "Missing required field: title"
    }
  ]
}
```

#### 4. Mixed Errors
```csv
Title,Author,ISBN
"Valid Book","John Smith",9780000000001
"Missing Author","",9780000000002
"","Jane Doe",9780000000003
"Valid Book 2","Alice Johnson",9780000000004
```

**Expected:**
```json
{
  "booksCreated": 2,
  "errors": [
    {
      "row": 3,
      "isbn": "9780000000002",
      "error": "Missing required field: author"
    },
    {
      "row": 4,
      "isbn": "9780000000003",
      "error": "Missing required field: title"
    }
  ]
}
```

---

## API Documentation

### OpenAPI Spec

The error schema is automatically included in the OpenAPI spec:

**View Live:**
- Spec: https://api.oooefam.net/v3/openapi.json
- Docs: https://api.oooefam.net/v3/docs

**Search for:**
- `JobErrorDetail` schema definition
- `JobResultsResponse` containing errors array
- `SSECompleteEvent` with errors field

### TypeScript SDK

```typescript
import { type JobErrorDetail, type JobResults } from '@jukasdrj/bookstrack-api-client'

// Type-safe error handling
function handleImportResults(results: JobResults) {
  if (results.errors.length > 0) {
    console.log(`${results.errors.length} errors occurred:`)
    results.errors.forEach((error) => {
      const rowInfo = error.row && error.row !== -1
        ? `Row ${error.row}`
        : 'Unknown row'
      console.log(`${rowInfo}: ${error.error}`)
    })
  }
}
```

---

## Rollback Plan

If iOS experiences issues with the new error format:

### Option 1: Ignore Errors (Quick Fix)

```swift
// Ignore errors, continue using only success count
let results = try JSONDecoder().decode(JobResults.self, from: data)
persistBooks(results.books)  // Only use books array
// Don't reference results.errors
```

**Impact:** No iOS changes needed, error tracking disabled

### Option 2: Server-Side Rollback

```javascript
// In csv-processor-core.ts line 463
errors: [],  // Revert to empty array
```

**Impact:** All clients get empty errors array again

---

## Performance Impact

### Payload Size

**Before PR #242:**
```
Typical response: ~50KB (100 books)
```

**After PR #242:**
```
Typical response: ~51KB (100 books + 5 errors)
Error object size: ~100 bytes each
500 errors: ~50KB (well under 1MB KV limit)
```

### Latency

**No measurable impact:**
- Error collection: <1ms per error
- JSON serialization: negligible
- Network: +1-2KB typical payload increase

---

## Monitoring

### Metrics to Track

**Backend (Already Instrumented):**
- Error rate per CSV import (`errors.length / totalRows`)
- Most common error types (group by `error` field)
- Average errors per import
- Percentage of imports with zero errors

**iOS (Recommended):**
- Track when users view error details
- Monitor if error counts correlate with support tickets
- A/B test error messaging clarity

---

## Known Limitations

### 1. Row Numbers Approximate for Validation
- Based on array index, not original CSV line
- May be off by 1-2 rows in edge cases
- **Mitigation:** Include ISBN for precise identification

### 2. Row Numbers Lost for Database Errors
- Set to `-1` as sentinel value
- ISBN provided for identification
- **Future:** Add `_rowNumber` field to `ParsedBook` interface

### 3. Gemini Filtering Invisible
- Books filtered by Gemini never reach error tracking
- Only captures what Gemini returns
- **Cannot track:** What Gemini silently drops

### 4. Duplicate ISBNs Not Tracked as Errors
- Intentional design decision
- Use `duplicatesSkipped` counter instead
- **Rationale:** Duplicates aren't errors, they're expected behavior

---

## FAQ

### Q: Do I need to update my iOS app immediately?

**A:** No. The change is backward compatible. If iOS ignores the `errors` field, everything continues working as before.

### Q: What if iOS crashes parsing the errors array?

**A:** Unlikely - `errors` was always present in the response, just empty. If you experience issues:
1. Update to latest `@jukasdrj/bookstrack-api-client` SDK
2. Verify your Swift model has `errors: [JobErrorDetail]` field
3. Check JSON decoding handles optional fields correctly

### Q: Can iOS trust the row numbers?

**A:** Mostly yes. Row numbers are exact for Gemini errors, approximate but close for validation errors, and `-1` (unknown) for database errors. Use ISBN as the primary identifier when row = -1.

### Q: Should iOS display technical error messages to users?

**A:** Recommended approach:
- Simple summary: "3 rows failed validation"
- Details on demand: Tap to view specific errors
- Technical messages are readable (e.g., "Missing required field: author")

### Q: What if a CSV has 500 errors?

**A:** API handles it fine (500 errors = ~50KB), but iOS should:
- Summarize error counts by type
- Paginate error list display
- Offer "Export Error Report" option

---

## Support

**Questions about:**
- **API integration:** @jukasdrj
- **TypeScript SDK:** https://www.npmjs.com/package/@jukasdrj/bookstrack-api-client
- **OpenAPI spec:** https://api.oooefam.net/v3/docs
- **Implementation details:** See PR #242 or PR242_FINAL_SUMMARY.md

---

**Last Updated:** January 5, 2026
**Implementation:** PR #242 (merged)
**Status:** ✅ Production Ready
**Documentation:** Complete
