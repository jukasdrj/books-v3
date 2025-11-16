# 📚 BooksTrack by oooe - Claude Code Guide

**Version 3.7.5 (Build 189+)** | **iOS 26.0+** | **Swift 6.1+** | **Updated: November 15, 2025**

**Native iOS book tracking app** with cultural diversity insights. SwiftUI, SwiftData, CloudKit sync.

**🎉 NOW ON APP STORE!** Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`

**📚 DOCUMENTATION HUB:** See `docs/README.md` for complete documentation navigation (PRDs, workflows, feature guides)

**🎯 EXPERTISE FOCUS:**
- **Swift 6.2** expertise required (concurrency, typed throws, strict data isolation)
- **SwiftUI** best practices (iOS 26 HIG compliance, Liquid Glass design)
- **SwiftData** mastery (persistent identifiers, CloudKit sync, relationship management)
- **Backend API v2.0:** All backend communication follows v2.0 canonical contract (December 1, 2025+)

**🤖 AI CONTEXT FILES:**
- **This file:** Claude Code development guide (primary)
- **`.ai/SHARED_CONTEXT.md`:** Project-wide AI context (tech stack, architecture, critical rules)
- **`.github/copilot-instructions.md`:** GitHub Copilot setup
- **`.ai/README.md`:** AI context organization guide

## Quick Start

ast-grep (sg) is available and SHALL be prioritized for syntax-aware searches --lang swift
Example usage for Swift (conceptual):
To find all public methods in a Swift file:
Code

ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' your_swift_file.swift

This command uses the --lang swift flag to specify the language and a pattern to match public function declarations, where $METHOD captures the function name and $$$ represents arbitrary arguments and function body content.

**Note:** Implementation plans tracked in [GitHub Issues](https://github.com/users/jukasdrj/projects/2).

### Core Stack
- **SwiftUI** - @Observable, @State, @Bindable (iOS 26 HIG patterns)
- **SwiftData** - CloudKit sync, persistent identifiers, relationships
- **Swift 6.2** - Strict concurrency (@MainActor, actors, typed throws)
- **Swift Testing** - @Test, #expect, parameterized tests
- **iOS 26 Design** - Liquid Glass, semantic colors, system fonts

### Essential Commands

**🚀 iOS Development (MCP-Powered):**
```bash
/build         # Quick build check
/test          # Run Swift Testing suite
/device-deploy # Deploy to iPhone/iPad
/sim           # Launch with log streaming
```
See **[MCP_SETUP.md](MCP_SETUP.md)** for XcodeBuildMCP configuration.

**Note:** Backend is in separate repository. iOS codebase follows canonical API contract (see Backend API Contract section).

### App Launch Architecture (Nov 2025 Optimization)

**Performance:** 600ms cold launch (down from 1500ms - 60% faster!)

**Flow:**
```
App Launch → Lazy ModelContainer Init → ContentView Renders → [Deferred 2s] Background Tasks
              (on-demand, ~200ms)        (instant)              (non-blocking)
```

**Key Components:**
- **ModelContainerFactory** - Lazy singleton pattern, container created on first access (not at app init)
- **BackgroundTaskScheduler** - Defers non-critical tasks by 2 seconds with low priority
- **LaunchMetrics** - Performance tracking for debug builds (milestone logging)

**Task Prioritization:**
- **Immediate:** UI rendering, ModelContainer creation (on-demand)
- **Deferred (2s):** EnrichmentQueue validation, ImageCleanupService, SampleDataGenerator, NotificationCoordinator

**Optimizations:**
- Lazy properties: Container, DTOMapper, LibraryRepository (~200ms off critical path)
- Task deferral: Background work delayed by 2s (~400ms off critical path)
- Micro-optimizations: Early exits, caching, predicate filtering (~180ms saved)

**Performance Instrumentation:**
- `LaunchMetrics.recordMilestone()` - Track initialization milestones
- `AppLaunchPerformanceTests` - CI regression tests
- Console logs in debug builds (full report 5s after launch)

**Results:** `docs/performance/2025-11-04-app-launch-optimization-results.md`

## Architecture

### SwiftData Models

**Entities:** Work, Edition, Author, UserLibraryEntry

**Relationships:**
```
Work 1:many Edition
Work many:many Author
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

**CloudKit Rules:**
- Inverse relationships MUST be declared on to-many side only
- All attributes need defaults
- All relationships optional
- Predicates can't filter on to-many (filter in-memory)

**🚨 CRITICAL: SwiftData Persistent Identifier Lifecycle**

SwiftData objects go through two ID states:
1. **Temporary ID** - Assigned by `modelContext.insert()` (in-memory only)
2. **Permanent ID** - Assigned by `modelContext.save()` (persisted to disk)

**NEVER use `persistentModelID` before calling `save()`!**

```swift
// ❌ WRONG: Using ID before save() - CRASH!
let work = Work(title: "...")
modelContext.insert(work)  // Assigns TEMPORARY ID
let id = work.persistentModelID  // ❌ Still temporary!
// Later when enrichment tries to use this ID:
// Fatal error: "Illegal attempt to create a full future for a temporary identifier"

// ✅ CORRECT: Save BEFORE capturing IDs
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]  // Relationships use temporary IDs (OK)
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Now safe to use!
```

**Insert-Before-Relate Rule:**
```swift
// ❌ WRONG: Setting relationship during initialization
let work = Work(title: "...", authors: [author])  // Crash!
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE setting relationships
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]  // Set relationship AFTER both are inserted
```

**Rules:**
1. Always `insert()` immediately after creating models
2. Set relationships AFTER both objects are inserted
3. Call `save()` before using `persistentModelID` for anything (enrichment queue, notifications, etc.)
4. Temporary IDs cannot be used for futures, deduplication, or background tasks

### State Management - No ViewModels!

**Pattern: @Observable models + @State**
```swift
@Observable
class SearchModel {
    var state: SearchViewState = .initial(trending: [], recentSearches: [])
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch searchModel.state {
        case .initial(let trending, _): TrendingBooksView(trending: trending)
        case .results(_, _, let items, _, _): ResultsListView(items: items)
        // ... handle all cases
        }
    }
}
```

**Property Wrappers:**
- `@State` - View-specific state and model objects
- `@Observable` - Observable model classes (replaces ObservableObject)
- `@Environment` - Dependency injection (ThemeStore, ModelContext)
- `@Bindable` - **CRITICAL for SwiftData models!** Enables reactive updates on relationships

**🚨 CRITICAL: @Bindable for SwiftData Reactivity**
```swift
// ❌ WRONG: View won't update when rating changes
struct BookDetailView: View {
    let work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}

// ✅ CORRECT: @Bindable observes changes
struct BookDetailView: View {
    @Bindable var work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}
```

### LibraryRepository Performance (Issue #217)

**Optimized Methods:**
- `totalBooksCount()`: Uses `fetchCount()` (10x faster, 0.5ms for 1000 books)
- `reviewQueueCount()`: Database-level count with predicate (8x faster)
- `fetchByReadingStatus()`: Predicate filtering before object loading (3-5x faster)

**Type Safety:**
- `calculateReadingStatistics()` returns `ReadingStatistics` struct (not unsafe dictionary)
- Compile-time safety prevents runtime crashes from typos/wrong types

**Image Proxy (#147):**
- All cover images routed through backend `/images/proxy` endpoint
- R2 caching for 50%+ faster loads
- Backend handles normalization + caching

### Backend API Contract (Canonical DTOs)

**🚨 CRITICAL:** All backend communication MUST adhere to v2.0 canonical contract. Backend API_CONTRACT.md is the **single source of truth**.

### Base URLs

| Environment | HTTP API | WebSocket API |
|-------------|----------|---------------|
| **Production** | `https://api.oooefam.net` | `wss://api.oooefam.net/ws/progress` |
| **Staging** | `https://staging-api.oooefam.net` | `wss://staging-api.oooefam.net/ws/progress` |
| **Local Dev** | `http://localhost:8787` | `ws://localhost:8787/ws/progress` |

### API Version

- **Current:** v2.0 (Production, November 15, 2025+)
- **Legacy:** v1.0 (Deprecated - sunset March 1, 2026)

**iOS Implementation:** Swift Codable DTOs in `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/`
- `WorkDTO` - Abstract creative work (mirrors SwiftData Work model)
- `EditionDTO` - Physical/digital manifestation (multi-ISBN support)
- `AuthorDTO` - Creator with cultural diversity analytics (Wikidata enrichment)

**Response Envelope (v2):** All `/v1/*` endpoints return:
```swift
struct ResponseEnvelope<T: Codable>: Codable {
    let data: T?                    // Payload (null on error)
    let metadata: ResponseMetadata  // Always present
    let error: APIError?            // Present only on error
}

struct ResponseMetadata: Codable {
    let timestamp: String           // ISO 8601 UTC
    let processingTime: Int?        // Milliseconds
    let provider: String?           // "google-books" | "openlibrary" | "isbndb" | "gemini"
    let cached: Bool?               // true if served from cache
}

struct APIError: Codable {
    let message: String             // Human-readable
    let code: String?               // Machine-readable (e.g., "NOT_FOUND")
    let details: AnyCodable?        // Optional context
}
```

**V1 Endpoints (Production Ready):**
- `GET /v1/search/title?q={query}` - Title search (fuzzy, up to 20 results)
- `GET /v1/search/isbn?isbn={isbn}` - ISBN lookup (ISBN-10 or ISBN-13)
- `GET /v1/search/advanced?title={title}&author={author}` - Multi-field search
- `GET /v1/scan/results/{jobId}` - ✅ Fetch AI scan results (24hr TTL)
- `GET /v1/csv/results/{jobId}` - ✅ Fetch CSV import results (24hr TTL)
- `GET /ws/progress?jobId={uuid}&token={token}` - WebSocket progress (all jobs)

**Error Codes:**
- `INVALID_ISBN` - Invalid ISBN format (HTTP 400)
- `INVALID_QUERY` - Missing/invalid query parameter (HTTP 400)
- `INVALID_REQUEST` - Malformed request body (HTTP 400)
- `NOT_FOUND` - Resource not found (HTTP 404)
- `RATE_LIMIT_EXCEEDED` - Too many requests (HTTP 429, retryable)
- `PROVIDER_TIMEOUT` - External API timeout (HTTP 504, retryable)
- `PROVIDER_ERROR` - External API error (HTTP 502, retryable)
- `INTERNAL_ERROR` - Server error (HTTP 500, retryable)

**Error Detection (v2):**
```swift
// Check for errors using EITHER pattern:

// Pattern 1: Check error field
if let error = envelope.error {
    throw APIError.serverError(error.message, code: error.code)
}

// Pattern 2: Check data field for null
guard let data = envelope.data else {
    throw APIError.noData
}
```

**DTO Schemas (v2.0 - Complete):**

**WorkDTO:**
```swift
struct WorkDTO: Codable {
    // ========== REQUIRED FIELDS ==========
    let title: String
    let subjectTags: [String]            // Always present (can be empty)
    let goodreadsWorkIDs: [String]       // Always present (can be empty)
    let amazonASINs: [String]            // Always present (can be empty)
    let librarythingIDs: [String]        // Always present (can be empty)
    let googleBooksVolumeIDs: [String]   // Always present (can be empty)
    let isbndbQuality: Int               // 0-100, always present
    let reviewStatus: ReviewStatus       // Always present
    
    // ========== OPTIONAL METADATA ==========
    let originalLanguage: String?        // ISO 639-1 (e.g., "en", "fr")
    let firstPublicationYear: Int?       // Year only (e.g., 1925)
    let description: String?             // Synopsis
    let coverImageURL: String?           // High-res (1200px width)
    
    // ========== PROVENANCE ==========
    let synthetic: Bool?                 // true if Work inferred from Edition
    let primaryProvider: String?         // "google-books" | "openlibrary" | "isbndb" | "gemini"
    let contributors: [String]?          // All providers that contributed
    
    // ========== EXTERNAL IDs (LEGACY - SINGLE VALUES) ==========
    let openLibraryID: String?           // e.g., "OL12345W"
    let openLibraryWorkID: String?       // Alias for openLibraryID
    let isbndbID: String?
    let googleBooksVolumeID: String?     // Deprecated: use googleBooksVolumeIDs[]
    let goodreadsID: String?             // Deprecated: use goodreadsWorkIDs[]
    
    // ========== QUALITY METRICS ==========
    let lastISBNDBSync: String?          // ISO 8601 timestamp
    
    // ========== AI SCAN METADATA ==========
    let originalImagePath: String?       // Source image for AI-detected books
    let boundingBox: BoundingBox?        // Book location in image
}

struct BoundingBox: Codable {
    let x: Double       // 0.0-1.0 (normalized)
    let y: Double       // 0.0-1.0 (normalized)
    let width: Double   // 0.0-1.0 (normalized)
    let height: Double  // 0.0-1.0 (normalized)
}

enum ReviewStatus: String, Codable {
    case verified = "verified"
    case needsReview = "needsReview"
    case userEdited = "userEdited"
}
```

**EditionDTO:**
```swift
struct EditionDTO: Codable {
    // ========== REQUIRED FIELDS ==========
    let isbns: [String]                  // All ISBNs (can be empty)
    let format: EditionFormat            // Always present
    let amazonASINs: [String]            // Always present (can be empty)
    let googleBooksVolumeIDs: [String]   // Always present (can be empty)
    let librarythingIDs: [String]        // Always present (can be empty)
    let isbndbQuality: Int               // 0-100, always present
    
    // ========== OPTIONAL IDENTIFIERS ==========
    let isbn: String?                    // Primary ISBN (first from isbns array)
    
    // ========== OPTIONAL METADATA ==========
    let title: String?
    let publisher: String?
    let publicationDate: String?         // YYYY-MM-DD or YYYY
    let pageCount: Int?
    let coverImageURL: String?
    let editionTitle: String?            // e.g., "Deluxe Illustrated Edition"
    let editionDescription: String?      // ⚠️ NOT 'description' (Swift @Model reserved)
    let language: String?                // ISO 639-1 code
    
    // ========== PROVENANCE ==========
    let primaryProvider: String?
    let contributors: [String]?
    
    // ========== EXTERNAL IDs (LEGACY) ==========
    let openLibraryID: String?
    let openLibraryEditionID: String?
    let isbndbID: String?
    let googleBooksVolumeID: String?     // Deprecated: use googleBooksVolumeIDs[]
    let goodreadsID: String?
    
    // ========== QUALITY METRICS ==========
    let lastISBNDBSync: String?          // ISO 8601 timestamp
}

enum EditionFormat: String, Codable {
    case hardcover = "Hardcover"
    case paperback = "Paperback"
    case ebook = "E-book"
    case audiobook = "Audiobook"
    case massMarket = "Mass Market"
}
```

**AuthorDTO:**
```swift
struct AuthorDTO: Codable {
    // ========== REQUIRED FIELDS ==========
    let name: String
    let gender: AuthorGender             // Always present (Wikidata enriched)
    
    // ========== OPTIONAL CULTURAL DIVERSITY FIELDS ==========
    let culturalRegion: CulturalRegion?  // Wikidata enriched
    let nationality: String?             // e.g., "Nigeria", "United States"
    let birthYear: Int?
    let deathYear: Int?
    
    // ========== EXTERNAL IDs ==========
    let openLibraryID: String?
    let isbndbID: String?
    let googleBooksID: String?
    let goodreadsID: String?
    
    // ========== STATISTICS ==========
    let bookCount: Int?                  // Total books by this author
}

enum AuthorGender: String, Codable {
    case female = "Female"
    case male = "Male"
    case nonBinary = "Non-binary"
    case other = "Other"
    case unknown = "Unknown"            // Fallback if Wikidata fails
}

enum CulturalRegion: String, Codable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    case northAmerica = "North America"
    case southAmerica = "South America"
    case oceania = "Oceania"
    case middleEast = "Middle East"
    case caribbean = "Caribbean"
    case centralAsia = "Central Asia"
    case indigenous = "Indigenous"
    case international = "International"
}
```

**WebSocket v2 Contract:**

All WebSocket messages use this envelope:
```swift
struct WebSocketMessage: Codable {
    let type: String                 // "job_started" | "job_progress" | "job_complete" | "error" | "ping" | "pong"
    let jobId: String
    let pipeline: String             // "batch_enrichment" | "csv_import" | "ai_scan"
    let timestamp: Int               // Unix timestamp (milliseconds)
    let version: String              // "1.0.0"
    let payload: MessagePayload      // Type-specific data
}
```

**🚨 CRITICAL: Summary-Only Completions**

Completion messages are **summary-only** (< 1 KB). Full results fetched via HTTP GET.

**Message Types:**

1. **job_started** - Sent on WebSocket connection
   ```swift
   payload: {
       type: "job_started"
       totalItems: 10
       estimatedDuration: 30000  // milliseconds
   }
   ```

2. **job_progress** - Periodic updates (every 5-10% progress)
   ```swift
   payload: {
       type: "job_progress"
       progress: 0.5              // 0.0 to 1.0 for progress bar
       status: "Processing image 5 of 10"
       processedCount: 5
       currentItem: "IMG_1234.jpg"
   }
   ```

3. **job_complete** - Summary only (⚠️ NO large arrays!)
   ```swift
   payload: {
       type: "job_complete"
       totalDetected: 25
       approved: 20
       needsReview: 5
       resultsUrl: "/v1/scan/results/uuid-12345"  // ⚠️ Fetch full results here!
       metadata: {
           modelUsed: "gemini-2.0-flash-exp"
           processingTime: 8500
       }
   }
   ```
   
   **Client Action (MANDATORY):** Fetch full results via HTTP GET:
   ```swift
   let fullResults = try await fetchResults(url: payload.resultsUrl)
   // GET https://api.oooefam.net/v1/scan/results/uuid-12345
   ```

4. **error** - Job failure
   ```swift
   payload: {
       type: "error"
       code: "E_CSV_PROCESSING_FAILED"
       message: "Invalid CSV format: Missing title column"
       retryable: true
       details: { lineNumber: 42 }
   }
   ```

**WebSocket Close Codes:**

| Code | Name | Client Action |
|------|------|---------------|
| 1000 | NORMAL_CLOSURE | Job completed successfully |
| 1001 | GOING_AWAY | Retry after 5 seconds |
| 1002 | PROTOCOL_ERROR | Fix client implementation |
| 1008 | POLICY_VIOLATION | Re-authenticate (invalid token) |
| 1009 | MESSAGE_TOO_BIG | Reduce payload size |
| 1011 | INTERNAL_ERROR | Retry with exponential backoff |
| 1013 | TRY_AGAIN_LATER | Server overload, retry after 30s |

**WebSocket Token Management:**

- **Token Expiration:** 2 hours (7200 seconds)
- **Refresh:** ⚠️ Not yet implemented (single-use tokens only)
- **Obtain Token:** POST endpoints return `{ jobId, token }` in response

**Performance Best Practices:**

**1. Summary-Only Completions Pattern**

❌ **Old (Causes UI Freezes):**
```swift
// Waiting for 5 MB JSON array in WebSocket message
let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
let books = message.payload.books  // UI freezes 10+ seconds!
```

✅ **New (Instant Response):**
```swift
// Step 1: Receive lightweight summary via WebSocket (< 1 KB)
let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
let resultsUrl = message.payload.resultsUrl

// Step 2: Fetch full results via HTTP GET (async, background)
Task.detached {
    let results = try await fetchResults(url: resultsUrl)
    await MainActor.run { updateUI(results) }
}
```

**2. Rate Limiting**

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Search endpoints | 100 req | 1 min |
| Batch endpoints | 10 req | 1 min |
| AI scan endpoints | 5 req | 1 min |
| Global limit | 1000 req | 1 hour |

**3. Caching (Server-Side)**

- Book metadata: **24 hours** (KV cache)
- ISBN lookups: **7 days**
- Cover images: **30 days**
- AI scan results: **24 hours** (KV, then 404)
- CSV import results: **24 hours** (KV, then 404)

**4. Cultural Diversity Data**

- Enriched via **Wikidata API** (70%+ success rate)
- Fallback: `gender: "Unknown"` if Wikidata fails
- Cache TTL: **7 days** (author metadata is stable)

**iOS Services Using Contract:**
- `SearchService` - `/v1/search/*` endpoints
- `BookshelfScannerService` - `/v1/scan/results/*`
- `CSVImportService` - `/v1/csv/results/*`
- `DTOMapper` - Canonical DTO → SwiftData model mapping

**Critical Rules:**
1. **Never bypass DTOMapper** - All backend responses MUST be parsed through DTOMapper
2. **Respect provenance** - Use `synthetic` flag for deduplication logic
3. **Handle all error codes** - Display user-friendly messages for each error code
4. **Summary-only completions** - ALWAYS fetch full results via HTTP GET after WebSocket `job_complete`
5. **Cultural diversity** - Handle Wikidata enrichment failures gracefully (fallback to "Unknown")
6. **Results TTL** - Fetch results within 24 hours (KV storage expires)

**Design Documentation:**
- `docs/API_CONTRACT.md` - **SINGLE SOURCE OF TRUTH** (v2.0 canonical contract)
- `docs/FRONTEND_INTEGRATION_GUIDE.md` - Complete frontend integration patterns
- `docs/plans/2025-10-29-canonical-data-contracts-design.md` - Design rationale

### Navigation Structure

**4-Tab Layout (iOS 26 HIG Optimized):**
- **Library** - Main collection view with Settings gear icon in toolbar
- **Search** - Book search with ISBN scanner
- **Shelf** - AI-powered bookshelf scanner (Gemini 2.0 Flash)
- **Insights** - Reading statistics and cultural diversity analytics

**Settings Access:**
- Accessed via gear icon in Library tab toolbar (Books.app pattern)
- Sheet presentation with "Done" button
- Not in tab bar (4 tabs optimal per iOS 26 HIG)

**Navigation Patterns:**
```swift
// Push navigation for details
.navigationDestination(item: $selectedBook) { book in WorkDetailView(work: book.work) }

// Sheet presentation for Settings
.sheet(isPresented: $showingSettings) {
    NavigationStack { SettingsView() }
}
```

## Development Standards

### Swift 6.2 Concurrency

**Actor Isolation:**
- `@MainActor` - UI components, SwiftUI views
- `@CameraSessionActor` - Camera/AVFoundation
- `nonisolated` - Pure functions, initialization

**🚨 BAN `Timer.publish` in Actors:**
- Use `await Task.sleep(for:)` instead
- Combine doesn't integrate with Swift 6 actor isolation

**Best Practice:**
```swift
@State private var tracker = PollingProgressTracker<MyJob>()
let result = try await tracker.start(
    job: myJob,
    strategy: AdaptivePollingStrategy(),  // Battery-optimized!
    timeout: 90
)
```

**See:** `docs/CONCURRENCY_GUIDE.md` for full patterns + `docs/SWIFT6_COMPILER_BUG.md` for lessons learned.

### Cover Image Display Pattern (Nov 2025)

**Always use `CoverImageService` for cover URLs** - Provides intelligent Edition → Work fallback logic.

```swift
// ✅ CORRECT: Centralized service with fallback
import SwiftUI

struct BookCard: View {
    let work: Work

    var body: some View {
        CachedAsyncImage(url: CoverImageService.coverURL(for: work)) {
            image in image.resizable()
        } placeholder: {
            PlaceholderView()
        }
    }
}

// ❌ WRONG: Direct access without fallback
CachedAsyncImage(url: work.primaryEdition?.coverURL)  // Misses Work-level covers!
```

**Why This Matters:**
- Covers can exist at Edition level OR Work level (enrichment populates both)
- Direct access bypasses fallback logic → missing covers
- Service delegates to `EditionSelectionStrategy` (AutoStrategy prioritizes editions with covers +10 points)

**Related:**
- `CoverImageService.swift` - Service implementation
- `EditionSelectionStrategy.swift` - Edition selection logic
- `EnrichmentQueue.applyEnrichedData()` - Populates Work.coverImageURL as fallback
- `docs/architecture/2025-11-09-cover-image-display-bug-analysis.md` - Root cause analysis

### iOS 26 HIG Compliance

**🚨 CRITICAL: Don't Mix @FocusState with .searchable()**
- iOS 26's `.searchable()` manages focus internally
- Manual `@FocusState` creates keyboard conflicts

**Navigation:**
```swift
// ✅ CORRECT: Push navigation
.navigationDestination(item: $selectedBook) { book in WorkDetailView(work: book.work) }

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedBook) { ... }
```

### Code Quality

**Swift Conventions:**
- UpperCamelCase types, lowerCamelCase properties
- Use `guard let`/`if let`, avoid force unwrapping
- `struct` for models, `class` only for reference semantics

**Zero Warnings Policy:**
- All PRs must build with zero warnings
- Warnings treated as errors (`-Werror`)

**Nested Types Pattern:**
```swift
@MainActor
public class CSVImportService {
    public enum DuplicateStrategy: Sendable { case skip, update, smart }
    public struct ImportResult { let successCount: Int }
}
```

**Sendable Rule:** Don't claim Sendable for types containing SwiftData @Model objects. Use `@MainActor` isolation.

**PR Checklist:**
- [ ] Zero warnings (Swift 6 concurrency, deprecated APIs)
- [ ] @Bindable for SwiftData models in child views
- [ ] No Timer.publish in actors (use Task.sleep)
- [ ] Nested supporting types
- [ ] WCAG AA contrast (4.5:1+)
- [ ] Real device testing

## Common Tasks

### Adding Features

1. Develop in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Use `public` for types exposed to app shell
3. Add dependencies in `BooksTrackerPackage/Package.swift`
4. Add tests in `BooksTrackerPackage/Tests/`

### Library Reset

**Comprehensive Reset (Settings → Reset Library):**
- Cancels in-flight backend enrichment jobs (prevents resource waste)
- Stops local enrichment processing
- Deletes all SwiftData models (Works, Editions, Authors, UserLibraryEntries)
- Clears enrichment queue
- Resets AI provider to Gemini
- Resets feature flags to defaults
- Clears search history

**Backend Cancellation Flow:**
1. iOS calls `EnrichmentQueue.shared.cancelBackendJob()`
2. POST to `/api/enrichment/cancel` with jobId
3. Worker calls `doStub.cancelJob()` on ProgressWebSocketDO
4. DO sets "canceled" status in Durable Object storage
5. Enrichment loop checks `doStub.isCanceled()` before each book
6. If canceled, sends final status update and breaks loop

**Critical:** Backend jobs are tracked via `currentJobId` in EnrichmentQueue. Always call `setCurrentJobId()` when starting enrichment and `clearCurrentJobId()` when complete.

### Barcode Scanning

**Implementation:** Apple VisionKit `DataScannerViewController` (iOS 16+)

```swift
// Quick integration in SearchView
.sheet(isPresented: $showingScanner) {
    ISBNScannerView { isbn in
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
    }
}
```

**Key Features:**
- Native Apple barcode scanning (zero custom camera code)
- Auto-highlighting and tap-to-scan gestures
- Built-in guidance ("Move Closer", "Slow Down")
- Pinch-to-zoom support
- Automatic capability checking (`DataScannerViewController.isSupported`, `isAvailable`)
- Error states: UnsupportedDeviceView (A12+ required), PermissionDeniedView (Settings link)

**Symbologies:** EAN-13, EAN-8, UPC-E (ISBN-specific)

**See:** `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md` for architecture details

### Features

**Bookshelf AI Scanner:** See `docs/features/BOOKSHELF_SCANNER.md`
- Gemini 2.0 Flash AI (optimized, 2M token context window)
- WebSocket real-time progress (8ms latency!)
- 60% confidence threshold for review queue
- iOS preprocessing (3072px @ 90% quality, 400-600KB)

**Batch Bookshelf Scanning:** See `docs/features/BATCH_BOOKSHELF_SCANNING.md`
- Capture up to 5 photos in one session
- Parallel upload → sequential Gemini processing
- Real-time per-photo progress via WebSocket
- Automatic deduplication by ISBN
- Cancel mid-batch with partial results

**Gemini CSV Import:** AI-powered parsing with zero configuration
- Gemini 2.0 Flash API for intelligent CSV parsing
- No column mapping needed (auto-detects title, author, ISBN)
- **Unified Enrichment Pipeline:** Books saved with minimal metadata, enriched in background via `EnrichmentQueue`
  - Parse CSV (5-15s) → Save to SwiftData (<1s) → Background enrichment (1-5min)
  - Books appear instantly in library (12-17s total vs 60-120s with old inline enrichment)
  - Consistent behavior across all import sources (CSV, bookshelf scan, manual add)
- Real-time WebSocket progress tracking (parsing phase only)
- 10MB file size limit, RFC 4180 compliant
- Versioned caching with SHA-256 content hashing
- Settings → Library Management → "AI-Powered CSV Import"
- Test file: `docs/testImages/goodreads_library_export.csv`
- **Status:** ✅ Production ready (v3.1.0+)
- See `docs/features/GEMINI_CSV_IMPORT.md` for documentation

**Legacy CSV Import:** Removed in v3.3.0 (October 2025)
- Manual column mapping system discontinued
- Replaced by Gemini AI-powered import (zero config)
- Archived documentation: `docs/archive/features-removed/CSV_IMPORT.md`

**Review Queue:** See `docs/features/REVIEW_QUEUE.md`
- Human-in-the-loop for low-confidence AI detections
- CorrectionView with spine image cropping
- Automatic temp file cleanup

## Debugging

### Critical Lessons

**Real Device Testing:**
- `.navigationBarDrawer(displayMode: .always)` breaks keyboard on real devices (iOS 26 bug!)
- Always test keyboard input on physical devices
- Glass overlays need `.allowsHitTesting(false)` to pass touches through

**SwiftData:**
- Persistent IDs can outlive models → always check existence
- Clean derived data for macro issues: `rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*`

**Architecture:**
- Check provider tags: `"orchestrated:google+openlibrary"` vs `"google"`
- Direct API calls between workers = violation
- Trust runtime verification over CLI tools

## Design System

### Themes
- 5 built-in: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- `@Environment(iOS26ThemeStore.self)` for access

### Text Contrast (WCAG AA)
```swift
// ✅ Use system semantic colors (auto-adapt to backgrounds)
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)

// ❌ Don't use custom "accessible" colors (deleted v1.12.0)
```

**Rule:** `themeStore.primaryColor` for brand, `.secondary`/`.tertiary` for metadata.

## Code Search Tools

### AST-Grep (Syntax-Aware Search) - Primary Tool

**ast-grep (sg)** is available and SHALL be prioritized for all Swift code searches over ripgrep/grep.

**Why AST-Grep?**
- **Syntax-aware:** Understands Swift structure (classes, methods, properties)
- **Accurate matching:** No false positives from strings/comments
- **Refactoring-safe:** Matches code structure, not text patterns

**Common Use Cases:**

```bash
# Find all public methods
ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' .

# Find all @MainActor classes
ast-grep --lang swift --pattern '@MainActor class $NAME { $$$ }' .

# Find all SwiftData @Model classes
ast-grep --lang swift --pattern '@Model public class $NAME { $$$ }' .

# Find all Task.sleep calls (check for Timer.publish violations)
ast-grep --lang swift --pattern 'Task.sleep(for: $DURATION)' .

# Find all force unwraps (!)
ast-grep --lang swift --pattern '$VAR!' .

# Find all @Observable classes
ast-grep --lang swift --pattern '@Observable class $NAME { $$$ }' .
```

**Pattern Syntax:**
- `$VAR` - Matches single identifier (variable/function name)
- `$$$` - Matches multiple parameters/arguments
- `{ $$$ }` - Matches any block contents

**When to use ripgrep instead:**
- Searching across multiple languages (Markdown, TypeScript, etc.)
- Simple text search in non-code files
- Debugging logs/error messages

**Rule:** For Swift code queries, ALWAYS use `ast-grep` unless user explicitly requests `grep`/`ripgrep`.

## Documentation

**📚 Complete Documentation Hub:** `docs/README.md` - Navigation guide for all doc types

```
📄 CLAUDE.md                 ← This file (Swift/iOS quick reference)
📄 MCP_SETUP.md             ← XcodeBuildMCP workflows
📄 CHANGELOG.md             ← Victory stories + debugging sagas

📁 docs/
  ├── README.md             ← **START HERE** - Documentation navigation & learning paths
  ├── product/              ← PRDs (problem statements, user stories, success metrics)
  ├── workflows/            ← Mermaid diagrams (visual flows for all features)
  ├── features/             ← Technical deep-dives (implementation, patterns, lessons)
  ├── architecture/         ← System design & architectural decisions
  └── guides/               ← How-to guides & best practices

📁 .claude/commands/        ← Slash commands (4 total: iOS development only)
```

**Note:** Backend documentation is in separate repository. iOS follows canonical API contract (see Backend API Contract section).

**Documentation Types:**
- **PRDs** (`docs/product/`) - WHY features exist, WHO they're for, WHAT success looks like
- **Workflows** (`docs/workflows/`) - HOW features work (Mermaid visual diagrams)
- **Feature Docs** (`docs/features/`) - IMPLEMENTATION details (code patterns, APIs, testing)
- **CLAUDE.md** - Quick reference for active development (this file)
- **GitHub Issues** - Active tasks & roadmap

**Learning Path:**
1. New to project? → Read `docs/README.md` then scan `docs/workflows/` (visual overview)
2. Planning feature? → Create PRD from `docs/product/PRD-Template.md`
3. Implementing? → Study `docs/features/` + workflow diagrams
4. Need quick answer? → Check CLAUDE.md (this file)

**Philosophy:**
- CLAUDE.md: Current standards (<500 lines, quick reference)
- docs/features/: Deep dives with architecture + lessons
- docs/workflows/: Visual Mermaid diagrams for quick comprehension
- docs/product/: Product requirements (problem → solution mapping)
- CHANGELOG.md: Historical victories
- GitHub Issues: Active tasks

## Key Business Logic

### Reading Status
```swift
// Wishlist → Owned → Reading → Read
let entry = UserLibraryEntry.createWishlistEntry(for: work)
entry.status = .toRead; entry.edition = ownedEdition
entry.currentPage = 150; entry.status = .reading
entry.status = .read; entry.completionDate = Date()
```

### Cultural Diversity
- AuthorGender: female, male, nonBinary, other, unknown
- CulturalRegion: africa, asia, europe, northAmerica, etc.
- Marginalized Voice: Auto-detection

---

**Build Status:** ✅ Zero warnings, zero errors
**HIG Compliance:** 100% iOS 26 standards
**Swift 6.2:** Full concurrency compliance
**Accessibility:** WCAG AA compliant contrast