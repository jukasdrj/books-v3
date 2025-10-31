# VisionKit Barcode Scanner Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace custom barcode scanner with Apple's native VisionKit DataScannerViewController to fix non-functional scanner in Search tab.

**Architecture:** Direct UIViewControllerRepresentable wrapper around DataScannerViewController with proper capability/permission validation. Zero custom camera or Vision code. All scanning, highlighting, and gestures handled by VisionKit.

**Tech Stack:** VisionKit (iOS 16+), SwiftUI, Swift 6.2 concurrency

---

## Task 1: Create ISBNScannerView Core Structure

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift`

**Step 1: Create file with imports and availability declaration**

```swift
import SwiftUI
import VisionKit

/// Apple-native barcode scanner using VisionKit DataScannerViewController
/// Follows official guidance from "Scanning data with the camera"
@available(iOS 16.0, *)
public struct ISBNScannerView: View {
    // Implementation will follow
}
```

**Step 2: Add static capability check**

Add this extension to the file:

```swift
@available(iOS 16.0, *)
extension ISBNScannerView {
    /// Check if scanner is available on this device
    static var isAvailable: Bool {
        DataScannerViewController.isSupported &&
        DataScannerViewController.isAvailable
    }
}
```

**Step 3: Add callback property**

Inside the `ISBNScannerView` struct, add:

```swift
@Environment(\.dismiss) private var dismiss
let onISBNScanned: (ISBNValidator.ISBN) -> Void

public init(onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void) {
    self.onISBNScanned = onISBNScanned
}
```

**Step 4: Add body with placeholder**

```swift
public var body: some View {
    Text("Scanner Placeholder")
        .onAppear {
            print("ISBNScannerView appeared")
        }
}
```

**Step 5: Build to verify no errors**

Run: From worktree root, use XcodeBuildMCP or open in Xcode
```bash
swift build -Xswiftc -sdk -Xswiftc `xcrun --sdk iphonesimulator --show-sdk-path`
```

Expected: Successful compilation

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift
git commit -m "feat: add ISBNScannerView skeleton with capability checks

- VisionKit-based barcode scanner structure
- Static isAvailable check per Apple guidance
- Callback-based architecture for ISBN results

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Create Error State Views

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift`

**Step 1: Add UnsupportedDeviceView component**

Add this before the main `ISBNScannerView` struct:

```swift
@available(iOS 16.0, *)
private struct UnsupportedDeviceView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))

            Text("Barcode Scanning Not Available")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("This device doesn't support the barcode scanner. Please use a device with an A12 Bionic chip or later (iPhone XS/XR+).")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [themeStore.primaryColor.opacity(0.3), themeStore.primaryColor.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
```

**Step 2: Add PermissionDeniedView component**

Add this after UnsupportedDeviceView:

```swift
@available(iOS 16.0, *)
private struct PermissionDeniedView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Please enable camera access in Settings to scan ISBN barcodes.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .foregroundColor(themeStore.primaryColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [themeStore.primaryColor.opacity(0.3), themeStore.primaryColor.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
```

**Step 3: Update ISBNScannerView body to show error states**

Replace the body in `ISBNScannerView`:

```swift
public var body: some View {
    Group {
        if !DataScannerViewController.isSupported {
            UnsupportedDeviceView()
        } else if !DataScannerViewController.isAvailable {
            PermissionDeniedView()
        } else {
            Text("Scanner Active State - Coming Next")
                .foregroundColor(.white)
        }
    }
}
```

**Step 4: Build to verify no errors**

Run: Build command from Task 1 Step 5

Expected: Successful compilation

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift
git commit -m "feat: add error state views for ISBNScannerView

- UnsupportedDeviceView for A12+ chip requirement
- PermissionDeniedView with Settings deep-link
- iOS 26 Liquid Glass design system integration

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Create DataScannerRepresentable

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift`

**Step 1: Add DataScannerRepresentable struct**

Add this before ISBNScannerView:

```swift
@available(iOS 16.0, *)
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onISBNScanned: (ISBNValidator.ISBN) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onISBNScanned: onISBNScanned, dismiss: dismiss)
    }
}
```

**Step 2: Add Coordinator class**

Add this inside DataScannerRepresentable (nested type):

```swift
class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onISBNScanned: (ISBNValidator.ISBN) -> Void
    let dismiss: DismissAction

    init(onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void, dismiss: DismissAction) {
        self.onISBNScanned = onISBNScanned
        self.dismiss = dismiss
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        handleScannedItem(item, dataScanner: dataScanner)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        guard let firstItem = addedItems.first else { return }
        handleScannedItem(firstItem, dataScanner: dataScanner)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: Error) {
        print("📷 Scanner became unavailable: \(error)")
        dismiss()
    }

    private func handleScannedItem(_ item: RecognizedItem, dataScanner: DataScannerViewController) {
        guard case .barcode(let barcode) = item,
              let payload = barcode.payloadStringValue else {
            return
        }

        switch ISBNValidator.validate(payload) {
        case .valid(let isbn):
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            // Stop scanning
            dataScanner.stopScanning()

            // Callback and dismiss
            Task { @MainActor in
                onISBNScanned(isbn)
                dismiss()
            }

        case .invalid:
            // Silently ignore non-ISBN barcodes
            return
        }
    }
}
```

**Step 3: Update ISBNScannerView body to use DataScannerRepresentable**

Replace the else clause in ISBNScannerView body:

```swift
public var body: some View {
    Group {
        if !DataScannerViewController.isSupported {
            UnsupportedDeviceView()
        } else if !DataScannerViewController.isAvailable {
            PermissionDeniedView()
        } else {
            DataScannerRepresentable(onISBNScanned: onISBNScanned)
                .ignoresSafeArea()
        }
    }
}
```

**Step 4: Build to verify no errors**

Run: Build command from Task 1 Step 5

Expected: Successful compilation

**Step 5: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/ISBNScannerView.swift
git commit -m "feat: implement DataScannerViewController integration

- Direct UIViewControllerRepresentable wrapper
- Coordinator with didTapOn and didAdd delegate methods
- ISBN validation using ISBNValidator
- Haptic feedback on successful scan
- Auto-dismiss on scan or error

Per Apple's VisionKit guidance:
- ISBN-specific symbologies (EAN-13, EAN-8, UPC-E)
- Balanced quality level
- Single-item recognition
- All native UI features enabled

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Update SearchView Integration

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/SearchView.swift:168-179`

**Step 1: Replace ModernBarcodeScannerView with ISBNScannerView**

Find the sheet presentation at line 168 and replace:

```swift
// OLD (line 168-179):
.sheet(isPresented: $showingScanner) {
    print("🔍 DEBUG: Sheet is presenting ModernBarcodeScannerView")
    return ModernBarcodeScannerView { isbn in
        print("🔍 DEBUG: ISBN scanned: \(isbn.normalizedValue)")
        // Handle scanned ISBN - set scope to ISBN
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
        #if DEBUG
        updatePerformanceText()
        #endif
    }
}

// NEW:
.sheet(isPresented: $showingScanner) {
    ISBNScannerView { isbn in
        print("📷 ISBN scanned: \(isbn.normalizedValue)")
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
        #if DEBUG
        updatePerformanceText()
        #endif
    }
}
```

**Step 2: Build to verify no errors**

Run: Build command from Task 1 Step 5

Expected: Successful compilation

**Step 3: Commit**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/SearchView.swift
git commit -m "feat: integrate ISBNScannerView into SearchView

- Replace ModernBarcodeScannerView with ISBNScannerView
- Keep existing callback flow unchanged
- Update debug logging prefix

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Remove Deprecated Files

**Files:**
- Delete: `BooksTrackerPackage/Sources/BooksTrackerFeature/ModernBarcodeScannerView.swift`
- Delete: `BooksTrackerPackage/Sources/BooksTrackerFeature/DataScannerView.swift`

**Step 1: Check for references to ModernBarcodeScannerView**

Run:
```bash
grep -r "ModernBarcodeScannerView" BooksTrackerPackage/Sources/ --include="*.swift"
```

Expected: No results (we replaced it in Task 4)

**Step 2: Check for references to DataScannerView**

Run:
```bash
grep -r "DataScannerView" BooksTrackerPackage/Sources/ --include="*.swift" | grep -v ISBNScannerView
```

Expected: No results (old DataScannerView not referenced)

**Step 3: Delete ModernBarcodeScannerView.swift**

Run:
```bash
git rm BooksTrackerPackage/Sources/BooksTrackerFeature/ModernBarcodeScannerView.swift
```

Expected: File removed from git

**Step 4: Delete DataScannerView.swift**

Run:
```bash
git rm BooksTrackerPackage/Sources/BooksTrackerFeature/DataScannerView.swift
```

Expected: File removed from git

**Step 5: Build to verify no breakage**

Run: Build command from Task 1 Step 5

Expected: Successful compilation (no references to deleted files)

**Step 6: Commit**

```bash
git commit -m "refactor: remove deprecated barcode scanner implementations

Removed:
- ModernBarcodeScannerView.swift (replaced by ISBNScannerView)
- DataScannerView.swift (replaced by ISBNScannerView)

Both replaced by single ISBNScannerView that follows
Apple's VisionKit guidance more closely with proper
capability/permission validation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Archive Unused AVFoundation Files (Optional)

**Files:**
- Move: `BooksTrackerPackage/Sources/BooksTrackerFeature/CameraManager.swift` → `_archive/`
- Move: `BooksTrackerPackage/Sources/BooksTrackerFeature/BarcodeDetectionService.swift` → `_archive/`

**Step 1: Check if CameraManager is used elsewhere**

Run:
```bash
grep -r "CameraManager" BooksTrackerPackage/Sources/ --include="*.swift" | grep -v "CameraManager.swift"
```

Expected: If results found, skip archiving (still in use). If no results, proceed.

**Step 2: Check if BarcodeDetectionService is used elsewhere**

Run:
```bash
grep -r "BarcodeDetectionService" BooksTrackerPackage/Sources/ --include="*.swift" | grep -v "BarcodeDetectionService.swift"
```

Expected: If results found, skip archiving (still in use). If no results, proceed.

**Step 3: Create archive directory**

Run:
```bash
mkdir -p BooksTrackerPackage/Sources/BooksTrackerFeature/_archive
```

**Step 4: Move files to archive (if not in use)**

Only run if Step 1 and 2 showed no usage:

```bash
git mv BooksTrackerPackage/Sources/BooksTrackerFeature/CameraManager.swift BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/
git mv BooksTrackerPackage/Sources/BooksTrackerFeature/BarcodeDetectionService.swift BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/
```

**Step 5: Build to verify no breakage**

Run: Build command from Task 1 Step 5

Expected: Successful compilation

**Step 6: Commit (if archived)**

```bash
git commit -m "refactor: archive unused AVFoundation barcode code

Archived (not deleted for reference):
- CameraManager.swift
- BarcodeDetectionService.swift

VisionKit DataScannerViewController handles all camera
management internally. These files kept for reference
but no longer used in barcode scanning flow.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Manual Testing on Physical Device

**Prerequisites:**
- Physical iPhone (iPhone XS/XR or newer for DataScannerViewController support)
- Camera permission granted
- Book with ISBN barcode

**Step 1: Deploy to device**

Use XcodeBuildMCP or Xcode:
```bash
# Option 1: XcodeBuildMCP (if configured)
# See MCP_SETUP.md for device deployment

# Option 2: Xcode
# Open BooksTracker.xcworkspace
# Select your physical device
# Cmd+R to build and run
```

**Step 2: Test scanner opens**

1. Open app
2. Tap Search tab
3. Tap barcode button (top-right toolbar)
4. **Verify:** Sheet presents with camera preview visible

**Step 3: Test barcode detection**

1. Point camera at book ISBN barcode
2. **Verify:** Barcode is highlighted automatically (blue box around it)
3. **Verify:** Guidance labels appear if needed ("Move Closer", etc.)

**Step 4: Test barcode tap**

1. With barcode visible and highlighted
2. Tap the highlighted barcode
3. **Verify:** Haptic feedback (vibration)
4. **Verify:** Scanner dismisses
5. **Verify:** Search results appear for that ISBN

**Step 5: Test invalid barcode**

1. Open scanner again
2. Point at non-ISBN barcode (QR code, product barcode, etc.)
3. **Verify:** Barcode highlighted but nothing happens (silently ignored)

**Step 6: Test permission denied**

1. Go to Settings → BooksTrack → Camera
2. Set to "Never"
3. Return to app and open scanner
4. **Verify:** "Camera Access Required" view shows with Settings button
5. Tap Settings button
6. **Verify:** Opens to BooksTrack settings page

**Step 7: Test pinch-to-zoom**

1. Open scanner with camera permission
2. Pinch to zoom in/out
3. **Verify:** Camera zooms smoothly

**Step 8: Document results**

Create file: `docs/testing/2025-10-30-visionkit-scanner-manual-test.md`

```markdown
# VisionKit Barcode Scanner - Manual Test Results

**Date:** 2025-10-30
**Device:** [iPhone model]
**iOS Version:** [version]
**Tester:** [name]

## Test Results

| Test Case | Expected | Result | Notes |
|-----------|----------|--------|-------|
| Scanner opens | Camera preview visible | ✅ / ❌ | |
| Barcode detection | Auto-highlight | ✅ / ❌ | |
| Barcode tap | Haptic + dismiss + search | ✅ / ❌ | |
| Invalid barcode | Silent ignore | ✅ / ❌ | |
| Permission denied | Error view + Settings button | ✅ / ❌ | |
| Pinch-to-zoom | Smooth zoom | ✅ / ❌ | |
| Guidance labels | "Move Closer" appears | ✅ / ❌ | |

## Issues Found

[List any issues discovered]

## Additional Notes

[Any other observations]
```

**Step 9: Commit test documentation**

```bash
git add docs/testing/2025-10-30-visionkit-scanner-manual-test.md
git commit -m "docs: add VisionKit scanner manual test results

Manual testing on physical device completed.
All core functionality verified.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: Update Documentation

**Files:**
- Modify: `CLAUDE.md` (Barcode Scanning section)

**Step 1: Update CLAUDE.md barcode scanning section**

Find the "Barcode Scanning" section (around line 430) and update:

```markdown
### Barcode Scanning

**Implementation:** VisionKit DataScannerViewController (iOS 16+)

Quick integration in SearchView:
```swift
.sheet(isPresented: $showingScanner) {
    ISBNScannerView { isbn in
        searchScope = .isbn
        searchModel.searchByISBN(isbn.normalizedValue)
    }
}
```

**Features:**
- Apple-native UI (highlighting, guidance, gestures)
- ISBN-specific symbologies (EAN-13, EAN-8, UPC-E)
- Automatic capability/permission validation
- Pinch-to-zoom, tap-to-focus (VisionKit-provided)
- Zero custom camera/Vision code

**Architecture:**
- `ISBNScannerView` - Main scanner view with error states
- `DataScannerRepresentable` - UIViewControllerRepresentable wrapper
- Error states: unsupported device, permission denied, runtime errors

**Requirements:**
- iOS 16.0+
- A12 Bionic chip or later (iPhone XS/XR+)
- Camera permission (NSCameraUsageDescription in Info.plist)

**See:** `docs/plans/2025-10-30-visionkit-barcode-scanner-design.md` for full architecture
```

**Step 2: Build to verify CLAUDE.md is valid markdown**

Run:
```bash
grep -q "ISBNScannerView" CLAUDE.md && echo "✅ Updated" || echo "❌ Not found"
```

Expected: ✅ Updated

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with VisionKit scanner info

- Replace legacy scanner documentation
- Add VisionKit-specific details
- Reference design document

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Success Criteria

✅ **Functionality:**
- [ ] Camera preview displays when scanner opens
- [ ] Barcodes detected and highlighted automatically
- [ ] Valid ISBN triggers search and dismisses scanner
- [ ] Invalid barcodes ignored gracefully
- [ ] Permission denied shows error with Settings button
- [ ] Unsupported devices show clear error message

✅ **Code Quality:**
- [ ] Zero compiler warnings
- [ ] Zero compiler errors
- [ ] Follows Swift 6.2 concurrency patterns
- [ ] iOS 26 HIG compliant

✅ **Documentation:**
- [ ] CLAUDE.md updated
- [ ] Manual test results documented
- [ ] Design document committed

✅ **Cleanup:**
- [ ] Deprecated files removed (ModernBarcodeScannerView, DataScannerView)
- [ ] Optional: Unused AVFoundation files archived

---

## Post-Implementation

After completing all tasks, use **superpowers:finishing-a-development-branch** to merge back to main.
