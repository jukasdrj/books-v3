# GitHub Copilot Instructions for BooksTrack

## Project Overview

BooksTrack is a modern iOS book tracking application (v3.0.0) with cultural diversity insights. Built with SwiftUI, SwiftData, and Cloudflare Workers backend.

**Bundle ID:** `Z67H8Y8DW.com.oooefam.booksV3`  
**Platforms:** iOS 26.0+, Swift 6.1+

## Technology Stack

### iOS App
- **UI Framework:** SwiftUI with @Observable pattern (no ViewModels)
- **Data Layer:** SwiftData with CloudKit sync
- **Concurrency:** Swift 6.1 structured concurrency (@MainActor, actors, typed throws)
- **Testing:** Swift Testing framework (@Test, #expect)
- **Design:** iOS 26 Liquid Glass design system

### Backend
- **Platform:** Cloudflare Workers (TypeScript/Hono monolith)
- **Architecture:** Single `api-worker` with direct function calls
- **Real-time:** Durable Objects (ProgressWebSocketDO) for WebSocket progress
- **Storage:** KV (caching), R2 (images)
- **AI:** Gemini 2.0 Flash (vision, CSV parsing)

## Critical Development Rules

### Swift Concurrency (Swift 6.1)
- **NEVER** use `Timer.publish` in actors - use `await Task.sleep(for:)` instead
- **ALWAYS** use `@MainActor` for UI components and SwiftUI views
- **NEVER** pass non-Sendable types across actor boundaries
- Prefer structured concurrency (TaskGroup) over unstructured Task.init

### SwiftData Lifecycle (CRITICAL)
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

**Rule:** ALWAYS call `modelContext.insert()` IMMEDIATELY after creating a model, BEFORE setting any relationships.

### State Management
- Use `@Observable` classes + `@State` (no ViewModels)
- Use `@Bindable` for SwiftData models in child views (enables reactive updates)
- Use `@Environment` for dependency injection (ThemeStore, ModelContext)

### Code Quality Standards
- **Zero warnings policy** - all builds must have zero warnings (-Werror)
- Use `guard let`/`if let`, avoid force unwrapping
- Nested supporting types (enums, structs) inside their parent class
- WCAG AA contrast (4.5:1+) for all UI text

## Architecture Patterns

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

### Navigation
- **4-Tab Layout:** Library, Search, Shelf, Insights
- Use push navigation (`.navigationDestination`) for details
- Use sheets for Settings and modals
- Settings accessed via gear icon in Library toolbar

## Backend API

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

## Essential Commands

### iOS Development
```bash
/gogo          # App Store validation pipeline
/build         # Quick build check
/test          # Run Swift Testing suite
/device-deploy # Deploy to iPhone/iPad
/sim           # Launch with log streaming
```

### Backend Operations
```bash
/deploy-backend  # Deploy api-worker with validation
/backend-health  # Health check + diagnostics
/logs            # Stream Worker logs (real-time)
```

### Code Search
- **Primary tool:** `ast-grep` (syntax-aware Swift search)
- Example: `ast-grep --lang swift --pattern '@MainActor class $NAME { $$ }' .`
- Use for finding patterns, not text

## Key Features

### AI-Powered
- **Bookshelf Scanner:** Gemini 2.0 Flash vision (batch up to 5 photos)
- **CSV Import:** Zero-config AI parsing with Gemini
- **Smart Enrichment:** Automatic metadata from multiple providers

### ISBN Scanning
- Apple VisionKit DataScannerViewController
- Symbologies: EAN-13, EAN-8, UPC-E
- Auto-highlighting and tap-to-scan

## Testing & Quality

### Testing Strategy
- Unit tests with Swift Testing (@Test, #expect)
- Real device testing required (keyboard, camera, real-world data)
- Thread Sanitizer for concurrency testing

### Performance Rules
- No N+1 queries in SwiftData
- Cache expensive computed properties
- Background processing for enrichment

## Documentation Structure

```
docs/
├── README.md           # Documentation hub & navigation
├── product/            # PRDs (problem statements, user stories)
├── workflows/          # Mermaid diagrams (visual flows)
├── features/           # Technical deep-dives
├── architecture/       # System design
└── guides/             # How-to guides

CLAUDE.md               # Quick reference (<500 lines)
CHANGELOG.md            # Historical victories
```

**For details:** See CLAUDE.md for comprehensive development guide.

## Common Patterns

### Add a new feature
1. Develop in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Use `public` for types exposed to app shell
3. Add dependencies in `BooksTrackerPackage/Package.swift`
4. Add tests in `BooksTrackerPackage/Tests/`

### Error Handling
- Use typed throws with Swift 6.1
- Structured error types (enum with associated values)
- User-facing errors with clear messages

### UI Components
- Follow iOS 26 HIG strictly
- Don't mix `@FocusState` with `.searchable()` (iOS 26 manages focus)
- Glass overlays need `.allowsHitTesting(false)`

## Security & Privacy

- Never commit secrets to source code
- Validate all user input (especially file uploads)
- Rate limit backend endpoints
- Request size validation (10MB max for CSV)

## Important Notes

- CloudKit sync enabled - test with multiple devices
- Real device testing is MANDATORY (simulators miss keyboard issues)
- Review `docs/SWIFT6_COMPILER_BUG.md` for known issues
- Check `docs/code-review.md` for detailed review guidelines
