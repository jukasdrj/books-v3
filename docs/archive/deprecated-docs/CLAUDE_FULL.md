# 📚 BooksTrack - Claude Code Guide

**Version 3.7.5 (Build 189+)** | **iOS 26.0+** | **Swift 6.2+** | **Updated: December 25, 2025**

## Agent Role

**Identity:** Books (iOS Frontend) - User Interface  
**Scope:** SwiftUI views, SwiftData persistence, CloudKit sync  
**Upstream:** bendv3 API (api.oooefam.net)  
**Cross-repo docs:** See `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`

---

## Quick Reference

**🤖 AI Context Files:**
- **`CLAUDE.md`** - Claude Code-specific (this file - MCP, slash commands)
- **`.claude/rules/`** - Memory rules (auto-loaded, see v2.0.64)
- **`docs/CROSS_REPO.md`** - Cross-repository architecture pointer

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

### Essential Commands

**🚀 iOS Development (xcodebuild CLI):**

**Safe Testing (Recommended - Prevents System Crashes):**
```bash
/quick-validate  # Build validation without Simulator (safe, fast)
/sim-safe        # Monitored Simulator with resource limits
/kill-xcode      # Emergency cleanup of all Xcode processes
/device-deploy   # Deploy to real device (most resource-efficient)
```

**Standard Testing (Higher Resource Usage):**
```bash
/build         # Quick build validation (can be resource-intensive)
/test          # Run Swift Testing suite
/sim           # Launch Simulator (WARNING: can crash system if low RAM)
```

**⚠️ IMPORTANT: Resource Management**
- **Always prefer `/quick-validate`** over `/build` during development
- **Use `/device-deploy`** for UI testing (much lighter than Simulator)
- **Only use `/sim-safe`** when Simulator specifically needed (has auto-kill limits)
- **Never use `/sim`** if you have <16GB RAM or system is slow
- **Use `/kill-xcode`** immediately if system becomes unresponsive

**Note:** All slash commands use standard `xcodebuild` command-line tools.

### Available MCP Servers

**PAL MCP Server (v9.1.3):**
- **Providers:** Google Gemini ✅, X.AI ✅
- **Available Models:** 14 (use `listmodels` tool)
- **Mode:** Auto model selection

---

## 🛠️ SwiftLint Integration (NEW)

**Added:** December 2025 (Build 189+)

BooksTrack now uses SwiftLint for architectural code quality enforcement, complementing the existing `-Werror` policy and Swift 6 strict concurrency.

### Configuration (`.swiftlint.yml`)

**Philosophy:** Focus on architectural quality, not style (compiler handles correctness).

**Enabled Rule Categories:**
- **Complexity & Architecture:** `cyclomatic_complexity`, `function_body_length`, `file_length`, `type_body_length`
- **SwiftData/SwiftUI Specific:** `force_unwrapping`, `force_cast`, `force_try`
- **Code Quality:** `redundant_discardable_let`, `unused_optional_binding`, `unused_closure_parameter`
- **Performance:** `contains_over_filter_count`, `first_where`

**Custom Rules (BooksTrack-specific):**
```yaml
# Enforce @Bindable for SwiftData models in child views
swiftdata_bindable:
  regex: '@State var \w+: \w*Model'
  message: "Use @Bindable for SwiftData models, not @State"
  severity: warning

# Discourage Timer.publish in actors (Swift 6 concurrency)
no_timer_in_actor:
  regex: 'actor.*\{[^}]*Timer\.publish'
  message: "Use Task.sleep instead of Timer.publish in actors"
  severity: error
```

**Thresholds:**
| Metric | Warning | Error |
|--------|---------|-------|
| Cyclomatic Complexity | 15 | 25 |
| Function Body Length | 60 | 100 |
| File Length | 500 | 800 |
| Type Body Length | 300 | 500 |

**Running SwiftLint:**
```bash
# Run manually
swiftlint lint

# Auto-fix violations
swiftlint lint --autocorrect

# CI/CD (GitHub Actions format)
swiftlint lint --reporter github-actions-logging
```

---

## 🎯 Multi-Agent Workflow System

### Architecture Overview

**Claude Code orchestrates complex tasks using specialized AI models:**

**🧠 Sonnet 4.5 (Primary)** - You (orchestration, planning, architecture)
- Multi-file refactoring and structural changes
- System architecture decisions
- Complex planning and task decomposition
- Code review coordination

**🎯 Opus 4.5 (Strategic Thinking)** - Via Plan subagent or manual delegation
- Complex architectural planning
- Multi-phase project design
- Strategic refactoring plans
- Critical decision-making with deep reasoning
- Available in Claude Code v2.0.51+

**⚡ Haiku 4.5 (Fast Implementation)** - Via `mcp__pal__chat` or Explore subagent
- Rapid iteration and implementation
- Single-file focused changes
- Simple bug fixes
- Boilerplate generation
- Codebase exploration (Explore subagent)
- Auto-uses Sonnet in plan mode ("SonnetPlan" mode)

**🔍 Grok-4 / Grok Code Fast 1 (Expert Review)** - Via `mcp__pal__codereview` / `mcp__pal__secaudit`
- Security and architecture validation
- Complex code review (70.8% SWE-Bench-Verified)
- Performance analysis
- Best practices enforcement

**🧪 Gemini 2.5 Pro / 3.0 Pro (Deep Analysis)** - Via `mcp__pal__debug` / `mcp__pal__thinkdeep`
- Root cause analysis
- Multi-stage investigation
- Complex debugging scenarios
- Pattern recognition
- 1M+ token context for comprehensive analysis

---

### Workflow Patterns

**Pattern 1: Fast Feature Implementation**
```
Sonnet (you): Plan feature architecture
  ↓
Haiku: Implement components rapidly via mcp__pal__chat
  ↓
Grok: Validate security/architecture via mcp__pal__codereview
  ↓
Sonnet (you): Final integration and testing
```

**Pattern 2: Complex Bug Investigation**
```
Sonnet (you): Initial triage and context gathering
  ↓
Gemini: Deep analysis via mcp__pal__debug or mcp__pal__thinkdeep
  ↓
Haiku: Implement fix via mcp__pal__chat
  ↓
Sonnet (you): Regression test and validation
```

**Pattern 3: Security-Critical Feature**
```
Sonnet (you): Security requirements planning
  ↓
Haiku: Initial implementation via mcp__pal__chat
  ↓
Grok: Security audit via mcp__pal__secaudit
  ↓
Sonnet (you): Address findings and final review
```

**Pattern 4: Async Agent Workflow (v2.0.64+)**
```
User: "Start a performance analysis in the background"
Sonnet (you): Launch async agent with run_in_background: true
  ↓
Background Agent: Runs performance profiling independently
  ↓
Sonnet (you): Continue with other tasks (refactoring, features)
  ↓
Background Agent: Sends message to wake up main agent when done
  ↓
Sonnet (you): Use TaskOutput tool to retrieve results
```

**New in v2.0.64:**
- Agents and bash commands can run asynchronously
- Background tasks send messages to wake up main agent
- **TaskOutput tool** replaces AgentOutputTool and BashOutputTool

**When to Use Async Agents:**
- Long-running analysis (performance profiling, security audits)
- Parallel work streams (one agent analyzes while you implement)
- Non-blocking investigations (let agent explore while you code)
- Resource-intensive tasks (offload to background process)

**Launching Async Agents:**
```javascript
Task({
  subagent_type: "performance-analyzer",
  prompt: "Analyze app startup performance",
  run_in_background: true  // ← Key parameter
})

// Later, retrieve results:
TaskOutput({
  task_id: "task_xyz123",
  block: true,     // Wait for completion
  timeout: 60000   // Max wait time (ms)
})
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
- **security-auditor** - Security scanning and OWASP compliance
- **performance-analyzer** - Performance profiling and optimization

**Custom Project Agents (`.claude/agents/`):**

- **pm** - Product manager & development orchestrator (HIGH autonomy)
  - Delegates fast tasks to Haiku, expert review to Grok-4
  - Makes architecture decisions, runs build/test workflows
- **xcode** - iOS build, test, and deployment specialist
  - Uses native xcodebuild CLI for all operations
  - Supports async builds for long-running operations
- **pal** - Deep analysis specialist (PAL MCP tools)
  - Debug, code review, security audit, planning
- **code-review-grok** - Expert code review via Grok-4
- **idb-ui-validator** - iOS UI/UX validation using IDB

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

### PAL MCP Subagent Delegation

**When to delegate to specialized models:**

**Haiku (Fast Implementation):**
- Simple CRUD operations
- View component creation
- Model boilerplate
- Test case generation
- **Tool:** `mcp__pal__chat` with `model="haiku"`

**Grok (Expert Review):**
- Security vulnerability scanning
- Architecture pattern validation
- Performance bottleneck analysis
- API contract compliance
- **Tools:** `mcp__pal__codereview`, `mcp__pal__secaudit` with `model="grok-code-fast-1"` or `"grok-4-1-fast-non-reasoning"`

**Gemini 2.5 (Deep Analysis):**
- Mysterious crashes and race conditions
- Complex SwiftData relationship bugs
- Performance regression investigation
- Architectural refactoring planning
- **Tools:** `mcp__pal__debug`, `mcp__pal__thinkdeep`, `mcp__pal__planner` with `model="gemini-2.5-pro"`

**Model Selection:**
Use `listmodels` tool to see all 14 available models. When delegating, specify the model explicitly:

```swift
// Example delegation pattern
User: "Implement the BookDetailView"
Sonnet: [Delegates to Haiku via mcp__pal__chat]
  mcp__pal__chat(
    model: "haiku",
    prompt: "Create BookDetailView with @Bindable Work, cover image, title, author, rating"
  )

User: "Review this for security issues"
Sonnet: [Delegates to Grok via mcp__pal__secaudit]
  mcp__pal__secaudit(
    model: "grok-code-fast-1",
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
mcp__pal__debug(model: "gemini-2.5-pro", step: "Initial investigation")
// Returns: continuation_id: "abc123"

// Follow-up call (REUSE ID!)
mcp__pal__debug(
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

### AskUserQuestion Tool (Enhanced)

**Recent improvements (v2.0.62+):**
- Multi-select support for non-exclusive choices
- Auto-submission for single-select queries
- Better mobile experience
- **"(Recommended)" indicator** - Add to preferred option label, move to top of list

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
- **Place recommended option first** with "(Recommended)" suffix

**Example (v2.0.62 pattern):**
```swift
AskUserQuestion(
  questions: [{
    question: "Which testing approach should I use?",
    header: "Testing",
    multiSelect: false,
    options: [
      {label: "/quick-validate (Recommended)", description: "Safe build validation"},
      {label: "/device-deploy", description: "Real device (most accurate)"},
      {label: "/sim-safe", description: "Simulator with resource limits"}
    ]
  }]
)
```

---

## 🔄 Checkpoints, Rewind & Sessions

**Claude Code auto-saves before each change.**

**Rewind Methods:**
- Press `Esc` twice in succession
- Use `/rewind` command
- Choose what to restore: code, conversation, or both

**Use Cases:**
- Undo unwanted changes
- Compare different approaches
- Recover from errors
- Restore previous task states

**Note:** Todo list state is preserved across rewinding.

### Named Sessions (v2.0.64)

**Sessions can now be named and resumed:**
- `/rename <name>` - Name current session for easy reference
- `/resume <name>` - Resume named session (in REPL)
- `claude --resume <name>` - Resume from terminal

**Resume Screen Features:**
- Grouped forked sessions for clarity
- `P` key - Preview session contents
- `R` key - Rename session

### Usage Statistics (v2.0.64)

**New `/stats` command provides:**
- Favorite model usage
- Usage graphs over time
- Usage streak tracking
- Session history insights

---

## 🛡️ Safe Testing & Resource Management

### Critical Rule: Prevent System Crashes

**ALWAYS follow this workflow when user requests testing:**

1. **Default to safe validation:**
   ```
   User: "Test my changes"
   Claude: [Uses /quick-validate, not /build or /sim]
   ```

2. **Only use Simulator when UI testing explicitly needed:**
   ```
   User: "Test the new button layout"
   Claude: [Uses /sim-safe with resource monitoring, not /sim]
   ```

3. **Prefer real device testing:**
   ```
   User: "Make sure this works"
   Claude: [Suggests /device-deploy instead of /sim]
   ```

### Safe Testing Workflows

**Pattern A: Code Validation (Default)**
```
User: "Check if this builds"
Claude:
  1. Use /quick-validate (NOT /build)
  2. Check build-quick.log for errors
  3. Report results
  4. If success: suggest real device test if UI changes
```

**Pattern B: UI Testing (When Needed)**
```
User: "Test the new LibraryView UI"
Claude:
  1. Ask: "Should I test on real device (/device-deploy) or Simulator?"
  2. If Simulator: Use /sim-safe (NOT /sim)
  3. Monitor resource usage in logs
  4. Auto-cleanup after testing
```

**Pattern C: Emergency Recovery**
```
User: "System is frozen" / "Xcode won't quit"
Claude:
  1. Use /kill-xcode immediately
  2. Wait 10 seconds
  3. Verify cleanup: ps aux | grep -E "(Xcode|Simulator)"
  4. Recommend /quick-validate for next test
```

### Resource-Aware Decision Making

**Before ANY testing command, check context:**

- **User mentions "slow", "crash", "frozen", "RAM", "CPU"** → Use /quick-validate
- **User has low RAM (<16GB)** → Prefer /device-deploy over Simulator
- **Simple code changes (syntax, logic, refactor)** → Use /quick-validate
- **UI/UX validation needed** → Ask about real device vs Simulator
- **Performance testing** → Real device only (Simulator misleading)

### Available Scripts

All safe testing scripts are in `.claude/scripts/`:

- `quick-validate.sh` - Build without Simulator (2 jobs, 5min timeout)
- `safe-test.sh` - Monitored Simulator (8GB limit, auto-kill)
- `kill-all-xcode.sh` - Emergency cleanup

**Full documentation:** `.claude/SAFE_TESTING.md`

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

### Attribution Setting (v2.0.62)

**Commit and PR attribution is configured via `attribution` setting:**

```json
{
  "attribution": {
    "commit": {
      "trailer": "Co-Authored-By: Claude <noreply@anthropic.com>",
      "footer": "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
    },
    "pr": {
      "footer": "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
    }
  }
}
```

**Note:** The `includeCoAuthoredBy` setting is **deprecated**. Use `attribution` instead.

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

**mcp-pal-usage:**
- Use for debugging complex issues
- Code review
- Planning features
- Expert analysis
- Ensures PAL MCP tools used appropriately (thinkdeep, debug, codereview, consensus, planner)

**Usage:**
```
Skill: "mcp-pal-usage"
```

### PAL MCP Tools (Brief Reference)

**Available tools from PAL MCP:**
- `mcp__pal__chat` - General collaboration and brainstorming
- `mcp__pal__thinkdeep` - Multi-stage investigation for complex problems
- `mcp__pal__planner` - Interactive planning with revision/branching
- `mcp__pal__consensus` - Multi-model consensus for decisions
- `mcp__pal__codereview` - Systematic code review
- `mcp__pal__debug` - Systematic debugging and root cause analysis
- `mcp__pal__challenge` - Prevents reflexive agreement, forces critical thinking

**Model Selection:**
When user names a specific model, use that exact name. When no model mentioned, use `listmodels` tool to see available options.

**Available Models (7 total):**
- **Gemini**: gemini-3-pro-preview, gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash, gemini-2.0-flash-lite
- **Grok**: grok-4-1-fast-non-reasoning (2M context), grok-code-fast-1 (256K context, code specialist)
- Use `listmodels` for complete catalog with aliases

---

## Token Budget & Performance

**Current Budget:** 200,000 tokens

**Auto-Compacting (v2.0.64):** Now instant - no delay when context needs reduction.

**Model Switching (v2.0.65):**
- **macOS**: `option+p` while writing prompt
- **Linux/Windows**: `alt+p` while writing prompt
- Context window info now shown in status line

**Optimization Tips:**
- Use Task tool with Explore agent for open-ended searches (reduces context)
- Use ast-grep over multiple Grep calls
- Read files in parallel when possible
- Don't repeat large code blocks in responses

**File Suggestions (v2.0.65):**
Custom `@` file search configured via `fileSuggestion` setting:
```json
{
  "fileSuggestion": {
    "command": "git ls-files --cached --others --exclude-standard",
    "maxResults": 50
  }
}
```

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
  4. Delegates to Grok for security audit:
     mcp__pal__secaudit(model="grok-code-fast-1", audit_focus="owasp")
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
     mcp__pal__debug(
       model="gemini-2.5-pro",
       step: "Investigate race condition in CSV parsing"
     )
  4. Gemini identifies SwiftData concurrency issue
  5. Delegates to Haiku for fix implementation:
     mcp__pal__chat(model="haiku", prompt="Fix actor isolation in CSVParser")
  6. Adds regression test
  7. Runs /test to verify
```

**4. Code Review (Expert Validation):**
```
User: "Review my new Enrichment service"
Sonnet (you):
  1. Uses code-architecture-reviewer agent for initial scan
  2. Checks Swift 6 concurrency, SwiftData patterns
  3. For security-critical paths, delegates to Grok:
     mcp__pal__codereview(
       model="grok-code-fast-1",
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
  8. Optionally: Grok architecture review
```

**6. Parallel Feature Development:**
```
User: "Implement user profiles AND notification system"
Sonnet (you):
  1. Creates parallel TodoWrite plans
  2. Delegates UserProfile to Haiku (Branch A):
     mcp__pal__chat(model="haiku", prompt="UserProfile model + CRUD")
  3. Delegates NotificationService to Haiku (Branch B):
     mcp__pal__chat(model="haiku", prompt="NotificationService with local/push")
  4. Reviews both implementations in parallel
  5. Integrates both features
  6. Runs /test for integration
  7. Final /build
```

---

## 🌐 Cloudflare Backend Development Patterns

### Automatic Agent Routing

**The following patterns trigger automatic delegation to specialized subagents:**

**Cloudflare Infrastructure Work:**
- Keywords: "D1 schema", "Workers API", "KV storage", "Durable Objects"
- File patterns: `*.worker.js`, `*-api.ts`, `*-service.ts` in backend code
- Auto-routes to: **cloudflare-specialist** subagent (Sonnet model)

**Code Review Requests:**
- Keywords: "review", "security audit", "check for vulnerabilities"
- Context: Any code review or quality assessment
- Auto-routes to: **code-review-grok** subagent (Grok model)

**API Orchestration Patterns:**
- Keywords: "multi-provider", "fallback chain", "orchestration"
- Context: API design or implementation
- Auto-activates: **cloudflare-api-orchestration** skill

### Cloudflare Workflow Examples

**Pattern A: D1 Schema Design**
```
User: "Design the D1 schema for our multi-tenant book data"
Sonnet (you):
  1. Routes to cloudflare-specialist subagent
  2. Specialist provides normalized schema with indexes
  3. You review and integrate with migration plan
  4. Delegates to Haiku for migration script implementation
  5. Routes to code-review-grok for security validation
```

**Pattern B: Workers API Implementation**
```
User: "Implement the /api/v2/books/search endpoint"
Sonnet (you):
  1. Routes to cloudflare-specialist subagent
  2. Specialist implements orchestration layer (Google+OpenLibrary)
  3. cloudflare-api-orchestration skill enforces patterns:
     - Provider tagging
     - Fallback chains
     - KV caching
  4. You integrate with D1 caching strategy
  5. Routes to code-review-grok for final validation
```

**Pattern C: Backend Security Audit**
```
User: "Audit the Workers API for security issues"
Sonnet (you):
  1. Routes to code-review-grok subagent (Grok)
  2. Grok performs OWASP Top 10 audit via mcp__pal__secaudit
  3. You review findings and prioritize fixes
  4. Delegates fixes to Haiku via mcp__pal__chat
  5. Routes back to code-review-grok for validation
```

**Pattern D: KV→D1 Migration**
```
User: "Help me migrate book data from KV to D1"
Sonnet (you):
  1. Routes to cloudflare-specialist for migration strategy
  2. Specialist designs:
     - D1 schema (normalized, indexed)
     - Zero-downtime migration plan
     - Rollback strategy
  3. Creates TodoWrite plan (10+ steps)
  4. Delegates batch migration script to Haiku
  5. You orchestrate incremental migration
  6. Routes to code-review-grok for data integrity validation
```

### Cloudflare-Specific Critical Rules

**Always Enforced (by cloudflare-api-orchestration skill):**

1. **Provider Orchestration MANDATORY**
   - NO direct API calls (e.g., `fetch('https://googleapis.com/...')`)
   - ALL calls go through orchestration layer
   - Tag responses: `"orchestrated:google+openlibrary"`, `"cache:kv"`, etc.

2. **D1 SQL Injection Prevention**
   - Use prepared statements: `DB.prepare('SELECT * FROM books WHERE isbn = ?').bind(isbn)`
   - NEVER string interpolation: `DB.prepare(\`SELECT * FROM books WHERE isbn = '${isbn}'\`)`

3. **KV Key Naming Convention**
   - Format: `namespace:entity:id`
   - Examples: `book:isbn:9780134685991`, `search:query:swift+programming`

4. **Rate Limiting & Circuit Breakers**
   - All public endpoints rate-limited
   - Circuit breakers protect external services
   - Graceful degradation when limits exceeded

5. **Real-Time Updates: V3 Uses SSE Exclusively**
   - ✅ **V3 API**: Server-Sent Events (SSE) for all job streaming (ACTIVE)
     - `GET /v3/jobs/scans/{jobId}/stream` - Scan progress
     - `GET /v3/jobs/imports/{jobId}/stream` - CSV import progress
     - `GET /v3/jobs/enrichment/{jobId}/stream` - Enrichment progress
   - ⚠️ **V1/V2 DEPRECATED**: WebSocket (`GET /ws/progress?jobId=xxx`)
     - iOS app uses WebSocket as automatic fallback when SSE fails
     - Backend sunsets WebSocket 90 days after V3 GA

   **V3 Migration Status (December 2025):**
   - ✅ iOS app migrated to V3 API endpoints
   - ✅ SSE client implemented (`SSEClient.swift`, `SSEResponseHandler.swift`)
   - ✅ V3 DTO models added (`V3Book.swift`, `V3ScanProgress.swift`, etc.)
   - ✅ Sync enrichment mode for small batches (≤50 ISBNs) - HTTP 200
   - ✅ Live API integration tests passing
   - 🔄 WebSocket fallback remains for SSE connection failures

   **Why V3 Chose SSE Over WebSockets:**
   - ✅ Browser-native reconnection with Last-Event-ID
   - ✅ Firewall-friendly (HTTP/1.1, not blocked by corporate proxies)
   - ✅ Automatic retry on connection loss
   - ✅ Simpler than WebSocket for one-way streaming
   - ✅ Can include full data payload in completion events
   - ⚠️ Trade-off: No bidirectional cancel (use `DELETE /v3/jobs/{type}/{jobId}` instead)

### Integration with iOS App

**API Contract (v3.2):**
- iOS app expects provider metadata in all responses
- Caching headers inform SwiftData sync strategy
- **SSE events for real-time updates** (V3 primary transport)
- **WebSocket fallback** (V1/V2 legacy, automatic when SSE fails)
- Error responses follow RFC 9457 Problem Details format

### Agent & Subagent Configuration

**Main Thread Agent Configuration (v2.0.59+):**

Configure the main conversation thread to use a specific agent's system prompt, tool restrictions, and model:

```json
{
  "agent": "cloudflare-specialist"
}
```

**This makes the main thread behave like the specified agent.**

**Override agent for a session:**
```bash
claude --agent cloudflare-specialist
```

**When to use:**
- Working on Cloudflare backend exclusively → `agent: "cloudflare-specialist"`
- Security-focused development → `agent: "security-auditor"`
- Performance optimization sprint → `agent: "performance-analyzer"`
- General development → Omit (use default Sonnet behavior)

---

**Subagent Model Configuration:**

**Configured in `.claude/settings.json`:**

```json
{
  "subagentModels": {
    "cloudflare-specialist": "sonnet",
    "code-review-grok": "grok-code-fast-1",
    "code-architecture-reviewer": "grok-code-fast-1",
    "security-auditor": "grok-code-fast-1",
    "performance-analyzer": "gemini-2.5-pro",
    "refactor-planner": "opus",
    "Plan": "opus",
    "Explore": "haiku"
  }
}
```

**Why these models:**
- **Sonnet 4.5** for Cloudflare specialist (complex architecture decisions)
- **Opus 4.5** for planning agents (strategic thinking, comprehensive plans)
- **Haiku 4.5** for exploration (speed, efficiency, auto-uses Sonnet in plan mode)
- **Grok-4 / Grok Code Fast 1** for code review & security (expert validation, 70.8% SWE-Bench)
- **Gemini 2.5 Pro / 3.0 Pro** for performance analysis (deep investigation, 1M context)

### Hooks & Automation

**Configured in `.claude/settings.json`:**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": ".claude/hooks/session-start.sh"}]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": ".claude/hooks/session-end.sh"}]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": ".claude/hooks/permission-request.sh"}]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": ".claude/hooks/pre-commit.sh"}]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": ".claude/hooks/subagent-start.sh"}]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": ".claude/hooks/subagent-stop.sh"}]
      }
    ]
  }
}
```

**Available Hook Events (v2.0.64):**

**Session Lifecycle:**
- **SessionStart** (v1.0.61+) - Triggered when Claude Code session begins
  - Use for: Environment checks, initialization, welcome messages
  - Hook: `.claude/hooks/session-start.sh`

- **SessionEnd** (v1.0.85+) - Triggered when Claude Code session ends
  - Use for: Cleanup, final checks, session summaries
  - Hook: `.claude/hooks/session-end.sh`

**Permission Management:**
- **PermissionRequest** (v2.0.45+) - Triggered when tool permission requested
  - Use for: Auto-approve/deny based on custom logic
  - Hook: `.claude/hooks/permission-request.sh`
  - Can modify tool inputs or update permissions

**Tool Execution:**
- **PreToolUse** (v1.0.38+) - Triggered before tool execution
  - Use for: Validation, security checks, pre-flight checks
  - Hook: `.claude/hooks/pre-commit.sh` (for Bash commands)

**Subagent Lifecycle (Updated v2.0.64):**
- **SubagentStart** (v2.0.43+) - Triggered when subagent starts
  - Use for: Logging, resource allocation, context preparation
  - Hook: `.claude/hooks/subagent-start.sh`
  - Receives: `agent_id`, `agent_type`, `run_in_background`, `CLAUDE_PROJECT_DIR`
  - **New**: Supports async agents with background execution

- **SubagentStop** (v2.0.42+) - Triggered when subagent completes
  - Use for: Review findings, archive transcripts, cleanup
  - Hook: `.claude/hooks/subagent-stop.sh`
  - Receives: `agent_id`, `agent_type`, `was_background`, `agent_transcript_path`
  - **New**: Indicates if agent ran in background

**New in v2.0.64:**
- Async agents can send messages to wake up main agent
- `TaskOutput` tool replaces `AgentOutputTool` and `BashOutputTool`
- Background bash commands also supported

**Hook Scripts (in `.claude/hooks/`):**
- `session-start.sh` - Environment checks, memory warnings, OpenAPI freshness
- `session-end.sh` - Cleanup, uncommitted changes check, session logging
- `permission-request.sh` - Auto-approve safe reads, deny dangerous operations
- `pre-commit.sh` - Validates bash commands, checks for sensitive files
- `subagent-start.sh` - Logs subagent activation
- `subagent-stop.sh` - Archives transcripts, prompts to review findings

**Automatic triggers:**
- Bash command → pre-commit validation
- Subagent starts → log activation
- Subagent completes → prompt to integrate results

### Memory Rules (`.claude/rules/`)

**Auto-loaded context rules for specific scenarios:**

| Rule File | Trigger Keywords | Purpose |
|-----------|------------------|---------|
| `safe-testing.md` | test, build, run, validate, simulator | Safe testing workflow enforcement |
| `swift-concurrency.md` | @Observable, @MainActor, actors, SwiftData | Swift 6 concurrency compliance |
| `async-agents.md` | background, async, parallel | Async agent usage patterns |
| `attribution.md` | commit, attribution | Git attribution settings |

**Rule Content Examples:**

**safe-testing.md:**
- Enforces `/quick-validate` as default (not `/build`)
- Recommends `/device-deploy` over `/sim`
- Provides emergency recovery with `/kill-xcode`

**swift-concurrency.md:**
- Requires `@MainActor` for all Observable classes
- Requires `@Bindable` for SwiftData in child views
- Prohibits `Timer.publish` in actors (use `Task.sleep`)

### Advanced Settings (`.claude/settings.json`)

**Async Agent Configuration:**
```json
{
  "asyncAgents": {
    "enabled": true,
    "maxConcurrent": 3,
    "wakeOnMessage": true
  }
}
```

**Compact Mode (Auto-Compacting):**
```json
{
  "compactMode": {
    "enabled": true,
    "threshold": 0.8
  }
}
```

**Environment Variables:**
```json
{
  "env": {
    "MAX_MCP_OUTPUT_TOKENS": "50000",
    "CLAUDE_CODE_SUBAGENT_PARALLEL": "true"
  }
}
```

**Permission Rules:**
- Auto-allow: Slash commands, safe git reads, file operations, PAL MCP tools
- Require approval: `git add`, `git commit`, `git push`, `rm`, `mv`, `cp`
- Deny: `rm -rf /`, `sudo rm`, `git push --force`

### Actions & Workflows

**Configured in `.claude/actions.yaml`:**

- **Zero Warnings Check** - Validates build before commit
- **SwiftData Model Validation** - Checks @Bindable usage on @Model changes
- **API Contract Check** - Verifies provider orchestration
- **Swift 6 Concurrency Audit** - Checks actor isolation
- **Test Coverage Reminder** - Prompts for tests on new services

---

## 🔧 Known Tech Debt & Sunset Plan

### API Sunset Timeline

| Component | Status | Sunset Date | Replacement |
|-----------|--------|-------------|-------------|
| V1 Search API (`/v1/search/*`) | Deprecated | March 1, 2026 | V3 API (`/v3/books/*`) |
| V1/V2 WebSocket | Deprecated | 90 days post-V3 GA | SSE (`/v3/jobs/{type}/{id}/stream`) |
| V2 Workflow Import | Experimental | Q2 2026 (TBD) | Evaluate adoption |
| V1 Enrichment (`/api/enrichment/*`) | Deprecated | March 1, 2026 | V3 (`/v3/books/enrich`) |

### Legacy Code Locations

**WebSocket Infrastructure (V1/V2 Fallback):**
- `Common/GenericWebSocketHandler.swift` - Generic handler
- `Common/WebSocketProgressManager.swift` - Progress tracking
- `Common/WebSocketHelpers.swift` - Utilities

**V1/V2 API Endpoints:** (See `EnrichmentConfig.swift`)
- All deprecated endpoints marked with `@available(*, deprecated)`
- Emergency fallback controlled by `FeatureFlags.disableCanonicalEnrichment`

**V3-to-V2 Compatibility:**
- `Services/V3ToV2Mapper.swift` - Maps V3 responses to SwiftData models
- Required until native V3 data model migration (long-term)

### Debug Print Statements

**Status:** 433+ print statements in codebase (mostly in `#if DEBUG` blocks)

**Priority Cleanup Areas:**
- `Common/WebSocketProgressManager.swift` - 40+ unwrapped prints
- `ReviewQueue/CorrectionView.swift` - 6 prints
- `ReviewQueue/ManualMatchView.swift` - 1 print

**Recommendation:** Replace with structured `Logger` from `os.log`

### Active Tech Debt TODOs

| File | Issue | Priority |
|------|-------|----------|
| `APIIntegrationTests.swift:28` | Migrate to V3 API before March 2026 | High |
| `EnrichmentQueue.swift:695` | Uses V1 cancel endpoint | Medium |
| `V3BooksService.swift:175` | Pagination TODO | Low |
| `BookSearchAPIService.swift:512` | Analytics TODO | Low |

### Cleanup Checklist

- [ ] Migrate `APIIntegrationTests.swift` to V3 API (before March 2026)
- [ ] Migrate `EnrichmentQueue` to V3 cancel endpoint
- [ ] Replace debug `print()` with `Logger`
- [ ] Remove WebSocket infrastructure (90 days post-V3 GA)
- [ ] Evaluate V2 workflow import adoption (Q2 2026)
- [ ] Remove `V3ToV2Mapper` (when native V3 models adopted)

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
- SwiftLint integration with architectural quality rules
- TodoWrite patterns for task management
- Git commit and PR workflows
- Claude Code-specific debugging tips
- Tech debt tracking and sunset timelines

**For universal project context, see AGENTS.md.**

---

**Last Updated:** December 25, 2025 (Claude Code v2.0.65, BooksTrack v3.7.5, Build 189)
**Maintained by:** oooe (jukasdrj)
**See Also:** [`AGENTS.md`](AGENTS.md)

**Recent Updates (December 2025):**
- 🔧 **SwiftLint Integration**: Added `.swiftlint.yml` with architectural quality rules (Build 189)
- 🚀 **V3 API Migration**: iOS app fully migrated to V3 API with SSE streaming
- 📱 **Custom Agents**: Added pm, xcode, pal, code-review-grok, idb-ui-validator agents
- 📋 **Memory Rules**: Documented `.claude/rules/` auto-loaded context rules
- ⚙️ **Settings**: Added asyncAgents, compactMode, permission rules documentation
- 🔄 **Live API Tests**: Added integration tests for V3 DTOs and BookSearchAPIService

**Claude Code v2.0.62-65 Features:**
- ⚡ **v2.0.65**: Model switching during prompt (`option+p`/`alt+p`), context window in status line, `fileSuggestion` setting
- 📛 **v2.0.64**: Named sessions (`/rename`, `/resume <name>`), `/stats` command, instant auto-compacting
- 🔄 **v2.0.64**: Async agents with `run_in_background`, `TaskOutput` tool (replaces AgentOutputTool/BashOutputTool)
- 📁 **v2.0.64**: `.claude/rules/` directory support for memory rules
- ⭐ **v2.0.62**: "(Recommended)" indicator for multiple-choice options
- 🏷️ **v2.0.62**: `attribution` setting (deprecates `includeCoAuthoredBy`)
- 🐛 **v2.0.62**: Fixed duplicate slash commands, skill symlink issues, IDE diff tab closing

**Previous Updates:**
- ✨ Added Opus 4.5 and Haiku 4.5 model documentation
- 🔄 Added background agent workflow patterns (v2.0.60)
- 🪝 Added PermissionRequest, SessionStart, SessionEnd hooks
- 📚 Created comprehensive mcp-pal-usage skill guide
- ⚙️ Documented `agent` setting for main thread configuration (v2.0.59)