---
description: Run Swift tests using xcodebuild + xcsift
---

🧪 **Swift Test Suite Runner** 🧪

Execute BooksTrackerPackage test suite using xcodebuild piped through xcsift for detailed failure analysis.

**Tasks:**
1. Run Swift Testing suite in BooksTrackerPackage
2. Pipe through `xcsift --coverage --slow-threshold 1.0` for structured output
3. Report test execution summary:
   - Passed/failed/skipped counts
   - Slow tests (>1.0s threshold)
   - Code coverage percentage
4. For any failures:
   - Show test name and failure reason with file:line references
   - Display relevant code context
   - Suggest potential fixes
5. Verify critical tests:
   - CSV parsing and import
   - Enrichment service
   - Search functionality
   - SwiftData model relationships

**Command Pattern:**
```bash
xcodebuild test \
  -workspace BooksTracker.xcworkspace \
  -scheme BooksTrackerPackage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enableCodeCoverage YES \
  2>&1 | xcsift --coverage --slow-threshold 1.0
```

**Package Path:** BooksTrackerPackage/
**Test Framework:** Swift Testing (@Test macros)
**Expected Coverage:** 90%+

**xcsift Benefits:**
- Automatic code coverage conversion (.xcresult → JSON)
- Slow test detection (flag tests >1.0s)
- Flaky test tracking
- Structured test failure output with file:line navigation

If tests fail, propose fixes and offer to implement them immediately.
