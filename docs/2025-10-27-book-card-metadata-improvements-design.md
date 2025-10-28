# Book Card Metadata Improvements - Design Document

**Date:** October 27, 2025
**Issues:** #144, #145, #146
**Status:** Approved for Implementation
**Consensus Score:** 9/10 (Pro), Balanced with Critical Analysis

## Executive Summary

Resolve three GitHub issues by creating reusable SwiftUI components for book metadata display, improving user experience through better data presentation and enhanced navigation to author bibliographies.

## Problem Statement

### GitHub Issues
1. **#144** - Year published still shows comma formatting
2. **#145** - Author name should link to bibliography search
3. **#146** - Genre/subject tags are tracked but not displayed

### Current State
- `iOS26AdaptiveBookCard` has 4 display modes (compact/standard/detailed/hero)
- Metadata display is inline and not reusable
- No navigation from author name to their other works
- `Work.subjectTags` array exists but is never rendered

## Design Decisions

### Approved Architecture (Pragmatic Scope)

Based on consensus analysis, we're taking a **balanced approach** that delivers high value with controlled complexity:

#### ✅ New Components (High Value, Reusable)

**1. BookMetadataRow.swift**
- **Purpose:** Reusable metadata display with icon + text pattern
- **Scope:** Handles year, publisher, page count, ISBN, etc.
- **Benefits:** Enforces consistent styling, WCAG AA contrast, reduces duplication
- **Usage:** Both iOS26AdaptiveBookCard and WorkDetailView

**2. GenreTagView.swift**
- **Purpose:** Compact genre/subject tag chips
- **Scope:** Displays 1-2 top genres from `Work.subjectTags`
- **Visibility:** Only renders in `.detailed` and `.hero` card modes
- **Benefits:** Progressive disclosure pattern (iOS 26 HIG compliant)

#### ⚠️ Simplified Approaches (Defer Complexity)

**Author Navigation:**
- **Initial Implementation:** Use inline `NavigationLink` styled as button with chevron
- **Rationale:** Don't extract `AuthorLinkButton` component until used in 3+ places (YAGNI)
- **Future:** If pattern repeats, extract to component

**Author Bibliography View:**
- **Phase 1 (MVP):** Navigate to Search tab with pre-filled author query
- **Phase 2 (Future):** Build dedicated `AuthorBibliographyView` after validating user demand
- **Rationale:** Validate feature value before investing in dedicated UI

### Key Design Patterns

#### 1. BookMetadataRow API
```swift
struct BookMetadataRow: View {
    let icon: String              // SF Symbol name
    let text: String              // Display text
    let style: MetadataStyle      // .secondary or .tertiary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(style.color)
            .accessibilityLabel(accessibilityText)
    }
}
```

**Usage:**
```swift
BookMetadataRow(icon: "calendar", text: "\(year)", style: .secondary)
    .accessibilityLabel("Year Published: \(year)")
```

#### 2. GenreTagView API
```swift
struct GenreTagView: View {
    let genres: [String]
    let maxVisible: Int = 2

    var body: some View {
        if !genres.isEmpty {
            HStack(spacing: 6) {
                ForEach(genres.prefix(maxVisible), id: \.self) { genre in
                    genreChip(genre)
                }
            }
        } else {
            EmptyView()  // Handle empty subjectTags gracefully
        }
    }
}
```

#### 3. Author Navigation Pattern
```swift
// In iOS26AdaptiveBookCard
NavigationLink(value: AuthorSearchDestination(author: work.primaryAuthor)) {
    HStack(spacing: 4) {
        Text(work.authorNames)
            .font(.caption)
            .foregroundStyle(.secondary)
        Image(systemName: "chevron.forward")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
```

### Progressive Disclosure Strategy

**Compact Mode:**
- Title only
- Status indicator

**Standard Mode:**
- Title
- Author (with navigation chevron)
- Status indicator

**Detailed Mode:**
- Title
- Author (with navigation chevron)
- **Year** (calendar icon + year)
- **Genre tags** (1-2 chips)
- Format indicator
- Status indicator

**Hero Mode:**
- All detailed mode content
- Larger fonts and spacing
- Enhanced visual hierarchy

## Edge Cases & Error Handling

### Data Availability
| Scenario | Behavior |
|----------|----------|
| Missing `firstPublicationYear` | `BookMetadataRow` not rendered |
| Empty `subjectTags` array | `GenreTagView` returns `EmptyView()` |
| Author with no other works | Search shows "No results found" message |
| Ambiguous author name (e.g., "John Smith") | Show "Results for [Author Name]" header |

### Genre Tag Overflow
- Display max 2 tags in compact space
- Future enhancement: Horizontal scrolling for 3+ tags
- Tag text truncation: `...` for long genre names

### Navigation Stack Depth
- Standard iOS navigation pattern (push/pop)
- Users can navigate: Library → Detail → Author Search → Another Detail
- System back button provides clear exit path

## Accessibility (WCAG AA)

### Compliance Requirements
1. **Icon Labels:** All SF Symbols must have descriptive accessibility labels
   - ✅ Calendar icon: "Year Published"
   - ✅ Chevron: "View author bibliography"

2. **Color Contrast:**
   - `.secondary` color: 4.5:1 minimum on all theme backgrounds
   - Genre chips: Theme-aware tinting with adequate contrast

3. **Touch Targets:**
   - Author navigation area: Minimum 44×44 pt (iOS HIG)
   - Genre tags: Decorative only (non-interactive)

## iOS 26 HIG Compliance

### Design Patterns Used
- **Progressive Disclosure:** Show more detail as space allows
- **Visual Hierarchy:** Icons + color + typography for scannable metadata
- **Drill-Down Navigation:** Standard push pattern for author bibliography
- **Adaptive Layouts:** Components respond to available space (4 card modes)

### Liquid Glass Design Integration
- `BookMetadataRow`: Uses semantic colors that adapt to glass backgrounds
- `GenreTagView`: Capsule style with theme-aware `.opacity(0.15)` tinting
- Navigation chevron: `.tertiary` foreground for subtle affordance

## Testing Strategy

### Unit Tests
- `BookMetadataRow`: Nil/empty data handling
- `GenreTagView`: Empty array, single tag, 2+ tags, long text truncation

### Integration Tests
- iOS26AdaptiveBookCard: All 4 display modes render components correctly
- WorkDetailView: Metadata components display consistently
- Navigation: Author link triggers search with correct query

### Visual Regression
- Screenshot tests for each card display mode
- Theme variations (all 5 built-in themes)

### Deferred (Phase 2)
- AuthorBibliographyView testing (when implemented)
- Performance testing for large genre tag arrays

## Implementation Phases

### Phase 1: Core Components (This Iteration)
1. Create `BookMetadataRow.swift` component
2. Create `GenreTagView.swift` component
3. Update `iOS26AdaptiveBookCard`:
   - Replace year display with `BookMetadataRow`
   - Add `GenreTagView` to detailed/hero modes
   - Add author `NavigationLink` with chevron
4. Update `WorkDetailView` for consistency
5. Add unit tests for new components
6. Fix Issue #144 (comma in year)
7. Implement Issue #145 (author navigation)
8. Resolve Issue #146 (genre display)

### Phase 2: Future Enhancements (Backlog)
- Extract `AuthorLinkButton` component if pattern repeats
- Build dedicated `AuthorBibliographyView` (validate demand first)
- Genre tag overflow handling (horizontal scroll)
- Additional metadata rows (publisher, pages, ISBN)

## File Structure

```
BooksTrackerPackage/Sources/BooksTrackerFeature/
├── Components/
│   ├── BookMetadataRow.swift       [NEW]
│   └── GenreTagView.swift          [NEW]
├── iOS26AdaptiveBookCard.swift     [MODIFIED]
└── WorkDetailView.swift            [MODIFIED]
```

## Success Metrics

### Immediate (v3.1.0)
- ✅ Issue #144 closed: Year displays as "📅 2017" (no comma)
- ✅ Issue #145 closed: Author name navigates to search
- ✅ Issue #146 closed: Genres visible in detailed/hero cards
- ✅ Zero new accessibility violations
- ✅ Zero new SwiftUI/Swift 6.2 warnings

### Future (v3.2.0+)
- User engagement with author navigation (analytics)
- Feature request volume for dedicated author bibliography view
- Genre tag discovery (how often users notice/use tags)

## Risk Mitigation

### Identified Risks
1. **Component Over-Abstraction:** Mitigated by limiting to 2 components initially
2. **Author Search Accuracy:** Mitigated by showing "Results for [Name]" header
3. **Empty Genre Data:** Mitigated by graceful `EmptyView()` fallback
4. **Navigation Depth:** Inherent iOS pattern, users familiar with back button

### Rollback Plan
- Changes are additive (new components, not refactoring)
- Can revert to inline metadata display if issues arise
- Feature flags: Could gate author navigation behind setting

## Consensus Analysis Summary

### Google Pro (Supportive) - 9/10 Confidence
**Strengths:**
- Excellent architecture with component reusability
- Strong iOS 26 HIG alignment (progressive disclosure)
- Low-moderate implementation complexity
- Long-term technical debt reduction

**Suggested Refinements:**
- Accessibility labels for icons ✅ Incorporated
- Genre tag overflow handling ✅ Deferred to Phase 2

### Critical Analysis (Devil's Advocate)
**Concerns Raised:**
- Risk of over-engineering simple fixes
- Edge cases: empty data, ambiguous authors, navigation depth
- Testing burden for component variations

**Mitigation:**
- Reduced scope: No `AuthorLinkButton` or `AuthorBibliographyView` in Phase 1
- Explicit edge case handling documented
- Pragmatic testing strategy (defer some tests to Phase 2)

### Final Recommendation
**Proceed with balanced approach:** Build high-value reusable components (`BookMetadataRow`, `GenreTagView`) while keeping author navigation simple (inline `NavigationLink`). Validate user demand before building dedicated `AuthorBibliographyView`.

---

## References
- [iOS 26 HIG - Progressive Disclosure](https://developer.apple.com/design/human-interface-guidelines/ios/app-architecture/progressive-disclosure/)
- [WCAG 2.1 AA Contrast Requirements](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
- [Swift 6.2 Concurrency Guide](../CONCURRENCY_GUIDE.md)
- [BooksTrack Architecture](../../CLAUDE.md)

## Approval
**Approved by:** Consensus (Pro 9/10 + Critical Analysis)
**Date:** 2025-10-27
**Next Step:** Worktree setup + implementation planning
