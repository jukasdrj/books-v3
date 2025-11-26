# BooksTrack - AI Agent Guide

**Version:** 3.7.5 (Build 189+) | **iOS:** 26.0+ | **Swift:** 6.2+ | **Bundle ID:** `Z67H8Y8DW.com.oooefam.booksV3`

Native iOS book tracking app with cultural diversity insights. SwiftUI, SwiftData, CloudKit sync, Cloudflare Workers backend.

**🎉 NOW ON APP STORE!**

> **Note:** This file provides unified instructions for ALL AI coding agents. For tool-specific setup (Claude Code MCP, slash commands), see `CLAUDE.md`.

---

## 🎯 Multi-Agent Workflow (Claude Code)

**Claude Code can orchestrate complex tasks using specialized AI models:**

- **Sonnet 4.5** (Primary) - Planning, architecture, multi-file refactoring
- **Haiku** - Fast implementation via `mcp__zen__chat`
- **Grok Code Fast 1** - Expert code review via `mcp__zen__codereview` or `mcp__zen__secaudit` (70.8% SWE-Bench-Verified)
- **Gemini 3 Pro** - Deep analysis via `mcp__zen__debug` or `mcp__zen__thinkdeep`

**When to use multi-agent workflows:**
- ✅ Complex features requiring fast iteration + expert validation
- ✅ Security-critical code (Haiku implements → Grok Code Fast audits)
- ✅ Mysterious bugs (Gemini 3 Pro investigates → Haiku fixes)
- ✅ Large refactorings (parallel component extraction)

**See `CLAUDE.md` for detailed multi-agent workflow patterns and delegation strategies.**

---

## Quick Start

### Tech Stack
- **iOS App:** SwiftUI, SwiftData, CloudKit, Swift 6.2 concurrency
- **Testing:** Swift Testing (@Test, #expect, 161+ tests)
- **Design:** iOS 26 Liquid Glass design system
- **Backend:** Cloudflare Workers (separate repo), Gemini 2.0 Flash AI

### Project Structure
```
BooksTracker/                       # iOS app shell (thin entry point)
BooksTrackerPackage/
  Sources/BooksTrackerFeature/      # All business logic, UI, models
    Models/                         # Work, Edition, Author, UserLibraryEntry
    Views/                          # Library, Search, Shelf, Insights tabs
    Services/                       # API, enrichment, scanning
  Tests/                            # Swift Testing tests
Config/Shared.xcconfig              # Version, bundle ID (UPDATE HERE!)
docs/                               # Documentation hub (see docs/README.md)
```

### Build & Run

**Xcode Workspace (REQUIRED):**
- Open `BooksTracker.xcworkspace` (NOT .xcodeproj!)
- Scheme: `BooksTracker`
- Zero warnings enforced: `GCC_TREAT_WARNINGS_AS_ERRORS = YES`

**MCP Commands (Claude Code only):**
```bash
/build         # Quick build validation
/test          # Run Swift Testing suite
/sim           # Launch in iOS Simulator with log streaming
/device-deploy # Deploy to connected iPhone/iPad
```

**Manual Build:**
```bash
# Build from command line
xcodebuild -workspace BooksTracker.xcworkspace \
           -scheme BooksTracker \
           -configuration Debug \
           build

# Run tests
xcodebuild test -workspace BooksTracker.xcworkspace \
                -scheme BooksTracker \
                -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

---

## 🚨 CRITICAL RULES (Common Crashes!)

### 1. SwiftData Persistent Identifier Lifecycle

SwiftData objects have TWO ID states:
1. **Temporary ID** - Assigned by `modelContext.insert()` (in-memory only)
2. **Permanent ID** - Assigned by `modelContext.save()` (persisted to disk)

**NEVER use `persistentModelID` before calling `save()`!**

```swift
// ❌ WRONG: Using ID before save() - CRASH!
let work = Work(title: "...")
modelContext.insert(work)  // Assigns TEMPORARY ID
let id = work.persistentModelID  // ❌ Still temporary!
// Later: Fatal error: "Illegal attempt to create a full future for a temporary identifier"

// ✅ CORRECT: Save BEFORE capturing IDs
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]  // Relationships use temporary IDs (OK)
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Now safe to use!
```

### 2. Insert-Before-Relate Pattern

```swift
// ❌ WRONG: Setting relationship during initialization
let work = Work(title: "...", authors: [author])  // Crash!
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE setting relationships
let author = Author(name: "...")
modelContext.insert(author)  // Insert first

let work = Work(title: "...", authors: [])
modelContext.insert(work)    // Insert second
work.authors = [author]      // Set relationship AFTER both are inserted
try modelContext.save()      // Save before using IDs
```

**Rules:**
1. Always `insert()` immediately after creating models
2. Set relationships AFTER both objects are inserted
3. Call `save()` before using `persistentModelID` for anything
4. Temporary IDs cannot be used for futures, deduplication, or background tasks

### 3. @Bindable for SwiftData Reactivity

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

### 4. Swift 6.2 Concurrency

- **NEVER** use `Timer.publish` in actors → use `await Task.sleep(for:)` instead
- **ALWAYS** use `@MainActor` for UI components and SwiftUI views
- **NEVER** pass non-Sendable types across actor boundaries
- Prefer structured concurrency (TaskGroup) over unstructured Task.init

### 5. iOS 26 HIG - Don't Mix @FocusState with .searchable()

- iOS 26's `.searchable()` manages focus internally
- Manual `@FocusState` creates keyboard conflicts
- Use push navigation (`.navigationDestination`), not sheets for drill-down

```swift
// ✅ CORRECT: Push navigation
.navigationDestination(item: $selectedBook) { book in 
    WorkDetailView(work: book.work) 
}

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedBook) { ... }
```

---

## Code Style & Conventions

### Swift Best Practices
- **UpperCamelCase** for types, **lowerCamelCase** for properties/functions
- Use `guard let`/`if let`, avoid force unwrapping (`!`)
- `struct` for models, `class` only for reference semantics
- Nested supporting types (enums, structs) inside their parent class

### State Management (NO ViewModels!)
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
        }
    }
}
```

**Property Wrappers:**
- `@State` - View-specific state and model objects
- `@Observable` - Observable model classes (replaces ObservableObject)
- `@Environment` - Dependency injection (ThemeStore, ModelContext)
- `@Bindable` - **CRITICAL for SwiftData models!** Enables reactive updates

### Navigation Structure

**4-Tab Layout (iOS 26 HIG optimized):**
- **Library** - Main collection view with Settings gear icon in toolbar
- **Search** - Book search with ISBN scanner
- **Shelf** - AI-powered bookshelf scanner (Gemini 2.0 Flash)
- **Insights** - Reading statistics and cultural diversity analytics

**Settings Access:**
- Gear icon in Library tab toolbar (Books.app pattern)
- Sheet presentation with "Done" button
- NOT in tab bar (4 tabs optimal per iOS 26 HIG)

---

## SwiftData Architecture

### Models
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

### Performance Best Practices

```swift
// ✅ CORRECT: Use fetchCount() for counts
let count = try modelContext.fetchCount(FetchDescriptor<Work>())

// ❌ WRONG: Load all objects just to count
let works = try modelContext.fetch(FetchDescriptor<Work>())
let count = works.count  // Loads ALL objects into memory!

// ✅ CORRECT: Predicate filtering before loading
var descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.readingStatus == .reading }
)
let reading = try modelContext.fetch(descriptor)

// ❌ WRONG: Load everything then filter in Swift
let all = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let reading = all.filter { $0.readingStatus == .reading }
```

---

## Backend API Contract (v2.4)

**🚨 CRITICAL:** All backend communication MUST adhere to v2.4 canonical contract.

**Last Updated:** November 20, 2025
**Backend Repo:** https://github.com/jukasdrj/bookstrack-backend
**Full Contract:** `docs/API_CONTRACT.md` in backend repo

**v2.4.1 Changes (Nov 20, 2025):**
- ⚡ WebSocket Hibernation API (70-80% cost reduction, zero client changes)

**v2.4 Changes (Nov 18, 2025):**
- ✅ Secure WebSocket auth via `Sec-WebSocket-Protocol` header (implemented)
- ✅ HTTP/1.1 enforcement for WebSocket (Issue #227 - implemented)
- ✅ HATEOAS `SearchLinksDTO` on Work/Edition (backend provides provider URLs - Issue #196)
- ✅ Image quality detection improvements (`isbndbQuality` field)
- ✅ 24-hour result expiry (`expiresAt` field in completion payloads)

#### SearchLinksDTO (HATEOAS) - Issue #196

**Purpose:** Backend centralizes URL construction for external book searches. Clients follow links directly without building URLs.

**Swift Usage Example:**
```swift
// ✅ CORRECT: Use searchLinks from backend
if let googleBooksURL = work.searchLinks?.googleBooks {
    openURL(URL(string: googleBooksURL)!)
}

// ❌ WRONG: Don't construct URLs manually
// let url = "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"
```

### Base URLs

| Environment | HTTP API | WebSocket API |
|-------------|----------|---------------|
| **Production** | `https://api.oooefam.net` | `wss://api.oooefam.net/ws/progress` |
| **Staging** | `https://staging-api.oooefam.net` | `wss://staging-api.oooefam.net/ws/progress` |
| **Local Dev** | `http://localhost:8787` | `ws://localhost:8787/ws/progress` |

### Response Envelope (v2.0)

All `/v1/*` endpoints return:
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

### V1 Endpoints (Production Ready)

```
GET /v1/search/title?q={query}              # Title search (fuzzy, up to 20 results)
GET /v1/search/isbn?isbn={isbn}             # ISBN lookup (ISBN-10 or ISBN-13)
GET /v1/search/advanced?title=&author=      # Multi-field search
GET /v1/scan/results/{jobId}                # Fetch AI scan results (24hr TTL)
GET /v1/csv/results/{jobId}                 # Fetch CSV import results (24hr TTL)
POST /api/scan-bookshelf/batch              # Upload 1-5 photos for AI processing
GET /ws/progress?jobId={uuid}               # WebSocket progress (token in header)
```

**Rate Limits:**
- Search: 100 req/min per IP
- Batch enrichment: 10 req/min per IP
- **AI batch scanning: 5 req/min per IP** (1-5 photos per batch)
- Global: 1000 req/hour per IP (burst: 50/min)

### Error Codes
- `INVALID_ISBN` - Invalid ISBN format (HTTP 400)
- `INVALID_QUERY` - Missing/invalid query parameter (HTTP 400)
- `NOT_FOUND` - Resource not found (HTTP 404)
- `RATE_LIMIT_EXCEEDED` - Too many requests (HTTP 429, retryable)
- `PROVIDER_TIMEOUT` - External API timeout (HTTP 504, retryable)
- `INTERNAL_ERROR` - Server error (HTTP 500, retryable)

### DTO Field Defaults (v2.4.1)

**Default Value Pattern:** Optional fields default to `nil` in Swift (NOT zero or empty arrays)

**Common Defaults:**
| Field Type | Swift Type | Default Value | Example Fields |
|------------|------------|---------------|----------------|
| Optional string | `String?` | `nil` | `originalLanguage`, `description`, `coverImageURL` |
| Optional number | `Int?`, `Double?` | `nil` | `pageCount`, `firstPublicationYear`, `publicationYear` |
| Optional object | `SearchLinksDTO?` | `nil` | `searchLinks`, `enrichment` |
| Required array | `[String]` | `[]` (empty array) | `subjectTags`, `goodreadsWorkIDs`, `amazonASINs` |
| Optional boolean | `Bool?` | `nil` | `synthetic` |

**Critical Swift Patterns:**
```swift
// ✅ CORRECT: Nil-coalescing for optional fields
let title = work.title ?? "Unknown Title"
let pageCount = edition.pageCount ?? 0

// ✅ CORRECT: Optional binding for nested objects
if let searchLinks = work.searchLinks {
    // Use searchLinks.googleBooks, etc.
}

// ❌ INCORRECT: Assuming default zero for optional numbers
let pages = edition.pageCount  // Type is Int?, NOT Int!
// Must use: let pages = edition.pageCount ?? 0

// ❌ INCORRECT: Force-unwrapping optional fields
let url = work.searchLinks!.googleBooks  // CRASH if nil!
```

**SwiftData Mapping:** When mapping DTOs to SwiftData models, use `@Attribute(.preserveValueOnDeletion)` for optional fields that should persist as `nil` rather than reverting to defaults on deletion.

### WebSocket v2.4 Contract

**🚨 CRITICAL: HTTP/1.1 ONLY (Issue #227)**

WebSocket connections **MUST** use HTTP/1.1. HTTP/2 and HTTP/3 are **not supported**.

**iOS URLRequest Configuration (MANDATORY):**
```swift
// FIX (Issue #227): WebSocket connections MUST use HTTP/1.1 for RFC 6455 compliance.
// iOS defaults to HTTP/2 for HTTPS, which is incompatible with WebSocket upgrade.
var request = URLRequest(url: url)
request.assumesHTTP3Capable = false  // Forces HTTP/1.1 (disables HTTP/2 and HTTP/3)
request.setValue("websocket", forHTTPHeaderField: "Upgrade")
request.setValue("Upgrade", forHTTPHeaderField: "Connection")

let webSocket = URLSession.shared.webSocketTask(with: request)
webSocket.resume()
```

**Why This Works:**
- `assumesHTTP3Capable = false` prevents HTTP/3 (QUIC) and HTTP/2 negotiation
- Explicit `Upgrade: websocket` header signals WebSocket upgrade intent (RFC 6455)
- `Connection: Upgrade` header required for protocol upgrade
- Result: iOS negotiates HTTP/1.1 → Server responds with `101 Switching Protocols`

**Violation Response:** `HTTP 426 Upgrade Required` (detected as URLError code `-1011`)

---

**🚨 CRITICAL: Secure Authentication (v2.4)**

**NEW METHOD (Recommended):**
```swift
let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)")!
var request = URLRequest(url: url)
request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
```

**OLD METHOD (Deprecated):**
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**Why Header Method:**
- Prevents token leakage in server logs
- Not visible in browser history
- Follows HATEOAS security principles

---

**🚨 CRITICAL: Send "ready" Signal**

Backend waits for client ready signal before processing (2-5 second timeout):

```swift
func webSocketDidConnect(_ webSocket: URLSessionWebSocketTask) {
    let readyMessage = ["type": "ready"]
    let jsonData = try! JSONEncoder().encode(readyMessage)
    webSocket.send(.data(jsonData))
}
```

---

**Message Types:**
1. **ready** (Client→Server) - Signal readiness after connection
2. **ready_ack** (Server→Client) - Backend acknowledges ready signal
3. **job_started** - Job begins processing
4. **job_progress** - Periodic updates (every 5-10% progress)
5. **job_complete** - Summary only (⚠️ NO large arrays!)
6. **error** - Job failure (v2.0 canonical format: `payload.error.message`, `payload.error.code`, `payload.retryable`)
7. **reconnected** - State sync after reconnect (progress, status, processedCount, totalCount)
8. **batch-init**, **batch-progress**, **batch-complete** - Photo batch scanning (1-5 photos)

---

**Summary-Only Completions:**

Completion messages are **summary-only** (< 1 KB). Full results fetched via HTTP GET.

**Client Action (MANDATORY):** Fetch full results via HTTP GET after `job_complete`:
```swift
let fullResults = try await fetchResults(url: payload.resultsUrl)
// GET https://api.oooefam.net/v1/scan/results/uuid-12345
```

**Results TTL:** 24 hours (v2.4) - `expiresAt` field (ISO 8601) indicates when results expire (24h from completion). Clients should check expiry before fetching results and either cache data locally OR handle 404 responses gracefully if fetching expired results. Example: `if Date() < expiresAt { fetchResults() }`

---

**Reconnection Support (Production Ready):**

Grace period: 60 seconds after unexpected disconnect

**Flow:**
1. Detect disconnect (close code ≠ 1000)
2. Reconnect with: `?jobId={jobId}&reconnect=true&token={token}`
3. Receive `reconnected` message with synced state
4. Continue listening for updates

**Best Practices:**
- Exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Max 3 retry attempts
- Preserve jobId/token in memory (use Keychain for security)

**✅ Implementation:** Our WebSocketProgressManager automatically adds `reconnect=true` parameter during reconnection attempts for optimal state sync.

---

## Testing

### Swift Testing Framework
```swift
@Test("Work creation with valid title")
func testWorkCreation() throws {
    let work = Work(title: "1984")
    #expect(work.title == "1984")
}

@Test("ISBN validation", arguments: [
    ("9780141036144", true),
    ("invalid", false)
])
func testISBNValidation(isbn: String, expected: Bool) {
    #expect(ISBN.isValid(isbn) == expected)
}
```

### Test Locations
- **Unit Tests:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/`
- **UI Tests:** `BooksTrackerUITests/`

### Running Tests
```bash
# Xcode
# Product > Test (Cmd+U)

# Command line
xcodebuild test -workspace BooksTracker.xcworkspace \
                -scheme BooksTracker \
                -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# MCP (Claude Code only)
/test
```

---

## Code Search Tools

### AST-Grep (PRIMARY - Syntax-Aware)

**ALWAYS use `ast-grep` for Swift code searches** (NOT ripgrep/grep).

**Why?**
- Syntax-aware (understands Swift structure)
- Accurate matching (no false positives from strings/comments)
- Refactoring-safe

**Common Use Cases:**
```bash
# Find all public methods
ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' .

# Find all @MainActor classes
ast-grep --lang swift --pattern '@MainActor class $NAME { $$$ }' .

# Find all SwiftData @Model classes
ast-grep --lang swift --pattern '@Model public class $NAME { $$$ }' .

# Find all Task.sleep calls
ast-grep --lang swift --pattern 'Task.sleep(for: $DURATION)' .

# Find all force unwraps
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

---

## Common Development Tasks

### Adding Features
1. Develop in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Use `public` for types exposed to app shell
3. Add dependencies in `BooksTrackerPackage/Package.swift`
4. Add tests in `BooksTrackerPackage/Tests/`

### Versioning
```bash
# Update version (auto-updates Info.plist, git tag)
./Scripts/update_version.sh patch  # 1.0.0 -> 1.0.1
./Scripts/update_version.sh minor  # 1.0.0 -> 1.1.0
./Scripts/update_version.sh major  # 1.0.0 -> 2.0.0

# Create release (runs tests, commits, tags)
./Scripts/release.sh minor "Added new reading statistics"
```

### Library Reset (Settings → Reset Library)
Comprehensive reset includes:
- Cancels in-flight backend enrichment jobs (prevents resource waste)
- Stops local enrichment processing
- Deletes all SwiftData models (Works, Editions, Authors, UserLibraryEntries)
- Clears enrichment queue
- Resets AI provider to Gemini
- Resets feature flags to defaults
- Clears search history

---

## Security & Privacy

### Checklist
- ✅ Zero warnings enforced (`GCC_TREAT_WARNINGS_AS_ERRORS = YES`)
- ✅ No secrets in code (backend manages API keys separately)
- ✅ Real device testing required (keyboard, camera, CloudKit)
- ✅ WCAG AA contrast (4.5:1+ with `.secondary`/`.tertiary`)
- ✅ Validate all user input (especially file uploads - 10MB max for CSV)
- ✅ Rate limit backend endpoints

### Common Security Issues
- **NEVER** commit API keys to source code
- **ALWAYS** validate ISBN format before backend calls
- **ALWAYS** sanitize user input for SQL/XSS vulnerabilities
- **ALWAYS** check file size before upload (10MB max)

---

## Common Issues & Debugging

### iOS Issues
1. **Keyboard broken on real device:**
   - Remove `.navigationBarDrawer(displayMode:)` (iOS 26 bug!)
   - Always test on physical devices

2. **"temporary identifier" crash:**
   - Call `save()` before using `persistentModelID`
   - Follow insert-before-relate pattern

3. **View not updating on SwiftData changes:**
   - Use `@Bindable` for SwiftData models in child views
   - Ensure relationships are properly set

4. **CloudKit sync fails:**
   - Test on multiple devices
   - Check CloudKit Dashboard
   - Reset via Settings → Reset Library

### Backend Issues
- See separate backend repository for troubleshooting
- Check Cloudflare Workers logs
- Verify Durable Object state

### Clean Build
```bash
# Clean derived data (fixes SwiftData macro issues)
rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*

# Clean build folder
xcodebuild clean -workspace BooksTracker.xcworkspace -scheme BooksTracker
```

---

## Documentation

**📚 Complete Documentation Hub:** See `docs/README.md` for navigation

```
📄 AGENTS.md                ← This file (unified AI agent guide)
📄 CLAUDE.md                ← Claude Code-specific (MCP, slash commands)
📄 MCP_SETUP.md            ← XcodeBuildMCP workflows
📄 CHANGELOG.md            ← Victory stories + debugging sagas

📁 docs/
  ├── README.md            ← **START HERE** - Documentation navigation
  ├── product/             ← PRDs (problem statements, user stories)
  ├── workflows/           ← Mermaid diagrams (visual flows)
  ├── features/            ← Technical deep-dives
  ├── architecture/        ← System design & decisions
  └── guides/              ← How-to guides & best practices

📁 .ai/
  ├── README.md            ← AI context organization guide
  ├── SHARED_CONTEXT.md    ← Project-wide AI context
  └── gemini-config.md     ← Gemini API setup

📁 .claude/commands/       ← Slash commands (4 total: iOS dev only)
```

**Documentation Types:**
- **AGENTS.md** - Unified AI agent instructions (this file)
- **CLAUDE.md** - Claude Code-specific setup (MCP, skills, slash commands)
- **PRDs** (`docs/product/`) - WHY features exist, WHO they're for
- **Workflows** (`docs/workflows/`) - HOW features work (Mermaid diagrams)
- **Feature Docs** (`docs/features/`) - IMPLEMENTATION details
- **CHANGELOG.md** - Historical victories

**Learning Path:**
1. New to project? → Read `docs/README.md` then scan `docs/workflows/`
2. Planning feature? → Create PRD from `docs/product/PRD-Template.md`
3. Implementing? → Study `docs/features/` + workflow diagrams
4. Need quick answer? → Check this file (AGENTS.md)

---

## Key Business Logic

### Reading Status Flow
```swift
// Wishlist → Owned → Reading → Read
let entry = UserLibraryEntry.createWishlistEntry(for: work)
entry.status = .toRead
entry.edition = ownedEdition
entry.currentPage = 150
entry.status = .reading
entry.status = .read
entry.completionDate = Date()
```

### Cultural Diversity
- **AuthorGender:** female, male, nonBinary, other, unknown
- **CulturalRegion:** africa, asia, europe, northAmerica, southAmerica, oceania, middleEast, caribbean, centralAsia, indigenous, international
- **Marginalized Voice:** Auto-detection based on gender + cultural region

### Cover Image Display Pattern
```swift
// ✅ CORRECT: Use CoverImageService for intelligent fallback
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

// ❌ WRONG: Direct access bypasses fallback logic
CachedAsyncImage(url: work.primaryEdition?.coverURL)  // Misses Work-level covers!
```

**Why:** Covers can exist at Edition level OR Work level. Service provides intelligent Edition → Work fallback.

---

## Features

### Bookshelf AI Scanner
- **AI Model:** Gemini 2.0 Flash (2M token context window)
- **Progress:** WebSocket real-time (8ms latency)
- **Confidence Threshold:** 60% for review queue
- **Image Preprocessing:** iOS resizes to 3072px @ 90% quality (400-600KB)
- **Docs:** `docs/features/BOOKSHELF_SCANNER.md`

### Batch Bookshelf Scanning
- Capture up to 5 photos in one session
- Parallel upload → sequential Gemini processing
- Real-time per-photo progress via WebSocket
- Automatic deduplication by ISBN
- Cancel mid-batch with partial results
- **Docs:** `docs/features/BATCH_BOOKSHELF_SCANNING.md`

### Gemini CSV Import
- AI-powered parsing (zero configuration)
- No column mapping needed (auto-detects title, author, ISBN)
- Unified Enrichment Pipeline (save → background enrichment)
- Real-time WebSocket progress
- 10MB file size limit, RFC 4180 compliant
- **Status:** ✅ Production ready (v3.1.0+)
- **Docs:** `docs/features/GEMINI_CSV_IMPORT.md`

### ISBN Barcode Scanner
- **Implementation:** Apple VisionKit `DataScannerViewController` (iOS 16+)
- Native barcode scanning (zero custom camera code)
- Auto-highlighting and tap-to-scan gestures
- Built-in guidance ("Move Closer", "Slow Down")
- **Symbologies:** EAN-13, EAN-8, UPC-E (ISBN-specific)
- **Docs:** `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md`

---

## Design System

### iOS 26 Liquid Glass
- **5 Built-in Themes:** liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- **Access:** `@Environment(iOS26ThemeStore.self)`

### Text Contrast (WCAG AA)
```swift
// ✅ Use system semantic colors (auto-adapt to backgrounds)
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)

// ❌ Don't use custom "accessible" colors
```

**Rule:** `themeStore.primaryColor` for brand, `.secondary`/`.tertiary` for metadata.

---

## Performance

### App Launch Architecture (Nov 2025 Optimization)
- **Performance:** 600ms cold launch (down from 1500ms - 60% faster!)
- **Lazy ModelContainer Init:** Container created on first access (not at app init)
- **Deferred Background Tasks:** Non-critical tasks delayed by 2 seconds
- **Task Prioritization:** UI rendering immediate, enrichment/cleanup deferred

### Key Optimizations
- Lazy properties: Container, DTOMapper, LibraryRepository (~200ms off critical path)
- Task deferral: Background work delayed by 2s (~400ms off critical path)
- Micro-optimizations: Early exits, caching, predicate filtering (~180ms saved)

**Results:** `docs/performance/2025-11-04-app-launch-optimization-results.md`

---

## Build Status

**✅ Zero warnings, zero errors**  
**✅ HIG Compliance:** 100% iOS 26 standards  
**✅ Swift 6.2:** Full concurrency compliance  
**✅ Accessibility:** WCAG AA compliant contrast  

---

**Last Updated:** November 26, 2025 (v3.7.5, Build 189)
**Maintained by:** oooe (jukasdrj)
**License:** Proprietary
**App Store:** Z67H8Y8DW.com.oooefam.booksV3
