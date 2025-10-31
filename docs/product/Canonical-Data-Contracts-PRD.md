# Canonical Data Contracts - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** Backend + iOS Developer
**Target Release:** v3.1.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Canonical Data Contracts establish TypeScript-first DTOs (Data Transfer Objects) as the single source of truth for all BooksTrack API responses. By normalizing diverse data provider formats (Google Books, OpenLibrary, ISBNDB) into consistent canonical structures on the backend, iOS consumes predictable, clean data without provider-specific parsing logic—reducing code complexity and enabling reliable feature development.

---

## Problem Statement

### Developer Pain Point

**What problem are we solving?**

Different book data providers return inconsistent JSON structures, forcing iOS to maintain provider-specific normalization code. Issues include:
- **Inconsistent field names:** `volumeInfo.title` (Google Books) vs `title` (OpenLibrary)
- **Genre chaos:** "Fiction / Science Fiction / General" vs "Science Fiction" vs "Sci-Fi"
- **Missing provenance:** Can't trace which API provided data (debugging nightmares)
- **iOS duplication:** Same genre normalization logic copied across search services

### Current Experience (Before Canonical Contracts)

**How did data flow work previously?**

```
Google Books API → Raw JSON → iOS parses volumeInfo → Extract fields → Normalize genres → Create Work
OpenLibrary API → Raw JSON → iOS parses differently → Extract fields → Normalize genres → Create Work
```

**Result:** 
- iOS has 200+ lines of provider-specific parsing code
- Genre normalization duplicated in 3 places
- No way to know "Where did this genre come from?"
- New providers require iOS code changes (not backend-only)

---

## Target Users

### Primary Persona

**Who benefits from canonical contracts?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Developers (backend + iOS), indirectly all users |
| **Usage Frequency** | Every API call (search, enrichment, CSV import) |
| **Tech Savvy** | High (backend engineers), Medium (iOS engineers) |
| **Primary Goal** | Clean, consistent API contracts → faster feature development |

**Example Developer Stories:**

> "As an **iOS developer**, I want **predictable API responses** so that I can **write simple Codable parsing without provider-specific logic**."

> "As a **backend developer**, I want **TypeScript DTOs** so that I can **enforce consistency across all data providers automatically**."

> "As a **QA engineer**, I want **provenance tracking** so that I can **debug 'Where did this wrong genre come from?'**"

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **iOS Code Reduction** | Remove 100+ lines of provider-specific parsing | Git diff (before/after migration) |
| **Genre Consistency** | 100% normalized ("Thriller" not "Thrillers") | Backend validation tests |
| **Provenance Tracking** | Every Work/Edition has `primaryProvider` field | Database query |
| **Backend-Only Changes** | Add new provider without iOS release | Architecture audit |

**Actual Results (Production):**
- ✅ iOS code reduction: 120+ lines removed (BookSearchAPIService refactored to use DTOMapper)
- ✅ Genre consistency: 100% (genre-normalizer.ts active on all /v1/* endpoints)
- ✅ Provenance tracking: All DTOs include `primaryProvider` + `contributors` fields
- ✅ Backend-only: Can add ISBNDB provider without iOS changes (future proof)

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Consistent API Responses

**As an** iOS developer
**I want** all `/v1/*` endpoints to return canonical DTOs
**So that** I write one Codable struct (not 5 provider-specific parsers)

**Acceptance Criteria:**
- [x] Given iOS calls `/v1/search/title?q=Dune`, when backend responds, then response contains `{ success, data: { works: WorkDTO[], authors: AuthorDTO[] }, meta }`
- [x] Given iOS calls `/v1/search/isbn?isbn=9780441013593`, when backend responds, then same envelope structure used
- [x] Given WorkDTO structure defined in TypeScript, when iOS mirrors with Swift Codable, then field names match exactly (`title`, not `volumeInfo.title`)

#### User Story 2: Genre Normalization

**As a** user searching for books
**I want** consistent genre tags
**So that** filtering and recommendations work reliably

**Acceptance Criteria:**
- [x] Given Google Books returns `"Fiction / Science Fiction / General"`, when backend normalizes, then DTO contains `["Fiction", "Science Fiction"]`
- [x] Given provider returns `"Thrillers"` (plural), when normalized, then DTO contains `"Thriller"` (singular)
- [x] Given unknown genre `"Quantum Literature"`, when normalization runs, then genre passes through unchanged (no data loss)

#### User Story 3: Provenance Tracking

**As a** developer debugging wrong metadata
**I want** to know which provider contributed data
**So that** I can fix the source (backend normalizer or provider API)

**Acceptance Criteria:**
- [x] Given WorkDTO created from Google Books, when iOS receives DTO, then `primaryProvider: "google-books"` field present
- [x] Given Edition enriched by multiple providers, when iOS receives DTO, then `contributors: ["google-books", "openlibrary"]` array present
- [x] Given synthetic Work (inferred from Edition-only data), when iOS receives DTO, then `synthetic: true` flag present

#### User Story 4: TypeScript Compiler Validation

**As a** backend developer
**I want** TypeScript to enforce DTO structure
**So that** breaking changes caught at compile-time (not runtime)

**Acceptance Criteria:**
- [x] Given WorkDTO interface defined with required fields, when backend code omits `title`, then TypeScript compilation fails
- [x] Given EditionDTO uses `EditionFormat` enum, when backend assigns invalid value, then TypeScript error
- [x] Given API response envelope uses discriminated union (`success: true | false`), when backend returns malformed envelope, then TypeScript catches

---

## Technical Implementation

### Architecture Overview

**Data Flow:**

```
Data Provider (Google Books)
  ↓
Backend Normalizer (normalizeGoogleBooksToWork)
  ↓
Canonical DTO (WorkDTO, EditionDTO, AuthorDTO)
  ↓
Genre Normalizer (genre-normalizer.ts)
  ↓
API Response Envelope ({ success, data, meta })
  ↓
iOS DTOMapper (Swift Codable parsing)
  ↓
SwiftData Models (Work, Edition, Author)
```

**TypeScript DTOs (Single Source of Truth):**

File: `cloudflare-workers/api-worker/src/types/canonical.ts`

```typescript
export interface WorkDTO {
  title: string;
  subtitle?: string;
  description?: string;
  coverUrl?: string;
  firstPublishDate?: string;
  genres: string[];  // Normalized genres
  googleBooksVolumeIDs: string[];
  openLibraryWorkID?: string;
  primaryProvider: DataProvider;
  contributors: DataProvider[];
  synthetic: boolean;  // Inferred from Edition-only data
}

export interface EditionDTO {
  isbn13?: string;
  isbn10?: string;
  title: string;
  publisher?: string;
  publishDate?: string;
  pageCount?: number;
  format?: EditionFormat;
  coverUrl?: string;
  googleBooksVolumeID?: string;
  openLibraryEditionID?: string;
  primaryProvider: DataProvider;
}

export interface AuthorDTO {
  name: string;
  openLibraryAuthorID?: string;
  gender?: AuthorGender;
  culturalRegion?: CulturalRegion;
  primaryProvider: DataProvider;
}
```

**iOS Swift DTOs (Mirror TypeScript):**

File: `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/CanonicalDTOs.swift`

```swift
struct WorkDTO: Codable {
    let title: String
    let subtitle: String?
    let description: String?
    let coverUrl: String?
    let firstPublishDate: String?
    let genres: [String]
    let googleBooksVolumeIDs: [String]
    let openLibraryWorkID: String?
    let primaryProvider: String
    let contributors: [String]
    let synthetic: Bool
}
```

**Response Envelope (All /v1/* Endpoints):**

```typescript
type ApiResponse<T> =
  | { success: true; data: T; error: undefined; meta: ResponseMeta }
  | { success: false; data: undefined; error: ApiError; meta: ResponseMeta };
```

---

## Decision Log

### October 2025 Decisions

#### **Decision:** TypeScript-First Contracts (Not OpenAPI/JSON Schema)

**Context:** Need single source of truth for API contracts.

**Options Considered:**
1. OpenAPI YAML → generate TypeScript + Swift (tooling complexity, YAML drift)
2. JSON Schema → validate at runtime (no compile-time safety)
3. TypeScript DTOs → iOS mirrors manually (simple, compile-time enforced)

**Decision:** Option 3 (TypeScript-first, iOS mirrors manually)

**Rationale:**
- **Compile-Time Safety:** TypeScript catches missing fields at build time
- **Simple Tooling:** No code generators, just TypeScript + Swift Codable
- **Version Control:** DTOs in source code (not separate YAML files)
- **Evolution:** Easy to add optional fields (backwards compatible)

**Tradeoffs:**
- Manual sync between TypeScript and Swift (must keep in sync, no auto-generation)
- Acceptable: PRs review both files, tests catch mismatches

---

#### **Decision:** Backend Normalization (Not iOS)

**Context:** Genre normalization, ID extraction, format parsing needed.

**Options Considered:**
1. iOS normalizes (simple backend, complex iOS, duplicated logic)
2. Backend normalizes (complex backend, simple iOS, single source of truth)
3. Hybrid (some backend, some iOS) (confusing, split responsibility)

**Decision:** Option 2 (Backend normalizes all provider data)

**Rationale:**
- **Single Source of Truth:** One place to fix genre mapping (backend only)
- **iOS Simplicity:** iOS just parses Codable, no business logic
- **Future Clients:** Android app gets normalized data for free
- **Debugging:** Backend logs show exact normalization steps

**Tradeoffs:**
- Backend complexity increases (normalizer functions for each provider)
- Acceptable: Backend has tests, easier to debug than iOS

---

#### **Decision:** Versioned Endpoints (/v1/*)

**Context:** Need to evolve API without breaking existing iOS releases.

**Options Considered:**
1. Single `/search/title` endpoint (breaking changes break old iOS)
2. Versioned `/v1/search/title` (gradual migration, dual-support)
3. Feature flags in response (complex, hard to test all combinations)

**Decision:** Option 2 (Versioned /v1/* endpoints)

**Rationale:**
- **Safe Migration:** Old iOS uses legacy endpoints, new iOS uses /v1/*
- **Gradual Rollout:** Migrate feature-by-feature (search → enrichment → scan)
- **Deprecation Path:** Mark legacy endpoints deprecated, remove after 3 months

**Tradeoffs:**
- Maintain two endpoint sets during migration (acceptable, temporary cost)

---

#### **Decision:** Synthetic Works Flag

**Context:** Google Books returns Editions but not abstract Works. Need to deduplicate.

**Options Considered:**
1. Backend creates Works from Editions (no flag, iOS unaware)
2. Backend flags synthetic Works, iOS deduplicates (explicit, flexible)
3. iOS infers synthetic (no backend flag, complex iOS logic)

**Decision:** Option 2 (Backend sets `synthetic: true`, iOS deduplicates)

**Rationale:**
- **Explicit:** iOS knows "this Work was inferred, check for duplicates"
- **Deduplication:** iOS can merge synthetic Works with real Works by ISBN
- **Provenance:** Clear signal "backend created this from Edition-only data"

**Tradeoffs:**
- Adds complexity to DTO (one boolean field, acceptable)

---

## API Specification

### GET /v1/search/title

**Request:**
```
GET /v1/search/title?q=Dune
```

**Response:**
```json
{
  "success": true,
  "data": {
    "works": [
      {
        "title": "Dune",
        "subtitle": null,
        "description": "Set on the desert planet Arrakis...",
        "coverUrl": "https://covers.openlibrary.org/b/id/123-L.jpg",
        "firstPublishDate": "1965",
        "genres": ["Science Fiction", "Fiction"],
        "googleBooksVolumeIDs": ["B00B7NPRY8"],
        "openLibraryWorkID": "OL893415W",
        "primaryProvider": "google-books",
        "contributors": ["google-books", "openlibrary"],
        "synthetic": false
      }
    ],
    "authors": [
      {
        "name": "Frank Herbert",
        "openLibraryAuthorID": "OL34184A",
        "gender": "Male",
        "culturalRegion": "North America",
        "primaryProvider": "openlibrary"
      }
    ]
  },
  "meta": {
    "timestamp": "2025-10-31T15:00:00Z",
    "processingTime": 234,
    "provider": "google-books",
    "cached": false
  }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "INVALID_QUERY",
    "message": "Search query cannot be empty",
    "details": { "query": "" }
  },
  "meta": {
    "timestamp": "2025-10-31T15:00:00Z",
    "processingTime": 5
  }
}
```

---

## Implementation Files

**Backend:**
- `cloudflare-workers/api-worker/src/types/canonical.ts` (DTOs)
- `cloudflare-workers/api-worker/src/types/enums.ts` (Shared enums)
- `cloudflare-workers/api-worker/src/types/responses.ts` (Response envelope)
- `cloudflare-workers/api-worker/src/normalizers/google-books.ts` (Google Books normalizer)
- `cloudflare-workers/api-worker/src/services/genre-normalizer.ts` (Genre normalization)
- `cloudflare-workers/api-worker/src/handlers/search-title.ts` (/v1/search/title)
- `cloudflare-workers/api-worker/src/handlers/search-isbn.ts` (/v1/search/isbn)
- `cloudflare-workers/api-worker/src/handlers/search-advanced.ts` (/v1/search/advanced)

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/CanonicalDTOs.swift` (Swift DTOs)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift` (DTO → SwiftData)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift` (Migrated to /v1/*)
- `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/CanonicalAPIResponseTests.swift` (Tests)

---

## Migration Path

### Phase 1: Backend Implementation ✅ Complete

- [x] Define TypeScript DTOs in `canonical.ts`
- [x] Create normalizers (`normalizeGoogleBooksToWork`, `normalizeGoogleBooksToEdition`)
- [x] Implement genre normalization service (`genre-normalizer.ts`)
- [x] Deploy /v1/* endpoints (title, ISBN, advanced search)
- [x] Add comprehensive tests

### Phase 2: iOS Migration ✅ Complete

- [x] Create Swift DTOs mirroring TypeScript
- [x] Implement DTOMapper service
- [x] Migrate BookSearchAPIService to /v1/* endpoints
- [x] Add iOS tests (CanonicalAPIResponseTests)
- [x] Verify deduplication works (synthetic Works merged)

### Phase 3: Legacy Deprecation ⏳ Deferred

- [ ] Mark legacy endpoints deprecated (warnings in logs)
- [ ] Monitor usage (analytics: how many requests to old endpoints)
- [ ] Remove legacy endpoints after 3 months (or when usage <1%)

---

## Error Codes

| Code | HTTP Status | Meaning |
|------|------------|---------|
| `INVALID_QUERY` | 400 | Search query empty or malformed |
| `INVALID_ISBN` | 400 | ISBN format incorrect (not 10 or 13 digits) |
| `PROVIDER_ERROR` | 502 | Upstream API (Google Books, etc.) failed |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **OpenLibrary Provider Normalizer**
   - Add `normalizeOpenLibraryToWork`
   - Enrich Google Books results with OpenLibrary data
   - Merge contributors arrays

2. **ISBNDB Provider Support**
   - Third data provider for missing books
   - Backend-only change (iOS unaffected)

3. **Structured Error Details**
   - Add `retryable: boolean` to error responses
   - iOS can auto-retry on 502 errors

4. **Field-Level Provenance**
   - Track which provider contributed each field
   - `{ title: { value: "Dune", provider: "google-books" } }`

---

## Testing Strategy

### Backend Tests

- [x] TypeScript DTO serialization (all fields present)
- [x] Genre normalization (Thrillers → Thriller)
- [x] Google Books normalizer (volumeInfo → WorkDTO)
- [x] Response envelope structure (success/error discriminated union)

### iOS Tests

- [x] Swift Codable parsing (CanonicalAPIResponseTests)
- [x] DTOMapper deduplication (synthetic Works merged)
- [x] Genre normalization flows to SwiftData models

### Integration Tests

- [x] End-to-end search (iOS → /v1/search/title → Google Books → iOS)
- [x] Provenance tracking (primaryProvider, contributors fields populated)

---

## Success Criteria (Shipped)

- ✅ TypeScript DTOs defined (WorkDTO, EditionDTO, AuthorDTO)
- ✅ All /v1/* endpoints return canonical responses
- ✅ Genre normalization active (100% consistency)
- ✅ Provenance tracking (primaryProvider, contributors, synthetic flags)
- ✅ iOS migrated to /v1/* endpoints (zero provider-specific code)
- ✅ DTOMapper deduplication working (synthetic Works merged)
- ✅ 120+ lines of iOS code removed (BookSearchAPIService refactored)

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
**Documentation:** 
- Design: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Implementation: `docs/plans/2025-10-30-canonical-contracts-implementation.md`
- Workflow: `docs/workflows/canonical-contracts-workflow.md`
