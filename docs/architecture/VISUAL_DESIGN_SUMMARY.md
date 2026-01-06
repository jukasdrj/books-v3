# BooksTracker v2 - Visual Design Summary

**Created:** November 20, 2025
**Status:** Design Phase
**Purpose:** Quick reference for v2 visual design principles and key UI patterns

---

## Design Philosophy

### Core Principles

1. **Visual Hierarchy:** Most important information surfaced first
2. **Modularity:** Different data types in dedicated, scannable modules
3. **Progressive Disclosure:** Hide complexity, reveal on demand
4. **Data Visualization:** Charts and badges over text lists
5. **Contextual Actions:** Actions appear when relevant

### Transformation Goal

**From:** Static "staircase" list of facts (v1)
**To:** Interactive, modular dashboard (v2)

---

## Key Visual Patterns

### 1. Bento Box Layout

**Pattern:** Modular 2x2 grid for book details
**Inspired by:** StoryGraph, iOS Widget system

```
┌─────────────┬─────────────┐
│  Progress   │  Habits     │  ← Top row
│  (Primary)  │  (Metrics)  │
├─────────────┴─────────────┤
│  Representation Radar     │  ← Full width
├─────────────┬─────────────┤
│  DNA Block  │  Annots.    │  ← Bottom row
└─────────────┴─────────────┘
```

**Benefits:**
- Scannable at a glance
- Equal visual weight to different data types
- Responsive to different screen sizes

---

### 2. Representation Radar Chart

**Pattern:** 5-7 axis spider/radar chart for diversity visualization
**Purpose:** Transform text lists into visual insights

**Key States:**

| State | Description | Visual |
|-------|-------------|--------|
| Complete | All axes have data | Solid filled polygon, green |
| Ghost | Missing data | Dashed axes, `+` icons |
| Interactive | User taps `+` | Modal/sheet for data entry |

**Color Coding:**
- 90-100%: Deep Green - "Highly Diverse"
- 70-89%: Light Green - "Diverse"
- 50-69%: Yellow - "Moderate"
- 30-49%: Orange - "Limited"
- 0-29%: Red - "Not Diverse"

---

### 3. Progressive Profiling

**Pattern:** Contextual prompts for data entry (not upfront forms)
**Triggers:**
- After reading session completion
- When viewing book with missing metadata
- On tapping "ghost" state `+` icons

**UI Variants:**

| Prompt Type | Use Case | Example |
|-------------|----------|---------|
| Multiple Choice Pills | Cultural heritage, genre tags | `[LATM] [S.AS] [Indig] [Skip]` |
| Binary Choice | Verification questions | `[Yes ✓] [No ✗]` |
| Free Text (Optional) | Additional context | `"Add details (optional)"` |

---

### 4. Gamification Elements

#### Progress Ring
- **Position:** Top-right corner of book cover
- **Size:** 44pt diameter
- **States:** Color-coded by completion (red → gold)
- **Interaction:** Tap to see checklist of missing data

#### Curator Badges
- **Trigger:** 5+ data contributions
- **Display:** Profile badge, "Curator" flair
- **Future:** Priority in Phase 3 social features

---

## Component Library

### Reusable UI Components

#### 1. QuickFactPill
```swift
// Horizontal scrollable pills for key facts
QuickFactPill(icon: "book.pages", text: "350 pages")
```
**Usage:** Header, quick facts ribbon

#### 2. IdentityBadge
```swift
// Color-coded diversity badges
IdentityBadge(text: "Own Voices", color: .purple)
```
**Usage:** Diversity block, author details

#### 3. MetadataRow
```swift
// Label-value pair for metadata
MetadataRow(label: "Published", value: "1998")
```
**Usage:** DNA block, expandable sections

#### 4. CompletionRing
```swift
// Progress ring with percentage
CompletionRing(completion: 0.73) // 73%
```
**Usage:** Book cover overlay, metadata completion

#### 5. RepresentationRadarChart
```swift
// 5-7 axis radar chart for diversity
RepresentationRadarChart(work: work)
```
**Usage:** Diversity block, detailed stats view

---

## Sprint Allocation

### Phase 1: Foundation (Sprints 3-4)

**Sprint 3: Bento Box Layout**
- [ ] Implement modular grid system
- [ ] Create card components (DNA, Stats, Tags)
- [ ] Add immersive header with blurred cover
- [ ] Implement expandable sections

**Sprint 4: Basic Diversity UI**
- [ ] Create diversity block with text badges
- [ ] Add identity badge components
- [ ] Implement basic completion tracking
- [ ] Progressive disclosure for metadata

---

### Phase 2: Visualization (Sprints 5-6)

**Sprint 5: Representation Radar**
- [ ] Implement radar chart drawing (Canvas API)
- [ ] Add "ghost" state with `+` icons
- [ ] Create interactive tap handlers
- [ ] Implement smooth animations

**Sprint 6: Progressive Profiling**
- [ ] Build post-session prompt system
- [ ] Create multiple choice pill UI
- [ ] Add binary verification flow
- [ ] Implement completion ring overlay

---

### Phase 3: Polish (Sprints 7-8)

**Sprint 7: Gamification**
- [ ] Curator badge system
- [ ] Verification flow refinement
- [ ] Contribution tracking
- [ ] Achievement animations

**Sprint 8: Accessibility & Performance**
- [ ] VoiceOver labels for charts
- [ ] Dynamic Type support
- [ ] Color blindness accommodations
- [ ] Performance optimization (chart caching)

---

## Design System Reference

### Typography

| Element | Font | Weight | Size |
|---------|------|--------|------|
| Book Title | System | Bold | .title |
| Author Name | System | Regular | .subheadline |
| Section Header | System | Semibold | .headline |
| Metadata Label | System | Regular | .subheadline |
| Metadata Value | System | Medium | .subheadline |
| Quick Fact Pill | System | Medium | .caption |
| Chart Label | System | Regular | .caption2 |

### Color Palette

#### Diversity Scores
```swift
enum DiversityScore {
    case highlyDiverse  // #2ECC71 (Deep Green)
    case diverse        // #52DE97 (Light Green)
    case moderate       // #F39C12 (Yellow)
    case limited        // #E67E22 (Orange)
    case notDiverse     // #E74C3C (Red)
}
```

#### Identity Badges
```swift
enum IdentityBadgeColor {
    case ownVoices      // Purple
    case cultural       // Orange
    case queer          // Rainbow gradient
    case neurodivergent // Blue
}
```

#### UI Elements
```swift
enum UIColor {
    case actionable     // #3498DB (Blue) - for + icons
    case missingData    // #95A5A6 (Gray) - for dashed lines
    case success        // #2ECC71 (Green) - for completion
    case warning        // #F39C12 (Yellow) - for partial data
}
```

### Spacing

| Context | Spacing |
|---------|---------|
| Module padding | 16pt |
| Grid gap | 12pt |
| Section spacing | 24pt |
| Pill horizontal padding | 12pt |
| Pill vertical padding | 6pt |
| Card corner radius | 12pt |
| Pill corner radius | 16pt (fully rounded) |

### Shadows

```swift
// Card shadow (depth)
.shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

// Modal/sheet shadow (prominence)
.shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
```

---

## Animation Guidelines

### Timing Functions

| Animation Type | Duration | Easing |
|---------------|----------|--------|
| Chart morph | 0.3s | ease-in-out |
| Counter animation | 0.5s | ease-out |
| Pulse/highlight | 0.2s | ease-in-out |
| Sheet presentation | 0.4s | spring (dampingFraction: 0.8) |
| Ring fill | 0.5s | linear |

### Animation Sequences

**Radar Chart First Load:**
1. Axes draw outward (0.4s, staggered 0.1s)
2. Grid appears (0.2s fade-in)
3. Data polygon fills (0.4s after 0.3s delay)
4. Score counter counts up (0.5s after 0.5s delay)

**Data Update:**
1. Old polygon morphs to new (0.3s)
2. Score counter updates (0.5s)
3. Updated axis pulses (0.2s)

---

## Accessibility Specifications

### VoiceOver

**All visual charts must have:**
- Descriptive label (what it is)
- Current value (data summary)
- Hint (how to interact)

**Example:**
```swift
.accessibilityLabel("Diversity representation chart")
.accessibilityValue("Overall score 73%. Cultural 95%, Gender 100%, Translation 0%, Own Voices 100%")
.accessibilityHint("Double tap to view details or add missing data")
```

### Dynamic Type

**Support up to accessibility size 5 (36pt)**
- Minimum chart diameter: 200pt
- Pill height expands for larger text
- Labels remain readable at all sizes

### Color Blindness

**Accommodations:**
- Patterns + color (not just color alone)
- Sufficient luminosity contrast
- Alternative palettes for common types:
  - Deuteranopia/Protanopia: Patterns for red areas
  - Tritanopia: Blue-orange instead of green-red

---

## Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Time to interactive | <100ms | User perceives as instant |
| Radar chart render | <50ms | No perceptible lag |
| Smooth scrolling | 60fps | Fluid Bento grid navigation |
| Image loading | Progressive | Show placeholders immediately |
| Chart caching | 24hrs | Reduce repeated rendering |

---

## Design Resources

### Figma Files (Future)
- [ ] Component library
- [ ] Bento Box layouts (iPhone sizes)
- [ ] Radar chart states (complete, ghost, interactive)
- [ ] Animation timeline mockups

### Apple Resources
- [WWDC22: Media Metadata](https://developer.apple.com/videos/play/wwdc2022/110384/)
- [Human Interface Guidelines: Charts](https://developer.apple.com/design/human-interface-guidelines/charts)
- [SF Symbols 5](https://developer.apple.com/sf-symbols/) (for icons)

### Inspiration
- **StoryGraph:** Modular stats cards, mood tracking
- **LibraryThing:** Tag clouds, member recommendations
- **Literal:** Cover-based navigation, social cards
- **Goodreads (avoid):** Cluttered staircase layout

---

## Next Steps

### Week of Nov 25, 2025: User Research
- [ ] Show Bento Box layout mockups to beta users
- [ ] Test radar chart comprehension
- [ ] Validate progressive profiling approach
- [ ] Gather feedback on gamification

### Week of Dec 2, 2025: Sprint 3 Planning
- [ ] Finalize component specifications
- [ ] Create Figma mockups for all states
- [ ] Define SwiftUI view hierarchy
- [ ] Plan animation implementation

### Q1 2026: Phase 1 Implementation
- [ ] Sprint 3: Bento Box + DNA block
- [ ] Sprint 4: Basic diversity UI
- [ ] Performance testing with real data
- [ ] Accessibility audit

---

## Open Questions for Design Review

1. **Chart Complexity:** Is 5-7 axes too many? Start with 5 and expand?
2. **Mobile vs. iPad:** Should iPad use 3x2 grid instead of 2x2?
3. **Dark Mode:** Should radar chart colors adjust for dark mode?
4. **Export:** Should users be able to share radar chart as image?
5. **Localization:** Do axis labels translate well to other languages?

---

**Maintained by:** oooe (jukasdrj)
**Status:** Living document - updates with each design decision
**Last Updated:** November 20, 2025
**Next Review:** December 2025 (Sprint 3 kickoff)

---

## Quick Reference: UI Transformation

| v1 (Current) | v2 (Target) |
|--------------|-------------|
| Vertical list | Bento Box grid |
| Text metadata | Visual modules |
| No diversity viz | Radar chart |
| Empty fields | Ghost state + CTAs |
| Edit forms | Progressive prompts |
| Static reference | Interactive dashboard |

**See [`features/book-details-redesign.md`](features/book-details-redesign.md) for complete specifications.**
