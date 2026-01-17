# Findings: Frontend Recommendations Integration

**Task**: Implement personalized book recommendations in BooksTrack iOS app
**Date**: 2026-01-09
**Backend Guide**: `/Users/juju/dev_repos/bendv3/docs/FRONTEND_RECOMMENDATION_INTEGRATION.md`

---

## Requirements

### Backend API (bendv3 - Ready)
- ✅ `GET /api/recommendations` - Production endpoint
- ✅ `GET /api/recommendations/debug` - Debug with scoring breakdown
- ✅ Content-based filtering using Alexandria subjects
- ✅ Dual strategy: `preference_based` vs `cold_start`
- ✅ Scoring: 0-100 scale (subject match + preference match + diversity)
- ✅ Exclusion support (ISBNs to skip)
- ✅ Configurable limit (max 50)

### iOS App Prerequisites
- ❓ User rating system (1-5 stars) - **NEEDS VERIFICATION**
- ❓ User preferences storage (genres, mood, constraints) - **NEEDS VERIFICATION**
- ⚠️ Authentication (x-user-id header) - **NEEDS INVESTIGATION**

---

## Research Findings

### Backend API Capabilities (712-line guide analyzed)

**Endpoint 1: `/api/recommendations`**
```
Query params: limit (default 10, max 50), exclude (comma-separated ISBNs)
Headers: x-user-id (TODO: map to actual auth)
Response: {recommendations[], total, strategy}
```

**Endpoint 2: `/api/recommendations/debug`**
```
Same as above + breakdown {subject_match, preference_match, diversity_bonus}
```

**Scoring Algorithm:**
- Subject match: 0-60 points (shared themes from Alexandria metadata)
- Preference match: 0-20 points (alignment with user preferences)
- Diversity bonus: 0-20 points (encourages variety)

**Strategies:**
- `preference_based`: User has 4-5 star ratings
- `cold_start`: User has preferences only, no ratings

### iOS Architecture Patterns

**Existing Features (Similar Complexity):**
- Goals Engine (Phase 3) - 6 goal types, progress tracking
- Insights Filtering (Phase 1) - Tap-to-filter navigation
- Library View - Book display, filtering, CloudKit sync

**Code Organization:**
- Feature modules: BooksTrack/Features/{FeatureName}/
- Models: BooksTrackerPackage/Sources/Types/Models/
- API clients: BooksTrackerPackage/Sources/Client/
- SwiftData persistence, CloudKit sync, @MainActor compliance

### Onboarding Flow Design (from guide)

**5-step wizard:**
1. Welcome screen - Introduction
2. Genre selection - Multi-select from 10-15 genres
3. Mood picker - 5 options (light, dark, epic, cozy, thrilling)
4. Constraints - Page count range, publication year
5. Initial recommendations - 5-10 books, rate to improve

**iOS Implementation:**
- TabView (page style) for steps
- FlowLayout for genre chips
- Radio buttons for mood
- Sliders for constraints
- LazyVStack for initial recs

---

## Technical Decisions

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Use native Swift types (not TS port) | Swift-first codebase, type safety | Create Swift equivalents of TS types |
| SwiftData for local caching | Existing pattern, offline support | New models: Recommendation, ScoredBook |
| Async/await API client | Swift 6 concurrency compliance | Clean, maintainable async code |
| @MainActor for view models | Zero Warnings Policy enforcement | Thread-safe UI updates |
| Separate feature module | Follows existing architecture | BooksTrack/Features/Recommendations/ |
| Reuse Work model for books | Already has cover, title, authors | Minimal new types needed |
| Follow Insights filter pattern | Proven navigation approach | Tap card → filter library |
| **Elevate to iOS 26 world-class UI/UX** | Function is top priority, but beautiful UX is close second | Premium polish, animations, accessibility |

### iOS 26 Design Principles (New Requirement)

**Goal**: World-class iOS 26 aesthetics - function first, beauty second

**Key Design Elements:**
1. **Premium animations**: Spring curves (response: 0.5, dampingFraction: 0.7)
2. **Micro-interactions**: Scale feedback (0.95 → 1.0), haptics, stagger animations
3. **iOS 26 materials**: Frosted glass, vibrancy effects, proper light/dark mode
4. **SF Pro typography**: Display for headlines, Text for body
5. **Skeleton loading**: Not generic ProgressView, custom shimmer cards
6. **Delightful empty states**: Custom illustrations, encouraging copy
7. **Circular progress rings**: For score badges (not simple percentages)
8. **Gradient pill badges**: For strategy indicators
9. **Card-based selection**: For onboarding (not plain radio buttons)
10. **Celebration moments**: Confetti/checkmarks on completion

**Accessibility (World-Class):**
- VoiceOver with semantic labels
- Dynamic Type support (all sizes)
- 44pt minimum touch targets
- WCAG AA color contrast
- Reduce motion alternatives

**Haptic Feedback:**
- Light: Card tap
- Medium: Add to library success
- Soft: Pull-to-refresh trigger
- Success: Onboarding completion

**Duration Impact:**
- Phase 3: +1 day (premium card design)
- Phase 4: +1 day (delightful onboarding)
- Phase 5: +1 day (accessibility + polish)
- **Total increase**: +3 days (10-11 → 13-14 days)

### Swift Type Mapping (TS → Swift)

**Backend TypeScript:**
```typescript
ScoredRecommendation {
  book: SimilarBook
  score: number
  reasons: string[]
  breakdown?: { subject_match, preference_match, diversity_bonus }
}
```

**iOS Swift:**
```swift
struct ScoredRecommendation: Codable, Identifiable {
  let id: String  // work_key
  let book: Work  // Reuse existing model
  let score: Double
  let reasons: [String]
  let breakdown: ScoreBreakdown?
}

struct ScoreBreakdown: Codable {
  let subjectMatch: Double
  let preferenceMatch: Double
  let diversityBonus: Double
}

enum RecommendationStrategy: String, Codable {
  case preferenceBased = "preference_based"
  case coldStart = "cold_start"
}
```

---

## Issues Encountered

| Issue | Resolution |
|-------|------------|
| Guide is TypeScript/React focused | Adapt patterns to Swift/SwiftUI idiomatically |
| Prerequisites unclear (rating/preferences) | Phase 1: Investigate existing models |
| Authentication mapping unclear | Phase 1: Read APIClient.swift for auth pattern |
| 712-line guide overwhelming | Use Manus planning, break into 6 phases |
| Onboarding flow complex (5 steps) | Dedicate Phase 4 entirely to onboarding |

---

## Resources

### Documentation
- Backend guide: `/Users/juju/dev_repos/bendv3/docs/FRONTEND_RECOMMENDATION_INTEGRATION.md` (712 lines)
- System architecture: `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`
- Swift 6 patterns: `.claude/rules/swift-concurrency.md`
- Testing guide: `.claude/rules/safe-testing.md`

### Files Investigated (Phase 1) ✅

**COMPLETED:**
- ✅ `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift` - Read (lines 1-250)
- ✅ `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift` - Read (full file)
- ✅ `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/UserSettings.swift` - Read (full file)
- ✅ `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/V3APIClientActual.swift` - Read (lines 1-80)
- ✅ Rating UI search - No existing UI found
- ✅ Preferences UI search - No existing UI found

**FINDINGS:**
1. **Rating system EXISTS** ✅
   - `UserLibraryEntry.rating` (Int? 1-5 stars) - line 29
   - `UserLibraryEntry.personalRating` (Double? 0.0-5.0 granular) - line 30
   - Validation method exists: `validateRating()` - line 221
   - **Status:** Backend ready, UI missing

2. **Preferences storage: NOW EXISTS** ✅
   - **Created:** `UserPreferences.swift` (215 lines) - BooksTrackerPackage/Sources/BooksTrackerFeature/Models/
   - SwiftData @Model with @Attribute(.unique) on userId
   - Fields: preferredSubjects, excludedSubjects, preferredAuthors, excludedAuthors
   - Mood: ReadingMood enum (light, dark, epic, cozy, thrilling) with displayName, description, systemImage, gradients
   - Constraints: pageCountMin/Max, publicationYearMin/Max
   - Validation: isPageCountValid, isPublicationYearValid, hasPreferences
   - API conversion: toDictionary() for backend requests (snake_case keys)
   - Metadata: lastUpdated, onboardingCompleted
   - **Status:** Model complete, UI pending (Phase 4)

3. **Rating UI: EXISTS** ✅
   - **Found:** `StarRatingView.swift` (243 lines) - BooksTrackerPackage/Sources/BooksTrackerFeature/Components/
   - Premium iOS 26 design with gradient fill (#FFD700 → #FF9900)
   - Half-star support (allowsHalfStars parameter)
   - Three sizes: compact, standard, large
   - Spring animations (response: 0.3, dampingFraction: 0.6)
   - Haptic feedback (light on tap, selection on drag)
   - Drag gesture for quick rating
   - Glow effect on filled stars (yellow shadow)
   - VoiceOver accessibility with adjustable actions
   - **Already integrated** in UserInteractionBlock.swift:48-57
   - Binds to UserLibraryEntry.personalRating (Double)
   - **Status:** Complete, production-ready

4. **Preferences UI: MISSING** ❌
   - No genre selection UI
   - No mood picker UI
   - No constraints form
   - **Status:** Need to build complete onboarding flow

5. **Auth pattern: X-Request-ID only** ⚠️
   - V3APIClientActual uses X-Request-ID header (line 15)
   - NO x-user-id header found in existing code
   - **Status:** Need to add user identification to API client

### Similar Features
- Goals Engine (Phase 3) - Multi-type model, progress tracking
- Insights Filtering (Phase 1) - Tap-to-filter navigation
- Reading Sessions - User preferences, tracking

---

## Implementation Progress (Phases 1-3)

### Phase 1: Prerequisites ✅ COMPLETE
- **Duration:** ~1 hour
- **Outcome:** StarRatingView exists, UserPreferences model created
- **Key Finding:** Rating UI already exists with premium iOS 26 design

### Phase 2: API Client ✅ COMPLETE
- **Duration:** ~15 minutes (with PAL expert consultation)
- **Outcome:** RecommendationsClient + RecommendationTypes created
- **Expert Guidance:** Gemini 3 Pro via PAL MCP
- **Architecture:** Separate client class (different error schema)
- **Pattern:** Stateless userId parameter for better testability

### Phase 3: Core UI (IN PROGRESS)
- **Duration So Far:** ~15 minutes
- **Completed:**
  - RecommendationCard (~380 lines) with circular score ring
  - RecommendationsViewModel (~160 lines) with @Observable pattern
  - Custom Equatable conformance for RecommendationError
- **Remaining:**
  - RecommendationsListView with skeleton/empty/error states
  - Tab bar navigation integration

### Files Created (Sessions 4-6)

**Models & Types:**
1. `UserPreferences.swift` (215 lines) - SwiftData model with ReadingMood enum
2. `RecommendationTypes.swift` (203 lines) - 6 domain models + error enum
3. `RecommendationsClient.swift` (170 lines) - @MainActor API client

**UI Components:**
4. `RecommendationCard.swift` (380 lines) - Premium card with ScoreRing
5. `RecommendationsViewModel.swift` (160 lines) - @Observable view model

**Total Lines:** ~1,128 lines of production code

### Design Patterns Applied

| Pattern | Application | Source |
|---------|-------------|--------|
| @Observable | RecommendationsViewModel | Swift 6 pattern |
| @MainActor | Thread-safe UI updates | Swift concurrency |
| Glass Card Material | RecommendationCard background | GlassCard.swift |
| Circular Progress Ring | ScoreRing component | CompletionRing.swift |
| Scale Button Style | Card interaction feedback | ScaleButtonStyle.swift |
| Optimistic Updates | markAsAddedToLibrary() | iOS best practice |
| Typed Error Enum | RecommendationError | Clean architecture |
| Custom Equatable | ViewState conformance | Swift protocol |

### Technical Challenges Solved

1. **Equatable Conformance:** RecommendationError has associated Error value
   - Solution: Custom == implementation comparing by case

2. **Type Imports:** V3Book not found in scope
   - Solution: Types in same module, no import needed

3. **ForEach Iterator:** Enumerated array binding issue
   - Solution: Use Array() with id: \.self instead of enumerated

4. **ViewBuilder Return:** Explicit return in preview
   - Solution: Remove return keyword (implicit return)

---

## Key Insights

1. **Backend is production-ready** - No API changes needed, comprehensive guide
2. **Type safety critical** - Swift types must match backend response exactly
3. **Onboarding is major effort** - 5-step wizard requires dedicated phase
4. **Prerequisites existed** - StarRatingView + rating backend already built
5. **PAL MCP invaluable** - Expert architectural guidance (Gemini 3 Pro)
6. **Existing patterns accelerate development** - GlassCard, CompletionRing reused
7. **Custom Equatable needed** - Error enum with associated values requires manual ==
8. **Zero Warnings achievable** - Strict Swift 6 compliance maintained
