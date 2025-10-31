# CloudKit Sync - Product Requirements Document

**Status:** Shipped
**Owner:** iOS Engineering Team
**Target Release:** v3.0.0 (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

CloudKit Sync provides automatic, zero-configuration library synchronization across devices (iPhone, iPad) using SwiftData's native CloudKit integration. Users seamlessly switch between devices while maintaining consistent library data without manual export/import.

---

## Problem Statement

**User Need:** Sync library across iPhone and iPad automatically.  
**Solution:** SwiftData CloudKit integration (zero config, Apple handles conflicts).

---

## Success Metrics

- ✅ Sync latency: 5-10s (network permitting)
- ✅ Zero data loss during conflicts
- ✅ Zero configuration required

---

## User Stories

**As a** user with iPhone + iPad, **I want** library synced automatically **so that** I can switch devices seamlessly.

**As a** user, **I want** reading progress synced **so that** I can pick up where I left off on any device.

---

## CloudKit Rules (Critical)

### Insert-Before-Relate Lifecycle
```swift
// ✅ CORRECT
let work = Work(title: "...", authors: [], ...)
modelContext.insert(work)  // Gets permanent ID

let author = Author(name: "...")
modelContext.insert(author)  // Gets permanent ID

work.authors = [author]  // Safe - both have permanent IDs
```

### Other Rules
- Inverse relationships on to-many side only
- All attributes need defaults
- All relationships optional
- Predicates can't filter on to-many (filter in-memory)

---

## Success Criteria (Shipped)

- ✅ Changes sync in 5-15s
- ✅ Zero crashes from temporary IDs (insert-before-relate enforced)
- ✅ Last-write-wins conflict resolution
- ✅ Local-only mode if not signed into iCloud

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
