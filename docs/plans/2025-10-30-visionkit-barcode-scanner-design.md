# VisionKit Barcode Scanner Design

**Date:** 2025-10-30
**Status:** Approved
**Replaces:** Custom AVFoundation + Vision barcode scanner implementation

## Problem Statement

The current barcode scanner in the Search tab is non-functional:
- Camera preview does not display
- Barcodes are not detected when scanned
- Implementation uses custom `DataScannerView` wrapper that doesn't properly validate device capabilities and permissions

**Root Cause:** Missing validation of `DataScannerViewController.isSupported` and `isAvailable` before presenting scanner, per Apple's VisionKit guidance.

## Solution Overview

Replace custom barcode scanner implementation with **Apple's native VisionKit `DataScannerViewController`** following official guidance from Apple's "Scanning data with the camera" documentation.

**Key Benefits:**
- Zero custom camera/Vision code
- Apple-native UI (highlighting, guidance, gestures)
- Proper capability and permission validation
- Simpler, more maintainable codebase

## Architecture

### Component Structure

```
ISBNScannerView (new primary scanner)
├─ if scannerAvailable
│  └─ DataScannerViewController (full screen, native UI)
├─ else if !isSupported
│  └─ UnsupportedDeviceView (A12+ chip requirement)
└─ else if !isAvailable
   └─ PermissionDeniedView (Settings deep-link)
```

### Files to Create

- **`BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift`**
  - Direct `UIViewControllerRepresentable` wrapper for `DataScannerViewController`
  - Handles all permission/capability validation
  - Implements `DataScannerViewControllerDelegate` via `Coordinator`

### Files to Deprecate/Remove

- **`ModernBarcodeScannerView.swift`** - Remove (replaced by ISBNScannerView)
- **`DataScannerView.swift`** - Remove (replaced by ISBNScannerView)
- **`CameraManager.swift`** - Archive (not needed for VisionKit)
- **`BarcodeDetectionService.swift`** - Archive (not needed for VisionKit)

### Files to Update

- **`SearchView.swift`** (lines 168-179 only)
  - Replace `ModernBarcodeScannerView` → `ISBNScannerView`
  - Keep existing `.sheet(isPresented: $showingScanner)` presentation
  - ISBN callback unchanged

### Files to Keep AS-IS

- **`ISBNValidator.swift`** - Already perfect, reused for validation

## DataScannerViewController Configuration

### Initialization Parameters

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

### Configuration Rationale

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `symbologies` | EAN-13, EAN-8, UPC-E | ISBN-specific only (faster recognition, fewer false positives) |
| `qualityLevel` | `.balanced` | Books held at normal reading distance (not too close/far) |
| `recognizesMultipleItems` | `false` | Single ISBN per scan (standard UX) |
| `isHighFrameRateTrackingEnabled` | `true` | Smooth highlighting animation |
| `isPinchToZoomEnabled` | `true` | Apple-native zoom gesture |
| `isGuidanceEnabled` | `true` | Show "Move Closer", "Slow Down" hints |
| `isHighlightingEnabled` | `true` | Auto-highlight detected barcodes |

### Validation Flow (Pre-Presentation)

```swift
var scannerAvailable: Bool {
    DataScannerViewController.isSupported &&  // A12+ chip check
    DataScannerViewController.isAvailable      // Permissions + no restrictions
}
```

**Validation Sequence:**
1. Check `isSupported` → Devices with A12 Bionic chip or later (iPhone XS/XR+)
2. Check `isAvailable` → Camera permissions granted, no Screen Time restrictions
3. If both true → Present scanner
4. If false → Show appropriate error state

## Delegate Pattern & ISBN Processing

### Coordinator Implementation

```swift
class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onISBNScanned: (ISBNValidator.ISBN) -> Void

    // User taps detected barcode
    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        handleScannedItem(item, dataScanner: dataScanner)
    }

    // Auto-detect (first barcode recognized)
    func dataScanner(_ dataScanner: DataScannerViewController,
                     didAdd addedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
        guard let firstItem = addedItems.first else { return }
        handleScannedItem(firstItem, dataScanner: dataScanner)
    }

    private func handleScannedItem(_ item: RecognizedItem,
                                   dataScanner: DataScannerViewController) {
        guard case .barcode(let barcode) = item,
              let payload = barcode.payloadStringValue else { return }

        // Validate using existing ISBNValidator
        switch ISBNValidator.validate(payload) {
        case .valid(let isbn):
            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Stop scanning + callback + dismiss handled by parent view
            dataScanner.stopScanning()
            onISBNScanned(isbn)

        case .invalid:
            // Silently ignore non-ISBN barcodes (wait for next scan)
            return
        }
    }
}
```

### Processing Flow

1. **Barcode Detected** → VisionKit highlights automatically
2. **User Taps OR Auto-Detect** → `didTapOn` or `didAdd` called
3. **Payload Extracted** → `barcode.payloadStringValue`
4. **ISBN Validation** → Reuse `ISBNValidator.validate()`
5. **Success Path:**
   - Haptic feedback (medium impact)
   - Stop scanning
   - Callback with validated ISBN
   - Dismiss scanner (handled by SearchView)
6. **Invalid Path:**
   - Silent ignore
   - Wait for next detection

### Lifecycle Management

- **Start:** Automatic via `startScanning()` in `updateUIViewController`
- **Stop:** On dismissal or successful scan
- **Cleanup:** No manual cleanup needed (VisionKit handles it)
- **Memory:** Coordinator held by representable, no retain cycles

## Error States & Permission Handling

### Error State Matrix

| Condition | Check | UI Response | User Action |
|-----------|-------|-------------|-------------|
| Device not supported | `!isSupported` | "Barcode Scanning Not Available" message | Upgrade device (iPhone XS/XR+) |
| Permission denied | `!isAvailable` | "Camera Access Required" + Settings button | Grant permission in Settings |
| Camera unavailable | `!isAvailable` | Generic unavailable message | Close other camera apps, check Screen Time |
| Runtime unavailable | `becameUnavailableWithError:` | Auto-dismiss + error alert | Retry scan |

### Permission States

**Not Determined:**
- VisionKit prompts automatically on first `startScanning()`
- Uses `NSCameraUsageDescription` from Info.plist (already configured)

**Authorized:**
- `isAvailable` returns `true`
- Present scanner immediately

**Denied:**
- `isAvailable` returns `false`
- Show "Camera Access Required" view with Settings deep-link

**Restricted:**
- `isAvailable` returns `false`
- Show "Camera Unavailable" message (Screen Time, MDM restrictions)

### Runtime Error Handling

Implement `becameUnavailableWithError:` delegate method:

```swift
func dataScanner(_ dataScanner: DataScannerViewController,
                 becameUnavailableWithError error: Error) {
    // Auto-dismiss scanner
    // Show error alert to user
    // Log error for debugging
}
```

## Integration with SearchView

### Minimal Changes Required

**Before:**
```swift
.sheet(isPresented: $showingScanner) {
    ModernBarcodeScannerView { isbn in
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
    }
}
```

**After:**
```swift
.sheet(isPresented: $showingScanner) {
    ISBNScannerView { isbn in
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
    }
}
```

**Changes:**
- Line 170: `ModernBarcodeScannerView` → `ISBNScannerView`
- Everything else unchanged

### Callback Flow (Unchanged)

1. User taps barcode button → `showingScanner = true`
2. Sheet presents `ISBNScannerView`
3. User scans ISBN → callback fires with validated `ISBN`
4. SearchView sets scope to `.isbn` and triggers search
5. Sheet dismisses automatically

## iOS 26 HIG Compliance

### Design System Integration

- **Theme:** Uses existing `iOS26ThemeStore` for error state backgrounds
- **Typography:** Standard iOS dynamic type throughout
- **Accessibility:** VoiceOver support via VisionKit's built-in labels
- **Haptics:** Medium impact feedback on successful scan

### Native UI Features (VisionKit-Provided)

- ✅ Auto-highlighting of detected barcodes
- ✅ Tap-to-focus gesture
- ✅ Pinch-to-zoom gesture
- ✅ Guidance labels ("Move Closer", "Slow Down")
- ✅ Automatic orientation handling
- ✅ Safe area insets

### Accessibility (WCAG AA)

- All error states use system semantic colors (auto-adapt to Dark Mode)
- VoiceOver labels provided by VisionKit
- Dynamic Type support inherited from VisionKit
- Sufficient contrast ratios (VisionKit design)

## Swift 6 Concurrency Compliance

### Actor Isolation

- `ISBNScannerView`: No actor isolation (pure SwiftUI view)
- `Coordinator`: No actor isolation (UIKit delegate, callbacks on main queue)
- Callbacks use `@MainActor` when needed

### Sendable Conformance

- `ISBN` struct already `Sendable` (value type)
- Closures capture `@escaping` callback safely
- No data races (VisionKit manages threading)

## Testing Strategy

### Manual Testing Checklist

- [ ] Scanner presents with camera preview visible
- [ ] Barcodes are highlighted automatically
- [ ] Tapping barcode triggers ISBN detection
- [ ] Valid ISBN triggers search and dismisses scanner
- [ ] Invalid barcode ignored (no action)
- [ ] Permission denied shows Settings button
- [ ] Unsupported device shows error message
- [ ] Pinch-to-zoom gesture works
- [ ] "Move Closer" guidance appears for distant barcodes
- [ ] Dark Mode rendering correct
- [ ] VoiceOver announces scanner state

### Edge Cases

- **Multiple barcodes in frame:** Only first detected is processed (`recognizesMultipleItems: false`)
- **Non-ISBN barcode scanned:** Silently ignored, wait for next scan
- **Permission revoked mid-scan:** `becameUnavailableWithError:` auto-dismisses
- **Camera in use by other app:** `isAvailable` check prevents presentation

## Implementation Phases

### Phase 1: Core Implementation
1. Create `ISBNScannerView.swift` with VisionKit integration
2. Implement `Coordinator` with delegate methods
3. Add capability/permission validation logic
4. Update `SearchView.swift` line 170

### Phase 2: Error States
1. Implement `UnsupportedDeviceView` component
2. Implement `PermissionDeniedView` with Settings deep-link
3. Add runtime error handling (`becameUnavailableWithError:`)

### Phase 3: Testing & Cleanup
1. Manual testing on physical device (iPhone)
2. Test permission flows (denied → granted)
3. Test unsupported device scenario (simulator)
4. Remove deprecated files (`ModernBarcodeScannerView`, `DataScannerView`)
5. Archive unused files (`CameraManager`, `BarcodeDetectionService`)

## Success Criteria

- ✅ Camera preview displays when scanner opens
- ✅ Barcodes detected and highlighted automatically
- ✅ Valid ISBN triggers search and dismisses scanner
- ✅ Invalid barcodes ignored gracefully
- ✅ Permission denied shows clear error + Settings button
- ✅ Unsupported devices show clear error message
- ✅ Zero compiler warnings
- ✅ Zero crashes in normal usage
- ✅ 100% iOS 26 HIG compliance

## References

- **Apple Documentation:** "Scanning data with the camera" (VisionKit)
- **Project Docs:** `CLAUDE.md` - Barcode Scanning section
- **Codebase:** `ISBNValidator.swift` - Existing validation logic
- **Design System:** `iOS26ThemeStore` - Theme integration
