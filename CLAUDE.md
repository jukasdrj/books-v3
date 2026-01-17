# 📚 BooksTrack - Claude Code Guide (Streamlined)

**Version 3.7.5 (Build 189+)** | **iOS 26.0+** | **Swift 6.2+** | **Updated: December 26, 2025**

## Agent Role

**Identity:** Books (iOS Frontend) - User Interface
**Scope:** SwiftUI views, SwiftData persistence, CloudKit sync
**Upstream:** bendv3 API (api.oooefam.net)
**Cross-repo docs:** `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`

---

## Quick Reference

**🤖 Context Files:**
- **`CLAUDE.md`** - This file (MCP, slash commands)
- **`.claude/rules/`** - Memory rules (auto-loaded)
- **`~/.claude/knowledge-base/`** - Shared patterns across projects
- **`docs/CROSS_REPO.md`** - Cross-repository architecture
- **`.claude/MANUS_SETUP.md`** - Planning-with-files plugin guide
- **`.claude/MANUS_QUICKREF.md`** - Manus quick reference

**Memory Rules Auto-Load:** When you mention specific keywords, relevant context automatically loads:
- **Testing** → `.claude/rules/safe-testing.md`
- **Swift 6** → `.claude/rules/swift-concurrency.md`
- **Multi-agent** → `.claude/rules/multi-agent-workflows.md`
- **Git/Commit** → `.claude/rules/git-workflows.md`
- **PM Orchestration** → `.claude/rules/pm-orchestration.md` (NEW)
- **Planning** → `.claude/rules/planning-automation.md` (NEW)

---

## Essential Commands

**🚀 iOS Development (xcodebuild + xcsift CLI):**

```bash
# Safe Testing (Recommended - Prevents System Crashes)
/quick-validate  # Build validation without Simulator (uses xcsift)
/sim-safe        # Monitored Simulator with resource limits (uses xcsift)
/kill-xcode      # Emergency cleanup
/device-deploy   # Deploy to real device (most efficient, uses xcsift)

# Standard Testing (Higher Resource Usage)
/build           # Build validation (resource-intensive, uses xcsift)
/test            # Run Swift Testing suite (uses xcsift for coverage)
/sim             # Launch Simulator (⚠️ can crash if <16GB RAM)
```

**⚠️ CRITICAL: Always prefer `/quick-validate` over `/build` during development**

**xcsift Integration:**
All xcodebuild commands automatically pipe through `xcsift` for:
- Structured error/warning parsing (JSON output)
- File:line navigation format for direct jumps
- Automatic deduplication of identical issues
- Build timing metrics and slowest target identification
- Code coverage automation (converts .xcresult → JSON)
- Slow test detection (configurable threshold)

---

## MCP Servers & Models

**PAL MCP Server (v9.1.3):**
- **Providers:** Gemini ✅, X.AI ✅
- **Models:** 14 available (use `listmodels` tool)
- **Auto-delegation:** Based on task type and complexity

**Key Models:**
- **Sonnet 4.5** (You) - Orchestration, architecture
- **Opus 4.5** - Strategic planning (Plan subagent)
- **Haiku 4.5** - Fast implementation (Explore subagent)
- **Grok-4** - Expert review (code review, security)
- **Gemini 2.5 Pro** - Deep analysis (debugging)

---

## Core Workflows

### PM Orchestration Mode (NEW - Auto-Enabled)

**Context:** BooksTrack = Solo-dev family app
- Pragmatic security (not paranoid)
- Quality > compliance
- Family-only users (low attack surface)

**For Complex Tasks (>5 tool calls):**
1. **Planning First** → `/planning-with-files` creates task_plan.md/findings.md/progress.md
2. **Delegate Implementation** → Haiku/Explore agents (not you!)
3. **Delegate Review** → PAL MCP (Grok/Gemini) validates quality
4. **Integrate** → You integrate validated outputs

**For Simple Tasks:**
- Handle directly (no delegation overhead)
- Examples: Typo fixes, single-line changes, quick edits

**Auto-Delegation Patterns:**
- **Code exploration** → Explore agent (Haiku)
- **Implementation** → Explore agent (Haiku) + PAL review gate
- **Bug investigation** → mcp__pal__debug (Gemini)
- **Security review** → mcp__pal__secaudit (Grok) - pragmatic focus
- **Code review** → mcp__pal__codereview (Grok)

**Quality Bar:** "Good enough for family app" (not enterprise-grade)

**Async Agents (v2.0.64):** Use `run_in_background: true` for long-running tasks

---

## BooksTrack-Specific Notes

### Zero Warnings Policy
- **ALL PRs must build with zero warnings** (enforced with `-Werror`)
- SwiftLint architectural quality rules (Build 189+)
- Swift 6 strict concurrency compliance

### Safe Testing Workflow
When user requests testing:
1. **Default:** `/quick-validate` (not `/build`)
2. **UI Testing:** Ask `/device-deploy` vs `/sim-safe`
3. **Emergency:** `/kill-xcode` if system freezes

### Modern Settings (v2.0.62-65)
- **Model switching:** `option+p` / `alt+p` during prompt
- **Named sessions:** `/rename <name>`, `/resume <name>`
- **Usage stats:** `/stats` command
- **Attribution:** Configured via `attribution` setting

### Planning-with-Files Plugin (v2.0.1) - AUTO-TRIGGERED

**Automatic Detection:** UserPromptSubmit hook detects complex tasks and reminds you
- Triggers on: "implement feature", "phase X", "migration", "refactor"
- Checks: If task_plan.md/findings.md/progress.md exist
- Reminds: "🎯 Multi-step task detected. Use /planning-with-files..."

**Manual Trigger:**
```bash
# Initialize planning files
.claude/skills/planning-with-files/scripts/init-session.sh "task-name"

# Or use slash command
/planning-with-files
```

**Creates:** `task_plan.md`, `findings.md`, `progress.md` in project root

**PM Integration:** Planning files provide persistent memory for PM orchestration

**See:** `.claude/MANUS_SETUP.md` (full guide) | `.claude/MANUS_QUICKREF.md` (quick ref)

---

## Cross-Repository Integration

**System Architecture:** See `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`

**Related Repos:**
| Repo | Purpose | Claude Context |
|------|---------|----------------|
| **bendv3** | API gateway, user data | `~/dev_repos/bendv3/CLAUDE.md` |
| **alex** | Book metadata, covers | `~/dev_repos/alex/CLAUDE.md` |
| **books-v3** | iOS frontend | This file |

**Shared Knowledge Base:** `~/.claude/knowledge-base/`
- **patterns/** - SwiftData, Swift 6 patterns
- **architectures/** - API orchestration, multi-provider
- **debugging/** - Real device testing, troubleshooting
- **decisions/** - Zero warnings policy, architectural decisions

---

## When to Use This vs Other Docs

**Use CLAUDE.md for:** Claude Code workflows, MCP setup, testing commands
**Use AGENTS.md for:** Universal project context, backend contracts, code style
**Use memory rules for:** Auto-loaded context patterns
**Use knowledge base for:** Cross-repo shared patterns

---

## Troubleshooting PM Orchestration & Planning Automation

### "Hook isn't triggering for complex tasks"

**Problem:** You say "implement feature X" but no planning reminder appears

**Check:**
1. UserPromptSubmit hook registered in `.claude/settings.json` (line 74-79)
2. Hook script is executable: `ls -l .claude/hooks/user-prompt-submit.sh`
3. Hook script exists and has no syntax errors

**Fix:**
```bash
chmod +x .claude/hooks/user-prompt-submit.sh
# Test manually: USER_INPUT="implement feature X" bash .claude/hooks/user-prompt-submit.sh
```

### "Memory rules not auto-loading"

**Problem:** PM orchestration guidance not appearing when you say "implement"

**Check:**
1. Memory rules enabled in settings.json: `"memoryRules": {"enabled": true}`
2. Trigger keywords configured (lines 11-20 in settings.json)
3. Memory rule files exist in `.claude/rules/`

**Verify:**
```bash
ls -l .claude/rules/pm-orchestration.md
ls -l .claude/rules/planning-automation.md
```

### "SubagentStop review gate not showing"

**Problem:** Subagent completes but no "⚠️ REVIEW GATE" message

**Check:**
1. Enhanced subagent-stop.sh hook has PAL review logic (lines 41-71)
2. AGENT_TYPE matches detection arrays (Explore, general-purpose, etc.)
3. WAS_BACKGROUND is "false" (background agents skip gate)

**Debug:**
```bash
# Check subagent-stop.sh has review gate logic
grep "REVIEW GATE" .claude/hooks/subagent-stop.sh
```

### "I'm still implementing directly instead of delegating"

**Problem:** You're writing code instead of using Explore agent

**Why:** PM orchestration is guidance, not absolute enforcement

**Solution:**
1. Manually trigger PM mode: Say "implement" in your prompt (triggers memory rule)
2. Check customInstructions loaded: Should mention "PM ORCHESTRATION MODE"
3. Remember: Simple tasks (<5 tool calls) don't need delegation
4. User can override: "you implement this directly"

### "PAL review is too slow"

**Problem:** mcp__pal__codereview adds latency after every subagent

**Solutions:**
1. Use `review_type: "quick"` for simple features (not "full")
2. Skip review for trivial changes (typo fixes, log statements)
3. Run reviews in background: `run_in_background: true` on Task tool
4. Remember bar: "Good enough for family app" (not exhaustive)

### "Planning files created in wrong location"

**Problem:** task_plan.md in `.claude/plugins/` instead of project root

**Fix:**
```bash
# Files belong in project root
ls task_plan.md findings.md progress.md  # Should be here

# NOT in plugin directory
ls .claude/plugins/planning-with-files/  # Should NOT be here
```

**Correct usage:**
```bash
cd /Users/juju/dev_repos/books-v3  # Project root
/planning-with-files  # Creates files here
```

### "Override PM orchestration for specific task"

**Scenario:** You want to implement directly, skip delegation

**Solutions:**
1. **User request:** "you implement this directly" (explicit override)
2. **Simple task:** Single-file edit, <5 tool calls (auto-skips)
3. **Emergency:** Set env var: `export SKIP_PM_ORCHESTRATION=1`

### "Security review too paranoid for family app"

**Problem:** Grok flagging theoretical attacks that don't apply

**Remember context:** BooksTrack = solo-dev family app
- Low attack surface (family-only users)
- Pragmatic bar: API keys secure, auth works, no obvious holes
- Skip: Theoretical DOS, timing attacks, compliance theater

**Acceptance criteria:**
- ✅ No hardcoded API keys in code
- ✅ Auth tokens validated properly
- ✅ No obvious SQL injection (if using raw SQL)
- ❌ Don't need: Rate limiting, CSRF tokens, exhaustive pentesting

---

**Last Updated:** January 14, 2026 (PM Orchestration v1.0)
**Previous:** December 26, 2025 (Claude Code v2.0.65, BooksTrack v3.7.5)