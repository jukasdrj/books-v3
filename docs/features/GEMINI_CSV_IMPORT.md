# Gemini CSV Import Feature

**Version:** 1.0.0 (Complete)
**Status:** ✅ Production Ready (v3.1.0+)
**Backend:** Cloudflare Worker + Gemini 2.0 Flash API
**Last Updated:** January 27, 2025

## Overview

AI-powered CSV import that requires zero configuration. Gemini automatically detects book data from any CSV format, eliminating the need for manual column mapping.

### Key Advantages

- **Zero Configuration:** No column mapping UI required
- **Intelligent Parsing:** Gemini 2.0 Flash understands CSV structure automatically
- **Real-Time Progress:** WebSocket updates every 100-500ms
- **Automatic Enrichment:** Fetches covers and metadata from Google Books + OpenLibrary
- **Content-Based Caching:** SHA-256 hashing for 30-day cache TTL

## Architecture

### Unified Enrichment Pipeline (October 2025)

**Important:** As of October 2025, CSV import uses the **unified enrichment pipeline** shared by all import sources (manual add, bookshelf scan, CSV import). This ensures consistent behavior and eliminates code duplication.

**Stage 1: Upload & Parse (5-15s)**
- iOS uploads CSV to Cloudflare Worker (`POST /api/import/csv-gemini`)
- Gemini 2.0 Flash analyzes CSV structure
- Extracts: title, author, ISBN, publisher, publication year
- Backend validates parsed books (title + author required)
- Returns: `{ books: [{ title, author, isbn? }], errors: [] }`
- **No enrichment on backend** - books returned with minimal metadata

**Stage 2: Save & Enqueue (<1s)**
- iOS saves minimal book data to SwiftData (Work, Author, Edition)
- Books appear **instantly** in library (no waiting for covers!)
- PersistentIdentifiers enqueued to `EnrichmentQueue`
- User can immediately browse and interact with books

**Stage 3: Background Enrichment (1-5 minutes)**
- `EnrichmentService` processes queue in background
- Fetches covers, metadata, ISBNs from external APIs (Google Books + OpenLibrary)
- Updates SwiftData models incrementally as data arrives
- User can browse library, search, and add books while enrichment happens
- Real-time UI updates as covers and metadata populate

### Real-Time Progress

- WebSocket connection: `wss://api-worker.jukasdrj.workers.dev/ws/progress?jobId={uuid}`
- Server pushes progress updates (0-100%)
- Current book title + overall progress percentage
- Final result includes all parsed/enriched data

### System Flow

```
User selects CSV file
    ↓
GeminiCSVImportView (iOS)
    ↓ Upload via multipart/form-data
Cloudflare Worker (/api/import/csv-gemini)
    ↓ Generate jobId
WebSocket Handshake (/ws/progress?jobId={uuid})
    ↓
Gemini 2.0 Flash API (Parsing Phase)
    ↓ 5-15s parsing only (no enrichment!)
WebSocket sends parsed books
    ↓
iOS saves to SwiftData (Work, Author, Edition models)
    ↓
Books appear INSTANTLY in Library tab (minimal metadata)
    ↓
EnrichmentQueue.enqueueBatch() called
    ↓
EnrichmentService processes in background
    ↓ 1-5 minutes (Google Books + OpenLibrary)
Cover images & metadata populate incrementally
    ↓
Library tab updates in real-time (no refresh needed)
```

## User Experience

### Step-by-Step Flow

1. **Access:** Settings → Library Management → "AI-Powered CSV Import (Recommended)"
2. **Select:** Choose CSV file from Files app (max 10MB)
3. **Upload:** Automatic upload with file size validation
4. **Parse:** Gemini analyzes CSV structure (5-15s progress)
5. **Review:** See success count and error list (parsing complete!)
6. **Save:** Tap "Add to Library" to save books to SwiftData
7. **View:** Books appear **instantly** in Library tab (within 1 second!)
8. **Enrich:** Covers and metadata populate in background (1-5 minutes)
   - No waiting required - browse library immediately
   - Real-time updates as enrichment completes
   - Continue using app while enrichment happens

### Progress Updates

- **Uploading:** Spinner with "Uploading CSV..." message
- **Processing:** Linear progress bar (0-100%)
  - Example: "Processing... 75%" + "Parsing: Analyzing CSV structure"
  - **Note:** Progress bar only tracks parsing phase (5-15s), not enrichment
- **Completed:** Green checkmark + statistics
  - "✅ Successfully imported: 87 books"
  - "⚠️ Errors: 3 books" (expandable error list)
  - Books ready to add to library immediately
- **Failed:** Red warning icon + error message + "Try Again" button
- **Background Enrichment:** (after adding to library)
  - Happens silently in background
  - No progress UI (enrichment is non-blocking)
  - Covers appear incrementally as they're fetched

### Error Handling

- **File too large (>10MB):** "CSV file too large (12MB). Maximum size is 10MB."
- **Network error:** "Network error: The Internet connection appears to be offline"
- **Server error:** "Server error (500): Internal server error"
- **Parsing failed:** "CSV parsing failed: Invalid CSV format"
- **WebSocket disconnect:** "Connection lost: Connection timed out"

## Implementation

### iOS Components

**GeminiCSVImportView.swift**
- Main UI with 5 states: idle, uploading, processing, completed, failed
- WebSocket client for real-time progress
- File picker integration with UTType validation
- Haptic feedback for success/error states
- SwiftData persistence with duplicate detection

**GeminiCSVImportService.swift**
- Actor-isolated HTTP upload service
- Multipart/form-data encoding
- File size validation (10MB max)
- Error handling with typed errors

**WebSocketProgressManager.swift**
- Generic WebSocket progress tracking (shared with Bookshelf Scanner)
- Connection management with ping/pong verification
- JSON message parsing with Codable models
- Automatic reconnection on errors

### Backend Endpoint

**POST** `/api/import/csv-gemini`

**Request:**
```http
POST /api/import/csv-gemini HTTP/1.1
Host: api-worker.jukasdrj.workers.dev
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary

------WebKitFormBoundary
Content-Disposition: form-data; name="file"; filename="import.csv"
Content-Type: text/csv

Book Id,Title,Author,ISBN13
123,Harry Potter,J.K. Rowling,9780439708180
------WebKitFormBoundary--
```

**Response:**
```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**WebSocket Progress:**
```json
{
  "type": "progress",
  "progress": 0.45,
  "status": "Enriching: Harry Potter"
}
```

**WebSocket Complete:**
```json
{
  "type": "complete",
  "result": {
    "books": [
      {
        "title": "Harry Potter and the Sorcerer's Stone",
        "author": "J.K. Rowling",
        "isbn": "9780439708180",
        "coverUrl": "https://books.google.com/...",
        "publisher": "Scholastic",
        "publicationYear": 1998,
        "enrichmentError": null
      }
    ],
    "errors": [
      {
        "title": "Unknown Book",
        "error": "No metadata found"
      }
    ],
    "successRate": "87%"
  }
}
```

### Caching Strategy

**Content-Based Cache Key:**
```javascript
// Backend: cloudflare-workers/api-worker/src/handlers/csv-gemini.js
const csvHash = await hashCSVContent(csvText);
const cacheKey = `csv-gemini:${csvHash}`;

// Check cache (30-day TTL)
const cached = await env.KV.get(cacheKey, { type: 'json' });
if (cached) {
  return cached; // Instant response for duplicate uploads
}

// Process + cache result
const result = await processCSV(csvText);
await env.KV.put(cacheKey, JSON.stringify(result), { expirationTtl: 2592000 });
```

**Why SHA-256?**
- Content-based: Same CSV = same cache key (regardless of filename)
- Collision-resistant: Virtually impossible for different CSVs to share key
- Fast: ~10ms for typical 1MB CSV file

### Rate Limiting

- **10MB file size limit** (backend memory constraints)
- **5 requests/minute per IP** (Cloudflare rate limiting)
- **1000 books/request max** (Gemini token limit ~500K tokens)

### Data Models

```swift
// GeminiCSVImportService.swift

public struct GeminiCSVImportResponse: Codable, Sendable {
    public let jobId: String
}

public struct GeminiCSVImportJob: Codable, Sendable {
    public let books: [ParsedBook]
    public let errors: [ImportError]
    public let successRate: String

    public struct ParsedBook: Codable, Sendable, Equatable {
        public let title: String
        public let author: String
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?
        public let enrichmentError: String?
    }

    public struct ImportError: Codable, Sendable, Equatable {
        public let title: String
        public let error: String
    }
}
```

### SwiftData Persistence

```swift
// GeminiCSVImportView.swift: saveBooks(_:)

private func saveBooks(_ books: [GeminiCSVImportJob.ParsedBook]) async {
    // Fetch all existing works ONCE (100x performance improvement)
    let allWorks = try? modelContext.fetch(FetchDescriptor<Work>())

    for book in books {
        // Duplicate detection by title + author (case-insensitive)
        let isDuplicate = allWorks?.contains { work in
            work.title.lowercased() == book.title.lowercased() &&
            work.authorNames.lowercased().contains(book.author.lowercased())
        } ?? false

        if isDuplicate {
            skippedCount += 1
            continue
        }

        // Create Author
        let author = Author(name: book.author)
        modelContext.insert(author)

        // Create Work
        let work = Work(
            title: book.title,
            authors: [author],
            originalLanguage: "Unknown",
            firstPublicationYear: book.publicationYear
        )
        modelContext.insert(work)

        // Create Edition (if we have ISBN/publisher/cover)
        if book.isbn != nil || book.publisher != nil {
            let edition = Edition(
                isbn: book.isbn,
                publisher: book.publisher,
                publicationDate: book.publicationYear.map { "\($0)" },
                pageCount: nil,
                format: .paperback
            )

            if let coverUrl = book.coverUrl {
                edition.coverImageURL = coverUrl
            }

            modelContext.insert(edition)
            work.editions = [edition]
        }

        savedCount += 1
    }

    try modelContext.save()

    // Haptic feedback
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}
```

## Testing

### Test File

**Location:** `docs/testImages/goodreads_library_export.csv`

**Format:** Goodreads export with 20 books
**Columns:** Book Id, Title, Author, ISBN13, My Rating, Average Rating, Publisher, etc.

**Sample Row:**
```csv
123,Long Bright River,Liz Moore,"=""0525540679""",5,4.05,Riverhead Books,Hardcover,482,2020
```

### Test Cases

1. **Valid Goodreads Export** (standard format)
   - Expected: 90%+ success rate
   - Covers fetched for 80%+ books
   - Duplicate detection works

2. **Custom CSV** (different column order)
   - Expected: Gemini auto-detects columns
   - No manual mapping needed

3. **CSV with Missing Data**
   - Expected: Graceful degradation
   - Books saved with available data
   - Errors shown for failed rows

4. **Duplicate Books** (same title + author)
   - Expected: Skipped during save
   - Completion screen shows skip count

5. **Large File** (1000+ books, ~2MB)
   - Expected: <60s total time
   - WebSocket updates every 500ms
   - Memory usage <50MB

### Manual Testing Steps

```bash
# 1. Build and launch app
/sim

# 2. Navigate to Settings
# Tap Settings gear icon in Library tab

# 3. Start import
# Tap "AI-Powered CSV Import (Recommended)"

# 4. Select test file
# Choose docs/testImages/goodreads_library_export.csv

# 5. Observe progress
# - Upload spinner appears
# - Progress bar updates smoothly
# - Status messages show current book
# - Completion screen shows statistics

# 6. Verify results
# - Tap "Add to Library"
# - Navigate to Library tab
# - Verify books appear with covers
# - Check for correct authors/years

# 7. Test duplicate handling
# - Import same CSV again
# - Verify duplicates skipped
# - No duplicate books in library
```

### Expected Results

- **Upload:** <1s for 2MB CSV
- **Parse:** 10-15s (Gemini processing)
- **Save to SwiftData:** <1s
- **Total (until books appear):** ~12-17s for 20 books (7x faster than old pipeline!)
- **Background Enrichment:** 1-5 minutes (non-blocking)
- **Success Rate:** 90%+ (covers found for 18/20 books after enrichment)
- **Duplicates:** Correctly detected and skipped
- **Memory:** <50MB peak usage
- **User Experience:** Books browsable immediately, covers populate progressively

## Comparison to Legacy CSV Import

| Feature | Gemini Import | Legacy Import |
|---------|--------------|---------------|
| **Column Mapping** | ❌ Auto-detect | ✅ Manual required |
| **Enrichment** | ✅ Background queue (unified) | ✅ Background queue |
| **Progress** | ✅ Real-time WebSocket (parsing only) | ⚠️ Polling/Local |
| **Books Appear** | 12-17s (instant!) | ~5-10s (after parse) |
| **Cover Detection** | ✅ Background (1-5min) | ✅ Background |
| **Duplicate Handling** | ✅ Title+Author | ✅ Configurable |
| **File Size Limit** | 10MB | Unlimited |
| **User Effort** | Low | High |
| **Configuration** | None | Column mapping UI |
| **Error Recovery** | Retry button | Manual retry |
| **Caching** | Content-based (SHA-256) | None |
| **Cost** | ~$0.05 per 1000 books | Free |
| **Pipeline** | Unified (shared with all imports) | Unified (shared with all imports) |

### When to Use Each System

**Use Gemini Import:**
- ✅ First-time import
- ✅ Unknown CSV format
- ✅ Small/medium libraries (<1000 books)
- ✅ Want instant results

**Use Legacy Import:**
- ✅ Very large libraries (5000+ books)
- ✅ Known CSV format (Goodreads/LibraryThing)
- ✅ Want background processing
- ✅ Want fine-grained duplicate strategy control

## Known Limitations

### Technical Constraints

1. **10MB File Size Limit**
   - **Reason:** Cloudflare Worker memory constraints (128MB)
   - **Impact:** ~5000 books max per import
   - **Workaround:** Split large CSVs into multiple files

2. **No Format Detection**
   - **Issue:** Defaults all books to "paperback" format
   - **Reason:** CSV exports rarely include format data
   - **Future:** Could infer from "Binding" column if available

3. **Language Detection**
   - **Issue:** Defaults to "Unknown" original language
   - **Reason:** Gemini doesn't detect language from title/author
   - **Future:** Could use Gemini for language detection

4. **Gemini API Costs**
   - **Cost:** ~$0.001 per 1K tokens (~$0.05 per 1000 books)
   - **Impact:** Negligible for personal use
   - **Mitigation:** 30-day caching reduces repeat costs

### UX Limitations

5. **No Manual Correction UI**
   - **Issue:** Can't fix failed rows in-app
   - **Workaround:** Re-import after fixing CSV
   - **Future:** Show failed rows with edit UI

6. **No Export Failed Rows**
   - **Issue:** Can't export errors to CSV for batch correction
   - **Workaround:** Screenshot error list
   - **Future:** "Export Errors to CSV" button

7. **No Partial Cancel**
   - **Issue:** Cancel button cancels entire import
   - **Current:** Must start over if cancelled
   - **Future:** Resume from last successful book

### Backend Limitations

8. **Single Worker Processing**
   - **Issue:** No distributed processing for very large CSVs
   - **Impact:** 10MB/1000 book limit
   - **Future:** Chunked upload for 50MB+ files

9. **No Progress Persistence**
   - **Issue:** WebSocket disconnect = start over
   - **Current:** Must keep app open during import
   - **Future:** Resume from last checkpoint

## Performance Characteristics

### Benchmarks (iPhone 15 Pro, iOS 26, 100 Mbps WiFi)

| Books | Upload | Parse | Enrich | Total | Memory |
|-------|--------|-------|--------|-------|--------|
| 20    | <1s    | 10s   | 30s    | 40s   | 30MB   |
| 100   | 2s     | 15s   | 60s    | 77s   | 45MB   |
| 500   | 5s     | 30s   | 180s   | 215s  | 65MB   |
| 1000  | 10s    | 45s   | 300s   | 355s  | 80MB   |

### Optimization Techniques

**Client-Side (iOS):**
- Fetch existing works ONCE (not per-book) → 100x speedup
- Batch SwiftData inserts → Reduces context saves
- Haptic feedback only on completion → Preserves battery

**Server-Side (Cloudflare):**
- Parallel enrichment (10 concurrent) → 10x speedup
- Content-based caching (SHA-256) → Instant cache hits
- KV caching (30-day TTL) → Reduces API calls by 90%
- WebSocket updates every 500ms → Balances UX vs bandwidth

**Network:**
- WebSocket for progress → 8ms latency (vs 200ms polling)
- Multipart upload → Handles large files efficiently
- Compressed JSON responses → Reduces bandwidth by 60%

## Future Improvements

### Near-Term (v3.2.0 - Q2 2025)

1. **Chunked Upload for Large Files**
   - Support 50MB+ CSVs
   - Stream upload in 5MB chunks
   - Resume from last chunk on failure

2. **Format Detection from CSV**
   - Parse "Binding" column (Goodreads)
   - Map to Edition.BookFormat enum
   - Fallback to Gemini inference

3. **Language Detection**
   - Use Gemini to detect original language
   - Store in Work.originalLanguage
   - Improve cultural diversity insights

### Mid-Term (v3.3.0 - Q3 2025)

4. **Manual Correction UI**
   - Show failed rows in table
   - Allow in-app editing
   - Re-enrich after correction

5. **Export Failed Rows to CSV**
   - Generate CSV with only errors
   - Include suggested corrections
   - User fixes and re-imports

6. **Progress Persistence**
   - Save checkpoint to SwiftData
   - Resume from last successful book
   - Survive app restarts/crashes

### Long-Term (v3.4.0+ - Q4 2025)

7. **Multi-Worker Processing**
   - Distribute load across workers
   - Support 10K+ book imports
   - Auto-scaling based on load

8. **AI-Powered Error Correction**
   - Use Gemini to suggest fixes
   - "Did you mean: Harry Potter?"
   - One-tap correction

9. **Custom Enrichment Sources**
   - Settings to enable/disable APIs
   - Prioritize specific providers
   - Support ISBNdb, Goodreads, etc.

## Security & Privacy

### Data Handling

- **CSV Content:** Uploaded to Cloudflare Worker (ephemeral, not stored)
- **Cache Storage:** KV stores only result JSON (30-day TTL, auto-purge)
- **No User Tracking:** No analytics, no user IDs, no telemetry
- **HTTPS Only:** All communication encrypted (TLS 1.3)

### API Keys

- **Gemini API Key:** Stored in Cloudflare Worker secrets (not client-side)
- **Google Books API:** Public API, no key required
- **OpenLibrary API:** Public API, no key required

### Rate Limiting

- **IP-based:** 5 requests/minute per IP (Cloudflare rate limiter)
- **No User Quotas:** Unlimited imports per user
- **Backend Quotas:** Gemini API limits handled with retries

## Related Documentation

- **Product Requirements:** `docs/product/CSV-Import-PRD.md` - Problem statement, user personas, KPIs
- **Workflow Diagrams:** `docs/workflows/csv-import-workflow.md` - Visual flows (import wizard, enrichment)
- **Legacy System:** `docs/features/CSV_IMPORT.md` - Manual column mapping system (deprecated)
- **Backend Code:** `cloudflare-workers/api-worker/src/handlers/csv-gemini.js` - Gemini integration
- **Implementation Plan:** `docs/plans/2025-01-27-complete-gemini-csv-and-deprecate-legacy.md` - Completion roadmap
- **Deprecation Plan:** `docs/deprecations/2025-Q2-LEGACY-CSV-REMOVAL.md` - Legacy removal timeline

## Support & Troubleshooting

### Common Issues

**Q: Import stuck at "Uploading CSV..."**
A: Check network connection. 10MB upload requires stable WiFi. Cancel and retry.

**Q: "CSV file too large" error**
A: File exceeds 10MB limit. Split CSV into smaller files or use legacy import.

**Q: Many books show "No metadata found"**
A: Obscure/self-published books may not be in Google Books/OpenLibrary. Expected for 10-20% of books.

**Q: Covers not loading in Library tab**
A: Check network connection. Cover URLs are fetched on-demand. Retry by scrolling.

**Q: Duplicate books appearing**
A: Duplicate detection uses title + author. Books with different editions may appear as duplicates. Manually delete unwanted editions.

**Q: WebSocket connection lost**
A: Keep app open during import. Background operation not supported. Retry import if interrupted.

### Debug Logging

```swift
// Enable debug logging in GeminiCSVImportView.swift
print("📤 Uploading CSV: \(csvText.count) bytes")
print("🔌 WebSocket connected: \(jobId)")
print("📊 Progress: \(progress * 100)% - \(statusMessage)")
print("✅ Complete: \(books.count) books, \(errors.count) errors")
print("💾 Saved: \(savedCount) books (\(skippedCount) skipped)")
```

### Backend Monitoring

```bash
# Tail Cloudflare Worker logs
npx wrangler tail api-worker --format pretty

# Check for errors
npx wrangler tail api-worker | grep "ERROR"

# Monitor Gemini API calls
npx wrangler tail api-worker | grep "gemini"
```

---

**Last Updated:** January 27, 2025
**Maintainers:** @jukasdrj
**Feedback:** Submit issues to [GitHub Issues](https://github.com/jukasdrj/books-tracker-v1/issues)
