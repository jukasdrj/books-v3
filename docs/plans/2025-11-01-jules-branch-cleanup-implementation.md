# Jules Branch Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up 19 stale Jules branches, archive commit SHAs for recovery, and validate the remaining branch for Issue #141.

**Architecture:** Script-based branch cleanup with safety checks (archive → audit → dry-run → delete → verify). Manual review of `add-cover-selection-tests` branch for test quality.

**Tech Stack:** Git, GitHub CLI (gh), Bash scripting

---

## Task 1: Archive All Branch Commit SHAs

**Files:**
- Create: `.branch-archive-2025-11-01.txt`

**Step 1: Generate branch archive file**

Run:
```bash
git show-ref | grep "refs/remotes/origin" > .branch-archive-2025-11-01.txt
```

Expected: File created with all remote branch refs and SHAs

**Step 2: Verify archive contents**

Run:
```bash
wc -l .branch-archive-2025-11-01.txt
grep "add-cover-selection-tests" .branch-archive-2025-11-01.txt
```

Expected:
- 30+ lines (all remote branches)
- One line with `add-cover-selection-tests` ref

**Step 3: Commit archive to git**

Run:
```bash
git add .branch-archive-2025-11-01.txt
git commit -m "Archive Jules branch commits before cleanup

Safety measure: All branch SHAs saved for potential recovery.
Cleanup plan: docs/plans/2025-11-01-jules-branch-cleanup-design.md"
```

Expected: Commit created with archive file

**Step 4: Push archive to remote**

Run:
```bash
git push origin main
```

Expected: Archive now on GitHub (recovery safety net)

---

## Task 2: Audit Category B Branches (Already Merged)

**Files:**
- None (verification only)

**Step 1: Check fix/phase1-test-suite-cleanup merge status**

Run:
```bash
git log main..origin/fix/phase1-test-suite-cleanup --oneline
```

Expected: Empty output (work is in main)

**Step 2: Check feature/jules-code-review-fixes merge status**

Run:
```bash
git log main..origin/feature/jules-code-review-fixes --oneline
```

Expected: Empty output (work is in main)

**Step 3: Document Category B findings**

Run:
```bash
echo "Category B (Already Merged) - Verified:
- fix/phase1-test-suite-cleanup → 0 unique commits (in main)
- feature/jules-code-review-fixes → 0 unique commits (in main)
" > category-b-audit.txt
```

Expected: Audit file created

---

## Task 3: Create Deletion List

**Files:**
- Create: `branches-to-delete.txt`

**Step 1: Generate full deletion list**

Create file with all 19 branches:
```bash
cat > branches-to-delete.txt <<'EOF'
fix/phase1-test-suite-cleanup
feature/jules-code-review-fixes
feat/optimize-edition-selection
feat/add-swiftlint-concurrency-rules
feature/isbn-scanner-error-alert
fix/genre-normalization-comment
fix/redundant-logging
fix/remove-empty-update-performance-text
fix/search-model-tests-migration
refactor-confidence-thresholds
refactor-pan-zoom-gestures
refactor-search-handlers
refactor/primary-edition-strategy
refactor/quality-scoring-helper
refactor/single-pass-search-handlers
feat/edge-caching-book-covers
feature/robust-work-cache
feature/batch-enrichment
feature/manual-book-matching
EOF
```

Expected: File with 19 branch names

**Step 2: Verify count**

Run:
```bash
wc -l branches-to-delete.txt
```

Expected: 19 lines

**Step 3: Verify no kept branches in list**

Run:
```bash
grep "add-cover-selection-tests" branches-to-delete.txt
```

Expected: Empty output (add-cover-selection-tests NOT in deletion list)

---

## Task 4: Dry-Run Deletion

**Files:**
- None (verification only)

**Step 1: Test deletion without executing**

Run:
```bash
xargs -I {} git push origin --delete --dry-run {} < branches-to-delete.txt
```

Expected: Dry-run output showing 19 branches would be deleted, no errors

**Step 2: Verify remote branches still exist**

Run:
```bash
git ls-remote --heads origin | grep -E "(feat/edge-caching|feature/batch-enrichment)" | wc -l
```

Expected: 2 (branches still exist after dry-run)

**Step 3: Document dry-run success**

Run:
```bash
echo "✅ Dry-run successful - 19 branches verified for deletion" >> category-b-audit.txt
```

---

## Task 5: Execute Branch Deletion

**Files:**
- None (remote operation)

**Step 1: Delete all 19 branches**

Run:
```bash
xargs -I {} git push origin --delete {} < branches-to-delete.txt
```

Expected: 19 deletion confirmations from GitHub

**Step 2: Verify deletions**

Run:
```bash
git fetch --prune
git branch -r | grep -E "origin/(feat|feature|fix|refactor|add-)" | wc -l
```

Expected: 1 (only add-cover-selection-tests remains)

**Step 3: Confirm kept branch exists**

Run:
```bash
git branch -r | grep "add-cover-selection-tests"
```

Expected: `origin/add-cover-selection-tests` (still exists)

**Step 4: Document deletion results**

Run:
```bash
cat > cleanup-summary.txt <<EOF
Jules Branch Cleanup Results - $(date +%Y-%m-%d)

Deleted Branches (19):
- Category B (merged): 2 branches
- Category C (no issue): 13 branches
- Category D (reimplementing): 4 branches

Kept Branches (1):
- add-cover-selection-tests (Issue #141)

Archive Location: .branch-archive-2025-11-01.txt
Design Doc: docs/plans/2025-11-01-jules-branch-cleanup-design.md
EOF
cat cleanup-summary.txt
```

**Step 5: Commit cleanup summary**

Run:
```bash
git add cleanup-summary.txt category-b-audit.txt branches-to-delete.txt
git commit -m "Complete Jules branch cleanup - 19 branches deleted

Kept: add-cover-selection-tests (Issue #141)
Deleted: 19 stale/duplicate branches (see cleanup-summary.txt)

All branch SHAs archived in .branch-archive-2025-11-01.txt"
git push origin main
```

---

## Task 6: Review Issue #141 Branch

**Files:**
- None (checkout and review only)

**Step 1: Fetch and checkout Jules' test branch**

Run:
```bash
git fetch origin add-cover-selection-tests
git checkout add-cover-selection-tests
```

Expected: On branch `add-cover-selection-tests`

**Step 2: Identify test files**

Run:
```bash
git diff main --name-only | grep -i test
```

Expected: List of test files added/modified (likely `*CoverSelection*Tests.swift`)

**Step 3: Review test file structure**

Run:
```bash
# Find the main test file
test_file=$(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1)
echo "Test file: $test_file"

# Show test structure
grep -E "@Test|@Suite" "$test_file" | head -20
```

Expected: List of test suites and test methods

**Step 4: Count test methods**

Run:
```bash
test_file=$(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1)
grep -c "@Test" "$test_file" || echo "0"
```

Expected: 10+ test methods (comprehensive coverage)

**Step 5: Check for edge cases**

Run:
```bash
test_file=$(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1)
grep -iE "(nil|empty|error|invalid)" "$test_file" | wc -l
```

Expected: 5+ lines (testing edge cases)

**Step 6: Run tests**

Run:
```bash
# Use MCP test command if available, else xcodebuild
swift test --filter CoverSelection 2>&1 | grep -E "(Test Suite|passed|failed)"
```

Expected: All tests pass

**Step 7: Document review findings**

Run:
```bash
cat > issue-141-review.txt <<EOF
Issue #141 Branch Review - add-cover-selection-tests

Date: $(date +%Y-%m-%d)
Branch: add-cover-selection-tests
Status: PENDING_REVIEW

Test File: $(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1)
Test Count: $(grep -c "@Test" $(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1) || echo "0")

Edge Case Coverage:
$(grep -iE "(nil|empty|error|invalid)" $(git diff main --name-only | grep -i "CoverSelection.*Tests.swift" | head -1) | head -5)

Test Results:
[MANUAL: Run tests and paste results here]

Decision:
[ ] MERGE - Tests comprehensive and passing
[ ] ENHANCE - Tests pass but need more coverage
[ ] REWRITE - Tests fail or insufficient coverage

Next Steps:
If MERGE: Create PR for add-cover-selection-tests
If ENHANCE: Add missing test cases, then create PR
If REWRITE: Implement Issue #141 ourselves (2 days)
EOF
cat issue-141-review.txt
```

**Step 8: Return to main branch**

Run:
```bash
git checkout main
git add issue-141-review.txt
git commit -m "Review Issue #141 branch (add-cover-selection-tests)

Findings documented in issue-141-review.txt
Decision pending based on test quality assessment"
git push origin main
```

---

## Task 7: Save Results to OpenMemory

**Files:**
- None (memory operation)

**Step 1: Document cleanup completion**

Create memory entry with results:

```
Jules Branch Cleanup COMPLETE (2025-11-01):

✅ EXECUTED: Branch cleanup following surgical approach
- Deleted: 19 branches (2 merged, 13 no issue, 4 reimplementing)
- Kept: 1 branch (add-cover-selection-tests for Issue #141)
- Archive: .branch-archive-2025-11-01.txt (all SHAs saved)

RESULTS:
- Category B (merged): fix/phase1-test-suite-cleanup, feature/jules-code-review-fixes
- Category C (no issue): 13 refactor/fix branches without tracked issues
- Category D (reimplementing): edge-caching, robust-work-cache, batch-enrichment, manual-book-matching

NEXT STEPS:
1. Review Issue #141 branch test quality (findings in issue-141-review.txt)
2. Create PR if tests pass OR enhance if incomplete
3. Begin Phase 2A (Issue #143 - Batch Enrichment) after #141 resolved

TIMELINE: 2-3 hours actual (as estimated)
```

**Step 2: Verify memory saved**

Check that cleanup results are documented for future reference.

---

## Verification Checklist

After completing all tasks:

- [ ] `.branch-archive-2025-11-01.txt` committed to main
- [ ] 19 branches deleted from remote
- [ ] Only `add-cover-selection-tests` remains in Jules branches
- [ ] `cleanup-summary.txt` documents all deletions
- [ ] Issue #141 branch reviewed (findings in `issue-141-review.txt`)
- [ ] All cleanup artifacts committed to git
- [ ] OpenMemory updated with results

## Success Criteria

**Branch Cleanup:**
- ✅ Zero stale branches remaining (except add-cover-selection-tests)
- ✅ All branch SHAs archived for recovery
- ✅ Clean git branch list verified

**Documentation:**
- ✅ Cleanup summary committed
- ✅ Category B audit completed
- ✅ Issue #141 review documented

**Next Actions:**
- Issue #141: Create PR or enhance based on test review
- Phase 2A: Begin Issue #143 implementation after #141 resolved

---

**Total Estimated Time:** 2-3 hours
**Actual Time:** [TO BE FILLED DURING EXECUTION]

🤖 Generated with Claude Code using superpowers:writing-plans skill
