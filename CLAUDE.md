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

## Claude Code-Specific Patterns

### Using Custom Agents (v2.0.43)

**BooksTrack has 3 custom agents for specialized workflows:**

#### `@pm` - Product Manager & Orchestrator
**Autonomy: HIGH** - Operates independently, makes decisions

**When to use:**
- Complex feature implementation
- Multi-step workflows requiring coordination
- When you want Haiku (fast coding) + Grok-4 (review)

**Example:**
```
User: "@pm implement pagination for library view"
PM: [Clarifies requirements → Delegates to Haiku → Reviews with Grok-4 → Validates → Delivers]
```

#### `@zen` - Deep Analysis Specialist
**Autonomy: MEDIUM** - PM orchestrates, Zen provides expert analysis

**When to use:**
- Complex debugging
- Comprehensive code review
- Security audits
- Architectural decisions

**Example:**
```
User: "@zen debug this SwiftData crash"
Zen: [Uses mcp__zen__debug → Investigates → Reports findings]
```

#### `@xcode` - Build, Test & Deploy Specialist  
**Autonomy: MEDIUM** - Executes build/test commands

**When to use:**
- Build validation
- Test execution
- Simulator/device deployment
- TestFlight uploads

**Example:**
```
User: "@xcode run tests"
Xcode: [Executes /test → Reports results]
```

### Using Built-In Agents

**Built-in agents (don't @-mention, they're automatic):**
- **Explore** - Finding files, understanding codebase structure
- **Plan** - Creating implementation plans for complex features

**Example:**
```
User: "Where are errors from the client handled?"
Claude: [Uses Explore agent automatically]
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

### Common Claude Code Workflows

**1. Adding a new feature (with @pm):**
```
1. "@pm implement dark mode toggle"
2. PM clarifies requirements
3. PM delegates to Haiku (implementation)
4. PM delegates to Grok-4 (review)
5. PM runs /build and /test
6. PM delivers complete, tested feature
```

**2. Fixing a bug:**
```
1. Use Explore agent to find relevant code
2. "@zen debug the crash"
3. Zen investigates and identifies root cause
4. Fix the bug
5. Add regression test
6. "@xcode run tests" to verify
```

**3. Refactoring:**
```
1. "@zen review this code for refactoring opportunities"
2. Zen provides analysis and recommendations
3. "@pm implement the refactoring"
4. PM coordinates implementation and validation
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
- Custom agents (@pm, @zen, @xcode)
- TodoWrite patterns
- Git commit workflow
- PR creation workflow
- Claude Code-specific debugging tips

---

**Last Updated:** November 18, 2025
**Maintained by:** oooe (jukasdrj)
**See Also:** [`AGENTS.md`](AGENTS.md), [`MCP_SETUP.md`](MCP_SETUP.md)