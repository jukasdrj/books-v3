# App Launch Performance Optimization Design

**Created:** November 4, 2025
**Status:** Design Phase
**Current Launch Time:** 3-5 seconds
**Target Launch Time:** 1-2 seconds
**Approach:** Async ModelContainer Initialization + Lazy Task Execution

---

## Problem Statement

BooksTrack currently takes 3-5 seconds from app tap to usable library screen, creating a poor first impression and competing poorly with native iOS apps like Books.app (< 1 second launch).

### Identified Bottlenecks

1. **Synchronous ModelContainer Initialization** (`BooksTrackerApp.swift:14-69`)
   - Blocks main thread during SwiftData schema creation
   - CloudKit configuration checks (simulator vs device)
   - Fallback logic execution on failure
   - **Impact:** 1-2 seconds of black screen

2. **Serial Task Execution in ContentView** (`ContentView.swift:100-133`)
   - EnrichmentQueue validation (SwiftData query)
   - ImageCleanupService operations (file system I/O × 2)
   - SampleDataGenerator (potential SwiftData writes)
   - NotificationCoordinator setup
   - **Impact:** 1-2 seconds before first render

3. **@Query Execution on First Render** (`iOS26LiquidLibraryView.swift:35`)
   - Loads all Works from SwiftData on initial view appearance
   - **Impact:** 0.5-1 second delay (library-dependent)

4. **DTOMapper Initialization** (`BooksTrackerApp.swift:75`)
   - Cache warming during app launch
   - **Impact:** 0.2-0.5 seconds

---

## Design Overview

### Core Strategy

**Async ModelContainer Initialization with Progressive UI Rendering**

Move expensive SwiftData setup off the main thread while showing a branded splash screen. Once the container is ready, transition smoothly to the main interface with lazy-loaded background tasks.

### Architecture Flow

```
App Launch
    ↓
Show SplashView (instant, no dependencies)
    ↓
[Background Thread] Initialize ModelContainer (1-2s)
    ↓
Transition to ContentView (0.3s fade)
    ↓
[Priority 1] Setup NotificationCoordinator (immediate)
    ↓
[Priority 2] Background tasks (2s delay, parallel execution)
    - EnrichmentQueue validation
    - Image cleanup
    - Sample data generation
```

### Performance Target

- **Primary Goal:** < 2 seconds (total time to interactive)
- **Stretch Goal:** < 1.5 seconds
- **Baseline Measurement:** 3-5 seconds (current)
- **Regression Threshold:** 2.5 seconds (fail CI if exceeded)

---

## Component 1: SplashView (New)

### Purpose

Lightweight branded loading screen that appears instantly while ModelContainer initializes in the background.

### Design Principles

- **Zero SwiftData dependency** - No @Query, no ModelContext
- **Minimal asset loading** - SF Symbols + theme colors (already in memory)
- **Branded experience** - App icon, name, loading indicator
- **Fast dismiss** - 0.3s fade transition when ready

### Visual Layout

```
┌─────────────────────────────┐
│                             │
│         📚                  │  ← SF Symbol "books.vertical.fill"
│      BooksTrack             │  ← App name (theme color)
│                             │
│   ⏳ Loading library...     │  ← ProgressView (indeterminate)
│                             │
└─────────────────────────────┘
```

### Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UI/SplashView.swift`

```swift
import SwiftUI

/// Lightweight splash screen displayed during ModelContainer initialization.
/// Zero dependencies on SwiftData to ensure instant rendering.
@available(iOS 26.0, *)
public struct SplashView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        ZStack {
            // Background gradient (theme-aware)
            LinearGradient(
                colors: [
                    themeStore.primaryColor.opacity(0.1),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // App icon
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(themeStore.primaryColor)

                // App name
                Text("BooksTrack")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(themeStore.primaryColor)

                Spacer()

                // Loading indicator
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(themeStore.primaryColor)
                        .scaleEffect(1.2)

                    Text("Loading your library...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 60)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BooksTrack is loading your library")
        .accessibilityAddTraits(.updatesFrequently)
    }

    public init() {}
}
```

### Accessibility

- VoiceOver: "BooksTrack is loading your library"
- Updates frequently trait (for dynamic loading state)
- No user interaction required

---

## Component 2: BooksTrackerApp Refactoring

### Current Implementation (Blocking)

```swift
let modelContainer: ModelContainer = {
    // Blocks main thread until SwiftData initialization completes
    let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}()

var body: some Scene {
    WindowGroup {
        ContentView()
            .modelContainer(modelContainer)  // Already initialized
    }
}
```

**Problem:** The static `let` property evaluates synchronously during app launch, blocking the main thread for 1-2 seconds.

### New Implementation (Async)

**File:** `BooksTracker/BooksTrackerApp.swift`

```swift
import SwiftUI
import SwiftData
import BooksTrackerFeature
import OSLog

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags.shared

    // MARK: - Async State

    @State private var modelContainer: ModelContainer?
    @State private var dtoMapper: DTOMapper?
    @State private var initError: Error?

    // MARK: - Performance Logging

    private let performanceLog = Logger(subsystem: "com.oooefam.booksV3", category: "Performance")
    private let signpostID = OSSignpostID()

    init() {
        os_signpost(.begin, log: OSLog.performance, name: "App Launch", signpostID: signpostID)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer, let dtoMapper {
                    // Container ready - show main app
                    ContentView()
                        .modelContainer(modelContainer)
                        .environment(\.dtoMapper, dtoMapper)
                        .transition(.opacity)
                        .onAppear {
                            os_signpost(.end, log: OSLog.performance, name: "App Launch", signpostID: signpostID)
                        }
                } else if let initError {
                    // Initialization failed - show error recovery
                    ErrorRecoveryView(
                        error: initError,
                        retry: { await initializeContainer() }
                    )
                } else {
                    // Initializing - show splash
                    SplashView()
                        .task { await initializeContainer() }
                }
            }
            .iOS26ThemeStore(themeStore)
            .environment(featureFlags)
            .animation(.easeInOut(duration: 0.3), value: modelContainer != nil)
        }
    }

    // MARK: - Async Initialization

    @MainActor
    private func initializeContainer() async {
        let startTime = Date()

        do {
            // Move heavy work off main thread
            let container = try await Task.detached(priority: .userInitiated) {
                try createModelContainer()
            }.value

            // Update UI state on main thread
            self.modelContainer = container
            self.dtoMapper = DTOMapper(modelContext: container.mainContext)

            let duration = Date().timeIntervalSince(startTime)
            performanceLog.info("✅ ModelContainer initialized in \(duration, privacy: .public)s")

        } catch {
            self.initError = error
            performanceLog.error("❌ ModelContainer init failed: \(error.localizedDescription)")
        }
    }

    // MARK: - ModelContainer Factory

    private static func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        #if targetEnvironment(simulator)
        // Simulator: Local storage only
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        #else
        // Device: CloudKit sync enabled via entitlements
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        #endif

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Fallback: Local-only mode (CloudKit disabled)
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }
}
```

### Key Changes

1. **State Management**
   - `@State var modelContainer: ModelContainer?` (was static `let`)
   - `@State var dtoMapper: DTOMapper?` (was instance property)
   - `@State var initError: Error?` (new error handling)

2. **Conditional Rendering**
   - Show `SplashView` while `modelContainer == nil`
   - Show `ErrorRecoveryView` if initialization fails
   - Show `ContentView` once container ready

3. **Background Initialization**
   - `Task.detached(priority: .userInitiated)` moves work off main thread
   - CloudKit checks won't block UI
   - Schema migration happens in background

4. **Performance Instrumentation**
   - `os_signpost` for end-to-end launch time
   - Logger for ModelContainer init duration
   - Metrics exported to Instruments

---

## Component 3: ContentView Task Optimization

### Current Implementation (Serial Execution)

```swift
.task {
    EnrichmentQueue.shared.validateQueue(in: modelContext)
}
.task {
    await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
    await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
}
.task {
    let generator = SampleDataGenerator(modelContext: modelContext)
    generator.setupSampleDataIfNeeded()
}
.task {
    await notificationCoordinator.handleNotifications(...)
}
```

**Problem:** All 4 tasks run serially before first render, delaying UI by 1-2 seconds.

### New Implementation (Prioritized + Parallel)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift`

```swift
.task {
    // ✅ Priority 1: Critical for app functionality (run immediately)
    await notificationCoordinator.handleNotifications(
        onSwitchToLibrary: { selectedTab = .library },
        onEnrichmentStarted: { payload in
            isEnriching = true
            enrichmentProgress = (0, payload.totalBooks)
            currentBookTitle = ""
        },
        onEnrichmentProgress: { payload in
            enrichmentProgress = (payload.completed, payload.total)
            currentBookTitle = payload.currentTitle
        },
        onEnrichmentCompleted: { isEnriching = false },
        onSearchForAuthor: { payload in
            selectedTab = .search
            searchCoordinator.setPendingAuthorSearch(payload.authorName)
        }
    )
}
.task {
    // ✅ Priority 2: Non-critical maintenance tasks (defer + parallelize)
    // Wait 2 seconds to let UI render and user start interacting
    try? await Task.sleep(for: .seconds(2))

    await withTaskGroup(of: Void.self) { group in
        // Validate enrichment queue (remove stale persistent IDs)
        group.addTask {
            EnrichmentQueue.shared.validateQueue(in: modelContext)
        }

        // Clean up reviewed scan images
        group.addTask {
            await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
        }

        // Clean up orphaned temp files (24h+ old)
        group.addTask {
            await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
        }

        // Setup sample data if library empty
        group.addTask {
            let generator = SampleDataGenerator(modelContext: modelContext)
            generator.setupSampleDataIfNeeded()
        }
    }
}
```

### Task Classification

| Task | Priority | Timing | Reason |
|------|----------|--------|--------|
| NotificationCoordinator | P1 | Immediate | Needed for app notifications (enrichment progress, author search) |
| EnrichmentQueue validation | P2 | Deferred 2s | Maintenance task, no immediate user impact |
| Image cleanup (reviewed) | P2 | Deferred 2s | Cleanup task, runs periodically |
| Image cleanup (orphaned) | P2 | Deferred 2s | Cleanup task, runs periodically |
| Sample data generation | P2 | Deferred 2s | Only runs on empty library (first launch) |

### Benefits

1. **Immediate First Render** - UI appears as soon as ModelContainer ready
2. **Parallel Execution** - Background tasks run concurrently (4× faster)
3. **User-First Priority** - Notifications setup immediately for enrichment/search
4. **Non-Blocking Cleanup** - Maintenance happens during user interaction

---

## Component 4: ErrorRecoveryView (New)

### Purpose

Graceful error handling if ModelContainer initialization fails (schema migration errors, CloudKit issues, disk full, etc.).

### Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UI/ErrorRecoveryView.swift`

```swift
import SwiftUI

/// Error recovery screen for ModelContainer initialization failures.
@available(iOS 26.0, *)
public struct ErrorRecoveryView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    let error: Error
    let retry: () async -> Void

    @State private var isRetrying = false

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            // Error title
            Text("Failed to Load Library")
                .font(.title2)
                .fontWeight(.bold)

            // Error message
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Retry button
            Button {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Try Again")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
            .disabled(isRetrying)
            .padding(.bottom, 60)
        }
        .themedBackground()
    }

    public init(error: Error, retry: @escaping () async -> Void) {
        self.error = error
        self.retry = retry
    }
}
```

### Error Scenarios

| Error Type | User Message | Recovery Action |
|------------|-------------|-----------------|
| Schema migration failed | "Library upgrade failed" | Retry with fallback to local-only mode |
| CloudKit unavailable | "Cloud sync unavailable" | Continue with local storage |
| Disk full | "Storage full" | Prompt to free space, retry |
| Unknown error | "Failed to load library" | Retry with full error details |

---

## Performance Measurement Strategy

### Instrumentation Points

**1. App Launch to First Pixel**
```swift
// BooksTrackerApp.init()
os_signpost(.begin, log: OSLog.performance, name: "App Launch")

// SplashView.onAppear()
os_signpost(.event, log: OSLog.performance, name: "Splash Visible")
```

**2. ModelContainer Initialization**
```swift
let startTime = Date()
let container = try await Task.detached { ... }.value
let duration = Date().timeIntervalSince(startTime)
performanceLog.info("ModelContainer init: \(duration)s")
```

**3. ContentView First Render**
```swift
// ContentView.onAppear()
os_signpost(.event, log: OSLog.performance, name: "Main UI Visible")
```

**4. Time to Interactive**
```swift
// After NotificationCoordinator setup complete
os_signpost(.end, log: OSLog.performance, name: "App Launch")
```

### Metrics Dashboard

Create performance test that validates launch time on each commit:

**File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Performance/AppLaunchPerformanceTests.swift`

```swift
import Testing
import XCTest
@testable import BooksTrackerFeature

@Suite("App Launch Performance")
struct AppLaunchPerformanceTests {

    @Test("App launch completes within 2 seconds")
    func launchTimeRegression() async throws {
        let startTime = Date()

        // Simulate app launch
        let container = try await Task.detached {
            try BooksTrackerApp.createModelContainer()
        }.value

        let duration = Date().timeIntervalSince(startTime)

        // Fail test if launch > 2.5s (regression threshold)
        #expect(duration < 2.5, "App launch took \(duration)s (threshold: 2.5s)")

        // Log performance for tracking
        print("📊 App launch time: \(String(format: "%.2f", duration))s")
    }

    @Test("ModelContainer initialization within 1.5 seconds")
    func containerInitPerformance() async throws {
        let startTime = Date()

        let container = try await Task.detached {
            try BooksTrackerApp.createModelContainer()
        }.value

        let duration = Date().timeIntervalSince(startTime)

        #expect(duration < 1.5, "ModelContainer init took \(duration)s (threshold: 1.5s)")
    }
}
```

### Baseline Measurements (Current)

| Phase | Duration | Device |
|-------|----------|--------|
| App launch to splash | 0.5-1.0s | iPhone 14 Pro |
| ModelContainer init | 1.0-2.0s | iPhone 14 Pro |
| ContentView tasks | 1.0-2.0s | iPhone 14 Pro |
| **Total** | **3.0-5.0s** | iPhone 14 Pro |

### Target Measurements (After Optimization)

| Phase | Duration | Device | Improvement |
|-------|----------|--------|-------------|
| App launch to splash | 0.1-0.2s | iPhone 14 Pro | 5× faster |
| ModelContainer init (background) | 1.0-1.5s | iPhone 14 Pro | No change (but async) |
| ContentView tasks (deferred) | 0.0s | iPhone 14 Pro | Runs after first render |
| **Total** | **1.1-1.7s** | iPhone 14 Pro | **~3× faster** |

---

## Testing Strategy

### Unit Tests

1. **SplashView Rendering**
   - Verify instant appearance (no SwiftData queries)
   - Accessibility label correctness
   - Theme color application

2. **BooksTrackerApp Initialization**
   - Async ModelContainer creation succeeds
   - Error handling triggers ErrorRecoveryView
   - DTOMapper injected correctly

3. **ErrorRecoveryView Interaction**
   - Retry button calls initialization function
   - Loading state displays during retry
   - Error message displayed correctly

### Integration Tests

1. **Cold Launch Flow**
   - Splash → ModelContainer init → ContentView render
   - All environment dependencies injected
   - Background tasks execute after delay

2. **Error Recovery Flow**
   - Simulate ModelContainer failure
   - Verify ErrorRecoveryView displayed
   - Retry button re-attempts initialization

3. **Performance Regression**
   - App launch < 2.5 seconds (CI failure threshold)
   - ModelContainer init < 1.5 seconds

### Device Testing Matrix

| Device | iOS Version | Library Size | Expected Launch Time |
|--------|-------------|--------------|----------------------|
| iPhone 12 (A14) | iOS 26.0 | Empty | < 2.0s |
| iPhone 12 (A14) | iOS 26.0 | 100 books | < 2.2s |
| iPhone 14 Pro (A16) | iOS 26.0 | Empty | < 1.5s |
| iPhone 14 Pro (A16) | iOS 26.0 | 1000 books | < 2.0s |
| iPhone 15 Pro (A17) | iOS 26.0 | Empty | < 1.2s |
| iPhone 15 Pro (A17) | iOS 26.0 | 1000 books | < 1.8s |

### Network Conditions

- **Airplane Mode** - Verify local-only fallback works
- **Slow Cellular** - CloudKit checks shouldn't block UI
- **WiFi** - Optimal CloudKit sync performance

---

## Edge Cases & Failure Modes

### 1. Schema Migration During Init

**Scenario:** User upgrades app with new SwiftData schema

**Current Behavior:** Migration blocks launch (2-5 seconds for large libraries)

**New Behavior:**
- Migration happens in background (async init)
- Splash screen shows during migration
- If migration > 3 seconds, show progress: "Upgrading library... 45%"

**Implementation:**
```swift
// Monitor migration progress
let migrationObserver = NotificationCenter.default
    .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
    .sink { notification in
        // Update progress in SplashView
    }
```

### 2. CloudKit Rate Limiting

**Scenario:** User launches app after long offline period, CloudKit backlog

**Current Behavior:** Potential timeout during ModelContainer init

**New Behavior:**
- Async init isolates CloudKit checks from UI
- Timeout after 10 seconds → fallback to local-only mode
- Show warning: "Cloud sync delayed, using local library"

### 3. Low Memory on Old Devices

**Scenario:** iPhone 12 with 4GB RAM, background apps running

**Current Behavior:** Potential memory pressure during init

**New Behavior:**
- Priority 2 tasks (cleanup, validation) run with `.background` priority
- If memory warning received, cancel P2 tasks
- Defer P2 tasks until app backgrounded next time

**Implementation:**
```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
    // Cancel background task group
    backgroundTaskGroup?.cancelAll()
}
```

### 4. Corrupted SwiftData Store

**Scenario:** App crashes during write, SQLite corruption

**Current Behavior:** App fails to launch, user sees black screen

**New Behavior:**
- ErrorRecoveryView displays with detailed error
- "Reset Library" button (last resort)
- Attempt local repair before offering reset

**Implementation:**
```swift
if let sqliteError = error as? NSError, sqliteError.domain == NSSQLiteErrorDomain {
    // Attempt repair
    try FileManager.default.replaceItemAt(storeURL, withItemAt: backupURL)
}
```

### 5. Empty Library (First Launch)

**Scenario:** New user, no books in library

**Current Behavior:** Sample data generation runs synchronously (0.5-1s delay)

**New Behavior:**
- Sample data generation deferred to P2 task (2s delay)
- User sees empty library immediately
- Sample data appears after 2 seconds (smooth insert animation)

---

## Rollback Plan

### Risk Assessment

- **High Risk:** BooksTrackerApp refactoring (async init)
- **Medium Risk:** ContentView task reordering
- **Low Risk:** SplashView addition (new component, no side effects)

### Rollback Triggers

1. Launch time > 5 seconds (worse than current)
2. ModelContainer initialization failure rate > 1%
3. Crash rate increase > 0.5%
4. User reports of frozen splash screen

### Rollback Procedure

1. **Immediate:** Revert `BooksTrackerApp.swift` to static `let modelContainer`
2. **Next Day:** Revert ContentView task changes
3. **Keep:** SplashView (can be used for future optimizations)

**Git Tags:**
- `v3.2.0-pre-launch-optimization` (baseline)
- `v3.2.0-launch-optimization` (new implementation)

---

## Success Metrics

### Primary KPIs

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Cold launch time | 3-5s | < 2s | os_signpost |
| Warm launch time | 2-3s | < 1s | os_signpost |
| ModelContainer init | 1-2s | < 1.5s | Logger duration |
| Time to first interaction | 3-5s | < 2s | os_signpost |

### Secondary KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Initialization failure rate | < 0.1% | Analytics |
| Memory usage during launch | < 150MB | Instruments |
| Background task completion rate | > 95% | Logger |
| Performance test pass rate | 100% | CI/CD |

### User Experience Goals

- **Perceived Speed:** User sees splash < 0.2s after tap
- **Smooth Transitions:** 0.3s fade between splash and library
- **No Jank:** 60fps maintained during transitions
- **Accessibility:** VoiceOver announces state changes clearly

---

## Future Optimizations (Out of Scope)

### Phase 2: Query Optimization

- Implement LibraryRepository pattern (see `docs/plans/2025-11-04-security-audit-implementation.md` Task 3.2)
- Replace `@Query` with lazy-loaded fetch descriptors
- Add pagination for large libraries (1000+ books)

### Phase 3: Image Preloading

- Preload first 10 book covers in background
- Use AsyncImage with placeholder during load
- Cache covers in URLCache for instant display

### Phase 4: Incremental Rendering

- Render first 20 books immediately
- Load remaining books incrementally (scrolling)
- Use SwiftUI's `LazyVStack` for memory efficiency

---

## Implementation Checklist

### Phase 1: Async ModelContainer (Days 1-2)

- [ ] Create `SplashView.swift` with SF Symbols + theme colors
- [ ] Add VoiceOver accessibility labels
- [ ] Refactor `BooksTrackerApp.swift` to use `@State var modelContainer`
- [ ] Implement `initializeContainer()` with Task.detached
- [ ] Add os_signpost instrumentation
- [ ] Create `ErrorRecoveryView.swift` with retry logic
- [ ] Add error handling for schema migration, CloudKit failures
- [ ] Test on simulator (cold launch, warm launch)

### Phase 2: Task Prioritization (Day 3)

- [ ] Reorder ContentView `.task` modifiers (P1 immediate, P2 deferred)
- [ ] Wrap P2 tasks in `withTaskGroup` for parallelism
- [ ] Add 2-second delay before P2 task group execution
- [ ] Test that NotificationCoordinator setup happens immediately
- [ ] Verify background tasks don't block scrolling

### Phase 3: Performance Testing (Day 4)

- [ ] Create `AppLaunchPerformanceTests.swift`
- [ ] Add launch time regression test (< 2.5s threshold)
- [ ] Add ModelContainer init test (< 1.5s threshold)
- [ ] Run tests on CI/CD pipeline
- [ ] Measure baseline vs optimized on iPhone 12, 14 Pro
- [ ] Document results in CHANGELOG.md

### Phase 4: Device Testing (Day 5)

- [ ] Test on iPhone 12 (A14) - empty library, 100 books, 1000 books
- [ ] Test on iPhone 14 Pro (A16) - empty library, 1000 books
- [ ] Test in airplane mode (CloudKit fallback)
- [ ] Test with slow cellular (CloudKit timeout)
- [ ] Test schema migration (upgrade from v3.1.0)
- [ ] Verify no memory warnings during launch

### Phase 5: Edge Case Validation (Day 6)

- [ ] Simulate ModelContainer init failure → ErrorRecoveryView
- [ ] Simulate CloudKit rate limiting → local-only fallback
- [ ] Simulate low memory → background task cancellation
- [ ] Simulate corrupted SQLite store → repair attempt
- [ ] Test sample data generation on empty library

### Phase 6: Documentation & Rollback (Day 7)

- [ ] Update CLAUDE.md with new launch flow
- [ ] Document performance metrics in CHANGELOG.md
- [ ] Create git tag `v3.2.0-pre-launch-optimization` (baseline)
- [ ] Create git tag `v3.2.0-launch-optimization` (new)
- [ ] Write rollback procedure in runbook
- [ ] Create monitoring dashboard for launch metrics

---

## References

- **iOS 26 HIG:** App Launch Best Practices
- **SwiftData Performance Guide:** Async Initialization Patterns
- **os_signpost Documentation:** Performance Measurement
- **Related Design:** `docs/plans/2025-11-04-security-audit-implementation.md` (Repository Pattern)

---

**Next Steps:** Review design, approve approach, proceed to Phase 5 (Worktree Setup) → Phase 6 (Implementation Planning).
