# Manus Plugin Setup Guide - BooksTrack iOS

**Plugin:** planning-with-files (v2.0.1)
**Repository:** https://github.com/OthmanAdi/planning-with-files
**Installed:** January 9, 2026
**Project:** BooksTrack iOS Frontend (Swift/SwiftUI)

---

## Installation Status

✅ **Plugin installed** at `.claude/plugins/planning-with-files/`
✅ **Skill registered** at `.claude/skills/planning-with-files/`
✅ **Scripts executable** in `.claude/skills/planning-with-files/scripts/`

## Quick Start

### 1. Initialize Planning Files (For New Tasks)

When starting a complex task (>5 tool calls), run:

```bash
.claude/skills/planning-with-files/scripts/init-session.sh "task-name"
```

This creates three files in your project root:
- `task_plan.md` - Phase tracking, decisions, errors
- `findings.md` - Research, discoveries, resources
- `progress.md` - Session log, test results

### 2. Using the /planning-with-files Skill

The skill is now available as a slash command:

```
/planning-with-files
```

This will invoke the planning workflow for complex tasks.

### 3. Manual File Creation

If you prefer to create files manually, use the templates:

```bash
# Copy templates to project root
cp .claude/skills/planning-with-files/templates/task_plan.md .
cp .claude/skills/planning-with-files/templates/findings.md .
cp .claude/skills/planning-with-files/templates/progress.md .

# Edit to customize for your task
```

---

## How It Works

### The 3-File Pattern

**Manus Pattern:**
```
Context Window = RAM (volatile, limited)
Filesystem = Disk (persistent, unlimited)

→ Anything important gets written to disk.
```

| File | Purpose | Update When |
|------|---------|-------------|
| `task_plan.md` | Roadmap: phases, decisions, errors | After each phase |
| `findings.md` | Knowledge base: research, discoveries | After ANY discovery (2-Action Rule) |
| `progress.md` | Session log: actions, tests, errors | Throughout session |

### The 2-Action Rule (CRITICAL)

**After every 2 view/browser/search operations, IMMEDIATELY save findings to `findings.md`**

This prevents multimodal/visual information from being lost when context resets.

### The 5-Question Reboot Test

Can you answer these? If yes, your context is solid:

1. **Where am I?** → Current phase in `task_plan.md`
2. **Where am I going?** → Remaining phases
3. **What's the goal?** → Goal statement in `task_plan.md`
4. **What have I learned?** → `findings.md`
5. **What have I done?** → `progress.md`

---

## Hooks Integration

The plugin includes hooks that automatically trigger during Claude Code operations:

### PreToolUse Hook (Automatic Plan Re-reading)

**Triggers before:** Write, Edit, Bash commands
**Action:** Reads first 30 lines of `task_plan.md` into context
**Why:** Keeps your goals/phases fresh in attention window

### Stop Hook (Completion Verification)

**Triggers on:** Session stop/exit
**Action:** Runs `.claude/skills/planning-with-files/scripts/check-complete.sh`
**Why:** Verifies all phases marked complete before allowing exit

**Note:** These hooks are defined in the skill's `SKILL.md` frontmatter, not in `.claude/settings.json`

---

## BooksTrack iOS-Specific Workflow

### When to Use Manus Pattern

**Use for:**
- Multi-phase features (Goals Engine, Insights filtering, Reading Sessions)
- SwiftUI + SwiftData integration work
- Swift 6 concurrency migrations
- Zero Warnings Policy enforcement sprints
- Cross-repo coordination (books-v3 ↔ bendv3)
- Complex debugging sessions (CloudKit sync, SwiftData relationships)
- iOS testing workflows (/sim-safe, /device-deploy)

**Skip for:**
- Quick bug fixes
- Single-file edits
- Simple questions
- Linting/formatting with SwiftLint

### Integration with Existing Tools

**BooksTrack iOS has:**
- `CLAUDE.md` - Quick reference (MCP, slash commands)
- `AGENTS.md` - Project context (backend contracts, code style)
- `.claude/rules/*.md` - Context-aware rules (Swift 6, testing, git)
- `~/.claude/knowledge-base/` - Shared cross-repo patterns

**Manus adds:**
- `task_plan.md` - Task-level phase tracking
- `findings.md` - Task-level research/discoveries
- `progress.md` - Task-level session logging

**Relationship:**
```
AGENTS.md (project context)
   ├── Phase 3: Goals Engine → task_plan.md
   ├── Phase 4: Insights Filtering → task_plan.md
   └── SwiftData Migration → task_plan.md
```

### Example: Goals Engine Implementation (Phase 3)

```bash
# 1. Initialize planning files
.claude/skills/planning-with-files/scripts/init-session.sh "phase-3-goals-engine"

# 2. Edit task_plan.md
## Goal
Implement Phase 3 Goals Engine with 6 goal types (pages read, books finished, reading streak, daily reading, genre exploration, series completion) and progress tracking.

## Phases
### Phase 1: Research & Design
- [ ] Review existing Goal model (SwiftData)
- [ ] Design progress tracking system
- [ ] Plan UI components (GoalCard, GoalProgressView)
- **Status:** in_progress

### Phase 2: Core Implementation
- [ ] Implement 6 goal types with validation
- [ ] Create progress calculation engine
- [ ] Add SwiftData relationships (Goal ↔ User)
- **Status:** pending

### Phase 3: UI Implementation
- [ ] Build GoalCard component
- [ ] Implement GoalProgressView
- [ ] Add goal creation flow
- **Status:** pending

### Phase 4: Testing & Validation
- [ ] Unit tests for progress calculations
- [ ] UI tests with /sim-safe
- [ ] Zero warnings validation
- **Status:** pending

# 3. During work, update findings.md
## Research Findings
- Existing Goal model at BooksTrackerPackage/Sources/Types/Models/Goal.swift:15
- 6 goal types: pagesRead, booksFinished, readingStreak, dailyReading, genreExploration, seriesCompletion
- Progress tracking needs: current value, target value, percentage
- SwiftData relationship: Goal.user (inverse: User.goals)

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Use @Bindable for Goal in child views | Swift 6 concurrency requirement |
| Calculate progress in computed property | Keeps model clean, testable |
| Store goal type as enum | Type safety, exhaustive switch |

## Swift 6 Patterns Used
- @MainActor for Observable classes
- @Bindable for SwiftData in child views
- Insert before relate pattern
- Nested supporting types (not top-level)

# 4. Update progress.md as you work
### Phase 1: Research & Design
- **Status:** complete
- **Started:** 2026-01-09 10:00
- Actions taken:
  - Read Goal.swift model (BooksTrackerPackage/Sources/Types/Models/Goal.swift)
  - Analyzed 6 goal types and progress calculation
  - Documented SwiftData relationships
  - Added findings to findings.md
- Files read:
  - BooksTrackerPackage/Sources/Types/Models/Goal.swift
  - BooksTrackerPackage/Sources/Types/Models/User.swift
- Files modified:
  - findings.md (research)
  - task_plan.md (phase 1 → complete)

## Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| Build with /quick-validate | Zero warnings | Zero warnings | ✅ |
| Goal progress calculation | 60% (6/10 books) | 60% | ✅ |
| SwiftData relationship | Bidirectional | Bidirectional | ✅ |
```

---

## Advanced Features

### Templates

Located at `.claude/skills/planning-with-files/templates/`:
- `task_plan.md` - Phase tracking template
- `findings.md` - Research/discovery template
- `progress.md` - Session logging template

### Scripts

Located at `.claude/skills/planning-with-files/scripts/`:
- `init-session.sh` - Creates all three planning files
- `check-complete.sh` - Verifies all phases complete (used by Stop hook)

### Reference Docs

Located at `.claude/skills/planning-with-files/`:
- `SKILL.md` - Skill definition + quick reference
- `reference.md` - Manus principles deep dive
- `examples.md` - Real-world usage examples

---

## Critical Rules (Manus Pattern)

### 1. Create Plan First
Never start a complex task without `task_plan.md`. Non-negotiable.

### 2. The 2-Action Rule
After every 2 view/browser/search operations, IMMEDIATELY save findings to `findings.md`.

### 3. Read Before Decide
Before major decisions, re-read `task_plan.md` to refresh goals in attention window.

### 4. Update After Act
After completing any phase:
- Mark phase status: `in_progress` → `complete`
- Log any errors encountered
- Note files created/modified

### 5. Log ALL Errors
Every error goes in both:
- `task_plan.md` - Quick error table
- `progress.md` - Detailed error log with timestamps

### 6. Never Repeat Failures
```
if action_failed:
    next_action != same_action
```
Track attempts, mutate approach using 3-Strike Protocol.

---

## The 3-Strike Error Protocol

```
ATTEMPT 1: Diagnose & Fix
  → Read error carefully
  → Identify root cause
  → Apply targeted fix

ATTEMPT 2: Alternative Approach
  → Same error? Try different method
  → Different tool? Different library?
  → NEVER repeat exact same failing action

ATTEMPT 3: Broader Rethink
  → Question assumptions
  → Search for solutions
  → Consider updating the plan

AFTER 3 FAILURES: Escalate to User
  → Explain what you tried
  → Share the specific error
  → Ask for guidance
```

---

## BooksTrack iOS Integration Examples

### Scenario 1: Insights Tap-to-Filter (Phase 1)

```bash
# Initialize
.claude/skills/planning-with-files/scripts/init-session.sh "insights-tap-filter"

# task_plan.md
## Goal
Implement tap-to-filter navigation from Insights to Library with filter persistence

## Phases
### Phase 1: Navigation Setup
- [ ] Add NavigationLink to InsightCard
- [ ] Pass filter context to LibraryView
- [ ] Implement filter state management
- **Status:** in_progress

### Phase 2: Filter Persistence
- [ ] Store filter in @AppStorage
- [ ] Restore filter on navigation
- [ ] Clear filter button
- **Status:** pending

### Phase 3: UI Polish
- [ ] Add filter indicator in LibraryView
- [ ] Smooth navigation transition
- [ ] Accessibility labels
- **Status:** pending
```

### Scenario 2: Swift 6 Concurrency Migration

```bash
# Initialize
.claude/skills/planning-with-files/scripts/init-session.sh "swift-6-concurrency"

# task_plan.md
## Goal
Migrate all Observable classes to @MainActor and fix Swift 6 concurrency warnings

## Phases
### Phase 1: Audit Current State
- [ ] Run /quick-validate to identify warnings
- [ ] List all Observable classes
- [ ] Identify @Binding vs @Bindable issues
- **Status:** in_progress

### Phase 2: Apply Fixes
- [ ] Add @MainActor to Observable classes
- [ ] Convert @Binding to @Bindable for SwiftData
- [ ] Fix Timer.publish in actors
- **Status:** pending

### Phase 3: Validation
- [ ] Run /quick-validate (zero warnings)
- [ ] Test with /sim-safe
- [ ] Verify CloudKit sync still works
- **Status:** pending

# findings.md - Updated during work
## Research Findings
- 12 Observable classes need @MainActor
- 5 child views using @Binding instead of @Bindable
- 2 actors using Timer.publish (forbidden)
- SwiftData relationship pattern: insert before relate

## Swift 6 Patterns
| Pattern | Before | After |
|---------|--------|-------|
| Observable class | `class SearchModel: Observable` | `@MainActor class SearchModel: Observable` |
| Child view binding | `@Binding var work: Work` | `@Bindable var work: Work` |
| Actor timer | `Timer.publish(...)` | `Task { try await Task.sleep(...) }` |

# progress.md - Session log
### Phase 1: Audit Current State
- **Status:** complete
- **Started:** 2026-01-09 14:00
- Actions taken:
  - Ran /quick-validate → 8 warnings identified
  - Listed 12 Observable classes needing @MainActor
  - Documented pattern violations in findings.md
- Build output:
  ```
  warning: Main actor-isolated property 'state' can not be referenced from a non-isolated context
  → Fix: Add @MainActor to SearchModel
  ```
- Files to modify (Phase 2):
  - BooksTrack/Features/Search/SearchModel.swift
  - BooksTrack/Features/Library/LibraryViewModel.swift
  - (10 more files...)
```

---

## Safe Testing Integration

When using Manus with iOS testing:

### Testing Decision Matrix

| Scenario | Command | When to Use |
|----------|---------|-------------|
| Build validation | `/quick-validate` | Default for all development |
| UI testing needed | Ask user: `/device-deploy` vs `/sim-safe` | After UI implementation |
| System unresponsive | `/kill-xcode` | Emergency cleanup |

### Document Test Results in progress.md

```markdown
## Test Results
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| Build validation | /quick-validate | Zero warnings | Zero warnings | ✅ |
| Goal progress UI | /sim-safe | Displays 60% | Displays 60% | ✅ |
| CloudKit sync | /device-deploy | Background sync | Background sync | ✅ |
```

---

## Resources

- **Plugin Repo:** https://github.com/OthmanAdi/planning-with-files
- **Manus Reference:** `.claude/skills/planning-with-files/reference.md`
- **Examples:** `.claude/skills/planning-with-files/examples.md`
- **BooksTrack Guidelines:** `CLAUDE.md`, `AGENTS.md`
- **Memory Rules:** `.claude/rules/*.md`
- **Shared Patterns:** `~/.claude/knowledge-base/`

---

## Troubleshooting

### Files created in wrong location
**Problem:** Planning files created in `.claude/plugins/planning-with-files/` instead of project root
**Solution:** Always run `init-session.sh` from project root (`/Users/juju/dev_repos/books-v3`)

### Hooks not triggering
**Problem:** PreToolUse hook not reading `task_plan.md`
**Solution:** Hooks are defined in skill's `SKILL.md`, not `.claude/settings.json`. Ensure skill is installed in `.claude/skills/planning-with-files/`

### Check-complete.sh blocking exit
**Problem:** Stop hook prevents exit because phases aren't marked complete
**Solution:** Update `task_plan.md` phase statuses from `in_progress` → `complete`

### Zero Warnings Policy
**Problem:** Build succeeds but has warnings
**Solution:** BooksTrack enforces `-Werror` in Xcode. All warnings must be fixed before PR. Document warnings in `task_plan.md` errors table.

---

**Last Updated:** January 9, 2026
**Maintained By:** @jukasdrj
**Plugin Version:** 2.0.1
