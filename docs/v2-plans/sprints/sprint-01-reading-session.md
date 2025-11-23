# Sprint 1: ReadingSession Model & Timer UI

**Sprint Duration:** 2 weeks
**Phase:** 1 (Engagement Foundation)
**Target Start:** TBD (Post user research)
**Priority:** CRITICAL

---

## Sprint Goals

1. Create `ReadingSession` SwiftData model with proper relationships
2. Implement timer UI in WorkDetailView/EditionMetadataView
3. Create `ReadingSessionService` actor for session lifecycle management
4. Add basic session persistence and validation
5. Update schema migration for SwiftData

---

## User Stories

### Story 1: Start Reading Session
**As a** reader
**I want to** start a timed reading session
**So that** I can track how long I spend reading

**Acceptance Criteria:**
- [ ] Timer button appears in WorkDetailView when book status is "Reading"
- [ ] Tapping "Start Session" begins timer and records start time
- [ ] Current page is captured as session start page
- [ ] Only one session can be active at a time
- [ ] Timer persists across app backgrounding/foregrounding

---

### Story 2: End Reading Session
**As a** reader
**I want to** stop my reading session and log pages read
**So that** the app can calculate my reading pace

**Acceptance Criteria:**
- [ ] "Stop Session" button appears when session is active
- [ ] User prompted to enter ending page number
- [ ] Session duration calculated automatically (minutes)
- [ ] Pages read calculated (endPage - startPage)
- [ ] Session saved to SwiftData with all fields
- [ ] UserLibraryEntry.currentPage updated to endPage

---

### Story 3: View Session History
**As a** reader
**I want to** see my past reading sessions for a book
**So that** I can review my reading patterns

**Acceptance Criteria:**
- [ ] Session list appears in WorkDetailView (below reading progress)
- [ ] Each session shows: date, duration, pages read, reading pace
- [ ] Sessions sorted by date (newest first)
- [ ] Empty state shown when no sessions exist

---

## Technical Tasks

### Task 1: SwiftData Model Creation
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/ReadingSession.swift` (NEW)

```swift
@Model
public final class ReadingSession {
    public var date: Date
    public var durationMinutes: Int
    public var startPage: Int
    public var endPage: Int

    @Relationship(deleteRule: .nullify, inverse: \UserLibraryEntry.readingSessions)
    public var entry: UserLibraryEntry?

    @Attribute(.unique)
    public var workPersistentID: PersistentIdentifier?

    // Computed
    public var pagesRead: Int { max(0, endPage - startPage) }
    public var readingPace: Double? {
        guard durationMinutes > 0 else { return nil }
        return Double(pagesRead) / Double(durationMinutes) * 60.0 // pages/hour
    }
}
```

**Subtasks:**
- [ ] Create `ReadingSession.swift` with all properties
- [ ] Add computed properties for `pagesRead` and `readingPace`
- [ ] Define relationship to `UserLibraryEntry`
- [ ] Add `workPersistentID` for efficient queries
- [ ] Write unit tests for computed properties

**Estimated:** 2 hours

---

### Task 2: Update UserLibraryEntry Model
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift` (MODIFIED)

**Changes:**
- [ ] Add `@Relationship(deleteRule: .cascade, inverse: \ReadingSession.entry) var readingSessions: [ReadingSession] = []`
- [ ] Add computed property `totalReadingMinutes: Int`
- [ ] Add computed property `averageReadingPace: Double?`

**Estimated:** 1 hour

---

### Task 3: Schema Migration
**File:** `BooksTracker/BooksTrackerApp.swift` (MODIFIED)

**Changes:**
- [ ] Add `ReadingSession.self` to Schema definition
- [ ] Test migration from v1 schema to v2 schema
- [ ] Verify no data loss on migration

**Estimated:** 2 hours

---

### Task 4: ReadingSessionService Actor
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/ReadingSessionService.swift` (NEW)

**Methods:**
- [ ] `startSession(for: UserLibraryEntry) async throws`
- [ ] `endSession(endPage: Int) async throws -> ReadingSession`
- [ ] `isSessionActive() -> Bool`
- [ ] `currentSession() -> SessionInfo?` (for timer UI)

**Error Handling:**
- [ ] `SessionError.alreadyActive`
- [ ] `SessionError.notActive`
- [ ] `SessionError.entryNotFound`

**Estimated:** 4 hours

---

### Task 5: Timer UI Component
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/EditionMetadataView.swift` (MODIFIED)

**UI Components:**
- [ ] Start/Stop button (contextual based on session state)
- [ ] Live timer display (MM:SS format)
- [ ] Page number input sheet (on stop)
- [ ] Session confirmation alert

**State Management:**
- [ ] `@State var isSessionActive: Bool`
- [ ] `@State var sessionStartTime: Date?`
- [ ] `@State var showEndSessionSheet: Bool`

**Estimated:** 6 hours

---

### Task 6: Session History View
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/ReadingSessionHistoryView.swift` (NEW)

**Features:**
- [ ] List of past sessions with details
- [ ] Formatted date display
- [ ] Duration and pages read
- [ ] Reading pace calculation
- [ ] Empty state view

**Estimated:** 4 hours

---

### Task 7: Integration with WorkDetailView
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/WorkDetailView.swift` (MODIFIED)

**Changes:**
- [ ] Inject `ReadingSessionService` via environment
- [ ] Add session history section below reading progress
- [ ] Wire up timer button to service methods
- [ ] Handle session state updates

**Estimated:** 3 hours

---

### Task 8: Unit Tests
**File:** `BooksTrackerPackageTests/ReadingSessionTests.swift` (NEW)

**Test Coverage:**
- [ ] ReadingSession model creation
- [ ] Computed properties (pagesRead, readingPace)
- [ ] Relationship cascade behavior
- [ ] SessionService start/stop lifecycle
- [ ] Error handling for edge cases

**Estimated:** 4 hours

---

### Task 9: Integration Tests
**File:** `BooksTrackerPackageTests/ReadingSessionIntegrationTests.swift` (NEW)

**Test Scenarios:**
- [ ] Full session lifecycle (start → stop → persist)
- [ ] UserLibraryEntry updates on session end
- [ ] Multiple sessions for same book
- [ ] Session persistence across app restarts

**Estimated:** 3 hours

---

## Design Specifications

### Timer Button States

**State 1: No Active Session**
```
┌─────────────────────┐
│  ▶ Start Reading   │
└─────────────────────┘
```

**State 2: Active Session**
```
┌─────────────────────┐
│  ■ Stop (00:15:32) │
└─────────────────────┘
```

**State 3: Loading**
```
┌─────────────────────┐
│  ⟳ Saving...       │
└─────────────────────┘
```

---

### End Session Sheet

```
┌────────────────────────────────┐
│  End Reading Session           │
├────────────────────────────────┤
│                                │
│  Duration: 15 minutes          │
│  Started on page: 45           │
│                                │
│  Current page:                 │
│  ┌──────────────────────────┐ │
│  │ 62                       │ │
│  └──────────────────────────┘ │
│                                │
│  Pages read: 17                │
│  Pace: 68 pages/hour           │
│                                │
│  ┌──────────────────────────┐ │
│  │      Save Session        │ │
│  └──────────────────────────┘ │
│                                │
│         Cancel                 │
│                                │
└────────────────────────────────┘
```

---

### Session History Item

```
┌──────────────────────────────────┐
│ Nov 19, 2025 • 3:45 PM          │
│                                  │
│ ⏱ 15 min  📖 17 pages  📊 68/hr │
│ Pages 45-62                      │
└──────────────────────────────────┘
```

---

## Testing Strategy

### Unit Tests (TDD Approach)
1. Write tests for `ReadingSession` computed properties first
2. Implement properties to pass tests
3. Write tests for `ReadingSessionService` methods
4. Implement service logic
5. Refactor with confidence

### Integration Tests
1. Test full session lifecycle in SwiftData
2. Test relationship updates (UserLibraryEntry ↔ ReadingSession)
3. Test edge cases (app backgrounding, force quit during session)

### Manual Testing Checklist
- [ ] Start session → background app → foreground → verify timer continues
- [ ] Start session → force quit → reopen → verify session state
- [ ] End session with invalid page number (< start page)
- [ ] Multiple sessions in same day
- [ ] Session with 0 pages read (same start/end page)
- [ ] Very long session (>2 hours)

---

## Definition of Done

- [ ] All code written and reviewed
- [ ] All unit tests passing (100% coverage for new code)
- [ ] All integration tests passing
- [ ] Manual testing completed on simulator
- [ ] Manual testing completed on real device (iPhone 16 Pro)
- [ ] Zero compiler warnings
- [ ] Documentation updated (inline comments, AGENTS.md if needed)
- [ ] SwiftData migration tested with existing v1 data
- [ ] Performance profiled (no memory leaks, efficient queries)

---

## Dependencies

- None (foundational feature)

---

## Risks & Mitigations

### Risk 1: Timer not persisting across app backgrounding
**Mitigation:** Use `UserDefaults` or SwiftData to persist session start time

### Risk 2: Concurrent access to session state
**Mitigation:** Use `@globalActor` for `ReadingSessionService` to ensure thread safety

### Risk 3: SwiftData migration issues with existing v1 data
**Mitigation:** Thoroughly test migration on device with real v1 data, provide rollback mechanism

### Risk 4: User forgets to end session
**Mitigation:** Add "Resume Session" reminder on app launch if active session detected

---

## Success Metrics

- [ ] Users can successfully start and stop reading sessions
- [ ] Session data persists correctly in SwiftData
- [ ] Timer UI updates in real-time without lag
- [ ] Reading pace calculations are accurate
- [ ] Zero crashes related to session management
- [ ] User feedback: "Helps me track my reading habits"

---

## Sprint Retrospective Questions

1. Was the 2-week timeline realistic?
2. Did we encounter unexpected SwiftData issues?
3. Is the timer UI intuitive and easy to use?
4. What would we do differently in Sprint 2?

---

**Created:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Draft - Pending user research validation
