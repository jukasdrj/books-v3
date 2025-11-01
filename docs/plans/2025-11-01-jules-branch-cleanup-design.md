# Jules Branch Cleanup & Issue Resolution Plan

**Date:** November 1, 2025
**Status:** Design Approved
**Timeline:** 2-3 hours cleanup + 2-3 weeks implementation

## Problem Statement

Jules (Google Labs AI) created **20 branches** to resolve GitHub issues. Many issues are now closed (#181, #180, #59, #31, #61), and some branches may contain duplicate or merged work. We need a systematic plan to:

1. Clean up stale/merged branches
2. Determine which branches to keep vs delete
3. Resolve remaining 6 open issues efficiently

## Current State

### Open Issues (6)
- **#185** - CI: GitHub Actions compatibility (low priority, wait for upstream)
- **#168** - Store PersistentIdentifier in workCache (medium priority)
- **#147** - Edge Caching for Book Covers (high priority)
- **#143** - Batch Enrichment API Support (medium priority)
- **#141** - Cover Selection Test Suite (medium priority)
- **#109** - Manual User Matching for CSV/Scans (medium priority)

### Jules Branches (20)
```
add-cover-selection-tests
feat/add-swiftlint-concurrency-rules
feat/edge-caching-book-covers
feat/optimize-edition-selection
feature/batch-enrichment
feature/isbn-scanner-error-alert
feature/jules-code-review-fixes
feature/manual-book-matching
feature/robust-work-cache
fix/genre-normalization-comment
fix/phase1-test-suite-cleanup
fix/redundant-logging
fix/remove-empty-update-performance-text
fix/search-model-tests-migration
refactor-confidence-thresholds
refactor-pan-zoom-gestures
refactor-search-handlers
refactor/primary-edition-strategy
refactor/quality-scoring-helper
refactor/single-pass-search-handlers
```

### Merged PRs (Context)
- **PR #184** - Phase 1 test suite cleanup (merged)
- 25+ other merged PRs with various feature branches

## Design Decision: Surgical Cleanup Approach

### Strategy Selection

We evaluated 3 approaches:

1. **Surgical Cleanup** ✅ SELECTED
   - Audit each branch individually
   - Delete duplicates and merged work
   - Keep Jules' #141 branch (test suite)
   - Implement #147/#168/#143/#109 ourselves
   - **Timeline:** 2-3 days
   - **Risk:** Low (conservative, thorough)

2. **Aggressive Purge** ❌ REJECTED
   - Delete ALL Jules branches
   - Implement all 6 issues from scratch
   - **Timeline:** 1-2 weeks
   - **Risk:** High (lose potentially good work)

3. **Hybrid Merge-First** ❌ REJECTED
   - Create PRs for all 5 key branches
   - Merge if tests pass, else implement ourselves
   - **Timeline:** 3-5 days
   - **Risk:** Medium (code review overhead, potential bad merges)

### Decision Criteria

**Deletion Criteria:**
- ✅ Branch work already merged to main (verified via git diff)
- ✅ Duplicate functionality (multiple branches for same issue)
- ❌ Age over 30 days (NOT a criterion - focus on duplicates/merged)
- ❌ No matching open issue (NOT automatic deletion - case-by-case)

**Implementation Decision:**
- **Use Jules:** Issue #141 (test suite only, low risk)
- **Implement ourselves:** Issues #147, #168, #143, #109 (code review flagged critical bugs, complex dependencies)

## Branch Classification

### Category A - Keep & Use (1 branch)
**Criteria:** Maps to open issue, low risk, no critical bugs

- `add-cover-selection-tests` → Issue #141
  - **Reason:** Test suite only, no production code changes
  - **Action:** Review locally, create PR if tests pass
  - **Timeline:** 2-3 hours

### Category B - Delete - Already Merged (2+ branches)
**Criteria:** Work exists in main via different PR

- `fix/phase1-test-suite-cleanup` → Merged in PR #184
- `feature/jules-code-review-fixes` → Merged (verify via git log)
- **Action:** Verify with `git log main..origin/<branch>`, delete if empty
- **Timeline:** 30 minutes audit + 5 minutes deletion

### Category C - Delete - No Open Issue (13+ branches)
**Criteria:** No matching open issue OR issue is closed

- `feat/optimize-edition-selection` → No matching open issue
- `feat/add-swiftlint-concurrency-rules` → Issue #59 closed
- `feature/isbn-scanner-error-alert` → No open issue
- `fix/genre-normalization-comment` → Minor fix, likely covered
- `fix/redundant-logging` → Minor fix, likely covered
- `fix/remove-empty-update-performance-text` → Minor fix
- `fix/search-model-tests-migration` → Handled in PR #184
- `refactor-confidence-thresholds` → General refactor, no issue
- `refactor-pan-zoom-gestures` → General refactor, no issue
- `refactor-search-handlers` → General refactor, no issue
- `refactor/primary-edition-strategy` → General refactor, no issue
- `refactor/quality-scoring-helper` → General refactor, no issue
- `refactor/single-pass-search-handlers` → General refactor, no issue

**Action:** Delete all (work not tied to tracked requirements)
**Timeline:** 5 minutes deletion

### Category D - Delete - Will Implement Ourselves (4 branches)
**Criteria:** Code review flagged critical bugs OR complex dependencies

- `feat/edge-caching-book-covers` → Issue #147
  - **Reason:** Breaking change risk (coverImageURL DTO changes), R2 + Image Resizing complexity
  - **Code Review Finding:** Non-breaking approach required (add `coverImageProxyURL` field)

- `feature/robust-work-cache` → Issue #168
  - **Reason:** Cache mutation bug (modifying dict during iteration)
  - **Code Review Finding:** Needs batch removal pattern + comprehensive tests

- `feature/batch-enrichment` → Issue #143
  - **Reason:** TODO stubs incomplete (batch-enrichment.js:56-59)
  - **Code Review Finding:** Needs actual enrichment logic implementation

- `feature/manual-book-matching` → Issue #109
  - **Reason:** Missing @Bindable pattern, incomplete UX spec
  - **Code Review Finding:** Needs detailed interaction flow + push navigation

**Action:** Delete all, implement fresh following Phase 2 plan
**Timeline:** 5 minutes deletion

## Deletion Workflow

### Step 1: Archive Branch SHAs
```bash
# Save all branch commits before deletion (recovery safety net)
git show-ref | grep "refs/remotes/origin" > .branch-archive-2025-11-01.txt
git add .branch-archive-2025-11-01.txt
git commit -m "Archive Jules branch commits before cleanup"
```

### Step 2: Audit & Verify Merge Status
```bash
# For each Category B candidate:
for branch in fix/phase1-test-suite-cleanup feature/jules-code-review-fixes; do
  commits=$(git log main..origin/$branch --oneline | wc -l)
  echo "$branch: $commits unique commits"
  if [ "$commits" -eq 0 ]; then
    echo "✅ Safe to delete (work in main)"
  else
    echo "⚠️  Review needed (has unique commits)"
  fi
done
```

### Step 3: Dry-Run Deletion
```bash
# Test deletion without actually deleting
git push origin --delete --dry-run \
  fix/phase1-test-suite-cleanup \
  feature/jules-code-review-fixes \
  feat/optimize-edition-selection \
  feat/add-swiftlint-concurrency-rules \
  feature/isbn-scanner-error-alert \
  fix/genre-normalization-comment \
  fix/redundant-logging \
  fix/remove-empty-update-performance-text \
  fix/search-model-tests-migration \
  refactor-confidence-thresholds \
  refactor-pan-zoom-gestures \
  refactor-search-handlers \
  refactor/primary-edition-strategy \
  refactor/quality-scoring-helper \
  refactor/single-pass-search-handlers \
  feat/edge-caching-book-covers \
  feature/robust-work-cache \
  feature/batch-enrichment \
  feature/manual-book-matching
```

### Step 4: Execute Deletion
```bash
# Remove --dry-run flag and execute
git push origin --delete \
  <all 19 branches from dry-run>
```

### Step 5: Verify Cleanup
```bash
# Should only show: add-cover-selection-tests
git branch -r | grep -E "origin/(feat|feature|fix|refactor|add-)"
```

### Step 6: Document Results
```bash
# Save deletion record to OpenMemory
echo "Deleted 19 Jules branches on 2025-11-01:
- Category B (merged): 2 branches
- Category C (no issue): 13 branches
- Category D (reimplementing): 4 branches
- Kept: add-cover-selection-tests (Issue #141)
" > branch-cleanup-summary.txt
```

## Issue Resolution Plan

### Issue #141 - Cover Selection Tests (Use Jules)
**Branch:** `add-cover-selection-tests`

**Validation Steps:**
1. Checkout branch locally: `git checkout add-cover-selection-tests`
2. Review test coverage:
   - Check for edge cases (nil covers, empty arrays, quality scoring)
   - Verify test naming follows Swift Testing conventions
   - Ensure @MainActor isolation correct
3. Run tests: `swift test` or `/test` MCP command
4. Code review: Check for comprehensive coverage (target: 90%+)

**Decision Tree:**
- ✅ Tests pass + coverage >80% → Create PR and merge
- ⚠️ Tests pass + coverage <80% → Enhance tests, then merge
- ❌ Tests fail → Investigate, fix, or rewrite

**Timeline:** 2-3 hours

---

### Issue #185 - CI Compatibility (Wait)
**Action:** Monitor GitHub Actions runner updates

**No immediate work:**
- GitHub typically adds new Xcode within 2-4 weeks of release
- Current workaround (Swift 6.0, iOS 18) is functional
- Not blocking development

**Acceptance Criteria:**
- [ ] GitHub Actions supports Xcode 16.2+ (Swift 6.2)
- [ ] Restore Package.swift to swift-tools-version: 6.2
- [ ] Restore Package.swift to platforms: [.iOS(.v26)]
- [ ] Update CI workflow to use iPhone 17 Pro Max

**Monitoring:** https://github.com/actions/runner-images/releases

---

### Issues #147, #168, #143, #109 - Implement Ourselves

**Follow Phase 2 Plan (Sequential Execution):**

#### **Phase 2A: Issue #143 - Batch Enrichment (Week 1)**
- Delete `feature/batch-enrichment` branch
- Complete TODO stubs in `batch-enrichment.js:56-59`
- Implement actual enrichment service integration
- Stress-test DTOMapper workCache under concurrent load
- **Timeline:** 1 week

#### **Phase 2B: Issue #168 - PID Caching (After 2A)**
- Delete `feature/robust-work-cache` branch
- Implement batch removal pattern (no mutation during iteration)
- Add comprehensive test suite (cache eviction, concurrent access, context teardown)
- Validate against batch enrichment patterns from Phase 2A
- **Timeline:** 2-3 days

#### **Phase 2C: Issue #147 - Edge Caching (Parallel with 2B)**
- Delete `feat/edge-caching-book-covers` branch
- Implement R2-only MVP (no Image Resizing initially)
- Add non-breaking `coverImageProxyURL` field to EditionDTO
- Configure wrangler.toml with BOOK_COVERS R2 bucket
- **Timeline:** 3-4 days

#### **Phase 3A: Issue #141 - Cover Tests (If Needed)**
- Only if Jules' branch insufficient
- Write comprehensive test suite
- **Timeline:** 2 days (fallback only)

#### **Phase 3B: Issue #109 - Manual Matching (After 3A)**
- Delete `feature/manual-book-matching` branch
- Design full UX flow (3 entry points: Review Queue, CSV Import, WorkDetailView)
- Implement ManualMatchView with @Bindable pattern
- Use push navigation (not sheets)
- **Timeline:** 2-3 days

**Total Implementation Timeline:** 2-3 weeks

## Execution Checklist

### Today: Branch Cleanup (2-3 hours)
- [ ] Archive branch SHAs to `.branch-archive-2025-11-01.txt`
- [ ] Audit all 20 branches (verify merge status, map to issues)
- [ ] Create deletion list (19 branches)
- [ ] Run dry-run deletion
- [ ] Execute remote branch deletion
- [ ] Verify only `add-cover-selection-tests` remains
- [ ] Document results in OpenMemory
- [ ] Commit branch archive to git

### This Week: Issue #141 (2-3 hours)
- [ ] Checkout `add-cover-selection-tests` locally
- [ ] Review test coverage and quality
- [ ] Run test suite, verify all pass
- [ ] Create PR if tests good OR enhance if incomplete
- [ ] Merge and close Issue #141

### Next 2-3 Weeks: Phase 2 Implementation
- [ ] Phase 2A: Implement #143 (Batch Enrichment)
- [ ] Phase 2B: Implement #168 (PID Caching)
- [ ] Phase 2C: Implement #147 (Edge Caching)
- [ ] Phase 3B: Implement #109 (Manual Matching)

## Success Metrics

**Branch Cleanup:**
- ✅ Zero stale branches (only active work remains)
- ✅ All branch commits archived for recovery
- ✅ Clean git branch list (1 Jules branch max)

**Issue Resolution:**
- ✅ All 6 open issues resolved
- ✅ Zero warnings policy maintained
- ✅ Code review validation on all implementations
- ✅ Comprehensive test coverage (>80%)

## Risk Mitigation

**Risk:** Deleting branch with unmerged valuable work
**Mitigation:** Archive all SHAs before deletion, can recover from `.branch-archive-2025-11-01.txt`

**Risk:** Jules' #141 tests insufficient
**Mitigation:** Fallback plan to enhance or rewrite tests (2 days buffer)

**Risk:** Phase 2 implementations take longer than estimated
**Mitigation:** Sequential execution allows reprioritization, can defer #109 if needed

**Risk:** Breaking changes in production
**Mitigation:** All Phase 2 work follows code-reviewer agent validation, non-breaking DTO changes

## References

- **Phase 1 Plan:** PR #184 completion notes
- **Code Review Findings:** Phase 1 code-reviewer agent output
- **Issue Priority Analysis:** OpenMemory (2025-11-01)
- **Original 3-Phase Plan:** Phase 2 design from earlier session

---

**Document Status:** ✅ Design Approved
**Next Step:** Execute branch cleanup today
**Owner:** Justin Gardner

🤖 Generated with Claude Code using superpowers:brainstorming skill
