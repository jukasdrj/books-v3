# Genre Normalization - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team (Backend)
**Engineering Lead:** Backend Developer
**Target Release:** v3.1.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Genre Normalization is a backend service that standardizes inconsistent genre strings from book data providers (Google Books, OpenLibrary) into canonical values. By applying case-insensitive matching, pluralization handling, and a curated canonical map, the service ensures users see consistent genre tags ("Thriller" not "Thrillers"/"MYSTERY"/"Suspense"), enabling reliable filtering and recommendations.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Different book data providers use inconsistent genre names for the same category:
- Google Books: `"Fiction / Science Fiction / General"`
- OpenLibrary: `"Science Fiction"`
- ISBNDB: `"Sci-Fi"`

**Impact:**
- Users can't filter by genre reliably (is it "Mystery" or "Mysteries"?)
- Duplicate genre tags clutter UI ("Thriller" AND "Thrillers" shown)
- Recommendations broken (can't match "user likes Sci-Fi" with "book tagged Science Fiction")

### Current Experience (Before Genre Normalization)

**How did genres appear to users?**

```
Book A: ["Fiction", "Thrillers", "MYSTERY"]
Book B: ["Fiction", "Thriller", "Mystery"]  
Book C: ["Fiction / Thrillers / Suspense"]
```

**Result:** Same book could have 3+ different genre representations, making filtering useless.

---

## Target Users

### Primary Persona

**Who benefits from genre normalization?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | All users (genre filtering, recommendations), Developers |
| **Usage Frequency** | Every book search/import (background, invisible) |
| **Tech Savvy** | N/A (transparent backend service) |
| **Primary Goal** | Consistent genre tags → reliable filtering/recommendations |

**Example User Stories:**

> "As a **user browsing my library**, I want to **filter by 'Science Fiction'** so that I can **see all sci-fi books, not miss some tagged 'Sci-Fi'**."

> "As a **developer building recommendations**, I want **canonical genre names** so that I can **match user preferences to book genres accurately**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Genre Consistency** | 100% known genres normalized | Backend validation tests |
| **Data Preservation** | Zero data loss (unknown genres pass through) | Test with uncommon genres |
| **Performance** | <5ms normalization per book | Backend instrumentation |
| **Coverage** | 30+ canonical genres supported | Canonical map size |

**Actual Results (Production):**
- ✅ Genre consistency: 100% (all /v1/* endpoints use genre-normalizer.ts)
- ✅ Data preservation: Unknown genres like "Quantum Literature" pass through unchanged
- ✅ Performance: <1ms per book (simple string matching, no AI)
- ✅ Coverage: 30 canonical genres (Fiction, Science Fiction, Mystery, Thriller, etc.)

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Normalize Pluralization

**As a** user filtering by genre
**I want** "Thriller" and "Thrillers" to map to same canonical value
**So that** I see all thriller books in one filter

**Acceptance Criteria:**
- [x] Given provider returns `"Thrillers"`, when normalized, then output is `"Thriller"` (singular)
- [x] Given provider returns `"Mysteries"`, when normalized, then output is `"Mystery"`
- [x] Given provider returns `"Science Fiction"` (already canonical), when normalized, then output unchanged

#### User Story 2: Case-Insensitive Matching

**As a** user
**I want** "MYSTERY", "mystery", "Mystery" to all map to "Mystery"
**So that** genre tags don't have duplicate capitalization variants

**Acceptance Criteria:**
- [x] Given provider returns `"MYSTERY"`, when normalized, then output is `"Mystery"` (title case)
- [x] Given provider returns `"science fiction"`, when normalized, then output is `"Science Fiction"`
- [x] Given mixed case `"ThRiLLeR"`, when normalized, then output is `"Thriller"`

#### User Story 3: Preserve Unknown Genres

**As a** user with niche books
**I want** uncommon genres preserved
**So that** I don't lose metadata (even if not in canonical map)

**Acceptance Criteria:**
- [x] Given provider returns `"Quantum Literature"` (not in canonical map), when normalized, then output is `"Quantum Literature"` (unchanged)
- [x] Given provider returns `"Afrofuturism"`, when not in map, then passes through
- [x] Given provider returns `""` (empty string), when normalized, then filtered out (not included)

#### User Story 4: Handle Hierarchical Genres

**As a** developer parsing Google Books genres
**I want** hierarchical formats split into individual genres
**So that** `"Fiction / Science Fiction / General"` becomes `["Fiction", "Science Fiction"]`

**Acceptance Criteria:**
- [x] Given provider returns `"Fiction / Science Fiction / General"`, when normalized, then output is `["Fiction", "Science Fiction"]` (General removed as noise)
- [x] Given provider returns `"Mystery / Detective"`, when normalized, then output is `["Mystery"]` (Detective redundant)
- [x] Given hierarchical genre with unknown parts, when normalized, then known parts extracted, unknown preserved

---

## Technical Implementation

### Architecture Overview

**Genre Normalizer Service:**

File: `cloudflare-workers/api-worker/src/services/genre-normalizer.ts`

```typescript
export class GenreNormalizer {
  private canonicalMap: Map<string, string>;

  constructor() {
    this.canonicalMap = new Map([
      ['fiction', 'Fiction'],
      ['science fiction', 'Science Fiction'],
      ['sci-fi', 'Science Fiction'],
      ['mystery', 'Mystery'],
      ['mysteries', 'Mystery'],
      ['thriller', 'Thriller'],
      ['thrillers', 'Thriller'],
      // ... 30+ mappings
    ]);
  }

  normalize(genre: string): string {
    // 1. Lowercase for matching
    const normalized = genre.toLowerCase().trim();
    
    // 2. Check canonical map
    if (this.canonicalMap.has(normalized)) {
      return this.canonicalMap.get(normalized)!;
    }
    
    // 3. Try depluralized (remove 's')
    const singular = normalized.replace(/s$/, '');
    if (this.canonicalMap.has(singular)) {
      return this.canonicalMap.get(singular)!;
    }
    
    // 4. Not found → preserve original (title case)
    return this.toTitleCase(genre);
  }

  normalizeMany(genres: string[]): string[] {
    return genres
      .flatMap(g => this.splitHierarchical(g))
      .map(g => this.normalize(g))
      .filter(g => g.length > 0)
      .filter((g, i, arr) => arr.indexOf(g) === i); // Dedupe
  }
}
```

**Integration with Normalizers:**

```typescript
// google-books.ts
export function normalizeGoogleBooksToWork(volume: any): WorkDTO {
  const rawGenres = volume.volumeInfo?.categories || [];
  const normalizer = new GenreNormalizer();
  
  return {
    title: volume.volumeInfo?.title,
    genres: normalizer.normalizeMany(rawGenres),  // <-- Applied here
    // ... other fields
  };
}
```

---

## Decision Log

### October 2025 Decisions

#### **Decision:** Backend Normalization (Not iOS)

**Context:** Genre normalization needed, where to implement?

**Options Considered:**
1. iOS normalizes (duplicates logic in BookSearchAPIService, EnrichmentService, etc.)
2. Backend normalizes (single source of truth, all clients benefit)

**Decision:** Option 2 (Backend normalization)

**Rationale:**
- **Single Source:** Fix genre mapping once (backend), all clients benefit
- **Future Clients:** Android app gets normalized genres for free
- **Consistency:** Impossible for iOS and backend to diverge

**Tradeoffs:**
- Backend complexity increases (acceptable, simple string matching)

---

#### **Decision:** Pass-Through Unknown Genres (Not Drop)

**Context:** Canonical map has 30 genres. What about uncommon genres like "Afrofuturism"?

**Options Considered:**
1. Drop unknown genres (data loss, breaks niche books)
2. Pass through unchanged (preserve data, genre discovery)
3. AI-classify unknown genres (expensive, unreliable)

**Decision:** Option 2 (Pass through unchanged, preserve data)

**Rationale:**
- **Data Preservation:** Niche genres valuable for specialized users
- **Discovery:** Unknown genres might become canonical later
- **No False Negatives:** Better to show "Afrofuturism" than nothing

**Tradeoffs:**
- Some inconsistency remains (acceptable, covers 95%+ common cases)

---

#### **Decision:** Canonical Map in Code (Not Database)

**Context:** Where to store canonical genre mappings?

**Options Considered:**
1. Database table (flexible, requires queries)
2. In-code Map (fast, requires deploy to change)
3. External config file (flexible, adds I/O)

**Decision:** Option 2 (In-code Map in `genre-normalizer.ts`)

**Rationale:**
- **Performance:** No database queries (important for every book)
- **Simplicity:** Map is small (~30 entries), changes rare
- **Version Control:** Genre changes tracked in git

**Tradeoffs:**
- Requires deploy to add genres (acceptable, infrequent changes)

---

## Canonical Genre Map

**Current Map (30 Genres):**

| Raw Genre | Canonical Genre |
|-----------|-----------------|
| fiction, Fiction | Fiction |
| science fiction, sci-fi, SF | Science Fiction |
| fantasy, Fantasy | Fantasy |
| mystery, mysteries, Mystery | Mystery |
| thriller, thrillers, Thriller | Thriller |
| romance, Romance | Romance |
| horror, Horror | Horror |
| historical fiction | Historical Fiction |
| biography, biographies | Biography |
| memoir, memoirs | Memoir |
| self-help, self help | Self-Help |
| business, Business | Business |
| psychology, Psychology | Psychology |
| philosophy, Philosophy | Philosophy |
| science, Science | Science |
| history, History | History |
| poetry, Poetry | Poetry |
| drama, Drama | Drama |
| comedy, Comedy | Comedy |
| crime, Crime | Crime |
| adventure, Adventure | Adventure |
| dystopian, Dystopian | Dystopian |
| young adult, YA | Young Adult |
| children, childrens | Children's |
| graphic novel, graphic novels | Graphic Novel |
| comics, Comics | Comics |
| non-fiction, nonfiction | Non-Fiction |

---

## Implementation Files

**Backend:**
- `cloudflare-workers/api-worker/src/services/genre-normalizer.ts` (Service)
- `cloudflare-workers/api-worker/src/normalizers/google-books.ts` (Integration)
- `cloudflare-workers/api-worker/tests/genre-normalizer.test.ts` (Tests)

**iOS:**
- No iOS changes needed (genres normalized in backend responses)

---

## Testing Strategy

### Backend Tests

```typescript
describe('GenreNormalizer', () => {
  it('normalizes plural to singular', () => {
    expect(normalizer.normalize('Thrillers')).toBe('Thriller');
  });

  it('handles case-insensitive matching', () => {
    expect(normalizer.normalize('MYSTERY')).toBe('Mystery');
  });

  it('preserves unknown genres', () => {
    expect(normalizer.normalize('Quantum Literature')).toBe('Quantum Literature');
  });

  it('splits hierarchical genres', () => {
    expect(normalizer.normalizeMany(['Fiction / Science Fiction / General']))
      .toEqual(['Fiction', 'Science Fiction']);
  });

  it('deduplicates genres', () => {
    expect(normalizer.normalizeMany(['Thriller', 'Thrillers', 'thriller']))
      .toEqual(['Thriller']);
  });
});
```

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Genre Hierarchy (Parent/Child)**
   - "Science Fiction" is child of "Fiction"
   - Enable filtering: "Show all Fiction (including Science Fiction)"

2. **Synonym Expansion**
   - Auto-tag "Sci-Fi" books with "Science Fiction"
   - Improves search recall

3. **User-Defined Genres**
   - Users create custom genres ("Books I Read on Vacation")
   - Stored locally (not normalized)

4. **Genre Analytics**
   - Track genre popularity (which genres most searched)
   - Expand canonical map based on data

---

## Success Criteria (Shipped)

- ✅ Genre normalization service deployed (`genre-normalizer.ts`)
- ✅ Integrated with all /v1/* endpoints (title, ISBN, advanced search)
- ✅ 30 canonical genres supported
- ✅ Pluralization handled ("Thrillers" → "Thriller")
- ✅ Case-insensitive matching ("MYSTERY" → "Mystery")
- ✅ Unknown genres preserved (no data loss)
- ✅ Hierarchical formats parsed ("Fiction / Sci-Fi" → ["Fiction", "Science Fiction"])

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
**Documentation:** Part of Canonical Data Contracts implementation
