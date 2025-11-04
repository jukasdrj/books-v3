# Test Suite API Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all test compilation errors by migrating tests to use current ReadingStatistics struct API and UserLibraryEntry insert-before-relate pattern.

**Architecture:** Update test files to use type-safe struct properties instead of dictionary subscripting, and enforce SwiftData's insert-before-relate lifecycle pattern for all UserLibraryEntry instantiations.

**Tech Stack:** Swift 6.2, Swift Testing framework, SwiftData, XcodeBuildMCP for test execution

---

## Task 1: Fix ReadingStatistics API in LibraryRepositoryTests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/LibraryRepositoryTests.swift:443-446`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/LibraryRepository.swift:5-17` (ReadingStatistics struct definition)

**Step 1: Read the failing test**

Read the current test implementation at lines 440-447 to understand the test logic.

**Step 2: Update test to use struct properties**

Replace dictionary subscript access with direct struct property access:

```swift
// OLD (lines 443-446):
#expect(stats["totalBooks"] as? Int == 3)
#expect(stats["currentlyReading"] as? Int == 2)
#expect(stats["completionRate"] as? Double == (1.0 / 3.0))
#expect(stats["totalPagesRead"] as? Int == 300)

// NEW (replacement):
#expect(stats.totalBooks == 3)
#expect(stats.currentlyReading == 2)
#expect(stats.completionRate == (1.0 / 3.0))
#expect(stats.totalPagesRead == 300)
```

**Step 3: Run tests to verify compilation success**

Run: XcodeBuildMCP test_sim for BooksTracker scheme
Expected: Test should compile (may have logic failures, but no compilation errors on these lines)

**Step 4: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/LibraryRepositoryTests.swift
git commit -m "fix(tests): migrate ReadingStatistics to struct property access

Replace dictionary subscripting with type-safe struct properties in
LibraryRepositoryTests. Aligns with API change from issue #217.

- Remove type casting (as? Int, as? Double)
- Use direct property access (stats.totalBooks, etc.)

Part of issue #224 test suite API migration."
```

---

## Task 2: Fix UserLibraryEntry Initialization in LibraryRepositoryPerformanceTests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift:15,54`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift:56-88` (initializer and factory methods)
- Reference: `CLAUDE.md` - Insert-Before-Relate Lifecycle section

**Step 1: Read the failing test code**

Read lines 10-20 and 50-60 to understand how UserLibraryEntry is being created in performance tests.

**Step 2: Update line 15 to use insert-before-relate pattern**

```swift
// OLD (line 15):
let entry = UserLibraryEntry(work: work, readingStatus: .toRead)

// NEW (replacement):
let entry = UserLibraryEntry(readingStatus: .toRead)
modelContext.insert(entry)  // Gets permanent ID first
entry.work = work           // Set relationship after insert
```

**Step 3: Update line 54 to use insert-before-relate pattern**

```swift
// OLD (line 54):
let entry = UserLibraryEntry(work: work, readingStatus: status)

// NEW (replacement):
let entry = UserLibraryEntry(readingStatus: status)
modelContext.insert(entry)  // Gets permanent ID first
entry.work = work           // Set relationship after insert
```

**Step 4: Add explanatory comment**

Add this comment before the first fix (around line 14):

```swift
// CRITICAL: SwiftData requires insert-before-relate pattern
// See CLAUDE.md "Insert-Before-Relate Lifecycle" section
```

**Step 5: Run tests to verify compilation**

Run: XcodeBuildMCP test_sim for BooksTracker scheme
Expected: LibraryRepositoryPerformanceTests should compile

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift
git commit -m "fix(tests): enforce insert-before-relate in performance tests

Update UserLibraryEntry initialization to follow SwiftData's
insert-before-relate pattern. Prevents 'temporary identifier' crashes.

- Create entry with readingStatus only
- Insert into context (gets permanent ID)
- Set work relationship after insert

Part of issue #224 test suite API migration."
```

---

## Task 3: Fix UserLibraryEntry Initialization in PrimaryEditionTests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Models/PrimaryEditionTests.swift:37,62`
- Reference: `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift:56-64` (initializer default parameters)

**Step 1: Read the failing test code**

Read lines 30-45 and 55-70 to understand the test context.

**Step 2: Update line 37 with proper initialization**

```swift
// OLD (line 37):
let userEntry = UserLibraryEntry()

// NEW (replacement - if setting work relationship):
let userEntry = UserLibraryEntry(readingStatus: .toRead)
modelContext.insert(userEntry)
// If setting work: userEntry.work = work (after insert)
```

**Note:** Check the test context to see if `work` relationship is being set. If yes, add the relationship assignment AFTER insert. If not, just use default initializer with explicit readingStatus.

**Step 3: Update line 62 with proper initialization**

```swift
// OLD (line 62):
let userEntry = UserLibraryEntry()

// NEW (replacement - same pattern as line 37):
let userEntry = UserLibraryEntry(readingStatus: .toRead)
modelContext.insert(userEntry)
// If setting work: userEntry.work = work (after insert)
```

**Step 4: Add explanatory comment if not already present**

If not already added in Task 2, add this comment before the first fix:

```swift
// CRITICAL: SwiftData requires insert-before-relate pattern
// See CLAUDE.md "Insert-Before-Relate Lifecycle" section
```

**Step 5: Run tests to verify compilation**

Run: XcodeBuildMCP test_sim for BooksTracker scheme
Expected: PrimaryEditionTests should compile

**Step 6: Commit**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Models/PrimaryEditionTests.swift
git commit -m "fix(tests): add explicit initialization in PrimaryEditionTests

Add explicit readingStatus parameter and insert-before-relate pattern
for UserLibraryEntry creation in edition tests.

Part of issue #224 test suite API migration."
```

---

## Task 4: Verify Full Test Suite Compilation

**Files:**
- No file modifications
- Validation only

**Step 1: Run full test suite**

Run: XcodeBuildMCP test_sim for BooksTracker scheme with full output
Expected: All tests should compile (no compilation errors)

**Step 2: Analyze test results**

Check test output for:
- ✅ Zero compilation errors
- Count of passed tests
- Count of failed tests (if any failures are logic-based, not compilation)

**Step 3: Document findings**

If compilation succeeds but tests fail:
- Note which tests fail
- Verify failures are logic-based (not API-related)
- Acceptable if pass rate > 95% per design document

If compilation fails:
- Identify remaining compilation errors
- Create additional tasks to fix them
- Repeat Task 4 after fixes

**Step 4: Commit verification results**

No code changes, but document in commit message:

```bash
git commit --allow-empty -m "test: verify full test suite compilation

Validation run after API migration fixes:
- Compilation: [SUCCESS/FAILURE]
- Tests passed: [N]
- Tests failed: [N]
- Pass rate: [X%]

Issue #224 test suite API migration verification."
```

---

## Task 5: Update Issue #224 with Findings

**Files:**
- No file modifications
- GitHub issue update only

**Step 1: Gather evidence**

Collect from previous tasks:
- Test compilation status
- Test pass/fail counts
- Specific errors encountered (if any)

**Step 2: Update issue description**

Update GitHub issue #224 with:

```markdown
## Update: Root Cause Identified

Investigation revealed the actual problem differs from initial report:

**Initial report:** 161 tests crash at runtime accessing `UserLibraryEntry.readingStatus.getter`

**Actual root cause:** Tests fail to compile due to incomplete API migration:
1. ReadingStatistics changed from dictionary to struct (issue #217)
2. UserLibraryEntry initializer removed `work` parameter (insert-before-relate enforcement)

**Files affected:**
- LibraryRepositoryTests.swift (ReadingStatistics API)
- LibraryRepositoryPerformanceTests.swift (UserLibraryEntry init)
- PrimaryEditionTests.swift (UserLibraryEntry init)

**Fix status:** [IN_PROGRESS/COMPLETE]
**Branch:** fix/test-api-migration-224
**Design doc:** docs/plans/2025-11-04-test-suite-api-migration-design.md
```

**Step 3: Add test results**

Append test validation results from Task 4.

**Step 4: No commit needed**

GitHub issue updates are tracked separately.

---

## Task 6: Create Pull Request

**Files:**
- No file modifications
- Pull request creation only

**Step 1: Push branch to remote**

```bash
git push -u origin fix/test-api-migration-224
```

**Step 2: Create PR using gh CLI**

```bash
gh pr create \
  --title "fix(tests): migrate test suite to current APIs (issue #224)" \
  --body "$(cat <<'EOF'
## Summary

Fixes test compilation errors caused by incomplete API migration in issue #223.

## Changes

**Category A: ReadingStatistics API Migration**
- Replace dictionary subscripting with type-safe struct properties
- Remove type casting (`as? Int`, `as? Double`)
- File: `LibraryRepositoryTests.swift`

**Category B: UserLibraryEntry Initialization**
- Enforce insert-before-relate pattern per CLAUDE.md
- Remove deprecated `init(work:readingStatus:)` calls
- Files: `LibraryRepositoryPerformanceTests.swift`, `PrimaryEditionTests.swift`

## Testing

- ✅ All tests compile without errors
- ✅ Test pass rate: [X%] ([N] passed, [M] failed)
- ✅ Follows insert-before-relate pattern
- ✅ Zero warnings policy maintained

## References

- Closes #224
- Related: #223 (partial fix), #217 (ReadingStatistics struct introduction)
- Design: `docs/plans/2025-11-04-test-suite-api-migration-design.md`
EOF
)"
```

**Step 3: Verify PR created**

Check PR URL in output and verify it links correctly to issue #224.

**Step 4: No commit needed**

PR creation tracked in GitHub.

---

## Success Criteria

**Compilation:**
- [ ] Zero compilation errors in test suite
- [ ] All tests execute (no crashes during test run)

**Test Quality:**
- [ ] Test pass rate > 95%
- [ ] Failed tests are logic-based only (not API-related)
- [ ] All UserLibraryEntry creations follow insert-before-relate

**Documentation:**
- [ ] Code comments explain insert-before-relate pattern
- [ ] Issue #224 updated with root cause findings
- [ ] PR created with comprehensive description

**Code Quality:**
- [ ] Zero warnings (maintains project policy)
- [ ] Follows Swift 6.2 concurrency standards
- [ ] DRY principle maintained (no code duplication)

---

## Rollback Plan

If unexpected issues arise during implementation:

1. **Branch preservation:** `fix/test-api-migration-224` remains for analysis
2. **Revert to main:** `git worktree remove .worktrees/fix-test-api-migration`
3. **Reassess approach:** Review design doc, create new plan if needed
4. **Alternative:** Consider adding deprecated convenience initializers with warnings

---

## References

- **CLAUDE.md:** Insert-Before-Relate Lifecycle (critical SwiftData pattern)
- **Design doc:** `docs/plans/2025-11-04-test-suite-api-migration-design.md`
- **ReadingStatistics struct:** `LibraryRepository.swift:5-17`
- **UserLibraryEntry init:** `UserLibraryEntry.swift:56-88`
- **Issue #224:** Runtime test failures (actual: compilation errors)
- **Issue #223:** Test compilation errors (partial fix)
- **Issue #217:** ReadingStatistics performance optimization (struct introduction)
