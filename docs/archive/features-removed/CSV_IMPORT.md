# CSV Import & Enrichment System

**Status:** ✅ Production (Build 45+)
**Performance:** 100 books/min, <200MB memory (1500+ books)
**Success Rate:** 95%+ duplicate detection, 90%+ enrichment success
**Last Updated:** October 2025

## Overview

Bulk import personal library from CSV exports (Goodreads, LibraryThing, StoryGraph) with automatic metadata enrichment via Cloudflare Workers API.

## Quick Start

```swift
// SettingsView
Button("Import CSV Library") { showingCSVImport = true }
    .sheet(isPresented: $showingCSVImport) { CSVImportFlowView() }
```

## Key Files

### Core Services
- `CSVParsingActor.swift` - High-performance CSV parsing (@globalActor)
- `CSVImportService.swift` - SwiftData import orchestration
- `EnrichmentService.swift` - API enrichment logic
- `EnrichmentQueue.swift` - Background enrichment queue (@MainActor)

### UI Layer
- `CSVImportFlowView.swift` - Multi-step import wizard
- `EnrichmentProgressBanner.swift` - Real-time progress UI

### Utilities
- `String+TitleNormalization.swift` - Title normalization for better API matching

## Architecture

```
CSV File
    ↓
CSVParsingActor (@globalActor)
    ↓ ParsedRow objects
CSVImportService
    ↓ SwiftData models
EnrichmentQueue (@MainActor)
    ↓ Background jobs
EnrichmentService
    ↓ API calls
Cloudflare Workers (books-api-proxy)
```

## Format Support

**Auto-Detection:** System automatically detects column mappings for:

1. **Goodreads**
   - Title: "Title"
   - Author: "Author"
   - ISBN: "ISBN" or "ISBN13"
   - Rating: "My Rating"
   - Status: "Exclusive Shelf"

2. **LibraryThing**
   - Title: "TITLE"
   - Author: "AUTHOR (first, last)"
   - ISBN: "ISBN"
   - Rating: "RATING"

3. **StoryGraph**
   - Title: "Title"
   - Authors: "Authors"
   - ISBN: "ISBN/UID"
   - Star Rating: "Star Rating"
   - Read Status: "Read Status"

## Title Normalization for Better Enrichment

### Problem

CSV exports (especially Goodreads) contain titles with:
- Series markers: `(Harry Potter, #1)`
- Subtitles: `Title: The Complete Edition`
- Edition details: `[Special Edition]`

These cause zero-result API searches, reducing enrichment success to ~70%.

### Solution: Two-Tier Title Storage

1. **Original Title** (`work.title`): Stored in SwiftData for display
2. **Normalized Title** (`title.normalizedTitleForSearch`): Used for API searches only

### Normalization Algorithm

```swift
// String+TitleNormalization.swift
extension String {
    var normalizedTitleForSearch: String {
        var result = self

        // 1. Remove series markers: (Series, #1)
        result = result.replacingOccurrences(
            of: #"\s*\([^)]*,\s*#\d+\)"#,
            with: "",
            options: .regularExpression
        )

        // 2. Remove edition markers: [Special Edition]
        result = result.replacingOccurrences(
            of: #"\s*\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )

        // 3. Strip subtitles (for titles > 10 chars)
        if result.count > 10, let colonIndex = result.firstIndex(of: ":") {
            result = String(result[..<colonIndex])
        }

        // 4. Clean abbreviations: Dept. → Dept
        result = result.replacingOccurrences(of: ".", with: "")

        // 5. Normalize whitespace
        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        return result
    }
}
```

### Examples

```
Input: "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)"
Original: "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)"
Normalized: "Harry Potter and the Sorcerer's Stone"

Input: "The da Vinci Code: The Young Adult Adaptation"
Original: "The da Vinci Code: The Young Adult Adaptation"
Normalized: "The da Vinci Code"

Input: "1984 [50th Anniversary Edition]"
Original: "1984 [50th Anniversary Edition]"
Normalized: "1984"
```

### Implementation

**CSVParsingActor.swift** (lines 49-51, 286-294):
```swift
struct ParsedRow {
    let title: String
    let normalizedTitle: String
    let authors: [String]
    // ... other fields
}

// During parsing
let normalizedTitle = cleanTitle.normalizedTitleForSearch
```

**CSVImportService.swift:**
```swift
// Store original title in SwiftData
let work = Work(
    title: row.title,  // Original with series markers
    publicationYear: row.year
)
modelContext.insert(work)
```

**EnrichmentService.swift** (lines 35-77, 138-167):
```swift
func enrichWork(_ work: Work) async throws -> EnrichmentResult {
    // Use normalized title for API search
    let searchTitle = work.title.normalizedTitleForSearch
    let results = try await apiClient.searchTitle(searchTitle)
    // ...
}

func findBestMatch(results: [APIResult], work: Work) -> APIResult? {
    let normalized = work.title.normalizedTitleForSearch

    for result in results {
        var score = 0

        // Prioritize normalized title matching (100/50 points)
        if result.title.lowercased() == normalized.lowercased() {
            score += 100
        } else if result.title.lowercased().contains(normalized.lowercased()) {
            score += 50
        }

        // Fallback to raw title matching (30/15 points)
        if result.title.lowercased() == work.title.lowercased() {
            score += 30
        } else if result.title.lowercased().contains(work.title.lowercased()) {
            score += 15
        }

        // Author matching, year matching, etc.
        // ...

        if score >= 60 { return result }
    }
    return nil
}
```

### Testing

**StringTitleNormalizationTests.swift** - 13 comprehensive test cases:
- Series markers removal
- Edition markers removal
- Subtitle stripping
- Abbreviation normalization
- Whitespace normalization
- Edge cases (empty strings, special characters)

### Expected Impact

- Enrichment success rate: 70% → 90%+
- Fewer "Not Found" results during import
- Better automatic matching for series books
- Preserves original titles for user display

## SyncCoordinator Pattern (Build 46+)

### Overview

Centralized job orchestration for multi-step background operations with type-safe progress tracking.

### Architecture

```
SyncCoordinator (Singleton @MainActor)
    ↓
JobModels (JobIdentifier, JobStatus, JobProgress)
    ↓
Services (CSVImportService, EnrichmentService) - Stateless Result-based APIs
    ↓
UI Observes @Published Job Status
```

### Key Files

- `SyncCoordinator.swift` - Central orchestrator
- `JobModels.swift` - Type-safe job tracking
- `SyncCoordinatorTests.swift` - Comprehensive test suite
- `docs/architecture/SyncCoordinator-Architecture.md` - Full design docs

### Usage

```swift
@StateObject private var coordinator = SyncCoordinator.shared

// Start CSV import job
let jobId = await coordinator.startCSVImport(
    csvContent: content,
    mappings: mappings,
    strategy: .smart,
    modelContext: modelContext
)

// Monitor progress
if let status = coordinator.getJobStatus(for: jobId) {
    switch status {
    case .active(let progress):
        ProgressView(value: progress.fractionCompleted)
        Text(progress.currentStatus)

    case .completed(let log):
        ForEach(log, id: \.self) { Text($0) }

    case .failed(let error):
        Text("Error: \(error)")

    default:
        ProgressView()
    }
}
```

### Migration Status

CSVImportService maintains backward compatibility with legacy `@Published` API while new code uses SyncCoordinator for enhanced type safety and centralized management.

## Enrichment Progress Banner (Build 45+)

### Architecture

**NotificationCenter-based** (NO Live Activity entitlements required!)

### Features

- Real-time progress: "Enriching Metadata... 15/100 (15%)"
- Theme-aware gradient backgrounds
- Pulsing icon animation
- WCAG AA compliant contrast
- Dismissible with "Got it" button

### Implementation

**ContentView.swift** (lines 9-12, 65-96, 272-365):
```swift
@State private var showEnrichmentBanner = false
@State private var enrichmentProgress: (current: Int, total: Int) = (0, 0)

var body: some View {
    ZStack(alignment: .top) {
        // Main content

        if showEnrichmentBanner {
            EnrichmentProgressBanner(
                isShowing: $showEnrichmentBanner,
                current: enrichmentProgress.current,
                total: enrichmentProgress.total
            )
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .enrichmentProgressUpdated)) { notification in
        // Update progress from notification
    }
}
```

**EnrichmentQueue.swift** (lines 174-179, 210-219, 235-239):
```swift
// Post progress notifications
NotificationCenter.default.post(
    name: .enrichmentProgressUpdated,
    object: nil,
    userInfo: [
        "current": completedCount,
        "total": totalCount
    ]
)
```

## Queue Self-Cleaning

### Problem

SwiftData persistent IDs can outlive their models (deletion, schema changes), causing enrichment queue to process non-existent works.

### Solution

**Startup Validation** (EnrichmentQueue.swift):
```swift
func validateQueue() {
    for id in workQueue {
        guard let work = try? modelContext.model(for: id) as? Work else {
            // Remove stale ID
            workQueue.remove(id)
            continue
        }
    }
}
```

**Graceful Processing:**
```swift
func processNextWork() async {
    guard let workId = workQueue.first else { return }

    // Validate existence before processing
    guard let work = try? modelContext.model(for: workId) as? Work else {
        workQueue.remove(workId)
        return processNextWork()  // Try next work
    }

    // Process valid work
    await enrichWork(work)
}
```

### When Validation Runs

1. App launch (ContentView.onAppear)
2. Before processing each work
3. After CSV import completion
4. Manual "Retry Failed" action

See `docs/archive/csvMoon-implementation-notes.md` for detailed implementation history.

## Performance Characteristics

### Memory Usage

- **Peak Memory**: <200MB for 1500+ book imports
- **Strategy**: Streaming parser, batch SwiftData inserts
- **Garbage Collection**: Automatic cleanup after each batch

### Speed Benchmarks

| Books | Import Time | Enrichment Time | Total |
|-------|-------------|-----------------|-------|
| 100   | ~30s        | ~2-3 min        | ~3.5 min |
| 500   | ~2.5 min    | ~10-12 min      | ~14 min |
| 1500  | ~7.5 min    | ~30-35 min      | ~42 min |

### Duplicate Detection

**Algorithm:**
1. Exact title + author match (primary)
2. ISBN match (if available)
3. Normalized title + fuzzy author match (fallback)

**Success Rate:** 95%+ duplicate prevention

### Enrichment Success

**Current Metrics (October 2025):**
- Title normalization enabled: **90%+ success**
- Before normalization: ~70% success
- Popular books: 95%+ success
- Obscure/self-published: 70-80% success

## Common Patterns

### Starting CSV Import

```swift
let importService = CSVImportService(modelContext: modelContext)

let result = await importService.importCSV(
    content: csvString,
    mappings: columnMappings,
    strategy: .smart  // or .replaceAll, .skipDuplicates
)

switch result {
case .success(let summary):
    print("Imported \(summary.imported) books")
    print("Skipped \(summary.duplicates) duplicates")

case .failure(let error):
    print("Import failed: \(error)")
}
```

### Manual Enrichment

```swift
let enrichmentService = EnrichmentService()

let result = try await enrichmentService.enrichWork(work)

switch result {
case .found(let metadata):
    work.coverImageURL = metadata.coverUrl
    work.isbn = metadata.isbn

case .notFound:
    print("No metadata found")

case .uncertain(let candidates):
    // Show user picker for ambiguous results
}
```

### Queue Management

```swift
// Add single work
await EnrichmentQueue.shared.add(work.persistentModelID)

// Add multiple works
let workIds = works.map(\.persistentModelID)
await EnrichmentQueue.shared.addMultiple(workIds)

// Check queue status
let count = EnrichmentQueue.shared.queueCount
let isProcessing = EnrichmentQueue.shared.isProcessing
```

## Testing

### Unit Tests

- `CSVParsingActorTests.swift` - Parser correctness
- `StringTitleNormalizationTests.swift` - Normalization algorithm
- `EnrichmentServiceTests.swift` - Matching logic
- `SyncCoordinatorTests.swift` - Job orchestration

### Integration Tests

```swift
@Test func importLargeLibrary() async throws {
    let csv = loadTestCSV(bookCount: 1500)
    let result = await importService.importCSV(content: csv)

    #expect(result.imported > 1400)  // 95%+ success
    #expect(result.duplicates < 100)
}
```

### Manual Testing

Test CSV files in `docs/testData/`:
- `goodreads-sample-100.csv` - Small Goodreads export
- `librarything-sample-500.csv` - Medium LibraryThing export
- `storygraph-sample-1500.csv` - Large StoryGraph export

## Future Enhancements

See [GitHub Issue #27](https://github.com/jukasdrj/books-tracker-v1/issues/27) for planned improvements:
- Progress persistence across app restarts
- Partial import recovery
- Custom column mapping UI
- Export enriched library back to CSV

---

## Related Documentation

- **Product Requirements:** `docs/product/CSV-Import-PRD.md` - Problem statement, user personas, KPIs
- **Workflow Diagrams:** `docs/workflows/csv-import-workflow.md` - Visual flows (import wizard, duplicate detection, enrichment)
- **Title Normalization Tests:** `BooksTrackerPackage/Tests/.../StringTitleNormalizationTests.swift` - Algorithm verification
- **Enrichment Workflow:** `docs/workflows/enrichment-workflow.md` - Background metadata fetching
- **SyncCoordinator:** `docs/architecture/SyncCoordinator-Architecture.md` - Job orchestration pattern
- **Backend Code:** `cloudflare-workers/api-worker/src/handlers/search.js` - Enrichment API
