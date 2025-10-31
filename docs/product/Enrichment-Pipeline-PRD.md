# Enrichment Pipeline - Product Requirements Document

**Status:** Shipped
**Owner:** iOS + Backend Engineering Teams
**Target Release:** v3.1.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

The Enrichment Pipeline is a background service that fetches complete book metadata (covers, genres, descriptions) after books are saved with minimal data. Books appear instantly in the library (<20s) while enrichment runs asynchronously, creating a responsive UX across CSV import, bookshelf scanning, and manual search.

---

## Problem Statement

**Before:** CSV import took 60-120s (inline enrichment blocked UI)  
**After:** Books appear in 12-17s, enrichment happens in background (1-5min)

---

## Success Metrics

- ✅ Books appear in <20s (vs 60-120s inline)
- ✅ Zero UI blocking during enrichment
- ✅ WebSocket real-time progress updates
- ✅ All import methods use same pipeline (CSV, bookshelf, manual)

---

## User Stories

**As a** user importing books, **I want** books to appear immediately **so that** I don't wait for slow enrichment.

**As a** user, **I want** covers and genres to load in background **so that** I can keep browsing.

---

## Architecture

```
iOS: EnrichmentQueue (Singleton)
  ├─ Queue Management (pending, in-progress, failed jobs)
  ├─ POST /api/enrichment/start with ISBN list
  └─ WebSocket /ws/progress for real-time updates

Backend: /api/enrichment/start
  ├─ For each ISBN: Fetch Google Books + OpenLibrary
  ├─ Send WebSocket "book X/Y" progress
  └─ Return enriched WorkDTOs
```

---

## Implementation Files

**iOS:** `EnrichmentQueue.swift`, `CSVImportService.swift`  
**Backend:** `enrichment.ts`, `ProgressWebSocketDO.ts`

---

## Success Criteria (Shipped)

- ✅ Books appear in 12-17s (CSV with 50 books)
- ✅ Backend job cancellation (Library Reset)
- ✅ WebSocket progress (8ms latency, 62x faster than polling)

---

**Status:** ✅ Shipped in v3.1.0 (Build 47+)
**Workflow:** See `docs/workflows/enrichment-workflow.md`
