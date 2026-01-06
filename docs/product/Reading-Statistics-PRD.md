# Reading Statistics - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** iOS Developer
**Target Release:** v3.0.0+ (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Reading Statistics provides users with insights into their reading habits by tracking book completion, reading progress (current page), and reading status transitions (Wishlist → Owned → Reading → Read). Accessible via the Insights tab, this feature helps users visualize their reading journey, set goals, and stay motivated through quantifiable metrics.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Readers want to track their progress and celebrate achievements (finishing books, hitting yearly goals) but lack visibility into their reading habits. Common frustrations:
- "How many books did I read this year?" (no way to know)
- "When did I finish this book?" (no completion dates)
- "How much progress am I making?" (can't see current page across all books)

### Current Experience (Before Reading Statistics)

**How did users track reading before this feature?**

- **Manual tracking:** Spreadsheets, Goodreads exports, physical journals (tedious, error-prone)
- **No tracking:** Users guess completion counts ("I think I read 20 books last year?")
- **No motivation:** No visual feedback on progress (hard to stay motivated)

---

## Target Users

### Primary Persona

**Who benefits from Reading Statistics?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Goal-oriented readers, book collectors, tracking enthusiasts |
| **Usage Frequency** | Weekly (check progress), monthly (review stats) |
| **Tech Savvy** | All levels (simple UI, clear charts) |
| **Primary Goal** | Visualize reading progress, celebrate achievements, set goals |

**Example User Stories:**

> "As a **reader with a yearly goal of 50 books**, I want to **see how many books I've completed** so that I can **track progress toward my goal**."

> "As a **book collector with 200 books**, I want to **see how many I've read vs owned** so that I can **prioritize my reading backlog**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Feature Usage** | 50%+ users view Insights tab weekly | Analytics (Insights tab views) |
| **Real-Time Updates** | Stats update within 1s of status change | UI responsiveness instrumentation |
| **Accuracy** | 100% completion tracking (no missed dates) | Database integrity checks |
| **Engagement** | Users set more goals after viewing stats | Goal-setting event tracking (future) |

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: View Books Read This Year

**As a** reader tracking yearly goals
**I want to** see total books completed this year
**So that** I can measure progress toward my reading goal

**Acceptance Criteria:**
- [x] Given user marks book as "Read", when viewing Insights tab, then "Books Read This Year" counter increments
- [x] Given user sets completion date to 2025-10-15, when querying stats, then book counted in 2025 total
- [x] Given current date is January 1, when viewing stats, then previous year's count resets to 0 (new year)

#### User Story 2: Track Reading Status Distribution

**As a** book collector
**I want to** see breakdown of books by status (Wishlist, Owned, Reading, Read)
**So that** I can understand my library composition

**Acceptance Criteria:**
- [x] Given user has 50 books (10 wishlist, 15 owned, 5 reading, 20 read), when viewing Insights, then pie chart shows accurate distribution
- [x] Given user changes book from "Owned" to "Reading", when stats update, then "Owned" count decrements, "Reading" count increments
- [x] Given user taps pie chart segment, when action triggered, then filter Library tab to that status (future enhancement)

#### User Story 3: Monitor Current Reading Progress

**As a** user reading multiple books simultaneously
**I want to** see current page for all in-progress books
**So that** I can track which books need attention

**Acceptance Criteria:**
- [x] Given user has 3 books in "Reading" status, when viewing Insights, then current page shown for each (e.g., "Book A: 150/400 pages")
- [x] Given user updates current page to 200, when stats refresh, then new progress shown immediately
- [x] Given book has unknown page count, when viewing progress, then show current page only (e.g., "200 pages read")

#### User Story 4: Review Completion Dates

**As a** reader tracking reading history
**I want to** see when I finished each book
**So that** I can remember my reading timeline

**Acceptance Criteria:**
- [x] Given user marks book "Read", when completion date auto-set to today, then date stored in UserLibraryEntry
- [x] Given user manually changes completion date to 2025-09-15, when viewing book detail, then custom date shown
- [x] Given user views Insights, when browsing "Recently Completed" list, then books sorted by completion date (most recent first)

---

## Technical Implementation

### Architecture Overview

**Component Structure:**

```
InsightsView (Tab 4)
  ├─ Reading Stats Summary Card
  │   ├─ Books Read This Year: XX
  │   ├─ Total Books in Library: YY
  │   ├─ Currently Reading: Z
  │   └─ Average Pages Per Book: AAA
  ├─ Status Distribution Pie Chart
  │   ├─ Wishlist: X%
  │   ├─ Owned: Y%
  │   ├─ Reading: Z%
  │   └─ Read: W%
  ├─ Current Reading Progress List
  │   ├─ Book A: 150/400 pages (37%)
  │   ├─ Book B: 75/250 pages (30%)
  │   └─ Book C: 320/500 pages (64%)
  └─ Recently Completed List
      ├─ Book X - Completed Oct 30, 2025
      ├─ Book Y - Completed Oct 25, 2025
      └─ Book Z - Completed Oct 20, 2025
```

**Data Sources:**

- **UserLibraryEntry** (SwiftData model)
  - `status: ReadingStatus` (wishlist, toRead, reading, read)
  - `currentPage: Int?` (progress tracking)
  - `completionDate: Date?` (when marked "Read")
  - `personalRating: Int?` (1-5 stars, for future stats)

**Aggregation Logic:**

```swift
// Books read this year
let currentYear = Calendar.current.component(.year, from: Date())
let readThisYear = try modelContext.fetch(
    FetchDescriptor<UserLibraryEntry>(
        predicate: #Predicate {
            $0.status == .read &&
            $0.completionDate != nil &&
            Calendar.current.component(.year, from: $0.completionDate!) == currentYear
        }
    )
).count

// Status distribution
let allEntries = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let distribution = Dictionary(grouping: allEntries, by: { $0.status })
let wishlistCount = distribution[.wishlist]?.count ?? 0
let ownedCount = distribution[.toRead]?.count ?? 0
let readingCount = distribution[.reading]?.count ?? 0
let readCount = distribution[.read]?.count ?? 0
```

---

## Decision Log

### October 2025 Decisions

#### **Decision:** Manual Status Updates (Not Automatic Completion Detection)

**Context:** Should BooksTrack automatically mark books "Read" when user reaches last page?

**Options Considered:**
1. Automatic completion (when currentPage == totalPages, set status to "Read")
2. Manual status updates (user explicitly marks book "Read")
3. Hybrid (suggest completion, user confirms)

**Decision:** Option 2 (Manual status updates)

**Rationale:**
- **User Control:** Some readers don't finish every page (skip epilogues, appendices)
- **Accuracy:** Automatic detection unreliable (page counts often wrong from APIs)
- **Simplicity:** No complex heuristics, clear user intent

**Tradeoffs:**
- Users might forget to mark books "Read" (acceptable, reading apps typically manual)

---

#### **Decision:** Completion Date Auto-Set to Today (With Manual Override)

**Context:** When user marks book "Read", what completion date to use?

**Options Considered:**
1. Always use today's date (simple, no user input)
2. Prompt user for date every time (tedious, friction)
3. Auto-set to today, allow manual edit (balance convenience and accuracy)

**Decision:** Option 3 (Auto-set to today, manual override available)

**Rationale:**
- **Common Case:** Most users finish book today, mark it immediately
- **Flexibility:** Power users can edit date if finished weeks ago
- **UX:** No blocking prompts, optional detail

**Tradeoffs:**
- Default date might be wrong if user marks book late (user can fix)

---

#### **Decision:** Current Page (Not Percentage) as Primary Progress Metric

**Context:** Should progress show "150/400 pages" or "37%"?

**Options Considered:**
1. Pages only (150/400)
2. Percentage only (37%)
3. Both (150/400 pages · 37%)

**Decision:** Option 3 (Both pages and percentage)

**Rationale:**
- **Pages:** Concrete, tangible (readers think in pages)
- **Percentage:** Easy to compare across books of different lengths
- **Both:** Maximum info, minimal space (one line)

**Tradeoffs:**
- Slightly more UI clutter (acceptable, not much text)

---

## UI Specification

### Insights Tab Layout

**Navigation:**
- Tab bar position: 4th tab (Library, Search, Shelf, **Insights**)
- Icon: Chart.bar.fill (SF Symbol)
- Title: "Insights"

**Screen Structure:**

```
┌─────────────────────────────────────┐
│  Insights                          │
├─────────────────────────────────────┤
│  📊 READING STATS                   │
│  ┌─────────────────────────────┐   │
│  │ Books Read This Year: 24    │   │
│  │ Total Books: 147            │   │
│  │ Currently Reading: 3        │   │
│  │ Average Pages: 352          │   │
│  └─────────────────────────────┘   │
│                                     │
│  📈 STATUS DISTRIBUTION             │
│  ┌─────────────────────────────┐   │
│  │     [Pie Chart]             │   │
│  │  Wishlist: 20 (14%)         │   │
│  │  Owned: 50 (34%)            │   │
│  │  Reading: 3 (2%)            │   │
│  │  Read: 74 (50%)             │   │
│  └─────────────────────────────┘   │
│                                     │
│  📖 CURRENTLY READING               │
│  ┌─────────────────────────────┐   │
│  │ The Three-Body Problem      │   │
│  │ 150/400 pages · 37%         │   │
│  │ [Progress Bar: 37%]         │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ Project Hail Mary           │   │
│  │ 75/250 pages · 30%          │   │
│  │ [Progress Bar: 30%]         │   │
│  └─────────────────────────────┘   │
│                                     │
│  ✅ RECENTLY COMPLETED              │
│  ┌─────────────────────────────┐   │
│  │ Dune                        │   │
│  │ Completed Oct 30, 2025      │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ Foundation                  │   │
│  │ Completed Oct 25, 2025      │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## Reading Status Lifecycle

### Status Transitions

**Standard Flow:**
```
Wishlist → Owned (toRead) → Reading → Read
```

**Skip Patterns (Valid):**
```
Wishlist → Reading (borrowed book, started immediately)
Wishlist → Read (finished before purchasing)
Owned → Read (skipped "Reading" status, binge-read)
```

**Status Definitions:**

| Status | Definition | User Intent |
|--------|-----------|-------------|
| **Wishlist** | Want to read, don't own yet | Discovery, shopping list |
| **Owned (toRead)** | Purchased/acquired, not started | Backlog, TBR pile |
| **Reading** | Currently reading | Active progress tracking |
| **Read** | Finished | Archive, statistics, reviews |

**Field Updates by Status:**

| Status | Auto-Set Fields | User-Editable Fields |
|--------|----------------|---------------------|
| Wishlist | status = .wishlist | edition (optional) |
| Owned | status = .toRead, edition | personalRating, notes |
| Reading | status = .reading | currentPage, edition |
| Read | status = .read, completionDate = today | completionDate, personalRating, notes |

---

## Implementation Files

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/InsightsView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/ReadingStatisticsService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/UserLibraryEntry.swift`

**SwiftData Model:**

```swift
@Model
public class UserLibraryEntry {
    public var status: ReadingStatus = .wishlist
    public var currentPage: Int? = nil
    public var completionDate: Date? = nil
    public var personalRating: Int? = nil  // 1-5 stars
    public var notes: String? = nil

    // Relationships
    public var work: Work?
    public var edition: Edition?
}

public enum ReadingStatus: String, Codable, CaseIterable {
    case wishlist
    case toRead  // "Owned" in UI
    case reading
    case read
}
```

---

## Aggregation Queries

### Books Read This Year

```swift
let currentYear = Calendar.current.component(.year, from: Date())
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate {
        $0.status == .read &&
        $0.completionDate != nil &&
        Calendar.current.component(.year, from: $0.completionDate!) == currentYear
    }
)
let readThisYear = try modelContext.fetch(descriptor).count
```

### Status Distribution

```swift
let allEntries = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let distribution = Dictionary(grouping: allEntries, by: { $0.status })
```

### Currently Reading with Progress

```swift
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.status == .reading },
    sortBy: [SortDescriptor(\.work?.title)]
)
let reading = try modelContext.fetch(descriptor)
for entry in reading {
    let progress = entry.currentPage ?? 0
    let total = entry.edition?.pageCount ?? 0
    let percentage = total > 0 ? (Double(progress) / Double(total)) * 100 : 0
    // Display: "\(progress)/\(total) pages · \(Int(percentage))%"
}
```

### Recently Completed

```swift
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.status == .read && $0.completionDate != nil },
    sortBy: [SortDescriptor(\.completionDate, order: .reverse)]
)
let recentlyCompleted = try modelContext.fetch(descriptor)
    .prefix(10)  // Show last 10 completed books
```

---

## Error Handling

### Edge Cases

| Scenario | Behavior | Rationale |
|----------|----------|-----------|
| Book marked "Read" without completion date | Auto-set to today | Most common case, reduce friction |
| Current page > total pages | Show currentPage only, no percentage | API page counts often wrong |
| Book with 0 pages (unknown) | Show "Page X" (no total) | Don't block progress tracking |
| Completion date in future | Allow (user might set reading goal) | Flexibility for planning |

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Reading Goals**
   - User sets "50 books this year" goal
   - Progress bar: "24/50 books (48%)"
   - Notifications: "You're on track!" or "Read 2 more this month to hit goal"

2. **Reading Streaks**
   - Track consecutive days with reading activity (currentPage updates)
   - Gamification: "7-day reading streak!"
   - Motivation for daily reading habit

3. **Average Reading Speed**
   - Calculate pages per day (total pages ÷ days elapsed)
   - Estimate time to finish current books
   - "At your pace, you'll finish Project Hail Mary in 5 days"

4. **Yearly Reading Report**
   - Auto-generated at year end (Dec 31)
   - "Your 2025 in Books" summary
   - Favorite genres, longest book, reading pace trends

5. **Genre Breakdown (Enhanced)**
   - Pie chart: "50% Science Fiction, 30% Fantasy, 20% Mystery"
   - Integration with Genre Normalization backend
   - Filter library by genre

6. **Completion Rate**
   - "You've read 74 of 147 books (50%)"
   - Identify backlog: "50 owned but unread books"
   - Suggestions: "Try reading 'The Hobbit' next (owned 6 months ago)"

---

## Testing Strategy

### Manual QA Scenarios

- [x] Add book, mark as "Read", verify "Books Read This Year" increments
- [x] Change completion date to last year, verify current year count decrements
- [x] Update current page for reading book, verify progress bar updates
- [x] Mark book "Read" without completion date, verify auto-set to today
- [x] View status distribution pie chart, verify percentages sum to 100%
- [x] Add book with unknown page count, verify progress shows "X pages read"

### Edge Case Testing

- [ ] Mark 100 books "Read" on same day, verify performance (< 1s to render stats)
- [ ] Set completion date to Jan 1, 2020, verify appears in "All Time" stats (not "This Year")
- [ ] Delete book marked "Read", verify stats update immediately

---

## Dependencies

**iOS:**
- SwiftData (UserLibraryEntry model with status, currentPage, completionDate)
- SwiftUI Charts (pie chart, progress bars - future enhancement)
- Calendar API (year filtering for "Books Read This Year")

---

## Success Criteria (Shipped)

- ✅ Books Read This Year counter accurate (real-time updates)
- ✅ Status distribution pie chart shows accurate percentages
- ✅ Current reading progress displays pages and percentage
- ✅ Recently completed list sorted by completion date (most recent first)
- ✅ Completion date auto-set to today when marking "Read"
- ✅ Stats update immediately when user changes status/progress (<1s)

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
**Documentation:** Referenced in `CLAUDE.md` under "Reading Status" and "Key Business Logic"
