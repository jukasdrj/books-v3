# Implementation Plan: Remaining GitHub Issues (Excluding #201)

**Date:** November 14, 2025  
**Author:** Claude Code + Gemini 2.5 Pro Planner  
**Continuation ID:** `6c4844d4-be1d-4e2b-8d4f-4c0f7ebbeb2a`  
**Status:** Ready for Implementation

---

## Executive Summary

**Scope:** 6 issues to resolve (7 total, excluding #201)  
**Timeline:** 2 weeks (Dec 11-22, 2025)  
**Sprint 3 Priority:** Issue #426 (Rate Limit Timer)

```
Priority Distribution:
├── MUST SHIP (Sprint 3)
│   └── #426 - Rate limit countdown timer
├── SHOULD SHIP (Quick Wins)  
│   ├── #435 - Tighten grid range (10-30 min)
│   └── #434 - Visual press feedback (20 min)
├── HIGH ROI (Performance)
│   ├── #436 - Skeleton screens (1-2 hr)
│   └── #437 - Image prefetching (1 hr)
└── BACKEND DEPENDENT
    └── #428 - CORS error handling (low priority)
```

---

## Issue Categorization

### Category 1: Backend Coordination Required

**#426 - Rate limit countdown timer UI** (HIGHEST PRIORITY)
- **Status:** Sprint 3 commitment, medium priority
- **Backend:** Already supports `Retry-After` header
- **Affected Services:** BookshelfAIService, EnrichmentService, CSVImportService
- **Dependencies:** None (backend ready)
- **Effort:** 2-3 hours

**#428 - CORS error handling**
- **Status:** Low priority, future web deployment only
- **Backend:** Needs `X-Custom-Error: CORS_BLOCKED` header
- **Current Impact:** Capacitor builds work fine (iOS whitelist ✅)
- **Dependencies:** Backend team coordination
- **Effort:** 1-2 hours

### Category 2: UI/UX Performance Enhancements (All LOW Priority)

**#435 - Tighten adaptive grid range**
- **Impact:** Reduces layout jumps during rotation/multitasking
- **Location:** `iOS26LiquidLibraryView.swift:246-247`
- **Options:** Quick fix (10 min) OR Size class based (30 min)
- **Effort:** 10-30 minutes

**#434 - Visual press feedback**
- **Impact:** Better perceived responsiveness
- **Applies to:** Floating grid, adaptive cards, liquid list rows
- **Enhancement:** Optional haptic feedback
- **Effort:** 20 minutes

**#436 - Skeleton screens for library load**
- **Impact:** 30% faster perceived performance
- **Components:** BookCardSkeleton, ShimmerEffect
- **Accessibility:** VoiceOver "Loading" announcement
- **Effort:** 1-2 hours

**#437 - Cover image prefetching in search**
- **Impact:** 200ms+ faster scroll, smoother experience
- **Risk:** Memory management critical
- **Mitigation:** Conservative limits, memory pressure monitoring
- **Effort:** 1 hour

---

## Implementation Phases

### PHASE 1: Error Handling & User Feedback (Week 1, Days 1-3)

#### Issue #426: Rate Limit Timer Implementation

**Day 1-2: Core Implementation**

```
Implementation Flow:
├── Verify ApiErrorCode enum exists
├── Create RateLimitBanner.swift component
│   ├── Parse Retry-After header
│   ├── Countdown timer (Task.sleep pattern)
│   ├── Display: "Too many requests. Try again in {N}s."
│   └── Auto-dismiss at zero
├── Update ApiErrorCode enum
│   └── Add RATE_LIMIT_EXCEEDED case
└── Integration into views
    ├── BookshelfScannerView
    ├── EnrichmentQueueView
    └── CSVImportView
```

**Error Response Parsing:**
1. Extract `Retry-After` from HTTP headers
2. Fallback to `details.retryAfter` in response body
3. Default to 60s if both missing

**Testing Checklist:**
- [ ] Simulate 429 response with mock server
- [ ] Verify countdown updates every second
- [ ] Confirm buttons disabled during countdown
- [ ] Test banner dismissal after countdown
- [ ] VoiceOver announces countdown status

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/ApiErrorCode.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Components/RateLimitBanner.swift` (NEW)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/BookshelfScannerView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/EnrichmentQueueView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/CSVImportView.swift`

**Unit Tests Required:**
```swift
// RateLimitBannerTests.swift
- testCountdownTimerDecrementsEverySecond()
- testBannerDismissesAtZero()
- testRetryAfterHeaderParsing()
- testRetryAfterBodyParsing()
- testDefaultsTo60Seconds()
- testAccessibilityAnnouncement()
```

---

#### Issue #428: CORS Error Handling

**Implementation Steps:**

```
Backend Coordination:
├── Open cross-repo issue in bookstrack-backend
├── Request X-Custom-Error: CORS_BLOCKED header
└── Link to iOS issue #428

iOS Implementation:
├── Add CORS_BLOCKED to ApiErrorCode enum
├── Detection in EnrichmentAPIClient
├── Detection in BookSearchAPIService
└── Heuristic fallback (null origin, 0 status)

User Experience:
├── Display: "Network error - check your connection"
└── Debug logging (Xcode console only)
```

**Testing Checklist:**
- [ ] Mock CORS error with custom URLProtocol
- [ ] User-friendly message displays
- [ ] Debug logs appear in Xcode console
- [ ] Test with real CORS blocked origin (if backend ready)

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/ApiErrorCode.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/EnrichmentAPIClient.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/BookSearchAPIService.swift`

**Backend Coordination:**
- Create issue in `bookstrack-backend` repository
- Link to iOS issue #428
- Wait for backend team confirmation before final testing

---

### PHASE 2: Layout & Interaction Polish (Week 1, Days 4-5)

#### Issue #435: Grid Stability (QUICK WIN)

**Option 2 (RECOMMENDED): Size Class Based**

```swift
private var gridColumns: [GridItem] {
    switch horizontalSizeClass {
    case .compact:
        return [GridItem(.flexible()), GridItem(.flexible())]  // 2 columns
    case .regular:
        return Array(repeating: GridItem(.flexible()), count: 4)  // 4 columns
    default:
        return [GridItem(.adaptive(minimum: 165), spacing: 16)]
    }
}
```

**Alternative (Option 1): Quick Fix**
```swift
GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)
// 20pt range instead of 50pt
```

**Testing Checklist:**
- [ ] Rotation on iPhone (portrait ↔ landscape)
- [ ] iPad multitasking (1/2, 1/3, 2/3 splits)
- [ ] Dynamic Type size changes
- [ ] Landscape mode stability
- [ ] No jarring size jumps during transitions

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/iOS26LiquidLibraryView.swift:246-247`

---

#### Issue #434: Press Feedback (QUICK WIN)

**Implementation:**

```swift
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Apply to all book card types
.buttonStyle(ScaleButtonStyle())
```

**Optional iOS 26 Enhancement:**
```swift
.sensoryFeedback(.selection, trigger: tapGesture)
```

**Application Points:**
- Floating grid cards (line 250-256)
- Adaptive cards (line 268)
- Liquid list rows (line 281)

**Testing Checklist:**
- [ ] Visual feedback on tap (smooth scale animation)
- [ ] No interference with NavigationLink navigation
- [ ] 60fps animation (profile with Instruments)
- [ ] Works on iPad with trackpad hover
- [ ] Haptic feedback triggers correctly (if implemented)

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Components/ScaleButtonStyle.swift` (NEW)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/iOS26LiquidLibraryView.swift`

**Unit Tests Required:**
```swift
// ScaleButtonStyleTests.swift
- testScaleEffectOnPress()
- testScaleResetOnRelease()
- testAnimationSmoothnessMetrics()
```

---

### PHASE 3: Performance & Loading States (Week 2)

#### Issue #436: Skeleton Screens

**Components to Create:**

**1. ShimmerEffect.swift**
```swift
struct ShimmerEffect: View {
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.3), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerPhase)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
    }
}
```

**2. BookCardSkeleton.swift**
```swift
struct BookCardSkeleton: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        VStack(spacing: 8) {
            // Cover placeholder (220pt)
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .frame(height: 220)
                .overlay { ShimmerEffect() }
            
            // Title placeholder (12pt)
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(height: 12)
                .overlay { ShimmerEffect() }
            
            // Author placeholder (10pt)
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(width: 80, height: 10)
                .overlay { ShimmerEffect() }
        }
    }
}
```

**Integration into iOS26LiquidLibraryView:**

```swift
@State private var isLoading = true

var body: some View {
    if cachedFilteredWorks.isEmpty && isLoading {
        // Show skeleton grid
        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                BookCardSkeleton()
            }
        }
        .accessibilityLabel("Loading library")
    } else {
        // Show real books
        optimizedFloatingGridLayout
    }
}

.onAppear {
    isLoading = true
}
.onChange(of: cachedFilteredWorks) {
    if !cachedFilteredWorks.isEmpty {
        isLoading = false
    }
}
```

**Testing Checklist:**
- [ ] Test on slow network (Network Link Conditioner)
- [ ] First launch experience (fresh install)
- [ ] Dark mode appearance (shimmer visible)
- [ ] VoiceOver announces "Loading" state
- [ ] Smooth transition to real books (no flash)
- [ ] 10s timeout (prevent infinite loading state)

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Components/BookCardSkeleton.swift` (NEW)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Components/ShimmerEffect.swift` (NEW)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/iOS26LiquidLibraryView.swift`

**Unit Tests Required:**
```swift
// BookCardSkeletonTests.swift
- testShimmerAnimationLoops()
- testAccessibilityLabel()
- testDarkModeContrast()
```

---

#### Issue #437: Image Prefetching

**Implementation:**

**1. Add Prefetch Logic to SearchView.swift:672**

```swift
ForEach(Array(items.enumerated()), id: \.element.id) { index, result in
    Button {
        selectedBook = result
    } label: {
        iOS26LiquidListRow(work: result.work, displayStyle: .standard)
    }
    .onAppear {
        // Prefetch next 10 covers (or 3 in low power mode)
        prefetchCovers(from: index, in: items)
    }
}
```

**2. Implement prefetchCovers() Function**

```swift
@State private var activePrefetchTasks: [Int: Task<Void, Never>] = [:]

private func prefetchCovers(from index: Int, in items: [SearchResult]) {
    // Respect low power mode
    let prefetchCount = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 10
    let prefetchRange = (index + 1)...(min(index + prefetchCount, items.count - 1))
    
    for i in prefetchRange {
        // Skip if already prefetching
        guard activePrefetchTasks[i] == nil else { continue }
        
        let work = items[i].work
        guard let url = CoverImageService.coverURL(for: work) else { continue }
        
        let task = Task.detached(priority: .utility) {
            // Prefetch using URLSession
            let request = URLRequest(url: url)
            _ = try? await URLSession.shared.data(for: request)
        }
        
        activePrefetchTasks[i] = task
    }
}

// Memory pressure monitoring
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
    // Cancel all prefetch tasks
    activePrefetchTasks.values.forEach { $0.cancel() }
    activePrefetchTasks.removeAll()
}

.onDisappear {
    // Clean up
    activePrefetchTasks.values.forEach { $0.cancel() }
    activePrefetchTasks.removeAll()
}
```

**3. Memory Management**
- Start with conservative limit (5 images instead of 10)
- Monitor memory pressure via `NotificationCenter`
- Cancel all prefetch tasks on memory warning
- Add user preference to disable prefetching (Settings)

**Testing Checklist:**
- [ ] Test with slow 3G network (Network Link Conditioner)
- [ ] Monitor memory usage (Instruments - Allocations)
- [ ] Verify no excessive network requests (Charles Proxy)
- [ ] Test with 100+ search results
- [ ] Low power mode reduces prefetch aggressiveness (3 vs 10)
- [ ] Fast scroll cancels prefetch tasks
- [ ] Memory warning cancels all tasks

**Files Modified:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/SearchView.swift`

---

## Risk Mitigation

### HIGH-RISK ITEMS

#### 1. Issue #437 - Memory Pressure (CRITICAL)

**Risk:** Aggressive prefetching could cause memory warnings or crashes on older devices (iPhone 12, iPad Air 3)

**Mitigation Strategy:**
- Start with conservative limit (5 images instead of 10)
- Implement memory pressure monitoring via `NotificationCenter.default.addObserver` for `UIApplication.didReceiveMemoryWarningNotification`
- Cancel all prefetch tasks on memory warning
- Add user preference to disable prefetching
- Profile with Instruments on iPhone 12 Mini (lowest RAM device still supported)

**Contingency Plan:**
If memory issues persist, implement adaptive prefetching based on available memory:
```swift
let availableMemory = ProcessInfo.processInfo.physicalMemory
let prefetchCount = availableMemory > 4_000_000_000 ? 10 : 3  // 4GB threshold
```

---

#### 2. Issue #426 - Sprint 3 Deadline (CRITICAL)

**Risk:** Missing Dec 25 deadline affects Sprint 3 commitments

**Mitigation Strategy:**
- Prioritize above all other issues
- Allocate first 2 days of Week 1 exclusively to #426
- Daily standup checks on progress
- Backend verification completed by Dec 12

**Contingency Plan:**
If backend `Retry-After` header missing, implement client-side exponential backoff:
```swift
let retryAfter = backendRetryAfter ?? calculateExponentialBackoff(attemptCount)
```

---

#### 3. Issue #428 - Backend Dependency

**Risk:** Backend team slow to respond or deprioritizes custom header addition

**Mitigation Strategy:**
- Open cross-repo issue early (Dec 11)
- Tag backend tech lead for visibility
- Implement iOS side with mock testing first
- Use heuristic CORS detection as fallback

**Contingency Plan:**
Ship without backend header, rely on heuristic detection only:
```swift
// Fallback CORS detection
if response.statusCode == 0 && request.url?.absoluteString.contains("null") == true {
    return .corsBlocked
}
```

---

### MEDIUM-RISK ITEMS

#### 4. Issue #436 - Accessibility Risk

**Risk:** Skeleton screens confuse VoiceOver users or create infinite loading state perception

**Mitigation Strategy:**
- Add clear "Loading library" accessibility label
- Ensure skeleton dismisses quickly (<2s on average connection)
- Test with VoiceOver from day 1
- Add timeout (10s max skeleton display)

**Contingency Plan:**
Simplify to basic loading spinner if accessibility issues:
```swift
ProgressView("Loading library...")
    .controlSize(.large)
```

---

#### 5. Issue #434 - Animation Performance

**Risk:** Scale animation drops frames on older devices

**Mitigation Strategy:**
- Profile with Instruments on iPhone 12
- Use `.animation(.spring())` instead of `.withAnimation {}`
- Test with 100+ books in library (stress test)
- Reduce animation if frame drops detected

**Contingency Plan:**
Disable animation on devices with low power mode enabled:
```swift
.scaleEffect(
    configuration.isPressed && !ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.95 : 1.0
)
```

---

## Testing Strategy

### Unit Testing Requirements

**New Components:**
```swift
// RateLimitBannerTests.swift
- testCountdownTimerDecrementsEverySecond()
- testBannerDismissesAtZero()
- testRetryAfterHeaderParsing()
- testRetryAfterBodyParsing()
- testDefaultsTo60Seconds()
- testAccessibilityAnnouncement()

// ScaleButtonStyleTests.swift
- testScaleEffectOnPress()
- testScaleResetOnRelease()
- testAnimationSmoothnessMetrics()

// BookCardSkeletonTests.swift
- testShimmerAnimationLoops()
- testAccessibilityLabel()
- testDarkModeContrast()
```

### Integration Testing

**#426 Rate Limit Flow:**
1. Simulate 429 response from mock server
2. Verify banner appears with correct countdown
3. Confirm buttons disabled
4. Wait for countdown completion
5. Verify banner dismisses
6. Confirm buttons re-enabled

**#437 Prefetch Flow:**
1. Load search results with 50+ books
2. Scroll to position 10
3. Monitor network requests (should see requests for items 11-20)
4. Trigger memory warning
5. Verify prefetch tasks canceled

### Performance Testing

**Metrics to Track:**
- **Scroll FPS:** Must maintain 60fps during search results scroll
- **Memory Usage:** Max increase of 50MB during prefetching
- **Network Requests:** No more than N+10 requests for N visible items
- **Animation Smoothness:** Scale animation must complete in <300ms
- **Skeleton Load Time:** Average <1s to real content

**Tools:**
- Xcode Instruments (Time Profiler, Allocations)
- Network Link Conditioner (simulate 3G, packet loss)
- Console.app (monitor memory warnings)
- Charles Proxy (verify network request patterns)

**Test Devices:**
- iPhone 15 Pro (latest, high-end)
- iPhone 12 Mini (3 years old, low RAM - CRITICAL)
- iPad Pro 11" (multitasking scenarios)
- iPad Air 3 (older, lower performance)

---

## Execution Timeline

### WEEK 1 (Dec 11-15)

#### Monday, Dec 11 (Sprint 3 Day 1)

**Morning (9am-12pm): #426 Setup & Research**
- [ ] Verify `ApiErrorCode` enum location
- [ ] Check backend code for `Retry-After` implementation
- [ ] Create `RateLimitBanner.swift` skeleton
- [ ] Write unit test stubs (TDD approach)

**Afternoon (1pm-5pm): #426 Implementation**
- [ ] Implement countdown timer logic
- [ ] Add error parsing in API clients
- [ ] Create banner UI component
- [ ] Test with mock 429 response

---

#### Tuesday, Dec 12 (Sprint 3 Day 2)

**Morning (9am-12pm): #426 Integration**
- [ ] Integrate into BookshelfScannerView
- [ ] Integrate into EnrichmentQueueView
- [ ] Integrate into CSVImportView
- [ ] VoiceOver testing

**Afternoon (1pm-5pm): #426 Testing & Documentation**
- [ ] Complete all testing checklist items
- [ ] Create `docs/features/RATE_LIMIT_HANDLING.md`
- [ ] Submit PR for code review
- [ ] Start #428 backend coordination (open cross-repo issue)

---

#### Wednesday, Dec 13

**Morning (9am-11am): #435 Grid Stability (Quick Win)**
- [ ] Implement size class based grid columns
- [ ] Test on iPhone and iPad
- [ ] Test rotation and multitasking
- [ ] Submit PR

**Late Morning (11am-12pm): #434 Press Feedback (Quick Win)**
- [ ] Create `ScaleButtonStyle.swift`
- [ ] Apply to all book card types
- [ ] Test animation smoothness
- [ ] Submit PR

**Afternoon (1pm-5pm): #428 CORS Implementation**
- [ ] Add `CORS_BLOCKED` to `ApiErrorCode`
- [ ] Implement detection in API clients
- [ ] Create mock CORS error test
- [ ] Document for backend team

---

#### Thursday, Dec 14

**Morning (9am-12pm): Code Review Responses**
- [ ] Address PR feedback for #426
- [ ] Address PR feedback for #435, #434
- [ ] Merge approved PRs

**Afternoon (1pm-5pm): #436 Skeleton Screens Start**
- [ ] Create `ShimmerEffect.swift` component
- [ ] Create `BookCardSkeleton.swift` component
- [ ] Test shimmer animation in dark mode

---

#### Friday, Dec 15

**Full Day: #436 Skeleton Screens Completion**
- [ ] Integrate skeleton into iOS26LiquidLibraryView
- [ ] Add loading state management
- [ ] VoiceOver testing
- [ ] Performance validation
- [ ] Submit PR

---

### WEEK 2 (Dec 18-22)

#### Monday, Dec 18

**Full Day: #437 Image Prefetching**
- [ ] Implement prefetch logic in SearchView
- [ ] Add memory pressure monitoring
- [ ] Test with 100+ search results
- [ ] Profile with Instruments (memory & network)
- [ ] Add user preference to disable
- [ ] Submit PR

---

#### Tuesday, Dec 19

**Morning (9am-12pm): #437 Optimization**
- [ ] Address memory issues (if any)
- [ ] Tune prefetch count based on testing
- [ ] Low power mode optimization

**Afternoon (1pm-5pm): #428 Finalization**
- [ ] Wait for backend team confirmation
- [ ] Test with real backend (if ready)
- [ ] Fallback to heuristic if backend not ready
- [ ] Submit PR

---

#### Wednesday, Dec 20

**Full Day: Integration Testing**
- [ ] Test all changes together on clean build
- [ ] Regression testing (app launch, scroll, etc.)
- [ ] Real device testing (iPhone 12, iPad Air)
- [ ] Accessibility audit

---

#### Thursday, Dec 21

**Morning (9am-12pm): Documentation Sprint**
- [ ] Complete all feature documentation
- [ ] Update CHANGELOG.md with victory stories
- [ ] Create Mermaid diagrams for workflows
- [ ] Update CLAUDE.md if needed

**Afternoon (1pm-5pm): Final PR Reviews**
- [ ] Address any outstanding feedback
- [ ] Ensure all tests passing
- [ ] Verify zero warnings build

---

#### Friday, Dec 22

**Morning (9am-12pm): Merge & Deploy**
- [ ] Merge all approved PRs to main
- [ ] Create release candidate build
- [ ] Final smoke testing

**Afternoon (1pm-5pm): Sprint Retrospective**
- [ ] Document lessons learned
- [ ] Update performance baselines
- [ ] Close all GitHub issues
- [ ] Celebrate!

---

## Contingency Plan

### Priority Tiers (If Behind Schedule)

1. **MUST SHIP (Sprint 3):** #426 (rate limit timer)
2. **SHOULD SHIP (High ROI):** #435, #434 (quick wins)
3. **NICE TO HAVE:** #436, #437 (performance enhancements)
4. **FUTURE SPRINT:** #428 (CORS, backend dependent)

### Drop Sequence (If Needed)

```
First drop  → #428 (move to Sprint 4)
              - Low impact (only affects future web builds)
              - Backend dependency makes it low priority

Second drop → #437 (defer prefetching)
              - Performance enhancement, not critical
              - Can ship in Sprint 4 after more testing

Third drop  → #436 (use simple spinner instead)
              - Perceived performance vs actual functionality
              - Can simplify to ProgressView

NEVER DROP  → #426, #435, #434
              - Sprint 3 commitment (#426)
              - Quick wins with high visibility (#435, #434)
```

---

## Documentation Requirements

### Feature Documentation

**Create New Files:**

1. **`docs/features/RATE_LIMIT_HANDLING.md`** (#426)
   - Architecture diagram (Mermaid)
   - Error flow from backend → banner display
   - Testing guide for 429 errors
   - Example responses with `Retry-After` header

2. **`docs/features/IMAGE_PREFETCHING.md`** (#437)
   - Prefetch algorithm explanation
   - Memory management strategy
   - Performance benchmarks (before/after)
   - Low power mode behavior

**Update Existing Files:**

1. **`docs/features/ERROR_HANDLING.md`**
   - Add CORS error handling section (#428)
   - Document heuristic detection fallback
   - Cross-repo coordination notes

2. **`docs/architecture/UI_COMPONENTS.md`**
   - Add skeleton screens documentation
   - Add ScaleButtonStyle pattern
   - iOS 26 HIG compliance notes

3. **`CHANGELOG.md`**
   - Victory stories for all 6 issues
   - Performance improvements quantified
   - User-facing changes highlighted

**Code Comments:**
- Inline documentation for all new public APIs
- Explain non-obvious decisions (e.g., why 10 prefetch limit, why 60s default timeout)
- Add Swift DocC comments for reusable components

---

## Integration & Deployment Strategy

### Branch Strategy

**Feature Branches:**
```bash
feature/426-rate-limit-timer
feature/435-grid-stability
feature/434-press-feedback
feature/436-skeleton-screens
feature/437-image-prefetching
feature/428-cors-handling
```

**PR Naming Convention:**
```
feat: implement rate limit countdown timer (#426)
feat: tighten adaptive grid range for layout stability (#435)
feat: add visual press feedback to book cards (#434)
feat: add skeleton screens for initial library load (#436)
feat: implement cover image prefetching in search (#437)
feat: implement CORS error handling (#428)
```

**Merge Strategy:**
- Create PR after testing checklist completed
- Require code review approval
- Merge to `main` after zero warnings build
- Delete feature branch after merge

---

### PR Review Checklist Template

```markdown
## Issue #[number]: [Title]

### Implementation
- [ ] All implementation steps completed
- [ ] Zero warnings build
- [ ] Code follows Swift 6.2 concurrency rules
- [ ] Public APIs documented with Swift DocC
- [ ] Nested types pattern followed
- [ ] @Bindable used for SwiftData models (if applicable)

### Testing
- [ ] All test checklist items passed
- [ ] Unit tests added (if applicable)
- [ ] Performance validated with Instruments
- [ ] Real device testing completed (iPhone + iPad)
- [ ] Network simulation tested (if applicable)

### Accessibility
- [ ] VoiceOver tested
- [ ] Dynamic Type tested
- [ ] WCAG AA contrast verified (4.5:1+)
- [ ] Keyboard navigation works (iPad)

### Documentation
- [ ] Feature documentation updated
- [ ] CHANGELOG.md entry added
- [ ] Code comments added for non-obvious logic
- [ ] Mermaid diagrams created (if workflow changes)

### iOS 26 HIG Compliance
- [ ] Navigation patterns follow HIG
- [ ] No manual @FocusState with .searchable()
- [ ] Liquid Glass design maintained
- [ ] System semantic colors used
```

---

### Deployment Order

**Week 1 End (Dec 15):**
- ✅ #426 - Rate limit timer (Sprint 3 priority)
- ✅ #435 - Grid stability (quick win)
- ✅ #434 - Press feedback (quick win)

**Week 2 Mid (Dec 19):**
- ✅ #436 - Skeleton screens (performance)
- ✅ #437 - Image prefetching (performance)

**Week 2 End (Dec 22):**
- ✅ #428 - CORS handling (backend coordination)

---

### Rollback Plan

**Feature Flags (If High Risk):**
```swift
// UserDefaults-based feature flags
@AppStorage("enableImagePrefetching") private var enablePrefetching = true
@AppStorage("enableSkeletonScreens") private var enableSkeleton = true
```

**Conditional Disabling:**
- Image prefetching: User preference in Settings
- Skeleton screens: Can be conditionally disabled via feature flag
- Press feedback: Safe to ship (no rollback needed)
- Rate limit handling: Additive only (safe to ship)

**Emergency Rollback:**
```bash
# Revert specific PR if critical issue found
git revert <commit-hash>
git push origin main

# Create hotfix branch
git checkout -b hotfix/revert-437-prefetching
```

---

## Post-Implementation Actions

### After All PRs Merged

**1. Performance Validation**
- Compare before/after Instruments traces
- Verify no regression in app launch time (<600ms maintained)
- Confirm 60fps scroll maintained
- Memory usage within acceptable limits (<50MB increase)

**2. User Feedback Collection**
- Monitor App Store reviews for next 2 weeks
- Check crash analytics (Xcode Organizer)
- Gather team feedback on perceived improvements
- Track user engagement metrics (if analytics available)

**3. Documentation Handoff**
- Ensure all feature docs complete and reviewed
- Update architectural decision records (ADRs)
- Create video demo of new features (optional)
- Share with QA team for regression testing

**4. Backend Coordination Follow-up**
- Confirm #428 CORS header added (cross-repo issue)
- Verify rate limit behavior in production environment
- Close cross-repo issue when backend confirms deployment
- Update backend coordination docs

---

## Success Criteria

### Technical Metrics

- [ ] All issues build with zero warnings
- [ ] Test suite 100% passing
- [ ] Code coverage >80% for new code
- [ ] 60fps scroll maintained (validated with Instruments)
- [ ] No memory regressions (<50MB increase max)
- [ ] App launch <600ms (no regression from baseline)
- [ ] Zero new accessibility violations

### User Experience Metrics

- [ ] Perceived performance: 30% faster (skeleton screens + prefetching)
- [ ] Layout stability: Zero jarring transitions during rotation
- [ ] Interaction confidence: 100% visual feedback on all cards
- [ ] Error clarity: Users understand rate limits and network errors
- [ ] First-launch experience improved (skeleton screens)

### Completion Signals

**Week 1 Milestone (Dec 15):**
- [ ] #426 merged and tested in production
- [ ] #435, #434 merged (quick wins shipped)
- [ ] Backend cross-repo issue created for #428

**Week 2 Milestone (Dec 20):**
- [ ] All 6 issues merged to main
- [ ] Integration testing complete
- [ ] Documentation updated

**Sprint 3 Complete (Dec 22):**
- [ ] Zero open issues (except #201)
- [ ] #426 shipped in production
- [ ] Sprint retrospective completed
- [ ] Performance baselines updated

---

## Next Immediate Actions

### Pre-Implementation Verification (Day 1 Morning)

**1. Verify Existing Infrastructure**
```bash
# Search for ApiErrorCode enum
ast-grep --lang swift --pattern 'enum ApiErrorCode' BooksTrackerPackage/

# Check if rate limit handling exists
grep -r "RATE_LIMIT" BooksTrackerPackage/Sources/

# Verify backend Retry-After implementation
# (Open backend repo and check middleware/error-handling.js)
```

**2. Set Up Testing Environment**
- [ ] Install Network Link Conditioner (Xcode Additional Tools)
- [ ] Configure Charles Proxy for mock 429 responses
- [ ] Create test server config for CORS simulation
- [ ] Set up Instruments baseline captures

**3. Create Feature Branches**
```bash
git checkout -b feature/426-rate-limit-timer
git checkout main
git checkout -b feature/435-grid-stability
git checkout main
git checkout -b feature/434-press-feedback
git checkout main
git checkout -b feature/436-skeleton-screens
git checkout main
git checkout -b feature/437-image-prefetching
git checkout main
git checkout -b feature/428-cors-handling
git checkout main
```

**4. Document Baseline Metrics**
```bash
# Run Instruments Time Profiler on SearchView scroll
# Capture memory usage during library load
# Record current app launch time (should be ~600ms)
# Save baseline screenshots for comparison
```

---

### First Implementation Steps (Start with #426)

**Step 1: Verify ApiErrorCode enum** (5 minutes)
```bash
ast-grep --lang swift --pattern 'enum ApiErrorCode' BooksTrackerPackage/
```

**Step 2: Create feature branch** (1 minute)
```bash
git checkout -b feature/426-rate-limit-timer
```

**Step 3: Write failing test** (30 minutes)
```swift
@Test func testRateLimitBannerCountdown() async {
    let banner = RateLimitBanner(retryAfter: 60)
    #expect(banner.remainingSeconds == 60)
    
    try await Task.sleep(for: .seconds(1))
    #expect(banner.remainingSeconds == 59)
}
```

**Step 4: Implement countdown logic** (1 hour)
```swift
@Observable
class RateLimitBanner {
    var remainingSeconds: Int
    
    init(retryAfter: Int) {
        self.remainingSeconds = retryAfter
        startCountdown()
    }
    
    private func startCountdown() {
        Task {
            while remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                remainingSeconds -= 1
            }
        }
    }
}
```

**Step 5: Integrate into first view** (30 minutes)
```swift
// BookshelfScannerView.swift
@State private var showRateLimitBanner = false
@State private var retryAfter = 0

if showRateLimitBanner {
    RateLimitBanner(retryAfter: retryAfter)
}
```

---

## Communication Plan

### Daily Updates
- Post standup updates on #426 progress
- Tag backend team in #428 cross-repo issue
- Share PR links in team channel for visibility
- Update GitHub project board after each merge

### Weekly Milestones
- **Week 1 Friday:** Demo #426, #435, #434 to team
- **Week 2 Wednesday:** Integration testing results
- **Week 2 Friday:** Sprint retrospective meeting

### Stakeholder Communication
- Sprint 3 progress report (daily)
- Backend team coordination (#428)
- QA team handoff (week 2)

---

## Appendix

### Related Documentation

**Product Requirements:**
- Sprint 3 roadmap (GitHub Projects)
- iOS 26 HIG compliance guide (CLAUDE.md)

**Technical References:**
- `docs/CONCURRENCY_GUIDE.md` - Swift 6.2 patterns
- `docs/features/ERROR_HANDLING.md` - Existing error patterns
- `docs/architecture/UI_COMPONENTS.md` - Component library

**Backend Coordination:**
- Backend repository: `https://github.com/jukasdrj/bookstrack-backend`
- Backend handoff doc: `FRONTEND_HANDOFF.md:19-40` (CORS)
- Backend handoff doc: `FRONTEND_HANDOFF.md:196-206` (Rate limits)

### GitHub Issues

**Implementing:**
- [#426](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887421) - Rate limit countdown timer
- [#428](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887419) - CORS error handling
- [#434](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887413) - Visual press feedback
- [#435](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887412) - Tighten grid range
- [#436](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887411) - Skeleton screens
- [#437](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887410) - Image prefetching

**Excluded:**
- [#201](https://github.com/users/jukasdrj/projects/2/views/1?pane=issue&itemId=95887233) - Remove ISBNdb (backend-only)

---

## Plan Status

**Status:** ✅ Ready for Implementation  
**Next Action:** Verify `ApiErrorCode` enum location  
**Owner:** Development Team  
**Sprint:** Sprint 3 (Dec 11-25, 2025)  
**Review Date:** Dec 22, 2025

---

**Generated by:** Claude Code + Gemini 2.5 Pro Planner  
**Planning Session ID:** `6c4844d4-be1d-4e2b-8d4f-4c0f7ebbeb2a`  
**Last Updated:** November 14, 2025
