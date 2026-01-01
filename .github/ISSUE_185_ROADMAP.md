# Issue #185 Implementation Roadmap
## Canonical Data Contracts Enhancement: OpenLibrary Integration + Genre Expansion

**Version:** 1.0
**Created:** 2026-01-01
**Status:** Planning Complete - Ready for Implementation

---

## Executive Summary

This roadmap orchestrates the implementation of Issue #185 across three repositories (books-v3, bendv3, alex) to transform BooksTrack from a single-provider system to a robust multi-provider architecture with:

1. **OpenLibrary Integration** - Native Work support, 40M+ books coverage
2. **110+ Genre Taxonomy** - From 30 generic genres to comprehensive subgenre system
3. **Provider Chain Orchestration** - Alexandria DB → ISBNdb → Google Books → OpenLibrary
4. **Conflict Resolution UI** - User-driven duplicate detection and merging

**Impact Metrics:**
- Metadata completeness: 60% → 85%
- Failed searches: 15% → 5%
- Genre specificity: 30 genres → 110+ with hierarchies
- Duplicate works: 5% → <1%

---

## Current Architecture Analysis

### Backend Structure (bendv3)

**DTO Contracts** (`bendv3/src/types/canonical.ts`):
```typescript
interface WorkDTO {
  title: string
  subjectTags: string[]              // Normalized genres
  synthetic: boolean                 // TRUE for inferred Works
  primaryProvider: DataProvider      // 'google-books' | 'openlibrary' | etc.
  contributors: DataProvider[]       // All providers that contributed
  openLibraryWorkID?: string
  googleBooksVolumeIDs: string[]
  // ... additional fields
}

interface EditionDTO {
  isbn?: string
  isbns: string[]
  format: EditionFormat              // 'Hardcover' | 'Paperback' | etc.
  primaryProvider: DataProvider
  // ... additional fields
}
```

**Current Provider Chain** (`alex/worker/services/external-apis.ts:resolveExternalISBN`):
1. Alexandria DB (local, 54M+ books)
2. ISBNdb (paid, most reliable)
3. Google Books (free, good coverage, **synthetic Works**)
4. OpenLibrary (free, **native Works** - needs enhancement!)

**Genre Normalizer** (`bendv3/src/services/genre-normalizer.ts`):
- 30 canonical genres
- Fuzzy matching with 85% threshold (Levenshtein)
- Provider-specific mappings (Google Books hierarchies)

### iOS Structure (books-v3)

**DTOMapper** (`BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`):
- Already handles canonical WorkDTO/EditionDTO
- **No changes needed for OpenLibrary** (backend-only enhancement)

**GenreTagView** (`BooksTrackerPackage/.../Components/GenreTagView.swift`):
- Displays genre tags
- Potential enhancement: Show parent → child hierarchy

---

## OpenLibrary API Analysis

### Key Insights

1. **OpenLibrary has NATIVE Works** (not synthetic like Google Books)
   - Higher quality work-level metadata
   - Should set `synthetic: false` in WorkDTO
   - Quality score: 50 vs Google's 40

2. **No Authentication Required** (but needs proper User-Agent)

3. **Rate Limiting:** ~1 req/sec soft limit (use 350ms delay)

4. **Multiple Endpoints:**
   - `/isbn/{isbn}.json` - Edition lookup
   - `/works/{olid}.json` - Work details
   - `/authors/{olid}.json` - Author info
   - `covers.openlibrary.org/b/id/{id}-L.jpg` - Cover images

### OpenLibrary Work Structure

```json
{
  "key": "/works/OL45804W",
  "title": "The Great Gatsby",
  "authors": [{"author": {"key": "/authors/OL123A"}}],
  "description": {"type": "/type/text", "value": "..."},
  "subjects": ["Fiction", "Jazz Age", "American literature"],
  "covers": [8376281],
  "first_publish_date": "1925"
}
```

**Critical Normalization Notes:**
- `description` can be string OR object (`{type, value}`)
- `first_publish_date` has multiple formats ("1949", "June 8, 1949")
- `subjects` includes places/people/times (need filtering)
- Cover IDs must be converted to URLs

---

## Genre Taxonomy Research (110 Genres)

### Breakdown by Category

**Speculative Fiction (39 genres):**
- Science Fiction: Cyberpunk, Solarpunk, Space Opera, Military SF, Hard SF, Dystopian, Post-Apocalyptic, Time Travel, Alternate History
- Fantasy: Epic, Urban, Dark, Cozy, Grimdark, Noblebright, Sword & Sorcery, Flintlock, Gaslamp
- GameLit/Progression: LitRPG, Progression Fantasy, Isekai, GameLit

**Mystery/Thriller (19 genres):**
- Mystery: Cozy, Police Procedural, Noir, Historical, Amateur Sleuth
- Thriller: Psychological, Legal, Medical, Techno, Spy, Domestic, Political

**Romance (23 genres):**
- Contemporary: Rom-Com, Small Town, Sports, Billionaire, Workplace
- Historical: Regency, Victorian, Western, Medieval
- Paranormal: Vampire, Shifter, Witch, Fae, Dragon
- LGBTQ+: M/M, F/F, Trans, Queer

**Non-Fiction (19 genres):**
- Biography, Memoir, Self-Help, Business, Science, History, True Crime, Cooking, Travel

**Horror (6 genres):**
- Gothic, Cosmic, Folk, Supernatural, Body, Psychological

**Literary Fiction (4 genres):**
- Magical Realism, Absurdist, Experimental, Satire

### Hierarchical Structure

```
Fantasy
  ├── Epic Fantasy
  ├── Urban Fantasy
  └── Progression Fantasy
        ├── LitRPG
        └── Cultivation Fantasy
```

**Hierarchy Resolution Strategy:** Leaf + 1 ancestor
- Display: "LitRPG" (most specific)
- Store: `["LitRPG", "Progression Fantasy", "Fantasy"]`
- Filter: Allow users to browse "All Fantasy" or narrow to "LitRPG"

---

## Implementation Plan

### Phase 1: OpenLibrary Client (alex worker)
**Duration:** 2-3 days
**Priority:** Critical (foundation for everything)

#### Files to Create/Modify

1. **`alex/worker/services/openlibrary-client.ts`** (NEW)
   ```typescript
   interface OpenLibraryClientConfig {
     userAgent: string
     requestDelayMs: number  // 350ms rate limiting
     maxRetries: number
     timeoutMs: number
   }

   class OpenLibraryClient {
     async getByISBN(isbn: string): Promise<OpenLibraryBook | null>
     async getWork(workKey: string): Promise<OpenLibraryWork | null>
     async search(query: string): Promise<OpenLibrarySearchResult[]>
     async getWorkEditions(workKey: string): Promise<OpenLibraryEdition[]>
   }
   ```

2. **`alex/worker/services/external-apis.ts`** (MODIFY)
   - Enhance `fetchFromOpenLibrary` to use new client
   - Add Work resolution: `GET /isbn/{isbn}` → extract Work key → `GET /works/{key}`
   - Build cover URLs from IDs

3. **`alex/worker/services/types.ts`** (MODIFY)
   - Add OpenLibrary type definitions
   - Add `OpenLibraryBook` interface

#### Key Decision Points

**Q1: Should we always fetch full Work data on ISBN lookups?**
- **Recommended:** YES (adds ~200ms latency but provides native Work quality)
- Alternative: Cache Work data in KV store

**Q2: Which cover size should we use?**
- **Recommended:** `-L` (large, 500x) for R2 processing and resizing

#### Implementation Steps

1. Create `OpenLibraryClient` class with User-Agent header
2. Implement rate limiting (350ms delay between requests)
3. Add Work resolution logic:
   ```typescript
   const edition = await GET(`/isbn/${isbn}.json`)
   const workKey = edition.works?.[0]?.key
   const work = await GET(`/works/${workKey}.json`)
   return { work, edition }
   ```
4. Build cover URL function:
   ```typescript
   function buildCoverURL(coverId: number): string {
     return `https://covers.openlibrary.org/b/id/${coverId}-L.jpg`
   }
   ```
5. Add error handling with retries
6. Write unit tests

---

### Phase 2: OpenLibrary Normalizer (bendv3)
**Duration:** 2 days
**Priority:** Critical (depends on Phase 1)

#### Files to Create/Modify

1. **`bendv3/src/services/normalizers/openlibrary.ts`** (NEW)
   ```typescript
   export function normalizeOpenLibraryToWork(
     work: OpenLibraryWork,
     edition?: OpenLibraryEdition
   ): WorkDTO {
     return {
       title: work.title,
       subjectTags: genreNormalizer.normalize(work.subjects || [], 'openlibrary'),
       synthetic: false,  // KEY: OpenLibrary has native Works!
       primaryProvider: 'openlibrary',
       contributors: ['openlibrary'],
       openLibraryWorkID: work.key,
       firstPublicationYear: parseOpenLibraryDate(work.first_publish_date),
       coverImageURL: buildCoverURL(work.covers?.[0] || edition?.covers?.[0]),
       description: extractDescription(work.description),
       isbndbQuality: calculateOpenLibraryQuality(work),
       reviewStatus: 'verified',
       // ... additional fields
     }
   }

   export function normalizeOpenLibraryToEdition(edition: OpenLibraryEdition): EditionDTO
   ```

2. **`bendv3/src/services/genre-normalizer.ts`** (MODIFY)
   - Add OpenLibrary-specific mappings to `PROVIDER_MAPPINGS`
   - Handle verbose subjects: "Detective and mystery stories" → "Mystery"

3. **`bendv3/tests/normalizers/openlibrary.test.ts`** (NEW)
   - Test Work normalization
   - Test Edition normalization
   - Test description extraction (string vs object)
   - Test date parsing variations

#### Critical Normalization Patterns

**Description Extraction:**
```typescript
function extractDescription(desc: string | OpenLibraryTextValue | undefined): string | undefined {
  if (!desc) return undefined
  if (typeof desc === 'string') return desc
  if (desc.type === '/type/text') return desc.value
  return undefined
}
```

**Date Parsing:**
```typescript
function parseOpenLibraryDate(date: string | undefined): number | undefined {
  if (!date) return undefined
  // Handles "1949", "June 8, 1949", "1949-06-08"
  const yearMatch = date.match(/\d{4}/)
  return yearMatch ? parseInt(yearMatch[0]) : undefined
}
```

**Format Mapping:**
```typescript
function mapPhysicalFormat(format: string | undefined): EditionFormat {
  const normalized = format?.toLowerCase() || ''
  if (normalized.includes('hardcover')) return 'Hardcover'
  if (normalized.includes('paperback')) return 'Paperback'
  if (normalized.includes('ebook') || normalized.includes('kindle')) return 'E-book'
  if (normalized.includes('audio')) return 'Audiobook'
  return 'Other'
}
```

---

### Phase 3: Genre Expansion to 110+ (bendv3)
**Duration:** 3-4 days
**Priority:** High (can be done in parallel with Phases 1-2)

#### Files to Create

1. **`bendv3/src/data/genres/canonical-genres.json`** (NEW)
   ```json
   {
     "version": "1.0",
     "genres": {
       "Science Fiction": {
         "aliases": ["Sci-Fi", "SF", "Scifi"],
         "parent": null,
         "children": ["Cyberpunk", "Space Opera", "Dystopian"],
         "description": "Fiction based on scientific speculation"
       },
       "LitRPG": {
         "aliases": ["Lit-RPG", "GameLit"],
         "parent": "Progression Fantasy",
         "children": [],
         "description": "Fiction with explicit game mechanics"
       }
     }
   }
   ```

2. **`bendv3/src/data/genres/hierarchy.json`** (NEW)
   ```json
   {
     "Fantasy": ["Epic Fantasy", "Urban Fantasy", "Progression Fantasy"],
     "Progression Fantasy": ["LitRPG", "Cultivation Fantasy"]
   }
   ```

3. **`bendv3/src/data/genres/provider-mappings/openlibrary.json`** (NEW)
   ```json
   {
     "Science fiction": ["Science Fiction"],
     "Detective and mystery stories": ["Mystery"],
     "Dystopian fiction": ["Dystopian", "Science Fiction"],
     "Imaginary places": ["Fantasy"],
     "Reading Level-Grade": []
   }
   ```

#### Files to Modify

1. **`bendv3/src/services/genre-normalizer.ts`** (REFACTOR)
   - Load JSON files instead of inline objects
   - Add hierarchy resolution
   - Enhance fuzzy matching with alias index

#### Implementation Steps

1. Extract current 30 genres to `canonical-genres.json`
2. Add 80+ new genres from research (110 total)
3. Create hierarchy relationships
4. Build provider mappings for OpenLibrary
5. Refactor `GenreNormalizer` to use JSON files:
   ```typescript
   class EnhancedGenreNormalizer {
     private genreData: CanonicalGenres
     private hierarchies: GenreHierarchy
     private providerMappings: Record<DataProvider, ProviderMapping>

     constructor() {
       this.genreData = loadJSON('canonical-genres.json')
       this.hierarchies = loadJSON('hierarchy.json')
       this.providerMappings = loadProviderMappings()
     }

     normalize(rawGenres: string[], provider: DataProvider): string[] {
       // 1. Exact match
       // 2. Provider mapping
       // 3. Fuzzy match
       // 4. Resolve hierarchy
     }
   }
   ```
6. Add hierarchy resolution (leaf + 1 ancestor)
7. Write comprehensive tests

---

### Phase 4: Provider Chain Enhancement (alex worker)
**Duration:** 2 days
**Priority:** Medium (quality of life improvements)

#### Files to Modify

1. **`alex/worker/services/external-apis.ts`**
   - Add structured error classification
   - Add response time tracking
   - Implement `shouldFallback` logic

#### Error Classification System

```typescript
enum ProviderError {
  // Trigger Fallback
  NOT_FOUND = 'not_found',
  RATE_LIMITED = 'rate_limited',
  TIMEOUT = 'timeout',
  SERVER_ERROR = 'server_error',

  // Abort Immediately
  INVALID_ISBN = 'invalid_isbn',
  AUTH_ERROR = 'auth_error',
  QUOTA_EXHAUSTED = 'quota_exhausted',
}

interface ProviderResult<T> {
  success: boolean
  data?: T
  error?: ProviderError
  provider: DataProvider
  responseTimeMs: number
}

function shouldFallback(error: ProviderError): boolean {
  return [
    ProviderError.NOT_FOUND,
    ProviderError.RATE_LIMITED,
    ProviderError.TIMEOUT,
    ProviderError.SERVER_ERROR,
  ].includes(error)
}
```

#### Enhanced Provider Chain

```typescript
export async function resolveExternalISBNEnhanced(
  isbn: string,
  env: Env
): Promise<ProviderResult<ExternalBookData>> {
  const results: ProviderResult<any>[] = []

  // 1. ISBNdb
  const isbndbResult = await tryProvider('isbndb', () => fetchFromISBNdb(isbn, env))
  results.push(isbndbResult)
  if (isbndbResult.success) return isbndbResult

  // 2. Google Books (if ISBNdb failed with fallback-eligible error)
  if (shouldFallback(isbndbResult.error!)) {
    const googleResult = await tryProvider('google-books', () => fetchFromGoogleBooks(isbn, env))
    results.push(googleResult)
    if (googleResult.success) return googleResult
  }

  // 3. OpenLibrary (if Google Books failed)
  if (shouldFallback(results[results.length - 1].error!)) {
    const olResult = await tryProvider('openlibrary', () => fetchFromOpenLibraryEnhanced(isbn, env))
    results.push(olResult)
    if (olResult.success) return olResult
  }

  // All providers failed - log analytics
  await logProviderChainFailure(isbn, results, env)
  return results[results.length - 1]  // Return last error
}

async function tryProvider<T>(
  provider: DataProvider,
  fn: () => Promise<T | null>
): Promise<ProviderResult<T>> {
  const startTime = Date.now()
  try {
    const data = await fn()
    return {
      success: !!data,
      data: data || undefined,
      error: data ? undefined : ProviderError.NOT_FOUND,
      provider,
      responseTimeMs: Date.now() - startTime,
    }
  } catch (error) {
    return {
      success: false,
      error: classifyError(error),
      provider,
      responseTimeMs: Date.now() - startTime,
    }
  }
}
```

---

### Phase 5: Conflict Resolution UI (books-v3)
**Duration:** 3-4 days
**Priority:** Medium (user-facing polish)

#### Overview

When users add books, detect potential duplicates and provide a merge interface.

#### Files to Create

1. **`BooksTrackerPackage/Sources/BooksTrackerFeature/Views/MergeWorksSheet.swift`** (NEW)
   ```swift
   struct MergeWorksSheet: View {
       let conflict: DuplicateConflict
       @State private var selectedWork: Work
       @Environment(\.modelContext) private var modelContext

       var body: some View {
           VStack {
               Text("Possible duplicate detected")
                   .font(.headline)

               ForEach(conflict.works) { work in
                   WorkComparisonCard(work: work, isSelected: selectedWork == work)
                       .onTapGesture { selectedWork = work }
               }

               Button("Merge Books") {
                   mergeWorks(primary: selectedWork, duplicates: conflict.works)
               }
           }
       }
   }
   ```

2. **`BooksTrackerPackage/Sources/BooksTrackerFeature/Components/WorkComparisonCard.swift`** (NEW)
   ```swift
   struct WorkComparisonCard: View {
       let work: Work
       let isSelected: Bool

       var body: some View {
           VStack(alignment: .leading, spacing: 8) {
               HStack {
                   Text(work.title).font(.headline)
                   if work.coverImageURL != nil {
                       Image(systemName: "checkmark.circle.fill")
                           .foregroundColor(.green)
                   }
               }

               Text("Provider: \(work.primaryProvider ?? "Unknown")")
               Text("Editions: \(work.editions.count)")

               if let genres = work.subjectTags, !genres.isEmpty {
                   Text("Genres: \(genres.joined(separator: ", "))")
                       .font(.caption)
               }
           }
           .padding()
           .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
           .cornerRadius(8)
       }
   }
   ```

#### Files to Modify

1. **`BooksTrackerPackage/Sources/BooksTrackerFeature/ViewModels/SearchModel.swift`**
   - Add duplicate detection after adding book
   - Show warning in UI

#### Duplicate Detection Logic

```swift
func detectDuplicates(for work: Work, in context: ModelContext) -> [Work] {
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate<Work> { existingWork in
            existingWork.id != work.id  // Exclude self
        }
    )

    guard let allWorks = try? context.fetch(descriptor) else { return [] }

    return allWorks.filter { existing in
        stringSimilarity(work.title, existing.title) >= 0.85  // 85% match
    }
}

func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    // Levenshtein distance implementation
    let s1Lower = s1.lowercased()
    let s2Lower = s2.lowercased()

    let distance = levenshteinDistance(s1Lower, s2Lower)
    let maxLength = max(s1Lower.count, s2Lower.count)
    return 1.0 - (Double(distance) / Double(maxLength))
}
```

#### Merge Logic

```swift
func mergeWorks(primary: Work, duplicates: [Work]) {
    for duplicate in duplicates where duplicate.id != primary.id {
        // Merge editions
        primary.editions.append(contentsOf: duplicate.editions)

        // Merge genres (union)
        let combinedGenres = Set(primary.subjectTags ?? [])
            .union(Set(duplicate.subjectTags ?? []))
        primary.subjectTags = Array(combinedGenres)

        // Delete duplicate
        modelContext.delete(duplicate)
    }

    try? modelContext.save()
}
```

---

### Phase 6: Testing & Quality Assurance
**Duration:** 2-3 days
**Priority:** Critical (zero warnings policy)

#### Test Coverage Requirements

1. **OpenLibrary Client Tests**
   - ISBN lookup with Work resolution
   - Rate limiting enforcement
   - Error handling (timeout, 404, server errors)
   - Cover URL building

2. **Normalizer Tests**
   - Work normalization (native Work data)
   - Edition normalization
   - Description extraction (string vs object)
   - Date parsing (various formats)
   - Format mapping

3. **Genre Normalizer Tests**
   - Exact matches
   - Provider mappings
   - Fuzzy matching with 110+ genres
   - Hierarchy resolution

4. **Provider Chain Tests**
   - Fallback triggers (NOT_FOUND, RATE_LIMITED)
   - No fallback (INVALID_ISBN, AUTH_ERROR)
   - Response time tracking
   - Analytics logging

5. **Conflict Resolution Tests**
   - Duplicate detection accuracy
   - Merge preserves all editions
   - Genre union works correctly

#### SwiftLint Compliance

All code must pass with zero warnings (`-Werror` enforced):
- Swift 6 concurrency compliance
- `@MainActor` for all Observable classes
- `@Bindable` for SwiftData models in child views
- No Timer.publish in actors

---

## Key Decision Points Summary

| Decision | Recommendation | Rationale |
|----------|----------------|-----------|
| **OpenLibrary Work fetching** | Always fetch for ISBN lookups | Native Work data is higher quality (+10 quality score) |
| **Rate limiting** | 350ms delay between requests | OpenLibrary soft limits at ~1 req/sec |
| **Cover size** | `-L` (large, 500x) | Best quality for R2 resizing |
| **Genre hierarchy depth** | Leaf + 1 ancestor | Balances specificity with discoverability |
| **Error retry policy** | 3 retries, exponential backoff | Match existing ISBNdb/Google patterns |
| **Quality score** | OpenLibrary: 50, Google: 40 | Native Works justify higher score |
| **Conflict detection threshold** | 85% string similarity | Matches existing fuzzy match threshold |

---

## Risk Assessment & Mitigation

### Risk 1: OpenLibrary Rate Limiting
**Likelihood:** Medium
**Impact:** High (blocks fallback chain)
**Mitigation:**
- Implement KV caching for all OpenLibrary responses (TTL: 14 days)
- Add circuit breaker pattern (already exists)
- Use 350ms delay between requests

### Risk 2: Genre Explosion (110+ genres)
**Likelihood:** Low
**Impact:** Medium (UI clutter)
**Mitigation:**
- Use hierarchy to group related genres
- Only show leaf + 1 ancestor in UI
- Allow users to collapse/expand genre families

### Risk 3: Duplicate Detection False Positives
**Likelihood:** Medium
**Impact:** Low (user can dismiss)
**Mitigation:**
- Set threshold at 85% (matches genre normalizer)
- Show non-blocking warning (not modal)
- Allow user to dismiss or merge

### Risk 4: iOS UI Complexity for Conflict Resolution
**Likelihood:** Low
**Impact:** Medium (dev time)
**Mitigation:**
- Start with simple merge sheet
- Iterate based on user feedback
- Phase 5 is medium priority (can delay if needed)

---

## Success Metrics

### Quantitative Metrics

1. **Metadata Completeness**
   - Before: 60% (Google Books only)
   - After: 85% (Google + OpenLibrary)
   - Measurement: % of ISBNs with cover + description + genres

2. **Search Success Rate**
   - Before: 85% (15% fail rate)
   - After: 95% (5% fail rate)
   - Measurement: % of ISBN searches returning results

3. **Genre Specificity**
   - Before: 30 canonical genres
   - After: 110+ canonical genres with hierarchies
   - Measurement: Average genres per book (should increase)

4. **Duplicate Rate**
   - Before: 5% of library
   - After: <1% (user can merge)
   - Measurement: % of works with duplicate titles

### Qualitative Metrics

1. **User Satisfaction** - Fewer "book not found" errors
2. **Genre Accuracy** - More specific genres (LitRPG vs generic Fantasy)
3. **Data Quality** - OpenLibrary's native Works improve metadata
4. **Developer Experience** - Structured error handling, better debugging

---

## Timeline & Resource Allocation

**Total Duration:** 10-14 days (2 weeks)

**Week 1:**
- Days 1-3: Phase 1 (OpenLibrary Client)
- Days 2-4: Phase 2 (Normalizer) - parallel with Phase 3
- Days 2-5: Phase 3 (Genre Expansion) - parallel with Phases 1-2

**Week 2:**
- Days 6-7: Phase 4 (Provider Chain Enhancement)
- Days 8-10: Phase 5 (Conflict Resolution UI)
- Days 11-12: Phase 6 (Testing & QA)
- Days 13-14: Buffer for bug fixes

**Critical Path:**
Phase 1 → Phase 2 → Phase 6 (OpenLibrary integration is foundation)

**Parallel Work:**
Phase 3 (Genre Expansion) can be done independently

---

## Cross-Repository Coordination

### Repository Ownership

| Feature | Repository | Owner |
|---------|------------|-------|
| OpenLibrary Client | alex | Backend Team |
| OpenLibrary Normalizer | bendv3 | Backend Team |
| Genre Expansion | bendv3 | Backend Team |
| Provider Chain | alex | Backend Team |
| Conflict Resolution UI | books-v3 | iOS Team |

### Integration Points

1. **bendv3 → alex:** Genre normalizer is consumed by alex worker
2. **alex → books-v3:** Enhanced WorkDTO with OpenLibrary data flows to iOS
3. **books-v3:** DTOMapper already handles canonical format (no changes needed)

### Communication Plan

- Daily standups during Weeks 1-2
- Share test ISBNs for cross-validation
- Backend completes Phases 1-4 before iOS starts Phase 5

---

## Appendix: File Inventory

### Files to Create (7 files)

#### Backend (6 files)
1. `alex/worker/services/openlibrary-client.ts` - OpenLibrary API client
2. `bendv3/src/services/normalizers/openlibrary.ts` - OpenLibrary normalizer
3. `bendv3/src/data/genres/canonical-genres.json` - 110 genre definitions
4. `bendv3/src/data/genres/hierarchy.json` - Parent-child relationships
5. `bendv3/src/data/genres/provider-mappings/openlibrary.json` - OpenLibrary mappings
6. `bendv3/tests/normalizers/openlibrary.test.ts` - Normalizer tests

#### iOS (1 file)
7. `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/MergeWorksSheet.swift` - Merge UI

### Files to Modify (6 files)

#### Backend (4 files)
1. `alex/worker/services/external-apis.ts` - Enhanced provider chain
2. `alex/worker/services/types.ts` - OpenLibrary types
3. `bendv3/src/services/genre-normalizer.ts` - Load JSON, add hierarchy
4. `bendv3/src/services/normalizers/google-books.ts` - Reference pattern

#### iOS (2 files)
5. `BooksTrackerPackage/Sources/BooksTrackerFeature/ViewModels/SearchModel.swift` - Duplicate detection
6. `BooksTrackerPackage/Sources/BooksTrackerFeature/Components/GenreTagView.swift` - Optional hierarchy display

### Files to Reference (Read-Only, 4 files)

1. `bendv3/src/types/canonical.ts` - DTO contracts
2. `bendv3/src/utils/string-similarity.ts` - Fuzzy matching
3. `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift` - iOS DTO mapper
4. `bendv3/docs/SYSTEM_ARCHITECTURE.md` - Cross-repo architecture

---

## Next Steps

1. **Review this roadmap** with stakeholders
2. **Assign ownership** for each phase
3. **Create feature branch:** `feature/issue-185-canonical-data-contracts`
4. **Start with Phase 1** (OpenLibrary Client) - foundation for everything
5. **Set up CI/CD** for bendv3 tests (genre normalizer)
6. **Track progress** using GitHub Project board

---

**Document Version:** 1.0
**Last Updated:** 2026-01-01
**Next Review:** After Phase 1 completion
