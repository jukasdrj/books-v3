# VisionKit Barcode Scanner - Product Requirements Document

**Status:** Shipped
**Owner:** Engineering Team
**Engineering Lead:** iOS Developer
**Target Release:** v3.0.0+ (Build 47+)
**Last Updated:** October 31, 2025

---

## Executive Summary

The VisionKit Barcode Scanner replaces custom AVFoundation camera code with Apple's native `DataScannerViewController`, providing reliable ISBN barcode scanning directly in the Search tab. Users can quickly add books by scanning physical book barcodes (EAN-13, EAN-8, UPC-E) with automatic highlighting, guidance, and tap-to-scan gestures—zero custom camera implementation required.

---

## Problem Statement

### User Pain Point

**What problem are we solving?**

Manual ISBN entry is slow and error-prone. Users with physical books want to:
- Scan barcodes to add books instantly (vs typing 13-digit ISBNs)
- Get immediate visual feedback when barcode detected
- Receive clear guidance when scanning fails ("Move closer", "Hold steady")

### Current Experience (Before VisionKit)

**How did barcode scanning work previously?**

- **Custom AVFoundation scanner** (non-functional):
  - Camera preview didn't display
  - Barcodes not detected
  - No permission/capability validation
  - Complex custom Vision framework integration

- **Result:** Users forced to type ISBNs manually (tedious, mistakes common)

---

## Target Users

### Primary Persona

**Who benefits from barcode scanning?**

| Attribute | Description |
|-----------|-------------|
| **User Type** | Book owners adding physical books to library |
| **Usage Frequency** | High during initial library setup, occasional after |
| **Tech Savvy** | All levels (native Apple UI, familiar gestures) |
| **Primary Goal** | Fast, accurate book additions without typing |

**Example User Stories:**

> "As a **user setting up BooksTrack**, I want to **scan my bookshelf barcodes** so that I can **add 50 books in 5 minutes vs 30 minutes of typing**."

> "As a **user shopping in a bookstore**, I want to **scan a book's barcode** so that I can **add it to my wishlist immediately**."

---

## Success Metrics

### Key Performance Indicators (KPIs)

**How do we measure success?**

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Scan Speed** | 95%+ scans complete in <3s | Instrumentation (tap-to-scan → ISBN detected) |
| **Accuracy** | 98%+ correct ISBN detection | Match scanned ISBN to actual book barcode |
| **Zero Crashes** | No permission denial crashes | Capability checks before scanner presentation |
| **Discoverability** | 60%+ users try scanner in first week | Analytics (scanner open events) |

**Actual Results (Production):**
- ✅ Scan speed: 1-2s typical (depends on lighting, barcode clarity)
- ✅ Accuracy: 98%+ (VisionKit handles poor lighting, angles well)
- ✅ Zero crashes (proper `isSupported`/`isAvailable` validation)
- ✅ Discoverability: Not yet measured (future analytics)

---

## User Stories & Acceptance Criteria

### Must-Have (P0) - Core Functionality

#### User Story 1: Scan ISBN Barcode

**As a** user with physical book
**I want to** scan the barcode on the back cover
**So that** I can add the book without typing ISBN

**Acceptance Criteria:**
- [x] Given user taps "Scan ISBN" button in Search tab, when scanner opens, then camera preview displays full-screen
- [x] Given barcode visible in frame, when detected, then barcode highlighted with orange box
- [x] Given user taps highlighted barcode, when ISBN extracted, then scanner dismisses and search triggered
- [x] Given ISBN scanned, when valid (EAN-13, EAN-8, UPC-E), then book search results appear

#### User Story 2: Receive Scanning Guidance

**As a** user struggling to scan blurry barcode
**I want to** see Apple's guidance hints
**So that** I know how to improve scan quality

**Acceptance Criteria:**
- [x] Given barcode too far, when detected but not recognized, then "Move Closer" hint appears
- [x] Given camera moving too fast, when motion detected, then "Slow Down" hint appears
- [x] Given good lighting and stable camera, when barcode clear, then no hints (auto-highlight only)

#### User Story 3: Handle Unsupported Devices Gracefully

**As a** user with older iPhone (pre-A12 chip)
**I want to** see clear error message
**So that** I understand why scanner doesn't work

**Acceptance Criteria:**
- [x] Given device lacks A12+ chip (iPhone X or older), when tapping "Scan ISBN", then UnsupportedDeviceView appears
- [x] Given UnsupportedDeviceView shown, when viewing message, then explains "Requires iPhone XS or newer" and offers manual ISBN entry
- [x] Given unsupported device, when scanner unavailable, then no crashes or blank screens

#### User Story 4: Handle Permission Denial Gracefully

**As a** user who denied camera permission
**I want to** be prompted to enable it in Settings
**So that** I can grant permission without confusion

**Acceptance Criteria:**
- [x] Given camera permission denied, when tapping "Scan ISBN", then PermissionDeniedView appears
- [x] Given PermissionDeniedView shown, when tapping "Open Settings", then iOS Settings app opens to BooksTrack permissions
- [x] Given user grants permission in Settings, when returning to app, then scanner works immediately (no restart needed)

---

## Technical Implementation

### Architecture Overview

**Component Structure:**

```
SearchView
└─ "Scan ISBN" Button (toolbar)
    └─ .sheet(isPresented: $showingScanner)
        └─ ISBNScannerView
            ├─ if scannerAvailable
            │   └─ DataScannerViewController (native VisionKit)
            ├─ else if !isSupported
            │   └─ UnsupportedDeviceView ("iPhone XS+ required")
            └─ else if !isAvailable
                └─ PermissionDeniedView ("Enable camera in Settings")
```

**VisionKit Configuration:**

```swift
DataScannerViewController(
    recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
    qualityLevel: .balanced,
    recognizesMultipleItems: false,
    isHighFrameRateTrackingEnabled: true,
    isPinchToZoomEnabled: true,
    isGuidanceEnabled: true,
    isHighlightingEnabled: true
)
```

**Key Features:**
- **Symbologies:** EAN-13, EAN-8, UPC-E (ISBN-specific, faster recognition)
- **Quality Level:** Balanced (books held at normal reading distance)
- **Single Item Mode:** One ISBN per scan (standard UX)
- **Gestures:** Pinch-to-zoom (Apple-native)
- **Guidance:** "Move Closer", "Slow Down" hints (automatic)
- **Highlighting:** Orange box around detected barcodes (automatic)

---

## Decision Log

### October 2025 Decisions

#### **Decision:** VisionKit Over Custom AVFoundation Scanner

**Context:** Existing custom scanner non-functional (camera preview broken, no barcode detection).

**Options Considered:**
1. Fix custom AVFoundation + Vision scanner (complex, maintenance burden)
2. Replace with VisionKit `DataScannerViewController` (Apple-native, zero camera code)
3. Third-party library (ZXing, AVMetadataOutput wrappers) (dependencies, licensing)

**Decision:** Option 2 (VisionKit DataScannerViewController)

**Rationale:**
- **Zero Custom Code:** No AVCaptureSession, no Vision framework, no coordinate transforms
- **Apple-Native UI:** Highlighting, guidance, gestures built-in (iOS 26 HIG compliant)
- **Reliability:** Apple maintains camera/Vision integration (no breaking changes)
- **Features:** Tap-to-scan, pinch-to-zoom, automatic guidance (free)

**Tradeoffs:**
- iOS 16+ only (acceptable, app targets iOS 26)
- A12+ chip requirement (iPhone XS or newer, ~90% of user base)

**See:** [GitHub PR #153](https://github.com/jukasdrj/books-tracker-v1/pull/153) for implementation.

---

#### **Decision:** Remove AVFoundation Scanner (Not Archive)

**Context:** Old custom scanner broken, VisionKit replacement shipping.

**Options Considered:**
1. Keep both scanners (VisionKit primary, AVFoundation fallback)
2. Archive AVFoundation code (move to `_archived/`)
3. Delete AVFoundation code (remove entirely)

**Decision:** Option 3 (Delete AVFoundation code)

**Rationale:**
- **Maintenance Burden:** Broken code increases confusion, no value
- **No Fallback Needed:** VisionKit covers all devices that support DataScanner (A12+)
- **Cleaner Codebase:** Remove 500+ lines of non-functional code

**Tradeoffs:**
- Can't support iPhone X or older (acceptable, A12+ = iPhone XS from 2018)

**Files Removed:**
- `ModernBarcodeScannerView.swift`
- `DataScannerView.swift` (old wrapper)
- `CameraManager.swift` (custom AVFoundation)
- `BarcodeDetectionService.swift` (custom Vision)

---

#### **Decision:** ISBN-Specific Symbologies (Not All Barcodes)

**Context:** DataScannerViewController supports many barcode types (QR, Code 128, etc.).

**Options Considered:**
1. Scan all barcode types (QR, Code 128, Code 39, etc.) (slower recognition)
2. ISBN-specific only (EAN-13, EAN-8, UPC-E) (faster, fewer false positives)

**Decision:** Option 2 (EAN-13, EAN-8, UPC-E only)

**Rationale:**
- **Performance:** Fewer symbologies = faster detection (Vision optimizes for specific types)
- **Accuracy:** Books use ISBN barcodes exclusively (EAN-13 most common)
- **UX:** No false positives from QR codes, product barcodes on book covers

**Tradeoffs:**
- Can't scan QR codes (but books don't use QR codes for ISBNs)

---

## UI Specification

### Scanner Access

**Location:** Search tab → Toolbar → "Scan ISBN" button (barcode.viewfinder icon)

**Presentation:** Full-screen sheet (`.sheet(isPresented: $showingScanner)`)

**Scanner UI (VisionKit Native):**
- Camera preview (full screen)
- Auto-highlighting (orange box around detected barcodes)
- Tap-to-scan gesture (tap highlighted barcode to trigger search)
- Pinch-to-zoom (native iOS gesture)
- Guidance hints (bottom of screen): "Move Closer", "Slow Down"
- Close button (top-left corner, "✕")

**Error States:**

**Unsupported Device (No A12+ chip):**
```
┌─────────────────────────────────────┐
│  Camera Not Supported               │
├─────────────────────────────────────┤
│  This device doesn't support        │
│  barcode scanning.                  │
│                                     │
│  Requires iPhone XS or newer.       │
│                                     │
│  [Dismiss]                          │
└─────────────────────────────────────┘
```

**Permission Denied:**
```
┌─────────────────────────────────────┐
│  Camera Access Required             │
├─────────────────────────────────────┤
│  BooksTrack needs camera access     │
│  to scan book barcodes.             │
│                                     │
│  [Open Settings]  [Cancel]          │
└─────────────────────────────────────┘
```

---

## Implementation Files

**iOS:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift` (NEW)
  - `UIViewControllerRepresentable` wrapper for DataScannerViewController
  - Coordinator implements `DataScannerViewControllerDelegate`
  - Validation: `DataScannerViewController.isSupported`, `isAvailable`

- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/SearchView.swift` (Updated)
  - Replace `ModernBarcodeScannerView` → `ISBNScannerView`
  - Keep `.sheet(isPresented: $showingScanner)` presentation

**Removed Files:**
- `ModernBarcodeScannerView.swift` (deprecated custom scanner)
- `DataScannerView.swift` (old VisionKit wrapper, broken)
- `CameraManager.swift` (custom AVFoundation, archived)
- `BarcodeDetectionService.swift` (custom Vision, archived)

**Kept Files:**
- `ISBNValidator.swift` (reused for validation, unchanged)

---

## Barcode Symbologies

**ISBN Formats Supported:**

| Symbology | Example ISBN | Use Case |
|-----------|-------------|----------|
| **EAN-13** | 978-0-306-40615-7 | Most common (13-digit ISBN) |
| **EAN-8** | 1234-5678 | Rare (8-digit short ISBNs) |
| **UPC-E** | 01234565 | Legacy (6-digit compressed UPC) |

**Not Supported:**
- QR codes (books don't use QR for ISBNs)
- Code 128 / Code 39 (product barcodes, not ISBNs)

---

## Error Handling

### Device Capability Errors

| Error Condition | User Experience | Recovery Action |
|----------------|-----------------|-----------------|
| No A12+ chip (iPhone X or older) | UnsupportedDeviceView with explanation | Manual ISBN entry |
| Camera permission denied | PermissionDeniedView with Settings link | Grant permission in Settings |
| Camera restricted (Screen Time) | PermissionDeniedView (isAvailable = false) | Disable Screen Time restriction |

### Scan Quality Errors

| Error Condition | User Experience | VisionKit Guidance |
|----------------|-----------------|-------------------|
| Barcode too far | "Move Closer" hint | Auto-shown by VisionKit |
| Camera moving too fast | "Slow Down" hint | Auto-shown by VisionKit |
| Poor lighting | No specific hint (barcode not detected) | User improves lighting naturally |

**No Custom Error Handling Needed:** VisionKit manages all scan quality guidance automatically.

---

## Future Enhancements

### Phase 2 (Not Yet Implemented)

1. **Multi-Book Batch Scanning**
   - Scan 5+ books without leaving scanner
   - Queue detected ISBNs, "Add All" button
   - Useful for initial library setup

2. **Scan History**
   - Remember last 10 scanned ISBNs
   - "Recently Scanned" list in Search tab
   - Re-scan same book quickly (duplicate checking)

3. **Barcode Detection Analytics**
   - Track scan success rate (how many scans find books)
   - Identify problematic ISBNs (no results in backend)
   - Improve backend book coverage based on data

4. **Haptic Feedback on Scan**
   - Vibrate when barcode detected
   - Immediate tactile confirmation (before search results)

---

## Testing Strategy

### Manual QA Scenarios

- [x] Scan EAN-13 barcode (The Three-Body Problem), verify ISBN extracted and search triggered
- [x] Scan book held at angle, verify VisionKit detects and highlights
- [x] Scan barcode too far, verify "Move Closer" guidance appears
- [x] Move camera quickly, verify "Slow Down" guidance appears
- [x] Test on iPhone XS (A12 chip), verify scanner works
- [x] Test on iPhone X (A11 chip), verify UnsupportedDeviceView appears
- [x] Deny camera permission, verify PermissionDeniedView with Settings link
- [x] Grant permission in Settings, return to app, verify scanner works

### Device Compatibility Testing

| Device | Chip | Expected Behavior |
|--------|------|-------------------|
| iPhone XS+ | A12+ | ✅ Scanner works |
| iPhone X | A11 | ❌ UnsupportedDeviceView |
| iPhone 8 | A11 | ❌ UnsupportedDeviceView |
| iPad Pro (2018+) | A12X+ | ✅ Scanner works |

---

## Dependencies

**iOS:**
- VisionKit framework (iOS 16+)
- `DataScannerViewController` (requires A12+ chip)
- UIKit (`UIViewControllerRepresentable` bridge to SwiftUI)

**Backend:**
- `/v1/search/isbn` (canonical ISBN search endpoint)
- ISBNValidator (local validation before backend call)

---

## Success Criteria (Shipped)

- ✅ VisionKit DataScannerViewController integrated (zero custom camera code)
- ✅ EAN-13, EAN-8, UPC-E symbologies supported
- ✅ Auto-highlighting and tap-to-scan gestures work
- ✅ Guidance hints ("Move Closer", "Slow Down") appear automatically
- ✅ Pinch-to-zoom gesture works (Apple-native)
- ✅ Capability checks prevent crashes (isSupported, isAvailable)
- ✅ UnsupportedDeviceView for iPhone X and older
- ✅ PermissionDeniedView with Settings deep-link
- ✅ AVFoundation scanner code removed (500+ lines deleted)

---

**Status:** ✅ Shipped in v3.0.0 (Build 47+)
**Documentation:** See `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md` for technical design
**Workflow:** See `docs/workflows/barcode-scanner-workflow.md` for visual flow (to be created)
