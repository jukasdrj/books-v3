---
description: Deploy BooksTrack to connected iPhone/iPad using xcodebuild
---

📱 **Physical Device Deployment** 📱

Build, install, and validate BooksTrack on connected iOS device using xcodebuild.

**Tasks:**

1. **Device Discovery**
   - List all connected iOS devices
   - Show device name, model, iOS version, and UUID
   - Verify device is eligible for development builds

2. **Build for Device**
   - Clean build folder
   - Build Release configuration for selected device
   - Report build time and any errors

3. **Install on Device**
   - Install .app bundle on device
   - Verify installation success
   - Report app bundle size

4. **Launch & Monitor**
   - Launch BooksTrack on device
   - Stream device logs in real-time
   - Monitor for crashes, warnings, or errors
   - Check critical features:
     - CSV import with Live Activity
     - Search with space bar input
     - Book metadata editing
     - Enrichment progress

5. **Validation Report**
   - ✅ Build successful
   - ✅ Installation successful
   - ✅ App launches without crash
   - ✅ No critical errors in logs
   - ⚠️ Any warnings or issues found

**Use Case:** Critical for testing real device issues like:
- Space bar input (simulator vs real keyboard)
- Live Activities on Lock Screen
- Camera/barcode scanning
- Hardware-specific performance

If no device is connected, provide instructions for connecting an iPhone via USB.
