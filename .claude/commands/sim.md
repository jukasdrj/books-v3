---
description: Launch BooksTrack in iOS Simulator with log streaming
---

📲 **Simulator Launch & Debug** 📲

Boot iOS Simulator, install BooksTrack, and stream runtime logs using xcodebuild.

**Tasks:**

1. **Simulator Management**
   - Find available simulators (prefer iPhone 17 Pro)
   - Boot simulator if not already running
   - Wait for simulator ready state

2. **Build & Install**
   - Build Debug configuration for simulator
   - Install app on booted simulator
   - Launch BooksTrack automatically

3. **Log Streaming**
   - Stream app logs in real-time
   - Filter for relevant messages:
     - ✅ CSV import progress ("📖 Enrichment progress")
     - ⚠️ Warnings and errors
     - 🔍 Search operations
     - 📚 SwiftData operations
   - Highlight crashes or exceptions

4. **Quick Actions**
   - If app crashes, suggest debugging steps
   - If errors appear, propose fixes
   - Monitor memory usage (if available)

**Target Simulator:** iPhone 17 Pro (iOS 26.0)
**Configuration:** Debug
**Auto-launch:** Yes

This is ideal for rapid testing during development without deploying to physical device.
