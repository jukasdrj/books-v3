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

## 🎯 Multi-Agent Workflow System

### Architecture Overview

**Claude Code orchestrates complex tasks using specialized AI models:**

**🧠 Sonnet 4.5 (Primary)** - You (orchestration, planning, architecture)
- Multi-file refactoring and structural changes
- System architecture decisions
- Complex planning and task decomposition
- Code review coordination

**⚡ Haiku (Fast Implementation)** - Via `mcp__zen__chat`
- Rapid iteration and implementation
- Single-file focused changes
- Simple bug fixes
- Boilerplate generation

**🔍 Grok-4 (Expert Review)** - Via `mcp__zen__codereview` / `mcp__zen__secaudit`
- Security and architecture validation
- Complex code review
- Performance analysis
- Best practices enforcement

**🧪 Gemini 2.5 (Deep Analysis)** - Via `mcp__zen__debug` / `mcp__zen__thinkdeep`
- Root cause analysis
- Multi-stage investigation
- Complex debugging scenarios
- Pattern recognition

---

### Workflow Patterns

**Pattern 1: Fast Feature Implementation**
```
Sonnet (you): Plan feature architecture
  ↓
Haiku: Implement components rapidly via mcp__zen__chat
  ↓
Grok-4: Validate security/architecture via mcp__zen__codereview
  ↓
Sonnet (you): Final integration and testing
```

**Pattern 2: Complex Bug Investigation**
```
Sonnet (you): Initial triage and context gathering
  ↓
Gemini: Deep analysis via mcp__zen__debug or mcp__zen__thinkdeep
  ↓
Haiku: Implement fix via mcp__zen__chat
  ↓
Sonnet (you): Regression test and validation
```

**Pattern 3: Security-Critical Feature**
```
Sonnet (you): Security requirements planning
  ↓
Haiku: Initial implementation via mcp__zen__chat
  ↓
Grok-4: Security audit via mcp__zen__secaudit
  ↓
Sonnet (you): Address findings and final review
```

---

### Built-In Task Tool Agents (Automatic)

**These activate automatically based on task type:**

- **Explore** - Finding files, understanding codebase structure
- **Plan** - Creating implementation plans for complex features
- **code-architecture-reviewer** - Code quality & architecture review
- **code-refactor-master** - Refactoring & code organization
- **refactor-planner** - Creating refactoring plans
- **auto-error-resolver** - Fixing compilation errors

**Examples:**
```
User: "Where are CSV imports handled?"
Sonnet: [Uses Explore agent automatically]

User: "Review my SwiftData service for best practices"
Sonnet: [Uses code-architecture-reviewer agent]

User: "This LibraryView is 800 lines, help me break it down"
Sonnet: [Uses refactor-planner agent]
```

---

### Zen MCP Subagent Delegation

**When to delegate to specialized models:**

**Haiku (Fast Implementation):**
- Simple CRUD operations
- View component creation
- Model boilerplate
- Test case generation
- **Tool:** `mcp__zen__chat` with `model="haiku"`

**Grok-4 (Expert Review):**
- Security vulnerability scanning
- Architecture pattern validation
- Performance bottleneck analysis
- API contract compliance
- **Tools:** `mcp__zen__codereview`, `mcp__zen__secaudit` with `model="grok-4"`

**Gemini 2.5 (Deep Analysis):**
- Mysterious crashes and race conditions
- Complex SwiftData relationship bugs
- Performance regression investigation
- Architectural refactoring planning
- **Tools:** `mcp__zen__debug`, `mcp__zen__thinkdeep`, `mcp__zen__planner` with `model="gemini-2.5-pro"`

**Model Selection:**
Use `listmodels` tool to see all 14 available models. When delegating, specify the model explicitly:

```swift
// Example delegation pattern
User: "Implement the BookDetailView"
Sonnet: [Delegates to Haiku via mcp__zen__chat]
  mcp__zen__chat(
    model: "haiku",
    prompt: "Create BookDetailView with @Bindable Work, cover image, title, author, rating"
  )

User: "Review this for security issues"
Sonnet: [Delegates to Grok-4 via mcp__zen__secaudit]
  mcp__zen__secaudit(
    model: "grok-4",
    audit_focus: "owasp",
    step: "Analyze AuthenticationService for vulnerabilities"
  )
```

---

### Delegation Best Practices

**When to delegate:**
- ✅ Task fits specialist model's strengths
- ✅ Parallel work improves throughput
- ✅ Expert validation needed (security, performance)
- ✅ Deep investigation required (debugging)

**When NOT to delegate:**
- ❌ Simple single-file edits (you handle directly)
- ❌ Task requires cross-file context (you orchestrate)
- ❌ User explicitly wants you to do it
- ❌ Delegation overhead exceeds benefit

**Continuation IDs:**
Always reuse `continuation_id` when resuming conversations with the same model:
```swift
// First call
mcp__zen__debug(model: "gemini-2.5-pro", step: "Initial investigation")
// Returns: continuation_id: "abc123"

// Follow-up call (REUSE ID!)
mcp__zen__debug(
  model: "gemini-2.5-pro",
  continuation_id: "abc123",  // ← CRITICAL!
  step: "Continue investigation with new findings"
)
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

### Multi-Agent Development Workflows

**1. Simple Feature (Single Agent):**
```
User: "Add dark mode toggle to Settings"
Sonnet (you):
  1. Uses Explore agent to find Settings code
  2. Creates TodoWrite plan (4-5 steps)
  3. Implements feature directly (simple, focused change)
  4. Runs /test to verify
  5. Runs /build for final check
```

**2. Complex Feature (Multi-Agent):**
```
User: "Add OAuth authentication with Keycloak"
Sonnet (you):
  1. Creates architecture plan with TodoWrite (security-critical!)
  2. Delegates to Haiku for boilerplate:
     - AuthenticationService stub
     - Token storage models
     - Login/logout flows
  3. Reviews Haiku's implementation
  4. Delegates to Grok-4 for security audit:
     mcp__zen__secaudit(model="grok-4", audit_focus="owasp")
  5. Addresses Grok-4 findings
  6. Runs /test and /build
  7. Final integration testing
```

**3. Mysterious Bug (Deep Analysis):**
```
User: "App crashes randomly on CSV import"
Sonnet (you):
  1. Uses Explore agent to find CSV import code
  2. Reads relevant files for context
  3. Delegates to Gemini for deep analysis:
     mcp__zen__debug(
       model="gemini-2.5-pro",
       step: "Investigate race condition in CSV parsing"
     )
  4. Gemini identifies SwiftData concurrency issue
  5. Delegates to Haiku for fix implementation:
     mcp__zen__chat(model="haiku", prompt="Fix actor isolation in CSVParser")
  6. Adds regression test
  7. Runs /test to verify
```

**4. Code Review (Expert Validation):**
```
User: "Review my new Enrichment service"
Sonnet (you):
  1. Uses code-architecture-reviewer agent for initial scan
  2. Checks Swift 6 concurrency, SwiftData patterns
  3. For security-critical paths, delegates to Grok-4:
     mcp__zen__codereview(
       model="grok-4",
       review_type="security",
       step: "Audit API key handling and network security"
     )
  4. Validates against AGENTS.md critical rules
  5. Consolidates findings and presents recommendations
```

**5. Large Refactoring (Orchestrated):**
```
User: "This LibraryView is 800 lines, help me break it down"
Sonnet (you):
  1. Uses refactor-planner agent to analyze
  2. Creates refactoring plan with TodoWrite (10+ steps)
  3. Delegates component extraction to Haiku:
     - FilterBarView (Haiku)
     - SortOptionsView (Haiku)
     - BookCardView (Haiku)
  4. Reviews each component for patterns/consistency
  5. Updates parent LibraryView (you handle orchestration)
  6. Runs /test after each extraction
  7. Final /build to verify
  8. Optionally: Grok-4 architecture review
```

**6. Parallel Feature Development:**
```
User: "Implement user profiles AND notification system"
Sonnet (you):
  1. Creates parallel TodoWrite plans
  2. Delegates UserProfile to Haiku (Branch A):
     mcp__zen__chat(model="haiku", prompt="UserProfile model + CRUD")
  3. Delegates NotificationService to Haiku (Branch B):
     mcp__zen__chat(model="haiku", prompt="NotificationService with local/push")
  4. Reviews both implementations in parallel
  5. Integrates both features
  6. Runs /test for integration
  7. Final /build
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

## Summary

**CLAUDE.md provides:**
- Multi-agent workflow orchestration (Sonnet → Haiku/Grok-4/Gemini)
- MCP slash commands (/build, /test, /sim, /device-deploy)
- TodoWrite patterns for task management
- Git commit and PR workflows
- Claude Code-specific debugging tips

**For universal project context, see AGENTS.md.**

---

**Last Updated:** November 21, 2025
**Maintained by:** oooe (jukasdrj)
**See Also:** [`AGENTS.md`](AGENTS.md), [`MCP_SETUP.md`](MCP_SETUP.md)