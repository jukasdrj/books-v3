# Search (Title/ISBN/Advanced) - Product Requirements Document

**Status:** Shipped
**Owner:** iOS + Backend Engineering Teams
**Target Release:** v3.1.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Search provides three modes for finding books: Title search (quick lookup by book name), ISBN search (exact edition match via barcode or manual entry), and Advanced search (combined title + author filtering). Powered by canonical backend APIs, search delivers consistent results from Google Books with genre normalization and provenance tracking built-in.

---

## Problem Statement

**User Need:** Users want to find books quickly by title ("Dune"), exact ISBN (barcode scan), or combined filters (title + author for disambiguation).

**Before Canonical Contracts:** Search responses inconsistent (raw Google Books JSON), manual genre parsing, no provenance.

**After Canonical Contracts:** Clean DTOs, normalized genres, fast results (<2s cached).

---

## Success Metrics

- ✅ Search results appear in <2s (cached queries)
- ✅ 95%+ search success rate (non-empty results)
- ✅ Zero crashes from malformed ISBNs

---

## User Stories

### Title Search
**As a** user, **I want to** search by book title **so that** I can find books quickly.

**Acceptance:**
- [x] Type "Dune" → Results appear in <2s
- [x] Results sorted by relevance (Google Books algorithm)
- [x] Genre tags normalized ("Science Fiction" not "Sci-Fi")

### ISBN Search
**As a** user, **I want to** search by ISBN **so that** I can add exact editions.

**Acceptance:**
- [x] Scan barcode → ISBN extracted → Search triggered
- [x] Invalid ISBN (wrong length) → Validation error shown
- [x] Valid ISBN → Book detail appears

### Advanced Search
**As a** user, **I want to** search by title + author **so that** I can disambiguate common titles.

**Acceptance:**
- [x] Search "Foundation" + "Asimov" → Filters out unrelated books
- [x] Either field optional (title-only or author-only works)

---

## API Specification

### GET /v1/search/title?q={query}
**Response:** `{ success, data: { works: WorkDTO[], authors: AuthorDTO[] }, meta }`

### GET /v1/search/isbn?isbn={isbn}
**Validation:** ISBN-10 or ISBN-13 format
**Response:** Single WorkDTO or error

### GET /v1/search/advanced?title={title}&author={author}
**Response:** Filtered WorkDTOs matching both criteria

---

## Implementation Files

**iOS:**
- `SearchView.swift` (UI with 3 search modes)
- `SearchModel.swift` (@Observable state machine)
- `BookSearchAPIService.swift` (Calls /v1/* endpoints)

**Backend:**
- `search-title.ts`, `search-isbn.ts`, `search-advanced.ts` handlers

---

## Success Criteria (Shipped)

- ✅ All 3 search modes working (title, ISBN, advanced)
- ✅ Canonical DTOs consumed (zero raw Google Books parsing)
- ✅ Genre normalization flows to UI
- ✅ Provenance tracking (primaryProvider field)

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
**Workflow:** See `docs/workflows/search-workflow.md`
