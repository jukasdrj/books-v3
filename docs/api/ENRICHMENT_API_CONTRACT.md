# Enrichment API Contract Notes

**Last Updated:** 2026-01-16
**Related Commits:** b6a4044 (Format 1b fix), 16e5347 (field name fix), 68a298d (search authors fix)

## Issue History

### Problem
Library enrichment was failing with "No enriched books in response" despite backend successfully processing 62/62 books.

### Root Cause
**Contract ambiguity** between bendv3 backend and books-v3 iOS client:

- **OpenAPI Spec:** Defines `JobResultsResponse.data.results` as generic `array` of `object` with note "structure varies by job type"
- **bendv3 Implementation:** Returns unwrapped `[V3EnrichedBook]` objects directly
- **iOS Client Expectation:** Expected wrapped `[EnrichedBookPayload]` with success/enriched fields

### Solution
Implemented **Format 1b** decoding strategy in `EnrichmentResultsClient.swift`:

```swift
// Format 1b: V3 Response with [V3EnrichedBook]
struct EnrichmentJobResultsV3: Codable {
    let jobId: String
    let status: String
    let results: [V3EnrichedBook]  // Unwrapped format from backend
}
```

Maps unwrapped V3EnrichedBook → wrapped EnrichedBookPayload using existing V3ToV2Mapper.

## Canonical Format (As-Implemented)

**Enrichment job results endpoint:** `GET /v3/jobs/enrichment/{jobId}/results`

**Actual Response Structure:**
```json
{
  "success": true,
  "data": {
    "jobId": "uuid",
    "status": "completed",
    "results": [
      {
        "isbn": "9780316769174",
        "title": "The Catcher in the Rye",
        "authors": [
          {
            "name": "J.D. Salinger",
            "key": "/authors/OL34184A",
            "openlibrary": "OL34184A",
            "bio": "...",
            "gender": "male",
            "birthYear": 1919,
            "deathYear": 2010
          }
        ],
        "publisher": "Little, Brown",
        "publishedDate": "1991-05-01",
        "pageCount": 277,
        "categories": ["Fiction", "Classics"],
        "coverUrl": "https://covers.openlibrary.org/b/id/...",
        "thumbnailUrl": "https://covers.openlibrary.org/b/id/...",
        "provider": "google_books",
        "quality": 95,
        "vectorized": true
      }
    ]
  },
  "metadata": {
    "timestamp": "2026-01-16T20:00:00Z",
    "requestId": "uuid"
  }
}
```

**Key Points:**
- `results` contains **unwrapped V3EnrichedBook objects** (not EnrichedBookPayload)
- Authors are **enriched V3Author objects** with metadata (not simple strings)
- No per-book `success` field (job-level success only)
- No nested `enriched: {work, edition, authors}` wrapper (flat structure)

## iOS Client Compatibility

**EnrichmentResultsClient.swift** implements **4 fallback formats**:

1. **Format 1:** ResponseEnvelope with wrapped EnrichedBookPayload (legacy)
2. **Format 1b:** ResponseEnvelope with unwrapped V3EnrichedBook ← **ACTIVE FORMAT**
3. **Format 2:** V3 direct response {success, data: {enrichedBooks}}
4. **Format 3:** Simple wrapper {data: {enrichedBooks}}

Client tries formats in order, using first successful decode. Format 1b is what actually works with current backend.

## Related Schema Changes

### Search API (Fixed in Same Session)
**Issue:** V2 Search also had author type mismatch
**Location:** `BookSearchAPIService.swift:417-443`
**Fix:** Changed `authors: [String]?` → `authors: [V3Author]?`

Both search and enrichment now correctly handle **enriched V3Author objects** instead of simple strings.

## Recommendation for bendv3

**Update OpenAPI spec** to explicitly document enrichment results schema:

```json
"EnrichmentJobResultsResponse": {
  "allOf": [
    {"$ref": "#/components/schemas/JobResultsResponse"},
    {
      "properties": {
        "data": {
          "properties": {
            "results": {
              "type": "array",
              "items": {"$ref": "#/components/schemas/V3EnrichedBook"},
              "description": "Array of enriched book objects with author metadata"
            }
          }
        }
      }
    }
  ]
}
```

This makes the unwrapped V3EnrichedBook format **canonical** for enrichment jobs while keeping JobResultsResponse generic for other job types.

## Files Modified

- `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentResultsClient.swift` - Added Format 1b, V3ToV2Mapper integration
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift` - Fixed V2SearchResultItem.authors type
- `task_plan.md` - Documented all fixes and root causes
- `findings.md` - Captured API contract investigation

## Status

✅ **RESOLVED** - iOS client now accepts actual backend format and gracefully handles multiple fallback formats for robustness.

---

**Investigation Tools Used:**
- PAL MCP debug (Gemini 2.5 Flash) - Search decoding investigation
- PAL MCP codereview (Grok-4) - Enrichment field name mismatch
- PAL MCP clink (Gemini Pro 3) - Format 1b implementation (YOLO mode)
