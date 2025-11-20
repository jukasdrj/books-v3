# Technical Design: Reading Sessions

**Feature:** Reading Session Tracking
**Phase:** 1 (Engagement Foundation)
**Sprint:** 1 & 2
**Status:** Design Phase

---

## Overview

Reading sessions enable users to track detailed reading habits including duration, pages read, and reading pace. This feature forms the foundation for streak tracking, analytics, and habit-building features.

---

## Goals

1. **Accurate Tracking:** Record precise session data (start time, end time, pages)
2. **Persistence:** Survive app backgrounding, force quit, and device restart
3. **Performance:** Minimal impact on app performance, efficient queries
4. **Privacy:** All data stored locally, no cloud sync required
5. **Extensibility:** Foundation for future features (streaks, insights, AI)

---

## Data Model

### ReadingSession Entity

```swift
@Model
public final class ReadingSession {
    // Primary fields
    public var id: UUID
    public var date: Date
    public var durationMinutes: Int
    public var startPage: Int
    public var endPage: Int

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \UserLibraryEntry.readingSessions)
    public var entry: UserLibraryEntry?

    // Denormalized for performance
    @Attribute(.unique)
    public var workPersistentID: PersistentIdentifier?

    // Computed properties
    public var pagesRead: Int {
        return max(0, endPage - startPage)
    }

    public var readingPace: Double? {
        guard durationMinutes > 0, pagesRead > 0 else { return nil }
        return Double(pagesRead) / Double(durationMinutes) * 60.0 // pages/hour
    }

    // Initialization
    public init(
        durationMinutes: Int,
        startPage: Int,
        endPage: Int,
        entry: UserLibraryEntry
    ) {
        self.id = UUID()
        self.date = Date()
        self.durationMinutes = durationMinutes
        self.startPage = startPage
        self.endPage = endPage
        self.entry = entry
        self.workPersistentID = entry.work?.persistentModelID
    }
}
```

### UserLibraryEntry Additions

```swift
extension UserLibraryEntry {
    // Relationship to sessions
    @Relationship(deleteRule: .cascade, inverse: \ReadingSession.entry)
    public var readingSessions: [ReadingSession] = []

    // Computed analytics
    public var totalReadingMinutes: Int {
        readingSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    public var totalPagesRead: Int {
        readingSessions.reduce(0) { $0 + $1.pagesRead }
    }

    public var averageReadingPace: Double? {
        let sessions = readingSessions.filter { $0.readingPace != nil }
        guard !sessions.isEmpty else { return nil }
        let totalPace = sessions.compactMap(\.readingPace).reduce(0, +)
        return totalPace / Double(sessions.count)
    }

    public var lastReadDate: Date? {
        readingSessions.max(by: { $0.date < $1.date })?.date
    }
}
```

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────┐
│                    View Layer                    │
│  ┌──────────────────┐  ┌─────────────────────┐ │
│  │ WorkDetailView   │  │ SessionHistoryView  │ │
│  └────────┬─────────┘  └──────────┬──────────┘ │
│           │                       │             │
└───────────┼───────────────────────┼─────────────┘
            │                       │
            ▼                       ▼
┌─────────────────────────────────────────────────┐
│              Service Layer (Actor)               │
│  ┌──────────────────────────────────────────┐  │
│  │      ReadingSessionService               │  │
│  │  - startSession(for:)                    │  │
│  │  - endSession(endPage:)                  │  │
│  │  - isSessionActive()                     │  │
│  │  - currentSessionInfo()                  │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────┐
│              Persistence Layer                   │
│  ┌──────────────┐  ┌──────────────────────┐    │
│  │  SwiftData   │  │   UserDefaults       │    │
│  │  (sessions)  │  │  (active session)    │    │
│  └──────────────┘  └──────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## Service Layer Design

### ReadingSessionService Actor

```swift
@globalActor
public actor ReadingSessionActor {
    public static let shared = ReadingSessionActor()
}

@ReadingSessionActor
public final class ReadingSessionService {
    // MARK: - Properties

    private let modelContainer: ModelContainer
    private var activeSessionStorage: ActiveSessionStorage

    // MARK: - Initialization

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.activeSessionStorage = ActiveSessionStorage()
    }

    // MARK: - Public API

    public func startSession(for entry: UserLibraryEntry) async throws {
        // 1. Validate no active session
        guard !activeSessionStorage.hasActiveSession else {
            throw SessionError.alreadyActive
        }

        // 2. Create context and fetch entry
        let context = ModelContext(modelContainer)
        guard let localEntry = context.model(for: entry.persistentModelID) as? UserLibraryEntry else {
            throw SessionError.entryNotFound
        }

        // 3. Store active session info
        let sessionInfo = ActiveSessionInfo(
            entryID: localEntry.persistentModelID,
            startTime: Date(),
            startPage: localEntry.currentPage
        )
        activeSessionStorage.save(sessionInfo)

        // 4. Update entry status if needed
        if localEntry.readingStatus != .reading {
            localEntry.readingStatus = .reading
            localEntry.touch()
        }

        try context.save()

        // 5. Notify UI
        await notifySessionStateChanged()
    }

    public func endSession(endPage: Int) async throws -> ReadingSession {
        // 1. Validate active session
        guard let sessionInfo = activeSessionStorage.load() else {
            throw SessionError.notActive
        }

        // 2. Calculate duration
        let duration = Date().timeIntervalSince(sessionInfo.startTime)
        let durationMinutes = max(1, Int(duration / 60))

        // 3. Create session record
        let context = ModelContext(modelContainer)
        guard let entry = context.model(for: sessionInfo.entryID) as? UserLibraryEntry else {
            throw SessionError.entryNotFound
        }

        let newSession = ReadingSession(
            durationMinutes: durationMinutes,
            startPage: sessionInfo.startPage,
            endPage: endPage,
            entry: entry
        )
        context.insert(newSession)

        // 4. Update entry
        entry.currentPage = endPage
        entry.updateReadingProgress()
        entry.touch()

        try context.save()

        // 5. Clear active session
        activeSessionStorage.clear()

        // 6. Notify UI
        await notifySessionStateChanged()

        return newSession
    }

    public func isSessionActive() -> Bool {
        activeSessionStorage.hasActiveSession
    }

    public func currentSessionInfo() -> ActiveSessionInfo? {
        activeSessionStorage.load()
    }

    // MARK: - Private Helpers

    private func notifySessionStateChanged() async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .readingSessionStateChanged,
                object: nil
            )
        }
    }
}
```

---

## State Persistence

### Active Session Storage

Active sessions are persisted to UserDefaults to survive app termination:

```swift
struct ActiveSessionInfo: Codable, Sendable {
    let entryID: PersistentIdentifier
    let startTime: Date
    let startPage: Int
}

final class ActiveSessionStorage: Sendable {
    private let userDefaults: UserDefaults
    private let key = "com.bookstrack.activeSession"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(_ info: ActiveSessionInfo) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(info) {
            userDefaults.set(data, forKey: key)
        }
    }

    func load() -> ActiveSessionInfo? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ActiveSessionInfo.self, from: data)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }

    var hasActiveSession: Bool {
        load() != nil
    }
}
```

---

## UI/UX Design

### Timer Button States

```swift
enum SessionTimerState {
    case notStarted
    case active(startTime: Date)
    case loading
}

struct SessionTimerButton: View {
    let state: SessionTimerState
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: buttonAction) {
            HStack {
                buttonIcon
                buttonText
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonBackground)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(state == .loading)
    }

    private var buttonAction: () -> Void {
        switch state {
        case .notStarted: return onStart
        case .active: return onStop
        case .loading: return {}
        }
    }

    private var buttonIcon: some View {
        switch state {
        case .notStarted:
            return Image(systemName: "play.fill")
        case .active:
            return Image(systemName: "stop.fill")
        case .loading:
            return Image(systemName: "circle.dotted")
        }
    }

    private var buttonText: Text {
        switch state {
        case .notStarted:
            return Text("Start Reading Session")
        case .active(let startTime):
            return Text("Stop Session • \(elapsedTime(from: startTime))")
        case .loading:
            return Text("Saving...")
        }
    }

    private func elapsedTime(from startTime: Date) -> String {
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

---

## Query Optimization

### Efficient Session Queries

```swift
extension UserLibraryEntry {
    /// Fetch sessions efficiently with predicate
    func recentSessions(limit: Int = 10) -> [ReadingSession] {
        guard let id = self.persistentModelID else { return [] }

        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { session in
                session.entry?.persistentModelID == id
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let context = modelContext
        return (try? context.fetch(descriptor)) ?? []
    }
}
```

### Aggregate Queries for Analytics

```swift
extension ReadingStats {
    static func totalReadingTime(for userID: String, in period: DateInterval) -> Int {
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { session in
                session.entry?.userID == userID &&
                session.date >= period.start &&
                session.date <= period.end
            }
        )

        guard let sessions = try? context.fetch(descriptor) else { return 0 }
        return sessions.reduce(0) { $0 + $1.durationMinutes }
    }
}
```

---

## Error Handling

### Session Errors

```swift
public enum SessionError: Error, LocalizedError, Sendable {
    case alreadyActive
    case notActive
    case entryNotFound
    case invalidPageNumber
    case sessionTooShort
    case persistenceFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "A reading session is already active. End the current session before starting a new one."
        case .notActive:
            return "No active reading session found."
        case .entryNotFound:
            return "Library entry not found. The book may have been deleted."
        case .invalidPageNumber:
            return "Invalid page number. Ending page must be greater than or equal to starting page."
        case .sessionTooShort:
            return "Session duration too short. Minimum 1 minute required."
        case .persistenceFailed(let error):
            return "Failed to save session: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .alreadyActive:
            return "End your current session first."
        case .notActive:
            return "Start a new reading session."
        case .entryNotFound:
            return "Try restarting the app or selecting a different book."
        case .invalidPageNumber:
            return "Enter a valid ending page number."
        case .sessionTooShort:
            return "Read for at least 1 minute before ending the session."
        case .persistenceFailed:
            return "Check available storage space and try again."
        }
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
@Test("ReadingSession computes pagesRead correctly")
func testPagesReadComputation() {
    let entry = createTestEntry()
    let session = ReadingSession(
        durationMinutes: 30,
        startPage: 10,
        endPage: 50,
        entry: entry
    )

    #expect(session.pagesRead == 40)
}

@Test("ReadingSession computes readingPace correctly")
func testReadingPaceComputation() {
    let entry = createTestEntry()
    let session = ReadingSession(
        durationMinutes: 30,
        startPage: 10,
        endPage: 70,
        entry: entry
    )

    // 60 pages in 30 minutes = 120 pages/hour
    #expect(session.readingPace == 120.0)
}
```

### Integration Tests

```swift
@Test("Full session lifecycle persists correctly")
func testSessionLifecycle() async throws {
    let container = createTestContainer()
    let service = ReadingSessionService(modelContainer: container)
    let entry = createTestEntry(in: container)

    // Start session
    try await service.startSession(for: entry)
    #expect(service.isSessionActive())

    // Simulate reading time
    try await Task.sleep(for: .seconds(2))

    // End session
    let session = try await service.endSession(endPage: 50)
    #expect(!service.isSessionActive())
    #expect(session.startPage == entry.currentPage)
    #expect(session.endPage == 50)
}
```

---

## Performance Considerations

### Indexing

```swift
// Add index to date for efficient time-based queries
@Model
public final class ReadingSession {
    @Attribute(.indexed) public var date: Date
    // ... other properties
}
```

### Denormalization

Store `workPersistentID` directly on `ReadingSession` to avoid joining through `UserLibraryEntry` for work-level queries.

### Batch Operations

When fetching sessions for analytics, use batch fetch limits and pagination:

```swift
let descriptor = FetchDescriptor<ReadingSession>(
    predicate: predicate,
    sortBy: [SortDescriptor(\.date, order: .reverse)]
)
descriptor.fetchLimit = 100 // Limit to most recent 100 sessions
```

---

## Future Enhancements

### Phase 2 (Intelligence Layer)
- **Pattern Recognition:** Identify optimal reading times, favorite genres by time of day
- **Pace Trends:** Track reading pace changes over time
- **Goal Predictions:** Estimate book completion dates based on pace

### Phase 3 (Social Features)
- **Shared Sessions:** Allow reading circles to see each other's reading activity (privacy-controlled)
- **Group Challenges:** Track group reading time towards shared goals

### Phase 4 (Discovery & Polish)
- **Mood Tracking:** Add optional mood before/after reading
- **Environmental Context:** Optional location, weather, social context
- **Reading Interruptions:** Track interruption patterns

---

## Migration Strategy

### v1 → v2 Migration

1. **Add ReadingSession to schema** (non-breaking)
2. **Add readingSessions relationship to UserLibraryEntry** (non-breaking)
3. **No data migration needed** - new feature, no existing data

### Rollback Plan

If critical bugs found:
1. Remove ReadingSession from schema
2. Remove UI components
3. Clear UserDefaults active session data
4. Revert to v1 schema

---

## Security & Privacy

### Local-First Storage
- All session data stored in local SwiftData
- No cloud sync (future opt-in feature)
- No analytics or telemetry

### Data Retention
- Sessions retained indefinitely (user-controlled deletion in future)
- Active session data in UserDefaults cleared on completion
- No PII collected (only reading activity)

---

## Dependencies

### Internal
- `UserLibraryEntry` model
- `Work` model
- `ReadingStats` model

### External
- SwiftData (iOS 26+)
- Swift 6 Concurrency (async/await, actors)

---

## Success Criteria

- [ ] Users can start/stop reading sessions reliably
- [ ] Session data persists across app restarts
- [ ] Reading pace calculated accurately
- [ ] No performance degradation with 1000+ sessions
- [ ] Zero crashes related to session management
- [ ] Timer UI updates in real-time without lag

---

**Created:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Design Phase - Ready for implementation
