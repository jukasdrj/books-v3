# 📚 BooksTrack - Claude Code Guide

**Version 3.7.5 (Build 189+)** | **iOS 26.0+** | **Swift 6.2+** | **Updated: November 18, 2025**

> **📋 For universal AI agent instructions, see [`AGENTS.md`](AGENTS.md)**
> This file contains **Claude Code-specific** setup (MCP, slash commands, skills).

---

## Quick Reference

**🤖 AI Context Files:**
- **`AGENTS.md`** - Universal AI agent guide (ALL tools use this)
- **`CLAUDE.md`** - Claude Code-specific (this file - MCP, slash commands)
- **`.ai/SHARED_CONTEXT.md`** - Project-wide context (tech stack, architecture)
- **`.github/copilot-instructions.md`** - GitHub Copilot setup

---

## Shared Knowledge Base

**This project contributes to and references shared learnings across all projects.**

**Knowledge Base Location:** `~/.claude/knowledge-base/`

### Patterns from BooksTrack

- [SwiftData Patterns](~/.claude/knowledge-base/patterns/swiftdata-patterns.md) - SwiftData best practices, concurrency, persistence
- [Swift 6 Actor Isolation](~/.claude/knowledge-base/patterns/swift6-actor-isolation.md) - Swift 6 concurrency and actor patterns
- [API Orchestration](~/.claude/knowledge-base/architectures/api-orchestration.md) - Multi-provider API orchestration design
- [Real Device Testing](~/.claude/knowledge-base/debugging/real-device-testing.md) - Issues only visible on physical devices
- [Zero Warnings Policy](~/.claude/knowledge-base/decisions/zero-warnings-policy.md) - Build warning policy and enforcement

---

## Claude Code MCP Setup

### Essential MCP Commands

**🚀 iOS Development (XcodeBuildMCP):**
```bash
/build         # Quick build validation using XcodeBuildMCP
/test          # Run Swift Testing suite
/sim           # Launch BooksTrack in iOS Simulator with log streaming
/device-deploy # Deploy BooksTrack to connected iPhone/iPad using XcodeBuildMCP
```

**XcodeBuildMCP Configuration:**
All slash commands use the XcodeBuildMCP server for native Xcode integration.

### Available MCP Servers

**Zen MCP Server (v9.1.3):**
- **Providers:** Google Gemini ✅, X.AI ✅
- **Available Models:** 14 (use `listmodels` tool)
- **Mode:** Auto model selection

---

## Claude Code Agent Workflow

### Built-In Agents (Automatic - No @-mention needed)

**Claude Code automatically selects the right agent for each task:**

**Task Tool Agents:**
- **Explore** - Finding files, understanding codebase structure
- **Plan** - Creating implementation plans for complex features
- **code-architecture-reviewer** - Code quality & architecture review
- **code-refactor-master** - Refactoring & code organization
- **refactor-planner** - Creating refactoring plans
- **auto-error-resolver** - Fixing TypeScript/Swift compilation errors

**Examples:**
```
User: "Where are CSV imports handled?"
Claude: [Uses Explore agent automatically]

User: "Review my SwiftData service for best practices"
Claude: [Uses code-architecture-reviewer agent]

User: "This LibraryView is 800 lines, help me break it down"
Claude: [Uses refactor-planner agent]
```

### Zen MCP Tools (For Deep Analysis)

**When to use Zen MCP tools explicitly:**
- Complex debugging → `mcp__zen__debug`
- Comprehensive code review → `mcp__zen__codereview`
- Multi-model consensus → `mcp__zen__consensus`
- Strategic planning → `mcp__zen__planner`
- Security audits → `mcp__zen__secaudit`
- Root cause analysis → `mcp__zen__thinkdeep`

**Model Selection:**
Use `listmodels` tool to see available models (14 total: Gemini 2.5 Flash/Pro, Grok-4, etc.)

**Example:**
```
User: "Use Zen to debug this SwiftData crash with Grok-4"
Claude: [Invokes mcp__zen__debug with model="grok-4"]
```

### TodoWrite Tool Usage

**MUST use TodoWrite for:**
- Complex multi-step tasks (3+ steps)
- Non-trivial tasks requiring careful planning
- User provides multiple tasks (numbered/comma-separated)

**Example:**
```swift
// User: "Add dark mode toggle. Make sure you run tests and build!"
// Assistant creates todos:
// 1. Create dark mode toggle component
// 2. Add dark mode state management
// 3. Implement CSS-in-JS styles
// 4. Update existing components
// 5. Run tests and build, address failures
```

**Rules:**
- Mark tasks as `in_progress` before starting
- Mark as `completed` immediately after finishing
- Exactly ONE task `in_progress` at any time
- Only mark `completed` when FULLY accomplished (not partial)

### AskUserQuestion Tool

**Use when you need:**
- User preferences or requirements
- Clarification on ambiguous instructions
- Decisions on implementation choices
- Offering choices about direction

**Features:**
- Users can always select "Other" for custom input
- `multiSelect: true` for multiple answers
- 2-4 options per question
- 1-4 questions max

---

## Code Search Tools (Claude Code)

### Built-in Grep Tool (PRIMARY)

**Use Claude Code's built-in Grep for all searches:**

```bash
# Find all @MainActor classes
User: "Find all @MainActor classes"
Claude: [Uses Grep tool with pattern '@MainActor']

# Find all SwiftData models
User: "Find all @Model classes"  
Claude: [Uses Grep tool with pattern '@Model']
```

**When exploring codebase:**
- Use Explore agent for open-ended searches
- Grep tool is used automatically when appropriate
- Don't run multiple search commands directly

---

## Claude Code Tone & Style

**Communication:**
- Output text to communicate with user (not bash echo or code comments)
- Short and concise responses
- GitHub-flavored Markdown (monospace font, CommonMark spec)
- Only use emojis if user explicitly requests

**File Operations:**
- ALWAYS prefer editing existing files over creating new ones
- NEVER create markdown files unless absolutely necessary
- Use specialized tools: Read (not cat), Edit (not sed), Write (not echo)

---

## Committing Changes with Git

**Git Safety Protocol:**
- NEVER update git config
- NEVER run destructive commands (push --force, hard reset) unless explicitly requested
- NEVER skip hooks (--no-verify, --no-gpg-sign) unless explicitly requested
- Avoid `git commit --amend` (only when user requests OR adding edits from pre-commit hook)

**Commit Workflow (ONLY when user explicitly asks):**

1. **Run git commands in parallel:**
   ```bash
   git status          # See untracked files
   git diff            # See staged/unstaged changes
   git log             # See recent commits for style
   ```

2. **Draft commit message:**
   - Summarize changes (new feature, bug fix, refactoring, etc.)
   - Focus on "why" rather than "what"
   - Ensure message accurately reflects changes

3. **Execute commit:**
   ```bash
   git add <relevant-files>
   git commit -m "$(cat <<'EOF'
   Commit message here.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   git status  # Verify success
   ```

4. **If pre-commit hook modifies files:**
   - Verify safe to amend: `git log -1 --format='%an %ae'`
   - Check not pushed: `git status` shows "Your branch is ahead"
   - If both true: amend commit
   - Otherwise: create NEW commit

**NEVER:**
- Run additional commands to read/explore code
- Use TodoWrite or Task tools during commit
- Push to remote unless user explicitly requests
- Use git commands with `-i` flag (interactive not supported)
- Create empty commits if no changes

---

## Creating Pull Requests

**PR Workflow (when user explicitly asks):**

1. **Run git commands in parallel:**
   ```bash
   git status                              # See untracked files
   git diff                                # See staged/unstaged changes
   git log [base-branch]...HEAD            # See commit history
   git diff [base-branch]...HEAD           # See full changes
   ```

2. **Analyze ALL commits** (not just latest!)

3. **Create PR:**
   ```bash
   # Push if needed
   git push -u origin <branch-name>

   # Create PR with HEREDOC
   gh pr create --title "PR title" --body "$(cat <<'EOF'
   ## Summary
   - Bullet point 1
   - Bullet point 2

   ## Test plan
   - [ ] Test item 1
   - [ ] Test item 2

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

**NEVER:**
- Use TodoWrite or Task tools during PR creation
- Return without PR URL

---

## Debugging Tips

### Real Device Testing

**Critical issues only visible on real devices:**
- `.navigationBarDrawer(displayMode: .always)` breaks keyboard on iOS 26
- Always test keyboard input on physical devices
- Glass overlays need `.allowsHitTesting(false)` to pass touches through

### SwiftData Issues

**Common problems:**
- Persistent IDs can outlive models → always check existence before fetching
- Clean derived data for macro issues:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*
  ```

### Architecture Verification

**Check provider tags:**
- `"orchestrated:google+openlibrary"` (correct - orchestrated)
- `"google"` (wrong - direct API call violation)
- Trust runtime verification over CLI tools

---

## Professional Objectivity

**Guidelines for Claude Code responses:**
- Prioritize technical accuracy over validating user beliefs
- Focus on facts and problem-solving
- Provide direct, objective technical info without superlatives
- Apply rigorous standards to all ideas, disagree when necessary
- Investigate uncertainty to find truth before confirming beliefs
- Avoid over-the-top validation ("You're absolutely right")

---

## Skills & MCP Integrations

### Available Skills

**mcp-zen-usage:**
- Use for debugging complex issues
- Code review
- Planning features
- Expert analysis
- Ensures Zen MCP tools used appropriately (thinkdeep, debug, codereview, consensus, planner)

**Usage:**
```
Skill: "mcp-zen-usage"
```

### Zen MCP Tools (Brief Reference)

**Available tools from Zen MCP:**
- `mcp__zen__chat` - General collaboration and brainstorming
- `mcp__zen__thinkdeep` - Multi-stage investigation for complex problems
- `mcp__zen__planner` - Interactive planning with revision/branching
- `mcp__zen__consensus` - Multi-model consensus for decisions
- `mcp__zen__codereview` - Systematic code review
- `mcp__zen__debug` - Systematic debugging and root cause analysis
- `mcp__zen__challenge` - Prevents reflexive agreement, forces critical thinking

**Model Selection:**
When user names a specific model, use that exact name. When no model mentioned, use `listmodels` tool to see available options.

**Available Models (14 total):**
- gemini-2.5-flash, gemini-2.5-flash-preview-09-2025, gemini-2.5-pro
- grok-4, grok-4-fast-reasoning
- Use `listmodels` for complete catalog

---

## Token Budget & Performance

**Current Budget:** 200,000 tokens

**Optimization Tips:**
- Use Task tool with Explore agent for open-ended searches (reduces context)
- Use ast-grep over multiple Grep calls
- Read files in parallel when possible
- Don't repeat large code blocks in responses

---

## BooksTrack-Specific Notes

### Zero Warnings Policy
- All PRs must build with zero warnings
- Warnings treated as errors (`-Werror`)
- This is ENFORCED - no exceptions

### PR Checklist (Claude Code specific)
- [ ] Zero warnings (Swift 6 concurrency, deprecated APIs)
- [ ] @Bindable for SwiftData models in child views
- [ ] No Timer.publish in actors (use Task.sleep)
- [ ] Nested supporting types
- [ ] WCAG AA contrast (4.5:1+)
- [ ] Real device testing
- [ ] Used ast-grep for Swift code searches
- [ ] Used Task tool for complex explorations
- [ ] Used TodoWrite for multi-step tasks

### Common Development Workflows

**1. Implementing a Feature:**
```
User: "Add dark mode toggle to Settings"
Claude:
  1. Uses Explore agent to find Settings code
  2. Creates TodoWrite plan (4-5 steps)
  3. Implements feature
  4. Uses code-architecture-reviewer to validate
  5. Runs /test to verify
  6. Runs /build for final check
```

**2. Debugging a Crash:**
```
User: "App crashes on CSV import"
Claude:
  1. Uses Explore agent to find CSV import code
  2. Reads relevant files
  3. Uses mcp__zen__debug for root cause analysis
  4. Implements fix
  5. Adds regression test
  6. Runs /test to verify
```

**3. Code Review:**
```
User: "Review my new Enrichment service"
Claude:
  1. Uses code-architecture-reviewer agent
  2. Checks Swift 6 concurrency, SwiftData patterns
  3. Validates against AGENTS.md critical rules
  4. Suggests improvements
  5. Optionally uses mcp__zen__codereview for deeper analysis
```

**4. Refactoring:**
```
User: "This LibraryView is 800 lines, help me break it down"
Claude:
  1. Uses refactor-planner agent to analyze
  2. Creates refactoring plan with TodoWrite
  3. Uses code-refactor-master to execute
  4. Runs /test after each extracted component
  5. Final /build to verify
```

---

## When to Use AGENTS.md vs CLAUDE.md

**Use AGENTS.md for:**
- Universal project context (tech stack, architecture, critical rules)
- Backend API contract
- Code style and conventions
- SwiftData patterns
- Common development tasks
- Testing patterns

**Use CLAUDE.md for:**
- MCP setup and slash commands
- Built-in agent workflow patterns
- TodoWrite patterns
- Git commit workflow
- PR creation workflow
- Claude Code-specific debugging tips

---

**Last Updated:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
**See Also:** [`AGENTS.md`](AGENTS.md), [`MCP_SETUP.md`](MCP_SETUP.md)