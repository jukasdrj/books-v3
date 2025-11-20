# Sprint 1: Diversity Stats + Reading Sessions (REVISED)

**Sprint Duration:** 2 weeks
**Phase:** 1 (Engagement Foundation)
**Target Start:** December 2, 2025 (Post user research)
**Priority:** CRITICAL
**Branch:** `feature/v2-diversity-reading-sessions`

> **🔄 MAJOR REVISION:** November 20, 2025
> Sprint 1 now prioritizes **EnhancedDiversityStats** (user's #1 priority) alongside ReadingSession tracking.
> See [USER_INTERVIEW_INSIGHTS.md](../USER_INTERVIEW_INSIGHTS.md) for rationale.

---

## Sprint Goals

### Primary Goals (MUST HAVE)
1. ✨ **NEW:** Implement Representation Radar chart (diversity visualization)
2. ✨ **NEW:** Add "ghost state" UI for missing diversity data
3. ✨ **NEW:** Integrate progressive profiling prompts with diversity stats
4. Create `ReadingSession` SwiftData model with proper relationships
5. Implement timer UI in WorkDetailView/EditionMetadataView
6. Create `ReadingSessionService` actor for session lifecycle management

### Secondary Goals (SHOULD HAVE)
7. Add diversity completion percentage for gamification
8. Basic session persistence and validation
9. Update schema migration for SwiftData

---

## User Interview Insights

**Key Quotes:**
> "Diversity stats are #1 priority - they feed my recommendations greatly"
> "Radar chart is very clear, love the '+' callout for missing data"
> "Very important - I'd use reading tracking daily"
> "Happy to help with progressive profiling prompts"

**Validated Features:**
- ✅ Representation Radar chart design approved
- ✅ "Ghost state" for missing data validated
- ✅ Progressive profiling acceptance confirmed
- ✅ Gamification (progress rings) highly motivating

---

## User Stories

### PART 1: Diversity Stats (NEW - TOP PRIORITY)

### Story 1: View Diversity Radar Chart
**As a** diversity-conscious reader
**I want to** see a visual representation of diversity in my reading
**So that** I can understand representation patterns at a glance

**Acceptance Criteria:**
- [ ] Representation Radar chart appears in Library Stats view
- [ ] Chart shows 5-7 diversity dimensions (cultural origin, gender, translation, etc.)
- [ ] Solid lines show completed data, dashed lines show missing data
- [ ] Chart is labeled and color-coded for clarity
- [ ] WCAG AA contrast compliance (4.5:1+)
- [ ] User interview feedback: "Very clear" ✓

**Priority:** CRITICAL (User's #1 feature request)

---

### Story 2: See Missing Data Indicators ("Ghost State")
**As a** power user who curates metadata
**I want to** see which diversity data is missing
**So that** I know what information I can contribute

**Acceptance Criteria:**
- [ ] Missing diversity dimensions shown as dashed lines on radar chart
- [ ] "+" icon appears next to each missing data point
- [ ] Tapping "+" launches progressive profiling prompt
- [ ] Progress ring shows overall diversity data completion percentage
- [ ] User interview feedback: "Love it - clear call-to-action" ✓

**Priority:** CRITICAL (Enables progressive profiling)

---

### Story 3: Complete Diversity Data via Progressive Prompts
**As a** reader finishing a reading session
**I want to** answer quick questions about the book's diversity
**So that** I can contribute to my library's diversity tracking

**Acceptance Criteria:**
- [ ] Post-session prompt appears after ending reading session
- [ ] Prompt asks ONE question (e.g., "What's the author's cultural background?")
- [ ] Multiple choice pills for easy selection
- [ ] "Skip" option available (no pressure)
- [ ] Successful submission updates radar chart in real-time
- [ ] User interview feedback: "Happy to help - I'd answer every time" ✓

**Priority:** HIGH (Integrates with reading sessions)

---

### Story 4: View Diversity Completion Gamification
**As a** quantified-self user
**I want to** see my diversity data completion percentage
**So that** I feel motivated to fill in missing information

**Acceptance Criteria:**
- [ ] Completion percentage displayed prominently (e.g., "Diversity: 75% Complete")
- [ ] Progress ring visual indicator
- [ ] Breakdown by dimension (e.g., "Cultural Origin: 100%, Gender: 50%")
- [ ] Curator points awarded for completing diversity data (+5 per field)
- [ ] User interview feedback: "Yes, very motivating" ✓

**Priority:** HIGH (Gamification validated)

---

### PART 2: Reading Sessions (ORIGINAL SPRINT 1)

### Story 5: Start Reading Session
**As a** reader
**I want to** start a timed reading session
**So that** I can track how long I spend reading

**Acceptance Criteria:**
- [ ] Timer button appears in WorkDetailView when book status is "Reading"
- [ ] Tapping "Start Session" begins timer and records start time
- [ ] Current page is captured as session start page
- [ ] Only one session can be active at a time
- [ ] Timer persists across app backgrounding/foregrounding

**Priority:** CRITICAL (Foundation for progressive profiling)

---

### Story 6: End Reading Session with Progressive Prompt
**As a** reader
**I want to** stop my reading session and log pages read
**So that** the app can calculate my reading pace AND I can contribute diversity data

**Acceptance Criteria:**
- [ ] "Stop Session" button appears when session is active
- [ ] User prompted to enter ending page number
- [ ] Session duration calculated automatically (minutes)
- [ ] Pages read calculated (endPage - startPage)
- [ ] **NEW:** Progressive profiling prompt appears AFTER session saved
- [ ] **NEW:** Prompt shows "Updated 1 book" confirmation
- [ ] Session saved to SwiftData with all fields
- [ ] UserLibraryEntry.currentPage updated to endPage

**Priority:** CRITICAL (Integrates diversity + sessions)

---

### Story 7: View Session History
**As a** reader
**I want to** see my past reading sessions for a book
**So that** I can review my reading patterns

**Acceptance Criteria:**
- [ ] Session list appears in WorkDetailView (below reading progress)
- [ ] Each session shows: date, duration, pages read, reading pace
- [ ] Sessions sorted by date (newest first)
- [ ] Empty state shown when no sessions exist

**Priority:** HIGH

---

## Technical Tasks

### PART 1: Diversity Stats Implementation

### Task 1: EnhancedDiversityStats SwiftData Model
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/EnhancedDiversityStats.swift` (NEW)

```swift
@Model
public final class EnhancedDiversityStats {
    public var userId: String
    public var period: StatsPeriod // all-time, year, month

    // Diversity dimensions (v1 data exists)
    public var culturalOrigins: [String: Int] // e.g., ["African": 12, "European": 8]
    public var genderDistribution: [String: Int] // e.g., ["Female": 15, "Male": 5]
    public var translationStatus: [String: Int] // e.g., ["Translated": 8, "Original Language": 12]

    // ✨ NEW: Additional dimensions for Radar Chart (5-7 axes total)
    public var ownVoicesTheme: [String: Int] // e.g., ["Own Voices": 10, "Not Own Voices": 8]
    public var nicheAccessibility: [String: Int] // e.g., ["Accessible": 5, "Standard": 13]

    // Completion tracking (NEW - for gamification)
    public var totalBooks: Int
    public var booksWithCulturalData: Int
    public var booksWithGenderData: Int
    public var booksWithTranslationData: Int
    public var booksWithOwnVoicesData: Int // ✨ ADDED for forward-compatibility
    public var booksWithAccessibilityData: Int // ✨ ADDED for forward-compatibility

    // Computed properties
    public var culturalCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithCulturalData) / Double(totalBooks) * 100
    }

    public var genderCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithGenderData) / Double(totalBooks) * 100
    }

    public var translationCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithTranslationData) / Double(totalBooks) * 100
    }

    public var ownVoicesCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithOwnVoicesData) / Double(totalBooks) * 100
    }

    public var accessibilityCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithAccessibilityData) / Double(totalBooks) * 100
    }

    public var overallCompletionPercentage: Double {
        // ✨ UPDATED: Now accounts for 5 dimensions (not 3)
        let totalFields = totalBooks * 5 // cultural, gender, translation, ownVoices, accessibility
        let completedFields = booksWithCulturalData + booksWithGenderData +
                              booksWithTranslationData + booksWithOwnVoicesData +
                              booksWithAccessibilityData
        guard totalFields > 0 else { return 0 }
        return Double(completedFields) / Double(totalFields) * 100
    }

    public init(userId: String, period: StatsPeriod = .allTime) {
        self.userId = userId
        self.period = period
        self.culturalOrigins = [:]
        self.genderDistribution = [:]
        self.translationStatus = [:]
        self.ownVoicesTheme = [:] // ✨ ADDED
        self.nicheAccessibility = [:] // ✨ ADDED
        self.totalBooks = 0
        self.booksWithCulturalData = 0
        self.booksWithGenderData = 0
        self.booksWithTranslationData = 0
        self.booksWithOwnVoicesData = 0 // ✨ ADDED
        self.booksWithAccessibilityData = 0 // ✨ ADDED
    }
}

public enum StatsPeriod: String, Codable {
    case allTime, year, month
}
```

> **🔧 CRITICAL FIX (Nov 20, 2025):**
> Added `ownVoicesTheme` and `nicheAccessibility` dimensions to prevent schema migration in Sprint 4.
> The Representation Radar Chart requires 5-7 axes, not just 3. This future-proofs the data model.

**Subtasks:**
- [ ] Create `EnhancedDiversityStats.swift` with all properties
- [ ] Add computed properties for completion percentages
- [ ] Write unit tests for completion calculations
- [ ] Test with existing v1 diversity data

**Estimated:** 3 hours

---

### Task 2: DiversityStatsService Actor
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/DiversityStatsService.swift` (NEW)

**Methods:**
- [ ] `calculateStats(period: StatsPeriod) async throws -> EnhancedDiversityStats`
- [ ] `fetchCompletionPercentage() async throws -> Double`
- [ ] `getMissingDataDimensions(for workId: String) async throws -> [DiversityDimension]`
- [ ] `updateDiversityData(workId: String, dimension: DiversityDimension, value: String) async throws`

**Subtasks:**
- [ ] Implement stats calculation from existing v1 Work/Author data
- [ ] Add completion percentage logic
- [ ] Integrate with progressive profiling
- [ ] Write unit tests for service methods

**Estimated:** 5 hours

---

### Task 3: Representation Radar Chart (SwiftUI)
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/RepresentationRadarChart.swift` (NEW)

**Features:**
- [ ] 5-7 axis radar/spider chart
- [ ] Solid lines for completed data
- [ ] Dashed lines for missing data (ghost state)
- [ ] "+" icon tap targets for missing dimensions
- [ ] **SPRINT 1 SCOPE:** Static chart rendering only (no animations)
- [ ] **SPRINT 1 SCOPE:** Basic VoiceOver labels (advanced accessibility → Sprint 2)

**Tech Stack:**
- SwiftUI `Canvas` for custom drawing (RECOMMENDED)
- OR Swift Charts framework (if ghost state is supported)

**Subtasks:**
- [ ] **Day 1:** Research Canvas vs. Swift Charts (2 hours max)
- [ ] **DECISION POINT:** If Swift Charts doesn't support ghost state dashed lines + tappable "+" icons, commit to Canvas immediately
- [ ] Implement radar chart polygon rendering (solid lines)
- [ ] Add ghost state dashed lines for missing dimensions
- [ ] Add "+" tap targets (44x44pt minimum)
- [ ] Test on real device (performance check)
- [ ] **DEFERRED TO SPRINT 2:** Advanced animations, transitions
- [ ] **DEFERRED TO SPRINT 2:** Full VoiceOver dimension-by-dimension navigation

**Estimated:** 8 hours

> **⚠️ RISK MITIGATION (Nov 20, 2025):**
> This is the MOST COMPLEX UI task in Sprint 1. To prevent scope creep:
> - **Focus on static rendering** (data polygon + ghost state)
> - **Defer animations** to Sprint 2 if time is short
> - **Commit to Canvas early** if Swift Charts doesn't support ghost state
> - **Test performance** with 100+ book library on real device
>
> **Success criteria for Sprint 1:**
> - Chart correctly displays 5 dimensions
> - Ghost state (dashed lines) is visually distinct
> - "+" icons are tappable and launch prompts
> - No lag on iPhone 16 Pro with 100 books

---

### Task 4: Progressive Profiling UI Integration
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/ProgressiveProfilingPrompt.swift` (NEW)

**Features:**
- [ ] Post-session prompt sheet
- [ ] Multiple choice pills (SF Symbols + text)
- [ ] Single-question focus
- [ ] "Skip" option
- [ ] **SUCCESS STATE:** Celebratory animation + immediate feedback
- [ ] **SUCCESS STATE:** Show updated Curator Points (+5)
- [ ] **SUCCESS STATE:** Show updated Completion Percentage (e.g., 75% → 80%)
- [ ] **SUCCESS STATE:** Immediate radar chart update (visual confirmation)

**Example Prompt:**
```
┌────────────────────────────────────┐
│  📖 Great session! 30 minutes      │
│                                    │
│  Quick question:                   │
│  What's the author's cultural      │
│  background?                       │
│                                    │
│  [🌍 European] [🌏 Asian]          │
│  [🌎 Latin American]               │
│  [🌍 African] [🌏 Middle Eastern]  │
│  [Other] [Skip]                    │
│                                    │
│  ℹ️ This will update your          │
│     diversity stats                │
└────────────────────────────────────┘
```

**Enhanced Success State:**
```
┌────────────────────────────────────┐
│  ✅ Cultural background saved!     │
│                                    │
│  📊 Diversity: 75% → 80% Complete  │
│  🏆 +5 Curator Points               │
│                                    │
│  [View Updated Radar Chart]        │
│  [Dismiss]                         │
└────────────────────────────────────┘
```

**Subtasks:**
- [ ] Create `ProgressiveProfilingPrompt` view
- [ ] Integrate with `ReadingSessionService`
- [ ] **CRITICAL:** Implement success animation (confetti, checkmark, haptic feedback)
- [ ] **CRITICAL:** Show before/after completion percentage (75% → 80%)
- [ ] **CRITICAL:** Display Curator Points awarded (+5)
- [ ] **CRITICAL:** Trigger immediate radar chart refresh
- [ ] Test user flow on real device

**Estimated:** 4 hours

> **✅ SUCCESS STATE REQUIREMENTS (Nov 20, 2025):**
> The success confirmation must:
> 1. **Celebrate the action** - Confetti animation, green checkmark, haptic feedback
> 2. **Show immediate value** - Before/after completion % (75% → 80%)
> 3. **Award points** - Display Curator Points gained (+5)
> 4. **Visual confirmation** - Radar chart updates in real-time
>
> This satisfies the gamification goal and confirms the action was valuable to the user.

---

### Task 5: Diversity Completion UI (Gamification)
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/DiversityCompletionWidget.swift` (NEW)

**Features:**
- [ ] Progress ring (like Apple Watch)
- [ ] Percentage display
- [ ] Breakdown by dimension
- [ ] Tap to expand details

**Example:**
```
┌────────────────────────────────────┐
│  📊 Diversity Data: 75% Complete   │
│                                    │
│      ███████░░░ 75%                │
│                                    │
│  Cultural Origin:  ████████ 100%   │
│  Gender Identity:  █████░░░ 50%    │
│  Translation:      ██████░░ 75%    │
│                                    │
│  🏆 +45 Curator Points              │
│  [Fill Missing Data]               │
└────────────────────────────────────┘
```

**Subtasks:**
- [ ] Create progress ring component
- [ ] Add dimension breakdown
- [ ] Integrate with gamification system
- [ ] Test visual polish

**Estimated:** 4 hours

---

### PART 2: Reading Sessions Implementation (ORIGINAL)

### Task 6: ReadingSession SwiftData Model
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

    // Progressive profiling integration (NEW)
    public var enrichmentPromptShown: Bool
    public var enrichmentCompleted: Bool

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
- [ ] **NEW:** Add progressive profiling tracking fields
- [ ] Define relationship to `UserLibraryEntry`
- [ ] Write unit tests for computed properties

**Estimated:** 2 hours

---

### Task 7: Update UserLibraryEntry Model
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift` (MODIFIED)

**Changes:**
- [ ] Add `@Relationship(deleteRule: .cascade, inverse: \ReadingSession.entry) var readingSessions: [ReadingSession] = []`
- [ ] Add computed property `totalReadingMinutes: Int`
- [ ] Add computed property `averageReadingPace: Double?`

**Estimated:** 1 hour

---

### Task 8: ReadingSessionService Actor
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/ReadingSessionService.swift` (NEW)

**Methods:**
- [ ] `startSession(for: UserLibraryEntry) async throws`
- [ ] `endSession(endPage: Int) async throws -> ReadingSession`
- [ ] `isSessionActive() -> Bool`
- [ ] `currentSession() -> SessionInfo?`
- [ ] **NEW:** `shouldShowEnrichmentPrompt() async throws -> Bool`
- [ ] **NEW:** `recordEnrichmentShown(for session: ReadingSession) async throws`

**Subtasks:**
- [ ] Implement session lifecycle methods
- [ ] **NEW:** Add progressive profiling trigger logic
- [ ] Add error handling
- [ ] Write unit tests

**Estimated:** 5 hours

---

### Task 9: Timer UI Component
**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/EditionMetadataView.swift` (MODIFIED)

**UI Components:**
- [ ] Start/Stop button (contextual based on session state)
- [ ] Live timer display (MM:SS format)
- [ ] Page number input sheet (on stop)
- [ ] Session confirmation alert
- [ ] **NEW:** Progressive profiling prompt integration

**State Management:**
- [ ] `@State var isSessionActive: Bool`
- [ ] `@State var sessionStartTime: Date?`
- [ ] `@State var showEndSessionSheet: Bool`
- [ ] **NEW:** `@State var showEnrichmentPrompt: Bool`

**Estimated:** 6 hours

---

### Task 10: Schema Migration
**File:** `BooksTracker/BooksTrackerApp.swift` (MODIFIED)

**Changes:**
- [ ] Add `ReadingSession.self` to Schema definition
- [ ] Add `EnhancedDiversityStats.self` to Schema definition
- [ ] Test migration from v1 schema to v2 schema
- [ ] Verify no data loss on migration

**Estimated:** 3 hours

---

## Testing Strategy

### Unit Tests (TDD Approach)

**Diversity Stats:**
- [ ] `EnhancedDiversityStats` completion percentage calculations
- [ ] `DiversityStatsService` stats aggregation from v1 data
- [ ] Missing data dimension detection
- [ ] Progressive profiling data updates

**Reading Sessions:**
- [ ] `ReadingSession` computed properties
- [ ] `ReadingSessionService` lifecycle methods
- [ ] Progressive profiling trigger logic

**Estimated:** 6 hours

---

### Integration Tests

**Diversity + Sessions Integration:**
- [ ] Post-session prompt triggers correctly
- [ ] Diversity data updates after prompt completion
- [ ] Radar chart updates in real-time
- [ ] Completion percentage recalculates

**Reading Sessions:**
- [ ] Full session lifecycle (start → stop → persist)
- [ ] UserLibraryEntry updates on session end
- [ ] Multiple sessions for same book

**Estimated:** 5 hours

---

### Manual Testing Checklist

**Diversity Stats:**
- [ ] Radar chart renders correctly on all device sizes
- [ ] Dashed lines (ghost state) are visually distinct
- [ ] "+" icons are tappable and launch prompts
- [ ] Completion percentage updates after data entry
- [ ] VoiceOver announces chart dimensions correctly

**Reading Sessions:**
- [ ] Start session → background app → foreground → verify timer continues
- [ ] End session → progressive prompt appears
- [ ] Progressive prompt → Skip → no data saved
- [ ] Progressive prompt → Answer → diversity data updates
- [ ] Radar chart updates immediately after prompt

**Real Device Testing (iPhone 16 Pro):**
- [ ] Timer accuracy on real device
- [ ] Progressive prompt doesn't block keyboard input
- [ ] Radar chart performance (no lag)

---

## Design Specifications

### Representation Radar Chart

**Dimensions (5-7 axes):**
1. Cultural Origin (African, Asian, European, Latin American, Middle Eastern, etc.)
2. Gender Representation (Female, Male, Non-binary, Unknown)
3. Translation Status (Translated, Original Language)
4. Time Period (Contemporary, Historical, Classic)
5. Geographic Diversity (continents represented)
6. *Optional:* Marginalized Voices (LGBTQ+, Disability, etc.)
7. *Optional:* Language Diversity

**Visual Design:**
- Solid lines: Green (#34C759) for completed data
- Dashed lines: Gray (#8E8E93) for missing data
- "+" icons: Blue (#007AFF) accent color
- Background: System background with subtle grid
- Labels: SF Pro Text, 12pt, medium weight

**Accessibility:**
- WCAG AA contrast: 4.5:1+ for all text
- VoiceOver: "Cultural Origin: 80% complete. African: 12 books, European: 8 books..."
- Tap targets: 44x44pt minimum for "+" icons

---

### Progressive Profiling Prompt

**Appearance:**
- Sheet presentation (`.presentationDetents([.medium])`)
- Rounded corners, glass effect (iOS 26 liquid glass)
- Multiple choice pills (SF Symbols + text)
- Generous spacing (16pt between options)

**Success State:**
```
┌────────────────────────────────────┐
│  ✅ Cultural background saved!     │
│                                    │
│  📊 Diversity: 75% → 80% Complete  │
│  🏆 +5 Curator Points               │
│                                    │
│  [Dismiss]                         │
└────────────────────────────────────┘
```

---

## Definition of Done

### Code Quality
- [ ] All code written and reviewed
- [ ] Zero compiler warnings (Swift 6 concurrency compliance)
- [ ] All unit tests passing (100% coverage for new code)
- [ ] All integration tests passing
- [ ] SwiftData migration tested with v1 data

### Testing
- [ ] Manual testing completed on simulator
- [ ] Manual testing completed on real device (iPhone 16 Pro)
- [ ] VoiceOver testing completed (accessibility)
- [ ] Performance profiled (no memory leaks, <200ms radar chart render)

### Documentation
- [ ] Inline code comments added
- [ ] AGENTS.md updated (if new patterns introduced)
- [ ] Sprint retrospective documented
- [ ] Known issues logged in GitHub

### User Validation
- [ ] Radar chart matches user interview mockup expectations
- [ ] Progressive prompt feels natural (not intrusive)
- [ ] Gamification elements are motivating (progress ring, points)

---

## Dependencies

### External Dependencies
- None (foundational features)

### Internal Dependencies
- Existing v1 `Work`, `Author`, `UserLibraryEntry` models
- Existing diversity data fields (culturalOrigin, genderIdentity)

---

## Risks & Mitigations

### Risk 1: Radar Chart Performance on Large Libraries
**Impact:** HIGH (user has 100+ book goal)
**Mitigation:**
- Limit chart to aggregated stats (not per-book rendering)
- Use SwiftUI Canvas with efficient drawing
- Profile with Instruments before shipping

### Risk 2: Timer Not Persisting Across App Backgrounding
**Impact:** MEDIUM
**Mitigation:**
- Use `UserDefaults` to persist session start time
- Test thoroughly on real device

### Risk 3: Progressive Prompts Feel Intrusive
**Impact:** HIGH (user validation)
**Mitigation:**
- User explicitly said "Happy to help, I'd answer every time"
- Provide clear "Skip" option
- Limit to ONE question per session
- Monitor user research feedback

### Risk 4: Complexity of Implementing Two Features in One Sprint
**Impact:** HIGH (scope creep)
**Mitigation:**
- Prioritize diversity stats (user's #1)
- Reading sessions are foundation from original plan
- Progressive profiling ties them together naturally
- Have clear MVP boundaries (advanced features pushed to Sprint 2)

---

## Success Metrics

### Quantitative
- [ ] Radar chart renders in <200ms
- [ ] Progressive prompt completion rate >50%
- [ ] Diversity data completion increases by 20%+
- [ ] Users can successfully start/stop reading sessions
- [ ] Zero crashes related to new features

### Qualitative
- [ ] User feedback: "Radar chart is very clear" (validated in interview)
- [ ] User feedback: "Progressive prompts are helpful, not annoying"
- [ ] No negative feedback about gamification elements

---

## Sprint Timeline

### Week 1: Implementation & Unit Tests

**Monday-Tuesday (Dec 2-3):**
- [ ] Task 1: EnhancedDiversityStats model (3h)
- [ ] Task 2: DiversityStatsService (5h)
- [ ] Task 6: ReadingSession model (2h)
- [ ] Task 7: Update UserLibraryEntry (1h)

**Wednesday-Thursday (Dec 4-5):**
- [ ] Task 3: Representation Radar Chart (8h)
- [ ] Task 8: ReadingSessionService (5h)
- [ ] Unit tests for models and services (6h)

**Friday (Dec 6):**
- [ ] Task 4: Progressive Profiling UI (4h)
- [ ] Task 5: Diversity Completion Widget (4h)

---

### Week 2: Integration, Testing, Documentation

**Monday-Tuesday (Dec 9-10):**
- [ ] Task 9: Timer UI Component (6h)
- [ ] Task 10: Schema Migration (3h)
- [ ] Progressive profiling integration (2h)

**Wednesday (Dec 11):**
- [ ] Integration tests (5h)
- [ ] Manual testing on simulator (3h)

**Thursday (Dec 12):**
- [ ] Real device testing (iPhone 16 Pro) (4h)
- [ ] VoiceOver/accessibility testing (2h)
- [ ] Performance profiling (2h)

**Friday (Dec 13):**
- [ ] Bug fixes and polish (4h)
- [ ] Documentation updates (2h)
- [ ] Sprint retrospective (2h)

---

## Post-Sprint Follow-Ups

**Sprint 2 Preparation:**
- [ ] Create Sprint 2 plan (Cascade Metadata + Session Analytics)
- [ ] Gather user feedback on Sprint 1 features
- [ ] Log any technical debt or nice-to-haves for future sprints

**Known Limitations (Addressed in Future Sprints):**
- Advanced diversity dimensions (intersectionality) → Sprint 4
- Streak tracking → Sprint 2
- AI recommendations integration → Sprint 5-8
- Community diversity benchmarks → Sprint 7 (federated learning)

---

**Document Owner:** Technical Team
**Last Updated:** November 20, 2025
**Status:** READY FOR IMPLEMENTATION
**Estimated Effort:** 2 weeks (79 hours total)
**Branch:** `feature/v2-diversity-reading-sessions`
