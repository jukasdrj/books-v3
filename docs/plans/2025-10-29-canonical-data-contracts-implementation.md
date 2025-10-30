# Canonical Data Contracts Implementation Plan

> **STATUS:** ✅ **Phases 1-3 COMPLETE** | Deployed to production | 18 tests passing

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement TypeScript-first canonical data contracts for BooksTrack API, creating `/v1/` endpoints with consistent response shapes and eliminating multi-provider response inconsistencies.

**Deployment:** https://api-worker.jukasdrj.workers.dev

**Architecture:** TypeScript interfaces define canonical DTOs (WorkDTO, EditionDTO, AuthorDTO) as single source of truth. Backend normalizers transform provider responses (Google Books, OpenLibrary, ISBNDB, Gemini) into canonical shapes. Universal response envelope wraps all API responses with metadata (timing, provider, cache status). Migration strategy: `/v1/` prefix for new endpoints, iOS dual-support, deprecate legacy after 3 months.

**Tech Stack:** TypeScript, Cloudflare Workers, Wrangler, Vitest (testing)

**Prerequisites:**
- Design document: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Existing normalizers: `cloudflare-workers/api-worker/src/services/external-apis.js`
- Current endpoints: `/search/title`, `/search/isbn`, `/search/advanced`

---

## ✅ COMPLETED WORK

**Phases 1-3 completed on 2025-10-30:**
- Phase 1: TypeScript type definitions (Tasks 1-3) ✅
- Phase 1b: Swift model alignment (Tasks 3a-3b) ✅
- Phase 2: Canonical normalizers (Tasks 4-6) ✅
- Phase 3: /v1/ endpoints (Tasks 7-8, 10-11) ✅

**Deployed:**
- `GET /v1/search/title?q={query}`
- `GET /v1/search/isbn?isbn={isbn}`
- `GET /v1/search/advanced?title={title}&author={author}`

**Test Results:** 18 passing (15 unit + 3 integration)

**Production:** https://api-worker.jukasdrj.workers.dev

---

## Phase 1: TypeScript Type Definitions ✅

### Task 1: Create Enum Types ✅ COMPLETED

**Files:**
- Create: `cloudflare-workers/api-worker/src/types/enums.ts`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/ModelTypes.swift`

**Step 1: Create enum types file**

```typescript
/**
 * Canonical Enum Types
 *
 * These match Swift enums in BooksTrackerFeature exactly.
 * DO NOT modify without updating iOS Swift enums.
 */

export type EditionFormat =
  | 'Hardcover'
  | 'Paperback'
  | 'E-book'
  | 'Audiobook'
  | 'Mass Market';

export type AuthorGender =
  | 'Female'
  | 'Male'
  | 'Non-binary'
  | 'Other'
  | 'Unknown';

export type CulturalRegion =
  | 'Africa'
  | 'Asia'
  | 'Europe'
  | 'North America'
  | 'South America'
  | 'Oceania'
  | 'Middle East'
  | 'Caribbean'
  | 'Central Asia'
  | 'Indigenous'
  | 'International';

export type ReviewStatus =
  | 'verified'
  | 'needsReview'
  | 'userEdited';

/**
 * Provider identifiers for attribution
 */
export type DataProvider =
  | 'google-books'
  | 'openlibrary'
  | 'isbndb'
  | 'gemini';

/**
 * Error codes for structured error handling
 */
export type ApiErrorCode =
  | 'INVALID_ISBN'
  | 'INVALID_QUERY'
  | 'PROVIDER_TIMEOUT'
  | 'PROVIDER_ERROR'
  | 'NOT_FOUND'
  | 'RATE_LIMIT_EXCEEDED'
  | 'INTERNAL_ERROR';
```

**Step 2: Verify TypeScript compiles**

Run: `cd cloudflare-workers/api-worker && npx tsc --noEmit src/types/enums.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add cloudflare-workers/api-worker/src/types/enums.ts
git commit -m "feat(types): add canonical enum types matching Swift models

- EditionFormat, AuthorGender, CulturalRegion, ReviewStatus
- DataProvider for attribution
- ApiErrorCode for structured errors
- Exact match with iOS BooksTrackerFeature/ModelTypes.swift

Part of canonical data contracts initiative (Phase 1)"
```

---

### Task 2: Create Core DTO Interfaces

**Files:**
- Create: `cloudflare-workers/api-worker/src/types/canonical.ts`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/Author.swift`

**Step 1: Create canonical DTOs file**

```typescript
/**
 * Canonical Data Transfer Objects
 *
 * Single source of truth for all API responses.
 * iOS Swift Codable structs mirror these interfaces exactly.
 *
 * Design doc: docs/plans/2025-10-29-canonical-data-contracts-design.md
 */

import type {
  EditionFormat,
  AuthorGender,
  CulturalRegion,
  ReviewStatus,
  DataProvider,
} from './enums.js';

// ============================================================================
// CORE ENTITIES
// ============================================================================

/**
 * Work - Abstract representation of a creative work
 * Corresponds to SwiftData Work model
 */
export interface WorkDTO {
  // Required fields
  title: string;
  subjectTags: string[]; // Normalized genres

  // Optional metadata
  originalLanguage?: string;
  firstPublicationYear?: number;
  description?: string;

  // Provenance
  synthetic?: boolean; // True if Work was inferred from Edition data
  primaryProvider?: DataProvider;
  contributors?: DataProvider[];

  // External IDs - Legacy (single values)
  openLibraryID?: string;
  openLibraryWorkID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;
  goodreadsID?: string;

  // External IDs - Modern (arrays)
  goodreadsWorkIDs: string[];
  amazonASINs: string[];
  librarythingIDs: string[];
  googleBooksVolumeIDs: string[];

  // Quality metrics
  lastISBNDBSync?: string; // ISO 8601 timestamp
  isbndbQuality: number; // 0-100

  // Review metadata (for AI-detected books)
  reviewStatus: ReviewStatus;
  originalImagePath?: string;
  boundingBox?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

/**
 * Edition - Physical/digital manifestation of a Work
 * Corresponds to SwiftData Edition model
 */
export interface EditionDTO {
  // Identifiers
  isbn?: string; // Primary ISBN
  isbns: string[]; // All ISBNs

  // Core metadata
  title?: string;
  publisher?: string;
  publicationDate?: string; // YYYY-MM-DD or YYYY
  pageCount?: number;
  format: EditionFormat;
  coverImageURL?: string;
  editionTitle?: string;
  description?: string;
  language?: string;

  // Provenance
  primaryProvider?: DataProvider;
  contributors?: DataProvider[];

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

/**
 * Author - Creator of works
 * Corresponds to SwiftData Author model
 */
export interface AuthorDTO {
  // Required
  name: string;
  gender: AuthorGender;

  // Optional
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
}
```

**Step 2: Verify TypeScript compiles**

Run: `cd cloudflare-workers/api-worker && npx tsc --noEmit src/types/canonical.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add cloudflare-workers/api-worker/src/types/canonical.ts
git commit -m "feat(types): add WorkDTO, EditionDTO, AuthorDTO interfaces

Core entity DTOs matching SwiftData models:
- WorkDTO: includes synthetic flag for edge cases
- EditionDTO: multi-ISBN support
- AuthorDTO: diversity analytics focus

Field names identical to Swift models (camelCase)
Omits iOS-specific fields (dateCreated, relationships)

Part of canonical data contracts initiative (Phase 1)"
```

---

### Task 3: Create Response Envelope Types

**Files:**
- Create: `cloudflare-workers/api-worker/src/types/responses.ts`

**Step 1: Create response envelope file**

```typescript
/**
 * API Response Envelopes
 *
 * Universal structure for all API responses.
 * Discriminated union enables TypeScript type narrowing.
 */

import type { DataProvider, ApiErrorCode } from './enums.js';
import type { WorkDTO, EditionDTO, AuthorDTO } from './canonical.js';

// ============================================================================
// RESPONSE ENVELOPE
// ============================================================================

/**
 * Response metadata included in every response
 */
export interface ResponseMeta {
  timestamp: string; // ISO 8601
  processingTime?: number; // milliseconds
  provider?: DataProvider;
  cached?: boolean;
  cacheAge?: number; // seconds since cached
  requestId?: string; // for distributed tracing (future)
}

/**
 * Success response envelope
 */
export interface SuccessResponse<T> {
  success: true;
  data: T;
  meta: ResponseMeta;
}

/**
 * Error response envelope
 */
export interface ErrorResponse {
  success: false;
  error: {
    message: string;
    code?: ApiErrorCode;
    details?: any;
  };
  meta: ResponseMeta;
}

/**
 * Discriminated union for all responses
 */
export type ApiResponse<T> = SuccessResponse<T> | ErrorResponse;

// ============================================================================
// DOMAIN-SPECIFIC RESPONSE TYPES
// ============================================================================

/**
 * Book search response
 * Used by: /v1/search/title, /v1/search/isbn, /v1/search/advanced
 */
export interface BookSearchResponse {
  works: WorkDTO[];
  authors: AuthorDTO[];
  totalResults?: number; // for pagination (future)
}

/**
 * Enrichment job response
 * Used by: /v1/api/enrichment/start
 */
export interface EnrichmentJobResponse {
  jobId: string;
  queuedCount: number;
  estimatedDuration?: number; // seconds
  websocketUrl: string;
}

/**
 * Bookshelf scan response
 * Used by: /v1/api/scan-bookshelf, /v1/api/scan-bookshelf/batch
 */
export interface BookshelfScanResponse {
  jobId: string;
  detectedBooks: {
    work: WorkDTO;
    edition: EditionDTO;
    confidence: number; // 0.0-1.0
  }[];
  websocketUrl: string;
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Create success response
 */
export function createSuccessResponse<T>(
  data: T,
  meta: Partial<ResponseMeta> = {}
): SuccessResponse<T> {
  return {
    success: true,
    data,
    meta: {
      timestamp: new Date().toISOString(),
      ...meta,
    },
  };
}

/**
 * Create error response
 */
export function createErrorResponse(
  message: string,
  code?: ApiErrorCode,
  details?: any,
  meta: Partial<ResponseMeta> = {}
): ErrorResponse {
  return {
    success: false,
    error: { message, code, details },
    meta: {
      timestamp: new Date().toISOString(),
      ...meta,
    },
  };
}
```

**Step 2: Verify TypeScript compiles**

Run: `cd cloudflare-workers/api-worker && npx tsc --noEmit src/types/responses.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add cloudflare-workers/api-worker/src/types/responses.ts
git commit -m "feat(types): add universal response envelope types

- SuccessResponse<T> / ErrorResponse discriminated union
- ResponseMeta with timing, provider, cache status
- BookSearchResponse, EnrichmentJobResponse, BookshelfScanResponse
- Helper functions: createSuccessResponse, createErrorResponse

All /v1/ endpoints will use these envelopes

Part of canonical data contracts initiative (Phase 1)"
```

---

## Phase 1b: Swift Model Updates (Code Review Follow-up)

### Task 3a: Add Provenance Fields to Work.swift

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift`

**Context:** Code review identified that TypeScript DTOs include provenance fields (`synthetic`, `primaryProvider`, `contributors`) that don't exist in Swift Work model. These fields enable debugging and observability.

**Step 1: Add provenance fields to Work.swift**

Add after line 27 (after `isbndbQuality`):

```swift
// Provenance tracking for debugging and observability
var synthetic: Bool = false  // True if Work was inferred from Edition data
var primaryProvider: String? // Which provider contributed this Work
var contributors: [String] = [] // All providers that enriched this Work
```

**Step 2: Update Work initializer**

Modify `init()` to include provenance parameters (optional):

```swift
public init(
    title: String,
    authors: [Author] = [],
    originalLanguage: String? = nil,
    firstPublicationYear: Int? = nil,
    subjectTags: [String] = [],
    synthetic: Bool = false,
    primaryProvider: String? = nil
) {
    self.title = title
    self.authors = nil // CRITICAL: Never create relationships in init
    self.originalLanguage = originalLanguage
    self.firstPublicationYear = firstPublicationYear
    self.subjectTags = subjectTags
    self.synthetic = synthetic
    self.primaryProvider = primaryProvider
    self.contributors = []
    self.dateCreated = Date()
    self.lastModified = Date()
}
```

**Step 3: Verify Swift compiles**

Run: `/build` slash command (uses XcodeBuildMCP)
Expected: Build succeeds with zero errors

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift
git commit -m "feat(models): add provenance fields to Work model

Adds observability and debugging fields:
- synthetic: Bool - Marks Works inferred from Edition data
- primaryProvider: String? - Which API contributed the Work
- contributors: [String] - All providers that enriched this Work

Matches TypeScript WorkDTO for canonical contracts.
Code review follow-up from Task 2.

Part of canonical data contracts initiative (Phase 1b)"
```

---

### Task 3b: Add Provenance Fields to Edition.swift

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift`

**Context:** Code review identified missing `description` and provenance fields in Swift Edition model that exist in TypeScript EditionDTO.

**Step 1: Add description and provenance fields**

Add after line 32 (after `isbndbQuality`):

```swift
// Edition-specific description (may differ from Work description)
var description: String?

// Provenance tracking for debugging and observability
var primaryProvider: String? // Which provider contributed this Edition
var contributors: [String] = [] // All providers that enriched this Edition
```

**Step 2: Update Edition initializer**

Modify `init()` to include new parameters (optional):

```swift
public init(
    isbn: String? = nil,
    publisher: String? = nil,
    publicationDate: String? = nil,
    pageCount: Int? = nil,
    format: EditionFormat = EditionFormat.hardcover,
    coverImageURL: String? = nil,
    editionTitle: String? = nil,
    description: String? = nil,
    work: Work? = nil,
    primaryProvider: String? = nil
) {
    self.isbn = isbn
    self.publisher = publisher
    self.publicationDate = publicationDate
    self.pageCount = pageCount
    self.format = format
    self.coverImageURL = coverImageURL
    self.editionTitle = editionTitle
    self.description = description
    self.work = work
    self.primaryProvider = primaryProvider
    self.contributors = []
    self.dateCreated = Date()
    self.lastModified = Date()
}
```

**Step 3: Verify Swift compiles**

Run: `/build` slash command
Expected: Build succeeds with zero errors

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift
git commit -m "feat(models): add description and provenance fields to Edition

Adds observability and metadata fields:
- description: String? - Edition-specific description
- primaryProvider: String? - Which API contributed the Edition
- contributors: [String] - All providers that enriched this Edition

Matches TypeScript EditionDTO for canonical contracts.
Code review follow-up from Task 2.

Part of canonical data contracts initiative (Phase 1b)"
```

---

## Phase 2: Canonical Normalizers

### Task 4: Create Normalizer for Google Books → WorkDTO

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`
- Reference: `src/services/external-apis.js` (existing normalizeGoogleBooksResponse)

**Step 1: Write failing test**

Create: `cloudflare-workers/api-worker/tests/normalizers/google-books.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { normalizeGoogleBooksToWork } from '../../src/services/normalizers/google-books.js';

describe('normalizeGoogleBooksToWork', () => {
  it('should convert Google Books item to WorkDTO', () => {
    const googleBooksItem = {
      id: 'beSP5CCpiGUC',
      volumeInfo: {
        title: '1984',
        authors: ['George Orwell'],
        publishedDate: '1949-06-08',
        categories: ['Fiction', 'Dystopian'],
        description: 'A dystopian novel...',
        industryIdentifiers: [
          { type: 'ISBN_13', identifier: '9780451524935' }
        ]
      }
    };

    const work = normalizeGoogleBooksToWork(googleBooksItem);

    expect(work.title).toBe('1984');
    expect(work.firstPublicationYear).toBe(1949);
    expect(work.subjectTags).toEqual(['Fiction', 'Dystopian']);
    expect(work.googleBooksVolumeIDs).toContain('beSP5CCpiGUC');
    expect(work.primaryProvider).toBe('google-books');
    expect(work.synthetic).toBe(false);
  });

  it('should handle missing optional fields', () => {
    const minimalItem = {
      id: 'xyz123',
      volumeInfo: {
        title: 'Unknown Book',
        authors: ['Unknown Author']
      }
    };

    const work = normalizeGoogleBooksToWork(minimalItem);

    expect(work.title).toBe('Unknown Book');
    expect(work.firstPublicationYear).toBeUndefined();
    expect(work.subjectTags).toEqual([]);
    expect(work.description).toBeUndefined();
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: FAIL with "Cannot find module"

**Step 3: Write minimal implementation**

Create: `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`

```typescript
/**
 * Google Books API → Canonical DTO Normalizers
 */

import type { WorkDTO, EditionDTO, AuthorDTO } from '../../types/canonical.js';

/**
 * Extract year from Google Books date string
 * Formats: "1949", "1949-06", "1949-06-08"
 */
function extractYear(dateString?: string): number | undefined {
  if (!dateString) return undefined;
  const match = dateString.match(/^(\d{4})/);
  return match ? parseInt(match[1], 10) : undefined;
}

/**
 * Normalize Google Books volume to WorkDTO
 */
export function normalizeGoogleBooksToWork(item: any): WorkDTO {
  const volumeInfo = item.volumeInfo || {};

  return {
    title: volumeInfo.title || 'Unknown',
    subjectTags: volumeInfo.categories || [],
    originalLanguage: volumeInfo.language,
    firstPublicationYear: extractYear(volumeInfo.publishedDate),
    description: volumeInfo.description,
    synthetic: false,
    primaryProvider: 'google-books',
    contributors: ['google-books'],
    goodreadsWorkIDs: [],
    amazonASINs: [],
    librarythingIDs: [],
    googleBooksVolumeIDs: [item.id],
    isbndbQuality: 0,
    reviewStatus: 'verified',
  };
}
```

**Step 4: Run test to verify it passes**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: PASS (2 tests)

**Step 5: Commit**

```bash
git add tests/normalizers/google-books.test.ts src/services/normalizers/google-books.ts
git commit -m "feat(normalizers): add Google Books → WorkDTO normalizer

Converts Google Books volumeInfo to canonical WorkDTO:
- Extracts year from publishedDate (supports YYYY, YYYY-MM, YYYY-MM-DD)
- Maps categories to subjectTags
- Sets primaryProvider = 'google-books'
- Handles missing optional fields gracefully

Tests: 2 passing (basic conversion + optional fields)

Part of canonical data contracts initiative (Phase 2)"
```

---

### Task 5: Create Normalizer for Google Books → EditionDTO

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`
- Modify: `cloudflare-workers/api-worker/tests/normalizers/google-books.test.ts`

**Step 1: Write failing test**

```typescript
// Add to tests/normalizers/google-books.test.ts

import { normalizeGoogleBooksToEdition } from '../../src/services/normalizers/google-books.js';

describe('normalizeGoogleBooksToEdition', () => {
  it('should convert Google Books item to EditionDTO', () => {
    const googleBooksItem = {
      id: 'beSP5CCpiGUC',
      volumeInfo: {
        title: '1984',
        publisher: 'Penguin',
        publishedDate: '2021-01-05',
        pageCount: 328,
        imageLinks: {
          thumbnail: 'http://books.google.com/covers/1984.jpg'
        },
        industryIdentifiers: [
          { type: 'ISBN_13', identifier: '9780451524935' },
          { type: 'ISBN_10', identifier: '0451524934' }
        ]
      }
    };

    const edition = normalizeGoogleBooksToEdition(googleBooksItem);

    expect(edition.isbn).toBe('9780451524935'); // ISBN-13 preferred
    expect(edition.isbns).toContain('9780451524935');
    expect(edition.isbns).toContain('0451524934');
    expect(edition.publisher).toBe('Penguin');
    expect(edition.publicationDate).toBe('2021-01-05');
    expect(edition.pageCount).toBe(328);
    expect(edition.format).toBe('Hardcover'); // default
    expect(edition.coverImageURL).toBe('https://books.google.com/covers/1984.jpg');
    expect(edition.primaryProvider).toBe('google-books');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: FAIL with "normalizeGoogleBooksToEdition is not exported"

**Step 3: Write minimal implementation**

Add to `src/services/normalizers/google-books.ts`:

```typescript
/**
 * Normalize Google Books volume to EditionDTO
 */
export function normalizeGoogleBooksToEdition(item: any): EditionDTO {
  const volumeInfo = item.volumeInfo || {};
  const identifiers = volumeInfo.industryIdentifiers || [];

  const isbn13 = identifiers.find((id: any) => id.type === 'ISBN_13')?.identifier;
  const isbn10 = identifiers.find((id: any) => id.type === 'ISBN_10')?.identifier;
  const isbns = [isbn13, isbn10].filter(Boolean) as string[];

  return {
    isbn: isbn13 || isbn10,
    isbns,
    title: volumeInfo.title,
    publisher: volumeInfo.publisher,
    publicationDate: volumeInfo.publishedDate,
    pageCount: volumeInfo.pageCount,
    format: 'Hardcover', // Google Books doesn't provide format
    coverImageURL: volumeInfo.imageLinks?.thumbnail?.replace('http:', 'https:'),
    editionTitle: undefined,
    description: volumeInfo.description,
    language: volumeInfo.language,
    primaryProvider: 'google-books',
    contributors: ['google-books'],
    amazonASINs: [],
    googleBooksVolumeIDs: [item.id],
    librarythingIDs: [],
    isbndbQuality: 0,
  };
}
```

**Step 4: Run test to verify it passes**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: PASS (3 tests total)

**Step 5: Commit**

```bash
git add tests/normalizers/google-books.test.ts src/services/normalizers/google-books.ts
git commit -m "feat(normalizers): add Google Books → EditionDTO normalizer

Converts Google Books volumeInfo to canonical EditionDTO:
- Extracts ISBN-13 and ISBN-10 from industryIdentifiers
- Prefers ISBN-13 as primary ISBN
- Upgrades HTTP cover URLs to HTTPS
- Defaults format to Hardcover (Google Books doesn't provide)

Tests: 3 passing

Part of canonical data contracts initiative (Phase 2)"
```

---

### Task 6: Create Edge Case Handler for Synthetic Works

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`
- Modify: `cloudflare-workers/api-worker/tests/normalizers/google-books.test.ts`

**Step 1: Write failing test**

Add to `tests/normalizers/google-books.test.ts`:

```typescript
import { ensureWorkForEdition } from '../../src/services/normalizers/google-books.js';

describe('ensureWorkForEdition', () => {
  it('should synthesize Work from Edition when Work is missing', () => {
    const edition: EditionDTO = {
      isbn: '9780451524935',
      isbns: ['9780451524935'],
      title: '1984',
      publisher: 'Penguin',
      publicationDate: '2021',
      format: 'Hardcover',
      primaryProvider: 'google-books',
      amazonASINs: [],
      googleBooksVolumeIDs: ['abc123'],
      librarythingIDs: [],
      isbndbQuality: 0,
    };

    const work = ensureWorkForEdition(edition);

    expect(work.title).toBe('1984');
    expect(work.firstPublicationYear).toBe(2021);
    expect(work.synthetic).toBe(true); // KEY: marks as inferred
    expect(work.primaryProvider).toBe('google-books');
    expect(work.googleBooksVolumeIDs).toContain('abc123');
  });

  it('should handle edition without title', () => {
    const edition: EditionDTO = {
      isbn: '1234567890',
      isbns: ['1234567890'],
      format: 'Paperback',
      primaryProvider: 'google-books',
      amazonASINs: [],
      googleBooksVolumeIDs: [],
      librarythingIDs: [],
      isbndbQuality: 0,
    };

    const work = ensureWorkForEdition(edition);

    expect(work.title).toBe('Unknown');
    expect(work.synthetic).toBe(true);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: FAIL with "ensureWorkForEdition is not exported"

**Step 3: Write minimal implementation**

Add to `src/services/normalizers/google-books.ts`:

```typescript
/**
 * Synthesize Work from Edition when Work data is missing
 * Sets synthetic: true to indicate inferred data
 */
export function ensureWorkForEdition(edition: EditionDTO): WorkDTO {
  return {
    title: edition.title || 'Unknown',
    subjectTags: [], // Will be populated by genre normalizer (Phase 3)
    firstPublicationYear: extractYear(edition.publicationDate),
    synthetic: true, // KEY: indicates this Work was inferred
    primaryProvider: edition.primaryProvider,
    contributors: edition.contributors,
    goodreadsWorkIDs: [],
    amazonASINs: edition.amazonASINs,
    librarythingIDs: edition.librarythingIDs,
    googleBooksVolumeIDs: edition.googleBooksVolumeIDs,
    isbndbQuality: edition.isbndbQuality,
    reviewStatus: 'verified',
  };
}
```

**Step 4: Run test to verify it passes**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/normalizers/google-books.test.ts`
Expected: PASS (5 tests total)

**Step 5: Commit**

```bash
git add tests/normalizers/google-books.test.ts src/services/normalizers/google-books.ts
git commit -m "feat(normalizers): add synthetic Work generation for orphaned Editions

ensureWorkForEdition() handles edge case when Edition has no Work:
- Synthesizes Work from Edition metadata (title, date, IDs)
- Sets synthetic: true flag (tells iOS this was inferred)
- Enables iOS deduplication to merge if same Work found later

Tests: 5 passing (includes edge cases)

Part of canonical data contracts initiative (Phase 2)"
```

---

## Phase 3: Implement /v1/ Endpoints

### Task 7: Create /v1/search/title Endpoint

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/v1/search-title.ts`
- Modify: `cloudflare-workers/api-worker/src/index.js`
- Reference: `src/handlers/search-handlers.js` (existing logic)

**Step 1: Write failing test**

Create: `cloudflare-workers/api-worker/tests/handlers/v1/search-title.test.ts`

```typescript
import { describe, it, expect, vi } from 'vitest';
import { handleSearchTitle } from '../../../src/handlers/v1/search-title.js';

describe('GET /v1/search/title', () => {
  it('should return canonical BookSearchResponse', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
    };

    const response = await handleSearchTitle('1984', mockEnv);

    expect(response.success).toBe(true);
    if (response.success) {
      expect(response.data.works).toBeDefined();
      expect(response.data.authors).toBeDefined();
      expect(response.meta.timestamp).toBeDefined();
      expect(response.meta.provider).toBe('google-books');
    }
  });

  it('should return error response for invalid query', async () => {
    const mockEnv = {};

    const response = await handleSearchTitle('', mockEnv);

    expect(response.success).toBe(false);
    if (!response.success) {
      expect(response.error.code).toBe('INVALID_QUERY');
      expect(response.error.message).toContain('query is required');
    }
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/handlers/v1/search-title.test.ts`
Expected: FAIL with "Cannot find module"

**Step 3: Write minimal implementation**

Create: `cloudflare-workers/api-worker/src/handlers/v1/search-title.ts`

```typescript
/**
 * GET /v1/search/title
 *
 * Search for books by title using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { searchGoogleBooks } from '../../services/external-apis.js';
import { normalizeGoogleBooksToWork } from '../../services/normalizers/google-books.js';

export async function handleSearchTitle(
  query: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation
  if (!query || query.trim().length === 0) {
    return createErrorResponse(
      'Search query is required',
      'INVALID_QUERY',
      { query }
    );
  }

  try {
    // Call existing Google Books search
    const result = await searchGoogleBooks(query, { maxResults: 20 }, env);

    if (!result.success) {
      return createErrorResponse(
        result.error || 'Search failed',
        'PROVIDER_ERROR',
        undefined,
        { processingTime: Date.now() - startTime }
      );
    }

    // Convert to canonical format
    const works = result.works.map((w: any) => {
      // Note: existing normalizeGoogleBooksResponse already returns work-like objects
      // We need to map to WorkDTO format
      return {
        title: w.title,
        subjectTags: w.subjects || [],
        firstPublicationYear: w.firstPublishYear,
        primaryProvider: 'google-books' as const,
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        googleBooksVolumeIDs: w.editions?.map((e: any) => e.googleBooksVolumeId).filter(Boolean) || [],
        isbndbQuality: 0,
        reviewStatus: 'verified' as const,
      };
    });

    const authors = result.authors?.map((a: any) => ({
      name: a.name,
      gender: 'Unknown' as const,
    })) || [];

    return createSuccessResponse(
      { works, authors },
      {
        processingTime: Date.now() - startTime,
        provider: 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `cd cloudflare-workers/api-worker && npm test -- tests/handlers/v1/search-title.test.ts`
Expected: PASS (2 tests)

**Step 5: Add route to index.js**

Modify `src/index.js`:

```javascript
// Add import at top
import { handleSearchTitle } from './handlers/v1/search-title.js';

// Add route in fetch handler (after existing routes)
if (url.pathname === '/v1/search/title' && request.method === 'GET') {
  const query = url.searchParams.get('q');
  const response = await handleSearchTitle(query, env);
  return new Response(JSON.stringify(response), {
    headers: { 'Content-Type': 'application/json' },
  });
}
```

**Step 6: Commit**

```bash
git add tests/handlers/v1/search-title.test.ts src/handlers/v1/search-title.ts src/index.js
git commit -m "feat(api): add GET /v1/search/title with canonical response

First /v1/ endpoint using canonical contracts:
- Returns SuccessResponse<BookSearchResponse> envelope
- Validates query parameter
- Maps existing searchGoogleBooks to WorkDTO format
- Includes ResponseMeta with timing and provider

Tests: 2 passing (success + validation)

Part of canonical data contracts initiative (Phase 3)"
```

---

## Phase 4: Integration Testing

### Task 8: Add End-to-End Test for /v1/search/title

**Files:**
- Create: `cloudflare-workers/api-worker/tests/integration/v1-search.test.ts`

**Step 1: Write integration test**

```typescript
/**
 * Integration tests for /v1/ search endpoints
 *
 * These tests hit real Cloudflare Worker (requires wrangler dev)
 */

import { describe, it, expect } from 'vitest';

const WORKER_URL = 'http://localhost:8787';

describe('GET /v1/search/title (integration)', () => {
  it('should return canonical response for "1984"', async () => {
    const response = await fetch(`${WORKER_URL}/v1/search/title?q=1984`);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.data).toBeDefined();
    expect(json.data.works).toBeInstanceOf(Array);
    expect(json.data.authors).toBeInstanceOf(Array);
    expect(json.meta.timestamp).toBeDefined();
    expect(json.meta.provider).toBe('google-books');

    // Validate WorkDTO structure
    const work = json.data.works[0];
    expect(work.title).toBeDefined();
    expect(work.subjectTags).toBeInstanceOf(Array);
    expect(work.goodreadsWorkIDs).toBeInstanceOf(Array);
    expect(work.isbndbQuality).toBeTypeOf('number');
  });

  it('should return error for empty query', async () => {
    const response = await fetch(`${WORKER_URL}/v1/search/title?q=`);
    const json = await response.json();

    expect(response.status).toBe(200); // Still 200, error in JSON
    expect(json.success).toBe(false);
    expect(json.error.code).toBe('INVALID_QUERY');
    expect(json.meta.timestamp).toBeDefined();
  });
});
```

**Step 2: Run test with wrangler dev**

Run: `cd cloudflare-workers/api-worker && npx wrangler dev &`
Wait for "Ready on http://localhost:8787"
Run: `npm test -- tests/integration/v1-search.test.ts`
Expected: PASS (2 tests)

**Step 3: Commit**

```bash
git add tests/integration/v1-search.test.ts
git commit -m "test(integration): add e2e tests for /v1/search/title

Integration tests against live Worker:
- Validates canonical response structure
- Checks WorkDTO field types
- Tests error handling (empty query)

Run: npx wrangler dev && npm test integration

Part of canonical data contracts initiative (Phase 4)"
```

---

## Phase 5: Documentation

### Task 9: Update CLAUDE.md with Canonical Contracts

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add canonical contracts section**

Add after "Backend Architecture" section in CLAUDE.md:

```markdown
### Canonical Data Contracts (v1.0.0)

**TypeScript-first API contracts** ensure consistency across all data providers.

**Core DTOs:** `cloudflare-workers/api-worker/src/types/canonical.ts`
- `WorkDTO` - Abstract creative work (mirrors SwiftData Work model)
- `EditionDTO` - Physical/digital manifestation (multi-ISBN support)
- `AuthorDTO` - Creator with diversity analytics

**Response Envelope:** All `/v1/*` endpoints return:
```typescript
{
  "success": true | false,
  "data": { ... } | "error": { message, code, details },
  "meta": { timestamp, processingTime, provider, cached }
}
```

**Migration Status:**
- ✅ TypeScript types defined
- ✅ Google Books normalizers implemented
- ✅ `/v1/search/title` endpoint live
- ⏳ `/v1/search/isbn` (next)
- ⏳ `/v1/search/advanced` (next)
- ⏳ iOS Swift Codable DTOs (Phase 2)

**Design:** `docs/plans/2025-10-29-canonical-data-contracts-design.md`
```

**Step 2: Verify markdown renders correctly**

Run: `npx markdownlint CLAUDE.md`
Expected: No errors

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add canonical data contracts section to CLAUDE.md

Documents v1.0.0 TypeScript-first contracts:
- Core DTOs (Work, Edition, Author)
- Response envelope structure
- Migration status checklist
- Reference to design document

Part of canonical data contracts initiative (Phase 5)"
```

---

## Remaining Tasks (Implementation Plan)

### ✅ Tasks 10-11: /v1/ Endpoints - COMPLETED
- ✅ Task 10: `/v1/search/isbn` with ISBN validation
- ✅ Task 11: `/v1/search/advanced` with flexible search
- **Status:** Deployed and tested in production

### ⏭️ Task 12: Add OpenLibrary Normalizers (OPTIONAL)
- `normalizeOpenLibraryToWork`
- `normalizeOpenLibraryToEdition`
- Test with OpenLibrary API responses
- **Status:** Deferred - Google Books sufficient for MVP
- **Estimated:** 2 hours

### ⏭️ Task 13: Implement Deduplication Service (OPTIONAL)
- `mergeWorks(work1, work2)` function
- Fuzzy title+author matching (Levenshtein distance)
- Unit tests for merge logic
- **Status:** Deferred - `synthetic` flag enables iOS deduplication
- **Estimated:** 3 hours

### 📋 Task 14: Create iOS Swift Codable DTOs (NEXT PHASE)
- Mirror TypeScript interfaces in Swift
- Files to create:
  - `BooksTrackerFeature/DTOs/WorkDTO.swift`
  - `BooksTrackerFeature/DTOs/EditionDTO.swift`
  - `BooksTrackerFeature/DTOs/AuthorDTO.swift`
  - `BooksTrackerFeature/DTOs/ResponseEnvelope.swift`
- Must match TypeScript field names exactly (camelCase)
- Include provenance fields (`primaryProvider`, `contributors`, `synthetic`)
- **Critical:** Use `editionDescription` (not `description` - @Model reserves it)
- **Estimated:** 2-3 hours
- **Prerequisites:** None (TypeScript contracts complete)

### 📋 Task 15: Implement iOS DTO → SwiftData Mapper (NEXT PHASE)
- Create `BooksTrackerFeature/Services/DTOMapper.swift`
- Functions:
  - `mapToWork(dto: WorkDTO, context: ModelContext) → Work`
  - `mapToEdition(dto: EditionDTO, work: Work, context: ModelContext) → Edition`
  - `mapToAuthor(dto: AuthorDTO, context: ModelContext) → Author`
- Handle deduplication:
  - Check for existing Work by `googleBooksVolumeIDs`
  - Merge `synthetic` Works with real Works when found
  - Use `primaryProvider` for conflict resolution
- Respect insert-before-relate pattern (SwiftData requirement)
- Test with real `/v1/` API responses
- **Estimated:** 3-4 hours
- **Prerequisites:** Task 14 (Swift DTOs must exist)

### 📋 Task 16: Update iOS Networking Layer (NEXT PHASE)
- Update `SearchService.swift` to use `/v1/` endpoints
- Parse canonical response envelopes
- Handle error codes (`INVALID_QUERY`, `INVALID_ISBN`, etc.)
- Update existing search flows (title, ISBN, advanced)
- **Estimated:** 2 hours
- **Prerequisites:** Tasks 14-15 (DTOs + mapper)

**Total Remaining Estimate:** 7-9 hours (iOS integration)
**Optional Work:** 5 hours (OpenLibrary + deduplication)

---

## Testing Strategy

**Unit Tests:**
- Normalizer functions (Task 4-6)
- Response envelope helpers
- Deduplication logic

**Integration Tests:**
- End-to-end endpoint tests (Task 8)
- Multi-provider fallback scenarios
- Cache behavior validation

**iOS Tests:**
- DTO parsing from JSON
- SwiftData mapping correctness
- Deduplication accuracy

**Manual Testing:**
- Search for common books ("Harry Potter", "1984")
- Edge cases (books without ISBNs, multi-author works)
- Provider fallback (Google Books → OpenLibrary)

---

## Rollback Plan

If canonical contracts cause issues:

1. **Backend:** Keep legacy endpoints running, disable `/v1/*` routes
2. **iOS:** Feature flag `FeatureFlags.useCanonicalAPI = false`
3. **Rollback commit:** Revert to previous stable state
4. **Debug:** Check Worker logs with `npx wrangler tail`

---

## Success Criteria

**Backend (Phases 1-3):** ✅ COMPLETE
- [x] All `/v1/*` endpoints return canonical envelopes
- [x] Zero TypeScript compilation errors
- [x] All unit tests passing (15/15 backend tests)
- [x] Integration tests passing against live Worker (3/3 integration tests)
- [x] Documentation updated (CLAUDE.md, implementation plan)

**iOS Integration (Tasks 14-16):** ⏳ NEXT PHASE
- [ ] iOS Swift Codable DTOs created (WorkDTO, EditionDTO, AuthorDTO, ResponseEnvelope)
- [ ] iOS can parse canonical responses without crashes
- [ ] DTO → SwiftData mapper implemented
- [ ] Deduplication logic working (merge synthetic Works)
- [ ] iOS networking layer updated to use `/v1/` endpoints
- [ ] Manual testing with real API responses

---

## References

- Design: `docs/plans/2025-10-29-canonical-data-contracts-design.md`
- Swift Models: `BooksTrackerPackage/Sources/BooksTrackerFeature/`
- Existing APIs: `cloudflare-workers/api-worker/src/services/external-apis.js`
- TypeScript Handbook: https://www.typescriptlang.org/docs/
- Cloudflare Workers: https://developers.cloudflare.com/workers/
