# Canonical Data Contracts - Completion Implementation

**Date:** October 30, 2025
**Version:** 1.0.0
**Status:** Design Approved
**Author:** BooksTrack Team
**Parent Design:** [2025-10-29-canonical-data-contracts-design.md](./2025-10-29-canonical-data-contracts-design.md)

## Executive Summary

This document defines the **completion phase** of the canonical data contracts implementation. It focuses on two critical pieces:
1. **Backend:** Genre normalization service to transform provider-specific genres into canonical subjectTags
2. **iOS:** Integration of DTOMapper into BookSearchAPIService to replace manual parsing

**What's Already Done:**
- ✅ TypeScript canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)
- ✅ All 3 v1 search endpoints deployed and tested
- ✅ iOS DTOMapper with full deduplication logic
- ✅ Swift Codable DTOs mirroring TypeScript types
- ✅ Comprehensive test coverage (CanonicalAPIResponseTests)

**What This Implementation Adds:**
- ✅ Genre normalization service (backend)
- ✅ DTOMapper integration in search flow (iOS)
- ✅ Removal of legacy parsing code (iOS)

**Deferred to Future Phases:**
- ⏳ Backend deduplication service (iOS-only deduplication is sufficient)
- ⏳ V1 endpoints for enrichment/scan (internal APIs, no migration needed)
- ⏳ CSV import and bookshelf scan DTO integration (separate feature branch)

---

## Design Philosophy

### Backend-First Sequential Approach

**Rationale:** Complete and validate each layer independently before moving to the next.

**Implementation Order:**
1. **Backend:** Build genre-normalizer.ts with full mapping logic
2. **Backend:** Integrate genre normalizer into existing v1 endpoint normalizers
3. **iOS:** Refactor BookSearchAPIService to use DTOMapper
4. **iOS:** Remove all legacy parsing code

**Benefits:**
- Each layer validated independently before moving to next
- Backend changes deployed and tested before iOS migration
- Easy rollback if issues discovered
- Clear separation of concerns

**Trade-offs:**
- Takes longer than parallel development
- iOS team waits for backend genre normalization to complete
- More commits/PRs to review

---

## Backend Architecture

### Genre Normalization Service

**Location:** `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`

**Responsibilities:**
- Transform provider-specific genres → canonical subjectTags
- Exact mapping lookup for known patterns
- Fuzzy matching for unmapped genres (Levenshtein distance)
- Deduplication and sorting of results

**Core Interface:**

```typescript
export class GenreNormalizer {
  private readonly mappings: Map<string, string[]>;
  private readonly fuzzyThreshold = 0.85;

  /**
   * Normalize raw genres from any provider to canonical subjectTags
   * @param rawGenres - Raw genre strings from provider
   * @param provider - Provider name ('google-books', 'openlibrary', etc.)
   * @returns Array of canonical genre tags
   */
  normalize(rawGenres: string[], provider: string): string[] {
    const normalized: Set<string> = new Set();

    for (const raw of rawGenres) {
      // 1. Provider-specific preprocessing
      const cleaned = this.preprocess(raw, provider);

      // 2. Exact mapping lookup
      if (this.mappings.has(cleaned)) {
        this.mappings.get(cleaned)!.forEach(tag => normalized.add(tag));
        continue;
      }

      // 3. Fuzzy matching for unmapped genres
      const fuzzyMatch = this.findFuzzyMatch(cleaned);
      if (fuzzyMatch) {
        fuzzyMatch.forEach(tag => normalized.add(tag));
      } else {
        // Pass through if no match found
        normalized.add(cleaned);
      }
    }

    // 4. Sort alphabetically for consistency
    return Array.from(normalized).sort();
  }

  /**
   * Provider-specific preprocessing
   * - Google Books: Split "Fiction / Science Fiction / General" → ["Fiction", "Science Fiction"]
   * - OpenLibrary: Lowercase normalization
   * - ISBNDB: Split "&" separators
   */
  private preprocess(raw: string, provider: string): string {
    // Implementation details...
  }

  /**
   * Find fuzzy match using Levenshtein distance
   */
  private findFuzzyMatch(genre: string): string[] | null {
    // Implementation details...
  }
}
```

**Canonical Taxonomy (Initial Set):**

```typescript
const CANONICAL_GENRES = {
  // Fiction categories
  'Science Fiction': ['Sci-Fi', 'Science Fiction', 'SF'],
  'Fantasy': ['Fantasy', 'Fantasie'],
  'Mystery': ['Mystery', 'Detective', 'Whodunit'],
  'Thriller': ['Thriller', 'Suspense'],
  'Romance': ['Romance', 'Love Story'],
  'Horror': ['Horror', 'Scary'],
  'Literary Fiction': ['Literary', 'Literature'],
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
  'Dystopian': ['Dystopian', 'Dystopia']
};
```

**Provider-Specific Mappings:**

```typescript
const PROVIDER_MAPPINGS = {
  // Google Books uses hierarchical format
  'Fiction / Science Fiction / General': ['Science Fiction', 'Fiction'],
  'Fiction / Science Fiction / Dystopian': ['Science Fiction', 'Dystopian', 'Fiction'],
  'Fiction / Fantasy / General': ['Fantasy', 'Fiction'],
  'Fiction / Mystery & Detective / General': ['Mystery', 'Fiction'],

  // ISBNDB uses "&" separators
  'Science Fiction & Fantasy': ['Science Fiction', 'Fantasy'],
  'Mystery & Thriller': ['Mystery', 'Thriller'],

  // OpenLibrary uses descriptive subjects
  'Dystopian fiction': ['Dystopian', 'Science Fiction'],
  'Science fiction': ['Science Fiction'],
  'Classic Literature': ['Classics', 'Literary Fiction'],

  // Gemini AI returns free-form genres
  'Sci-fi dystopia': ['Science Fiction', 'Dystopian'],
  'Post-apocalyptic fiction': ['Science Fiction', 'Dystopian']
};
```

**Fuzzy Matching Strategy:**

When exact mapping not found:
1. Calculate Levenshtein distance between input and all canonical genres
2. If distance < 15% of genre length (threshold = 0.85 similarity), consider it a match
3. Return canonical genre for the match
4. If no match found, pass through original genre (user might have custom tags)

**Examples:**

```typescript
// Exact mapping
normalize(['Fiction / Science Fiction / General'], 'google-books')
// → ['Fiction', 'Science Fiction']

// Fuzzy matching
normalize(['Sci-Fi & Fantasie'], 'unknown')
// → ['Fantasy', 'Science Fiction']

// Pass-through (no match)
normalize(['Steampunk'], 'unknown')
// → ['Steampunk']

// Deduplication
normalize(['Science Fiction', 'Science fiction', 'Sci-Fi'], 'openlibrary')
// → ['Science Fiction']
```

---

### Integration with Existing Normalizers

**Update existing normalizer functions to use GenreNormalizer:**

```typescript
// src/services/normalizers/google-books.ts
import { GenreNormalizer } from '../genre-normalizer.js';

const genreNormalizer = new GenreNormalizer();

export function normalizeGoogleBooksToWork(item, provider = 'google-books') {
  const rawCategories = item.volumeInfo?.categories || [];

  return {
    title: item.volumeInfo?.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(rawCategories, 'google-books'), // ← NEW
    firstPublicationYear: extractYear(item.volumeInfo?.publishedDate),
    // ... rest of fields unchanged
  };
}

export function normalizeGoogleBooksToEdition(item, provider = 'google-books') {
  // No changes needed - Editions don't have genres
}
```

**No changes needed in v1 handlers** - they already call normalizer functions:

```typescript
// src/handlers/v1/search-title.ts (unchanged)
const works = googleBooksItems.map(item =>
  normalizeGoogleBooksToWork(item, 'google-books')
);
// Genre normalization happens automatically inside normalizer!
```

---

## iOS Architecture

### DTOMapper Integration

**Goal:** Replace all manual parsing in BookSearchAPIService with DTOMapper.

**Current State:**

```swift
// BookSearchAPIService.swift:194
// TODO: Use DTOMapper here instead of manual parsing
private func parseSearchResults(_ json: [String: Any]) -> [Work] {
    // Manual JSON → Work conversion
    // Duplicates logic that DTOMapper already handles
    // Error-prone and inconsistent with enrichment flow
}
```

**Refactored Architecture:**

```swift
// BookSearchAPIService.swift
@MainActor
public final class BookSearchAPIService {
    private let modelContext: ModelContext
    private let dtoMapper: DTOMapper

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.dtoMapper = DTOMapper(modelContext: modelContext)
    }

    // MARK: - Search Methods

    public func searchByTitle(_ query: String) async throws -> [Work] {
        guard !query.isEmpty else {
            throw BookSearchError.invalidQuery
        }

        // 1. Call v1 endpoint (canonical response)
        let url = URL(string: "\(baseURL)/v1/search/title?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BookSearchError.networkError
        }

        // 2. Decode canonical response
        let canonicalResponse = try JSONDecoder().decode(
            CanonicalResponse<BookSearchResponse>.self,
            from: data
        )

        guard canonicalResponse.success else {
            throw BookSearchError.apiError(canonicalResponse.error?.message ?? "Unknown error")
        }

        // 3. Use DTOMapper to convert DTOs → SwiftData models
        var works: [Work] = []

        for workDTO in canonicalResponse.data.works {
            let work = try dtoMapper.mapToWork(workDTO)
            works.append(work)
        }

        // DTOMapper automatically handles:
        // - Deduplication by googleBooksVolumeIDs
        // - Synthetic Work → Real Work merging
        // - Author relationship linking

        return works
    }

    public func searchByISBN(_ isbn: String) async throws -> Work? {
        // Similar implementation, calls /v1/search/isbn
    }

    public func advancedSearch(title: String?, author: String?) async throws -> [Work] {
        // Similar implementation, calls /v1/search/advanced
    }
}
```

**Key Changes:**
1. **Endpoint migration:** `/search/title` → `/v1/search/title`
2. **Response decoding:** Decode to `CanonicalResponse<BookSearchResponse>` (Swift Codable)
3. **Parsing delegation:** Use `dtoMapper.mapToWork()` instead of manual parsing
4. **Remove legacy code:** Delete all manual JSON → Work conversion logic

**Deduplication Behavior:**

DTOMapper handles deduplication automatically:

```swift
// DTOMapper.swift:164-174 (already implemented)
private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
    guard !volumeIDs.isEmpty else { return nil }

    let descriptor = FetchDescriptor<Work>()
    let allWorks = try modelContext.fetch(descriptor)

    // Find Work with any matching googleBooksVolumeID
    return allWorks.first { existingWork in
        !Set(existingWork.googleBooksVolumeIDs).isDisjoint(with: volumeIDs)
    }
}
```

**Result:** No duplicate Works in SwiftData, even if user searches multiple times.

---

## Testing Strategy

### Backend Testing

**Unit Tests for GenreNormalizer:**

```typescript
// test/services/genre-normalizer.test.ts
import { describe, test, expect } from 'vitest';
import { GenreNormalizer } from '../src/services/genre-normalizer.js';

describe('GenreNormalizer', () => {
  const normalizer = new GenreNormalizer();

  describe('Exact Mappings', () => {
    test('normalizes Google Books hierarchical genres', () => {
      expect(normalizer.normalize(
        ['Fiction / Science Fiction / General'],
        'google-books'
      )).toEqual(['Fiction', 'Science Fiction']);
    });

    test('handles ISBNDB "&" separators', () => {
      expect(normalizer.normalize(
        ['Science Fiction & Fantasy'],
        'isbndb'
      )).toEqual(['Fantasy', 'Science Fiction']); // Sorted!
    });

    test('handles OpenLibrary descriptive subjects', () => {
      expect(normalizer.normalize(
        ['Dystopian fiction', 'Science fiction'],
        'openlibrary'
      )).toEqual(['Dystopian', 'Science Fiction']);
    });
  });

  describe('Fuzzy Matching', () => {
    test('matches slight variations', () => {
      expect(normalizer.normalize(
        ['Sci-Fi', 'Fantasie'],
        'unknown'
      )).toEqual(['Fantasy', 'Science Fiction']);
    });

    test('handles typos', () => {
      expect(normalizer.normalize(
        ['Scifi', 'Mystrey'],
        'unknown'
      )).toEqual(['Mystery', 'Science Fiction']);
    });
  });

  describe('Pass-through', () => {
    test('preserves unmapped genres', () => {
      expect(normalizer.normalize(
        ['Steampunk', 'Cyberpunk'],
        'unknown'
      )).toEqual(['Cyberpunk', 'Steampunk']); // Sorted!
    });
  });

  describe('Deduplication', () => {
    test('removes duplicate tags', () => {
      expect(normalizer.normalize(
        ['Science Fiction', 'Science fiction', 'Sci-Fi'],
        'openlibrary'
      )).toEqual(['Science Fiction']);
    });
  });
});
```

**Integration Tests for V1 Endpoints:**

```typescript
// test/integration/v1-endpoints.test.ts
describe('V1 Search Endpoints', () => {
  test('/v1/search/title returns normalized genres', async () => {
    const response = await fetch('http://localhost:8787/v1/search/title?q=1984');
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data.works[0].subjectTags).toContain('Science Fiction');
    expect(data.data.works[0].subjectTags).toContain('Dystopian');
    expect(data.data.works[0].subjectTags).not.toContain('Fiction / Science Fiction / General');
  });

  test('/v1/search/isbn returns normalized genres', async () => {
    const response = await fetch('http://localhost:8787/v1/search/isbn?isbn=9780451524935');
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data.works[0].subjectTags).toContain('Science Fiction');
  });
});
```

### iOS Testing

**Unit Tests for DTOMapper Integration:**

```swift
// Tests/BooksTrackerFeatureTests/BookSearchAPIServiceTests.swift
import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("BookSearchAPIService Tests")
struct BookSearchAPIServiceTests {

    @Test("Search by title uses DTOMapper")
    func testSearchByTitleUsesDTOMapper() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Edition.self, Author.self, configurations: config)
        let context = ModelContext(container)

        let service = BookSearchAPIService(modelContext: context)

        // Call real API (or mock if network unavailable)
        let results = try await service.searchByTitle("1984")

        // Verify DTOMapper was used
        #expect(!results.isEmpty)
        #expect(results[0].title == "1984")
        #expect(results[0].subjectTags.contains("Science Fiction"))

        // Verify deduplication works
        let secondSearch = try await service.searchByTitle("1984")
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try context.fetch(descriptor)

        // Should have same Work instance, not duplicate
        #expect(allWorks.count == 1)
    }

    @Test("Search handles normalized genres correctly")
    func testNormalizedGenres() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Edition.self, Author.self, configurations: config)
        let context = ModelContext(container)

        let service = BookSearchAPIService(modelContext: context)
        let results = try await service.searchByTitle("Dune")

        #expect(!results.isEmpty)
        #expect(results[0].subjectTags.contains("Science Fiction"))
        #expect(!results[0].subjectTags.contains("Fiction / Science Fiction / General"))
    }
}
```

**Existing Tests Still Pass:**

```swift
// Tests/BooksTrackerFeatureTests/DTOMapperTests.swift (already exists)
// All existing DTOMapper tests should continue passing
// No changes needed - DTOMapper behavior unchanged
```

### Manual Testing Checklist

**Backend (Cloudflare Worker):**
- [ ] Deploy genre-normalizer.ts to staging
- [ ] Test `/v1/search/title?q=1984` - verify `subjectTags` contains `["Science Fiction", "Dystopian"]`
- [ ] Test `/v1/search/isbn?isbn=9780451524935` - verify normalized genres
- [ ] Test `/v1/search/advanced?title=Dune&author=Herbert` - verify normalized genres
- [ ] Verify legacy endpoints (`/search/title`) still return old format

**iOS (Xcode):**
- [ ] Run all unit tests (should pass)
- [ ] Search for "1984" twice - verify no duplicate Works created
- [ ] Search by ISBN - verify normalized genres appear
- [ ] Advanced search - verify normalized genres work
- [ ] Verify existing library entries not affected (only new searches use v1)

---

## Implementation Checklist

### Phase 1: Backend Genre Normalization

- [ ] Create `src/services/genre-normalizer.ts`
  - [ ] Implement `GenreNormalizer` class
  - [ ] Add canonical genre taxonomy (initial set)
  - [ ] Add provider-specific mappings (Google Books, OpenLibrary, ISBNDB)
  - [ ] Implement fuzzy matching (Levenshtein distance)
  - [ ] Add unit tests
- [ ] Update `src/services/normalizers/google-books.ts`
  - [ ] Import `GenreNormalizer`
  - [ ] Replace raw categories with `genreNormalizer.normalize()`
  - [ ] Add integration tests
- [ ] Deploy to staging
  - [ ] Test all v1 endpoints return normalized genres
  - [ ] Verify legacy endpoints unchanged
- [ ] Deploy to production
  - [ ] Monitor for errors (24 hours)
  - [ ] Verify genre normalization working correctly

### Phase 2: iOS DTOMapper Integration

- [ ] Refactor `BookSearchAPIService.swift`
  - [ ] Add `DTOMapper` property
  - [ ] Update `searchByTitle()` to call `/v1/search/title`
  - [ ] Update `searchByISBN()` to call `/v1/search/isbn`
  - [ ] Update `advancedSearch()` to call `/v1/search/advanced`
  - [ ] Replace all manual parsing with `dtoMapper.mapToWork()`
- [ ] Remove legacy parsing code
  - [ ] Delete `parseSearchResults()` method
  - [ ] Delete any helper methods for manual JSON parsing
  - [ ] Remove `// TODO: Use DTOMapper` comment
- [ ] Add unit tests
  - [ ] Create `BookSearchAPIServiceTests.swift`
  - [ ] Test search uses DTOMapper
  - [ ] Test deduplication works
  - [ ] Test normalized genres appear correctly
- [ ] Run full test suite
  - [ ] Verify all existing tests pass
  - [ ] Run on real device (iPhone, iPad)
- [ ] Submit PR for review

### Phase 3: Documentation Updates

- [ ] Update `CLAUDE.md`
  - [ ] Mark genre normalization as implemented
  - [ ] Update implementation status section
- [ ] Update `docs/plans/2025-10-29-canonical-data-contracts-design.md`
  - [ ] Check off completed items in Implementation Checklist
  - [ ] Update status to "Implemented"
- [ ] Update `CHANGELOG.md`
  - [ ] Add entry for genre normalization
  - [ ] Add entry for DTOMapper integration

---

## Success Metrics

**How we'll know this implementation is successful:**

1. **Genre consistency** - All v1 endpoints return canonical subjectTags (no raw provider formats)
2. **Deduplication accuracy** - Searching same book twice creates 0 duplicates in SwiftData
3. **Code simplification** - Remove 100+ lines of manual parsing code from BookSearchAPIService
4. **Test coverage** - 100% coverage for GenreNormalizer, DTOMapper integration tests pass
5. **Zero regressions** - All existing tests pass, no user-reported issues

---

## Rollback Plan

**If issues discovered after deployment:**

**Backend Rollback:**
1. Revert genre-normalizer.ts changes
2. Restore original normalizer functions (pass-through genres)
3. Deploy to production (5 minutes)
4. Verify v1 endpoints return original genres (less consistent, but functional)

**iOS Rollback:**
1. Revert BookSearchAPIService changes
2. Restore manual parsing code
3. Submit expedited App Store update (24-48 hours)
4. Users continue using legacy endpoints temporarily

**Risk Mitigation:**
- Backend changes deployed first (iOS waits for stable backend)
- iOS changes reviewed thoroughly before merge
- Comprehensive test coverage reduces risk of bugs
- Real device testing before production deployment

---

## Future Enhancements

**Deferred to later phases:**

1. **Backend deduplication service** (Phase 3)
   - Merge WorkDTOs before sending to iOS
   - Reduces network payload for large searches
   - Consistent deduplication across all clients (if we add Android, web, etc.)

2. **V1 endpoints for enrichment/scan** (Not planned)
   - Internal APIs, no migration needed
   - Current response format sufficient for iOS integration

3. **CSV/bookshelf DTO integration** (Separate feature branch)
   - Refactor CSV import to use DTOMapper
   - Refactor bookshelf scanning to use DTOMapper
   - Consistent behavior across all import sources

4. **Genre taxonomy expansion** (Ongoing)
   - Add more provider-specific mappings as discovered
   - Community feedback on genre accuracy
   - AI-powered genre suggestion (use Gemini to suggest canonical tags)

---

## References

- [Parent Design Document](./2025-10-29-canonical-data-contracts-design.md)
- [DTOMapper Implementation](../../BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift)
- [Existing V1 Handlers](../../cloudflare-workers/api-worker/src/handlers/v1/)
- [Google Books API](https://developers.google.com/books/docs/v1/reference)
- [OpenLibrary Subjects](https://openlibrary.org/subjects)

---

## Change Log

| Version | Date       | Author        | Changes                          |
|---------|------------|---------------|----------------------------------|
| 1.0.0   | 2025-10-30 | BooksTrack    | Initial completion design        |
