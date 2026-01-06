# DTOMapper Integration - Product Requirements Document

**Feature:** iOS DTO-to-SwiftData Mapper Service
**Status:** ✅ Production (v3.0.0+)
**Last Updated:** October 31, 2025
**Owner:** iOS Engineering
**Related Docs:**
- Parent: [Canonical Data Contracts PRD](Canonical-Data-Contracts-PRD.md)
- Code: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`

---

## Problem Statement

**Core Pain Point:**
iOS received canonical DTOs (`WorkDTO`, `EditionDTO`, `AuthorDTO`) from `/v1/*` endpoints but needed to convert them to SwiftData models (`Work`, `Edition`, `Author`). Every search/enrichment service duplicated this conversion logic.

**Specific Issues:**
1. **Duplicated Conversion Logic:** 3+ services had copy-pasted DTO → model code
2. **Synthetic Work Deduplication:** Google Books returns 5 editions → iOS should show 1 work with 5 editions
3. **Insert-Before-Relate Lifecycle:** SwiftData requires `modelContext.insert()` BEFORE setting relationships (crashes with temporary IDs)
4. **Genre Normalization Pass-Through:** Backend normalizes genres, iOS must preserve them (no re-normalization)

**Why Now:**
- Canonical contracts launched (DTOs ready)
- Multiple features consume DTOs (search, enrichment, bookshelf scanner)
- Deduplication logic complex (needs centralized service)

---

## Solution Overview

Single `DTOMapper` service converts canonical DTOs to SwiftData models with:
1. **Insert-Before-Relate Pattern:** Always `insert()` before setting relationships
2. **Synthetic Work Deduplication:** Group by ISBN, merge editions under single work
3. **Genre Preservation:** Apply `workDTO.subjectTags` directly (backend already normalized)
4. **Provenance Tracking:** Store `primaryProvider` for debugging

---

## User Stories

**US-1: Zero Duplicate Conversion Logic**
As an iOS developer, I want a single service to convert DTOs to models, so search/enrichment services don't duplicate logic.
- **AC:** `BookSearchAPIService`, `EnrichmentService`, `BookshelfScannerService` all call `DTOMapper.mapToWorks()`
- **Implementation:** `DTOMapper.swift` (centralized service)

**US-2: Synthetic Work Deduplication**
As a user, I want 5 editions of "The Great Gatsby" merged into 1 work, so my library doesn't show duplicates.
- **AC:** Google Books returns 5 `WorkDTO` (all `synthetic: true`, same ISBN) → iOS shows 1 work with 5 editions
- **Implementation:** `deduplicateSyntheticWorks()` groups by ISBN

**US-3: Genre Normalization Pass-Through**
As a user, I want genres normalized by backend (not iOS), so genre tags are consistent across all clients.
- **AC:** `workDTO.subjectTags = ["Fiction", "Thriller"]` → `work.subjectTags = ["Fiction", "Thriller"]` (no iOS normalization)
- **Implementation:** Direct assignment in `mapToWorks()`

---

## Technical Implementation

**File:** `DTOMapper.swift`

**Core Methods:**
```swift
func mapToWorks(data: SearchResponseData, modelContext: ModelContext) -> [Work] {
    var works: [Work] = []

    for workDTO in data.works {
        // 1. Create Work model
        let work = Work(title: workDTO.title, ...)
        modelContext.insert(work) // Insert BEFORE relating!

        // 2. Apply genre normalization (already done by backend)
        work.subjectTags = workDTO.subjectTags

        // 3. Create Author models
        let authors = insertAuthors(data.authors, modelContext)
        work.authors = authors // Safe - both have permanent IDs

        // 4. Create Edition models
        let editions = insertEditions(data.editions, modelContext, work)
        work.editions = editions

        works.append(work)
    }

    // 5. Deduplicate synthetic works
    return deduplicateSyntheticWorks(works, data.editions)
}

private func deduplicateSyntheticWorks(_ works: [Work], _ editions: [EditionDTO]) -> [Work] {
    let syntheticWorks = works.filter { $0.synthetic == true }
    let grouped = Dictionary(grouping: syntheticWorks, by: { work in
        // Group by ISBN (from editions)
        editions.first { $0.workId == work.id }?.isbn ?? ""
    })

    var deduplicated: [Work] = []
    for (isbn, duplicateWorks) in grouped where duplicateWorks.count > 1 {
        // Merge editions into first work, delete rest
        let primaryWork = duplicateWorks[0]
        for work in duplicateWorks.dropFirst() {
            primaryWork.editions.append(contentsOf: work.editions)
            modelContext.delete(work)
        }
        deduplicated.append(primaryWork)
    }

    return works.filter { $0.synthetic == false } + deduplicated
}
```

**Integration Points:**
- **SearchView:** Calls `BookSearchAPIService.searchByTitle()` → `DTOMapper.mapToWorks()`
- **EnrichmentQueue:** Background enrichment calls `/v1/search/isbn` → `DTOMapper.mapToWorks()`
- **BookshelfScanner:** AI-detected ISBNs call `/v1/search/isbn` → `DTOMapper.mapToWorks()`

---

## Success Metrics

- ✅ **Zero duplicate conversion logic:** Single `mapToWorks()` used by 3+ services
- ✅ **100% deduplication success:** 5 synthetic works → 1 work with 5 editions
- ✅ **Zero insert-before-relate crashes:** Always `insert()` before setting relationships
- ✅ **Genre normalization preserved:** Backend genres flow to SwiftData unchanged

---

## Decision Log

### [October 29, 2025] Decision: Single DTOMapper Service

**Rationale:** Centralize conversion logic, easier to test, consistent insert-before-relate enforcement.

### [October 29, 2025] Decision: Deduplicate by ISBN

**Rationale:** Most reliable unique identifier for editions, handles synthetic works from Google Books.

### [October 29, 2025] Decision: No iOS Genre Normalization

**Rationale:** Backend already normalizes, iOS just applies directly (single source of truth).

---

## Future Enhancements

1. **Provenance Tracking:** Store `primaryProvider` in SwiftData models (debug view)
2. **Fuzzy Title Deduplication:** Handle typos (e.g., "The Great Gatbsy" → "The Great Gatsby")
3. **Merge Conflict Resolution:** UI to resolve duplicate works manually

---

**PRD Status:** ✅ Complete
**Implementation:** ✅ Production (v3.0.0)
