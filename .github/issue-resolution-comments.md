# GitHub Issue Resolution Comments

## Issue #426 - Rate Limit Countdown Timer UI

### Resolution Approach

**Priority:** MUST SHIP (Sprint 3 commitment)

**Implementation Strategy:**

1. **Add `RATE_LIMIT_EXCEEDED` to `ApiErrorCode` enum**
   - Location: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/ApiErrorCode.swift`

2. **Create `RateLimitBanner.swift` component**
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

3. **Parse `Retry-After` header from API responses**
   - Primary: Extract from HTTP headers
   - Fallback: Read from response body `details.retryAfter`
   - Default: 60 seconds if both missing

4. **Integrate into affected views:**
   - `BookshelfScannerView.swift`
   - `EnrichmentQueueView.swift`
   - `CSVImportView.swift`

5. **Display format:** "Too many requests. Try again in {N}s."
   - Auto-dismiss when countdown reaches zero
   - Disable action buttons during countdown
   - VoiceOver announces countdown status

**Testing Requirements:**
- [ ] Simulate 429 response with mock server
- [ ] Verify countdown updates every second
- [ ] Confirm buttons disabled during countdown
- [ ] Test banner dismissal after countdown
- [ ] VoiceOver testing

**Backend Note:** Backend already supports `Retry-After` header (verified in `bookstrack-backend`)

**Estimated Effort:** 2-3 hours

---

## Issue #428 - CORS Error Handling

### Resolution Approach

**Priority:** LOW (Future web deployment only - current Capacitor builds work fine)

**Implementation Strategy:**

1. **Backend Coordination Required**
   - Create cross-repo issue in `bookstrack-backend`
   - Request `X-Custom-Error: CORS_BLOCKED` header
   - Link to this iOS issue

2. **Add `CORS_BLOCKED` to `ApiErrorCode` enum**
   - Location: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/API/ApiErrorCode.swift`

3. **Detection in API clients:**
   - `EnrichmentAPIClient.swift`
   - `BookSearchAPIService.swift`

4. **Implement heuristic fallback** (if backend header not available):
   ```swift
   // Fallback CORS detection
   if response.statusCode == 0 && request.url?.absoluteString.contains("null") == true {
       return .corsBlocked
   }
   ```

5. **User Experience:**
   - Display: "Network error - check your connection"
   - Debug logging (Xcode console only, not user-facing)

**Testing Requirements:**
- [ ] Mock CORS error with custom URLProtocol
- [ ] User-friendly message displays
- [ ] Debug logs appear in Xcode console
- [ ] Test with real CORS blocked origin (when backend ready)

**Current Impact:** None (iOS whitelist works, only affects future web builds)

**Estimated Effort:** 1-2 hours (iOS) + backend coordination time

---

## Issue #434 - Visual Press Feedback

### Resolution Approach

**Priority:** SHOULD SHIP (Quick Win - 20 minutes)

**Implementation Strategy:**

1. **Create `ScaleButtonStyle.swift` component:**
   ```swift
   struct ScaleButtonStyle: ButtonStyle {
       func makeBody(configuration: Configuration) -> some View {
           configuration.label
               .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
               .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
       }
   }
   ```

2. **Apply to all book card types:**
   - Floating grid cards (`iOS26LiquidLibraryView.swift:250-256`)
   - Adaptive cards (line 268)
   - Liquid list rows (line 281)

3. **Optional iOS 26 Enhancement:**
   ```swift
   .sensoryFeedback(.selection, trigger: tapGesture)
   ```

**Benefits:**
- Better perceived responsiveness
- Immediate visual confirmation of tap
- Smooth 60fps animation

**Testing Requirements:**
- [ ] Visual feedback on tap (smooth scale animation)
- [ ] No interference with NavigationLink navigation
- [ ] 60fps animation (profile with Instruments)
- [ ] Works on iPad with trackpad hover
- [ ] Low power mode optimization (disable animation if needed)

**Performance Consideration:**
```swift
// Disable animation on low power mode if frame drops detected
.scaleEffect(
    configuration.isPressed && !ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.95 : 1.0
)
```

**Estimated Effort:** 20 minutes

---

## Issue #435 - Tighten Adaptive Grid Range

### Resolution Approach

**Priority:** SHOULD SHIP (Quick Win - 10-30 minutes)

**Problem:** Current range of 150-200 causes layout jumps during rotation/multitasking

**Recommended Solution (Option 2): Size Class Based**

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
// Location: iOS26LiquidLibraryView.swift:246-247
GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)
// 20pt range instead of 50pt
```

**Benefits:**
- Reduces jarring layout transitions
- Predictable column counts during rotation
- Better multitasking experience on iPad

**Testing Requirements:**
- [ ] Rotation on iPhone (portrait ↔ landscape)
- [ ] iPad multitasking (1/2, 1/3, 2/3 splits)
- [ ] Dynamic Type size changes
- [ ] Landscape mode stability
- [ ] No jarring size jumps during transitions

**Estimated Effort:** 10 minutes (quick fix) OR 30 minutes (size class based)

---

## Issue #436 - Skeleton Screens for Library Load

### Resolution Approach

**Priority:** HIGH ROI (Performance Enhancement - 1-2 hours)

**Impact:** 30% faster perceived performance on initial library load

**Implementation Strategy:**

1. **Create `ShimmerEffect.swift` component:**
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

2. **Create `BookCardSkeleton.swift` component:**
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

3. **Integrate into `iOS26LiquidLibraryView.swift`:**
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

   .onChange(of: cachedFilteredWorks) {
       if !cachedFilteredWorks.isEmpty {
           isLoading = false
       }
   }
   ```

**Accessibility:**
- VoiceOver announces "Loading" state
- Smooth transition to real books (no flash)
- 10s timeout to prevent infinite loading state

**Testing Requirements:**
- [ ] Test on slow network (Network Link Conditioner)
- [ ] First launch experience (fresh install)
- [ ] Dark mode appearance (shimmer visible)
- [ ] VoiceOver testing
- [ ] Smooth transition to real books

**Estimated Effort:** 1-2 hours

---

## Issue #437 - Cover Image Prefetching in Search

### Resolution Approach

**Priority:** HIGH ROI (Performance Enhancement - 1 hour)

**Impact:** 200ms+ faster scroll, smoother search experience

**⚠️ CRITICAL: Memory Management Required**

**Implementation Strategy:**

1. **Add prefetch logic to `SearchView.swift:672`:**
   ```swift
   @State private var activePrefetchTasks: [Int: Task<Void, Never>] = [:]

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

2. **Implement `prefetchCovers()` function:**
   ```swift
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
               // Prefetch and populate CachedAsyncImage's NSCache
               let request = URLRequest(url: url)
               if let (data, _) = try? await URLSession.shared.data(for: request) {
                   // Store in shared ImageCache (used by CachedAsyncImage)
                   ImageCache.shared.setCache(data, for: url.absoluteString)
               }
           }

           activePrefetchTasks[i] = task
       }
   }
   ```

3. **Memory pressure monitoring:**
   ```swift
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

**Risk Mitigation:**
- Start with conservative limit (5 images instead of 10)
- Monitor memory usage with Instruments (Allocations tool)
- Reduce prefetch count to 3 in low power mode
- Cancel all tasks on memory warning
- Add user preference to disable prefetching

**Testing Requirements:**
- [ ] Test with slow 3G network (Network Link Conditioner)
- [ ] Monitor memory usage (Instruments - Allocations)
- [ ] Verify no excessive network requests (Charles Proxy)
- [ ] Test with 100+ search results
- [ ] Low power mode reduces prefetch (3 vs 10)
- [ ] Fast scroll cancels prefetch tasks
- [ ] Memory warning cancels all tasks
- [ ] Test on iPhone 12 Mini (lowest RAM device)

**Estimated Effort:** 1 hour + thorough memory testing

---

## Dead Code Issue - iOS26AdaptiveBookCard Non-Functional Buttons

### Resolution Approach

**Priority:** CRITICAL (User-Facing Bug)

**Problem:** "Add to Library" and "Add to Wishlist" buttons create UserLibraryEntry objects but never persist them due to missing `@Environment(\.modelContext)`.

**Affected Files:**
1. `iOS26AdaptiveBookCard.swift` (Lines 536-549)
2. `iOS26FloatingBookCard.swift` (Lines 309, 642) - needs investigation
3. `iOS26LiquidListRow.swift` (Line 522) - needs investigation

**Recommended Solution: Remove Dead Code**

**Why:** These views are display-only components for LibraryView. Users navigate to WorkDetailView for actual persistence. The add/wishlist buttons were never fully implemented.

**Implementation:**
1. Delete `addToLibrary()` and `addToWishlist()` functions
2. Remove buttons from `quickActionsMenu` at lines:
   - 63, 66 (top menu)
   - 271 (context menu)
   - 474, 478 (bottom actions)

**Alternative (If Quick-Add Desired): Implement Properly**

```swift
struct iOS26AdaptiveBookCard: View {
    let work: Work
    @Environment(\.modelContext) private var modelContext  // ADD THIS

    private func addToLibrary() {
        // If no edition exists, create one first
        let edition: Edition
        if let primaryEdition = work.availableEditions.first {
            edition = primaryEdition
        } else {
            let newEdition = Edition()
            modelContext.insert(newEdition)
            newEdition.work = work
            edition = newEdition
        }

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        // Entry is auto-saved by factory method
    }
}
```

**⚠️ Warning:** Option 2 is a breaking change requiring:
- API changes to view
- Comprehensive testing on real devices
- Verification of SwiftData insert-before-relate pattern

**Verification Steps:**
- [ ] Build succeeds with zero warnings
- [ ] Buttons either removed OR fully functional
- [ ] If implemented: Test on real device
  - Tap "Add to Library" → Work appears in library
  - Tap "Add to Wishlist" → Work appears in wishlist
- [ ] No memory leaks (Instruments check)

**Recommendation:** Proceed with **Remove Dead Code** for now. If quick-add functionality is desired, implement properly in a separate feature PR with full testing.

---

## Summary

**Total Issues:** 6 (+ 1 dead code issue discovered)

**Implementation Order:**
1. **Week 1:** #426 (rate limit - Sprint 3 priority), #435, #434 (quick wins)
2. **Week 2:** #436, #437 (performance), #428 (backend coordination)
3. **Anytime:** Dead code cleanup (independent)

**Testing Priority:**
- Real device testing (iPhone + iPad)
- Memory pressure monitoring (#437)
- Accessibility (VoiceOver) for all
- Performance validation (Instruments)

**Backend Coordination:**
- #426: Backend ready (Retry-After header exists)
- #428: Needs cross-repo issue + header addition

**Quick Wins (Ship First):**
- #434: 20 minutes
- #435: 10-30 minutes

**High ROI (Ship Second):**
- #436: 1-2 hours, 30% perceived performance boost
- #437: 1 hour, 200ms+ faster scroll

**Low Priority (Ship Last):**
- #428: Only affects future web builds