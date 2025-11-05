# Privacy Strings Required for Bookshelf Scanner

## NSPhotoLibraryUsageDescription

**Location:** Add to your app's `Info.plist` (or configure in Xcode target settings)

**Key:** `NSPhotoLibraryUsageDescription`

**Recommended String:**
```
BooksTrack analyzes bookshelf photos on your device to detect book titles and ISBNs. No photos are uploaded to servers.
```

**Why This Is Needed:**
- PhotosPicker requires this privacy description (even though it doesn't directly access Photo Library)
- App Store Connect may reject builds without it
- Provides transparency to users about photo usage

## NSCameraUsageDescription (Future Phase 2)

**Key:** `NSCameraUsageDescription`

**Recommended String:**
```
BooksTrack uses your camera to scan book spines and barcodes, making it faster to add books to your library. All analysis happens on your device.
```

**When Needed:**
- Phase 2 when implementing camera-based live scanning
- Currently NOT needed (Phase 1 uses PhotosPicker only)

---

## How to Add in Xcode

1. Open BooksTracker.xcworkspace
2. Select "BooksTracker" target
3. Go to "Info" tab
4. Click "+" under "Custom iOS Target Properties"
5. Add key: "Privacy - Photo Library Usage Description"
6. Add value: (use string above)

---

## Testing Privacy Disclosure

**Before First Photo Selection:**
1. User taps "Select Bookshelf Photos"
2. System shows Photo Picker permission prompt with your description
3. User grants/denies access

**Privacy Banner in App:**
- Already implemented in `BookshelfScannerView.swift`
- Shows "Analysis happens on this iPhone. Photos are not uploaded."
- Visible BEFORE PhotosPicker appears (HIG compliance ✅)

---

Generated: October 2025
Phase: 1C-1E Implementation
