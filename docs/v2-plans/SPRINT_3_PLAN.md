# Sprint 3: Bento Box Layout Implementation

**Sprint Duration:** 1 Week (5 working days)
**Goal:** Transform WorkDetailView from vertical list to modular Bento Box dashboard
**Phase:** 1 (Foundation)

---

## Sprint Overview

### Objective
Replace the current single-column scroll layout in `WorkDetailView` with an interactive 2x2 Bento Box grid, establishing the visual foundation for v2's modular dashboard approach.

### Success Criteria
- [ ] WorkDetailView renders Bento Box grid on all iPhone sizes
- [ ] All 4 core modules implemented and functional
- [ ] Zero SwiftUI warnings, Swift 6 concurrency compliant
- [ ] Performance: <100ms time to interactive
- [ ] VoiceOver fully accessible (WCAG AA)

---

## Day-by-Day Implementation Plan

### Day 1: Data Model Extensions (Full Day)

> **Scope Adjustment (Grok-4 Review):** Originally included BentoBoxLayout skeleton,
> moved to Day 2 morning to ensure quality Work extensions with full test coverage.

**Morning (4 hours)**

1. **Extend Work Model** (`Extensions/Work+DiversityExtensions.swift`)
   - Add `diversityRadarValues: [Double]` computed property
   - Add private scoring helpers using existing model data
   - Add `metadataCompletion: Double` computed property

```swift
extension Work {
    /// Diversity radar values (0.0 - 1.0) for 5 axes
    /// Uses existing Work/Author data with realistic scoring logic
    var diversityRadarValues: [Double] {
        [
            culturalRepresentationScore,
            genderDiversityScore,
            translationScore,
            ownVoicesScore,
            accessibilityScore
        ]
    }

    /// Cultural representation: 1.0 if non-European/unknown, 0.5 if European, 0.0 if missing
    private var culturalRepresentationScore: Double {
        guard let region = culturalRegion else { return 0.0 }
        return region == .europe ? 0.5 : 1.0
    }

    /// Gender diversity: 1.0 if non-male, 0.5 if male, 0.0 if unknown
    private var genderDiversityScore: Double {
        guard let gender = authorGender, gender != .unknown else { return 0.0 }
        return gender == .male ? 0.5 : 1.0
    }

    /// Translation: 1.0 if non-English original, 0.0 if English or unknown
    private var translationScore: Double {
        guard let lang = originalLanguage?.lowercased() else { return 0.0 }
        return lang == "english" || lang == "en" ? 0.0 : 1.0
    }

    /// Own Voices: Stub at 0.5 until user verification flags implemented (Sprint 4+)
    private var ownVoicesScore: Double { 0.5 }

    /// Accessibility: Stub at 0.0 until accessibility tags implemented (Sprint 4+)
    private var accessibilityScore: Double { 0.0 }

    /// Metadata completion (0.0 - 1.0)
    var metadataCompletion: Double {
        let fields: [Any?] = [
            primaryEdition?.isbn13,
            primaryEdition?.publisher,
            // Note: seriesInfo not currently on Work model
            firstPublicationYear,
            primaryAuthor?.culturalRegion,
            primaryAuthor?.gender != .unknown ? primaryAuthor?.gender : nil,
            originalLanguage
        ]
        let filled = fields.compactMap { $0 }.count
        return Double(filled) / Double(fields.count)
    }
}
```

**Afternoon (4 hours)**

2. **Add Boolean Convenience Flags**
   - `isOwnVoices` - Stub until user verification
   - `hasQueerRep` - Check author gender for non-binary/other
   - `hasNeurodiversity` - Stub until tag system

3. **Write Comprehensive Unit Tests** (`WorkDiversityExtensionsTests.swift`)
   - Test each scoring property with edge cases
   - Test metadataCompletion with varying field presence
   - Test with nil relationships (no author, no edition)

**Deliverables:**
- [ ] `Work+DiversityExtensions.swift` with computed properties
- [ ] `WorkDiversityExtensionsTests.swift` with 100% coverage
- [ ] PR ready for self-review

---

### Day 2: BentoBoxLayout Skeleton + DNABlock

**Morning (4 hours)**

4. **Create BentoBoxLayout View** (`Views/BentoBoxLayout.swift`)
   - Implement `LazyVGrid` with responsive column logic
   - iPhone SE (< 375pt) uses single column
   - All other iPhones use 2-column layout
   - Wrap in `GlassCard` containers

```swift
@available(iOS 26.0, *)
struct BentoBoxLayout: View {
    @Bindable var work: Work
    let entry: UserLibraryEntry?

    /// Responsive columns: single column for iPhone SE, 2 columns otherwise
    private var columns: [GridItem] {
        let width = UIScreen.main.bounds.width
        return width < 375 ? [GridItem(.flexible())] : [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // Row 1: DNA + Diversity
            DNABlock(work: work)
            DiversityBlock(work: work)

            // Row 2: Reading Progress (full width)
            ReadingProgressBlock(entry: entry)
                .gridCellColumns(columns.count)  // Spans all columns

            // Row 3: Stats + Tags
            StatsBlock(work: work)
            TagsBlock(work: work)
        }
        .padding(.horizontal, 16)
    }
}
```

**Deliverables (Morning):**
- [ ] `BentoBoxLayout.swift` with responsive columns
- [ ] Placeholder stubs for all 5 module views

**Afternoon (4 hours)**

5. **Implement DNABlock** (`Views/Modules/DNABlock.swift`)
   - Essential metadata display (Published, Original, Series, Publisher)
   - Expandable "Technical Details" section
   - Uses `GlassCard` wrapper with "book.closed" icon
   - Implements `MetadataRow` helper component

6. **Create MetadataRow Component** (`Components/MetadataRow.swift`)
   - Reusable label-value pair with consistent styling
   - Support for `.subheadline` and `.caption` font variants
   - Accessibility labels for VoiceOver

7. **Integration Testing**
   - Verify DNABlock renders correctly in BentoBoxLayout
   - Test expandable section animation
   - Test with missing data (nil values)

**Deliverables (Day 2):**
- [ ] `BentoBoxLayout.swift` with responsive columns
- [ ] `DNABlock.swift` with full implementation
- [ ] `MetadataRow.swift` reusable component
- [ ] Integration tests for DNABlock
- [ ] SwiftUI Preview with sample data

---

### Day 3: DiversityBlock Module (Radar Chart Integration)

**Morning (4 hours)**

8. **Implement DiversityBlock** (`Views/Modules/DiversityBlock.swift`)
   - Integrate existing `RepresentationRadarChart`
   - Connect to `Work.diversityRadarValues`
   - Add "Complete" button for progressive profiling
   - Add identity badges (IdentityBadge component)

**Afternoon (4 hours)**

9. **Create IdentityBadge Component** (`Components/IdentityBadge.swift`)
   - Pill-style badge with color coding
   - Support for Own Voices (purple), Cultural (orange), LGBTQ+ (rainbow gradient), Neurodivergent (blue)
   - Horizontal scroll container for multiple badges

10. **Wire up RadarChart to Progressive Profiling**
    - `onAddData` callback triggers `ProgressiveProfilingPrompt`
    - Update radar chart after data entry
    - Test ghost state → complete state animation

**Deliverables (Day 3):**
- [ ] `DiversityBlock.swift` with radar chart integration
- [ ] `IdentityBadge.swift` component
- [ ] Wiring to `ProgressiveProfilingPrompt`
- [ ] Animation tests for data updates

---

### Day 4: ReadingProgressBlock, StatsBlock, TagsBlock, QuickFactPill

> **Scope Adjustment (Grok-4 Review):** Added ReadingProgressBlock which was missing
> from original plan despite being a critical full-width module.

**Morning (4 hours)**

11. **Implement ReadingProgressBlock** (`Views/Modules/ReadingProgressBlock.swift`)
    - Full-width progress bar with theme color
    - Current page / total pages display
    - Start/Stop reading session button
    - Uses `UserLibraryEntry` reading status and sessions

12. **Implement StatsBlock** (`Views/Modules/StatsBlock.swift`)
    - Display reading time, sessions, pace metrics
    - Pull from `UserLibraryEntry` reading sessions
    - Fallback display for books not yet started

**Afternoon (4 hours)**

13. **Implement TagsBlock** (`Views/Modules/TagsBlock.swift`)
    - Display `Work.subjectTags` as pill cloud
    - Use existing `FlowLayout` for wrapping tags
    - Tap to filter library by tag (navigation action)

14. **Create QuickFactPill Component** (`Components/QuickFactPill.swift`)
    - Horizontal scrollable pills for header facts
    - Icon + text format with translucent background
    - Support for color variants (default white, success green)

15. **Integrate QuickFactPill into Header**
    - Replace hardcoded header content with QuickFactPill row
    - Facts: pages, genre, year, rating, ownership status

**Deliverables (Day 4):**
- [ ] `ReadingProgressBlock.swift` implementation
- [ ] `StatsBlock.swift` implementation
- [ ] `TagsBlock.swift` implementation
- [ ] `QuickFactPill.swift` component
- [ ] Updated `WorkDetailView` header with pills

---

### Day 5: Integration, Polish, and Testing

**Morning (4 hours)**

16. **Full Integration in WorkDetailView**
    - Replace `mainContent` VStack with `BentoBoxLayout`
    - Ensure proper spacing and safe area handling
    - Test on **iPhone SE** (single-column), iPhone 15, iPhone 15 Pro Max

17. **Accessibility Audit**
    - VoiceOver navigation through all modules
    - Dynamic Type testing (up to accessibility size 5)
    - Color contrast validation (WCAG AA 4.5:1+)

**Afternoon (4 hours)**

18. **Performance Testing**
    - Measure time to interactive (<100ms target)
    - Profile radar chart rendering (<50ms target)
    - Verify smooth 60fps scrolling

19. **Final Polish + Buffer Time**
    - Animation timing refinement
    - Shadow and blur consistency
    - Edge case handling (empty library, no editions)
    - **Buffer:** Address any issues from PR review cycle

20. **Documentation Update**
    - Update CLAUDE.md with new component patterns
    - Add usage examples for new components
    - Update sprint checklist

**Deliverables (Day 5):**
- [ ] Fully integrated `WorkDetailView` with Bento Box
- [ ] iPhone SE responsive layout verified
- [ ] Accessibility audit passed
- [ ] Performance benchmarks documented
- [ ] PR ready for code review

---

## Technical Specifications

### File Structure

```
BooksTrackerFeature/
├── Views/
│   ├── Modules/
│   │   ├── DNABlock.swift
│   │   ├── DiversityBlock.swift
│   │   ├── StatsBlock.swift
│   │   ├── TagsBlock.swift
│   │   └── ReadingProgressBlock.swift
│   ├── BentoBoxLayout.swift
│   └── RepresentationRadarChart.swift (existing)
├── Components/
│   ├── GlassCard.swift (existing)
│   ├── MetadataRow.swift
│   ├── IdentityBadge.swift
│   └── QuickFactPill.swift
└── Extensions/
    └── Work+DiversityExtensions.swift
```

### Dependencies

| Component | Depends On |
|-----------|------------|
| BentoBoxLayout | DNABlock, DiversityBlock, StatsBlock, TagsBlock, GlassCard |
| DNABlock | MetadataRow, GlassCard, Work |
| DiversityBlock | RepresentationRadarChart, IdentityBadge, GlassCard, Work |
| StatsBlock | GlassCard, UserLibraryEntry |
| TagsBlock | FlowLayout, GlassCard, Work |
| QuickFactPill | (standalone) |

### Design Tokens

```swift
// Spacing
let moduleSpacing: CGFloat = 12
let modulePadding: CGFloat = 16
let sectionSpacing: CGFloat = 24

// Corner Radius
let cardRadius: CGFloat = 16
let pillRadius: CGFloat = 16 // fully rounded

// Typography
let headerFont: Font = .headline.weight(.semibold)
let labelFont: Font = .subheadline
let captionFont: Font = .caption
```

---

## Risk Assessment

### Medium Risk
1. **Radar chart performance on older devices**
   - Mitigation: Canvas rendering is optimized; add caching if needed

2. **Grid layout on iPhone SE**
   - Mitigation: Test early on Day 1; may need single-column fallback

### Low Risk
3. **SwiftData relationship access in computed properties**
   - Mitigation: Use optional chaining, tested patterns from existing code

---

## Definition of Done

- [ ] All 5 deliverable sets completed
- [ ] Zero compiler warnings
- [ ] All unit tests passing
- [ ] Accessibility audit passed
- [ ] Performance targets met
- [ ] Code reviewed and approved
- [ ] Merged to main branch

---

## Post-Sprint: Sprint 4 Handoff

Sprint 4 will build on this foundation:
- Basic Diversity UI enhancements
- Completion tracking refinements
- Progressive disclosure for metadata
- Initial gamification elements (Progress Ring overlay)

---

**Created:** November 25, 2025
**Author:** Claude (AI Assistant)
**Reviewed by:** Grok-4 (xAI)
**Status:** Approved with revisions incorporated

---

## Grok-4 Review Summary

**Review Date:** November 25, 2025

### Issues Addressed

| Severity | Issue | Resolution |
|----------|-------|------------|
| HIGH | Work extensions referenced undefined properties | Added concrete scoring logic using existing `culturalRegion`, `authorGender`, `originalLanguage` |
| MEDIUM | Day 1 scope overload | Split into Day 1 (extensions only) + Day 2 morning (BentoBoxLayout) |
| MEDIUM | ReadingProgressBlock missing | Added to Day 4 morning with full implementation spec |
| MEDIUM | iPhone SE fallback not allocated | Added responsive column logic + Day 5 SE testing |
| LOW | No buffer time | Added buffer in Day 5 afternoon for PR review cycles |

### Positive Feedback
- Excellent dependency ordering for parallel work
- Reuses battle-tested components (GlassCard, RadarChart)
- Strong risk assessment with mitigations
- Comprehensive success criteria (perf <100ms, WCAG AA)
