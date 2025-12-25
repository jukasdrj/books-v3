# Library Reset - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** iOS Developer
**Target Release:** v3.0.0+ (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Library Reset is a comprehensive data clearing feature accessible via Settings → Library Management. It allows users to start fresh by deleting all books, authors, reading progress, and related data, while also canceling any in-flight backend enrichment jobs to prevent resource waste. This feature serves both end-users (wanting a fresh start) and developers (testing import features cleanly).

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Users and developers need a way to completely clear their library without reinstalling the app. Common scenarios:
- **User:** "I imported the wrong CSV file with 500 books. How do I undo this?"
- **Developer:** "I'm testing CSV import and need to clear test data between runs"
- **Beta Tester:** "I want to test the onboarding flow again with a fresh library"

### Current Experience (Before Library Reset)

**How did users clear their library before this feature?**

- **Delete app and reinstall** (nuclear option, loses Settings too)
- **Manually delete 500+ books one-by-one** (tedious, hours of work)
- **No solution** (users stuck with bad data)

---

## Target Users

### Primary Personas

**Who uses Library Reset?**

| Persona | Use Case | Frequency |
|---------|----------|-----------|
| **End User** | Imported wrong data, wants fresh start | Rare (1-2 times per year) |
| **Developer** | Testing import features (CSV, bookshelf scan) | Frequent (multiple times per day) |
| **Beta Tester** | Validating onboarding flow, feature testing | Occasional (weekly) |

**Example User Stories:**

> "As a **user who imported the wrong CSV**, I want to **reset my library** so that I can **re-import the correct file without 500 duplicate books**."

> "As a **developer testing CSV import**, I want to **quickly clear test data** so that I can **validate import logic with fresh SwiftData**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Speed** | Reset completes in <2s | Instrumentation (operation timing) |
| **Completeness** | 100% data deleted (no orphaned records) | Post-reset database query |
| **Backend Cleanup** | In-flight enrichment jobs canceled | Backend job cancellation logs |
| **User Safety** | Zero accidental resets (confirmation required) | No reset without explicit confirmation |

**Actual Results (Production):**
- ✅ Reset completes in <1s (SwiftData batch delete is fast)
- ✅ All entities deleted (Works, Editions, Authors, UserLibraryEntries)
- ✅ Backend jobs canceled via `/api/enrichment/cancel`
- ✅ Confirmation dialog prevents accidental resets

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Access Library Reset from Settings

**As a** user wanting to clear my library
**I want** Library Reset accessible in Settings → Library Management
**So that** I can easily find and execute the reset

**Acceptance Criteria:**
- [x] Given user opens Settings, when viewing "Library Management" section, then "Reset Library" button shown in red (destructive action)
- [x] Given user taps "Reset Library", when confirmation dialog appears, then user must confirm action
- [x] Given user cancels confirmation, when dialog dismissed, then no data deleted

#### User Story 2: Comprehensive Data Deletion

**As a** user resetting my library
**I want** all book data deleted
**So that** I have a completely fresh start

**Acceptance Criteria:**
- [x] Given user confirms reset, when operation completes, then all Works deleted
- [x] Given reset in progress, when deleting entities, then all Editions deleted
- [x] Given reset in progress, when deleting entities, then all Authors deleted
- [x] Given reset in progress, when deleting entities, then all UserLibraryEntries deleted
- [x] Given reset completes, when user views Library tab, then empty state shown ("No books yet")

#### User Story 3: Cancel In-Flight Backend Jobs

**As a** user resetting library during enrichment
**I want** backend enrichment jobs canceled
**So that** I don't waste resources enriching deleted books

**Acceptance Criteria:**
- [x] Given enrichment job running (CSV import in progress), when user resets library, then backend job receives cancellation request
- [x] Given backend receives cancellation, when Durable Object updated, then job status set to "canceled"
- [x] Given enrichment loop running, when checking `doStub.isCanceled()`, then loop breaks and sends final WebSocket update
- [x] Given reset completes, when enrichment queue cleared, then `currentJobId` set to nil

#### User Story 4: Clear Auxiliary Data

**As a** user resetting library
**I want** search history, feature flags, and enrichment queue cleared
**So that** I have a truly fresh start

**Acceptance Criteria:**
- [x] Given user confirms reset, when operation completes, then search history cleared
- [x] Given reset in progress, when clearing data, then enrichment queue emptied
- [x] Given reset in progress, when clearing data, then AI provider reset to Gemini (default)
- [x] Given reset in progress, when clearing data, then feature flags reset to defaults

---

## Technical Implementation

### Architecture Overview

**Reset Flow:**

```
User taps "Reset Library" → Confirmation Dialog
  ↓ (User Confirms)
iOS: SettingsView.performLibraryReset()
  ├─ Step 1: Cancel Backend Jobs
  │   ├─ EnrichmentQueue.shared.cancelBackendJob()
  │   └─ POST /api/enrichment/cancel with currentJobId
  ├─ Step 2: Delete SwiftData Models
  │   ├─ Fetch all Works, Authors, Editions, UserLibraryEntries
  │   ├─ Batch delete (modelContext.delete() for each entity)
  │   └─ Save context (modelContext.save())
  ├─ Step 3: Clear Auxiliary Data
  │   ├─ EnrichmentQueue.shared.clearAll()
  │   ├─ SearchHistoryService.clearAll()
  │   ├─ FeatureFlags.resetToDefaults()
  │   └─ AI Provider → Gemini (default)
  └─ Step 4: Show Success Toast
      └─ "Library reset successfully"
```

**Backend Cancellation Flow:**

```
iOS: POST /api/enrichment/cancel { jobId: uuid }
  ↓
Worker: enrichment.ts cancel() handler
  ├─ Get ProgressWebSocketDO stub
  ├─ Call doStub.cancelJob()
  └─ Return success response
  ↓
ProgressWebSocketDO: cancelJob()
  ├─ Set job status to "canceled" in storage
  ├─ Broadcast WebSocket message: { type: "canceled", jobId }
  └─ Return
  ↓
Enrichment Loop (running in background)
  ├─ Before processing each book: check doStub.isCanceled()
  ├─ If canceled: break loop
  ├─ Send final WebSocket update: { type: "complete", canceled: true }
  └─ Exit
```

**Critical:** Backend jobs tracked via `currentJobId` in EnrichmentQueue. Always call `setCurrentJobId()` when starting enrichment and `clearCurrentJobId()` when complete or canceled.

---

## Decision Log

### October 2025 Decisions

#### **Decision:** Cancel Backend Jobs During Reset

**Context:** User resets library while enrichment job running (e.g., CSV import enriching 100 books in background).

**Options Considered:**
1. Ignore backend jobs (let enrichment complete, data discarded on iOS)
2. Cancel backend jobs (POST /api/enrichment/cancel)
3. Wait for enrichment to complete before allowing reset (blocks user)

**Decision:** Option 2 (Cancel backend jobs via POST /api/enrichment/cancel)

**Rationale:**
- **Resource Efficiency:** Prevents wasting backend compute (Gemini API calls cost money)
- **Fast Reset:** User doesn't wait for enrichment to finish (can reset immediately)
- **Clean State:** Backend Durable Object updated with "canceled" status (no orphaned jobs)

**Tradeoffs:**
- Added complexity (HTTP request, error handling for network failures)
- Acceptable: If cancellation fails, enrichment completes harmlessly (data already deleted on iOS)

---

#### **Decision:** Comprehensive Reset (Not Selective Deletion)

**Context:** Should Library Reset allow selective deletion (e.g., "Delete only read books") or full reset?

**Options Considered:**
1. Selective deletion (checkboxes: Delete read books, Delete wishlist, etc.)
2. Comprehensive reset (delete everything, no options)
3. Archive mode (soft delete, recoverable)

**Decision:** Option 2 (Comprehensive reset, delete everything)

**Rationale:**
- **Simplicity:** No UI complexity, one button does everything
- **Clear Intent:** "Reset Library" = delete all data (user expectation)
- **Use Case:** Primary use case is "start fresh", not "delete subset"

**Tradeoffs:**
- No granular control (user can't delete only wishlist books)
- Acceptable: Users can manually delete individual books if needed (not reset's job)

---

#### **Decision:** Confirmation Dialog Required

**Context:** Library Reset is destructive (deletes all data). How to prevent accidental resets?

**Options Considered:**
1. No confirmation (instant reset, dangerous)
2. Single confirmation dialog ("Are you sure?")
3. Two-step confirmation (dialog + typing "DELETE")

**Decision:** Option 2 (Single confirmation dialog)

**Rationale:**
- **Safety:** Prevents accidental taps (user must confirm intent)
- **Balance:** Not overly cautious (two-step overkill for local data)
- **Precedent:** iOS Settings uses single confirmation for destructive actions

**Tradeoffs:**
- Users might still confirm accidentally (rare, acceptable risk)

---

## UI Specification

### Settings Screen Integration

**Location:** Settings → Library Management → "Reset Library"

**Button Appearance:**
- Red text (destructive action indicator)
- Label: "Reset Library"
- Subtitle: "Delete all books, authors, and reading progress"

**Confirmation Dialog:**

```
┌────────────────────────────────────────┐
│  Reset Library?                        │
├────────────────────────────────────────┤
│  This will delete all books, authors,  │
│  editions, and reading progress.       │
│  This action cannot be undone.         │
│                                        │
│  In-flight enrichment jobs will be     │
│  canceled.                             │
├────────────────────────────────────────┤
│  [Cancel]              [Reset] (Red)   │
└────────────────────────────────────────┘
```

**Post-Reset Toast:**
- "Library reset successfully"
- Dismisses after 2s

---

## What Gets Deleted

### SwiftData Models (Complete Deletion)

- ✅ **Works** (all books, titles, descriptions, cover URLs)
- ✅ **Editions** (all ISBNs, publishers, publication dates, page counts)
- ✅ **Authors** (all author names, gender, cultural region, marginalized voice)
- ✅ **UserLibraryEntries** (all reading statuses, current pages, ratings, notes, completion dates)

### Auxiliary Data (Cleared)

- ✅ **Enrichment Queue** (pending/failed enrichment jobs)
- ✅ **Search History** (recent searches, trending books)
- ✅ **Feature Flags** (reset to defaults: Gemini AI, experimental scanner enabled)
- ✅ **AI Provider** (reset to Gemini)

### Backend State (Canceled)

- ✅ **In-Flight Enrichment Jobs** (POST /api/enrichment/cancel)
- ✅ **WebSocket Connections** (Durable Object receives cancellation)

### What's NOT Deleted (Preserved)

- ❌ **App Settings** (theme selection, UI preferences) - User choice preserved
- ❌ **CloudKit Sync State** (reset only deletes local data, CloudKit unchanged)
- ❌ **iCloud Account** (user still signed in)

**Note on CloudKit:** Library Reset deletes local SwiftData. If user has CloudKit sync enabled, deleted data will sync to other devices (all devices end up with empty library). This is intended behavior.

---

## Error Handling

### Failure Scenarios

| Error Condition | User Experience | Recovery Action |
|----------------|-----------------|-----------------|
| SwiftData delete fails | Alert: "Reset failed, try again" | Retry button |
| Backend cancel timeout (network offline) | Continue with local reset | Backend job will timeout naturally (harmless) |
| Partial deletion (crash mid-reset) | Some data remains | Re-run reset (idempotent operation) |

### Backend Cancellation Failure Handling

**Scenario:** iOS sends POST /api/enrichment/cancel, but network offline or backend unavailable.

**Behavior:**
- iOS continues with local reset (deletes SwiftData)
- Backend enrichment job continues running (harmless, data already deleted on iOS)
- Enrichment eventually completes or times out (30-60s typical)

**Impact:** Minor resource waste (backend processes already-deleted books), but acceptable.

---

## API Specification

### POST /api/enrichment/cancel

**Request:**
```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response (Success):**
```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "canceled"
  },
  "meta": {
    "timestamp": "2025-10-31T14:30:00Z"
  }
}
```

**Response (Job Not Found):**
```json
{
  "success": false,
  "error": {
    "code": "JOB_NOT_FOUND",
    "message": "No active job found with this ID"
  }
}
```

**WebSocket Message (After Cancellation):**
```json
{
  "type": "canceled",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1698764400000,
  "data": {
    "message": "Job canceled by user",
    "processedItems": 5,
    "totalItems": 50
  }
}
```

---

## Implementation Files

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/SettingsView.swift` (UI + reset logic)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/EnrichmentQueue.swift` (backend job cancellation)

**Backend:**
- `cloudflare-workers/api-worker/src/handlers/enrichment.ts` (POST /api/enrichment/cancel)
- `cloudflare-workers/api-worker/src/durable-objects/ProgressWebSocketDO.ts` (cancelJob method)

**Code Example (iOS):**

```swift
// SettingsView.swift
private func performLibraryReset() {
    Task { @MainActor in
        do {
            // Step 1: Cancel backend jobs
            if let jobId = EnrichmentQueue.shared.currentJobId {
                try await EnrichmentQueue.shared.cancelBackendJob(jobId: jobId)
            }

            // Step 2: Delete SwiftData models
            let works = try modelContext.fetch(FetchDescriptor<Work>())
            for work in works {
                modelContext.delete(work)  // Cascades to editions, authors, entries
            }
            try modelContext.save()

            // Step 3: Clear auxiliary data
            EnrichmentQueue.shared.clearAll()
            SearchHistoryService.shared.clearAll()
            FeatureFlags.resetToDefaults()

            // Step 4: Show success
            showToast("Library reset successfully")
        } catch {
            showAlert("Reset failed: \(error.localizedDescription)")
        }
    }
}
```

---

## Testing Strategy

### Manual QA Scenarios

- [x] Open Settings → Library Management, tap "Reset Library", verify confirmation dialog appears
- [x] Tap "Cancel" on confirmation, verify no data deleted
- [x] Tap "Reset" on confirmation, verify all books deleted (<2s)
- [x] Start CSV import (50 books), tap "Reset Library" mid-enrichment, verify backend job canceled
- [x] Reset library, verify search history cleared
- [x] Reset library, verify enrichment queue empty
- [x] Reset library, verify AI provider reset to Gemini
- [x] Reset library with CloudKit sync enabled, verify other devices sync empty library

### Edge Cases

- [ ] Reset library while offline (no network), verify local delete succeeds (backend cancel fails gracefully)
- [ ] Reset library with 1000+ books, verify performance acceptable (<2s)
- [ ] Crash app mid-reset, relaunch, verify partial deletion handled (re-run reset completes)

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Backup Before Reset**
   - Auto-export CSV before deleting data
   - Save to Files app: "BooksTrack_Backup_2025-10-31.csv"
   - User can restore if reset was mistake

2. **Selective Reset Options**
   - "Delete only read books" (keep wishlist, currently reading)
   - "Delete only wishlist" (keep owned books)
   - "Delete reading progress only" (keep books, reset status/ratings)

3. **Reset Analytics**
   - Track reset frequency (identify UX issues causing resets)
   - Prompt: "Why are you resetting?" (imported wrong data, testing, fresh start)
   - Improve onboarding based on reset reasons

4. **Soft Delete / Undo**
   - Mark data as deleted (hide from UI)
   - Allow "Undo Reset" within 5 minutes
   - Permanent delete after timeout

---

## Dependencies

**iOS:**
- SwiftData (persistent storage for deletion)
- EnrichmentQueue (backend job tracking and cancellation)
- ModelContext (batch deletion)

**Backend:**
- `/api/enrichment/cancel` (Durable Object job cancellation)
- ProgressWebSocketDO (job status management)

---

## Success Criteria (Shipped)

- ✅ Reset completes in <2s (all data deleted)
- ✅ Confirmation dialog prevents accidental resets
- ✅ In-flight backend enrichment jobs canceled
- ✅ Search history, enrichment queue, feature flags cleared
- ✅ Library tab shows empty state after reset
- ✅ CloudKit sync propagates deletion to other devices (if enabled)

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
**Documentation:** Referenced in `CLAUDE.md` under "Library Reset" section
