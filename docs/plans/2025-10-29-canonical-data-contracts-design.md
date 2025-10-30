# Canonical Data Contracts Design

**Date:** October 29, 2025
**Version:** 1.0.0
**Status:** Design Approved
**Author:** BooksTrack Team

## Executive Summary

This document defines the **canonical data structure** for BooksTrack's backend API contracts. It establishes TypeScript-first DTOs (Data Transfer Objects) as the single source of truth for all API responses, ensuring consistency across Google Books, OpenLibrary, ISBNDB, Gemini, and other data providers.

**Key Goals:**
1. **Eliminate response inconsistencies** - Unify mixed JSON shapes across endpoints
2. **TypeScript-first contracts** - Backend defines canonical types, iOS mirrors with Swift Codable
3. **Handle edge cases** - Edition-without-Work, multi-provider IDs, genre normalization
4. **Enable evolution** - Extensible design for future fields (author bio, relationships)

**Scope:**
- ✅ Core entity DTOs (Work, Edition, Author)
- ✅ External ID management strategy
- ✅ API response envelope structure
- ⏳ Genre normalization (implementation deferred to Phase 2)
- ⏳ Relationship embedding (deferred to v2.0.0)

---

## Design Philosophy

### Follow OpenLibrary's Work/Edition Model

**Work** = Abstract creative work (e.g., "1984" by George Orwell)
**Edition** = Physical/digital manifestation (e.g., "1984, Penguin Classics 2021, Hardcover")

This separation is critical because:
- Users track **Works** (avoiding "I have 3 copies of 1984" clutter)
- Editions carry format-specific data (ISBN, cover, page count)
- Multiple providers describe same Work differently → deduplication needed

### TypeScript-First Contract Approach

**Single Source of Truth:** `cloudflare-workers/api-worker/src/types/canonical.ts`

**Backend responsibilities:**
- Define TypeScript interfaces for WorkDTO, EditionDTO, AuthorDTO
- Normalizers transform provider responses → canonical DTOs
- All endpoints return canonical shapes (no more raw Google Books `volumeInfo`)

**iOS responsibilities:**
- Swift Codable structs mirror TypeScript DTOs **exactly** (field names, types)
- SwiftData models consume DTOs and map to persistent entities
- iOS handles deduplication, relationship resolution, local enrichment

**Migration path:**
- Phase 1: Create `/v1/*` endpoints with canonical contracts
- Phase 2: Migrate iOS to `/v1/*` (dual-support old endpoints during transition)
- Phase 3: Deprecate legacy endpoints after 3 months

---

## Core Entity Contracts

### TypeScript Enums

Match Swift enums **exactly** (including string rawValues):

```typescript
export type EditionFormat =
  | 'Hardcover' | 'Paperback' | 'E-book' | 'Audiobook' | 'Mass Market';

export type AuthorGender =
  | 'Female' | 'Male' | 'Non-binary' | 'Other' | 'Unknown';

export type CulturalRegion =
  | 'Africa' | 'Asia' | 'Europe' | 'North America' | 'South America'
  | 'Oceania' | 'Middle East' | 'Caribbean' | 'Central Asia'
  | 'Indigenous' | 'International';

export type ReviewStatus =
  | 'verified' | 'needsReview' | 'userEdited';
```

### WorkDTO

```typescript
export interface WorkDTO {
  // Required fields
  title: string;
  subjectTags: string[]; // Normalized genres (see Genre Normalization section)

  // Optional metadata
  originalLanguage?: string;
  firstPublicationYear?: number;
  description?: string;

  // Provenance (NEW fields for edge case handling)
  synthetic?: boolean;        // True if Work was inferred from Edition data
  primaryProvider?: string;   // 'openlibrary' | 'google' | 'isbndb' | 'gemini'
  contributors?: string[];    // All providers that enriched this Work

  // External IDs - Legacy (single values, kept for backward compatibility)
  openLibraryID?: string;
  openLibraryWorkID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;
  goodreadsID?: string;

  // External IDs - Modern (arrays for multi-provider support)
  goodreadsWorkIDs: string[];      // ["1234567", "7654321"]
  amazonASINs: string[];           // ["B08N5WRWNW", "0451524934"]
  librarythingIDs: string[];       // ["12345"]
  googleBooksVolumeIDs: string[];  // ["beSP5CCpiGUC", "anotherVolumeId"]

  // Quality metrics
  lastISBNDBSync?: string;  // ISO 8601 timestamp
  isbndbQuality: number;    // 0-100

  // Review metadata (for AI-detected books from bookshelf scanning)
  reviewStatus: ReviewStatus;
  originalImagePath?: string;
  boundingBox?: { x: number; y: number; width: number; height: number; };
}
```

**Design Notes:**
- **Field name matching:** `firstPublicationYear`, `subjectTags`, `isbndbQuality` identical to Swift models
- **Date representation:** ISO 8601 strings (not `Date` objects) for JSON serialization
- **Bounding box:** Decomposed to `{x, y, width, height}` object (cleaner than 4 separate fields)
- **Omissions:** No `dateCreated`, `lastModified`, `works`, `editions` (iOS-specific SwiftData fields)

### EditionDTO

```typescript
export interface EditionDTO {
  // Identifiers (at least ONE required: isbn OR title+publisher+year)
  isbn?: string;      // Primary ISBN
  isbns: string[];    // All ISBNs (ISBN-10, ISBN-13, etc.)

  // Core metadata
  title?: string;             // May differ from Work title
  publisher?: string;
  publicationDate?: string;   // YYYY-MM-DD or YYYY format
  pageCount?: number;
  format: EditionFormat;
  coverImageURL?: string;
  editionTitle?: string;      // "Deluxe Edition", "Abridged", etc.
  description?: string;       // Edition-specific description
  language?: string;          // Edition language (may differ from Work)

  // Provenance
  primaryProvider?: string;
  contributors?: string[];

  // External IDs - Legacy
  openLibraryID?: string;
  openLibraryEditionID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;
  goodreadsID?: string;

  // External IDs - Modern
  amazonASINs: string[];
  googleBooksVolumeIDs: string[];
  librarythingIDs: string[];

  // Quality metrics
  lastISBNDBSync?: string;
  isbndbQuality: number;
}
```

**Design Notes:**
- **Edition title vs Work title:** Edition may have subtitle/special edition name
- **Language field:** Edition language can differ from Work's `originalLanguage`
- **Multiple ISBNs:** `isbns[]` array handles ISBN-10, ISBN-13, alternate ISBNs

### AuthorDTO

```typescript
export interface AuthorDTO {
  // Required
  name: string;
  gender: AuthorGender;

  // Diversity analytics (high priority for BooksTrack)
  culturalRegion?: CulturalRegion;
  nationality?: string;
  birthYear?: number;
  deathYear?: number;

  // External IDs
  openLibraryID?: string;
  isbndbID?: string;
  googleBooksID?: string;
  goodreadsID?: string;

  // Statistics
  bookCount?: number;

  // FUTURE (v2.0.0): Author biography and media
  // bio?: string;
  // photoURL?: string;
  // website?: string;
  // socialLinks?: { platform: string; url: string; }[];
}
```

**Design Notes:**
- **Current focus:** Diversity analytics only (gender, region, nationality)
- **Extensibility:** Author bio/photo commented out with `// FUTURE` tag
- **No breaking changes:** Can add bio later without changing existing iOS parsing

---

## API Response Envelope

### Standard Structure

**ALL endpoints** must use this envelope for consistency:

```typescript
export interface ResponseMeta {
  timestamp: string;        // ISO 8601
  processingTime?: number;  // milliseconds
  provider?: string;        // 'google-books' | 'openlibrary' | 'isbndb' | 'gemini'
  cached?: boolean;         // Was response served from cache?
  cacheAge?: number;        // Seconds since cached (if cached: true)
  requestId?: string;       // For distributed tracing (future)
}

export interface SuccessResponse<T> {
  success: true;
  data: T;
  meta: ResponseMeta;
}

export interface ErrorResponse {
  success: false;
  error: {
    message: string;
    code?: string;    // 'INVALID_ISBN' | 'PROVIDER_TIMEOUT' | 'NOT_FOUND'
    details?: any;    // Additional context for debugging
  };
  meta: ResponseMeta;
}

export type ApiResponse<T> = SuccessResponse<T> | ErrorResponse;
```

### Domain-Specific Response Types

```typescript
export interface BookSearchResponse {
  works: WorkDTO[];
  authors: AuthorDTO[];
  totalResults?: number;  // For pagination (future)
}

export interface EnrichmentJobResponse {
  jobId: string;
  queuedCount: number;
  estimatedDuration?: number;  // seconds
  websocketUrl: string;
}

export interface BookshelfScanResponse {
  jobId: string;
  detectedBooks: {
    work: WorkDTO;
    edition: EditionDTO;
    confidence: number;  // 0.0-1.0
  }[];
  websocketUrl: string;
}
```

### Usage Examples

**Example 1: GET /v1/search/title?q=1984**

```json
{
  "success": true,
  "data": {
    "works": [
      {
        "title": "1984",
        "subjectTags": ["Dystopian", "Science Fiction", "Classics"],
        "firstPublicationYear": 1949,
        "openLibraryWorkID": "OL45804W",
        "goodreadsWorkIDs": ["5470", "40961427"],
        "isbndbQuality": 95,
        "reviewStatus": "verified"
      }
    ],
    "authors": [
      {
        "name": "George Orwell",
        "gender": "Male",
        "culturalRegion": "Europe",
        "birthYear": 1903,
        "deathYear": 1950
      }
    ]
  },
  "meta": {
    "timestamp": "2025-10-29T12:00:00Z",
    "processingTime": 234,
    "provider": "google-books",
    "cached": false
  }
}
```

**Example 2: POST /v1/api/enrichment/start**

```json
{
  "success": true,
  "data": {
    "jobId": "abc-123-def-456",
    "queuedCount": 25,
    "estimatedDuration": 60,
    "websocketUrl": "wss://api-worker.jukasdrj.workers.dev/ws/progress?jobId=abc-123-def-456"
  },
  "meta": {
    "timestamp": "2025-10-29T12:00:00Z",
    "processingTime": 12
  }
}
```

**Example 3: Error Response**

```json
{
  "success": false,
  "error": {
    "message": "Invalid ISBN format",
    "code": "INVALID_ISBN",
    "details": {
      "provided": "123",
      "expected": "10 or 13 digits"
    }
  },
  "meta": {
    "timestamp": "2025-10-29T12:00:00Z",
    "processingTime": 5
  }
}
```

---

## Edge Case Handling

### Rule 1: Never Return Orphaned Editions

**Problem:** ISBN lookup from Google Books returns Edition data only (no Work).

**Backend behavior:**
1. Check if Edition has associated Work in provider response
2. If missing, synthesize Work from Edition metadata:
   ```typescript
   function ensureWorkForEdition(edition: EditionDTO, provider: string): WorkDTO {
     return {
       title: edition.title || 'Unknown',
       subjectTags: [], // Will be populated by genre normalizer
       firstPublicationYear: extractYearFromDate(edition.publicationDate),
       synthetic: true,
       primaryProvider: provider,
       goodreadsWorkIDs: [],
       amazonASINs: [],
       librarythingIDs: [],
       googleBooksVolumeIDs: edition.googleBooksVolumeIDs || [],
       isbndbQuality: edition.isbndbQuality || 0,
       reviewStatus: 'verified',
     };
   }
   ```
3. iOS deduplication will merge if same Work found later from another provider

**Indicator:** `synthetic: true` flag tells iOS this Work was inferred, not canonical.

### Rule 2: Multi-Provider ID Deduplication

**Problem:** Same Work/Edition can have IDs from multiple providers:
- OpenLibrary: "OL45804W"
- Google Books: "beSP5CCpiGUC"
- Goodreads: "5470", "40961427" (multiple IDs!)

**Backend Deduplication Strategy:**

**WHEN TO MERGE:**
1. **Exact ID match** on ANY external ID field
   - If `openLibraryWorkID` matches, it's the same Work
2. **Fuzzy title+author match** (90%+ similarity)
   - Use string distance (Levenshtein) on normalized strings
   - Normalize: lowercase, remove punctuation, trim whitespace

**HOW TO MERGE:**
```typescript
function mergeWorks(work1: WorkDTO, work2: WorkDTO): WorkDTO {
  return {
    ...work1,
    title: work1.title || work2.title,
    firstPublicationYear: work1.firstPublicationYear ?? work2.firstPublicationYear,

    // Merge ID arrays (union, deduplicate)
    goodreadsWorkIDs: [...new Set([
      ...work1.goodreadsWorkIDs,
      ...work2.goodreadsWorkIDs
    ])],
    amazonASINs: [...new Set([...work1.amazonASINs, ...work2.amazonASINs])],
    googleBooksVolumeIDs: [...new Set([...work1.googleBooksVolumeIDs, ...work2.googleBooksVolumeIDs])],

    // Quality: prefer higher score
    isbndbQuality: Math.max(work1.isbndbQuality, work2.isbndbQuality),

    // Provenance: merge contributors
    contributors: [...new Set([
      ...(work1.contributors || []),
      ...(work2.contributors || [])
    ])]
  };
}
```

**iOS Deduplication Strategy:**

When iOS receives multiple Works from different searches:
1. Query SwiftData for existing Work with matching external IDs
2. If found, merge new IDs into existing Work
3. If not found, check for fuzzy title+author match (Levenshtein distance)
4. If still not found, insert as new Work

SwiftData predicate example:
```swift
let predicate = #Predicate<Work> { work in
  work.openLibraryWorkID == newWork.openLibraryWorkID ||
  work.goodreadsWorkIDs.contains(where: { newWork.goodreadsWorkIDs.contains($0) }) ||
  work.googleBooksVolumeIDs.contains(where: { newWork.googleBooksVolumeIDs.contains($0) })
}
```

### Rule 3: Genre Normalization (Backend Responsibility)

**Problem:** Each provider uses different genre taxonomies:
- Google Books: `"Fiction / Science Fiction / General"`
- OpenLibrary: `["Science Fiction", "Dystopian", "Classic Literature"]`
- ISBNDB: `"Science Fiction & Fantasy"`
- Gemini: Free-form AI-generated genres (inconsistent)

**Solution:** Backend normalizes to canonical `subjectTags[]` before returning WorkDTO.

**Implementation approach (deferred to Phase 2):**

1. Create `src/services/genre-normalizer.ts` service
2. Maintain mapping of provider-specific → canonical genres:
   ```typescript
   const GENRE_MAPPINGS = {
     'Fiction / Science Fiction / General': ['Science Fiction'],
     'Science Fiction & Fantasy': ['Science Fiction', 'Fantasy'],
     'Dystopian fiction': ['Dystopian', 'Science Fiction'],
     // ... 100+ mappings
   };
   ```
3. Use fuzzy string matching (Levenshtein distance) for unmapped genres
4. Return array of canonical tags: `["Science Fiction", "Dystopian", "Classics"]`

**Canonical genre taxonomy (subset):**
- Fiction, Science Fiction, Fantasy, Mystery, Thriller, Romance, Horror
- Non-Fiction, Biography, History, Science, Philosophy, Self-Help
- Classics, Contemporary, Young Adult, Children's

**Not part of canonical DTOs** - genre normalization is a backend service concern that **produces** the `subjectTags` array. The DTO contract only specifies that `subjectTags` is a `string[]`.

---

## Migration Strategy

### Current State Audit

**Inconsistent response shapes:**
- ✅ `/search/title` returns: `{ success, provider, works, authors }`
- ✅ `/search/isbn` returns: `{ success, provider, works, authors }`
- ❌ `/search/advanced` returns: `{ success, provider, items }` (Google Books `volumeInfo` format)
- ❌ `/api/enrichment/start` returns: `{ jobId, queuedCount }` (no envelope)
- ❌ `/api/scan-bookshelf` returns: `{ jobId, detectedBooks }` (no envelope)

### Phase 1: Create Canonical Endpoints

**New `/v1/` prefix for canonical contracts:**
- `GET /v1/search/title` → Returns `SuccessResponse<BookSearchResponse>`
- `GET /v1/search/isbn` → Returns `SuccessResponse<BookSearchResponse>`
- `GET /v1/search/advanced` → Returns `SuccessResponse<BookSearchResponse>`
- `POST /v1/api/enrichment/start` → Returns `SuccessResponse<EnrichmentJobResponse>`
- `POST /v1/api/scan-bookshelf` → Returns `SuccessResponse<BookshelfScanResponse>`

**Implementation steps:**
1. Create `src/types/canonical.ts` with all DTOs
2. Create `src/services/canonical-normalizers.ts` (transforms provider responses → DTOs)
3. Implement `/v1/*` endpoints using canonical normalizers
4. Add Zod schemas for runtime validation (optional but recommended)
5. Generate TypeScript documentation with TSDoc comments

**Timeline:** 2-3 days (backend only)

### Phase 2: iOS Migration

**Dual-support period (3 months):**
- iOS app supports both legacy and `/v1/` endpoints
- Feature flag: `useCanonicalAPI` (default: false, gradually roll out to users)
- Monitor error rates, rollback if issues

**Implementation steps:**
1. Create Swift Codable DTOs mirroring TypeScript contracts (exact field names)
2. Add `APIVersion` enum: `.legacy`, `.v1`
3. Implement canonical DTO → SwiftData model mapping
4. Test deduplication logic with unit tests
5. Roll out to 10% of users, monitor for 1 week
6. Gradually increase to 100% over 2 months

**Timeline:** 1-2 weeks (iOS development + testing)

### Phase 3: Deprecation

**After 3 months of stable `/v1/` usage:**
- Add deprecation warnings to legacy endpoints (response header: `X-Deprecated: true`)
- Update iOS to exclusively use `/v1/` (remove legacy code)
- After 6 months: Remove legacy endpoints entirely

---

## Future Enhancements (v2.0.0)

### Deferred Features

1. **Relationship Embedding**
   - Current: Flat DTOs (Work, Edition, Author returned separately)
   - Future: Option for nested responses (Work includes `editions[]` and `authors[]` embedded)
   - Query parameter: `?expand=editions,authors` (optional nesting)

2. **Author Biography**
   - Add `bio`, `photoURL`, `website`, `socialLinks` to AuthorDTO
   - Integrate with Wikipedia API for biography enrichment

3. **Pagination**
   - Add `totalResults`, `page`, `perPage` to `BookSearchResponse`
   - Support `?page=2&perPage=50` query parameters

4. **GraphQL API**
   - Alternative to REST for advanced clients
   - Enables client-side field selection (reduce over-fetching)

5. **OpenAPI Specification**
   - Generate OpenAPI 3.1 spec from TypeScript types
   - Auto-generate API docs with Scalar or Redoc

---

## Implementation Checklist

### Backend (Cloudflare Workers)

- [ ] Create `src/types/canonical.ts` with all DTO interfaces
- [ ] Create `src/types/enums.ts` with TypeScript enum types
- [ ] Create `src/types/responses.ts` with envelope types
- [ ] Create `src/services/canonical-normalizers.ts`
  - [ ] `normalizeWorkFromGoogleBooks(item) → WorkDTO`
  - [ ] `normalizeWorkFromOpenLibrary(doc) → WorkDTO`
  - [ ] `normalizeEditionFromGoogleBooks(item) → EditionDTO`
  - [ ] `normalizeAuthorFromGoogleBooks(name) → AuthorDTO`
  - [ ] `ensureWorkForEdition(edition) → WorkDTO` (synthetic Works)
- [ ] Create `src/services/deduplicator.ts`
  - [ ] `mergeWorks(work1, work2) → WorkDTO`
  - [ ] `fuzzyMatch(title1, author1, title2, author2) → number` (0-1 similarity)
- [ ] Implement `/v1/search/title` endpoint
- [ ] Implement `/v1/search/isbn` endpoint
- [ ] Implement `/v1/search/advanced` endpoint
- [ ] Implement `/v1/api/enrichment/start` endpoint
- [ ] Implement `/v1/api/scan-bookshelf` endpoint
- [ ] Add integration tests for canonical responses
- [ ] Update `wrangler.toml` routes for `/v1/*` prefix

### iOS (SwiftUI + SwiftData)

- [ ] Create `BooksTrackerFeature/DTOs/WorkDTO.swift` (mirrors TypeScript)
- [ ] Create `BooksTrackerFeature/DTOs/EditionDTO.swift`
- [ ] Create `BooksTrackerFeature/DTOs/AuthorDTO.swift`
- [ ] Create `BooksTrackerFeature/DTOs/ResponseEnvelope.swift`
- [ ] Create `BooksTrackerFeature/Services/CanonicalAPIClient.swift`
  - [ ] `searchByTitle(_:) async throws → BookSearchResponse`
  - [ ] `searchByISBN(_:) async throws → BookSearchResponse`
  - [ ] `startEnrichment(_:) async throws → EnrichmentJobResponse`
- [ ] Create `BooksTrackerFeature/Services/DTOMapper.swift`
  - [ ] `mapToWork(dto: WorkDTO, context: ModelContext) → Work`
  - [ ] `mapToEdition(dto: EditionDTO, context: ModelContext) → Edition`
  - [ ] `mapToAuthor(dto: AuthorDTO, context: ModelContext) → Author`
- [ ] Implement iOS-side deduplication logic
- [ ] Add unit tests for DTO → SwiftData mapping
- [ ] Add feature flag: `FeatureFlags.useCanonicalAPI`
- [ ] Test with real devices (iPhone, iPad)

### Documentation

- [x] Design document (this file)
- [ ] API reference documentation (generate from TypeScript with TSDoc)
- [ ] Migration guide for iOS developers
- [ ] Add to `docs/README.md` navigation

---

## Success Metrics

**How we'll know this design is successful:**

1. **Zero shape inconsistencies** - All `/v1/*` endpoints return canonical envelope
2. **iOS parsing simplicity** - Single DTO parser per entity (not 3+ variations)
3. **Deduplication accuracy** - <5% duplicate Works in iOS SwiftData after 1 month
4. **Provider independence** - Can add new provider (e.g., Amazon API) without changing iOS code
5. **Developer velocity** - New API fields added to TypeScript propagate to iOS in <1 day

---

## Open Questions

1. **Zod validation:** Should we add Zod schemas for runtime validation of DTOs?
   - **Pro:** Catches malformed provider responses at runtime
   - **Con:** Adds dependency, slight performance overhead
   - **Recommendation:** Add in Phase 2 after `/v1/` endpoints stabilize

2. **Relationship embedding depth:** When we add nested responses, how deep?
   - Option A: Shallow (Work includes Edition IDs only, not full objects)
   - Option B: One level (Work includes Edition objects, but Edition doesn't include Work)
   - Option C: Configurable via `?expand=editions.work` query parameter
   - **Recommendation:** Defer to v2.0.0, start with Option B when implemented

3. **Genre taxonomy ownership:** Who maintains canonical genre list?
   - Option A: Backend hardcoded list (100+ genres)
   - Option B: Cloudflare KV dynamic list (editable via admin UI)
   - Option C: OpenLibrary subjects as canonical source
   - **Recommendation:** Start with Option A (hardcoded), migrate to Option B later

---

## References

- [OpenLibrary API Documentation](https://openlibrary.org/developers/api)
- [Google Books API Reference](https://developers.google.com/books/docs/v1/reference)
- [TypeScript Handbook: Interfaces](https://www.typescriptlang.org/docs/handbook/interfaces.html)
- [Swift Codable Documentation](https://developer.apple.com/documentation/swift/codable)
- [BooksTrack SwiftData Models](../BooksTrackerPackage/Sources/BooksTrackerFeature/)

---

## Change Log

| Version | Date       | Author        | Changes                          |
|---------|------------|---------------|----------------------------------|
| 1.0.0   | 2025-10-29 | BooksTrack    | Initial design approved          |
