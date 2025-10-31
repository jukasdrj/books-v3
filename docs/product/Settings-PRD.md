# Settings - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** iOS Developer
**Target Release:** v3.0.0+ (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

Settings provides users with app customization options (themes, AI provider selection, experimental features) accessible via a gear icon in the Library tab toolbar. Following iOS 26 HIG guidelines, Settings uses a sheet presentation rather than a dedicated tab, keeping the tab bar focused on core workflows (Library, Search, Shelf, Insights).

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Users want to personalize their app experience (visual themes, AI performance vs accuracy tradeoffs, beta features) but don't know where to find these options. Common frustrations:
- "How do I change the app theme?" (not discoverable)
- "Can I try experimental features?" (hidden)
- "Where do I reset my library?" (critical utility function)

### Current Experience (Before Settings)

**How did users access customization before this feature?**

- No theme selection (stuck with default blue)
- No AI provider choice (Gemini only, no alternatives)
- No feature flags (experimental features hidden from users)
- No Library Reset (had to reinstall app to clear data)

---

## Target Users

### Primary Persona

**Who uses Settings?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | All users (aesthetic customizers, power users, testers) |
| **Usage Frequency** | Low (setup once, occasional changes) |
| **Tech Savvy** | All levels (simple UI, clear labels) |
| **Primary Goal** | Customize app appearance and behavior |

**Example User Stories:**

> "As a **user who loves purple**, I want to **change the app theme to Cosmic Purple** so that **the app matches my aesthetic**."

> "As a **beta tester**, I want to **enable experimental features** so that I can **try new functionality before public release**."

> "As a **developer**, I want to **reset my library** so that I can **test CSV import with fresh data**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Discoverability** | 60%+ users find Settings within first week | Analytics (Settings screen views) |
| **Theme Adoption** | 40%+ users change default theme | Theme selection events |
| **Immediate Effect** | Theme changes apply without restart (0s) | UI responsiveness |
| **Feature Flags Respected** | 100% experimental features gated correctly | Code audit |

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Access Settings from Library Tab

**As a** user browsing my library
**I want to** access Settings via a toolbar button
**So that** I can customize the app without leaving my current screen

**Acceptance Criteria:**
- [x] Given user is on Library tab, when tapping gear icon in toolbar, then Settings sheet appears
- [x] Given Settings is open, when tapping "Done" button, then Settings dismisses
- [x] Given Settings is not a tab bar item, when user checks tab bar, then only 4 tabs visible (Library, Search, Shelf, Insights)

#### User Story 2: Change App Theme

**As a** user who wants visual customization
**I want to** select from 5 built-in themes
**So that** the app matches my personal style

**Acceptance Criteria:**
- [x] Given user opens Settings, when viewing "Appearance" section, then 5 theme options shown (Liquid Blue, Cosmic Purple, Forest Green, Sunset Orange, Moonlight Silver)
- [x] Given user selects new theme, when change applied, then entire app UI updates immediately (no restart)
- [x] Given theme changed, when user relaunches app, then selected theme persists

#### User Story 3: Select AI Provider

**As a** user with performance vs accuracy preferences
**I want to** choose AI provider (Gemini)
**So that** I can optimize for my needs

**Acceptance Criteria:**
- [x] Given user opens Settings, when viewing "AI & Scanning" section, then AI provider dropdown shown
- [x] Given user selects Gemini, when scanning bookshelf or importing CSV, then Gemini API used
- [x] Given provider changed, when user performs AI operation, then new provider used immediately

#### User Story 4: Enable Experimental Features

**As a** power user or beta tester
**I want to** toggle experimental features
**So that** I can try new functionality early

**Acceptance Criteria:**
- [x] Given user opens Settings, when viewing "Advanced" section, then feature flag toggles shown
- [x] Given user enables experimental barcode scanner, when feature available, then new scanner UI appears
- [x] Given feature flag disabled, when feature not ready, then toggle grayed out with explanation

#### User Story 5: Reset Library Data

**As a** user wanting a fresh start (or developer testing)
**I want to** reset all library data
**So that** I can start over without reinstalling app

**Acceptance Criteria:**
- [x] Given user opens Settings, when viewing "Library Management" section, then "Reset Library" button shown
- [x] Given user taps "Reset Library", when confirmation dialog appears, then user must confirm action
- [x] Given user confirms reset, when operation completes, then all Works, Editions, Authors, UserLibraryEntries deleted
- [x] Given reset in progress, when user waits, then enrichment queue cleared, backend jobs canceled, search history cleared

---

## Technical Implementation

### Architecture Overview

**Component Structure:**

```
SettingsView (Sheet Presentation)
  ├─ Appearance Section
  │   └─ iOS26ThemeStore (Theme selection with 5 options)
  ├─ AI & Scanning Section
  │   └─ AI Provider Picker (Gemini default)
  ├─ Advanced Section
  │   └─ Feature Flags (Experimental toggles)
  └─ Library Management Section
      ├─ Reset Library (Destructive action with confirmation)
      └─ Storage Info (Used space, total books)
```

**Access Pattern:**

- Settings accessed via gear icon in Library tab toolbar
- Sheet presentation with "Done" button (follows Books.app pattern)
- Not a tab bar item (iOS 26 HIG recommends 4-tab maximum)

**Theme System:**

- `iOS26ThemeStore` injected via `@Environment`
- 5 built-in themes: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- Theme changes propagate app-wide via `@Observable` pattern
- Persisted to UserDefaults (survives app restart)

---

## Decision Log

### October 2025 Decisions

#### **Decision:** Settings in Library Tab Toolbar (Not Tab Bar)

**Context:** iOS 26 HIG recommends 4-tab maximum for optimal UX. Adding Settings as 5th tab violates guideline.

**Options Considered:**
1. Settings as 5th tab (violates HIG, cluttered tab bar)
2. Settings in Library toolbar (follows Books.app pattern)
3. Settings in "More" overflow menu (hidden, poor discoverability)

**Decision:** Option 2 (Settings in Library toolbar with gear icon)

**Rationale:**
- **HIG Compliance:** 4-tab maximum for optimal thumb reach
- **Precedent:** Apple Books uses same pattern (gear icon in Library)
- **Discoverability:** Toolbar gear icon is standard iOS pattern
- **Accessibility:** Larger tap target than 5th tab would be

**Tradeoffs:**
- Settings less prominent than tab (but low-frequency feature, acceptable)

---

#### **Decision:** Sheet Presentation (Not Push Navigation)

**Context:** Settings could use push navigation (NavigationLink) or sheet presentation.

**Options Considered:**
1. Push navigation (keeps user in Library navigation stack)
2. Sheet presentation (modal, separate context)
3. Popover (iPad-specific, not iOS universal)

**Decision:** Option 2 (Sheet presentation with "Done" button)

**Rationale:**
- **iOS 26 HIG:** Modal sheets for self-contained tasks (Settings is configuration, not content browsing)
- **User Mental Model:** Settings is separate from Library content (sheet reinforces this)
- **Dismissal:** "Done" button provides clear exit (push navigation ambiguous)

**Tradeoffs:**
- Sheet blocks Library view (but Settings is low-frequency, acceptable)

---

#### **Decision:** 5 Built-In Themes (Not User-Created Themes)

**Context:** Users want visual customization. How much flexibility to provide?

**Options Considered:**
1. Single theme (simple, no customization)
2. 5 curated themes (balance choice vs complexity)
3. Custom color picker (maximum flexibility, high complexity)

**Decision:** Option 2 (5 curated themes: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver)

**Rationale:**
- **Quality Control:** Curated themes ensure WCAG AA contrast (4.5:1+)
- **Simple UX:** 5 options balances choice without overwhelming
- **Maintainability:** Custom colors hard to validate for accessibility

**Tradeoffs:**
- Users can't create exact color match (but 5 themes cover most preferences)

---

#### **Decision:** Gemini-Only AI Provider (No Cloudflare Workers AI)

**Context:** Cloudflare Workers AI models (Llama, LLaVA, UForm) removed due to small context windows (8K-128K tokens) that couldn't handle bookshelf images.

**Options Considered:**
1. Keep Cloudflare Workers AI as fallback (unreliable, small context)
2. Gemini-only (reliable, 2M token context, optimized for vision)
3. Add OpenAI GPT-4V (expensive, rate limits)

**Decision:** Option 2 (Gemini 2.0 Flash only)

**Rationale:**
- **Performance:** Gemini handles 4-5MB images natively (no resizing)
- **Accuracy:** 0.7-0.95 confidence scores (high detection quality)
- **Cost:** Gemini pricing reasonable for our scale
- **Simplicity:** One provider = less code, fewer edge cases

**Tradeoffs:**
- No fallback if Gemini has outage (acceptable for v3.0, future enhancement)

**See:** [GitHub Issue #134](https://github.com/jukasdrj/books-tracker-v1/issues/134) for Cloudflare Workers AI removal rationale.

---

## UI Specification

### Settings Screen Layout

**Navigation:**
- Sheet presentation from Library tab toolbar
- Title: "Settings"
- Right button: "Done" (dismisses sheet)

**Sections:**

```
┌─────────────────────────────────────┐
│  Settings                    [Done] │
├─────────────────────────────────────┤
│  APPEARANCE                         │
│  Theme: Liquid Blue            [>]  │
│                                     │
│  AI & SCANNING                      │
│  AI Provider: Gemini           [>]  │
│                                     │
│  ADVANCED                           │
│  Experimental Barcode Scanner [✓]  │
│  Batch Upload Limit: 5         [>]  │
│                                     │
│  LIBRARY MANAGEMENT                 │
│  Reset Library           [Red Text] │
│  Storage Used: 45 MB / 250 books    │
└─────────────────────────────────────┘
```

---

## Implementation Files

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/SettingsView.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Theme/iOS26ThemeStore.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ContentView.swift` (Library toolbar integration)

**SwiftUI Pattern:**

```swift
struct LibraryView: View {
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            // Library content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}
```

---

## Feature Flags Available

| Feature Flag | Description | Default | Status |
|-------------|-------------|---------|--------|
| `experimentalBarcodeScanner` | VisionKit-based ISBN scanner (shipped) | Enabled | ✅ Shipped |
| `batchUploadLimit` | Max photos in bookshelf batch scan | 5 | ✅ Active |
| `geminiCSVImport` | AI-powered CSV parsing | Enabled | ✅ Shipped |

---

## Library Reset Behavior

**Comprehensive Reset Flow:**

1. User taps "Reset Library" → Confirmation dialog appears
2. User confirms → Reset begins:
   - Cancel in-flight backend enrichment jobs (`POST /api/enrichment/cancel`)
   - Stop local enrichment processing
   - Delete all SwiftData models (Works, Editions, Authors, UserLibraryEntries)
   - Clear enrichment queue (`EnrichmentQueue.shared.clearAll()`)
   - Reset AI provider to Gemini
   - Reset feature flags to defaults
   - Clear search history
3. User sees empty library, ready for fresh import

**Backend Cancellation:**
- iOS calls `EnrichmentQueue.shared.cancelBackendJob()`
- POST to `/api/enrichment/cancel` with jobId
- Worker calls `doStub.cancelJob()` on ProgressWebSocketDO
- DO sets "canceled" status in Durable Object storage
- Enrichment loop checks `doStub.isCanceled()` before each book
- If canceled, sends final status update and stops processing

**Critical:** Backend jobs tracked via `currentJobId` in EnrichmentQueue. Always call `setCurrentJobId()` when starting enrichment and `clearCurrentJobId()` when complete.

---

## Error Handling

### UI Error States

| Error Condition | User Experience | Recovery Action |
|----------------|-----------------|-----------------|
| Theme load failure | Default to Liquid Blue | Log error, show toast |
| AI provider unavailable | Gray out option, show tooltip | Enable when available |
| Reset failure (SwiftData error) | Alert: "Reset failed, try again" | Retry button |
| Backend cancel timeout | Continue with local reset | Background job will timeout naturally |

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Export Library Data**
   - Export to CSV (title, author, ISBN, status, rating)
   - Useful for backup or migration to other apps
   - Settings → Library Management → "Export to CSV"

2. **Import/Export Settings Profile**
   - Save theme + feature flags as JSON
   - Share settings with friends or across devices
   - Settings → Advanced → "Export Settings Profile"

3. **Storage Analytics**
   - Show storage breakdown (covers, temp files, SwiftData)
   - "Clean Cache" button to remove orphaned files
   - Settings → Library Management → "Storage Details"

4. **Accessibility Settings**
   - Font size override (beyond system Dynamic Type)
   - High contrast mode toggle
   - Settings → Accessibility

---

## Testing Strategy

### Manual QA Scenarios

- [x] Open Settings from Library toolbar, verify gear icon visible
- [x] Change theme to Cosmic Purple, verify entire app updates immediately
- [x] Relaunch app, verify theme persists
- [x] Select Gemini AI provider, scan bookshelf, verify Gemini used
- [x] Enable experimental feature flag, verify new UI appears
- [x] Reset Library, verify all data deleted and backend job canceled
- [x] Dismiss Settings with "Done", verify Library view still loaded

---

## Dependencies

**iOS:**
- SwiftUI (sheet presentation, navigation)
- SwiftData (persistent storage for library data)
- UserDefaults (theme and feature flag persistence)
- iOS26ThemeStore (theme management)

**Backend:**
- `/api/enrichment/cancel` (for Library Reset job cancellation)

---

## Success Criteria (Shipped)

- ✅ Settings accessible via Library toolbar gear icon
- ✅ 5 themes available (liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver)
- ✅ Theme changes apply immediately (no restart)
- ✅ AI provider selection (Gemini default)
- ✅ Feature flags for experimental features
- ✅ Library Reset with backend job cancellation
- ✅ Sheet presentation with "Done" button (iOS 26 HIG compliant)

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
**Documentation:** Referenced in `CLAUDE.md` under "Settings Access" and "Navigation Structure"
