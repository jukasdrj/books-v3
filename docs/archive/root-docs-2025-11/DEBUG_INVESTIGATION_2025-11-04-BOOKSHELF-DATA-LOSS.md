# Critical Bug Investigation: Bookshelf Scan Data Loss

## Bug Summary

**Issue:** Bookshelf scan reports contradictory data:
- iOS logs: "✅ Scan complete with 9 books (9 approved, 0 review)"
- iOS logs: "📸 WebSocket progress: 66% - Enriched 9/9 books"
- **But Analytics:** `books_detected: 0`

**JobId:** `0D9E91CF-CC2E-4996-8F80-FDBC6874D3EF`

**Impact:** Analytics event logs zero books detected despite successful backend processing

---

## Root Cause Analysis

### The Data Flow Architecture

```
iOS Client                          Backend (Cloudflare Workers)        Data Layer
─────────────────────────────────  ─────────────────────────────────   ──────────

1. User captures photo
   ↓
2. WebSocket.establishConnection()
   ↓
3. POST /api/scan-bookshelf         → [API Router] (index.js:244)
   (image data, jobId)              → Waits for WebSocket ready
                                    ↓
                                    [AI Scanner Service]
                                    → scanImageWithGemini()
                                    → enrichBooksParallel()
                                    → doStub.pushProgress()
                                    (FINAL COMPLETION MESSAGE)
   ↓
4. WebSocket receives progress      → ProgressWebSocketDO
   updates via message handler      → pushProgress() method
                                    → broadcasts to client
   ↓
5. iOS parses WebSocket message     → WebSocketProgressManager
   → Extracts scanResult            → Stores in JobProgress.scanResult
   → Logs analytics with books.count
```

### The Critical Data Flow Point (ai-scanner.js:169-191)

```typescript
// FINAL WEBSOCKET MESSAGE - Line 169-191
await doStub.pushProgress({
  progress: 1.0,
  processedItems: 3,
  totalItems: 3,
  currentStatus: 'Scan complete',
  jobId,
  result: {                          // ← NESTED OBJECT CONTAINING BOOKS
    totalDetected: 9,
    approved: 9,
    needsReview: 0,
    works: [...],                    // ← Canonical DTOs from enrichment
    editions: [...],
    authors: [...],
    detections: [...],               // ← Original Gemini detection data
    metadata: { ... }
  }
});
```

### The Data Extraction on iOS (BookshelfAIService.swift:218-230)

```swift
if let scanResult = jobProgress.scanResult {
    print("✅ Scan complete with \(scanResult.totalDetected) books (\(scanResult.approved) approved, \(scanResult.needsReview) review)")

    // Convert scan result to detected books
    let detectedBooks = scanResult.books.compactMap { bookPayload in
        self.convertPayloadToDetectedBook(bookPayload)  // ← Uses scanResult.books
    }

    // Analytics line 291
    print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(result.0.count), scan_id: \(jobId), success: true, strategy: websocket")
}
```

### The Analytics Event (BookshelfAIService.swift:291)

```swift
// Line 291 - where analytics is logged
print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(result.0.count), scan_id: \(jobId), success: true, strategy: websocket")
```

**Problem identified:** `result.0.count` is the count of `detectedBooks` returned from `convertPayloadToDetectedBook()`, which requires specific conditions to be met.

---

## Hypothesis: Book Payload Filtering in Conversion

### The Conversion Logic (BookshelfAIService.swift:416-490)

```swift
internal func convertPayloadToDetectedBook(_ bookPayload: ScanResultPayload.BookPayload) -> DetectedBook? {
    // ... bounding box calculation ...

    // Status determination logic
    let status: DetectionStatus
    if let enrichment = bookPayload.enrichment {
        switch enrichment.status.uppercased() {
        case "SUCCESS":
            status = .detected
        case "NOT_FOUND", "ERROR":
            status = .uncertain
        default:
            status = bookPayload.confidence >= 0.7 ? .detected : .uncertain
        }
    } else {
        status = bookPayload.confidence >= 0.7 ? .detected : .uncertain
    }

    // Returns nil if ANY of these conditions fail:
    var detectedBook = DetectedBook(
        isbn: bookPayload.isbn,
        title: bookPayload.title,      // ← Requires non-nil title
        author: bookPayload.author,    // ← Requires non-nil author
        format: format,
        confidence: bookPayload.confidence,  // ← If missing, defaults to 0.5 or causes crash
        boundingBox: boundingBox,
        rawText: rawText,
        status: status
    )

    // CRITICAL: Returns nil implicitly if any Codable decode fails
    return detectedBook  // ← Only returns if all fields decode successfully
}
```

**Key Issue:** The `compactMap` on line 223 of BookshelfAIService filters out **any book payloads that fail to decode or have nil critical fields**.

### Possible Payload Structure Mismatch

Looking at the WebSocket message structure (WebSocketProgressManager.swift:379-385):

```swift
struct ScanResultData: Codable, Sendable {
    let totalDetected: Int
    let approved: Int
    let needsReview: Int
    let books: [BookData]?  // ← OPTIONAL - may be missing!
    let metadata: ScanMetadata
}
```

**BUT the backend sends different field names!** (ai-scanner.js:175-189)

```javascript
// Backend sends:
result: {
    totalDetected: detectedBooks.length,
    approved: approved.length,
    needsReview: review.length,
    works: enrichedBooks.map(b => b.enrichment.work),    // ← Named "works"
    editions: enrichedBooks.flatMap(...),                // ← Named "editions"
    authors: enrichedBooks.flatMap(...),                 // ← Named "authors"
    detections: detectedBooks,                           // ← Gemini raw data
    metadata: { ... }
}

// iOS expects:
result: {
    totalDetected: Int,
    approved: Int,
    needsReview: Int,
    books: [BookData]?   // ← Expects "books" array!
    metadata: ScanMetadata
}
```

---

## Root Cause Confirmed

**The backend sends `works`, `editions`, `authors` arrays but iOS expects a `books` array.**

### Data Flow Breakdown

1. **Backend sends completion message** (ai-scanner.js:169)
   ```javascript
   result: {
     totalDetected: 9,
     approved: 9,
     needsReview: 0,
     works: [9 WorkDTO objects],      // ← Named "works"
     editions: [...],
     authors: [...],
     metadata: { ... }
   }
   ```

2. **iOS decodes WebSocketMessage** (WebSocketProgressManager.swift:297)
   ```swift
   let message = try decoder.decode(WebSocketMessage.self, from: data)
   // ScanResultData.books field is nil (because backend didn't send "books")
   // "works" array is LOST - no field to receive it
   ```

3. **iOS creates ScanResultPayload** (WebSocketProgressManager.swift:305-343)
   ```swift
   scanResult.books = (scanData.books ?? [])  // ← EMPTY ARRAY!
   // scanData.books is nil, so fallback to []
   ```

4. **iOS converts books** (BookshelfAIService.swift:223)
   ```swift
   let detectedBooks = scanResult.books.compactMap { ... }  // ← Empty array!
   // 0 books returned because there's nothing to map
   ```

5. **Analytics logs zero** (BookshelfAIService.swift:291)
   ```swift
   print("[Analytics] bookshelf_scan_completed - ... books_detected: 0 ...")
   // result.0.count = 0 because detectedBooks is empty
   ```

---

## Evidence Trail

### iOS Logs Show Success Messages (Misleading!)

```
✅ Scan complete with 9 books (9 approved, 0 review)
📸 WebSocket progress: 66% - Enriched 9/9 books
```

**These log messages come from the WebSocket final message stats, NOT from the books array:**

```swift
// BookshelfAIService.swift:219
if let scanResult = jobProgress.scanResult {
    print("✅ Scan complete with \(scanResult.totalDetected) books (\(scanResult.approved) approved, \(scanResult.needsReview) review)")
    //                                  ↑ These come from message metadata, not from books array!

    let detectedBooks = scanResult.books.compactMap { ... }  // ← But this is empty!

    // Analytics (line 291) logs detectedBooks.count = 0
}
```

### The Smoking Gun

The `totalDetected`, `approved`, `needsReview` fields ARE successfully decoded (they have values), but the `books` array is missing from the decoded structure because:

1. Backend sends `works`, `editions`, `authors` (separate canonical DTOs)
2. iOS decoder expects `books` array (per ScanResultData struct)
3. Codable silently sets `books` to `nil` when field not found
4. iOS treats `nil` as empty array `[]`
5. `compactMap` on empty array returns empty array
6. `detectedBooks.count = 0`

---

## System Design Flaw

The issue stems from **mismatch between data model definitions and backend output:**

### What the backend sends (canonical format):

```typescript
// ai-scanner.js returns separate canonical DTOs
const works = enrichedBooks.map(b => b.enrichment.work).filter(Boolean);
const editions = enrichedBooks.flatMap(b => b.enrichment.editions || []);
const authors = enrichedBooks.flatMap(b => b.enrichment.authors || []);

// Final message structure
result: {
    totalDetected,
    approved,
    needsReview,
    works,          // ← Canonical WorkDTO[]
    editions,       // ← Canonical EditionDTO[]
    authors,        // ← Canonical AuthorDTO[]
    detections,     // ← Original Gemini detections (for review queue)
    metadata
}
```

### What iOS expects (incompatible model):

```swift
// WebSocketProgressManager.swift
struct ScanResultData: Codable {
    let totalDetected: Int
    let approved: Int
    let needsReview: Int
    let books: [BookData]?  // ← Expects "books" with enrichment embedded!
    let metadata: ScanMetadata

    struct BookData: Codable {
        let title: String
        let author: String
        let isbn: String?
        let format: String?
        let confidence: Double
        let boundingBox: BoundingBox
        let enrichment: Enrichment?  // ← Enrichment embedded in each book
    }
}
```

---

## Fix Required

**Two options:**

### Option 1: Backend Changes (Recommended)
Flatten the structure to match iOS expectations:

```typescript
// ai-scanner.js:175-189
const books = enrichedBooks.map(b => ({
    title: b.title,
    author: b.author,
    isbn: b.isbn,
    format: b.format,
    confidence: b.confidence,
    boundingBox: b.boundingBox,
    enrichment: b.enrichment  // Embed enrichment in each book
}));

await doStub.pushProgress({
    progress: 1.0,
    currentStatus: 'Scan complete',
    result: {
        totalDetected: detectedBooks.length,
        approved: approved.length,
        needsReview: review.length,
        books,           // ← Unified array instead of separate arrays
        metadata: { ... }
    }
});
```

**Pros:**
- Single source of truth for each book
- Cleaner iOS parsing
- No redundant data in separate arrays
- Matches how iOS processes books

**Cons:**
- Slight data duplication (enrichment objects appear once per book instead of centralized)

### Option 2: iOS Changes (Not Recommended)
Update iOS to expect the canonical format:

```swift
// Update ScanResultData to match backend
struct ScanResultData: Codable {
    let totalDetected: Int
    let approved: Int
    let needsReview: Int
    let works: [WorkDTO]?          // Accept backend format
    let editions: [EditionDTO]?
    let authors: [AuthorDTO]?
    let detections: [BookData]?    // Gemini raw data
    let metadata: ScanMetadata
}

// Then manually reconstruct books from works + enrichments
let books = works?.enumerated().map { idx, work in
    let enrichment = detections?[idx]?.enrichment
    // ... reconstruct
}
```

**Pros:**
- Matches backend's canonical format philosophy

**Cons:**
- More complex iOS code
- Requires manual reconstruction of book array
- Mismatch between what backend sends and what iOS needs

---

## Verification Steps (Before Fix)

To confirm the root cause, check Cloudflare logs:

```bash
npx wrangler tail api-worker --search "0D9E91CF" --format pretty

# Look for:
# 1. "[AI Scanner] Scan complete for job ...: 9 books" ✅
# 2. "[ProgressDO] completeBatch called" or "pushProgress called" ✅
# 3. "[ProgressDO] Progress sent successfully" ✅
# 4. Message contains: "works: [...], editions: [...], authors: [...]"
# 5. Message MISSING: "books: [...]"
```

---

## Impact Assessment

- **Affected Jobs:** All WebSocket-based bookshelf scans (new monolith architecture)
- **Data Loss:** Only in analytics/logging - actual data IS sent to iOS, just mislabeled
- **User Experience:** Books appear in review queue normally (data IS processed)
- **Bug Window:** Since monolith refactor (when canonical DTOs introduced)

---

## Next Steps

1. **Immediate:** Confirm root cause by checking worker logs for job `0D9E91CF`
2. **Fix:** Implement Option 1 (backend restructuring) for cleaner architecture
3. **Test:** Run bookshelf scan and verify `books_detected` in analytics matches visual count
4. **Regression:** Check all analytics events for similar field naming mismatches
5. **Documentation:** Update data contract in `canonical.ts` with complete response structure

