# Sprint 3: Book Enrichment UI (Ratings + Metadata + Annotations)

**Sprint Duration:** 2 weeks
**Sprint Goal:** Build user-facing UI for book enrichment system, leveraging BookEnrichment model from Sprint 2
**Status:** 📋 Planning
**Branch:** `feature/v2-book-enrichment-ui`
**Depends On:** Sprint 2 (BookEnrichment, CascadeMetadataService models)

---

## Overview

Sprint 3 focuses on creating the user-facing UI layer for the Book Enrichment system. While Sprint 2 built the data models and backend services (`BookEnrichment`, `CascadeMetadataService`), Sprint 3 delivers the interactive experience that allows users to:

- **Rate books** with a multi-source rating system (user, critics, community)
- **Track enrichment progress** with gamification widgets
- **View author profiles** with cascade metadata visualization
- **Manage overrides** for work-specific exceptions to cascaded data

---

## Goals

### Primary Goals
1. ✅ **Ratings UI Component** - Multi-source rating display and editing
2. ✅ **Enrichment Completion Widget** - Progress visualization with gamification
3. ✅ **Author Profile View** - Aggregated author metadata with cascade insights
4. ✅ **Override Management UI** - Create/edit/remove work-specific overrides

### Secondary Goals
5. 📊 **Enrichment Analytics** - Show enrichment stats across library
6. 🎨 **iOS 26 Design Polish** - Liquid Glass styling for all components
7. ⚡ **Performance** - Smooth 60fps scrolling in enrichment views

---

## User Stories

### 1. Rating Books (Priority: HIGH)
**As a user**, I want to rate books and see how my ratings compare to critics and community scores, so I can make informed reading decisions.

**Acceptance Criteria:**
- [ ] Star rating component (1-5 stars) in book detail view
- [ ] Display user rating, critics rating (e.g., NYT, Goodreads), community rating
- [ ] Tap to edit user rating with haptic feedback
- [ ] Save rating to `BookEnrichment.userRating`
- [ ] Visual differentiation between rating sources (color-coded)

### 2. Enrichment Progress Tracking (Priority: HIGH)
**As a user**, I want to see how complete my book enrichment is, so I can be motivated to add more metadata.

**Acceptance Criteria:**
- [ ] Completion percentage widget using `BookEnrichment.completionPercentage`
- [ ] Circular progress indicator (0-100%)
- [ ] Breakdown of completed fields (ratings, genres, themes, notes, etc.)
- [ ] Curator points display (gamification)
- [ ] "Complete Profile" CTA when < 100%

### 3. Author Profile Viewing (Priority: MEDIUM)
**As a user**, I want to view aggregated author information, so I understand how author metadata cascades to my books.

**Acceptance Criteria:**
- [ ] Author profile sheet/page with photo and bio (if available)
- [ ] Display `AuthorMetadata` fields (cultural background, gender identity, nationality)
- [ ] Show cascade status: "Applied to X books"
- [ ] List all books by author in my library
- [ ] Visual indicator for works with overrides

### 4. Override Management (Priority: MEDIUM)
**As a user**, I want to create exceptions for specific books, so I can handle co-authored works or special cases.

**Acceptance Criteria:**
- [ ] "Edit Override" button in book detail view
- [ ] Form to override specific fields (cultural background, gender identity)
- [ ] Required "reason" field (e.g., "Co-author with different background")
- [ ] Save to `WorkOverride` model via `CascadeMetadataService`
- [ ] Display override indicator in book cards
- [ ] Ability to remove overrides and revert to cascaded data

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Book Detail View                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  RatingsCard (NEW)                                    │  │
│  │  - User: ★★★★☆                                       │  │
│  │  - Critics: ★★★★★ (NYT)                             │  │
│  │  - Community: ★★★★☆ (Goodreads)                     │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  EnrichmentCompletionWidget (NEW)                     │  │
│  │  ⭕ 57% Complete                                      │  │
│  │  +35 Curator Points                                   │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Author Section                                       │  │
│  │  [Author Profile] → AuthorProfileView (NEW)           │  │
│  │  [Edit Override] → OverrideSheet (NEW)                │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Author Profile View (NEW)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Author Header                                        │  │
│  │  Photo, Name, Bio                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Metadata Card                                        │  │
│  │  Cultural Background: [value]                         │  │
│  │  Gender Identity: [value]                             │  │
│  │  Nationality: [value]                                 │  │
│  │  Languages: [list]                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Cascade Status                                       │  │
│  │  "Applied to 12 books" ✓                              │  │
│  │  "3 books with overrides" ⚠                          │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Books by Author (LazyVStack)                         │  │
│  │  - Work 1 (cascaded) ✓                                │  │
│  │  - Work 2 (override) ⚠                                │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

### Component Breakdown

#### 1. RatingsCard.swift (NEW)
**Purpose:** Display and edit multi-source book ratings

**Properties:**
- `@Bindable var enrichment: BookEnrichment` - Book enrichment data
- `userRating: Int?` - User's 1-5 star rating
- `criticsRating: Int?` - Critics' rating (from backend/API)
- `communityRating: Double?` - Community average (Goodreads, etc.)

**UI Elements:**
- Star rating picker (tap to edit)
- Read-only star displays for critics/community
- Labels: "Your Rating", "Critics (NYT)", "Community (Goodreads)"
- Haptic feedback on rating change
- Save animation on update

**Services:**
- Update `BookEnrichment.userRating` via `CascadeMetadataService`

#### 2. EnrichmentCompletionWidget.swift (NEW)
**Purpose:** Gamification widget showing enrichment progress

**Properties:**
- `@Bindable var enrichment: BookEnrichment` - Book enrichment data
- `completionPercentage: Double` - Computed from `enrichment.completionPercentage`
- `curatorPoints: Int` - Gamification score (5 points per field completed)

**UI Elements:**
- Circular progress indicator (SwiftUI `ProgressView` or custom)
- Percentage text (e.g., "57% Complete")
- Curator points display (e.g., "+35 Points")
- Breakdown list: ✓ Rating, ✓ Genres, ✗ Themes, etc.
- "Complete Profile" button (if < 100%)

**Computed Properties:**
- `curatorPoints: Int { Int(completionPercentage * 100) }`
- `missingFields: [String]` - List of incomplete fields

#### 3. AuthorProfileView.swift (NEW)
**Purpose:** Display aggregated author metadata and cascade status

**Properties:**
- `let authorId: String` - Author's unique ID
- `@State private var authorMetadata: AuthorMetadata?` - Fetched metadata
- `@State private var authorWorks: [Work]` - Books by author in library

**UI Elements:**
- Author header: photo (if available), name, bio
- Metadata card: cultural background, gender identity, nationality, languages
- Cascade status: "Applied to X books", "Y books with overrides"
- Books list: LazyVStack of book cards with cascade indicators

**Services:**
- Fetch `AuthorMetadata` via `CascadeMetadataService.fetchOrCreateAuthorMetadata()`
- Query `Work` where `author.id == authorId`

#### 4. OverrideSheet.swift (NEW)
**Purpose:** Create/edit/remove work-specific metadata overrides

**Properties:**
- `@Bindable var work: Work` - Work being edited
- `@State private var override: WorkOverride?` - Existing override (if any)
- `@State private var reason: String` - User-entered reason for override
- `@State private var culturalBackgroundOverride: String?`
- `@State private var genderIdentityOverride: String?`

**UI Elements:**
- Form with sections: "Cultural Background", "Gender Identity"
- Text field for each override value
- Text editor for "Reason" (required)
- "Save Override" button (disabled if no changes)
- "Remove Override" button (if override exists)
- Cancel button

**Services:**
- `CascadeMetadataService.createOverride()`
- `CascadeMetadataService.removeOverride()`

---

## Implementation Plan

### Week 1: Core UI Components (Days 1-5)

#### Day 1: RatingsCard Component
- [ ] Create `RatingsCard.swift` in `Views/Components/`
- [ ] Implement star rating picker with haptic feedback
- [ ] Add read-only star displays for critics/community
- [ ] Wire up to `BookEnrichment.userRating`
- [ ] Add unit tests for rating logic

#### Day 2: EnrichmentCompletionWidget
- [ ] Create `EnrichmentCompletionWidget.swift`
- [ ] Implement circular progress indicator
- [ ] Add curator points calculation
- [ ] Create field breakdown list
- [ ] Add iOS 26 Liquid Glass styling
- [ ] Add unit tests for completion percentage

#### Day 3: Integrate RatingsCard + Widget into Book Detail
- [ ] Update `WorkDetailView` to include RatingsCard
- [ ] Add EnrichmentCompletionWidget below RatingsCard
- [ ] Test enrichment data flow
- [ ] Verify save operations work correctly

#### Day 4: AuthorProfileView (Part 1 - Layout)
- [ ] Create `AuthorProfileView.swift`
- [ ] Implement author header (photo, name, bio)
- [ ] Add metadata card with fields
- [ ] Style with iOS 26 Liquid Glass

#### Day 5: AuthorProfileView (Part 2 - Data Loading)
- [ ] Integrate `CascadeMetadataService` for data fetching
- [ ] Query works by author
- [ ] Add cascade status indicators
- [ ] Test navigation from book detail view

---

### Week 2: Override Management + Polish (Days 6-10)

#### Day 6: OverrideSheet UI
- [ ] Create `OverrideSheet.swift`
- [ ] Implement form with cultural background + gender identity fields
- [ ] Add reason text editor
- [ ] Add save/cancel buttons
- [ ] Style with iOS 26 Liquid Glass

#### Day 7: OverrideSheet Logic + Integration
- [ ] Wire up `CascadeMetadataService.createOverride()`
- [ ] Implement remove override functionality
- [ ] Add validation (reason required)
- [ ] Test override creation/deletion flow
- [ ] Add unit tests for override logic

#### Day 8: Integration Testing
- [ ] Test cascade → enrichment → UI flow
- [ ] Test override → cascade update → UI refresh
- [ ] Verify gamification points calculation
- [ ] Test ratings save/load
- [ ] Test author profile navigation

#### Day 9: Performance + Polish
- [ ] Profile EnrichmentCompletionWidget rendering (60fps target)
- [ ] Optimize AuthorProfileView lazy loading
- [ ] Add loading states and skeletons
- [ ] Improve error handling and user feedback
- [ ] Add accessibility labels

#### Day 10: Documentation + Cleanup
- [ ] Update API_CONTRACT.md with new components
- [ ] Create Sprint 3 summary document
- [ ] Clean up debug logging
- [ ] Final build verification (zero warnings)
- [ ] Prepare Sprint 3 retrospective

---

## Testing Strategy

### Unit Tests
- [ ] `RatingsCardTests.swift` - Star rating logic, save operations
- [ ] `EnrichmentCompletionWidgetTests.swift` - Completion percentage, curator points
- [ ] `AuthorProfileViewTests.swift` - Data loading, cascade status
- [ ] `OverrideSheetTests.swift` - Override creation/deletion, validation

### Integration Tests
- [ ] Cascade → Enrichment → UI flow
- [ ] Override → Cascade update → UI refresh
- [ ] Progressive Profiling → Cascade → Enrichment completion

### UI Tests (Optional)
- [ ] Star rating interaction
- [ ] Enrichment widget tap-through
- [ ] Author profile navigation
- [ ] Override sheet form submission

---

## Performance Targets

- **RatingsCard render:** < 16ms (60fps)
- **EnrichmentCompletionWidget render:** < 16ms (60fps)
- **AuthorProfileView initial load:** < 200ms
- **OverrideSheet save operation:** < 100ms
- **Memory:** No leaks, stable usage during navigation

---

## Design Requirements

### iOS 26 Liquid Glass Styling
- Use `iOS26ThemeStore.primaryColor` for brand accents
- Glass card backgrounds with blur effects
- Aurora gradient overlays for highlights
- Proper WCAG AA contrast (4.5:1+) for text

### Accessibility
- All interactive elements have accessibility labels
- Star ratings support VoiceOver announcements
- Forms have clear field labels and hints
- Override reasons are descriptive

---

## Dependencies

### Sprint 2 Deliverables (REQUIRED)
✅ `BookEnrichment` model
✅ `AuthorMetadata` model
✅ `WorkOverride` model
✅ `CascadeMetadataService`
✅ `SessionAnalyticsService` (for gamification)

### External APIs (OPTIONAL)
- NYT Critics Rating API (future integration)
- Goodreads Community Rating (future integration)
- Author bio/photo from OpenLibrary or Google Books

---

## Success Metrics

### Feature Completion
- [ ] All 4 primary UI components built and tested
- [ ] Zero compiler warnings/errors
- [ ] 100% unit test pass rate
- [ ] iOS 26 design compliance

### User Experience
- [ ] Smooth 60fps scrolling in all enrichment views
- [ ] < 200ms load time for author profiles
- [ ] Haptic feedback on rating interactions
- [ ] Clear visual feedback for save operations

### Code Quality
- [ ] Swift 6.2 concurrency compliance
- [ ] @MainActor actor isolation for UI components
- [ ] Proper error handling and logging
- [ ] Public access control for cross-module components

---

## Risks & Mitigations

### Risk 1: Critics/Community Rating Data Unavailable
**Impact:** RatingsCard shows only user rating
**Mitigation:** Design component to gracefully handle missing data (hide critics/community sections if nil)

### Risk 2: Performance Issues with Large Author Catalogs
**Impact:** AuthorProfileView slow for prolific authors (100+ books)
**Mitigation:** Use pagination/lazy loading for books list, cache author metadata

### Risk 3: Override UI Complexity
**Impact:** Users confused about when/why to use overrides
**Mitigation:** Add help text, examples, and clear "Revert to Cascaded" option

---

## Sprint Backlog

### Must Have (P0)
1. RatingsCard component
2. EnrichmentCompletionWidget component
3. Integration into book detail view
4. Basic author profile view

### Should Have (P1)
5. Override management UI
6. Cascade status visualization
7. Gamification points display

### Nice to Have (P2)
8. Critics/community ratings integration (API dependent)
9. Enrichment analytics dashboard
10. Author bio/photo fetching

---

## Definition of Done

A Sprint 3 feature is "done" when:
- ✅ Code written and merged to `feature/v2-book-enrichment-ui`
- ✅ Unit tests written and passing
- ✅ Integration tests passing
- ✅ Zero compiler warnings/errors
- ✅ iOS 26 design compliance verified
- ✅ Accessibility labels added
- ✅ Performance targets met (60fps, < 200ms loads)
- ✅ Documentation updated (API_CONTRACT.md)
- ✅ Code reviewed and approved (multi-agent review)

---

## Next Steps

1. **Kick off Sprint 3** - Begin Week 1 Day 1 (RatingsCard)
2. **Create feature branch** - `feature/v2-book-enrichment-ui`
3. **Set up test fixtures** - Mock BookEnrichment, AuthorMetadata, Work data
4. **Design mockups** - Sketch RatingsCard and EnrichmentCompletionWidget layouts

---

**Created:** November 21, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Planning Phase
**Next Sprint:** Sprint 4 (Enhanced Diversity Analytics)
