# Cloud Sync - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Target Release:** v3.0.0+
**Last Updated:** December 2025

---

## Executive Summary

Cloud Sync provides automatic, zero-configuration library synchronization across all user devices. Users can seamlessly switch between devices while maintaining a consistent library, reading progress, and app settings without manual data export/import.

---

## Problem Statement

### User Pain Point

Users with multiple devices want their book library to stay synchronized without manual intervention:
- "I added 20 books on my phone, but they don't show on my tablet"
- "My reading progress doesn't sync between devices"
- "I have to manually export/import to keep devices in sync"

### Current Experience (Without Sync)

- **No sync:** Each device has independent library (data siloed)
- **Manual export/import:** Users export CSV from Device A, import to Device B
- **Error-prone:** Manual sync leads to duplicates and inconsistencies

---

## Target Users

| Attribute | Description |
|-----------|-------------|
| **User Type** | Multi-device owners (phone + tablet common) |
| **Usage Frequency** | Continuous (background sync, not user-initiated) |
| **Tech Savvy** | All levels (zero configuration required) |
| **Primary Goal** | Seamless device switching without data loss |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Sync Latency** | Changes propagate in 5-15s | Instrumentation |
| **Data Integrity** | Zero data loss during sync | Conflict logs |
| **Zero Config** | 100% of users sync without setup | No Settings required |
| **Multi-Device** | 30%+ users on 2+ devices | Account tracking |

---

## User Stories & Acceptance Criteria

### Must-Have (P0)

#### US-1: Automatic Library Sync

**As a** user with multiple devices
**I want** books added on Device A to appear on Device B automatically
**So that** I don't manually export/import data

**Acceptance Criteria:**
- [x] User signed into cloud account on both devices → sync automatic
- [x] Book added on Device A → appears on Device B within 15s
- [x] Book deleted on Device A → removed from Device B
- [x] Edge case: Not signed in → local-only mode (no errors)

#### US-2: Reading Progress Sync

**As a** user reading across devices
**I want** my reading progress (page, status, completion date) synced
**So that** I can switch devices mid-book

**Acceptance Criteria:**
- [x] Status change on Device A → syncs to Device B
- [x] Page number update → syncs within 15s
- [x] Completion date → syncs when book marked "Read"

#### US-3: Conflict Resolution

**As a** user editing same book on two devices offline
**I want** conflicts resolved automatically
**So that** I don't lose data

**Acceptance Criteria:**
- [x] Offline edits on both devices → merged when reconnect
- [x] User sees no error dialogs
- [x] Last-write-wins for conflicting fields

#### US-4: Zero Configuration

**As a** user installing on new device
**I want** sync to work automatically if signed in
**So that** I don't configure settings

**Acceptance Criteria:**
- [x] Install on new device → library syncs automatically
- [x] Not signed in → local-only mode
- [x] Sign in later → sync activates automatically

---

## Data Models

### Synced Entities

```typescript
// All entities sync automatically
interface SyncedData {
  works: Work[];           // Books
  editions: Edition[];     // Physical/digital editions
  authors: Author[];       // Author metadata
  userEntries: UserLibraryEntry[];  // Reading status, progress
  readingSessions: ReadingSession[]; // Reading history
}

// Local-only (not synced)
interface LocalData {
  tempImages: string[];    // Scan temp files
  searchHistory: string[]; // Privacy - intentionally local
  enrichmentQueue: any[];  // In-flight jobs
}
```

### Sync Rules

| Condition | Behavior |
|-----------|----------|
| User signed in | Automatic sync |
| User signed out | Local-only mode |
| Offline | Queue changes, sync when online |
| Conflict | Last-write-wins |
| New device | Full sync on first launch |

---

## Non-Functional Requirements

### Performance

| Requirement | Target | Rationale |
|-------------|--------|-----------|
| **Sync Latency** | <15 seconds | Feels real-time |
| **Initial Sync** | <60s for 1000 books | Acceptable wait |
| **Battery Impact** | Minimal | Background sync efficient |

### Reliability

- **Data Integrity:** Zero data loss (conflicts resolved automatically)
- **Offline Support:** Full functionality, sync when online
- **Error Recovery:** Automatic retry with exponential backoff

---

## Testing Strategy

### Manual QA

- [ ] Sign in on Device A, add book, verify appears on Device B
- [ ] Edit book on Device B, verify syncs to Device A
- [ ] Delete book on Device A, verify removed on Device B
- [ ] Go offline, edit book, reconnect, verify syncs
- [ ] Create conflict (edit same book offline on both), verify resolution

---

## Platform Implementation Notes

### iOS Implementation

**Status:** Completed

**Technology:** SwiftData + CloudKit (Apple native sync)

**Key Configuration:**
- iCloud capability enabled in Xcode
- CloudKit container: `iCloud.Z67H8Y8DW.com.oooefam.booksV3`
- Private database (user's data only)

**CloudKit Rules (Critical):**
1. Inverse relationships on to-many side only
2. All attributes need defaults
3. All relationships must be optional
4. Insert models BEFORE setting relationships
5. Can't filter predicates on to-many relationships

**Files:**
- `BooksTrackerApp.swift` - ModelContainer configuration
- All SwiftData models automatically sync via CloudKit

**Conflict Resolution:** Last-write-wins (CloudKit default)

---

### Flutter Implementation

**Status:** Not Started

**Recommended Approaches:**

1. **Firebase Firestore** (Recommended for cross-platform)
   - Real-time sync built-in
   - Offline support
   - Conflict resolution via timestamps
   - Free tier generous for small apps

2. **Supabase** (Open source alternative)
   - PostgreSQL-based
   - Real-time subscriptions
   - Row-level security

3. **Custom Backend + Local DB**
   - Use existing Cloudflare backend
   - Local SQLite with sync logic
   - More control, more work

**Key Dependencies:**
```yaml
dependencies:
  cloud_firestore: ^4.0.0  # Or supabase_flutter
  firebase_auth: ^4.0.0
  connectivity_plus: ^5.0.0  # Offline detection
```

**Implementation Notes:**
- Handle offline queue with local storage
- Implement conflict resolution strategy
- Test with poor network conditions
- Consider data encryption at rest

---

### Android Implementation

**Status:** Not Started

**Options:**
- Share Firebase/Supabase implementation with Flutter
- Room database for local storage
- WorkManager for background sync

---

## Decision Log

### [October 2025] Decision: CloudKit for iOS

**Context:** Need iOS sync solution
**Decision:** Use SwiftData CloudKit integration
**Rationale:**
- Zero maintenance (Apple handles sync)
- Free for users (included with iCloud)
- Privacy (data in user's iCloud)
- Deep SwiftData integration
**Trade-off:** Apple-only (acceptable for iOS-first)

### [October 2025] Decision: Last-Write-Wins Conflicts

**Context:** How to resolve offline conflicts?
**Decision:** Last-write-wins (automatic)
**Rationale:**
- Simple UX (no dialogs)
- Rare occurrence (users typically online)
- Acceptable data loss for book ratings

---

## Related Documentation

- **Library Management:** `docs/product/Library-Management-PRD.md`

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| Oct 2025 | Initial CloudKit implementation | Engineering |
| Dec 2025 | Refactored to platform-agnostic PRD | Documentation |
