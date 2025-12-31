# UserJourneys E2E Tests

**Directory:** `Tests/BooksTrackerFeatureTests/Workflows/UserJourneys/`

Phase 1 end-to-end (E2E) tests for BooksTrack core user workflows. These tests validate complete user journeys from search through library management, using the actual app architecture.

## Purpose

E2E tests in this directory verify:
- **Complete workflows:** User actions from start to finish (search → add to library → rate → mark read)
- **Cross-layer integration:** Views, state management, persistence, and API communication working together
- **Real-world scenarios:** Using realistic mock data and realistic timing constraints
- **Data consistency:** SwiftData persistence, CloudKit sync readiness, and state propagation

## Test Categories

### Phase 1 (Planned)

1. **Search & Add Workflow** - `SearchAndAddWorkflow.swift`
   - User searches for a book
   - Taps result to view details
   - Adds to library
   - Verifies library is updated

2. **Reading Session Workflow** - `ReadingSessionWorkflow.swift`
   - User marks book as "currently reading"
   - Logs reading sessions with page progress
   - Verifies reading stats and progress updates

3. **Library Management Workflow** - `LibraryManagementWorkflow.swift`
   - User views full library with filtering
   - Searches within library
   - Marks books as read
   - Updates ratings

4. **Error Recovery Workflow** - `ErrorRecoveryWorkflow.swift`
   - Network timeout during search
   - Graceful degradation when API returns partial results
   - User can still use app in offline mode

## Running Tests

### Run All E2E Tests
```bash
swift test --filter BooksTrackerFeatureTests.UserJourneys
```

### Run Specific Test
```bash
swift test --filter 'SearchAndAddWorkflow'
```

### Run with Verbose Output
```bash
swift test --filter UserJourneys --verbose
```

### Run from Xcode
1. Open project: `BooksTrackerPackage.xcodeproj`
2. Select Test Navigator (Cmd+6)
3. Expand `BooksTrackerFeatureTests > Workflows > UserJourneys`
4. Click play button on specific test

## How to Add New Journey Tests

### 1. Create New Test File

```swift
//
//  YourJourneyTests.swift
//  BooksTrackerFeatureTests
//
//  User Journey: [Brief description]

import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("Your Journey Tests")
@MainActor
struct YourJourneyTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        modelContainer = try ModelContainer.createWorkflowTestContainer()
        modelContext = ModelContext(modelContainer)
    }

    @Test("Journey: User does X, then Y, expects Z")
    func yourJourneyName() {
        // Setup: Create test data
        // Action: Perform user actions
        // Verify: Check results using TestValidationHelpers
    }
}
```

### 2. Use Test Builders for Setup

```swift
@Test("User adds book to library")
func userAddsBook() throws {
    var workBuilder = WorkBuilder(title: "Harry Potter", modelContext: modelContext)
    workBuilder = workBuilder
        .withAuthor(name: "J.K. Rowling")
        .withEdition(isbn: "9780439708180")
    let work = try workBuilder.build()

    // Verify library contains the work
    TestValidationHelpers.verifyLibraryContains(
        modelContext: modelContext,
        expectedTitles: ["Harry Potter"]
    )
}
```

### 3. Leverage Test Validation Helpers

```swift
@Test("Search returns quality results")
func searchReturnsQuality() throws {
    let mockData = TestValidationHelpers.createMockSearchResponse(
        query: "swift",
        bookCount: 10,
        page: 1,
        totalPages: 5
    )

    let decoder = JSONDecoder()
    let response = try decoder.decode(V3SearchResponse.self, from: mockData)

    // Validate response schema
    TestValidationHelpers.verifyV3SearchResponseSchema(response)

    // Verify search ordering
    TestValidationHelpers.verifySearchResultsOrdering(response.data.books)
}
```

### 4. Test Error Scenarios

```swift
@Test("App handles network timeout gracefully")
func handlesNetworkTimeout() {
    let error = TestValidationHelpers.createNetworkTimeoutError()

    // Simulate API timeout
    // Verify app remains functional
    // Verify user sees friendly error message
}
```

## Common Patterns & Best Practices

### 1. Use the Insert-Before-Relate Pattern

**REQUIRED:** Always insert models before setting relationships:

```swift
// CORRECT: Insert first, then relate
let work = Work(title: "...")
modelContext.insert(work)  // Get permanent ID

let author = Author(name: "...")
modelContext.insert(author)

work.authors = [author]  // Safe to relate
try modelContext.save()

// WRONG: Don't set relationships before insert
let work = Work(title: "...")
work.authors = [author]  // ID not yet assigned!
modelContext.insert(work)
```

### 2. Use @Bindable for Reactive Views

When passing Work to child views that observe relationships:

```swift
struct WorkDetailView: View {
    @Bindable var work: Work  // NOT @Binding or plain var

    var body: some View {
        Text("Rating: \(work.userEntry?.personalRating ?? 0)")  // Updates reactively
    }
}
```

### 3. Use Realistic Mock Data

```swift
// GOOD: Use recognizable ISBNs and realistic data
let mockData = TestValidationHelpers.createMockSearchResponse(
    query: "Harry Potter",  // Specific, recognizable
    bookCount: 5,
    page: 1,
    totalPages: 1
)

// AVOID: Generic, unrealistic test data
let isbn = "0000000000000"  // Non-existent ISBN
```

### 4. Verify Performance Requirements

```swift
@Test("Large library (100+ books) loads quickly")
func largeLibraryPerformance() async throws {
    // Create 100+ books in library
    // ...

    let elapsedMs = try await TestValidationHelpers.measurePerformance("Load library") {
        // Perform operation
    }

    TestValidationHelpers.verifyPerformance(
        operationName: "Load library",
        elapsedTime: elapsedMs / 1000.0,
        maxTimeMs: 500
    )
}
```

### 5. Test Error Recovery

```swift
@Test("App recovers from partial API failure")
func recoversFromPartialFailure() throws {
    // Create mock response with some successes, some failures
    let results = TestValidationHelpers.createMockPartialFailureResponse(
        totalBooks: 10,
        successCount: 7
    )

    // Verify graceful degradation
    TestValidationHelpers.verifyGracefulDegradation(
        resultCount: results.count,
        expectedMinimum: 5  // At least 50% success
    )
}
```

### 6. Verify Observable State Changes

```swift
@Test("Library updates when work is added")
func libraryUpdatesObservably() throws {
    // Before: Library empty
    TestValidationHelpers.verifyLibraryCount(
        modelContext: modelContext,
        expectedCount: 0
    )

    // Action: Add book
    // ...

    // After: Library contains new book
    TestValidationHelpers.verifyLibraryCount(
        modelContext: modelContext,
        expectedCount: 1
    )
}
```

## Test Data Consistency

All mock data must follow:

### ISBN Format
- **ISBN-13:** 13 digits (e.g., `9780439708180`)
- **ISBN-10:** 10 digits (e.g., `0439708188`)

### Book Quality Scores
- Range: 0-100
- Realistic range: 70-100 (higher = better metadata quality)

### Authors
- Non-empty for all books
- Realistic names (avoid "Test Author" unless absolutely necessary)

### Publication Year
- Range: 1000-2100
- Typical range: 1900-2025

### Accessibility Tags
- Must be from known set: "Dyslexia Friendly", "Large Print", "Audiobook Available", "Braille", "High Contrast"
- Don't create fictional tags

### API Providers
- Known values: "alexandria", "google-books", "openlibrary", "isbndb"
- Don't make up provider names

## Validation Helpers Reference

### Fixture Validation
- `verifyMockDataConsistency()` - Ensures all mock data is realistic
- `verifyV3SearchResponseSchema()` - Validates API response format
- `verifyContainerIsolation()` - Ensures test isolation

### Navigation Assertions
- `verifyNavigationState()` - Check current tab and stack depth

### Library Assertions
- `verifyLibraryContains()` - Check specific books in library
- `verifyLibraryExcludes()` - Check books NOT in library
- `verifyLibraryCount()` - Check exact book count

### Search Assertions
- `verifySearchResults()` - Validate search results format and content
- `verifySearchResultsOrdering()` - Ensure results sorted by quality

### Observable State
- `verifyObservableStateChange()` - Verify state propagation
- `verifyWorkObservableRelationships()` - Check relationship updates

### Performance
- `verifyPerformance()` - Measure and verify operation timing
- `measurePerformance()` - Get elapsed time for operation
- `verifySearchDebouncing()` - Check API call throttling
- `verifyStateTransitionSynchronicity()` - Verify UI updates are immediate

### Error Scenarios
- `createNetworkTimeoutError()` - Mock network timeout
- `createMockErrorResponse()` - Mock API error
- `createMockPartialFailureResponse()` - Mock partial success
- `verifyGracefulDegradation()` - Check app handles failures

### Mock Data Factories
- `createMockSearchResponse()` - Create realistic search response
- `createMockISBNResponse()` - Create realistic ISBN lookup response

## Swift 6 Concurrency Notes

All tests must be `@MainActor` to satisfy Swift 6 strict concurrency:

```swift
@Suite("Your Tests")
@MainActor  // Required for Swift 6
struct YourTests {
    @Test
    func yourTest() async throws {
        // Test code
    }
}
```

## Test Isolation & Cleanup

Each test gets:
- **Fresh ModelContainer:** In-memory, empty database
- **Isolated ModelContext:** No sharing between tests
- **Automatic cleanup:** Automatic when test ends

Do NOT share containers/contexts between tests:

```swift
// WRONG: Shared state between tests
var sharedContext: ModelContext!

@Suite struct Tests {
    init() {
        sharedContext = // ...  Error-prone!
    }
}

// CORRECT: Fresh container per test
@Suite struct Tests {
    var modelContext: ModelContext!

    init() throws {
        let container = try ModelContainer.createWorkflowTestContainer()
        modelContext = ModelContext(container)
    }
}
```

## CI/CD Integration

Tests are automatically run in CI when:
1. Changes pushed to `main` branch
2. Pull request opened against `main`
3. Manual trigger via GitHub Actions dashboard

All E2E tests must pass before merge.

## Debugging Failed Tests

### 1. Run Single Test with Full Output
```bash
swift test --filter 'SpecificTest' --verbose 2>&1 | tee test_output.log
```

### 2. Add Debug Assertions
```swift
@Test("Debug example")
func debugTest() {
    let work = Work(title: "Debug Book")
    print("Work created: \(work.title)")  // Visible in test output

    #expect(work.title == "Debug Book")
}
```

### 3. Check Recent Commits
Tests often fail after API changes. Review recent commits to API models/services.

### 4. Verify Mock Data
Use `verifyMockDataConsistency()` to catch data setup issues early:

```swift
@Test("Setup is valid")
func setupIsValid() {
    let works = [/* ... */]
    TestValidationHelpers.verifyMockDataConsistency(works)  // Fail fast
}
```

## Related Documentation

- **CLAUDE.md** - Development environment setup, recommended commands
- **AGENTS.md** - Project architecture, API contracts, code style
- **Workflows/README.md** - Other workflow tests (Reading, CloudKit, Scanning)
- **BooksTrackerFeature/API/** - API integration code
- **BooksTrackerFeature/DTOs/** - Data models and API contracts

## Questions & Support

For questions about:
- **Test structure:** See existing tests in `Reading/`, `CloudKit/`, `Scanning/`
- **Validation helpers:** See `TestValidationHelpers.swift` documentation
- **API contracts:** See `DTOs/V3/` folder for schema definitions
- **SwiftData patterns:** See `TestHelpers/WorkflowTestHelpers.swift` builders
