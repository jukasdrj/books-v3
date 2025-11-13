# BooksTrack Codebase Context

**Version:** 3.0.0 (Build 47+)
**Last Updated:** November 13, 2025

This document provides AI assistants with essential context about the BooksTrack codebase structure, domain logic, and key patterns.

---

## 📱 Project Overview

**BooksTrack** is a personal book tracking iOS app with cultural diversity insights. Users can:
- Search for books (ISBN scanner, title/author search)
- Track reading progress (wishlist → owned → reading → read)
- Scan bookshelves with AI (Gemini 2.0 Flash)
- Import libraries (Gemini-powered CSV import)
- View diversity insights (author demographics, cultural regions)

**Tech Stack:**
- **Frontend:** SwiftUI, SwiftData, CloudKit sync
- **Backend:** Cloudflare Workers (monolith), Durable Objects (WebSocket progress)
- **AI:** Gemini 2.0 Flash API (Google), multi-model via Zen MCP
- **Testing:** Swift Testing (@Test, #expect)
- **Concurrency:** Swift 6.2 (strict concurrency, @MainActor, actors)

---

## 🏗️ Architecture

### iOS App Structure

```
BooksTrackerPackage/
├── Sources/
│   ├── BooksTrackerFeature/        # Main app logic (SwiftUI + business logic)
│   │   ├── Scanning/              # AI bookshelf scanner (camera + Gemini)
│   │   ├── Search/                # Book search (ISBN + title/author)
│   │   ├── Library/               # Reading list management
│   │   ├── Insights/              # Diversity analytics
│   │   ├── Settings/              # App configuration
│   │   └── Shared/                # Reusable views + services
│   └── BooksTrackerCore/          # Models + backend integration
│       ├── Models/                # SwiftData @Model classes
│       ├── Services/              # Backend API clients
│       └── Utilities/             # Helpers + extensions
└── Tests/                         # Swift Testing suite
```

**App Shell:** `BooksTracker/BooksTrackerApp.swift` (minimal, loads package)

### Backend Structure

```
cloudflare-workers/api-worker/
├── src/
│   ├── index.js                   # Main router (RPC endpoints)
│   ├── durable-objects/           # ProgressWebSocketDO (real-time updates)
│   ├── services/                  # Business logic (AI, enrichment, search)
│   ├── providers/                 # AI provider modules (Gemini)
│   ├── handlers/                  # Request handlers
│   ├── types/                     # TypeScript canonical DTOs
│   └── utils/                     # Shared utilities (cache, normalization)
└── wrangler.toml                  # Cloudflare config
```

**Architecture:** Single monolith worker (no service bindings), KV caching, R2 image storage, WebSocket progress (all background jobs).

---

## 🗄️ Data Model

### SwiftData Entities

**Work** (Abstract creative work)
```swift
@Model public class Work {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var authors: [Author]? = []          // many-to-many
    public var editions: [Edition]? = []        // one-to-many
    public var userLibraryEntries: [UserLibraryEntry]? = []  // one-to-many
    public var primaryEdition: Edition?         // computed (selected by EditionSelectionStrategy)
    public var coverImageURL: URL?              // Fallback if no Edition covers
    public var genres: [String] = []
    public var originalPublicationYear: Int?
    public var providerTag: String?             // "google", "openlibrary", "orchestrated:google+openlibrary"
    public var isSynthetic: Bool = false        // True if inferred from Edition data
}
```

**Edition** (Physical/digital manifestation)
```swift
@Model public class Edition {
    @Attribute(.unique) public var id: UUID
    public var isbn10: String?
    public var isbn13: String?
    public var work: Work?                      // many-to-one
    public var userLibraryEntries: [UserLibraryEntry]? = []
    public var coverURL: URL?
    public var pageCount: Int?
    public var publisher: String?
    public var publishedDate: Date?
    public var language: String?
}
```

**Author**
```swift
@Model public class Author {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var works: [Work]? = []              // many-to-many
    public var gender: AuthorGender = .unknown  // Diversity analytics
    public var culturalRegion: CulturalRegion = .unknown
    public var isMarginalizedVoice: Bool = false
}
```

**UserLibraryEntry** (User's reading record)
```swift
@Model public class UserLibraryEntry {
    @Attribute(.unique) public var id: UUID
    public var work: Work?                      // many-to-one
    public var edition: Edition?                // many-to-one (specific owned edition)
    public var status: ReadingStatus = .wishlist  // wishlist, toRead, reading, read
    public var currentPage: Int?
    public var personalRating: Int?             // 1-5 stars
    public var completionDate: Date?
    public var addedDate: Date = Date()
}
```

**Enums:**
- `ReadingStatus`: wishlist, toRead, reading, read
- `AuthorGender`: female, male, nonBinary, other, unknown
- `CulturalRegion`: africa, asia, europe, northAmerica, southAmerica, oceania, middleEast, caribbean, unknown

### Relationships

**CloudKit Sync Rules:**
- Inverse relationships ONLY on to-many side
- All attributes need defaults (CloudKit requirement)
- All relationships optional (CloudKit requirement)
- Predicates can't filter on to-many relationships (filter in-memory instead)

**Persistent ID Lifecycle:**
```swift
// ❌ WRONG: Using ID before save()
let work = Work(title: "...")
modelContext.insert(work)  // Assigns TEMPORARY ID
let id = work.persistentModelID  // ❌ Crash! Still temporary!

// ✅ CORRECT: Save BEFORE using ID
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]  // Relationships OK with temporary IDs
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Safe!
```

**Insert-Before-Relate Rule:**
```swift
// ✅ CORRECT: Insert both, THEN relate
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]  // Set relationship AFTER both inserted
```

---

## 🚀 Key Services

### LibraryRepository
**Purpose:** SwiftData queries for user's library.

**Key Methods:**
- `fetchByReadingStatus(_ status: ReadingStatus) -> [UserLibraryEntry]`
- `totalBooksCount() -> Int` (optimized with `fetchCount()`)
- `reviewQueueCount() -> Int` (database-level predicate)
- `calculateReadingStatistics() -> ReadingStatistics` (type-safe struct)

**Performance:**
- Uses `fetchCount()` instead of loading all objects (10x faster)
- Predicate filtering before object materialization (3-5x faster)
- Returns type-safe structs, not dictionaries

### EnrichmentQueue
**Purpose:** Background metadata enrichment for books (covers, genres, authors).

**Flow:**
1. User adds book with minimal metadata (title, author, ISBN)
2. Book saved to SwiftData immediately (appears in library)
3. EnrichmentQueue enqueues work ID for background processing
4. Backend `/v1/enrichment/batch` fetches full metadata (genres, covers, etc.)
5. iOS applies enriched data to existing Work/Edition/Author models

**Key Methods:**
- `enqueue(_ workId: UUID)` - Add to queue
- `processNextBatch() async throws` - Process up to 10 items
- `applyEnrichedData(_ dtos: [WorkDTO]) throws` - Merge backend data

**Critical:**
- Always `save()` before calling `enqueue()` (needs permanent IDs)
- WebSocket progress for batch jobs (real-time updates)
- Cancel backend jobs on library reset (`cancelBackendJob()`)

### CoverImageService
**Purpose:** Intelligent Edition → Work fallback for cover images.

**Strategy:**
```swift
// ✅ CORRECT: Always use CoverImageService
CachedAsyncImage(url: CoverImageService.coverURL(for: work))

// ❌ WRONG: Direct access misses fallback
CachedAsyncImage(url: work.primaryEdition?.coverURL)  // Misses Work.coverImageURL!
```

**Why:** Enrichment populates covers at both Edition and Work levels. Direct access bypasses fallback logic (missing covers).

### DTOMapper
**Purpose:** Convert backend canonical DTOs to SwiftData models.

**Key Methods:**
- `mapToModels(_ dtos: [WorkDTO]) throws -> [Work]`
- Handles deduplication (by ISBN, title+author)
- Creates all relationships (Work ↔ Edition ↔ Author)
- Inserts into ModelContext
- **Requires `save()` after mapping!**

---

## 🎨 UI Architecture

### Navigation (4-Tab Layout)

```swift
TabView {
    LibraryView()       // Main collection, settings gear icon
    SearchView()        // Book search + ISBN scanner
    ShelfView()         // AI bookshelf scanner
    InsightsView()      // Diversity analytics
}
```

**Settings:** Accessed via gear icon in Library tab toolbar (not in tab bar per iOS 26 HIG).

### State Management

**Pattern:** `@Observable` models + `@State` (no ViewModels!)

```swift
@Observable
class SearchModel {
    var state: SearchViewState = .initial(...)
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch searchModel.state {
        case .initial(let trending, _): TrendingView(trending)
        case .results(_, _, let items, _, _): ResultsView(items)
        // ... handle all states
        }
    }
}
```

**Property Wrappers:**
- `@State` - View-local state and model objects
- `@Observable` - Observable model classes (Swift 6 observation)
- `@Environment` - Dependency injection (ThemeStore, ModelContext)
- `@Bindable` - **CRITICAL for SwiftData!** Enables reactive updates on relationships

**Bindable Example:**
```swift
// ❌ WRONG: View won't update when rating changes
struct BookDetailView: View {
    let work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}

// ✅ CORRECT: @Bindable observes SwiftData changes
struct BookDetailView: View {
    @Bindable var work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}
```

### Navigation Patterns

**Push Navigation (preferred):**
```swift
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}
```

**Sheet Presentation (for modals):**
```swift
.sheet(isPresented: $showingSettings) {
    NavigationStack { SettingsView() }
}
```

**Don't use sheets for drill-down navigation!** (breaks iOS 26 HIG)

---

## ☁️ Backend API

### Canonical Data Contracts (v1.0.0)

**Endpoints:**
- `GET /v1/search/title?q={query}` - Title search
- `GET /v1/search/isbn?isbn={isbn}` - ISBN lookup (validates ISBN-10/13)
- `GET /v1/search/advanced?title={title}&author={author}` - Flexible search
- `POST /v1/enrichment/batch` - Batch enrichment with WebSocket progress

**Response Envelope:**
```typescript
{
  "success": true | false,
  "data": { works: WorkDTO[], authors: AuthorDTO[] } | undefined,
  "error": { message: string, code: ApiErrorCode, details?: any } | undefined,
  "meta": { timestamp: string, processingTime: number, provider: string, cached: boolean }
}
```

**DTOs:**
- `WorkDTO` - Mirrors SwiftData Work model
- `EditionDTO` - Supports multi-ISBN (ISBN-10 + ISBN-13)
- `AuthorDTO` - Includes diversity analytics

**Provenance Tracking:**
- `primaryProvider` - "google-books", "openlibrary", etc.
- `contributors` - Array of all enrichment providers
- `synthetic` - True if Work inferred from Edition data

### Legacy Endpoints (Still Active)

- `GET /search/title?q={query}` (6h cache)
- `GET /search/isbn?isbn={isbn}` (7-day cache)
- `POST /api/enrichment/start` - **DEPRECATED** (use `/v1/enrichment/batch`)
- `POST /api/scan-bookshelf?jobId={uuid}` - Gemini 2.0 Flash AI scan
- `GET /ws/progress?jobId={uuid}` - WebSocket progress (unified for ALL jobs)

**Note:** Legacy endpoints will be removed 2-4 weeks after full iOS migration.

### AI Provider (Gemini Only)

**Gemini 2.0 Flash:**
- 2M token context window
- Processing time: 25-40s (AI inference + enrichment)
- Accuracy: 0.7-0.95 confidence scores
- Optimized for ISBN detection and small text

**Best Practices:**
- System instructions separated from dynamic content
- Image-first ordering in prompts
- Temperature: 0.2 (CSV), 0.4 (bookshelf)
- JSON output via `responseMimeType`
- Token usage logging

---

## ⚡ Performance Optimizations

### App Launch (600ms - Nov 2025)

**Flow:**
```
App Launch → Lazy ModelContainer Init → ContentView Renders → [Deferred 2s] Background Tasks
              (on-demand, ~200ms)        (instant)              (non-blocking)
```

**Key Components:**
- `ModelContainerFactory` - Lazy singleton (created on first access)
- `BackgroundTaskScheduler` - Defers non-critical tasks by 2s (low priority)
- `LaunchMetrics` - Performance tracking (debug builds only)

**Optimizations:**
- Lazy properties: Container, DTOMapper, LibraryRepository (~200ms saved)
- Task deferral: Background work delayed by 2s (~400ms saved)
- Micro-optimizations: Early exits, caching, predicate filtering (~180ms saved)

**Result:** 60% faster launch (1500ms → 600ms)

### Database Queries

**Optimized Methods:**
- `totalBooksCount()` uses `fetchCount()` (0.5ms for 1000 books)
- `reviewQueueCount()` uses database-level predicates (8x faster)
- `fetchByReadingStatus()` filters before object loading (3-5x faster)

**Image Proxy (#147):**
- All covers routed through `/images/proxy` endpoint
- R2 caching (50%+ faster loads)
- Backend normalization

**Cache Key Normalization (#197):**
- Shared utilities: `normalizeTitle()`, `normalizeISBN()`, `normalizeAuthor()`, `normalizeImageURL()`
- Impact: +15-30% cache hit rate improvement (60-70% → 75-90%)

---

## 🎨 Design System

### Themes
- 5 built-in: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- Access via `@Environment(iOS26ThemeStore.self)`

### Text Contrast (WCAG AA)
```swift
// ✅ Use system semantic colors (auto-adapt)
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)

// ❌ Don't use custom "accessible" colors (removed v1.12.0)
```

**Rule:** `themeStore.primaryColor` for brand, `.secondary`/`.tertiary` for metadata.

---

## 🧪 Testing

**Framework:** Swift Testing (@Test, #expect)

**Test Structure:**
```swift
@Test("Description of test")
func testFeature() async throws {
    #expect(actualValue == expectedValue)
}

// Parameterized tests
@Test("Multiple inputs", arguments: [1, 2, 3])
func testMultiple(input: Int) async throws {
    #expect(input > 0)
}
```

**Test Files:**
- `BooksTrackerPackage/Tests/` - Unit tests
- `AppLaunchPerformanceTests.swift` - Performance regression tests

---

## 🚨 Critical Rules

### Swift 6 Concurrency

**BAN `Timer.publish` in Actors:**
```swift
// ❌ WRONG: Combine doesn't integrate with actors
Timer.publish(every: 2, on: .main, in: .common)

// ✅ CORRECT: Use Task.sleep
while !isCancelled {
    await Task.sleep(for: .seconds(2))
    await doWork()
}
```

**Actor Isolation:**
- `@MainActor` - UI components, SwiftUI views
- `@CameraSessionActor` - Camera/AVFoundation
- `nonisolated` - Pure functions, initialization

### SwiftData

**Always `save()` before using `persistentModelID`:**
```swift
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]
try modelContext.save()  // ← CRITICAL!
let id = work.persistentModelID  // Now safe
```

**Always use `@Bindable` for child views:**
```swift
struct ParentView: View {
    @Query var works: [Work]
    var body: some View {
        WorkDetailView(work: works[0])  // Pass Work
    }
}

struct WorkDetailView: View {
    @Bindable var work: Work  // ← CRITICAL for reactive updates!
    var body: some View {
        Text(work.title)
    }
}
```

### iOS 26 HIG

**Don't mix `@FocusState` with `.searchable()`:**
```swift
// ❌ WRONG: Keyboard conflict
@FocusState var searchFocused: Bool
SearchView().searchable(...).focused($searchFocused)

// ✅ CORRECT: Let .searchable() manage focus
SearchView().searchable(...)
```

**Use push navigation, not sheets:**
```swift
// ✅ CORRECT
.navigationDestination(item: $selectedBook) { book in WorkDetailView(work: book.work) }

// ❌ WRONG: Breaks navigation stack
.sheet(item: $selectedBook) { book in WorkDetailView(work: book.work) }
```

---

## 📚 Key Documentation

- **CLAUDE.md** (root) - Quick reference for active development (<500 lines)
- **docs/README.md** - Documentation hub (navigation guide)
- **docs/features/** - Feature-specific implementation details
- **docs/workflows/** - Mermaid diagrams (visual flows)
- **docs/architecture/** - Architectural decision records
- **cloudflare-workers/MONOLITH_ARCHITECTURE.md** - Backend architecture

---

## 🔍 Common Patterns

### Adding a Book

```swift
// 1. Create Work + Edition + Author
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]

let edition = Edition(isbn13: "...", work: work)
modelContext.insert(edition)
edition.work = work

// 2. Create UserLibraryEntry
let entry = UserLibraryEntry.createWishlistEntry(for: work)
modelContext.insert(entry)

// 3. SAVE BEFORE ENRICHMENT!
try modelContext.save()

// 4. Enqueue for background enrichment
EnrichmentQueue.shared.enqueue(work.persistentModelID)
```

### Updating Reading Status

```swift
// Wishlist → Owned
entry.status = .toRead
entry.edition = ownedEdition

// Owned → Reading
entry.status = .reading
entry.currentPage = 150

// Reading → Read
entry.status = .read
entry.completionDate = Date()
entry.personalRating = 4  // 1-5 stars

try modelContext.save()
```

### Displaying Covers

```swift
// ✅ CORRECT: Use CoverImageService
CachedAsyncImage(url: CoverImageService.coverURL(for: work)) {
    image in image.resizable()
} placeholder: {
    PlaceholderView()
}

// ❌ WRONG: Bypasses fallback logic
CachedAsyncImage(url: work.primaryEdition?.coverURL)
```

---

**This context file is AI-optimized. Refer to `docs/` for human-readable documentation.**
