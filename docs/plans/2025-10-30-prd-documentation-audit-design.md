# PRD Documentation Audit & Update - Design Document

**Date:** October 30, 2025
**Status:** Design Complete
**Goal:** Ensure all production features have actionable PRD documentation that reflects current implementation

## Problem Statement

The BooksTrack app has evolved rapidly over the past 2-4 weeks with significant changes:
- VisionKit barcode scanner replaced AVFoundation implementation
- Canonical data contracts (v1 API endpoints) deployed
- Genre normalization, DTOMapper integration, enrichment pipeline updates

**Current State:**
- Some features lack PRDs entirely (VisionKit scanner)
- Some PRDs reference deprecated tech (AVFoundation, old API endpoints)
- Some features have PRDs but no workflow diagrams
- Unclear which features are fully implemented vs planned

**Impact:**
- Future development decisions lack historical context
- New contributors can't understand why technical choices were made
- Documentation drift makes onboarding harder
- Can't confidently say "what we have vs what we documented"

## Solution Overview

**Interactive Audit → Immediate PRD Fixes**

Instead of generating a report for later action, we'll:
1. Walk through each feature area systematically
2. Identify gaps in real-time (missing PRDs, outdated sections, missing workflows)
3. Fix gaps immediately as we find them
4. Produce updated/new documentation files during the audit itself

**Key Benefits:**
- PRDs are done when audit finishes (no follow-up work)
- Fresh implementation details while still in memory
- Can validate fixes against actual code during the session
- Establishes documentation quality standards for future features

**Trade-off Accepted:**
- Takes longer than automated report (3-4 hours vs 15 min)
- Requires active participation throughout
- More mentally taxing than batch updates

**Why This Approach:**
Actionability was the primary goal. An audit report sitting in docs/ doesn't improve decision-making. Updated PRDs with decision logs and current technical details do.

## Audit Process

### Step 1: Inventory Current State (15 min)

**Scan existing documentation:**
```bash
# Check PRDs
ls -la docs/product/*.md

# Check workflows
ls -la docs/workflows/*.md

# Review CLAUDE.md feature list
grep -A 5 "## Features" CLAUDE.md

# Recent code changes
git log --since="2 weeks ago" --oneline --name-only
```

**Output:** Master list of:
- Existing PRDs and their last modified dates
- Existing workflow diagrams
- Features mentioned in CLAUDE.md
- Recent code changes (from git log)

### Step 2: Feature-by-Feature Audit

**Execution Order (Priority-Based):**

1. **Recently Changed Features** (30-45 min per feature)
   - VisionKit barcode scanner
   - Canonical data contracts (WorkDTO/EditionDTO/AuthorDTO)
   - Genre normalization
   - DTOMapper integration

2. **Core User Workflows** (20-30 min per feature)
   - Search (title, ISBN, author, advanced)
   - CSV import (Gemini AI-powered)
   - Bookshelf scanner (single + batch)
   - Enrichment pipeline

3. **Supporting Features** (15-20 min per feature)
   - Settings (theme, AI provider, feature flags)
   - CloudKit sync
   - Review queue
   - Library reset

4. **Analytics & Insights** (20-30 min per feature)
   - Diversity insights (author gender, cultural region)
   - Reading statistics
   - Progress tracking

**Per-Feature Checklist:**
```markdown
Feature: [Name]
- [ ] PRD exists in docs/product/
- [ ] PRD sections complete: Problem, Solution, User Stories, Success Metrics, Technical Notes, Decision Log
- [ ] PRD reflects current implementation (not planned/old architecture)
- [ ] Workflow diagram exists in docs/workflows/
- [ ] Workflow shows actual data flow (not conceptual)
- [ ] CLAUDE.md documents the feature accurately
- [ ] Cross-references are consistent (PRD ↔ Workflow ↔ CLAUDE.md)
```

### Step 3: Gap Identification & Immediate Fix

**Gap Type 1: Missing PRD**
- **Create:** `docs/product/[Feature-Name]-PRD.md`
- **Populate from:** Current code, CLAUDE.md, git commit messages, workflow diagrams
- **Focus on:** WHY built, WHO uses it, WHAT success looks like, DECISION LOG
- **Time:** 30-45 min for complex features, 15-20 min for simple

**Gap Type 2: Missing Workflow**
- **Create:** `docs/workflows/[feature-name]-workflow.md`
- **Include:** Mermaid sequence diagram showing iOS → Backend → External APIs
- **Document:** Caching layers, WebSocket flows, error handling paths
- **Time:** 15-20 min

**Gap Type 3: Outdated PRD Sections**
- **Identify:** Which sections reference deprecated tech (AVFoundation, old API endpoints)
- **Update:** Only stale sections (preserve problem statement, user stories if still valid)
- **Add:** "Last Updated: [date]" timestamp to changed sections
- **Flag:** Deprecated features as "[REMOVED: date] reason"
- **Time:** 10-15 min per section

**Gap Type 4: Unclear Actionability**
- **Add:** "Decision Log" section with rationale for technical choices
- **Add:** "Future Enhancements" with specific next steps
- **Link:** To implementation plans if they exist
- **Include:** Performance metrics, success criteria with actual numbers
- **Time:** 5-10 min

### Step 4: Quality Gates

**Before marking feature "complete":**
- ✅ PRD answers: "Why does this exist?" "Who uses it?" "How do we know it works?"
- ✅ Workflow diagram shows: Request → Processing → Response with error paths
- ✅ No references to removed/deprecated tech
- ✅ Cross-references between PRD, workflow, CLAUDE.md are consistent
- ✅ Decision log explains key technical choices
- ✅ Success metrics are quantifiable or observable

## Documentation Standards

### PRD Template Structure

Every PRD must include:

**1. Problem Statement**
- What user pain point does this solve?
- Why now? (What triggered building this?)
- Links to user feedback, GitHub issues, or design discussions

**2. Solution Overview**
- High-level architecture (2-3 sentences)
- Key technical choices with rationale
- Trade-offs considered and why we chose this approach

**3. User Stories**
- Format: "As a [user type], I want [goal] so that [benefit]"
- Include edge cases and error scenarios
- Link to actual code implementing each story

**4. Success Metrics**
- Quantifiable: "95% of ISBN scans complete in <3s"
- Observable: "Zero crashes related to camera permission denial"
- References to actual Analytics Engine data if available

**5. Technical Implementation**
- Current architecture (as-built, not as-planned)
- API endpoints, models, services used
- Dependencies on other features
- Known limitations

**6. Decision Log** (NEW - for actionability)
- Format: "[Date] Decision: ... Rationale: ..."
- Why we chose X over Y
- What we tried that didn't work
- What we deferred for later

**7. Future Enhancements** (optional but recommended)
- Specific next steps with priority
- Links to GitHub issues if planned
- Technical debt to address

### Workflow Diagram Standards

Every workflow must show:
- **Actors:** User, iOS App, Backend Worker, External APIs
- **Happy path:** Request → Processing → Success
- **Error paths:** What fails and how we handle it
- **Caching layers:** Where and when we cache (KV, R2, Edge Cache)
- **WebSocket flows:** If async processing involved (enrichment, scanning, CSV import)
- **Performance notes:** Expected latency, timeout values

**Format:** Mermaid sequence diagrams (renders in GitHub, readable as text)

### Cross-Reference Rules

- PRD links to workflow diagram: `See [Workflow](../workflows/feature-name-workflow.md)`
- Workflow links back to PRD: `See [PRD](../product/Feature-Name-PRD.md)`
- CLAUDE.md references both for quick lookup: `**Feature:** See docs/product/Feature-PRD.md`
- Implementation plans reference PRDs: `Based on [PRD](../product/Feature-PRD.md)`

## Timeline Estimates

**Per-Feature Time:**
- **Simple feature** (Theme Selector, Settings toggle): 15-20 min
  - Check PRD exists (2 min)
  - Verify technical details current (5 min)
  - Update/create workflow (8 min)
  - Review for actionability (5 min)

- **Complex feature** (Bookshelf Scanner, Enrichment): 30-45 min
  - Audit existing PRD thoroughly (10 min)
  - Update multiple outdated sections (15 min)
  - Create/update workflow diagram (15 min)
  - Add decision log and metrics (5 min)

**Total Estimated Time: 3-4 hours** for comprehensive audit + fixes

**Feature Count Estimates:**
- Recently changed: 4 features × 35 min = 140 min
- Core workflows: 4 features × 25 min = 100 min
- Supporting: 5 features × 17 min = 85 min
- Analytics: 2 features × 25 min = 50 min
- **Total: 375 min (6.25 hours)** - rounded down to 3-4 hours accounting for overlap/efficiency

## Deliverables

At the end of the audit session:

1. **Updated/New PRD Files** (`docs/product/`)
   - All production features have current PRDs
   - All PRDs include Decision Log sections
   - No references to deprecated tech

2. **Updated/New Workflow Diagrams** (`docs/workflows/`)
   - All PRDs have corresponding workflows
   - All workflows show actual implementation (not conceptual)

3. **Audit Summary Report** (`docs/audit-2025-10-30-summary.md`)
   - List of all changes made
   - New PRDs created
   - Sections updated in existing PRDs
   - Gaps found and fixed
   - Recommendations for preventing future drift

4. **Updated CLAUDE.md**
   - Feature list reflects current implementation
   - Cross-references to PRDs and workflows
   - Deprecated features flagged clearly

## Success Criteria

**Objective Measures:**
- ✅ Zero production features without PRDs
- ✅ Zero PRDs without workflow diagrams
- ✅ Zero references to AVFoundation scanner (replaced by VisionKit)
- ✅ Zero references to old API endpoints (pre-canonical contracts)
- ✅ 100% of PRDs include Decision Log sections
- ✅ All PRDs have "Last Updated" timestamps

**Subjective Measures:**
- Can a new developer read a PRD and understand WHY we built it?
- Can a developer make informed decisions about future enhancements?
- Do workflows accurately reflect actual code paths?
- Is the documentation useful for onboarding?

## Future Workflow Prevention

**To prevent documentation drift going forward:**

1. **PRD-First Development**
   - Require PRD creation/update BEFORE starting implementation
   - Include PRD link in PR descriptions
   - Code review checklist: "Does this PR update relevant PRDs?"

2. **Documentation CI Check** (future automation)
   - Script to detect features in CLAUDE.md without PRDs
   - Warn if PRD modified date is >3 months old
   - Flag TODOs in PRDs that reference completed work

3. **Regular Audits**
   - Quarterly documentation review (lighter version of this audit)
   - Tag PRDs with "last-reviewed" date
   - Archive PRDs for removed features

## Next Steps

After design approval:

1. **No worktree needed** - documentation updates done in main branch
2. **No implementation plan needed** - this IS the implementation plan
3. **Execute the audit** following the process defined above
4. **Commit PRD updates incrementally** as we complete each feature area
5. **Create final summary report** when all features audited

---

**Design Status:** ✅ Complete and validated
**Ready for Execution:** Yes
**Estimated Duration:** 3-4 hours of focused work
**Output:** Comprehensive, actionable PRD documentation for all BooksTrack features
