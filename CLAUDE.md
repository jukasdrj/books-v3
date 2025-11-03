# 📚 BooksTrack by oooe - Claude Code Guide

**Version 3.0.0 (Build 47+)** | **iOS 26.0+** | **Swift 6.1+** | **Updated: October 23, 2025**

Personal book tracking iOS app with cultural diversity insights. SwiftUI, SwiftData, Cloudflare Workers backend.

**🎉 NOW ON APP STORE!** Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`

**📚 DOCUMENTATION HUB:** See `docs/README.md` for complete documentation navigation (PRDs, workflows, feature guides)

## Quick Start

ast-grep (sg) is available and SHALL be prioritized for syntax-aware searches --lang swift
Example usage for Swift (conceptual):
To find all public methods in a Swift file:
Code

ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' your_swift_file.swift

This command uses the --lang swift flag to specify the language and a pattern to match public function declarations, where $METHOD captures the function name and $$$ represents arbitrary arguments and function body content.

**Note:** Implementation plans tracked in [GitHub Issues](https://github.com/users/jukasdrj/projects/2).

### Core Stack
- SwiftUI + @Observable + SwiftData + CloudKit sync
- Swift 6.1 concurrency (@MainActor, actors, typed throws)
- Swift Testing (@Test, #expect, parameterized tests)
- iOS 26 Liquid Glass design system
- Cloudflare Workers (RPC service bindings, Durable Objects, KV/R2)

### Essential Commands

**🚀 iOS Development (MCP-Powered):**
```bash
/gogo          # App Store validation pipeline
/build         # Quick build check
/test          # Run Swift Testing suite
/device-deploy # Deploy to iPhone/iPad
/sim           # Launch with log streaming
```
See **[MCP_SETUP.md](MCP_SETUP.md)** for XcodeBuildMCP configuration.

**☁️ Backend Operations:**
```bash
/deploy-backend  # Deploy api-worker with validation
/backend-health  # Health check + diagnostics
/logs            # Stream Worker logs (real-time)
```

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

**🚨 CRITICAL: Insert-Before-Relate Lifecycle**
```swift
// ❌ WRONG: Crash with "temporary identifier"
let work = Work(title: "...", authors: [author], ...)
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE setting relationships
let work = Work(title: "...", authors: [], ...)
modelContext.insert(work)  // Gets permanent ID

let author = Author(name: "...")
modelContext.insert(author)  // Gets permanent ID

work.authors = [author]  // Safe - both have permanent IDs
```

**Rule:** ALWAYS call `modelContext.insert()` IMMEDIATELY after creating a new model, BEFORE setting any relationships. SwiftData cannot create relationship futures with temporary IDs.

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

### Backend Architecture

**Worker:** `api-worker` (Cloudflare Worker monolith)

#### Canonical Data Contracts (v1.0.0) 🎉 NEW

**TypeScript-first API contracts** ensure consistency across all data providers. All `/v1/*` endpoints return structured canonical responses.

**Core DTOs:** `cloudflare-workers/api-worker/src/types/canonical.ts`
- `WorkDTO` - Abstract creative work (mirrors SwiftData Work model)
- `EditionDTO` - Physical/digital manifestation (multi-ISBN support)
- `AuthorDTO` - Creator with diversity analytics

**Response Envelope:** All `/v1/*` endpoints return discriminated union:
```typescript
{
  "success": true | false,
  "data": { works: WorkDTO[], authors: AuthorDTO[] } | undefined,
  "error": { message: string, code: ApiErrorCode, details?: any } | undefined,
  "meta": { timestamp: string, processingTime: number, provider: string, cached: boolean }
}
```

**V1 Endpoints (Canonical):**
- `GET /v1/search/title?q={query}` - Title search (canonical response)
- `GET /v1/search/isbn?isbn={isbn}` - ISBN lookup with validation (ISBN-10/ISBN-13)
- `GET /v1/search/advanced?title={title}&author={author}` - Flexible search (title, author, or both)
- `POST /v1/enrichment/batch` - Batch enrichment with WebSocket progress

**Error Codes:** Structured error handling
- `INVALID_QUERY` - Empty/invalid search parameters
- `INVALID_ISBN` - Malformed ISBN format
- `PROVIDER_ERROR` - Upstream API failure (Google Books, etc.)
- `INTERNAL_ERROR` - Unexpected server error

**Provenance Tracking:** Every DTO includes:
- `primaryProvider` - Which API contributed the data ("google-books", "openlibrary", etc.)
- `contributors` - Array of all providers that enriched the data
- `synthetic` - Flag for Works inferred from Edition data (enables iOS deduplication)

**Implementation Status:**
- ✅ TypeScript types defined (`enums.ts`, `canonical.ts`, `responses.ts`)
- ✅ Google Books normalizers (`normalizeGoogleBooksToWork`, `normalizeGoogleBooksToEdition`)
- ✅ Backend genre normalization service (`genre-normalizer.ts`)
- ✅ All 3 `/v1/*` endpoints deployed with genre normalization active
- ✅ Backend enrichment services migrated to canonical format
- ✅ AI scanner WebSocket messages use canonical DTOs
- ✅ iOS Swift Codable DTOs (`WorkDTO`, `EditionDTO`, `AuthorDTO`)
- ✅ iOS search services migrated to `/v1/*` endpoints with DTOMapper
- ✅ iOS enrichment service migrated to canonical parsing
- ✅ Comprehensive test coverage (CanonicalAPIResponseTests)
- ✅ iOS DTOMapper fully integrated (deduplication active, genre normalization flowing)
- ⏳ Legacy endpoint deprecation (deferred 2-4 weeks)

**Design:** `docs/plans/2025-10-29-canonical-data-contracts-design.md`
**Implementation:** `docs/plans/2025-10-29-canonical-data-contracts-implementation.md`

**Legacy Endpoints (Still Active):**
- `GET /search/title?q={query}` - Book search (6h cache)
- `GET /search/isbn?isbn={isbn}` - ISBN lookup (7-day cache)
- `GET /search/advanced?title={title}&author={author}` - Multi-field search (6h cache, supports POST for compatibility)
- `POST /api/enrichment/start` - **DEPRECATED** Batch enrichment with WebSocket progress
- `POST /api/scan-bookshelf?jobId={uuid}` - AI bookshelf scan with Gemini 2.0 Flash
- `POST /api/scan-bookshelf/batch` - Batch scan (max 5 photos, parallel upload → sequential processing)
- `POST /api/import/csv-gemini` - AI-powered CSV import with Gemini parsing (Beta)
- `GET /ws/progress?jobId={uuid}` - WebSocket progress (unified for ALL jobs)

**AI Provider (Gemini Only):**
- **Gemini 2.0 Flash:** Google's production vision model with 2M token context window
- Processing time: 25-40s (includes AI inference + enrichment)
- Image size: Handles 4-5MB images natively (no resizing needed)
- Accuracy: High (0.7-0.95 confidence scores)
- Optimized for ISBN detection and small text on book spines

**Note:** Cloudflare Workers AI models (Llama, LLaVA, UForm) removed due to small context windows (128K-8K tokens) that couldn't handle typical bookshelf images. See [GitHub Issue #134](https://github.com/jukasdrj/books-tracker-v1/issues/134) for details.

**Architecture:**
- Single monolith worker with direct function calls (no RPC service bindings)
- ProgressWebSocketDO for real-time status updates (all background jobs)
- No circular dependencies, no polling endpoints
- KV caching, R2 image storage, multi-provider AI integration

**Internal Structure:**
```
api-worker/
├── src/index.js                # Main router
├── durable-objects/            # WebSocket DO
├── services/                   # Business logic (AI, enrichment, APIs)
├── providers/                  # AI provider modules (Gemini, Cloudflare)
├── handlers/                   # Request handlers (search)
└── utils/                      # Shared utilities (cache)
```

**Rule:** All background jobs report via WebSocket. No polling. All services communicate via direct function calls.

**See:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md` for monolith architecture details. Previous distributed architecture archived in `cloudflare-workers/_archived/`.

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


### Backend
```bash
npx wrangler tail books-api-proxy --search "provider"
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

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
📄 CLAUDE.md                 ← This file (quick reference <500 lines)
📄 MCP_SETUP.md             ← XcodeBuildMCP workflows
📄 CHANGELOG.md             ← Victory stories + debugging sagas

📁 docs/
  ├── README.md             ← **START HERE** - Documentation navigation & learning paths
  ├── product/              ← PRDs (problem statements, user stories, success metrics)
  ├── workflows/            ← Mermaid diagrams (visual flows for all features)
  ├── features/             ← Technical deep-dives (implementation, patterns, lessons)
  ├── architecture/         ← System design & architectural decisions
  └── guides/               ← How-to guides & best practices

📁 cloudflare-workers/      ← Backend: MONOLITH_ARCHITECTURE.md
📁 .claude/commands/        ← Slash commands (8 total: iOS + backend operations)
```

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
