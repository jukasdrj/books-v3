---
description: Comprehensive review of all open work items (GitHub issues, PRs, TODOs, planning files) with prioritization and actionable recommendations
user-invocable: true
model: sonnet
context: main
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---

# Work Review Skill

## Purpose

Provides a complete snapshot of all outstanding work across the project by aggregating:
- Open GitHub issues with labels and status
- Open pull requests
- TODO.md items
- CURRENT-STATUS.md active issues
- Unfinished planning files (task_plan.md, findings.md, progress.md)
- Any other tracked work items

Organizes findings by priority and provides actionable recommendations for what to tackle next.

## When to Use

- Starting a new work session to understand priorities
- Weekly/monthly planning and review
- After completing major features to assess next steps
- When context-switching between tasks
- Before proposing new work to understand current load

## Skill Workflow

### Phase 1: Discovery (5 min)

1. **GitHub Issues & PRs**
   - Query open issues with `gh issue list`
   - Query open PRs with `gh pr list`
   - Extract labels, status, last update timestamps
   - Note any stale items (>30 days without update)

2. **Repository Documentation**
   - Read `TODO.md` for roadmap items
   - Read `docs/CURRENT-STATUS.md` for active work
   - Check for completion status and blocking issues

3. **Planning Artifacts**
   - Find all `task_plan.md` files
   - Find all `findings.md` and `progress.md` files
   - Identify incomplete planning sessions:
     - task_plan.md exists but progress.md shows incomplete
     - findings.md with open questions
     - Any "IN PROGRESS" or "BLOCKED" status markers

4. **Other Work Trackers**
   - Check for any `.planning/` directory files
   - Look for `docs/planning/` items
   - Identify any experimental or draft work

### Phase 2: Analysis (5 min)

1. **Categorize by Status**
   - **Active**: Currently being worked on
   - **Blocked**: Waiting on dependencies
   - **Ready**: All prerequisites met, can start immediately
   - **Backlog**: Planned but not prioritized
   - **Stale**: No activity >30 days, may need closure

2. **Assess Priority**
   Use labels and content to determine:
   - **P0 - Critical**: Security, data integrity, production outages
   - **P1 - High**: Core features, performance issues, user-facing bugs
   - **P2 - Medium**: Enhancements, technical debt, documentation
   - **P3 - Low**: Nice-to-haves, future optimizations

3. **Identify Dependencies**
   - Note which issues block others
   - Identify prerequisite work
   - Flag items waiting on external factors

4. **Calculate Effort Estimates**
   - **Quick wins** (<2 hours): Small fixes, documentation
   - **Medium effort** (1-3 days): Features, integrations
   - **Large effort** (1-2 weeks): Epics, major refactors

### Phase 3: Organization & Reporting (5 min)

Generate structured report with:

1. **Executive Summary**
   - Total open items count
   - Items by priority (P0/P1/P2/P3)
   - Items by status (Active/Blocked/Ready/Backlog/Stale)
   - Completion rate trend (if historical data available)

2. **Critical Items** (P0/P1)
   - List with issue number, title, status
   - Why it's critical
   - Blockers or dependencies
   - Recommended action

3. **Quick Wins** (Ready + Low Effort)
   - List items that can be completed quickly
   - Estimated time to complete
   - Impact/benefit

4. **Stale Items** (>30 days inactive)
   - List with last update date
   - Recommendation: close, revisit, or re-prioritize?

5. **Planning Files Status**
   - List incomplete planning sessions
   - Recommendations: resume, abandon, or complete?

6. **Recommended Next Actions**
   - Top 3-5 items to work on
   - Rationale for each
   - Suggested order of execution

### Phase 4: Interactive Selection (Optional)

Present the report to user and ask:
```
I found X open items across Y categories. Here are the top priorities:

**Critical (P0/P1):**
1. [Issue #123] Fix production quota leak
2. [Issue #124] Security vulnerability in search

**Ready to Start:**
3. [Issue #125] Add caching to recommendations
4. [TODO] Complete Phase 3 of Issue #163

**Quick Wins:**
5. [Issue #126] Document magic numbers
6. [Planning] Resume backfill scheduler task

Which would you like to work on? (Or type "show all" for full report)
```

## Output Format

### Standard Report Structure

```markdown
# Work Review
**Generated**: [timestamp]
**Total Items**: X open

---

## 📊 Summary

- **Critical (P0)**: X items
- **High Priority (P1)**: X items
- **Medium Priority (P2)**: X items
- **Low Priority (P3)**: X items

- **Active**: X items
- **Blocked**: X items
- **Ready**: X items
- **Backlog**: X items
- **Stale**: X items (>30 days)

---

## 🔥 Critical Items (P0/P1)

### #XXX - [Title]
**Priority**: P0 | **Status**: Blocked | **Last Updated**: [date]
**Why Critical**: [explanation]
**Blockers**: [list]
**Action**: [recommendation]

---

## ⚡ Quick Wins (Ready + <2hrs)

1. **#XXX** - [Title] - Est: 1hr - Impact: [high/med/low]
2. **#XXX** - [Title] - Est: 30min - Impact: [high/med/low]

---

## 📋 Planning Files Status

### Incomplete Planning Sessions

1. **Backfill Scheduler** (`.planning/task_plan.md`)
   - Status: Phase 2 incomplete
   - Recommendation: Resume and complete OR archive if obsolete

2. **ISBN Resolution** (`.planning/task_plan.md`)
   - Status: BLOCKED - waiting on API key
   - Recommendation: Follow up on blocker

---

## 🗑️ Stale Items (>30 days)

1. **#XXX** - [Title] - Last update: 45 days ago
   - Recommendation: Close as won't-fix OR re-prioritize

---

## 🎯 Recommended Next Actions

### Option 1: Fix Critical Production Issue
- **What**: [Issue #123] Fix ISBNdb quota leak
- **Why**: Production system exhausting quota daily
- **Effort**: 2-3 hours
- **Impact**: HIGH - prevents service degradation

### Option 2: Complete In-Progress Work
- **What**: Resume backfill scheduler planning
- **Why**: 80% complete, quick to finish
- **Effort**: 1 hour
- **Impact**: MEDIUM - unblocks future automation

### Option 3: Quick Wins Sprint
- **What**: Complete 3-4 quick wins from list above
- **Why**: Build momentum, clear backlog
- **Effort**: 2-3 hours total
- **Impact**: MEDIUM - improved code quality

---

## 📈 Full Inventory

[Detailed list of all items organized by category]
```

## Parameters

```typescript
interface WorkReviewParams {
  // Optional: filter by priority
  min_priority?: 'P0' | 'P1' | 'P2' | 'P3';

  // Optional: filter by status
  status?: 'active' | 'blocked' | 'ready' | 'backlog' | 'stale';

  // Optional: include closed items from last N days
  include_recent_closed?: number; // days

  // Optional: output format
  format?: 'summary' | 'detailed' | 'interactive';

  // Optional: focus area
  focus?: 'issues' | 'planning' | 'todos' | 'all';
}
```

## Example Usage

```bash
# Full comprehensive review
/work-review

# High-priority items only
/work-review --min_priority=P1

# Just check planning files
/work-review --focus=planning

# Interactive mode with prioritization
/work-review --format=interactive

# Include recently completed items for context
/work-review --include_recent_closed=7
```

## Integration with Other Skills

- **After `/work-review`**: Use `/planning-with-files` for complex tasks
- **Before `/commit`**: Run review to ensure work is tracked
- **Weekly routine**: `/work-review` → select task → execute → `/commit`

## Success Criteria

This skill is successful when:
- ✅ All open work items are discovered and categorized
- ✅ User understands current priorities at a glance
- ✅ User can make informed decision on what to work on next
- ✅ Stale items are surfaced for triage
- ✅ Dependencies and blockers are clearly identified

## Implementation Notes

1. **Use parallel tool calls** for discovery (gh issue list + file reads)
2. **Cache results** for 1 hour (items change infrequently)
3. **Highlight NEW items** since last review (if cache exists)
4. **Use PAL MCP consensus** for complex prioritization decisions (optional)
5. **Track review history** to show progress over time (optional enhancement)

## Related Files

- Source of truth: `TODO.md`, `docs/CURRENT-STATUS.md`
- Planning artifacts: `.planning/`, `docs/planning/`
- GitHub: Issues and PRs via `gh` CLI

---

**Skill Owner**: Claude Code
**Created**: 2026-01-13
**Last Updated**: 2026-01-13
