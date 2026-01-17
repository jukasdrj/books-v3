# Task Plan: Frontend Recommendations Integration (iOS)

## Goal
Implement personalized book recommendations in BooksTrack iOS app using bendv3's recommendation API, including prerequisite features (ratings, preferences) and a complete 5-step onboarding flow for new users. **Elevate UI/UX to world-class iOS 26 standards** - function is top priority, but beautiful, delightful user experience is a close second.

## Current Phase
Phase 3 - Core Recommendations UI (In Progress - Components Built ✅)

## Phases

### Phase 1: Prerequisites Investigation & Setup ✅ COMPLETE
**Goal**: Verify existing features and build missing rating/preferences infrastructure

- [x] Read Work.swift model - check for rating field
- [x] Read User.swift model - check for preferences field
- [x] Read APIClient.swift - understand auth pattern (x-user-id mapping)
- [x] Search for existing rating UI components
- [x] Search for existing preferences UI
- [x] Document findings: what exists, what needs building
- [x] **Decision**: Build rating system first OR preferences first (Decision: Rating first)
- [x] Create UserPreferences model (if missing) - Created with ReadingMood enum
- [x] Create BookRating model (if missing) - N/A: UserLibraryEntry.personalRating exists
- [x] Update User model with relationships - N/A: No separate User model
- [x] Build star rating UI component (if missing) - Already exists (StarRatingView.swift)
- [ ] Build preferences form UI (if missing) - DEFERRED to Phase 4 (Onboarding)
- [x] Validate with /quick-validate (zero warnings) - BUILD SUCCEEDED
- **Status:** complete
- **Actual Duration:** ~1 hour (investigation + model creation)
- **Blockers:** None
- **Key Findings:**
  - StarRatingView already exists with premium iOS 26 design
  - UserLibraryEntry.personalRating (Double) already integrated
  - Created UserPreferences model with 5 moods, constraints, API conversion
  - Preferences UI will be built in Phase 4 (Onboarding flow)

### Phase 2: API Client & Swift Types ✅ COMPLETE
**Goal**: Create type-safe Swift API client for recommendations endpoints

- [x] Create Swift type definitions (RecommendationResponse, ScoredRecommendation, etc.)
- [x] Map TypeScript types to Swift (see findings.md for mapping)
- [x] Create RecommendationsClient.swift (separate class, not extension)
  - [x] getRecommendations(userId:limit:excludedISBNs:) async function
  - [x] getRecommendationsDebug(userId:limit:excludedISBNs:) async function
  - [x] Error handling for "no preferences/ratings" case (RecommendationError.insufficientHistory)
- [x] Add x-user-id header mapping (method parameter pattern)
- [ ] Write unit tests for response decoding - DEFERRED (Phase 6)
- [ ] Write unit tests for exclusion logic - DEFERRED (Phase 6)
- [x] Validate with /quick-validate (zero warnings)
- **Status:** complete
- **Actual Duration:** ~15 minutes (with PAL expert consultation)
- **Blockers:** None
- **Key Achievements:**
  - Expert architectural guidance from Gemini 3 Pro via PAL MCP
  - Separate RecommendationsClient (different error schema than V3APIClientActual)
  - Stateless userId parameter pattern for better testability
  - Typed RecommendationError enum with `.insufficientHistory` for onboarding trigger
  - Swift 6 strict concurrency compliance (@MainActor + Sendable)

### Phase 3: Core Recommendations UI (iOS 26 World-Class Design) - IN PROGRESS
**Goal**: Build main recommendation viewing experience with premium iOS 26 aesthetics

- [x] Create BooksTrack/Features/Recommendations/ directory structure
- [x] Build RecommendationCard.swift component (~380 lines)
  - [x] AsyncImage for cover (multi-size support, subtle loading shimmer)
  - [x] Book info stack (title, author) with SF Pro typography
  - [x] **Premium score badge** (circular progress ring with color tiers)
  - [x] ScoreRing component (Gold/Green/Blue/Gray, spring animation)
  - [x] Reasons list (max 3) with SF Symbols checkmarks
  - [x] "Add to Library" button with gradient capsule
  - [x] **Card design**: Glass material, corner radius 20, subtle shadow
  - [x] **Micro-interactions**: Scale feedback (0.98x), haptic feedback
- [ ] Build RecommendationsListView.swift (NEXT)
  - [ ] Strategy badge (preference_based vs cold_start) with gradient pill
  - [ ] LazyVStack with RecommendationCard rows (spacing: 12)
  - [ ] **Premium loading state**: Animated skeleton cards
  - [ ] **Delightful empty state**: Custom illustration, CTA button
  - [ ] **Helpful error state**: Friendly messaging, retry with haptics
  - [ ] Pull-to-refresh with spring animation
  - [ ] **iOS 26 materials**: Frosted glass navigation bar
- [x] Build RecommendationsViewModel.swift (~160 lines)
  - [x] @MainActor + @Observable for SwiftUI reactivity
  - [x] ViewState enum (initial/loading/loaded/error/needsOnboarding)
  - [x] fetchRecommendations() async with smooth state transitions
  - [x] markAsAddedToLibrary(isbn:) with optimistic updates
  - [x] refresh() and retry() for error recovery
  - [x] **Smart error routing**: insufficientHistory → needsOnboarding
- [ ] Add navigation from main tab bar (DEFERRED to Phase 5)
- [ ] Test with /sim-safe (UI validation) - PENDING
- [x] Validate with /quick-validate (zero warnings) - BUILD SUCCEEDED ✅
- **Status:** in_progress
- **Actual Duration So Far:** ~15 minutes (core components)
- **Remaining:** RecommendationsListView + states
- **Blockers:** None
- **Achievements:**
  - Custom Equatable for RecommendationError (ViewState compatibility)
  - Reusable ScoreRing with color-coded tiers
  - Optimistic updates for instant UI feedback

### Phase 4: Onboarding Flow (5 Steps - Delightful First Experience)
**Goal**: Build first-time user onboarding wizard with world-class iOS 26 design

- [ ] Create OnboardingView.swift container (TabView with page style)
  - [ ] Page indicator with animated transitions
  - [ ] Smooth page swipe animations with spring curves
  - [ ] Progress bar (0% → 100%) at top of screen
- [ ] **Step 1**: WelcomeScreen.swift
  - [ ] Hero illustration (custom SF Symbol composition or Lottie animation)
  - [ ] Welcoming headline with SF Pro Display typography
  - [ ] Subheadline explaining personalization
  - [ ] "Get Started" button (prominent, iOS 26 button style with vibrancy)
  - [ ] Skip option (subtle, bottom-right)
  - [ ] **Entrance animation**: Fade in with scale (0.9 → 1.0)
- [ ] **Step 2**: GenreSelectionView.swift
  - [ ] FlowLayout with genre chips (10-15 popular genres)
  - [ ] **Premium chip design**: Pill shape, SF Symbols icons, toggle animation
  - [ ] Multi-select with spring feedback
  - [ ] "Selected: 3 genres" counter with number animation
  - [ ] Continue button (disabled → enabled state transition with color change)
  - [ ] **Interactive feedback**: Haptics on selection, chips scale on tap
- [ ] **Step 3**: MoodPickerView.swift
  - [ ] 5 mood options (light, dark, epic, cozy, thrilling)
  - [ ] **Card-based selection** (not radio buttons) with custom illustrations
  - [ ] Description for each mood with emoji icons
  - [ ] Selected card highlights with glow effect (iOS 26 vibrancy)
  - [ ] Skip button (optional step)
  - [ ] **Animation**: Cards slide in with stagger effect
- [ ] **Step 4**: ConstraintsFormView.swift
  - [ ] Page count slider (100-1000 pages) with live value label
  - [ ] Publication year picker (1900-2026) with decade shortcuts
  - [ ] Toggle for "only recent books" with smooth switch animation
  - [ ] **Visual feedback**: Slider thumb pulses on interaction
  - [ ] Skip button (optional step)
  - [ ] Form fields grouped in frosted glass cards
- [ ] **Step 5**: InitialRecommendationsView.swift
  - [ ] Show 5-10 recommendations based on preferences
  - [ ] **Hero moment**: "Finding your perfect books..." with loading animation
  - [ ] Recommendations appear with stagger animation (cascade effect)
  - [ ] Inline rating prompt ("Rate to improve") with star animation
  - [ ] "Done" button → navigate to main recs view with transition
  - [ ] **Celebration micro-interaction**: Confetti or success checkmark
- [ ] Save preferences to backend on completion
- [ ] Show onboarding on first launch only (@AppStorage flag)
- [ ] Test complete flow with /sim-safe
- [ ] Validate with /quick-validate (zero warnings)
- **Status:** pending
- **Estimated Duration:** 4 days (increased for premium polish)
- **Blockers:** Phase 3 completion (RecommendationCard reuse)

### Phase 5: Integration & Premium Polish (iOS 26 Excellence)
**Goal**: Connect all pieces and add production features with world-class attention to detail

- [ ] Add tab bar icon for Recommendations
  - [ ] Custom SF Symbol with hierarchical rendering
  - [ ] Badge indicator for new recommendations (subtle animation)
  - [ ] Tab selection animation (scale + color transition)
- [ ] Add deep linking support (recommendations://)
  - [ ] Smooth transition when launched from URL
  - [ ] Preserve navigation stack
- [ ] Implement exclusion logic
  - [ ] Auto-exclude books in user's library
  - [ ] Pass exclude param to API
  - [ ] Update on library changes with optimistic UI
  - [ ] **Visual feedback**: Toast notification "Already in library"
- [ ] Add analytics events
  - [ ] "Recommendations Viewed" (count, strategy)
  - [ ] "Recommendation Accepted" (isbn, score)
  - [ ] "Recommendation Dismissed" (isbn, score)
  - [ ] "Onboarding Completed" (time taken, steps completed)
- [ ] **iOS 26 Accessibility** (world-class inclusive design)
  - [ ] VoiceOver support for all interactive elements
  - [ ] Semantic labels for scores/reasons with context
  - [ ] Dynamic Type support (test at all sizes)
  - [ ] Increase touch targets to 44pt minimum
  - [ ] Color contrast compliance (WCAG AA)
  - [ ] Reduce motion alternatives for animations
- [ ] **Premium haptic feedback** (UIImpactFeedbackGenerator)
  - [ ] Light haptic on card tap
  - [ ] Medium haptic on "Add to Library" success
  - [ ] Soft haptic on pull-to-refresh trigger
  - [ ] Success haptic on onboarding completion
- [ ] **iOS 26 vibrancy and materials**
  - [ ] Frosted glass backgrounds where appropriate
  - [ ] Proper light/dark mode support
  - [ ] Vibrancy effects on overlays
- [ ] **Animation polish**
  - [ ] Spring animations (response: 0.5, dampingFraction: 0.7)
  - [ ] Stagger animations for list items
  - [ ] Smooth loading → content transitions
- [ ] Test navigation flows
- [ ] Test with /sim-safe (full integration)
- [ ] Validate with /quick-validate (zero warnings)
- **Status:** pending
- **Estimated Duration:** 2 days (increased for premium polish)
- **Blockers:** Phase 4 completion

### Phase 6: Testing & Validation
**Goal**: Comprehensive testing and zero warnings enforcement

- [ ] **Cold start scenario**
  - [ ] New user, no ratings
  - [ ] Set preferences only
  - [ ] Verify recommendations appear
  - [ ] Verify strategy: "cold_start"
- [ ] **Preference-based scenario**
  - [ ] User rates 5+ books (4-5 stars)
  - [ ] Verify recommendations improve
  - [ ] Verify strategy: "preference_based"
- [ ] **Exclusions**
  - [ ] Add book to library
  - [ ] Verify excluded from future recs
  - [ ] Verify exclude param works
- [ ] **Error handling**
  - [ ] Test no preferences/ratings case
  - [ ] Test API failure case
  - [ ] Test network timeout case
  - [ ] Verify friendly error messages
- [ ] **Performance**
  - [ ] Measure API response time (<3s)
  - [ ] Test slow network (Charles proxy)
  - [ ] Verify loading states work
- [ ] Run /quick-validate → zero warnings
- [ ] Run /sim-safe → manual UI testing
- [ ] Optional: /device-deploy for real device testing
- [ ] Document test results in progress.md
- **Status:** pending
- **Estimated Duration:** 1 day
- **Blockers:** Phase 5 completion

---

## Decisions Made

| Decision | Rationale | Date |
|----------|-----------|------|
| Use native Swift types (not TypeScript) | Swift-first codebase, type safety | 2026-01-09 |
| SwiftData for local caching | Existing pattern, offline support | 2026-01-09 |
| Reuse Work model for books | Already has all needed fields | 2026-01-09 |
| @MainActor for view models | Zero Warnings Policy enforcement | 2026-01-09 |
| Separate Recommendations feature module | Follows Goals/Insights architecture | 2026-01-09 |
| Build rating system in Phase 1 | Required for preference_based strategy | 2026-01-09 |
| 5-step onboarding flow | Matches backend guide recommendation | 2026-01-09 |
| Use Manus planning pattern | Complex task >5 tool calls, needs persistence | 2026-01-09 |
| **Elevate to iOS 26 world-class UI/UX** | Function first, beauty close second | 2026-01-09 |
| Premium animations and micro-interactions | Delightful user experience, brand differentiation | 2026-01-09 |
| World-class accessibility (WCAG AA) | Inclusive design, VoiceOver, Dynamic Type | 2026-01-09 |

---

## Errors Encountered

| Error | Attempt | Resolution | Date |
|-------|---------|------------|------|
| (none yet) | - | - | - |

---

## Dependencies

### External (bendv3 API)
- ✅ `/api/recommendations` endpoint (production ready)
- ✅ `/api/recommendations/debug` endpoint (production ready)
- ⚠️ `/api/users/me/preferences` endpoint (exists?)
- ⚠️ `/api/users/me/ratings` endpoint (exists?)

### Internal (BooksTrack iOS)
- Work model (BooksTrackerPackage/Sources/Types/Models/Work.swift)
- User model (BooksTrackerPackage/Sources/Types/Models/User.swift)
- APIClient (BooksTrackerPackage/Sources/Client/APIClient.swift)
- Auth system (x-user-id header mapping)
- Main tab bar navigation

---

## Success Criteria

### Functional Requirements
- [ ] New users can complete 5-step onboarding
- [ ] Users can set preferences (genres, mood, constraints)
- [ ] Users can rate books (1-5 stars)
- [ ] Recommendations API returns personalized results
- [ ] Recommendations display with scores and reasons
- [ ] Users can add recommended books to library
- [ ] Books in library are excluded from future recs
- [ ] Error states handle missing preferences gracefully
- [ ] Zero compiler warnings (enforced with -Werror)
- [ ] All UI tests pass with /sim-safe
- [ ] Code follows Swift 6 concurrency patterns

### iOS 26 Premium UI/UX Requirements
- [ ] **Animations**: Spring curves on all interactions (response: 0.5, dampingFraction: 0.7)
- [ ] **Micro-interactions**: Tap feedback, scale animations, stagger effects
- [ ] **Materials**: Frosted glass, vibrancy effects, proper light/dark mode
- [ ] **Typography**: SF Pro Display headlines, SF Pro Text body
- [ ] **Loading states**: Custom skeleton shimmer (not generic ProgressView)
- [ ] **Empty states**: Custom illustrations with encouraging copy
- [ ] **Score visualization**: Circular progress rings (not plain percentages)
- [ ] **Haptic feedback**: Light/medium/soft haptics at appropriate moments
- [ ] **Accessibility**: VoiceOver, Dynamic Type, 44pt targets, WCAG AA contrast
- [ ] **Polish**: Celebration moments, smooth transitions, optimistic updates
- [ ] **Feels premium**: User says "wow, this feels like a top-tier iOS app"

---

**Total Estimated Duration:** 13-14 days (increased from 10-11 for premium polish)
**Risk Level:** Medium-High (prerequisites unknown, complex onboarding, ambitious UX goals)
**Next Action:** Begin Phase 1 - read Work.swift, User.swift, APIClient.swift
