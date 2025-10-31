# Genre Normalization Service - Product Requirements Document

**Feature:** Backend Genre Normalization Service
**Status:** ✅ Production (v3.0.0+)
**Last Updated:** October 31, 2025
**Owner:** Backend Engineering
**Related Docs:**
- Parent: [Canonical Data Contracts PRD](Canonical-Data-Contracts-PRD.md)
- Code: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`

---

## Problem Statement

**Core Pain Point:**
Different book providers use wildly different genre naming conventions:
- Google Books: `["Fiction", "Thrillers", "MYSTERY"]` (mixed case, plural)
- OpenLibrary: `["thriller", "fiction", "suspense"]` (lowercase, descriptive)
- Gemini AI: `["Sci-fi dystopia", "Post-apocalyptic fiction"]` (free-form)

iOS library filters couldn't reliably match books by genre. Searching for "Thriller" wouldn't find books tagged "Thrillers" or "thriller" or "Suspense".

**User Impact:**
- Duplicate genre tags in library ("Fiction" vs "fiction" vs "FICTION")
- Broken genre filters (search "Science Fiction" misses "Sci-Fi")
- Inconsistent reading statistics (genre counts split across variations)

**Why Now:**
- Canonical data contracts launching (need consistent DTOs)
- Multiple providers planned (Google Books, OpenLibrary, ISBNDB, Gemini AI)
- iOS DTOMapper ready to consume normalized genres

---

## Solution Overview

Backend service normalizes all genre strings to canonical values BEFORE sending to iOS. Single source of truth: `CANONICAL_GENRES` map with ~30 common genres + fuzzy matching for variations.

**Key Features:**
1. **Canonical Genre Map:** Maps variations → canonical names (e.g., "Thrillers" → "Thriller")
2. **Provider-Specific Preprocessing:** Handles hierarchical genres (Google Books), descriptive subjects (OpenLibrary)
3. **Fuzzy Matching:** Levenshtein distance matching for typos ("Mystrey" → "Mystery")
4. **Pass-Through Unknown Genres:** Preserves niche genres (e.g., "Solarpunk") instead of dropping

---

## User Stories

**US-1: Genre Consistency**
As a user, I want all books tagged "Thriller" (not "Thrillers", "thriller", "Suspense"), so library filters work reliably.
- **AC:** Google Books `"Thrillers"` → `"Thriller"`, OpenLibrary `"thriller"` → `"Thriller"`
- **Implementation:** `CANONICAL_GENRES['Thriller'] = ['Thriller', 'Suspense']`

**US-2: Hierarchical Genre Support**
As a user searching for science fiction, I want books tagged "Fiction / Science Fiction / Dystopian" normalized to ["Science Fiction", "Dystopian", "Fiction"].
- **AC:** Google Books hierarchical genres split into canonical tags
- **Implementation:** `PROVIDER_MAPPINGS['Fiction / Science Fiction / Dystopian']`

**US-3: Fuzzy Matching**
As a developer, I want typos like "Mystrey" auto-corrected to "Mystery", so data quality improves without manual fixes.
- **AC:** Levenshtein distance 85%+ similarity → canonical match
- **Implementation:** `findFuzzyMatch()` with 0.85 threshold

---

## Technical Implementation

**File:** `genre-normalizer.ts`

**Core Logic:**
```typescript
normalize(rawGenres: string[], provider: string): string[] {
  1. Preprocess (provider-specific rules)
  2. Check exact match (PROVIDER_MAPPINGS)
  3. Check canonical variations (CANONICAL_GENRES)
  4. Fuzzy match (Levenshtein distance ≥85%)
  5. Pass-through if no match (preserve unknown genres)
  6. Deduplicate & sort alphabetically
}
```

**Canonical Map (Sample):**
```typescript
const CANONICAL_GENRES = {
  'Science Fiction': ['Sci-Fi', 'Science Fiction', 'SF', 'Scifi'],
  'Thriller': ['Thriller', 'Suspense'],
  'Mystery': ['Mystery', 'Detective', 'Whodunit', 'Mystrey'],
  'Classics': ['Classic', 'Classics', 'Classical'],
  // ... 30+ genres
};
```

**Provider Mappings (Google Books):**
```typescript
const PROVIDER_MAPPINGS = {
  'Fiction / Science Fiction / General': ['Science Fiction', 'Fiction'],
  'Fiction / Science Fiction / Dystopian': ['Science Fiction', 'Dystopian', 'Fiction'],
  'Fiction / Thrillers / General': ['Thriller', 'Fiction'],
  // ... 20+ mappings
};
```

**Integration:** Applied in all `/v1/*` search endpoints:
- `normalizeGoogleBooksToWork()` calls `genreNormalizer.normalize(volumeInfo.categories, 'google-books')`
- Result stored in `WorkDTO.subjectTags`

---

## Success Metrics

- ✅ **100% genre consistency:** "Thriller" (not "Thrillers", "thriller", "Suspense")
- ✅ **30+ canonical genres mapped:** Fiction, Science Fiction, Mystery, Thriller, etc.
- ✅ **Zero data loss:** Unknown genres pass through unchanged (e.g., "Solarpunk")
- ✅ **85% fuzzy match threshold:** "Mystrey" → "Mystery"

---

## Decision Log

### [October 28, 2025] Decision: Backend Normalization Over iOS

**Rationale:** Single source of truth, consistent for all clients (iOS, future Android), easier debugging.

### [October 28, 2025] Decision: Pass-Through Unknown Genres

**Rationale:** Preserves niche genres (Solarpunk, LitRPG), allows genre discovery via logs, no data loss.

### [October 28, 2025] Decision: Fuzzy Matching with 85% Threshold

**Rationale:** Catches common typos ("Mystrey"), avoids false positives (85% is strict enough).

---

## Future Enhancements

1. **Expand Genre Map:** Add 100+ genres (LitRPG, Cozy Mystery, Urban Fantasy)
2. **Genre Hierarchy:** Parent-child relationships (Fiction > Mystery > Detective)
3. **AI-Assisted Genre Tagging:** Use Gemini to suggest genres for untagged books

---

**PRD Status:** ✅ Complete
**Implementation:** ✅ Production (v3.0.0)
