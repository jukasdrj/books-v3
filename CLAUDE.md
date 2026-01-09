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
- **Planning** → Manus pattern (complex tasks >5 tool calls)

---

## Essential Commands

**🚀 iOS Development (xcodebuild CLI):**

```bash
# Safe Testing (Recommended - Prevents System Crashes)
/quick-validate  # Build validation without Simulator
/sim-safe        # Monitored Simulator with resource limits
/kill-xcode      # Emergency cleanup
/device-deploy   # Deploy to real device (most efficient)

# Standard Testing (Higher Resource Usage)
/build           # Build validation (resource-intensive)
/test            # Run Swift Testing suite
/sim             # Launch Simulator (⚠️ can crash if <16GB RAM)
```

**⚠️ CRITICAL: Always prefer `/quick-validate` over `/build` during development**

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

**Simple Tasks:** Handle directly
**Complex Tasks:** Use TodoWrite → Delegate to specialists → Integrate

**Auto-Delegation Patterns:**
- **Code exploration** → Explore agent (Haiku)
- **Implementation planning** → Plan agent (Opus)
- **Bug investigation** → mcp__pal__debug (Gemini)
- **Security review** → mcp__pal__secaudit (Grok)
- **Code review** → mcp__pal__codereview (Grok)

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

### Planning-with-Files Plugin (v2.0.1)
**Use for complex tasks (>5 tool calls):**
```bash
# Initialize planning files
.claude/skills/planning-with-files/scripts/init-session.sh "task-name"

# Or use slash command
/planning-with-files
```

**Creates:** `task_plan.md`, `findings.md`, `progress.md` in project root

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

**Last Updated:** December 26, 2025 (Claude Code v2.0.65, BooksTrack v3.7.5)
**Size Reduction:** From 1,393 → ~150 lines (89% reduction via memory rules & knowledge base)