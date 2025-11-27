---
description: Run Swift tests using xcodebuild
---

🧪 **Swift Test Suite Runner** 🧪

Execute BooksTrackerPackage test suite using xcodebuild and provide detailed failure analysis.

**Tasks:**
1. Run Swift Testing suite in BooksTrackerPackage
2. Report test execution summary (passed/failed/skipped)
3. For any failures:
   - Show test name and failure reason
   - Display relevant code context
   - Suggest potential fixes
4. Check test coverage (if available)
5. Verify critical tests:
   - CSV parsing and import
   - Enrichment service
   - Search functionality
   - SwiftData model relationships

**Package Path:** BooksTrackerPackage/
**Test Framework:** Swift Testing (@Test macros)
**Expected Coverage:** 90%+

If tests fail, propose fixes and offer to implement them immediately.
