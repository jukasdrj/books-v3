# DTOMapper - Product Requirements Document

**Status:** Shipped
**Owner:** iOS Engineering Team
**Target Release:** v3.1.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

DTOMapper is an iOS service that converts canonical backend DTOs (WorkDTO, EditionDTO, AuthorDTO) into SwiftData models (Work, Edition, Author), handling deduplication, relationship resolution, and insert-before-relate lifecycle compliance. By centralizing DTO-to-model conversion, the service eliminates duplicated parsing code across search, enrichment, and import features.

---

## Problem Statement

**Developer Pain:** iOS services (BookSearchAPIService, EnrichmentService, CSV import) each manually converted DTOs to SwiftData models, duplicating 100+ lines of code and creating inconsistent deduplication logic.

**Solution:** Single DTOMapper service converts DTOs → SwiftData models with automatic deduplication by ISBN and insert-before-relate pattern enforcement.

---

## Success Metrics

- ✅ Zero manual DTO parsing in iOS services (100+ lines removed from BookSearchAPIService)
- ✅ 100% deduplication success (5 EditionDTOs → 1 Work with 5 Editions)
- ✅ Genre normalization preserved in SwiftData models

---

## Key Features

### Deduplication by ISBN
- Groups WorkDTOs by shared ISBNs
- Merges synthetic Works into real Works
- Deletes duplicate Work instances

### Insert-Before-Relate Compliance
- Calls `modelContext.insert()` immediately after creating models
- Sets relationships AFTER both entities have permanent IDs
- Prevents "temporary identifier" crashes

### Relationship Management
- Maps WorkDTO → Work, EditionDTO → Edition, AuthorDTO → Author
- Sets bidirectional relationships (work.authors, author.works)
- Handles Work.editions, Edition.work correctly

---

## Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DTOMapper.swift`

**Key Methods:**
- `mapToWorks(from response: CanonicalSearchResponse, modelContext: ModelContext) -> [Work]`
- `deduplicateSyntheticWorks(_ works: [Work]) -> [Work]`
- `insertAuthors(_ dtos: [AuthorDTO], modelContext: ModelContext) -> [Author]`

**Usage:**
```swift
// Before (manual parsing):
let work = Work(title: dto.title, authors: [], ...)
modelContext.insert(work)
// ... 50+ lines of field mapping

// After (DTOMapper):
let works = dtoMapper.mapToWorks(from: response, modelContext: modelContext)
```

---

## Decision Log

**Decision:** Single DTOMapper Class (Not Per-Feature)  
**Rationale:** Centralize conversion logic, ensure consistent deduplication, easier testing

**Decision:** Deduplicate by ISBN (Not Title)  
**Rationale:** ISBNs most reliable unique identifier, handles synthetic Works from Google Books

---

## Success Criteria (Shipped)

- ✅ DTOMapper integrated in BookSearchAPIService, EnrichmentService, BookshelfScannerService
- ✅ Deduplication working (synthetic Works merged by ISBN)
- ✅ Insert-before-relate pattern enforced (zero crashes)
- ✅ 120+ lines of manual parsing code removed

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
