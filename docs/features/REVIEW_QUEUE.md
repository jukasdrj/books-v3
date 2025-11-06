# Review Queue (Human-in-the-Loop) Feature

**Status:** ✅ Shipped (Build 49+) | ✨ Enhanced with Manual Matching (Build 50+)
**Last Updated:** November 5, 2025
**Related Issues:** #112, #113, #114, #115, #116, #117, #118, #119, #120

---

## Overview

The Review Queue allows users to review and correct AI-detected book metadata from bookshelf scans when the AI confidence is below 60%. This human-in-the-loop workflow ensures data quality while maintaining the speed benefits of automated detection.

**NEW (Build 50+):** Manual matching feature allows users to search and select the correct book when enrichment fails or AI detection is incorrect, providing a complete recovery path for all failed enrichments.

**Problem Solved:**
Gemini 2.5 Flash AI can misread book spines due to blur, glare, or unusual fonts. The Review Queue surfaces these low-confidence detections for human verification, preventing incorrect data from entering the library. When text editing isn't sufficient, users can now search external APIs to find and apply the correct match.

---

## User Flow

```
Bookshelf Scan (Gemini AI)
           ↓
   Confidence Check
           ↓
  ├─ ≥60%: Auto-import as .verified
  └─ <60%: Import as .needsReview
           ↓
   User opens Library
           ↓
   Sees Review Queue badge (🔴 indicator)
           ↓
   Taps Review Queue button
           ↓
   Views list of books needing review
           ↓
   Taps book → CorrectionView
           ↓
   Sees cropped spine image + edit fields
           ↓
   ├─ Edits title/author → Saves → .userEdited
   ├─ No changes → Mark as Verified → .verified
   └─ **NEW: Taps "Search for Match" → ManualMatchView**
           ↓
   **Manual Match Flow:**
   - Searches OpenLibrary/ISBNdb/Google Books
   - Browses results with cover previews
   - Selects correct match
   - Confirms replacement
           ↓
   Book updated with correct metadata + cover
   Marked as .userEdited and removed from queue
           ↓
   All books reviewed → Image cleanup on next launch
```

---

## Architecture

### Data Model

**ReviewStatus Enum:**
```swift
public enum ReviewStatus: String, Codable, Sendable {
    case verified       // AI or user confirmed accuracy
    case needsReview    // Low confidence (< 60%)
    case userEdited     // Human corrected AI result
}
```

**Work Model Extensions:**
```swift
@Model
public class Work {
    // Review workflow properties
    public var reviewStatus: ReviewStatus = .verified
    public var originalImagePath: String?  // Temp file path
    public var boundingBox: CGRect?        // Normalized (0.0-1.0)
}
```

**DetectedBook:**
```swift
public struct DetectedBook {
    public var confidence: Double
    public var boundingBox: CGRect
    public var originalImagePath: String?

    // Computed property
    public var needsReview: Bool {
        confidence < 0.60  // 60% threshold
    }
}
```

### Components

| Component | Responsibility | Lines of Code |
|-----------|---------------|---------------|
| **ReviewQueueModel** | State management, queue loading | 93 |
| **ReviewQueueView** | Queue list UI, navigation | 315 |
| **CorrectionView** | Editing interface with image cropping | 335 |
| **ManualMatchView** ✨ NEW | Search and match selection UI | 430 |
| **ImageCleanupService** | Automatic temp file cleanup | 145 |

**Total:** ~1,318 lines of production code (+455 for manual matching)

---

## Key Features

### 1. Automatic Queue Population

**Trigger:** ScanResultsView import (BookshelfScanning/ScanResultsView.swift:545-550)

```swift
// Set review status based on confidence threshold
work.reviewStatus = detectedBook.needsReview ? .needsReview : .verified

// Store image metadata for correction UI
work.originalImagePath = detectedBook.originalImagePath
work.boundingBox = detectedBook.boundingBox
```

### 2. ✨ NEW: Manual Book Matching (Build 50+)

**Location:** CorrectionView → "Search for Match" button

**Purpose:** Allows users to search external APIs when text editing isn't sufficient

**Architecture:**
- Reuses existing `SearchModel` and `BookSearchAPIService`
- Presents search UI with scope selector (All/Title/Author/ISBN)
- Shows results with cover image previews
- Applies selected match with confirmation dialog

**Implementation:** (ManualMatchView.swift:1-430)

```swift
// User taps "Search for Match" in CorrectionView
ManualMatchView(work: work)
    .sheet(isPresented: $showingManualMatch)

// Presents search interface
- Pre-populated with work title
- Search scopes: All, Title, Author, ISBN
- Results show cover images + metadata
- Confirmation before applying match

// Applies selected match
- Updates Work title, authors, metadata
- Updates/creates editions with cover images
- Preserves existing user library entries
- Marks as .userEdited and removes from queue
```

**Integration Points:**
1. **Review Queue:** CorrectionView "Search for Match" button
2. **CSV Import Failures:** Future - add to failed enrichments
3. **Work Detail View:** Future - "Find Alternative Cover" action

**Benefits:**
- 10% CSV import failures now have recovery path
- Bookshelf scan misdetections can be corrected
- Users can replace incorrect covers/metadata
- No manual typing of complex metadata

### 3. Visual Queue Indicator

**Location:** iOS26LiquidLibraryView toolbar (iOS26LiquidLibraryView.swift:91-109)

```swift
Button {
    showingReviewQueue.toggle()
} label: {
    ZStack(alignment: .topTrailing) {
        Image(systemName: "exclamationmark.triangle")

        if reviewQueueCount > 0 {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: 4, y: -4)
        }
    }
}
.foregroundStyle(reviewQueueCount > 0 ? .orange : .primary)
```

### 3. Image Cropping

**Algorithm:** (CorrectionView.swift:209-236)

```swift
// Convert normalized coordinates to pixel coordinates
let imageWidth = CGFloat(cgImage.width)
let imageHeight = CGFloat(cgImage.height)

let cropRect = CGRect(
    x: boundingBox.origin.x * imageWidth,
    y: boundingBox.origin.y * imageHeight,
    width: boundingBox.width * imageWidth,
    height: boundingBox.height * imageHeight
)

guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
    return nil
}

return UIImage(cgImage: croppedCGImage)
```

### 4. Automatic Cleanup

**Trigger:** App launch (ContentView.swift:73-78)

```swift
.task {
    // Clean up temporary scan images after all books reviewed
    await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
    // Clean up orphaned temp files from failed scans (24h+ old)
    await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
}
```

**Two-Phase Cleanup Strategy:**

**Phase 1 - Reviewed Images:** (ImageCleanupService.swift:25-73)
- Groups works by `originalImagePath`
- Checks if all books from scan are `.verified` or `.userEdited`
- Deletes image file and clears Work references
- Saves ModelContext changes

**Phase 2 - Orphaned Files:** (ImageCleanupService.swift:148-202)
- Scans temp directory for `bookshelf_scan_*.jpg` files
- Checks if file is referenced by any Work in SwiftData
- Deletes files that are:
  - NOT referenced by any Work (orphaned)
  - AND older than 24 hours (age threshold)
- **Handles edge cases:** Failed scans, crashes, network errors where Works are never created
- **Safe:** 24-hour grace period prevents deleting active sessions

---

## Analytics Events

| Event | Properties | Trigger |
|-------|-----------|---------|
| `review_queue_viewed` | `queue_count` | Queue opened |
| `review_queue_correction_saved` | `had_title_change`, `had_author_change` | User saves edits |
| `review_queue_verified_without_changes` | None | User verifies without editing |

**Current Implementation:** Placeholder print statements (📊 Analytics: event_name)
**TODO:** Replace with Firebase Analytics or Mixpanel SDK

---

## iOS 26 Design Compliance

### Liquid Glass Styling

- ✅ `.ultraThinMaterial` backgrounds on all cards
- ✅ `themeStore.backgroundGradient` full-screen backdrop
- ✅ `themeStore.primaryColor` for action buttons
- ✅ 16pt corner radius (standard)
- ✅ 8pt shadow on spine images

### Accessibility (WCAG AA)

- ✅ System semantic colors (`.primary`, `.secondary`, `.tertiary`)
- ✅ VoiceOver labels on all interactive elements
- ✅ Orange warning color for review badge (4.5:1+ contrast)
- ✅ Keyboard toolbar for number pad (page count fields)

### Known HIG Concerns

See Issue #120 for toolbar button design review:
- Visual hierarchy (all 3 buttons equal weight)
- Semantic grouping (alert vs info vs preference)
- Badge visibility (8pt red dot may be too small)

---

## Performance Metrics

| Metric | Value | Note |
|--------|-------|------|
| Confidence Threshold | 60% | Balances automation vs accuracy |
| Image Cleanup Delay | App relaunch | Ensures all books reviewed |
| Queue Load Time | <100ms | In-memory filtering (no predicates) |
| Image Crop Time | <50ms | CGImage operation, async |

**SwiftData Limitation:** Enum case comparison not supported in predicates
**Solution:** Fetch all works, filter in-memory with `.filter { $0.reviewStatus == .needsReview }`

---

## Testing Strategy

### Unit Testing

**Recommended Tests:**
```swift
@Test func lowConfidenceBooksFlaggedForReview() {
    let detected = DetectedBook(confidence: 0.55, ...)
    #expect(detected.needsReview == true)
}

@Test func highConfidenceBooksBypassReview() {
    let detected = DetectedBook(confidence: 0.85, ...)
    #expect(detected.needsReview == false)
}

@Test func imageCleanupOnlyAfterAllBooksReviewed() async {
    // Create 3 works with same imagePath
    // Mark 2 as .verified, 1 as .needsReview
    // Run cleanup
    // #expect(imageExists == true)
}
```

### Manual Testing Checklist

- [ ] Scan bookshelf with mix of high/low confidence books
- [ ] Verify Review Queue badge appears in Library toolbar
- [ ] Tap Review Queue → See list of books needing review
- [ ] Tap book → CorrectionView shows cropped spine image
- [ ] Edit title → Save → Book marked as `.userEdited`
- [ ] No edits → Verify → Book marked as `.verified`
- [ ] **NEW:** Tap "Search for Match" → ManualMatchView appears
- [ ] **NEW:** Search for book → See results with covers
- [ ] **NEW:** Select match → Confirmation dialog appears
- [ ] **NEW:** Confirm → Work updated, removed from queue
- [ ] Book disappears from queue after action
- [ ] Relaunch app → Image cleanup runs (check console logs)
- [ ] Test across all 5 themes (liquidBlue, cosmicPurple, etc.)
- [ ] VoiceOver navigation works correctly

---

## Common Issues & Solutions

### Issue: "Could not cast value to ReviewStatus"

**Cause:** Existing database doesn't have `reviewStatus` column
**Solution:** Uninstall app to reset database (simulator only)

```bash
xcrun simctl uninstall <UDID> Z67H8Y8DW.com.oooefam.booksV3
```

### Issue: Images not deleting after review

**Check:** Console logs on app launch
```
✅ ImageCleanupService: Deleted <path> (3 books reviewed)
🧹 ImageCleanupService: Cleaned up 1 image(s), 0 error(s)
```

**Debug:**
- Verify all books from scan are `.verified` or `.userEdited`
- Check `ImageCleanupService.getActiveImageCount()` returns 0
- Ensure file permissions allow deletion

### Issue: Review Queue always shows 0

**Check:** Import logic in `ScanResultsView.addAllToLibrary()`
```swift
work.reviewStatus = detectedBook.needsReview ? .needsReview : .verified
```

Verify `DetectedBook.confidence < 0.60` for low-confidence books.

---

## Future Enhancements

### Planned (Backlog)

1. **CSV Import Integration** - Add "Fix Failed Enrichments" after CSV import completion
2. **Work Detail Alternative Covers** - Add "Find Alternative Cover" action in WorkDetailView
3. **Library Filtering** - Filter library by "Missing Covers" → Batch match UI
4. **Batch Review Mode** - Swipe through multiple books without dismissing
5. **Confidence Score Display** - Show AI confidence % in CorrectionView
6. **Manual Recrop** - Adjust bounding box if AI cropped incorrectly
7. **Review History** - Track accuracy improvements over time

### Considered (Deferred)

- Auto-retry with OpenLibrary API for low-confidence detections
- ML model retraining based on user corrections
- Bulk verify (mark all as verified without individual review)

---

## Related Documentation

- **Product Requirements:** `docs/product/Review-Queue-PRD.md` - User stories, acceptance criteria, success metrics
- **Workflow Diagrams:** `docs/workflows/bookshelf-scanner-workflow.md` - Review Queue integration (confidence routing section)
- **Bookshelf Scanner:** `docs/features/BOOKSHELF_SCANNER.md` - AI detection system
- **iOS 26 HIG:** `CLAUDE.md` - iOS 26 Liquid Glass Design System compliance
- **Image Cleanup:** `ImageCleanupService.swift` - Automatic temp file management

---

## Changelog

**Build 50 (November 5, 2025):**
- ✨ **NEW:** Manual book matching feature (ManualMatchView)
- ✨ Integrated search into CorrectionView with "Search for Match" button
- ✨ Reuses existing search infrastructure (SearchModel, BookSearchAPIService)
- ✨ Support for all search scopes (All/Title/Author/ISBN)
- ✨ Confirmation dialog before applying match
- ✅ Preserves user library entries when applying match
- ✅ Unit tests for manual matching (ManualMatchViewTests)
- ✅ Documentation updates

**Build 49 (October 23, 2025):**
- ✅ Core workflow implementation (Issues #112-115)
- ✅ ImageCleanupService automatic cleanup (#116)
- ✅ iOS 26 Liquid Glass styling (#117)
- ✅ Analytics placeholder events (#118)
- ✅ Feature documentation (#119)
- ⏳ Toolbar button HIG review (#120) - Pending ios26-hig-designer

**Build 48 (October 17, 2025):**
- Added `reviewStatus`, `originalImagePath`, `boundingBox` to Work model
- Added `needsReview` computed property to DetectedBook

---

**Maintainers:** @jukasdrj
**Status:** Production-ready with manual matching, pending HIG review (#120)
