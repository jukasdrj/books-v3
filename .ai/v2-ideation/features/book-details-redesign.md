# Feature Spec: Book Details View Redesign

**Feature:** Modular Book Details Dashboard
**Phase:** 1-2 (UI in Phase 1, Advanced visualizations in Phase 2)
**Priority:** HIGH
**Status:** Design Phase

---

## Problem Statement

The current book details view uses a traditional "staircase" list layout (vertical list of facts) which:
- Creates visual clutter with dense metadata
- Fails to highlight important information
- Doesn't effectively communicate diversity data
- Lacks interactivity and engagement
- Doesn't scale well with richer v2 metadata

**User Feedback:**
- "Too much text, hard to scan"
- "I want to see what makes this book unique at a glance"
- "The diversity stats should be more visual"
- "Goodreads layout is boring and cluttered"

---

## Solution: "Bento Box" Modular Dashboard

Transform the book details view from a static list into an interactive, modular dashboard inspired by StoryGraph and LibraryThing's best practices.

### Core Principles

1. **Visual Hierarchy:** Most important info surfaced first with visual prominence
2. **Modularity:** Different data types in dedicated, scannable modules
3. **Progressive Disclosure:** Hide complexity, reveal on demand
4. **Data Visualization:** Charts and badges over text lists
5. **Contextual Actions:** Actions appear when relevant (e.g., "Complete the graph" when data missing)

---

## Design Specifications

### 1. Header: Immersive Context

**Current State:**
```
┌─────────────────────────┐
│   [Cover Image]         │
│                         │
│   Book Title            │
│   by Author Name        │
│                         │
│   [Start Reading]       │
└─────────────────────────┘
```

**New Design: Immersive Hero**
```
┌───────────────────────────────────────┐
│                                       │
│  [Blurred cover art background]      │
│                                       │
│    The Name of the Wind               │
│    by Patrick Rothfuss                │
│                                       │
│  ┌─────┬─────┬─────┬─────┬─────┐    │
│  │350pg│Fant.│1998 │4.5★ │Own  │    │
│  └─────┴─────┴─────┴─────┴─────┘    │
│                                       │
└───────────────────────────────────────┘
         ┌─────────────────────┐
         │  ▶ Start Reading    │
         └─────────────────────┘
    (Floating, persistent button)
```

**Implementation:**
```swift
struct ImmersivedHeaderView: View {
    let work: Work
    let entry: UserLibraryEntry?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Blurred cover background
            AsyncImage(url: work.coverImageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 20)
                    .overlay(Color.black.opacity(0.4))
            } placeholder: {
                Color.gray
            }
            .frame(height: 300)
            .clipped()

            VStack(spacing: 16) {
                // Title & Author
                VStack(spacing: 4) {
                    Text(work.title)
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("by \(work.primaryAuthor?.name ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }

                // Quick Facts Pills (Horizontal Scroll)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickFactPill(icon: "book.pages", text: "\(work.pageCount ?? 0) pages")
                        QuickFactPill(icon: "tag", text: work.primaryGenre ?? "Fiction")
                        QuickFactPill(icon: "calendar", text: work.publicationYear)
                        QuickFactPill(icon: "star.fill", text: String(format: "%.1f★", work.averageRating))
                        if entry?.isOwned == true {
                            QuickFactPill(icon: "checkmark.circle", text: "Owned", color: .green)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

struct QuickFactPill: View {
    let icon: String
    let text: String
    var color: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
```

---

### 2. Bento Box Grid: Modular Data Blocks

**Layout Pattern:**
```
┌─────────────┬─────────────┐
│  Module 1   │  Module 2   │
│  (DNA)      │  (Diversity)│
├─────────────┴─────────────┤
│  Module 3                 │
│  (Reading Progress)       │
├─────────────┬─────────────┤
│  Module 4   │  Module 5   │
│  (Stats)    │  (Tags)     │
└─────────────┴─────────────┘
```

**Implementation:**
```swift
struct BentoBoxLayout: View {
    let work: Work
    let entry: UserLibraryEntry?

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            // Row 1: DNA + Diversity
            DNABlock(work: work)
            DiversityBlock(work: work)

            // Row 2: Reading Progress (full width)
            ReadingProgressBlock(entry: entry)
                .gridCellColumns(2)

            // Row 3: Stats + Tags
            StatsBlock(work: work)
            TagsBlock(work: work)
        }
        .padding()
    }
}
```

---

### 3. Module 1: "DNA" Block (Metadata)

**Purpose:** Essential bibliographic metadata in scannable format

**Design:**
```
┌─────────────────────────┐
│  📖 DNA                 │
├─────────────────────────┤
│  Published: 1998        │
│  Original: 1998 (EN)    │
│  Series: Kingkiller #1  │
│  Publisher: DAW Books   │
│                         │
│  [Technical Details ▼]  │
└─────────────────────────┘
```

**Expandable Section:**
```
┌─────────────────────────┐
│  Technical Details      │
├─────────────────────────┤
│  ISBN-10: 0756404746    │
│  ISBN-13: 978-0756...   │
│  Format: Hardcover      │
│  Language: English      │
│  Pages: 662             │
└─────────────────────────┘
```

**Implementation:**
```swift
struct DNABlock: View {
    let work: Work
    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "book.closed")
                    .foregroundColor(.blue)
                Text("DNA")
                    .font(.headline)
            }

            Divider()

            // Essential metadata
            MetadataRow(label: "Published", value: work.publicationYear)
            if let original = work.originalPublicationYear {
                MetadataRow(label: "Original", value: "\(original) (\(work.originalLanguage ?? ""))")
            }
            if let series = work.seriesInfo {
                MetadataRow(label: "Series", value: "\(series.name) #\(series.position)")
            }
            MetadataRow(label: "Publisher", value: work.publisher ?? "Unknown")

            // Expandable technical details
            Button(action: { showTechnicalDetails.toggle() }) {
                HStack {
                    Text("Technical Details")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
            }

            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: 4) {
                    MetadataRow(label: "ISBN-13", value: work.isbn13 ?? "N/A", font: .caption)
                    MetadataRow(label: "Format", value: work.format ?? "N/A", font: .caption)
                    MetadataRow(label: "Language", value: work.language ?? "N/A", font: .caption)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    var font: Font = .subheadline

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(font)
                .foregroundColor(.secondary)
            Text(value)
                .font(font.weight(.medium))
            Spacer()
        }
    }
}
```

---

### 4. Module 2: Diversity Block with Visualization

**Purpose:** Transform diversity data from text lists into visual insights

#### Design 1: Representation Radar (Spider Chart)

**Concept:**
```
        Cultural
            ▲
            │╱ ╲
   Gender ─┼─── Translation
            │╲ ╱
            ▼
         Queer Rep
```

**Implementation:**
```swift
struct DiversityBlock: View {
    let work: Work
    @State private var showDetailedBreakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.green)
                Text("Representation")
                    .font(.headline)
                Spacer()
                Button("Complete") {
                    // Trigger diversity data entry
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            Divider()

            // Radar Chart
            RepresentationRadarChart(work: work)
                .frame(height: 120)

            // Identity Badges
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if work.isOwnVoices {
                        IdentityBadge(text: "Own Voices", color: .purple)
                    }
                    if let cultural = work.culturalSetting {
                        IdentityBadge(text: cultural, color: .orange)
                    }
                    if work.hasQueerRep {
                        IdentityBadge(text: "LGBTQ+", color: .rainbow)
                    }
                    if work.hasNeurodiversity {
                        IdentityBadge(text: "Neurodivergent", color: .blue)
                    }
                }
            }

            // Detailed breakdown (tap to expand)
            Button(action: { showDetailedBreakdown.toggle() }) {
                HStack {
                    Text("View Breakdown")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showDetailedBreakdown ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
            }

            if showDetailedBreakdown {
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Author", value: work.authorDemographics)
                    DetailRow(label: "Characters", value: work.characterDemographics)
                    DetailRow(label: "Setting", value: work.culturalSetting)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct RepresentationRadarChart: View {
    let work: Work

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 20

            ZStack {
                // Background grid (5 concentric circles)
                ForEach(1..<6) { i in
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        .frame(width: radius * 2 * CGFloat(i) / 5,
                               height: radius * 2 * CGFloat(i) / 5)
                }

                // Axes
                ForEach(0..<5) { i in
                    Path { path in
                        let angle = Double(i) * 2 * .pi / 5 - .pi / 2
                        let point = CGPoint(
                            x: center.x + radius * cos(angle),
                            y: center.y + radius * sin(angle)
                        )
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                }

                // Data polygon
                Path { path in
                    let values = work.diversityRadarValues // [0-1] for each axis
                    guard !values.isEmpty else { return }

                    for (index, value) in values.enumerated() {
                        let angle = Double(index) * 2 * .pi / 5 - .pi / 2
                        let point = CGPoint(
                            x: center.x + radius * value * cos(angle),
                            y: center.y + radius * value * sin(angle)
                        )
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    path.closeSubpath()
                }
                .fill(Color.green.opacity(0.3))
                .overlay(
                    Path { path in
                        let values = work.diversityRadarValues
                        guard !values.isEmpty else { return }

                        for (index, value) in values.enumerated() {
                            let angle = Double(index) * 2 * .pi / 5 - .pi / 2
                            let point = CGPoint(
                                x: center.x + radius * value * cos(angle),
                                y: center.y + radius * value * sin(angle)
                            )
                            if index == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                        path.closeSubpath()
                    }
                    .stroke(Color.green, lineWidth: 2)
                )

                // Axis labels
                Text("Cultural")
                    .font(.caption2)
                    .position(x: center.x, y: 10)
                Text("Gender")
                    .font(.caption2)
                    .position(x: 20, y: center.y)
                Text("Translation")
                    .font(.caption2)
                    .position(x: geometry.size.width - 30, y: center.y)
                // ... more labels
            }
        }
    }
}

struct IdentityBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
```

---

### 5. Progressive Profiling: "Complete the Graph"

**Problem:** Asking users to fill out complex forms upfront creates friction

**Solution:** Trigger-based prompts that appear contextually

#### Trigger 1: After Reading Session

```
┌────────────────────────────────────┐
│  Great session! 45 minutes         │
│                                    │
│  📊 Help us improve your insights  │
│                                    │
│  We're missing cultural context    │
│  for this author.                  │
│                                    │
│  Do you know their heritage?       │
│                                    │
│  ┌────┬────┬────┬────┬────────┐  │
│  │LATM│S.AS│Indig│E.AS│ Skip  │  │
│  └────┴────┴────┴────┴────────┘  │
│                                    │
│  [Submit]                          │
└────────────────────────────────────┘
```

**Implementation:**
```swift
struct PostSessionPrompt: View {
    let work: Work
    @State private var selectedHeritage: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Help us improve your insights")
                .font(.title3.bold())

            Text("We're missing cultural context for this author.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Do you know their heritage?")
                .font(.headline)
                .padding(.top)

            // Multiple choice pills
            FlowLayout(spacing: 8) {
                ForEach(heritageOptions, id: \.self) { option in
                    Button(action: { selectedHeritage = option }) {
                        Text(option)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedHeritage == option ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedHeritage == option ? .white : .primary)
                            .cornerRadius(8)
                    }
                }

                Button("Skip") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Button("Submit") {
                // Save contribution
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedHeritage == nil)
        }
        .padding()
    }

    private let heritageOptions = [
        "Latin American", "South Asian", "Indigenous",
        "East Asian", "African", "Caribbean",
        "Middle Eastern", "European"
    ]
}
```

#### Gamification: Progress Ring

```swift
struct CompletionRing: View {
    let completion: Double // 0.0 - 1.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)

            Circle()
                .trim(from: 0, to: completion)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .green]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(completion * 100))%")
                .font(.caption.bold())
        }
        .frame(width: 50, height: 50)
    }
}

// Usage in book cover thumbnail
struct BookCoverWithCompletion: View {
    let work: Work

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: work.coverImageURL) { image in
                image.resizable()
            } placeholder: {
                Color.gray
            }
            .aspectRatio(2/3, contentMode: .fit)
            .cornerRadius(8)

            // Completion ring overlay
            CompletionRing(completion: work.metadataCompletion)
                .padding(4)
        }
    }
}
```

---

### 6. Crowdsourced Verification

**Problem:** Automated scraped data may be inaccurate

**Solution:** Present data as questions for user verification

```
┌────────────────────────────────────┐
│  🤔 Quick Question                 │
│                                    │
│  Is this book set in Nigeria?      │
│                                    │
│  ┌──────────┐  ┌──────────┐       │
│  │   Yes    │  │    No    │       │
│  └──────────┘  └──────────┘       │
│                                    │
│  [Not Sure]                        │
└────────────────────────────────────┘
```

**Implementation:**
```swift
struct VerificationPrompt: View {
    let question: String
    let onVerify: (Bool?) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Quick Question")
                .font(.headline)

            Text(question)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Yes") {
                    onVerify(true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("No") {
                    onVerify(false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Button("Not Sure") {
                onVerify(nil)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 8)
    }
}
```

---

## Implementation Roadmap

### Phase 1: Foundation (Sprint 3-4)
- [ ] Implement Bento Box grid layout
- [ ] Create modular card components (DNA, Stats, Tags)
- [ ] Add immersive header with blurred cover
- [ ] Implement expandable sections

**Estimated:** 2 sprints

### Phase 2: Visualization (Sprint 5-6)
- [ ] Implement Representation Radar Chart
- [ ] Add identity badges
- [ ] Create completion ring overlay
- [ ] Build progressive profiling system

**Estimated:** 2 sprints

### Phase 3: Gamification (Sprint 7)
- [ ] Add post-session prompts
- [ ] Implement curator badge system
- [ ] Create verification flow
- [ ] Build contribution tracking

**Estimated:** 1 sprint

---

## Success Metrics

### User Engagement
- [ ] 80%+ users interact with at least 3 different modules
- [ ] 50%+ users expand "Technical Details" at least once
- [ ] 60%+ completion rate on progressive profiling prompts

### Data Quality
- [ ] 70%+ books have complete diversity radar data
- [ ] 90%+ user verification accuracy on scraped data
- [ ] 40%+ users become "Curators" (5+ contributions)

### Performance
- [ ] <100ms time to interactive for book details view
- [ ] Smooth 60fps scrolling through Bento grid
- [ ] <50ms radar chart render time

---

## Technical Considerations

### SwiftUI Implementation
- Use `LazyVGrid` for Bento layout
- Custom `Canvas` for radar chart drawing
- `@State` and `@Published` for expandable sections
- Async image loading with placeholders

### Accessibility
- VoiceOver descriptions for all visual charts
- Semantic labels for modules ("DNA section", "Diversity data")
- Support for Dynamic Type
- High contrast mode support

### Data Model Extensions

```swift
extension Work {
    // Diversity radar values (0.0 - 1.0)
    var diversityRadarValues: [Double] {
        [
            culturalRepresentationScore,
            genderDiversityScore,
            translationScore,
            queerRepresentationScore,
            neurodiversityScore
        ]
    }

    // Metadata completion (0.0 - 1.0)
    var metadataCompletion: Double {
        let fields: [Any?] = [
            isbn13,
            publisher,
            seriesInfo,
            originalPublicationYear,
            culturalSetting,
            authorDemographics,
            translator
        ]
        let filled = fields.compactMap { $0 }.count
        return Double(filled) / Double(fields.count)
    }

    // Identity flags
    var isOwnVoices: Bool { /* check if author identity matches character rep */ }
    var hasQueerRep: Bool { /* check diversity data */ }
    var hasNeurodiversity: Bool { /* check character tags */ }
}
```

---

## References

### Apple Resources
- **WWDC22: Explore media metadata publishing and playback interactions**
  - https://developer.apple.com/videos/play/wwdc2022/110384/
  - Best practices for metadata display on iOS
  - Hierarchical information architecture
  - Interactive media presentation patterns

### Design Inspiration
- **StoryGraph:** Modular stats cards, mood tracking visualization
- **LibraryThing:** Tag clouds, member recommendations
- **Literal:** Beautiful cover-based navigation, social reading cards

### Accessibility Standards
- **WCAG 2.1 AA:** Color contrast (4.5:1 minimum)
- **VoiceOver:** Semantic labeling for charts and visualizations
- **Dynamic Type:** Support for larger text sizes

---

## Detailed Visual Specifications

### Bento Box Module Breakdown (2x2 Grid)

| Row | Column 1 (Left: Action & Flow - Wide) | Column 2 (Right: Context & Status - Compact) |
|-----|--------------------------------------|---------------------------------------------|
| **Top** | **Reading Progress / Timer** | **Reading Habits & Pace** |
| | Large progress bar (theme color) + Start/Stop button | Small icon + metrics |
| | Current Page / Total Pages; Session elapsed time | `Avg. Pace: 30 pgs/hr`, `Streak: 7 Days` |
| **Bottom** | **Diversity & Representation** | **User Profile / Annotations** |
| | Representation Radar (preview) + "Diverse Voices %" | Annotation journal link + Rating stars |
| | `42% Diverse` score; preview: *Cultural Origin: Africa* | User rating, "Notes" link |

**Visual Hierarchy:**
- **Top-left (largest):** Primary action (reading progress/timer) - most interactive
- **Top-right:** Passive metrics - glanceable insights
- **Bottom-left:** Diversity visualization - educational/engaging
- **Bottom-right:** User-generated content - personal connection

---

### Representation Radar: Detailed Specification

#### Chart Structure

**Type:** 5-7 axis spider/radar chart
**Purpose:** Show balance across representation dimensions
**Visual State:** Full outline (100% target) overlaid with actual score (filled area)

#### Axis Definitions

| Axis # | Label | Data Source | Score Calculation | Interactive Element |
|--------|-------|-------------|-------------------|---------------------|
| **1** | Cultural Origin | `Author.culturalRegion` | 100% if non-Western/European, 0% if missing | `+` icon if missing |
| **2** | Gender Identity | `Author.gender` | 100% if non-male, 50% if data present but male, 0% if missing | `+` icon if missing |
| **3** | Translation | `Work.originalLanguage` | 100% if translated, 0% if originally English or missing | `+` icon if missing |
| **4** | Own Voices | User flag | 100% if author identity matches subject matter, 0% if not/missing | `+` icon prompts user verification |
| **5** | Accessibility | Tags (`Work.tags`) | 100% if has accessibility tags (dyslexia-friendly, audiobook), 0% if none | `+` icon to add tags |
| **6** (Optional) | Marginalized Voices | `Author.marginalizedIdentities` | 100% if author from marginalized community, 0% if not/missing | `+` icon if missing |
| **7** (Optional) | Niche Representation | Character/theme tags | 100% if has underrepresented themes, 0% if mainstream/missing | `+` icon to add themes |

#### Visual States

**State 1: Complete Data (Ideal)**
```
        Cultural (95%)
            ▲
        ╱───┼───╲
       ╱    │    ╲
Gender ─────┼───── Translation
 (100%) │    │    │ (0%)
       ╲    │    ╱
        ╲───┼───╱
            ▼
       Own Voices (100%)

Overall: 73% Diverse
```
- **Filled area:** Solid green with 30% opacity
- **Border:** Solid green 2pt stroke
- **Background grid:** 5 concentric circles (20%, 40%, 60%, 80%, 100%)

**State 2: Missing Data ("Ghost" State)**
```
        Cultural (?)
            ▲ +
        ╱⋯⋯⋯┼⋯⋯⋯╲
       ╱     │     ╲
Gender ─────┼───── Translation
 (100%) │   │ +   │ (?)
       ╲     │     ╱
        ╲⋯⋯⋯┼⋯⋯⋯╱
            ▼
       Own Voices (100%)

Overall: 67% (33% missing data)
```
- **Dashed axis lines:** Where data is missing
- **`+` icon:** Tappable, positioned at end of dashed axis
- **Overall score:** Shows % with caveat "33% missing data"

**State 3: Interactive (User taps `+`)**
```
┌────────────────────────────────────┐
│  📊 Complete the Graph             │
│                                    │
│  What is this author's cultural    │
│  heritage?                         │
│                                    │
│  ┌────┬────┬────┬────┬────┐      │
│  │LATM│S.AS│Indig│E.AS│Afr │      │
│  └────┴────┴────┴────┴────┘      │
│                                    │
│  [Skip] [Submit]                   │
└────────────────────────────────────┘
```
- **Modal/sheet:** Appears over chart
- **Multiple choice:** Tap to select, then submit
- **Immediate update:** Chart animates to show new data

#### Color Palette

**Diversity Score Ranges:**
- **90-100%:** Deep Green (#2ECC71) - "Highly Diverse"
- **70-89%:** Light Green (#52DE97) - "Diverse"
- **50-69%:** Yellow (#F39C12) - "Moderate"
- **30-49%:** Orange (#E67E22) - "Limited"
- **0-29%:** Red (#E74C3C) - "Not Diverse"

**Missing Data:**
- Dashed lines: Gray (#95A5A6) with 50% opacity
- `+` icon: Blue (#3498DB) - actionable color

#### Animation

**On Data Update:**
1. Chart smoothly morphs from old shape to new (0.3s ease-in-out)
2. Overall score counter animates from old to new value (0.5s)
3. Newly filled axis pulses once (highlight effect, 0.2s)

**On First Load:**
1. Axes draw outward from center (0.4s, staggered by 0.1s per axis)
2. Data polygon fills inward (0.3s delay, then 0.4s fill)
3. Overall score counts up from 0 (0.5s delay, then 0.5s count)

---

### Progressive Profiling: Visual Flow

#### Trigger Points

**Post-Reading Session:**
```
Session Complete
       ↓
Check work.metadataCompletion
       ↓
If < 80% complete
       ↓
Show Progressive Prompt
       ↓
User selects answer
       ↓
Update Work model
       ↓
Animate radar chart
```

**On Book Detail View Load:**
```
View appears
       ↓
Check radar chart for missing axes
       ↓
Display ghost state with + icons
       ↓
User taps +
       ↓
Show contextual prompt
       ↓
User contributes data
       ↓
Immediately update chart
```

#### Prompt UI Patterns

**Pattern 1: Multiple Choice Pills (Cultural Heritage)**
```swift
FlowLayout {
    ForEach(options) { option in
        SelectablePill(
            text: option,
            isSelected: selection == option,
            color: .blue
        )
    }
}
```
- Wraps to multiple lines if needed
- Selected pill fills with color
- Haptic feedback on selection

**Pattern 2: Binary Choice (Verification)**
```swift
HStack(spacing: 16) {
    BigButton(text: "Yes", color: .green, icon: "checkmark")
    BigButton(text: "No", color: .red, icon: "xmark")
}
```
- Large touch targets (60pt height)
- Clear visual distinction
- Icon reinforces choice

**Pattern 3: Free Text (Optional Details)**
```swift
VStack {
    TextField("Add details (optional)", text: $details)
        .textFieldStyle(.roundedBorder)
    Text("Help other readers understand the representation")
        .font(.caption)
        .foregroundColor(.secondary)
}
```
- Always optional, never required
- Helper text explains value

---

### Gamification: Progress Ring Detail

#### Visual Specification

**Position:** Overlays top-right corner of book cover
**Size:** 44pt diameter (large enough to see easily)
**Ring Width:** 4pt stroke

**States:**

| Completion | Ring Color | Text Color | Badge |
|-----------|-----------|------------|-------|
| 0-25% | Red gradient | White | None |
| 26-50% | Orange gradient | White | None |
| 51-75% | Yellow gradient | White | None |
| 76-99% | Green gradient | White | "Almost!" badge |
| 100% | Gold gradient | White | "Complete!" badge |

**Animation on Progress:**
- Ring fills clockwise from top (12 o'clock position)
- Percentage counter counts up over 0.5s
- When reaching 100%, brief confetti animation

**Tap Interaction:**
```
User taps ring
      ↓
Sheet appears: "Complete Your Book"
      ↓
Shows checklist:
☑ Author demographics
☑ Cultural setting
☐ Translation info
☐ Own Voices flag
☐ Accessibility tags
      ↓
User can tap any incomplete item
      ↓
Opens contextual prompt for that data
```

---

### Accessibility Considerations

#### VoiceOver Labels

**Radar Chart:**
```swift
.accessibilityLabel("Diversity representation chart")
.accessibilityValue("Overall diversity score: 73%. Cultural representation: 95%. Gender diversity: 100%. Translation: 0%. Own Voices: 100%.")
.accessibilityHint("Double tap to view detailed breakdown or contribute missing data")
```

**Missing Data Axis:**
```swift
.accessibilityLabel("Cultural representation: data missing")
.accessibilityHint("Double tap to provide information about the author's cultural heritage")
```

**Progress Ring:**
```swift
.accessibilityLabel("Metadata completion")
.accessibilityValue("\(Int(completion * 100))% complete")
.accessibilityHint("Double tap to view what information is missing")
```

#### Dynamic Type Support

**Minimum Sizes:**
- Chart labels: Support up to accessibility size 5 (36pt)
- Pills: Expand height to accommodate larger text
- Radar chart: Maintain minimum 200pt diameter regardless of text size

#### Color Blindness

**Deuteranopia/Protanopia (Red-Green):**
- Use patterns in addition to color (diagonal lines for red areas)
- Ensure sufficient luminosity contrast (not just hue)

**Tritanopia (Blue-Yellow):**
- Use blue-orange palette instead of green-red for diversity scores

---

## Implementation Priority Matrix

| Feature Component | Phase | Sprint | Complexity | Impact | Priority |
|------------------|-------|--------|-----------|--------|----------|
| Bento Grid Layout | 1 | 3 | Medium | High | CRITICAL |
| Immersive Header | 1 | 3 | Low | High | CRITICAL |
| DNA Block (Metadata) | 1 | 3 | Low | Medium | HIGH |
| Reading Progress Block | 1 | 1-2 | Low | High | CRITICAL (already in Sprint 1) |
| Diversity Block (Basic) | 1 | 4 | Medium | High | CRITICAL |
| Representation Radar | 2 | 5 | High | High | CRITICAL |
| Progressive Prompts | 2 | 6 | Medium | High | HIGH |
| Progress Ring | 2 | 6 | Low | Medium | MEDIUM |
| Ghost State + Icons | 2 | 5 | Medium | High | HIGH |
| Verification Flow | 2 | 7 | Medium | Medium | MEDIUM |
| Animations | 3 | 8+ | Medium | Low | LOW |

---

## Open Questions

1. **Radar Chart Axes:** Fixed 5-7 axes or user-configurable? (Recommend fixed to start, iterate later)
2. **Gamification Rewards:** What tangible benefits for "Curator" badges? (Profile flair, priority in Phase 3 social features)
3. **Data Verification:** Confidence score for scraped vs. user-verified? (Yes, show as badge: "Community Verified")
4. **Mobile Performance:** Pre-render radar charts? (Generate on-demand, cache rendered image for 24hrs)
5. **Data Privacy:** Should radar chart export be anonymous? (Yes, no PII in chart exports)

---

## Summary: UI Transformation Comparison

| Aspect | Current (v1) | New (v2) |
|--------|-------------|----------|
| **Layout** | Vertical list ("staircase") | Bento Box (modular 2x2 grid) |
| **Diversity Data** | Text list or hidden | Radar chart + identity badges |
| **Missing Data** | Empty fields, no call-to-action | "Ghost" state with `+` icons |
| **User Contribution** | Edit form (friction) | Progressive prompts (contextual) |
| **Metadata** | Flat list | Expandable DNA block |
| **Visual Hierarchy** | Equal weight to all data | Clear primary action (timer) + supporting modules |
| **Engagement** | Passive viewing | Interactive (tap to contribute, expand, verify) |
| **Gamification** | None | Progress rings, curator badges |

**Net Effect:** Transforms book details from static reference card into interactive, data-rich dashboard that encourages engagement and contribution.

---

**Created:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**Status:** Design Phase - Detailed visual specs complete
**Next Review:** December 2025 (Sprint 3 planning)
**References:** WWDC22 Media Metadata session, StoryGraph UI patterns, LibraryThing tag clouds
