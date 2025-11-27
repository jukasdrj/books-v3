# GitHub Copilot Instructions for BooksTrack

**Version:** 3.7.5 (Build 189+) | **iOS 26.0+, Swift 6.2+** | **Bundle:** `Z67H8Y8DW.com.oooefam.booksV3`

## Stack
**iOS:** SwiftUI + @Observable (NO ViewModels!) + SwiftData + CloudKit | Swift Testing (@Test, 161 tests)  
**Backend:** Separate repository at [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend)

## Commands (Execute from repository root)

### Build
```bash
# Open workspace (REQUIRED - NOT .xcodeproj!)
open BooksTracker.xcworkspace

# Build from command line
xcodebuild -workspace BooksTracker.xcworkspace \
           -scheme BooksTracker \
           -configuration Debug \
           build

# MCP command (requires XcodeBuildMCP server):
/build
```

### Test
```bash
# Run all tests
xcodebuild test -workspace BooksTracker.xcworkspace \
                -scheme BooksTracker \
                -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# MCP command:
/test
```

### Run
```bash
# Launch in simulator with log streaming
# MCP command:
/sim

# Deploy to connected iPhone/iPad
# MCP command:
/device-deploy
```

**Key Build Facts:**
- Workspace: `BooksTracker.xcworkspace` (NOT .xcodeproj!)
- Scheme: `BooksTracker`
- Version config: `Config/Shared.xcconfig`
- Zero warnings enforced: `GCC_TREAT_WARNINGS_AS_ERRORS = YES`

## Boundaries (NEVER Touch These!)

### Files & Directories
- ❌ **NEVER** edit files in `.github/agents/` - These contain instructions for other agents
- ❌ **NEVER** commit secrets, API keys, or tokens to any file
- ❌ **NEVER** modify `Config/Shared.xcconfig` without updating version numbers correctly
- ❌ **NEVER** edit Xcode project files (`.xcodeproj/`) directly - use Xcode
- ❌ **NEVER** commit files in `DerivedData/` or build artifacts
- ❌ **NEVER** force push or modify git history (`git push --force`, `git rebase`)

### Code Practices
- ❌ **NEVER** use `Timer.publish` in actors (Swift 6 violation - use `Task.sleep`)
- ❌ **NEVER** use `persistentModelID` before calling `modelContext.save()` (crashes!)
- ❌ **NEVER** set SwiftData relationships during model initialization (crashes!)
- ❌ **NEVER** mix `@FocusState` with `.searchable()` on iOS 26 (keyboard conflicts)
- ❌ **NEVER** use force unwrapping (`!`) except for truly guaranteed cases
- ❌ **NEVER** commit code with warnings (build will fail)
- ❌ **NEVER** bypass actor isolation with `@unchecked Sendable` without justification

## Code Examples (Follow These Patterns!)

### SwiftData Model Creation (CRITICAL - Common Crash!)
**Problem:** Using `persistentModelID` before `save()` causes "temporary identifier" crash
```swift
// ❌ WRONG: Crash "temporary identifier"
let work = Work(title: "...", authors: [author])
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE relationships
let work = Work(title: "...", authors: [])
let author = Author(name: "...")
modelContext.insert(work)    // Gets ID
modelContext.insert(author)  // Gets ID
work.authors = [author]      // NOW safe
try modelContext.save()      // REQUIRED before persistentModelID
```

### State Management Pattern (NO ViewModels!)
```swift
// ✅ CORRECT: @Observable with @State
@Observable
class SearchModel {
    var query: String = ""
    var results: [Work] = []
}

struct SearchView: View {
    @State private var model = SearchModel()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List(model.results) { work in
            Text(work.title)
        }
        .searchable(text: $model.query)
    }
}

// ❌ WRONG: Don't use ObservableObject or ViewModels
```

### SwiftData Child View Pattern
```swift
// ✅ CORRECT: Use @Bindable for reactive updates
struct BookDetailView: View {
    @Bindable var work: Work
    
    var body: some View {
        TextField("Rating", value: $work.personalRating, format: .number)
            .onChange(of: work.personalRating) { /* Updates automatically */ }
    }
}

// ❌ WRONG: View won't update when model changes
struct BookDetailView: View {
    let work: Work  // Missing @Bindable!
}
```

### Swift 6 Concurrency Pattern
```swift
// ✅ CORRECT: Use Task.sleep in actors
actor BackgroundService {
    func pollForUpdates() async {
        while true {
            await performUpdate()
            try? await Task.sleep(for: .seconds(30))
        }
    }
}

// ❌ WRONG: Timer.publish crashes in actors
actor BackgroundService {
    var cancellable: AnyCancellable?
    
    func start() {
        cancellable = Timer.publish(every: 30, on: .main, in: .common)  // CRASH!
            .sink { _ in }
    }
}
```

### Navigation Pattern (iOS 26 HIG)
```swift
// ✅ CORRECT: Push navigation with navigationDestination
NavigationStack {
    List(works) { work in
        NavigationLink(value: work) {
            WorkRow(work: work)
        }
    }
    .navigationDestination(for: Work.self) { work in
        WorkDetailView(work: work)
    }
}

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedWork) { work in
    WorkDetailView(work: work)
}
```

### Testing Pattern (Swift Testing)
```swift
// ✅ CORRECT: Use @Test and #expect
import Testing
@testable import BooksTrackerFeature

@Test("Work creation with valid title")
func testWorkCreation() throws {
    let work = Work(title: "1984")
    #expect(work.title == "1984")
    #expect(work.authors.isEmpty)
}

@Test("ISBN validation", arguments: [
    ("9780141036144", true),
    ("invalid", false)
])
func testISBNValidation(isbn: String, expected: Bool) {
    #expect(ISBN.isValid(isbn) == expected)
}
```

## CRITICAL Rules

**Insert-Before-Relate Pattern:**
```
1. Create model objects
2. Call insert() immediately for each
3. Set relationships AFTER both inserted
4. Call save() before using persistentModelID
```

**Swift 6.2 Concurrency Rules:**
- **ALWAYS** `@MainActor` for UI components and SwiftUI views
- **NEVER** `Timer.publish` in actors → use `await Task.sleep(for:)`
- **NEVER** pass non-Sendable types across actor boundaries
- Prefer structured concurrency (TaskGroup) over unstructured Task.init

**State Management Rules:**
- Use `@Observable` + `@State` (NO ObservableObject or ViewModels!)
- Use `@Bindable` for SwiftData models in child views (enables reactive updates)
- Never mix `@FocusState` with `.searchable()` (iOS 26 manages focus internally)

## Project Structure
```
BooksTracker/BooksTrackerApp.swift          # iOS entry (@main)
BooksTrackerPackage/
  Sources/BooksTrackerFeature/
    Models/      # Work, Edition, Author, UserLibraryEntry
    Views/       # Library, Search, Shelf, Insights tabs
    Services/    # BookSearchAPIService, EnrichmentQueue
  Tests/         # 161 Swift Testing tests
Config/Shared.xcconfig  # Version, bundle ID (UPDATE HERE!)
docs/README.md          # Documentation hub (START HERE)
CLAUDE.md               # Quick reference (<500 lines)
```

**Backend:** Maintained in separate repository at [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend)

## API (Canonical v1.0.0)
```typescript
Response: {success, data: {works, authors}, error: {message, code}, meta}

GET /v1/search/title?q=              # Title search
GET /v1/search/isbn?isbn=            # ISBN (validates 10/13)
GET /v1/search/advanced?title=&author=
POST /v1/enrichment/batch
GET /ws/progress?jobId={uuid}        # WebSocket (real-time)
```

**Backend Repository:** https://github.com/jukasdrj/bookstrack-backend

## SwiftData Models
```
Work 1:many Edition
Work many:many Author  
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```
**CloudKit:** Inverse on to-many only, all attrs have defaults, all relationships optional, can't filter predicates on to-many

## Development

### Add Feature
1. Code: `BooksTrackerPackage/Sources/BooksTrackerFeature/[Category]/`
2. Use `public` for app shell exports
3. Tests: `BooksTrackerPackage/Tests/`
4. Backend: See [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend) repository

### Code Search (IMPORTANT!)
```bash
# ALWAYS ast-grep for Swift (NOT ripgrep!)
ast-grep --lang swift --pattern '@MainActor class $NAME { $$$ }' .
```

## Common Issues

### iOS
1. **Keyboard broken on device:** Remove `.navigationBarDrawer(displayMode:)`, test real device
2. **"temporary identifier" crash:** Call `save()` before `persistentModelID`
3. **CloudKit sync fails:** Test multi-device, check dashboard, reset via Settings

### Backend
4. **Backend issues:** See [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend) repository for troubleshooting

## Security
- ✅ Zero warnings (enforced)
- ✅ No secrets in code (backend manages API keys separately)
- ✅ Real device test (keyboard, camera, CloudKit)
- ✅ WCAG AA contrast (4.5:1+ with .secondary/.tertiary)

## Docs
- **Quick:** CLAUDE.md | **Visual:** docs/workflows/ | **Deep:** docs/features/ | **Why:** docs/product/

**Trust these instructions!** Validated with real builds. Search only if incomplete/incorrect.