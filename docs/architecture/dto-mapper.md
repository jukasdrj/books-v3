# DTO-to-SwiftData Mapper Service (DTOMapper)

**Component:** `DTOMapper`
**Status:** ✅ Production (v3.0.0+)
**Implementation:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`

---

## Overview

The `DTOMapper` is a centralized service responsible for converting canonical Data Transfer Objects (DTOs) from the `/v1/*` and `/v3/*` endpoints into SwiftData models (`Work`, `Edition`, `Author`). It solves the critical problem of deduplication and relationship management that was previously scattered across multiple services.

## Core Responsibilities

1.  **Conversion:** Transforms `WorkDTO`, `EditionDTO`, and `AuthorDTO` into SwiftData `@Model` classes.
2.  **Deduplication:** Merges "synthetic" works (e.g., from Google Books) that share the same ISBN into a single logical `Work`.
3.  **Lifecycle Management:** Enforces the "Insert-Before-Relate" pattern to prevent SwiftData crashes.
4.  **Genre Preservation:** Passes through backend-normalized genre tags without client-side modification.

## Key Patterns

### Insert-Before-Relate
SwiftData requires objects to be inserted into the `ModelContext` before relationships are established, especially when using temporary IDs. The mapper strictly follows this sequence:
1.  Initialize `Work`
2.  `context.insert(work)`
3.  Initialize and insert `Author`s
4.  Set `work.authors`
5.  Initialize and insert `Edition`s
6.  Set `work.editions`

### Synthetic Work Deduplication
When search providers (like Google Books) return multiple entries for the same book (different editions), the backend flags them as `synthetic: true`. The mapper:
1.  Groups these works by ISBN.
2.  Merges all editions into the first work.
3.  Deletes the redundant work objects from the context.
4.  Returns a clean list of unique works.

## Usage

```swift
// In Search Service
let works = DTOMapper.mapToWorks(data: searchResponse, modelContext: context)

// In Bookshelf Scanner
let scannedWorks = DTOMapper.mapToWorks(data: enrichmentResponse, modelContext: context)
```

## Data Flow

1.  **Input:** `SearchResponseData` (contains arrays of `WorkDTO`, `EditionDTO`, `AuthorDTO`).
2.  **Process:**
    *   Iterate through `WorkDTO`s.
    *   Create and insert `Work` models.
    *   Resolve and link `Author` models (reusing existing authors if found).
    *   Resolve and link `Edition` models.
    *   Perform deduplication pass.
3.  **Output:** `[Work]` (persistent SwiftData objects).

## Provenance & Debugging

*   **Genre Normalization:** The mapper does *not* normalize genres. It trusts the `subjectTags` array from the DTO, which is normalized by the backend.
*   **Primary Provider:** The `primaryProvider` field is mapped to help debug which source (Google, OpenLibrary, etc.) contributed the metadata.
