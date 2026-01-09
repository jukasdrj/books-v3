# Manus Quick Reference - BooksTrack iOS

**Plugin:** planning-with-files v2.0.1 | **Docs:** `.claude/MANUS_SETUP.md`

---

## 🚀 Quick Start

### Initialize Session (Complex Tasks)

```bash
.claude/skills/planning-with-files/scripts/init-session.sh "task-name"
```

**Creates:** `task_plan.md`, `findings.md`, `progress.md` in project root

### Use Slash Command

```
/planning-with-files
```

---

## 📋 The 3-File Pattern

| File | Purpose | Update When |
|------|---------|-------------|
| `task_plan.md` | Phases, decisions, errors | After each phase |
| `findings.md` | Research, discoveries | After ANY discovery |
| `progress.md` | Session log, test results | Throughout session |

---

## ⚡ Critical Rules

### 1. Create Plan First
**Never** start complex tasks without `task_plan.md`. Non-negotiable.

### 2. The 2-Action Rule
After every **2 view/browser/search operations**, IMMEDIATELY save findings to `findings.md`.

### 3. Read Before Decide
Before major decisions, re-read `task_plan.md` to refresh goals.

### 4. Update After Act
Mark phases: `in_progress` → `complete`. Log errors.

### 5. Log ALL Errors
Every error → `task_plan.md` + `progress.md`

### 6. Never Repeat Failures
```
if action_failed:
    next_action != same_action
```

---

## 🎯 When to Use

**Use Manus for:**
- Multi-phase features (Goals Engine, Insights, Reading Sessions)
- SwiftUI + SwiftData integration
- Swift 6 concurrency migrations
- Zero Warnings enforcement sprints
- Cross-repo coordination (books-v3 ↔ bendv3)
- Complex debugging (CloudKit, SwiftData relationships)

**Skip for:**
- Quick bug fixes
- Single-file edits
- Simple questions
- Linting/formatting

---

## 🔧 Example Usage

### Phase 3: Goals Engine

```bash
.claude/skills/planning-with-files/scripts/init-session.sh "phase-3-goals-engine"
```

**task_plan.md:**
```markdown
## Goal
Implement 6 goal types with progress tracking

## Phases
### Phase 1: Research & Design
- [ ] Review Goal model
- [ ] Design progress system
- **Status:** in_progress

### Phase 2: Core Implementation
- [ ] Implement 6 goal types
- [ ] Create progress engine
- **Status:** pending

### Phase 3: UI Implementation
- [ ] Build GoalCard
- [ ] Implement GoalProgressView
- **Status:** pending
```

**findings.md:**
```markdown
## Research Findings
- Goal model: BooksTrackerPackage/Sources/Types/Models/Goal.swift:15
- 6 types: pagesRead, booksFinished, readingStreak, dailyReading, genreExploration, seriesCompletion
- SwiftData relationship: Goal.user ↔ User.goals

## Swift 6 Patterns
- @MainActor for Observable classes
- @Bindable for SwiftData in child views
```

**progress.md:**
```markdown
### Phase 1: Research & Design
- **Status:** complete
- **Started:** 2026-01-09 10:00
- Actions: Read Goal.swift, analyzed types, documented patterns
- Files read: Goal.swift, User.swift

## Test Results
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| Build | /quick-validate | Zero warnings | Zero warnings | ✅ |
```

---

## 🧪 Testing Integration

| Scenario | Command | When |
|----------|---------|------|
| Build validation | `/quick-validate` | Default |
| UI testing | Ask: `/device-deploy` vs `/sim-safe` | After UI work |
| Emergency | `/kill-xcode` | System freeze |

**Document in progress.md:**
```markdown
## Test Results
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| Build | /quick-validate | 0 warnings | 0 warnings | ✅ |
| UI | /sim-safe | Goal card shown | Goal card shown | ✅ |
```

---

## 🛠️ The 3-Strike Error Protocol

```
ATTEMPT 1: Diagnose & Fix
  → Read error, identify root cause, apply fix

ATTEMPT 2: Alternative Approach
  → Different method/tool/library
  → NEVER repeat same failing action

ATTEMPT 3: Broader Rethink
  → Question assumptions, search solutions

AFTER 3 FAILURES: Escalate to User
  → Explain attempts, share error, ask guidance
```

---

## 📂 File Locations

| Location | Contents |
|----------|----------|
| `.claude/plugins/planning-with-files/` | Plugin installation |
| `.claude/skills/planning-with-files/` | Skill (slash command) |
| `.claude/skills/planning-with-files/scripts/` | Helper scripts |
| `.claude/skills/planning-with-files/templates/` | File templates |
| Project root (`/Users/juju/dev_repos/books-v3/`) | Your planning files |

---

## 📚 Resources

- **Plugin Repo:** https://github.com/OthmanAdi/planning-with-files
- **Manus Principles:** `.claude/skills/planning-with-files/reference.md`
- **Examples:** `.claude/skills/planning-with-files/examples.md`
- **Full Setup:** `.claude/MANUS_SETUP.md`
- **BooksTrack Guidelines:** `CLAUDE.md`, `AGENTS.md`
- **Memory Rules:** `.claude/rules/*.md`

---

## 🔍 5-Question Reboot Test

Can you answer these?

1. **Where am I?** → Current phase in `task_plan.md`
2. **Where am I going?** → Remaining phases
3. **What's the goal?** → Goal statement
4. **What have I learned?** → `findings.md`
5. **What have I done?** → `progress.md`

---

## ⚠️ Common Mistakes

| Don't | Do Instead |
|-------|------------|
| Use TodoWrite for persistence | Create `task_plan.md` file |
| State goals once and forget | Re-read plan before decisions |
| Hide errors and retry silently | Log errors to plan file |
| Stuff everything in context | Store large content in files |
| Start executing immediately | Create plan file FIRST |
| Repeat failed actions | Track attempts, mutate approach |
| Create files in skill directory | Create in project root |

---

**Last Updated:** January 9, 2026
**Plugin Version:** 2.0.1
**Check Installation:** `ls .claude/skills/planning-with-files/`
