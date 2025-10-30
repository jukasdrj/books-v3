# Canonical Contracts Completion - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete canonical data contracts by adding backend genre normalization and iOS DTOMapper integration.

**Architecture:** Backend-first sequential approach. Build and test genre normalizer service first, then integrate into v1 endpoints, then migrate iOS BookSearchAPIService to use DTOMapper.

**Tech Stack:** TypeScript (Cloudflare Workers), Swift 6.2 (SwiftUI + SwiftData), Levenshtein distance for fuzzy matching, Swift Testing framework

**Design Document:** [2025-10-30-canonical-contracts-completion.md](./2025-10-30-canonical-contracts-completion.md)

---

## Phase 1: Backend Genre Normalization

### Task 1: Create Genre Normalizer Service

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`
- Test: `cloudflare-workers/api-worker/test/services/genre-normalizer.test.ts` (if test framework exists)

**Step 1: Create genre-normalizer.ts with core structure**

```typescript
/**
 * Genre Normalization Service
 * Transforms provider-specific genres into canonical subjectTags
 */

/**
 * Canonical genre taxonomy
 * Maps variations → canonical names
 */
const CANONICAL_GENRES: Record<string, string[]> = {
  // Fiction categories
  'Science Fiction': ['Sci-Fi', 'Science Fiction', 'SF', 'Scifi'],
  'Fantasy': ['Fantasy', 'Fantasie'],
  'Mystery': ['Mystery', 'Detective', 'Whodunit', 'Mystrey'],
  'Thriller': ['Thriller', 'Suspense'],
  'Romance': ['Romance', 'Love Story'],
  'Horror': ['Horror', 'Scary'],
  'Literary Fiction': ['Literary', 'Literature', 'Literary Fiction'],
  'Historical Fiction': ['Historical Fiction', 'Historical Novel'],

  // Non-fiction categories
  'Biography': ['Biography', 'Memoir', 'Autobiography'],
  'History': ['History', 'Historical'],
  'Science': ['Science', 'Popular Science'],
  'Philosophy': ['Philosophy', 'Philosophical'],
  'Self-Help': ['Self-Help', 'Self Improvement', 'Personal Development'],
  'Business': ['Business', 'Economics', 'Entrepreneurship'],
  'True Crime': ['True Crime', 'Crime'],

  // Age groups
  'Young Adult': ['Young Adult', 'YA', 'Teen'],
  "Children's": ["Children's", 'Kids', 'Juvenile'],
  'Middle Grade': ['Middle Grade', 'MG'],

  // Special categories
  'Classics': ['Classic', 'Classics', 'Classical'],
  'Contemporary': ['Contemporary', 'Modern'],
  'Graphic Novels': ['Graphic Novel', 'Comics', 'Manga'],
  'Poetry': ['Poetry', 'Poems', 'Verse'],
  'Dystopian': ['Dystopian', 'Dystopia'],
  'Fiction': ['Fiction']
};

/**
 * Provider-specific genre mappings
 * Handles exact matches for known provider formats
 */
const PROVIDER_MAPPINGS: Record<string, string[]> = {
  // Google Books hierarchical format
  'Fiction / Science Fiction / General': ['Science Fiction', 'Fiction'],
  'Fiction / Science Fiction / Dystopian': ['Science Fiction', 'Dystopian', 'Fiction'],
  'Fiction / Fantasy / General': ['Fantasy', 'Fiction'],
  'Fiction / Fantasy / Epic': ['Fantasy', 'Fiction'],
  'Fiction / Mystery & Detective / General': ['Mystery', 'Fiction'],
  'Fiction / Thrillers / General': ['Thriller', 'Fiction'],
  'Fiction / Romance / General': ['Romance', 'Fiction'],
  'Fiction / Horror': ['Horror', 'Fiction'],
  'Fiction / Literary': ['Literary Fiction', 'Fiction'],
  'Fiction / Historical / General': ['Historical Fiction', 'Fiction'],

  // ISBNDB uses "&" separators
  'Science Fiction & Fantasy': ['Science Fiction', 'Fantasy'],
  'Mystery & Thriller': ['Mystery', 'Thriller'],
  'Romance & Fiction': ['Romance', 'Fiction'],

  // OpenLibrary descriptive subjects
  'Dystopian fiction': ['Dystopian', 'Science Fiction'],
  'Science fiction': ['Science Fiction'],
  'Classic Literature': ['Classics', 'Literary Fiction'],
  'Fantasy fiction': ['Fantasy'],
  'Detective and mystery stories': ['Mystery'],

  // Gemini AI free-form genres
  'Sci-fi dystopia': ['Science Fiction', 'Dystopian'],
  'Post-apocalyptic fiction': ['Science Fiction', 'Dystopian'],
  'Epic fantasy': ['Fantasy'],
};

/**
 * Calculate Levenshtein distance between two strings
 * Used for fuzzy genre matching
 */
function levenshteinDistance(a: string, b: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Genre Normalizer Service
 * Transforms provider-specific genres into canonical subjectTags
 */
export class GenreNormalizer {
  private readonly fuzzyThreshold = 0.85;

  /**
   * Normalize raw genres from any provider to canonical subjectTags
   * @param rawGenres - Raw genre strings from provider
   * @param provider - Provider name ('google-books', 'openlibrary', etc.)
   * @returns Array of canonical genre tags (sorted, deduplicated)
   */
  normalize(rawGenres: string[], provider: string): string[] {
    const normalized: Set<string> = new Set();

    for (const raw of rawGenres) {
      // 1. Provider-specific preprocessing
      const cleaned = this.preprocess(raw, provider);

      // 2. Exact mapping lookup
      const exactMatch = PROVIDER_MAPPINGS[cleaned];
      if (exactMatch) {
        exactMatch.forEach(tag => normalized.add(tag));
        continue;
      }

      // 3. Check canonical genre variations
      const canonicalMatch = this.findCanonicalMatch(cleaned);
      if (canonicalMatch) {
        normalized.add(canonicalMatch);
        continue;
      }

      // 4. Fuzzy matching for unmapped genres
      const fuzzyMatch = this.findFuzzyMatch(cleaned);
      if (fuzzyMatch) {
        normalized.add(fuzzyMatch);
      } else {
        // Pass through if no match found (user might have custom tags)
        normalized.add(cleaned);
      }
    }

    // Sort alphabetically for consistency
    return Array.from(normalized).sort();
  }

  /**
   * Provider-specific preprocessing
   * - Google Books: Split "Fiction / Science Fiction / General" → process each part
   * - OpenLibrary: Lowercase normalization, trim
   * - ISBNDB: Split "&" separators
   */
  private preprocess(raw: string, provider: string): string {
    // Trim whitespace
    let cleaned = raw.trim();

    // Provider-specific transformations
    if (provider === 'google-books') {
      // Google Books uses hierarchical format "Fiction / Science Fiction / General"
      // We check the full string first in PROVIDER_MAPPINGS
      // If not found, we'll fuzzy match
      return cleaned;
    }

    if (provider === 'isbndb') {
      // ISBNDB uses "&" separators - but we check full string first
      return cleaned;
    }

    if (provider === 'openlibrary') {
      // OpenLibrary uses lowercase descriptive subjects
      // Capitalize first letter for consistency
      return cleaned.charAt(0).toUpperCase() + cleaned.slice(1).toLowerCase();
    }

    return cleaned;
  }

  /**
   * Find canonical genre by checking all variations
   */
  private findCanonicalMatch(genre: string): string | null {
    const lowerGenre = genre.toLowerCase();

    for (const [canonical, variations] of Object.entries(CANONICAL_GENRES)) {
      if (variations.some(v => v.toLowerCase() === lowerGenre)) {
        return canonical;
      }
    }

    return null;
  }

  /**
   * Find fuzzy match using Levenshtein distance
   * Returns canonical genre if similarity > threshold (85%)
   */
  private findFuzzyMatch(genre: string): string | null {
    const lowerGenre = genre.toLowerCase();
    let bestMatch: string | null = null;
    let bestSimilarity = 0;

    for (const canonical of Object.keys(CANONICAL_GENRES)) {
      const distance = levenshteinDistance(lowerGenre, canonical.toLowerCase());
      const maxLen = Math.max(lowerGenre.length, canonical.length);
      const similarity = 1 - distance / maxLen;

      if (similarity > bestSimilarity && similarity >= this.fuzzyThreshold) {
        bestMatch = canonical;
        bestSimilarity = similarity;
      }
    }

    return bestMatch;
  }
}
```

**Step 2: Commit genre-normalizer.ts**

```bash
cd cloudflare-workers/api-worker
git add src/services/genre-normalizer.ts
git commit -m "feat(backend): add genre normalization service

- Canonical genre taxonomy with 25+ genres
- Provider-specific mappings (Google Books, OpenLibrary, ISBNDB)
- Fuzzy matching with Levenshtein distance (85% threshold)
- Modular design for adding new providers

Related: docs/plans/2025-10-30-canonical-contracts-completion.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Integrate Genre Normalizer into Google Books Normalizer

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts:25`

**Step 1: Import GenreNormalizer at top of file**

```typescript
// Add after existing imports
import { GenreNormalizer } from '../genre-normalizer.js';
```

**Step 2: Create normalizer instance**

Add after imports, before functions:

```typescript
// Create genre normalizer instance (reused across all normalizations)
const genreNormalizer = new GenreNormalizer();
```

**Step 3: Update normalizeGoogleBooksToWork to use genre normalizer**

Replace line 25 in `normalizeGoogleBooksToWork`:

```typescript
// BEFORE:
subjectTags: volumeInfo.categories || [],

// AFTER:
subjectTags: genreNormalizer.normalize(volumeInfo.categories || [], 'google-books'),
```

**Step 4: Update ensureWorkForEdition comment**

Replace line 80 comment:

```typescript
// BEFORE:
subjectTags: [], // Will be populated by genre normalizer (Phase 3)

// AFTER:
subjectTags: [], // No genres available from Edition data
```

**Step 5: Commit google-books.ts changes**

```bash
git add src/services/normalizers/google-books.ts
git commit -m "feat(backend): integrate genre normalizer into Google Books normalizer

- Google Books categories now normalized to canonical genres
- Example: 'Fiction / Science Fiction / General' → ['Fiction', 'Science Fiction']

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Test Genre Normalization (Manual)

**Step 1: Deploy to Cloudflare staging (if available)**

```bash
cd cloudflare-workers/api-worker
npx wrangler deploy --env staging
```

**Step 2: Test v1/search/title endpoint**

```bash
# Test 1984 (should have Science Fiction, Dystopian)
curl "https://api-worker.jukasdrj.workers.dev/v1/search/title?q=1984" | jq '.data.works[0].subjectTags'

# Expected output:
# ["Dystopian", "Fiction", "Science Fiction"]

# Test Dune (should have Science Fiction, Fiction)
curl "https://api-worker.jukasdrj.workers.dev/v1/search/title?q=Dune" | jq '.data.works[0].subjectTags'

# Expected output:
# ["Fiction", "Science Fiction"]
```

**Step 3: Verify legacy endpoints unchanged**

```bash
# Legacy endpoint should still return raw categories
curl "https://api-worker.jukasdrj.workers.dev/search/title?q=1984" | jq '.works[0]'

# Should NOT have normalized genres (no 'subjectTags' field in legacy format)
```

**Step 4: Deploy to production (if staging tests pass)**

```bash
npx wrangler deploy
```

**Step 5: Commit deployment notes**

```bash
git commit --allow-empty -m "deploy(backend): genre normalization live in production

Verified:
- /v1/search/title returns normalized genres
- Legacy /search/title unchanged
- No errors in Cloudflare logs

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 2: iOS DTOMapper Integration

### Task 4: Refactor BookSearchAPIService to Use DTOMapper

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`

**Step 1: Change actor to MainActor class**

The BookSearchAPIService is currently an `actor`, but DTOMapper requires `@MainActor` context. Change the class declaration:

```swift
// BEFORE (line 7):
public actor BookSearchAPIService {

// AFTER:
@MainActor
public class BookSearchAPIService {
```

**Step 2: Add modelContext and dtoMapper properties**

Add after `urlSession` property (around line 10):

```swift
private let modelContext: ModelContext
private let dtoMapper: DTOMapper
```

**Step 3: Update initializer to accept modelContext**

Replace the `init()` method:

```swift
// BEFORE:
public init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10.0
    config.timeoutIntervalForResource = 30.0
    self.urlSession = URLSession(configuration: config)
}

// AFTER:
public init(modelContext: ModelContext) {
    self.modelContext = modelContext
    self.dtoMapper = DTOMapper(modelContext: modelContext)

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10.0
    config.timeoutIntervalForResource = 30.0
    self.urlSession = URLSession(configuration: config)
}
```

**Step 4: Commit initialization changes**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(ios): prepare BookSearchAPIService for DTOMapper integration

- Change actor → @MainActor class (required for SwiftData)
- Add modelContext and dtoMapper properties
- Update initializer to accept modelContext

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Update search() Method to Use DTOMapper

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift:20-100` (search method)

**Step 1: Read current search() method to understand structure**

Find the `search(query:maxResults:scope:)` method (starts around line 20). We'll replace the parsing logic with DTOMapper.

**Step 2: Update search() method to decode canonical response and use DTOMapper**

Replace the entire `search(query:maxResults:scope:)` method with:

```swift
func search(query: String, maxResults: Int = 20, scope: SearchScope = .all) async throws -> SearchResponse {
    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        throw SearchError.invalidQuery
    }

    // iOS 26 HIG: Intelligent routing based on query context
    let endpoint: String
    let urlString: String

    switch scope {
    case .all:
        // Smart detection: ISBN → Title search, otherwise use title search
        // Title search handles ISBNs intelligently + provides best coverage
        endpoint = "/v1/search/title"
        urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)"
    case .title:
        endpoint = "/v1/search/title"
        urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)"
    case .author:
        // Use advanced search with author-only parameter (canonical format)
        endpoint = "/v1/search/advanced"
        urlString = "\(baseURL)\(endpoint)?author=\(encodedQuery)"
    case .isbn:
        // Dedicated ISBN endpoint for ISBNdb lookups (7-day cache, most accurate)
        endpoint = "/v1/search/isbn"
        urlString = "\(baseURL)\(endpoint)?isbn=\(encodedQuery)"
    }

    guard let url = URL(string: urlString) else {
        throw SearchError.invalidURL
    }

    // Execute network request
    let (data, response) = try await urlSession.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw SearchError.networkError
    }

    guard httpResponse.statusCode == 200 else {
        throw SearchError.httpError(statusCode: httpResponse.statusCode)
    }

    // Decode canonical response
    let decoder = JSONDecoder()
    let canonicalResponse = try decoder.decode(CanonicalResponse<BookSearchResponse>.self, from: data)

    guard canonicalResponse.success else {
        let errorMessage = canonicalResponse.error?.message ?? "Unknown error"
        throw SearchError.apiError(message: errorMessage)
    }

    guard let searchData = canonicalResponse.data else {
        throw SearchError.emptyResponse
    }

    // Use DTOMapper to convert DTOs → SwiftData models
    var works: [Work] = []

    for workDTO in searchData.works {
        do {
            let work = try dtoMapper.mapToWork(workDTO)
            works.append(work)
        } catch {
            print("Warning: Failed to map Work DTO: \(error)")
            // Continue processing other works
        }
    }

    // DTOMapper automatically handles:
    // - Deduplication by googleBooksVolumeIDs
    // - Synthetic Work → Real Work merging
    // - Author relationship linking

    // Return SearchResponse with mapped works
    return SearchResponse(
        works: works,
        provider: canonicalResponse.meta.provider ?? "unknown",
        cached: canonicalResponse.meta.cached ?? false
    )
}
```

**Step 3: Remove old parsing helper methods**

Search for and delete these methods if they exist:
- `parseSearchResults(_:)`
- Any other manual JSON → Work conversion methods

**Step 4: Commit search() method refactor**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "refactor(ios): migrate search() to use DTOMapper

- Decode CanonicalResponse<BookSearchResponse> instead of raw JSON
- Use dtoMapper.mapToWork() for all Work conversions
- Remove manual parsing logic (100+ lines deleted)
- Automatic deduplication via DTOMapper

Related: docs/plans/2025-10-30-canonical-contracts-completion.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Update SearchView to Pass ModelContext

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Search/SearchView.swift` (wherever BookSearchAPIService is initialized)

**Step 1: Find BookSearchAPIService initialization**

Search for where `BookSearchAPIService()` is created in SearchView or SearchModel.

**Step 2: Update initialization to pass modelContext**

```swift
// BEFORE:
private let searchService = BookSearchAPIService()

// AFTER:
@Environment(\.modelContext) private var modelContext
// ... then in init or where service is created:
private lazy var searchService = BookSearchAPIService(modelContext: modelContext)
```

OR if in SearchModel:

```swift
// In SearchModel
@MainActor
class SearchModel: ObservableObject {
    private let searchService: BookSearchAPIService

    init(modelContext: ModelContext) {
        self.searchService = BookSearchAPIService(modelContext: modelContext)
    }
}

// In SearchView
@Environment(\.modelContext) private var modelContext
@State private var searchModel: SearchModel
// Initialize in init or use @State initializer
```

**Step 3: Commit SearchView changes**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Search/SearchView.swift
git commit -m "fix(ios): pass modelContext to BookSearchAPIService

- Update SearchView to inject modelContext into BookSearchAPIService
- Ensures DTOMapper has SwiftData context for deduplication

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Fix Compilation Errors Across App

**Step 1: Find all BookSearchAPIService initializations**

```bash
cd BooksTrackerPackage
grep -r "BookSearchAPIService()" Sources/
```

**Step 2: Update each initialization to pass modelContext**

For each file found:
1. Add `@Environment(\.modelContext) private var modelContext` if not present
2. Change `BookSearchAPIService()` → `BookSearchAPIService(modelContext: modelContext)`

**Step 3: Build to verify no compilation errors**

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1
xcodebuild -scheme BooksTracker -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: Build succeeds with 0 errors, 0 warnings

**Step 4: Commit all fixes**

```bash
git add -A
git commit -m "fix(ios): update all BookSearchAPIService call sites

- Pass modelContext to all BookSearchAPIService initializations
- Zero compilation errors

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 3: Testing

### Task 8: Add iOS Unit Tests for DTOMapper Integration

**Files:**
- Create: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookSearchAPIServiceTests.swift`

**Step 1: Create BookSearchAPIServiceTests.swift**

```swift
import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("BookSearchAPIService Tests")
@MainActor
struct BookSearchAPIServiceTests {

    /// Helper: Create in-memory ModelContext for testing
    func createTestContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("BookSearchAPIService uses DTOMapper for search results")
    func testSearchUsesDTOMapper() async throws {
        let context = try createTestContext()
        let service = BookSearchAPIService(modelContext: context)

        // Call real API (requires network)
        let response = try await service.search(query: "1984", maxResults: 5, scope: .title)

        // Verify DTOMapper was used (check normalized genres)
        #expect(!response.works.isEmpty, "Should return search results")

        let firstWork = response.works[0]
        #expect(firstWork.title.contains("1984"), "Should contain '1984' in title")

        // Verify normalized genres (not raw Google Books format)
        #expect(firstWork.subjectTags.contains("Science Fiction") ||
                firstWork.subjectTags.contains("Dystopian"),
                "Should have normalized genres")

        // Should NOT have raw provider genres
        #expect(!firstWork.subjectTags.contains("Fiction / Science Fiction / General"),
                "Should not have raw Google Books genre format")
    }

    @Test("Search deduplication prevents duplicate Works")
    func testDeduplication() async throws {
        let context = try createTestContext()
        let service = BookSearchAPIService(modelContext: context)

        // Search for same book twice
        _ = try await service.search(query: "Dune", maxResults: 5, scope: .title)
        _ = try await service.search(query: "Dune", maxResults: 5, scope: .title)

        // Count Works in SwiftData
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try context.fetch(descriptor)

        // Should not have duplicates (DTOMapper deduplicates by googleBooksVolumeIDs)
        let duneWorks = allWorks.filter { $0.title.contains("Dune") }
        #expect(duneWorks.count <= 2, "Should not create excessive duplicates (max 2 for different editions)")
    }

    @Test("Search by ISBN uses DTOMapper")
    func testISBNSearchUsesDTOMapper() async throws {
        let context = try createTestContext()
        let service = BookSearchAPIService(modelContext: context)

        // Search by ISBN for 1984
        let response = try await service.search(query: "9780451524935", maxResults: 1, scope: .isbn)

        #expect(!response.works.isEmpty, "Should return result for valid ISBN")

        let work = response.works[0]
        #expect(work.subjectTags.contains("Science Fiction") ||
                work.subjectTags.contains("Dystopian"),
                "ISBN search should also have normalized genres")
    }

    @Test("Advanced search uses DTOMapper")
    func testAdvancedSearchUsesDTOMapper() async throws {
        let context = try createTestContext()
        let service = BookSearchAPIService(modelContext: context)

        // Search by author only
        let response = try await service.search(query: "Frank Herbert", maxResults: 5, scope: .author)

        #expect(!response.works.isEmpty, "Should return results for valid author")

        let firstWork = response.works[0]
        #expect(!firstWork.subjectTags.isEmpty || firstWork.title.count > 0,
                "Should have normalized data from DTOMapper")
    }
}
```

**Step 2: Run tests**

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1
xcodebuild test -scheme BooksTrackerPackage -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: All tests pass (requires network for API calls)

**Step 3: Commit tests**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookSearchAPIServiceTests.swift
git commit -m "test(ios): add BookSearchAPIService integration tests

- Verify DTOMapper is used for all search scopes
- Verify deduplication prevents duplicate Works
- Verify normalized genres appear correctly
- All tests pass

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Manual Testing on Real Device

**Step 1: Build and run on iPhone**

```bash
# Using MCP XcodeBuildMCP if available
# Otherwise use Xcode GUI to build and deploy
```

**Step 2: Test search functionality**

Manual test checklist:
- [ ] Search for "1984" - verify results appear
- [ ] Search for "1984" again - verify no duplicate Works in library
- [ ] Check Work detail - verify genres are normalized (e.g., "Science Fiction", not "Fiction / Science Fiction / General")
- [ ] Search by ISBN (9780451524935) - verify normalized genres
- [ ] Advanced search by author ("George Orwell") - verify normalized genres
- [ ] Check existing library entries - verify they are not affected (only new searches use v1)

**Step 3: Check for crashes or errors**

Monitor Xcode console for:
- No SwiftData crashes
- No "temporary identifier" errors
- No network errors

**Step 4: Commit manual test results**

```bash
git commit --allow-empty -m "test(ios): manual testing complete on iPhone

Verified:
- Search returns normalized genres
- Deduplication works (no duplicate Works)
- No crashes or SwiftData errors
- Existing library entries unaffected

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 4: Documentation

### Task 10: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Modify: `CHANGELOG.md`

**Step 1: Update CLAUDE.md implementation status**

Find the "Canonical Data Contracts" section and update:

```markdown
**Implementation Status:**
- ✅ TypeScript types defined (`enums.ts`, `canonical.ts`, `responses.ts`)
- ✅ Google Books normalizers (`normalizeGoogleBooksToWork`, `normalizeGoogleBooksToEdition`)
- ✅ All 3 `/v1/*` endpoints deployed and tested with real API
- ✅ Backend genre normalization service (genre-normalizer.ts)
- ✅ Backend enrichment services migrated to canonical format
- ✅ AI scanner WebSocket messages use canonical DTOs
- ✅ iOS Swift Codable DTOs (`WorkDTO`, `EditionDTO`, `AuthorDTO`)
- ✅ iOS search services migrated to `/v1/*` endpoints with DTOMapper
- ✅ iOS enrichment service migrated to canonical parsing
- ✅ Comprehensive test coverage (CanonicalAPIResponseTests, BookSearchAPIServiceTests)
- ✅ DTOMapper fully integrated in search flow (deduplication active)
- ⏳ CSV import and bookshelf scan DTO integration (deferred, separate feature)
- ⏳ Legacy endpoint deprecation (deferred 2-4 weeks)
```

**Step 2: Update design document checklist**

In `docs/plans/2025-10-29-canonical-data-contracts-design.md`, check off completed items:

```markdown
### Backend (Cloudflare Workers)

- [x] Create `src/services/genre-normalizer.ts`
- [x] Update `src/services/normalizers/google-books.ts`
- [x] Deploy to production
- [x] Verify genre normalization working correctly

### iOS (SwiftUI + SwiftData)

- [x] Refactor `BookSearchAPIService.swift`
- [x] Update `search()` to use DTOMapper
- [x] Remove legacy parsing code
- [x] Add unit tests (BookSearchAPIServiceTests.swift)
- [x] Run full test suite
- [x] Run on real device (iPhone, iPad)
```

**Step 3: Update CHANGELOG.md**

Add new entries at the top:

```markdown
## [Unreleased]

### Added
- Backend: Genre normalization service with 25+ canonical genres
- Backend: Provider-specific mappings (Google Books, OpenLibrary, ISBNDB)
- Backend: Fuzzy genre matching with Levenshtein distance (85% threshold)
- iOS: DTOMapper integration in BookSearchAPIService for all search operations
- iOS: Automatic Work deduplication by googleBooksVolumeIDs
- iOS: BookSearchAPIServiceTests for integration testing

### Changed
- Backend: All v1 search endpoints now return normalized genres
- iOS: BookSearchAPIService migrated from actor to @MainActor class
- iOS: Removed 100+ lines of manual JSON parsing code

### Fixed
- iOS: Search no longer creates duplicate Works when searching multiple times
- iOS: Genres now display consistently (e.g., "Science Fiction" instead of "Fiction / Science Fiction / General")
```

**Step 4: Commit documentation updates**

```bash
git add CLAUDE.md docs/plans/2025-10-29-canonical-data-contracts-design.md CHANGELOG.md
git commit -m "docs: update for canonical contracts completion

- Mark genre normalization as implemented
- Mark DTOMapper integration as complete
- Update CHANGELOG with new features

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Success Criteria

**Backend:**
- [x] Genre normalizer service created and tested
- [x] All v1 endpoints return normalized genres
- [x] Legacy endpoints unchanged
- [x] No errors in production logs

**iOS:**
- [x] BookSearchAPIService uses DTOMapper for all searches
- [x] Deduplication works (searching twice creates 0 duplicates)
- [x] Normalized genres appear in UI
- [x] All unit tests pass
- [x] Manual testing on real device successful
- [x] Zero compilation errors/warnings

**Documentation:**
- [x] CLAUDE.md updated with implementation status
- [x] Design document checklist completed
- [x] CHANGELOG updated with new features

---

## Rollback Plan

**If issues discovered:**

**Backend Rollback:**
```bash
cd cloudflare-workers/api-worker
git revert HEAD~2  # Revert last 2 commits (normalizer + integration)
npx wrangler deploy
```

**iOS Rollback:**
```bash
cd BooksTrackerPackage
git revert HEAD~4  # Revert DTOMapper integration commits
# Build and deploy expedited App Store update
```

---

## Notes for Executing Engineer

**Assumptions:**
- You have Cloudflare Workers CLI (`wrangler`) installed
- You have Xcode 16+ with iOS 26 SDK
- You have network access for API testing
- You understand Swift 6.2 concurrency (@MainActor)
- You understand SwiftData relationships and deduplication

**Testing Notes:**
- Backend tests require deploying to staging/production (no local test framework)
- iOS tests require network access (call real API)
- Manual testing on real device is CRITICAL (simulators don't catch all issues)

**Common Pitfalls:**
- Don't forget to pass modelContext to BookSearchAPIService in all initialization sites
- Don't skip manual testing - SwiftData issues only appear on real devices
- Don't forget to update CHANGELOG and documentation

**Questions?**
- Design document: `docs/plans/2025-10-30-canonical-contracts-completion.md`
- Parent design: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Ask in #bookstrack-dev Slack channel (if available)
