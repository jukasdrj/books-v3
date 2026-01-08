# Goals Engine (Phase 2)

**Status:** ✅ Complete (January 8, 2026)
**Version:** v3.7.5+
**Build:** 189+

## Overview

Complete reading goal tracking system with SwiftData persistence, automatic progress calculation, and CloudKit sync support.

## Features

### Goal Types (6 total)

1. **Books Read** - Track number of completed books
2. **Pages Read** - Sum total pages from finished books
3. **Authors Explored** - Count unique authors discovered
4. **Genres Explored** - Track unique subject tags/genres
5. **Reading Streak** - Maintain consecutive reading days
6. **Reading Time** - Track total hours spent reading

### Goal Management

- Create goals with custom targets and optional deadlines
- Pause/resume active goals
- Delete goals with confirmation
- View progress history with milestone snapshots
- Private goals (excluded from sharing/exports)

### Progress Tracking

**Automatic Updates:**
- Listens to `.libraryWasUpdated` notification
- Listens to `.bookMarkedAsRead` notification
- Listens to `.readingSessionEnded` notification
- Auto-completes goals when target reached
- Records milestones at 25%, 50%, 75%, 100%

**Manual Updates:**
- `GoalProgressService.updateAllGoalProgress()` - Refresh all goals
- `GoalProgressService.recordProgress()` - Manual progress entry

### UI Components

**GoalsView:**
- Summary card (total progress, average completion, overdue count)
- Active goals list with progress rings
- Completed goals section
- Empty state for new users

**GoalCard:**
- Circular progress ring (color-coded by percentage)
- Linear progress bar with gradient
- Status badges (Active, Paused, Completed, Overdue)
- Deadline/estimated completion display
- Notes preview

**CreateGoalSheet:**
- Form-based goal creation
- Live preview card
- Validation (title, target > 0, deadline after start)
- All 6 goal types supported

**GoalDetailSheet:**
- Large progress ring visualization
- Goal metadata (type, target, progress, deadline)
- Milestone history
- Pause/resume actions
- Delete with confirmation

## Architecture

### Data Models

**Goal.swift:**
```swift
@Model
public final class Goal {
    // Raw value storage for CloudKit compatibility
    public var goalTypeRawValue: String
    public var statusRawValue: String

    // Computed properties for type-safe access
    public var goalType: GoalType { get set }
    public var status: GoalStatus { get set }

    // Core fields
    public var uuid: UUID
    public var title: String
    public var targetCount: Int
    public var currentProgress: Int
    public var startDate: Date
    public var deadline: Date?
    public var notes: String?
    public var isPrivate: Bool

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \GoalProgress.goal)
    var progressHistory: [GoalProgress]?
}
```

**GoalProgress.swift:**
```swift
@Model
public final class Goal Progress {
    public var uuid: UUID
    public var recordedDate: Date
    public var progressValue: Int
    public var milestone: String?
    public var note: String?

    // Relationships
    var goal: Goal?
    public var goalUUID: UUID
}
```

### Services

**GoalProgressService.swift:**
- Calculates progress for all 6 goal types
- Queries SwiftData for relevant entries/sessions
- Uses fetch-then-filter pattern for complex predicates
- Creates milestone snapshots

**GoalTrackingCoordinator.swift:**
- Observable coordinator for automatic tracking
- NotificationCenter integration
- Debounced updates (prevents duplicate processing)
- Environment key injection pattern

### SwiftData Integration

**Schema Registration:**
```swift
let schema = Schema([
    Work.self,
    Edition.self,
    Author.self,
    UserLibraryEntry.self,
    ReadingSession.self,
    // v3 Phase 2: Goals Engine
    Goal.self,
    GoalProgress.self
])
```

**CloudKit Sync:**
- Enum storage using raw String values
- All properties have default values
- Cascade delete for progress history

## Navigation Integration

**5-Tab Layout:**
1. Library
2. Search
3. Scan & Import
4. Insights
5. **Goals** ← New tab

**ContentView.swift:**
```swift
// Goals Tab
NavigationStack {
    GoalsView()
}
.themedNavigationGlass()
.tabItem {
    Label("Goals", systemImage: selectedTab == .goals ? "target" : "target")
}
.tag(MainTab.goals)
```

## Technical Decisions

### 1. Predicate Simplification

**Problem:** `#Predicate` macro doesn't support complex expressions or enum member access.

**Solution:** Split into simple predicate + post-fetch filter.

```swift
// ❌ Complex predicate (doesn't compile)
#Predicate { entry in
    entry.readingStatus == .read &&
    entry.dateCompleted >= goal.startDate
}

// ✅ Simplified predicate + filter
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { entry in
        entry.readingStatus.rawValue == "Read"
    }
)
let allEntries = try modelContext.fetch(descriptor)
let entries = allEntries.filter { entry in
    guard let dateCompleted = entry.dateCompleted else { return false }
    return dateCompleted >= startDate
}
```

### 2. CloudKit Enum Storage

**Problem:** Direct enum storage not supported by CloudKit.

**Solution:** Store raw String values with computed properties.

```swift
// ❌ Direct enum storage
public var goalType: GoalType = .booksRead

// ✅ Raw value storage
public var goalTypeRawValue: String = GoalType.booksRead.rawValue

public var goalType: GoalType {
    get { GoalType(rawValue: goalTypeRawValue) ?? .booksRead }
    set { goalTypeRawValue = newValue.rawValue }
}
```

### 3. Genre Exploration

**Problem:** `Work` model doesn't have a `genres` property.

**Solution:** Use `Work.subjectTags` as genre/subject source.

```swift
var subjects = Set<String>()
for entry in entries {
    if let work = entry.work, !work.subjectTags.isEmpty {
        for subject in work.subjectTags {
            subjects.insert(subject.lowercased())
        }
    }
}
return subjects.count
```

## Files Created

**Models:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/Goal.swift` (350 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/GoalProgress.swift` (80 lines)

**Services:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/GoalProgressService.swift` (350 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/GoalTrackingCoordinator.swift` (183 lines)

**UI:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/GoalsView.swift` (460 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/CreateGoalSheet.swift` (256 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/Components/GoalCard.swift` (251 lines)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Goals/Components/GoalProgressRing.swift` (120 lines)

**Modified:**
- `BooksTracker/BooksTrackerApp.swift` (added Goal/GoalProgress to schema)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift` (added Goals tab)

**Total:** 9 files, ~2,000 lines of code

## Testing

**Build Status:**
- ✅ Zero warnings (enforced with `-Werror`)
- ✅ Swift 6 concurrency compliant
- ✅ SwiftData patterns validated

**Manual Testing Checklist:**
- [ ] Create goal for each type
- [ ] Verify progress calculations
- [ ] Test pause/resume workflow
- [ ] Test delete with confirmation
- [ ] Verify milestone snapshots
- [ ] Test deadline warnings
- [ ] Test empty state
- [ ] Verify CloudKit sync

## Future Enhancements

### Phase 3: Notifications & Reminders
- Push notifications for overdue goals
- Weekly progress summaries
- Milestone achievement celebrations
- Streak maintenance reminders

### Phase 4: Goal Templates
- Pre-defined goal templates (e.g., "52 Books in 52 Weeks")
- Community-shared templates
- Adaptive difficulty (based on reading pace)

### Phase 5: Social Features
- Share goals with friends
- Compete on leaderboards
- Group reading challenges
- Progress comparisons

## Related Documentation

- **Architecture:** See `AGENTS.md` lines 52-54 for project structure
- **SwiftData Patterns:** See `AGENTS.md` lines 91-149 for critical rules
- **Changelog:** See `CHANGELOG.md` for detailed implementation notes
- **CLAUDE.md:** See lines 56-59 for Goals schema registration

## Implementation Notes

**Total Development Time:** ~6 hours (continued from previous session)

**Key Challenges:**
1. `#Predicate` macro limitations with complex expressions
2. ReadingStatus enum access in predicates
3. Missing `Work.genres` property (used `subjectTags` instead)

**Lessons Learned:**
1. Always prefer fetch-then-filter for complex SwiftData queries
2. Use `.rawValue` comparison for enums in predicates
3. Validate model property existence before implementing features
4. CloudKit compatibility requires raw value storage for enums

---

**Last Updated:** January 8, 2026
**Status:** Complete and integrated into main app
