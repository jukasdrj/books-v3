# Diversity Insights - Product Requirements Document

**Status:** ✅ Shipped (v3.1.0)
**Owner:** Product Team
**Engineering Lead:** iOS Development Team
**Design Lead:** iOS 26 HIG Compliance
**Target Release:** v3.1.0 (October 2025)
**Last Updated:** November 23, 2025

---

## Executive Summary

The Diversity Insights tab provides comprehensive visualizations of cultural diversity, gender representation, language variety, and reading statistics. This feature transforms BooksTrack from a simple book tracker into a self-reflection tool that helps readers understand their reading habits through cultural and demographic lenses. By surfacing diversity metrics through beautiful Swift Charts visualizations, users can discover gaps in their reading (e.g., "0% authors from Africa") and set intentional goals to diversify their libraries.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Readers passionate about diverse representation lack tools to measure and track their reading diversity. While users may *intend* to read diversely (across cultures, genders, languages), they have no quantitative feedback to:

1. **Measure baseline diversity:** "What percentage of my authors are from marginalized communities?"
2. **Track progress:** "Am I reading more diversely this year vs last year?"
3. **Discover gaps:** "I've read zero books from African authors - let's fix that!"
4. **Set intentional goals:** "I want 50% of my 2025 reads to be from women authors"

**Impact:**
- **Lack of Awareness:** Readers don't realize their libraries are homogeneous (90% white, male, Western authors)
- **No Accountability:** Without metrics, diversity goals remain aspirational ("read more diversely" = vague)
- **Discovery Friction:** Users don't know which regions/demographics they're under-representing
- **Competitor Gap:** Goodreads/LibraryThing lack diversity analytics (competitive advantage for BooksTrack)

**Real-World Context:**
- **#ReadWomen movement:** Readers tracking gender % manually in spreadsheets
- **#ReadDiverse challenges:** Users want 50/50 splits but can't track progress
- **Cultural awareness:** Post-2020, readers seeking to decolonize their reading lists

### Current Experience (Before Diversity Insights)

**Manual Tracking:**
1. Export Goodreads CSV
2. Open Excel/Google Sheets
3. Manually tag each author's gender, region, marginalized status
4. Create pivot tables and charts
5. Update monthly as library grows

**Pain Points:**
- 5-10 hours manual work for 500-book library
- Error-prone (missed author demographics)
- Static snapshots (no real-time updates)
- No historical tracking (can't compare years)

**User Quote (Beta Feedback):**
> "I track my reading in a spreadsheet but it's exhausting. I just want to see: Am I reading diversely? Show me charts!"

---

## Target Users

### Primary Persona: **The Conscious Reader**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Readers who actively seek diverse representation in literature (ages 25-45, progressive values) |
| **Usage Frequency** | Weekly check-ins, monthly goal reviews |
| **Tech Savvy** | Medium-High (comfortable with data visualizations) |
| **Primary Goal** | Measure and improve reading diversity across culture, gender, language |

**Example User Story:**

> "As a **reader committed to diverse representation**, I want to **see visual charts of my library's cultural/gender breakdown** so that I can **identify gaps and set intentional goals to read more diversely**."

### Secondary Persona: **The Data Enthusiast**

Users who love statistics and gamification. They track pages read, books per month, and want deeper insights beyond simple counts.

---

## Success Metrics

### Key Performance Indicators (KPIs)

| Metric | Target | Current | Measurement Method |
|--------|--------|---------|-------------------|
| **Tab Engagement** | 40% of users visit Insights tab weekly | TBD | Analytics: `insights_tab_opened` |
| **Chart Interaction** | 20% of users tap charts (future feature) | N/A | Analytics: `chart_tapped` |
| **Diversity Score Awareness** | 60% of users check diversity score monthly | TBD | Unique user tracking |
| **Goal Setting Adoption** | 30% of users create diversity goals (Phase 5) | N/A | Future feature |
| **User Satisfaction** | 4.5/5 stars for feature (App Store reviews) | TBD | Review sentiment analysis |

**Success Criteria:**
- 40%+ weekly active users visit Insights tab at least once
- Diversity Score correlates with user engagement (higher score = more usage)
- <3% users report "charts confusing" (accessibility/UX issue)
- Feature mentioned positively in 10+ App Store reviews

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: View Cultural Diversity Breakdown

**As a** user wanting to understand my reading diversity
**I want to** see a chart of cultural regions represented in my library
**So that** I can identify underrepresented regions

**Acceptance Criteria:**
- [x] Given library with books from 5 different regions, when Insights tab loads, then horizontal bar chart shows all 5 regions
- [x] Given marginalized regions (Africa, Indigenous, Middle East, South Asia), when chart renders, then marginalized regions highlighted in theme color
- [x] Given user has 0 books from Africa, when chart shows, then "Africa: 0 books" bar is minimal height with annotation
- [x] Edge case: Given library with 0 books (no authors), when chart loads, then empty state shows "Add books with author metadata to see cultural insights"

---

#### User Story 2: Understand Gender Representation

**As a** reader tracking gender diversity
**I want to** see a donut chart of author gender percentages
**So that** I can measure progress toward 50/50 gender balance

**Acceptance Criteria:**
- [x] Given library with 60% male, 35% female, 5% non-binary authors, when donut chart renders, then segments show accurate percentages
- [x] Given donut chart displays, when rendered, then center shows total author count (e.g., "142 Authors")
- [x] Given gender distribution, when legend renders, then Female (pink), Male (blue), Non-Binary (purple), Other (orange), Unknown (gray at 30% opacity)
- [x] Edge case: Given all authors have Unknown gender, when chart shows, then single gray segment at 100% with message "Add author gender metadata"

---

#### User Story 3: See Language Variety

**As a** multilingual reader
**I want to** see all languages in my library as tappable tag cloud
**So that** I can browse books by language

**Acceptance Criteria:**
- [x] Given library with books in English, Spanish, French, when tag cloud renders, then 3 language pills displayed with flag emojis
- [x] Given languages sorted by book count (descending), when tags show, then English (100 books) appears before Spanish (20 books)
- [x] Given tag cloud layout, when screen size changes (rotation), then tags wrap naturally using FlowLayout
- [x] Edge case: Given book language is "Unknown", when tag cloud renders, then "Unknown" pill shown with book icon (no flag emoji)

---

#### User Story 4: Track Reading Statistics by Time Period

**As a** user setting annual reading goals
**I want to** filter statistics by "This Year" vs "All Time"
**So that** I can track 2025 progress separately from historical data

**Acceptance Criteria:**
- [x] Given time period picker with "All Time", "This Year", "Last 30 Days", when user taps "This Year", then stats recalculate for Jan 1-Dec 31 2025
- [x] Given "This Year" selected, when reading stats show, then "Pages Read" displays only pages from books completed in 2025
- [x] Given time period changes, when stats update, then diversity score recalculates for filtered subset
- [x] Edge case: Given "This Year" selected and Jan 1, when stats load, then "0 books completed this year" empty state shows

---

#### User Story 5: Understand Diversity Score

**As a** user seeing a "7.2/10" diversity score
**I want to** understand what contributes to this score
**So that** I know how to improve it

**Acceptance Criteria:**
- [x] Given diversity score calculated, when InsightsView loads, then score displayed as "7.2/10" in hero stats card
- [x] Given score breakdown (regions 2.0, gender 3.0, language 1.0, marginalized 1.2), when user taps score (future), then tooltip explains components
- [x] Given user has 11/11 regions, when score calculates, then regional component = 3.0 (max)
- [x] Edge case: Given library with 0 books, when score calculates, then shows "0.0/10" with message "Add books to calculate diversity"

**Diversity Score Formula (documented):**
```
regionScore      = (regionsRepresented / 11) × 3.0
genderScore      = genderDiversity × 3.0  // Shannon entropy (0-1)
languageScore    = min(languages / 5, 1.0) × 2.0
marginalizedScore = (marginalizedPercentage / 100) × 2.0

diversityScore = regionScore + genderScore + languageScore + marginalizedScore
// Max possible: 3.0 + 3.0 + 2.0 + 2.0 = 10.0
```

---

### Should-Have (P1) - Enhanced Experience

#### User Story 6: Hero Stats Quick Overview

**As a** user opening Insights tab
**I want to** see 4 key metrics at a glance (hero card)
**So that** I can assess diversity without scrolling

**Acceptance Criteria:**
- [x] Given library loaded, when hero card renders, then 2x2 grid shows: Regions, Gender %, Marginalized %, Languages
- [x] Given "5 of 11 regions", when hero card shows, then uses theme color accent for value
- [x] Given hero stats tappable (future), when user taps, then jumps to detailed chart section
- [x] Edge case: Given new user (0 books), when hero card shows, then all metrics display "--" placeholder

---

### Nice-to-Have (P2) - Future Enhancements

- [ ] **Custom Date Range Picker:** Select arbitrary date ranges (e.g., "Summer 2024")
- [ ] **Tap Chart to Filter Library:** Tap "Africa: 0 books" → filter Library tab to African authors
- [ ] **Historical Periods Chart:** Bar chart showing pre-1900, 1900-1950, 1951-2000, 2001-2020, 2021+ distribution
- [ ] **Comparison Mode:** Compare stats vs friends or community averages
- [ ] **Discovery Prompts:** "You haven't read any Oceania authors - explore recommendations!"
- [ ] **Export/Share Insights:** Generate infographic image for social sharing
- [ ] **Goal Setting with Progress Rings:** Set "50% women authors in 2025" goal with circular progress

---

## Functional Requirements

### High-Level Flow

**End-to-end user journey:**

```
User taps Insights tab (4th tab in TabBar)
    ↓
DiversityStats.calculate(from: modelContext)
ReadingStats.calculate(from: modelContext, period: .thisYear)
    ↓ 50-100ms calculation (cached for 1 minute)
InsightsView renders:
    ↓
1. Hero Stats Card (2x2 grid of key metrics)
2. Cultural Regions Chart (horizontal bar chart)
3. Gender Donut Chart (donut with legend)
4. Language Tag Cloud (wrapping capsule pills)
5. Reading Stats Section (time picker + 4 stat cards)
    ↓
User taps time period picker → Stats recalculate
User scrolls through charts → VoiceOver announces values
```

**See:** `docs/workflows/diversity-insights-flow.md` for Mermaid diagrams (to be created)

---

### Feature Specifications

#### 1. Diversity Statistics Calculation

**Description:** Calculate cultural, gender, language, and marginalized voice statistics from SwiftData

**Technical Requirements:**
- **Input:** ModelContext (SwiftData)
- **Processing:**
  - Fetch all `Work` objects with `authors` relationship
  - For each author: extract `culturalRegion`, `gender`, `originalLanguage`, `isMarginalizedVoice`
  - Group by region/gender/language, count occurrences
  - Calculate Shannon entropy for gender diversity (0-1 scale)
  - Compute diversity score using formula above
  - Cache results for 1 minute (performance optimization)
- **Output:** `DiversityStats` struct with arrays of stats
- **Error Handling:** If fetch fails, return empty stats with error message

**Performance:**
- First load: 50-100ms (depends on library size: 100-1500 books)
- Cached loads: <5ms (95% faster)
- Cache invalidated on library changes

**File:** `DiversityStats.swift`

---

#### 2. Reading Statistics by Time Period

**Description:** Calculate pages read, books completed, reading pace filtered by time period

**Technical Requirements:**
- **Input:** ModelContext + TimePeriod enum (.allTime, .thisYear, .last30Days)
- **Processing:**
  - Fetch all `UserLibraryEntry` objects where `status == .read`
  - Filter by `completionDate` based on selected period
  - Sum `work.editions.first?.pageCount` for pages read
  - Calculate average pages/day: `pagesRead / daysInPeriod`
  - Recalculate diversity score for filtered subset
  - Compare to previous period (e.g., This Year vs Last Year)
- **Output:** `ReadingStats` struct with pages, books, pace, diversity
- **Error Handling:** If no books in period, return zeros with empty state message

**Performance:**
- Calculation time: <100ms for 1000+ books
- No caching (recalculates on period change)

**File:** `ReadingStats.swift`

---

#### 3. Swift Charts Visualizations

**Description:** Native iOS charts using Swift Charts framework

**Chart Types:**
- **Horizontal Bar Chart** (Cultural Regions)
  - `BarMark` with region name, book count
  - Marginalized regions in theme color, others in gray
  - Accessibility: VoiceOver announces "Africa, 15 books, marginalized region"

- **Donut Chart** (Gender Representation)
  - `SectorMark` with gender, percentage
  - Golden ratio inner radius: 0.618
  - Center annotation shows total author count
  - Accessibility: Audio graph support

- **Tag Cloud** (Languages)
  - Custom FlowLayout (not Swift Charts)
  - Capsule buttons with flag emoji + count
  - Wraps naturally on screen rotation
  - Accessibility: "English, 100 books" label

**Technical Requirements:**
- iOS 26+ (Swift Charts minimum)
- Theme-aware colors via `iOS26ThemeStore.primaryColor`
- Liquid Glass backgrounds (`.ultraThinMaterial`)
- Dark Mode support (semantic colors)

**Files:**
- `CulturalRegionsChart.swift`
- `GenderDonutChart.swift`
- `LanguageTagCloud.swift`
- `FlowLayout.swift` (custom layout)

---

## Non-Functional Requirements

### Performance

| Requirement | Target | Current | Rationale |
|-------------|--------|---------|-----------|
| **First Load Time** | <200ms for 500 books | 50-100ms | Instant tab switching |
| **Cached Load Time** | <10ms | <5ms | Smooth navigation |
| **Memory Usage** | <30MB | <30MB | Efficient charting |
| **Chart Rendering** | <100ms | <100ms | Swift Charts optimized |

---

### Reliability

- **Calculation Accuracy:** 100% (deterministic formulas)
- **Cache Invalidation:** Automatic on library changes (NotificationCenter)
- **Empty State Handling:** All charts show helpful guidance when no data
- **Offline Support:** Fully offline (no network required)

---

### Accessibility (WCAG AA Compliance)

- [x] VoiceOver labels on all chart elements ("Africa, 15 books, marginalized region")
- [x] Color contrast ratio ≥ 4.5:1 (all text on backgrounds)
- [x] Audio graphs for donut chart (iOS 26 feature)
- [x] Dynamic Type support (all text scales)
- [x] Reduced motion (disable chart animations when enabled)
- [x] Keyboard navigation (iPad support)

**Accessibility Testing:**
- Manual VoiceOver testing on all charts
- Dynamic Type at largest size (Accessibility XXL)
- Dark Mode contrast verification

---

## Design & User Experience

### iOS 26 HIG Compliance

- [x] Swift Charts for native visualizations (recommended by Apple)
- [x] Liquid Glass materials (`.ultraThinMaterial` for card backgrounds)
- [x] Semantic colors (`.primary`, `.secondary`, `.tertiary`)
- [x] Theme-aware gradient (themeStore.backgroundGradient)
- [x] Standard corner radius (16pt for cards)
- [x] VoiceOver labels and hints
- [x] Dynamic Type scaling
- [x] Haptic feedback for interactions (future)

---

### User Feedback & Affordances

| State | Visual Feedback | Example |
|-------|----------------|---------|
| **Loading** | Progress indicator | Spinner while calculating stats |
| **Data Loaded** | Smooth chart animations | Bars/sectors animate in |
| **Empty State** | Helpful guidance | "Add books with author metadata to see insights" |
| **Time Period Change** | Chart updates | Smooth transition between periods |
| **Low Diversity** | Subtle indicators | "0 books from Africa" in muted color |

---

## Technical Architecture

### System Components

| Component | Type | Responsibility | File Location |
|-----------|------|---------------|---------------|
| **InsightsView** | SwiftUI View | Main container, orchestrates charts | `InsightsView.swift` |
| **HeroStatsCard** | SwiftUI View | 2x2 grid of key metrics | `HeroStatsCard.swift` |
| **CulturalRegionsChart** | SwiftUI View | Horizontal bar chart | `CulturalRegionsChart.swift` |
| **GenderDonutChart** | SwiftUI View | Donut chart with legend | `GenderDonutChart.swift` |
| **LanguageTagCloud** | SwiftUI View | Wrapping tag pills | `LanguageTagCloud.swift` |
| **ReadingStatsSection** | SwiftUI View | Time picker + stat cards | `ReadingStatsSection.swift` |
| **DiversityStats** | @MainActor Model | Statistics calculation | `DiversityStats.swift` |
| **ReadingStats** | @MainActor Model | Time-filtered statistics | `ReadingStats.swift` |
| **FlowLayout** | Custom Layout | Wrapping layout algorithm | `FlowLayout.swift` |

---

### Data Model Changes

**No new SwiftData models required.** Uses existing:
- `Work` (title, authors, originalLanguage)
- `Author` (name, gender, culturalRegion, isMarginalizedVoice)
- `UserLibraryEntry` (status, completionDate)
- `Edition` (pageCount for reading stats)

**New Enums:**
```swift
public enum TimePeriod: String, CaseIterable {
    case allTime = "All Time"
    case thisYear = "This Year"
    case last30Days = "Last 30 Days"
    case custom = "Custom Range" // Future
}
```

---

## Testing Strategy

### Unit Tests

- [x] Diversity score calculation - Verify formula accuracy (all components 0-10 scale)
- [x] Shannon entropy calculation - Test gender distribution balance metric
- [x] Time period filtering - "This Year" only includes current year books
- [x] Cache invalidation - Statistics update when library changes

**Test Files:**
- `DiversityStatsTests.swift`
- `ReadingStatsTests.swift`

---

### Integration Tests

- [x] Full pipeline: SwiftData → Stats → Charts → Rendering
- [x] Empty library → Empty states shown
- [x] Large library (1500 books) → Performance <200ms

**Test File:**
- `InsightsIntegrationTests.swift`

---

### Manual QA Checklist

**Core Workflow:**
- [ ] Tap Insights tab → Charts load in <200ms
- [ ] Hero card shows 4 correct metrics
- [ ] Cultural regions chart highlights marginalized regions (Africa, Middle East, etc.)
- [ ] Gender donut chart center shows total author count
- [ ] Language tag cloud wraps naturally on portrait/landscape rotation
- [ ] Tap "This Year" → Stats recalculate, diversity score changes
- [ ] Empty library → All charts show helpful empty states

**Accessibility:**
- [ ] VoiceOver reads all chart elements correctly
- [ ] Dynamic Type at largest size → Text scales, no clipping
- [ ] Dark Mode → All colors have sufficient contrast
- [ ] Reduced Motion enabled → Chart animations disabled

**Real Device Testing:**
- [ ] iPhone 17 Pro (iOS 26.0.1)
- [ ] iPhone 12 (iOS 26.0)
- [ ] iPad Pro 13" (iOS 26.0)

---

## Rollout Plan

### Phased Release

| Phase | Audience | Features Enabled | Success Criteria | Timeline |
|-------|----------|------------------|------------------|----------|
| **Alpha** | Internal team | Core charts + hero card | Zero crashes, charts render correctly | Week 1-2 (Oct 1-14) |
| **Beta** | TestFlight users | Full feature set | 40%+ weekly engagement | Week 3-4 (Oct 15-28) |
| **GA** | All users | Production-ready | 4.5/5 stars feature rating | Week 5 (Oct 29+) |

**Rollout completed:** v3.1.0 shipped October 2025

---

## Launch Checklist

**Pre-Launch:**
- [x] All P0 acceptance criteria met
- [x] Unit tests passing (DiversityStats, ReadingStats)
- [x] Manual QA completed (iPhone/iPad, VoiceOver)
- [x] Performance benchmarks validated (<200ms load)
- [x] iOS 26 HIG compliance review
- [x] Accessibility audit (WCAG AA contrast)
- [x] Analytics events instrumented (`insights_tab_opened`)
- [x] Documentation updated (CLAUDE.md, feature docs)

**Post-Launch:**
- [ ] Monitor tab engagement (target: 40% weekly users)
- [ ] Track empty state views (users with incomplete author metadata)
- [ ] Collect feedback on diversity score formula
- [ ] Measure chart interaction rates (future tappable feature)


## vNext (Q1 2026): Interactive Insights + Goals

Objective: Move from static dashboards to actionable, interactive insights that drive reading behavior change.

### Architecture Changes
1) Insights Store and Query Layer
- Create `InsightsStore` actor to cache computed stats and expose query functions (e.g., by region, by period).
- Persist last-computed stats snapshot for offline loading.

2) Tap-to-Filter Cross-Nav
- Introduce a lightweight routing contract so tapping a chart element opens Library with the appropriate filter pre-applied.
- Deep link format: `bookstrack://library?filter=region:africa`.

3) Goals Engine (Phase 1)
- Local-only goals with periodic reminders and progress rings.
- Goal model: type (region|gender|language), target %, period (This Year).

### UX Improvements
- Charts become interactive: tap a bar/sector to drill-down; long-press shows tooltip.
- Add “What to read next” card powered by gaps in diversity metrics.
- Empty states include a one-tap action to search recommended titles.
- Optional “Compare This Year vs Last Year” toggle.

### KPIs
- 25% of users create at least one goal in the first month.
- 30% of taps on charts result in a filtered Library view.
- Increase weekly Insights tab engagement by +15%.

### Acceptance Criteria (P0)
- Given a user taps “Africa” in the bar chart, the Library opens with region:africa filter applied and badge visible.
- Given a user creates a goal “≥50% women authors”, the progress ring updates as new books are added.
- Given offline mode, previously computed stats load instantly with “stale” banner and recompute on reconnect.

### API/Model Additions
- `Goal` model (SwiftData) with fields: id, type, target, period, createdAt, updatedAt.
- `InsightsStore` actor with methods: `calculate()`, `snapshot()`, `filterLink(for:)`.

---

---

## Related Documentation

- **Technical Implementation:** `docs/features/DIVERSITY_INSIGHTS.md` - Complete technical deep-dive
- **Workflow Diagram:** `docs/workflows/diversity-insights-flow.md` (to be created)
- **Implementation Plan:** `docs/plans/2025-10-26-diversity-insights-landing-page.md`
- **Data Models:** `docs/architecture/2025-10-26-data-model-breakdown.md`

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| Oct 15, 2025 | Initial draft | Product Team |
| Oct 20, 2025 | Added diversity score formula | Engineering |
| Oct 26, 2025 | Approved for v3.1.0 | PM |
| Oct 28, 2025 | Shipped to production | Engineering |
| Jan 27, 2025 | Converted to PRD format from feature doc | Documentation |

---

## Approvals

**Sign-off required from:**

- [x] Product Manager - Approved Oct 26, 2025
- [x] Engineering Lead - Approved Oct 26, 2025
- [x] Design Lead (iOS 26 HIG) - Approved Oct 24, 2025
- [x] QA Lead - Approved Oct 27, 2025

**Approved for Production:** v3.1.0 shipped October 28, 2025
