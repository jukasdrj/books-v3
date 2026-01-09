# Planning-with-Files Plugin Installation

**Date:** January 9, 2026
**Plugin Version:** 2.0.1
**Repository:** https://github.com/OthmanAdi/planning-with-files

---

## Installation Summary

✅ **Completed successfully!**

### What Was Installed

1. **Plugin directory:** `.claude/plugins/planning-with-files/`
   - Full plugin source code
   - Templates, scripts, reference docs

2. **Skill registration:** `.claude/skills/planning-with-files/`
   - Skill definition (SKILL.md)
   - Executable scripts (init-session.sh, check-complete.sh)
   - Templates (task_plan.md, findings.md, progress.md)
   - Reference documentation

3. **Documentation:**
   - `.claude/MANUS_SETUP.md` - Full setup guide (iOS-specific examples)
   - `.claude/MANUS_QUICKREF.md` - Quick reference card
   - Updated `CLAUDE.md` with plugin reference

### Files Modified

- `CLAUDE.md` - Added Manus references in Quick Reference and BooksTrack-Specific sections

---

## Verification

```bash
# Check plugin installed
ls .claude/plugins/planning-with-files/

# Check skill registered
ls .claude/skills/planning-with-files/

# Verify scripts are executable
ls -la .claude/skills/planning-with-files/scripts/

# Test initialization (in project root)
.claude/skills/planning-with-files/scripts/init-session.sh "test"
```

---

## Quick Start

### For Complex Tasks (>5 tool calls)

```bash
# Method 1: Use init script
.claude/skills/planning-with-files/scripts/init-session.sh "task-name"

# Method 2: Use slash command
/planning-with-files
```

This creates three files in your project root:
- `task_plan.md` - Phase tracking, decisions, errors
- `findings.md` - Research, discoveries
- `progress.md` - Session log, test results

---

## iOS-Specific Use Cases

**Perfect for:**
- Goals Engine implementation (Phase 3)
- Insights tap-to-filter (Phase 1)
- Swift 6 concurrency migrations
- SwiftUI + SwiftData integration work
- Cross-repo coordination (books-v3 ↔ bendv3)
- Zero Warnings Policy enforcement sprints

**Skip for:**
- Quick bug fixes
- Single-file edits
- Simple questions
- Linting/formatting

---

## Documentation

- **Full Guide:** `.claude/MANUS_SETUP.md`
- **Quick Reference:** `.claude/MANUS_QUICKREF.md`
- **Manus Principles:** `.claude/skills/planning-with-files/reference.md`
- **Examples:** `.claude/skills/planning-with-files/examples.md`

---

## Hooks (Automatic Behavior)

### PreToolUse Hook
**Triggers:** Before Write, Edit, Bash commands
**Action:** Reads first 30 lines of `task_plan.md` into context
**Why:** Keeps goals/phases fresh in attention window

### Stop Hook
**Triggers:** On session stop/exit
**Action:** Runs `check-complete.sh` to verify all phases complete
**Why:** Prevents incomplete work from being abandoned

**Note:** Hooks are defined in `.claude/skills/planning-with-files/SKILL.md` frontmatter

---

## Integration with Existing Tools

**BooksTrack iOS already has:**
- `CLAUDE.md` - Quick reference (MCP, slash commands)
- `AGENTS.md` - Project context (backend contracts, code style)
- `.claude/rules/*.md` - Auto-loaded context patterns
- `~/.claude/knowledge-base/` - Shared cross-repo patterns

**Manus adds:**
- Task-level phase tracking (task_plan.md)
- Task-level research/discoveries (findings.md)
- Task-level session logging (progress.md)

**Relationship:**
```
AGENTS.md (project context)
   ├── Phase 3: Goals Engine → task_plan.md
   ├── Phase 4: Insights Filtering → task_plan.md
   └── SwiftData Migration → task_plan.md
```

---

## Next Steps

1. **Try it out:** Initialize planning files for your next complex task
2. **Read the guides:** Review `.claude/MANUS_SETUP.md` for iOS-specific examples
3. **Follow the pattern:** Create plan first, update after each phase, log all errors

---

## Comparison with bendv3 Setup

**Similarities:**
- Same plugin version (2.0.1)
- Same directory structure
- Same documentation approach (SETUP + QUICKREF)

**iOS-Specific Additions:**
- Swift 6 concurrency examples
- Safe testing integration (/quick-validate, /sim-safe)
- Zero Warnings Policy context
- SwiftUI + SwiftData patterns
- iOS testing workflows

---

**Installation by:** Claude (Sonnet 4.5)
**Verified:** ✅ All components installed and functional
**Status:** Ready to use
