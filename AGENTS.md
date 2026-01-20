# BooksTrack - AI Agent Guide

**Version:** 3.7.6 | **iOS:** 26.0+ | **Swift:** 6.2+ | **Bundle ID:** `Z67H8Y8DW.com.oooefam.booksV3`
**Heuristic:** Documentation is secondary. Always check `Package.swift` and actual View code for current implementation details.

Native iOS book tracking app with cultural diversity insights. SwiftUI, SwiftData, CloudKit sync, Cloudflare Workers backend.

**🎉 NOW ON APP STORE!**

> **Note:** This file provides unified instructions for ALL AI coding agents. For tool-specific setup (Claude Code MCP, slash commands), see `CLAUDE.md`.

---

## Legacy Constraints & Migration
- **Status**: Migration to V3 Architecture (SwiftData + CloudKit) is active.
- **Reference**: See `docs/architecture/V3_MIGRATION_PLAN.md` (if available) or assume V3 is the target.
- **Cleanup**: Code relating to `CoreData` (legacy V2 persistence) should be treated as deprecated/read-only unless migrating.

## 🎯 Multi-Agent Workflow (Claude Code)

**Claude Code can orchestrate complex tasks using specialized AI models:**

- **Sonnet 4.5** (Primary) - Planning, architecture, multi-file refactoring
- **Haiku** - Fast implementation via `mcp__pal__chat`
- **Grok Code Fast 1** - Expert code review via `mcp__pal__codereview` or `mcp__pal__secaudit` (70.8% SWE-Bench-Verified)
- **Gemini 3 Pro** - Deep analysis via `mcp__pal__debug` or `mcp__pal__thinkdeep`

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
- **Testing:** Swift Testing (@Test, #expect)
- **Design:** iOS 26 Liquid Glass design system
- **Backend:** Cloudflare Workers (separate repo), Gemini 2.0 Flash AI

### Project Structure
```
BooksTracker/                       # iOS app shell (thin entry point)
BooksTrackerPackage/
  Sources/BooksTrackerFeature/      # All business logic, UI, models
    Models/                         # Work, Edition, Author, UserLibraryEntry, Goal, GoalProgress
    Views/                          # Library, Search, Shelf, Insights tabs
    Goals/                          # Phase 2: Goals Engine (tracking, progress, UI)
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

**Slash Commands (Claude Code only):**
```bash
/build         # Quick build validation using xcodebuild
/test          # Run Swift Testing suite using xcodebuild
/sim           # Launch in iOS Simulator with log streaming
/device-deploy # Deploy to connected iPhone/iPad using xcodebuild
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

**📍 AUTHORITATIVE SOURCE:** `docs/api/openapi-v3.json` (Synced from backend repo)

**⚠️ NOTE:** This section is a **convenience reference only** for frontend developers.

**Backend Repo:** https://github.com/jukasdrj/bookstrack-backend

### Base URLs

| Environment | HTTP API | WebSocket API |
|-------------|----------|---------------|
| **Production** | `https://api.oooefam.net` | `wss://api.oooefam.net/ws/progress` |
| **Staging** | `https://staging-api.oooefam.net` | `wss://staging-api.oooefam.net/ws/progress` |
| **Local Dev** | `http://localhost:8787` | `ws://localhost:8787/ws/progress` |

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
```

---

## Documentation

**📚 Complete Documentation Hub:** See `docs/README.md` for navigation

```
📄 AGENTS.md                ← This file (unified AI agent guide)
📄 CLAUDE.md                ← Claude Code-specific (MCP, slash commands)
📄 CHANGELOG.md            ← Victory stories + debugging sagas

📁 docs/
  ├── README.md            ← **START HERE** - Documentation navigation
  ├── api/                 ← API Specs (OpenAPI)
  ├── architecture/        ← System design & decisions
  ├── features/            ← Technical deep-dives
  ├── product/             ← PRDs (problem statements, user stories)
  └── workflows/           ← Mermaid diagrams (visual flows)
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
- **Docs:** `docs/features/BOOKSHELF_SCANNER.md`

### Batch Bookshelf Scanning
- Capture up to 5 photos in one session
- **Docs:** `docs/features/BATCH_BOOKSHELF_SCANNING.md`

### Gemini CSV Import
- AI-powered parsing (zero configuration)
- **Docs:** `docs/features/GEMINI_CSV_IMPORT.md`

### ISBN Barcode Scanner
- **Implementation:** Apple VisionKit `DataScannerViewController` (iOS 16+)
- **Docs:** `docs/archive/product/Barcode-Scanner-PRD.md` (Feature shipped)

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

**Last Updated:** January 05, 2026 (v3.7.6)
**Maintained by:** oooe (jukasdrj)
**License:** Proprietary
**App Store:** Z67H8Y8DW.com.oooefam.booksV3
