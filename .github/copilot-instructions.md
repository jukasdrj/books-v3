# GitHub Copilot Instructions for BooksTrack

**Version:** 3.0.1 (Build 188) | **iOS 26.0+, Swift 6.1+** | **Bundle:** `Z67H8Y8DW.com.oooefam.booksV3`

## Stack
**iOS:** SwiftUI + @Observable (NO ViewModels!) + SwiftData + CloudKit | Swift Testing (@Test, 161 tests)  
**Backend:** Separate repository at [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend)

## Build & Test (VALIDATED)

### iOS (Xcode REQUIRED - NOT available in CI)
```bash
# Workspace: BooksTracker.xcworkspace (NOT .xcodeproj!)
# Scheme: BooksTracker | Version: Config/Shared.xcconfig
# Zero warnings enforced: GCC_TREAT_WARNINGS_AS_ERRORS = YES

# MCP commands (requires XcodeBuildMCP server):
/build /test /gogo /device-deploy /sim
```

## CRITICAL Rules (Common Crashes!)

### SwiftData Lifecycle
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
**Rules:** (1) `insert()` immediately (2) relationships AFTER both inserted (3) `save()` before using IDs

### Swift 6.1 Concurrency
- **NEVER** `Timer.publish` in actors → use `await Task.sleep(for:)`
- **ALWAYS** `@MainActor` for UI
- **NEVER** pass non-Sendable across actor boundaries

### State Management
- Use `@Observable` + `@State` (NO ViewModels!)
- Use `@Bindable` for SwiftData in child views (reactive updates)
- Never mix `@FocusState` with `.searchable()` (iOS 26 manages focus)

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