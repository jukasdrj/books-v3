# BooksTrack - Shared AI Context

**Version:** 3.7.5 (Build 189+) | **iOS:** 26.0+ | **Swift:** 6.2+ | **Bundle ID:** Z67H8Y8DW.com.oooefam.booksV3

Personal book tracking iOS app with cultural diversity insights. SwiftUI, SwiftData, Cloudflare Workers backend.

## Tech Stack

### iOS App
- **UI Framework:** SwiftUI with @Observable pattern (no ViewModels)
- **Data Layer:** SwiftData with CloudKit sync
- **Concurrency:** Swift 6.2 structured concurrency (@MainActor, actors, typed throws)
- **Testing:** Swift Testing framework (@Test, #expect, parameterized tests)
- **Design:** iOS 26 Liquid Glass design system

### Backend
- **Platform:** Cloudflare Workers (TypeScript/Hono monolith)
- **Architecture:** Single `api-worker` with direct function calls
- **Real-time:** Durable Objects (ProgressWebSocketDO) for WebSocket progress
- **Storage:** KV (caching), R2 (images)
- **AI:** Gemini 2.0 Flash (vision, CSV parsing)

## Architecture Principles

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

### State Management
- Use `@Observable` classes + `@State` (no ViewModels)
- Use `@Bindable` for SwiftData models in child views (enables reactive updates)
- Use `@Environment` for dependency injection (ThemeStore, ModelContext)

### Navigation
- **4-Tab Layout:** Library, Search, Shelf, Insights
- Use push navigation (`.navigationDestination`) for details
- Use sheets for Settings and modals
- Settings accessed via gear icon in Library toolbar

## Critical Rules

### 🚨 SwiftData Persistent Identifier Lifecycle
SwiftData objects have two ID states:
1. **Temporary ID** - Assigned by `modelContext.insert()` (in-memory only)
2. **Permanent ID** - Assigned by `modelContext.save()` (persisted to disk)

**NEVER use `persistentModelID` before calling `save()`!**

```swift
// ❌ WRONG: Using ID before save() - CRASH!
let work = Work(title: "...")
modelContext.insert(work)
let id = work.persistentModelID  // ❌ Still temporary!

// ✅ CORRECT: Save BEFORE capturing IDs
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Now safe to use!
```

### 🚨 Insert-Before-Relate Pattern
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
3. Call `save()` before using `persistentModelID` for anything
4. Temporary IDs cannot be used for futures, deduplication, or background tasks

### 🚨 @Bindable for SwiftData Reactivity
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

### 🚨 Swift 6.2 Concurrency
- **NEVER** use `Timer.publish` in actors - use `await Task.sleep(for:)` instead
- **ALWAYS** use `@MainActor` for UI components and SwiftUI views
- **NEVER** pass non-Sendable types across actor boundaries
- Prefer structured concurrency (TaskGroup) over unstructured Task.init

### 🚨 iOS 26 HIG - Don't Mix @FocusState with .searchable()
- iOS 26's `.searchable()` manages focus internally
- Manual `@FocusState` creates keyboard conflicts
- Use push navigation (`.navigationDestination`), not sheets for drill-down

## Code Quality Standards

### Zero Warnings Policy
- All builds must have zero warnings (`-Werror`)
- Warnings treated as errors in CI

### Swift Conventions
- UpperCamelCase types, lowerCamelCase properties
- Use `guard let`/`if let`, avoid force unwrapping
- `struct` for models, `class` only for reference semantics
- Nested supporting types (enums, structs) inside their parent class

### Accessibility
- WCAG AA contrast (4.5:1+) for all UI text
- VoiceOver support for all interactive elements

### Testing
- Unit tests with Swift Testing (@Test, #expect)
- Real device testing required (keyboard, camera, real-world data)
- Thread Sanitizer for concurrency testing

## Backend Architecture

### Canonical Data Contracts (v1.0.0)
All `/v1/*` endpoints return structured canonical responses:

**Response Envelope:**
```typescript
{
  "success": true | false,
  "data": { works: WorkDTO[], authors: AuthorDTO[] } | undefined,
  "error": { message: string, code: ApiErrorCode, details?: any } | undefined,
  "meta": { timestamp: string, processingTime: number, provider: string, cached: boolean }
}
```

**V1 Endpoints:**
- `GET /v1/search/title?q={query}` - Title search
- `GET /v1/search/isbn?isbn={isbn}` - ISBN lookup (validates ISBN-10/13)
- `GET /v1/search/advanced?title={title}&author={author}` - Flexible search
- `POST /v1/enrichment/batch` - Batch enrichment with WebSocket progress

### WebSocket Progress
- All background jobs report via WebSocket (no polling)
- Unified endpoint: `GET /ws/progress?jobId={uuid}`
- Used for: bookshelf scanning, CSV import, batch enrichment

### Internal Structure
```
api-worker/
├── src/index.js                # Main router
├── durable-objects/            # WebSocket DO
├── services/                   # Business logic (AI, enrichment, APIs)
├── providers/                  # AI provider modules (Gemini)
├── handlers/                   # Request handlers (search)
└── utils/                      # Shared utilities (cache, normalization)
```

**Rule:** All background jobs report via WebSocket. No polling. All services communicate via direct function calls.

## Common Development Patterns

### Adding Features
1. Develop in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Use `public` for types exposed to app shell
3. Add dependencies in `BooksTrackerPackage/Package.swift`
4. Add tests in `BooksTrackerPackage/Tests/`

### Error Handling
- Use typed throws with Swift 6.2
- Structured error types (enum with associated values)
- User-facing errors with clear messages

### Performance
- No N+1 queries in SwiftData
- Cache expensive computed properties
- Background processing for enrichment
- Use `fetchCount()` over `fetch().count`

## Security & Privacy

- Never commit secrets to source code
- Validate all user input (especially file uploads)
- Rate limit backend endpoints
- Request size validation (10MB max for CSV)

## Documentation Structure

```
docs/
├── README.md           # Documentation hub & navigation
├── product/            # PRDs (problem statements, user stories)
├── workflows/          # Mermaid diagrams (visual flows)
├── features/           # Technical deep-dives
├── architecture/       # System design
└── guides/             # How-to guides

CLAUDE.md               # Claude Code development guide
CHANGELOG.md            # Historical victories
```

## Tool-Specific Context Files

- **CLAUDE.md** (root): Claude Code development guide with MCP setup
- **.ai/gemini-config.md**: Gemini API configuration
- **.github/copilot-instructions.md**: GitHub Copilot setup

---

**Last Updated:** December 5, 2025