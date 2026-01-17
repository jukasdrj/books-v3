---
description: Quick build validation using xcodebuild + xcsift
---

🔨 **Quick Build Check** 🔨

Use xcodebuild piped through xcsift to build BooksTracker.xcworkspace and parse errors/warnings.

**Tasks:**
1. Build for iPhone 17 Pro simulator (Debug configuration)
2. Pipe output through `xcsift --warnings` for structured error/warning parsing
3. Report build status with:
   - File paths and line numbers for direct navigation
   - Categorized warnings (compile, SwiftUI, runtime)
   - Linker errors with symbol names
   - Build time and slowest targets
4. Suggest fixes for any errors found
5. If build succeeds, confirm "✅ Build passed - ready for testing!"

**Command Pattern:**
```bash
xcodebuild -workspace BooksTracker.xcworkspace \
  -scheme BooksTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build \
  2>&1 | xcsift --warnings --build-info
```

**Workspace:** BooksTracker.xcworkspace
**Scheme:** BooksTracker
**Destination:** iPhone 17 Pro (Simulator)
**Configuration:** Debug

**xcsift Benefits:**
- Structured JSON output for easy parsing
- Automatic error/warning categorization
- Deduplication of identical issues
- File:line navigation format
- Build timing metrics

This is for rapid iteration during development.
