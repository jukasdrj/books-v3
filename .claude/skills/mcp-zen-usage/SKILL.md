---
name: mcp-zen-usage
description: |
  Ensures proper use of Zen MCP tools (thinkdeep, debug, codereview, consensus, planner)
  for complex tasks requiring deep analysis, multi-model collaboration, or systematic
  investigation.

  Auto-activates when:
  - User requests debugging, code review, or planning assistance
  - Complex problems require systematic investigation
  - Multi-model consensus needed for architectural decisions
  - Deep thinking required for root cause analysis

  Provides guidance on:
  - When to use each Zen MCP tool
  - Proper continuation_id management
  - Model selection strategies
  - Workflow orchestration patterns

allowed-tools: ["Read", "Grep", "mcp__zen__chat", "mcp__zen__thinkdeep", "mcp__zen__debug", "mcp__zen__codereview", "mcp__zen__consensus", "mcp__zen__planner", "mcp__zen__secaudit", "mcp__zen__precommit", "mcp__zen__listmodels"]
---

# Zen MCP Usage Skill

This skill provides guidance on using Zen MCP tools effectively for complex software engineering tasks.

## Available Zen MCP Tools

### 1. `mcp__zen__chat` - General Collaboration
**Use for:**
- Brainstorming and ideation
- Getting second opinions
- Quick consultations
- Validation of approaches

**Example:**
```javascript
mcp__zen__chat({
  model: "haiku",  // Fast for simple tasks
  prompt: "Review this approach for implementing dark mode",
  absolute_file_paths: ["/path/to/ThemeManager.swift"],
  working_directory_absolute_path: "/path/to/project"
})
```

**When NOT to use:**
- Systematic debugging → use `debug` instead
- Code review → use `codereview` instead
- Strategic planning → use `planner` instead

---

### 2. `mcp__zen__debug` - Systematic Debugging
**Use for:**
- Complex bugs with unclear root cause
- Race conditions and concurrency issues
- Memory leaks and performance problems
- Mysterious crashes

**Example:**
```javascript
mcp__zen__debug({
  model: "gemini-2.5-pro",  // Deep analysis capability
  step: "Investigate SwiftData relationship crash in LibraryView",
  step_number: 1,
  total_steps: 3,
  next_step_required: true,
  findings: "App crashes when accessing book.author.name. Suspect SwiftData fault issue.",
  hypothesis: "Accessing unfaulted relationship on background thread",
  relevant_files: ["/path/to/LibraryView.swift", "/path/to/Work.swift"],
  files_checked: ["/path/to/LibraryView.swift"],
  confidence: "medium"
})
```

**Confidence levels:**
- `exploring` - Just starting investigation
- `low` - Early hypothesis
- `medium` - Some evidence gathered
- `high` - Strong evidence
- `very_high` - Very confident
- `almost_certain` - Nearly proven
- `certain` - 100% confirmed locally (skips external validation)

**Critical:** Always reuse `continuation_id` for multi-step debugging!

---

### 3. `mcp__zen__codereview` - Systematic Code Review
**Use for:**
- Comprehensive quality assessment
- Security vulnerability scanning
- Architecture validation
- Performance analysis

**Review types:**
- `full` - Complete review (quality, security, performance, architecture)
- `security` - Security-focused audit
- `performance` - Performance bottleneck analysis
- `quick` - Fast high-level review

**Example:**
```javascript
mcp__zen__codereview({
  model: "grok-code-fast-1",  // Expert review capability
  step: "Review EnrichmentService for security and performance",
  step_number: 1,
  total_steps: 2,
  next_step_required: true,
  findings: "Starting comprehensive review...",
  relevant_files: ["/path/to/EnrichmentService.swift"],
  review_type: "full",
  confidence: "medium"
})
```

**Validation types:**
- `external` (default) - Expert model validation after your review
- `internal` - Local-only review (faster, less thorough)

---

### 4. `mcp__zen__secaudit` - Security Audit
**Use for:**
- OWASP Top 10 vulnerability scanning
- Security compliance validation
- Pre-deployment security checks
- Sensitive code path review

**Audit focus:**
- `owasp` - OWASP Top 10 vulnerabilities
- `compliance` - Regulatory compliance (GDPR, SOC2, etc.)
- `infrastructure` - Infrastructure security (API keys, secrets)
- `dependencies` - Third-party dependency vulnerabilities
- `comprehensive` - All of the above

**Example:**
```javascript
mcp__zen__secaudit({
  model: "grok-code-fast-1",  // Security expertise
  step: "Audit AuthenticationService for OWASP vulnerabilities",
  step_number: 1,
  total_steps: 2,
  next_step_required: true,
  findings: "Analyzing API key handling and session management...",
  relevant_files: ["/path/to/AuthenticationService.swift"],
  audit_focus: "owasp",
  threat_level: "high",
  confidence: "medium"
})
```

**Threat levels:**
- `low` - Internal tools, non-production
- `medium` - Production app with limited exposure
- `high` - Public-facing production service
- `critical` - Handles sensitive PII or financial data

---

### 5. `mcp__zen__planner` - Interactive Planning
**Use for:**
- Complex project planning
- Multi-phase migrations
- Architectural design sessions
- Strategic refactoring plans

**Features:**
- Step-by-step planning with revision capability
- Branch exploration for alternative approaches
- Expert model validation of plans

**Example:**
```javascript
mcp__zen__planner({
  model: "gemini-2.5-pro",  // Strategic thinking
  step: "Plan migration from KV storage to D1 database",
  step_number: 1,
  total_steps: 5,
  next_step_required: true
})

// Later: Branch to explore alternative approach
mcp__zen__planner({
  continuation_id: "abc123",  // REUSE ID!
  model: "gemini-2.5-pro",
  step: "Explore zero-downtime migration using dual-write pattern",
  step_number: 3,
  total_steps: 5,
  next_step_required: true,
  is_branch_point: true,
  branch_id: "zero-downtime-approach",
  branch_from_step: 2
})
```

---

### 6. `mcp__zen__consensus` - Multi-Model Consensus
**Use for:**
- Critical architectural decisions
- Technology selection
- Complex trade-off analysis
- Design pattern selection

**Example:**
```javascript
mcp__zen__consensus({
  step: "Evaluate: Should we use SwiftData or Core Data for BooksTrack v4?",
  step_number: 1,
  total_steps: 4,  // 3 models + synthesis
  next_step_required: true,
  findings: "Initial analysis: SwiftData offers modern API, Core Data more mature",
  models: [
    {model: "gemini-2.5-pro", stance: "for"},      // Pro-SwiftData
    {model: "grok-code-fast-1", stance: "against"}, // Pro-Core Data
    {model: "claude-opus-4", stance: "neutral"}     // Unbiased analysis
  ],
  relevant_files: ["/path/to/Work.swift", "/path/to/Author.swift"]
})
```

**Stances:**
- `for` - Argue in favor of proposal
- `against` - Argue against proposal
- `neutral` - Unbiased analysis

---

### 7. `mcp__zen__precommit` - Pre-Commit Validation
**Use for:**
- Validating git changes before commit
- Multi-repository change validation
- Impact assessment
- Completeness verification

**Example:**
```javascript
mcp__zen__precommit({
  model: "grok-code-fast-1",
  step: "Validate staged changes for completeness and security",
  path: "/path/to/repo",
  step_number: 1,
  total_steps: 3,
  next_step_required: true,
  findings: "Analyzing git diff and impact...",
  include_staged: true,
  include_unstaged: true,
  confidence: "medium"
})
```

**Validation options:**
- Compare to specific branch: `compare_to: "main"`
- Focus on specific concerns: `focus_on: "security"`
- Filter by severity: `severity_filter: "high"`

---

### 8. `mcp__zen__thinkdeep` - Deep Thinking
**Use for:**
- Complex problem analysis
- Architecture decisions requiring deep reasoning
- Performance challenges
- Multi-stage investigation

**Similar to `debug` but more general-purpose.**

**Example:**
```javascript
mcp__zen__thinkdeep({
  model: "gemini-2.5-pro",
  step: "Analyze the architectural implications of real-time sync",
  step_number: 1,
  total_steps: 3,
  next_step_required: true,
  findings: "Exploring WebSocket vs SSE vs polling trade-offs...",
  hypothesis: "SSE provides best balance of simplicity and reliability",
  focus_areas: ["architecture", "performance", "reliability"],
  confidence: "medium"
})
```

---

## Model Selection Guide

**Use `listmodels` to see all available models:**
```javascript
mcp__zen__listmodels()
```

**Top Models (as of v2.0.60):**

- **grok-code-fast-1** (256K context, code specialist, 70.8% SWE-Bench)
  - Best for: Code review, security audits, architecture validation
  - Score: 100

- **gemini-2.5-pro** (1M context, thinking mode, code generation)
  - Best for: Deep analysis, debugging, strategic planning
  - Score: 100

- **gemini-3-pro-preview** (1M context, thinking mode, latest)
  - Best for: Cutting-edge analysis, complex reasoning
  - Score: 100

- **grok-4-1-fast-non-reasoning** (2M context)
  - Best for: Large codebase analysis, massive context requirements
  - Score: 100

- **haiku** (fast, efficient)
  - Best for: Quick consultations, simple implementations
  - Auto-uses Sonnet in plan mode

---

## Critical Continuation Pattern

**ALWAYS reuse `continuation_id` for multi-turn conversations:**

```javascript
// First call
const step1 = await mcp__zen__debug({
  model: "gemini-2.5-pro",
  step: "Investigate crash",
  // ...
});
// Returns: continuation_id: "xyz789"

// Follow-up (CRITICAL: REUSE ID!)
const step2 = await mcp__zen__debug({
  continuation_id: "xyz789",  // ← MUST REUSE!
  model: "gemini-2.5-pro",
  step: "Continue investigation with new findings",
  // ...
});
```

**Why this matters:**
- Preserves full conversation context
- Maintains investigation state
- Enables seamless resumption
- Prevents redundant work

---

## Workflow Decision Tree

```
User request
  ├─ "Debug this crash/bug/issue"
  │    → Use mcp__zen__debug
  │
  ├─ "Review this code"
  │    → Use mcp__zen__codereview
  │
  ├─ "Audit for security issues"
  │    → Use mcp__zen__secaudit
  │
  ├─ "Plan this migration/feature"
  │    → Use mcp__zen__planner
  │
  ├─ "Should we use X or Y?"
  │    → Use mcp__zen__consensus
  │
  ├─ "Validate my changes before commit"
  │    → Use mcp__zen__precommit
  │
  ├─ "Analyze this complex problem"
  │    → Use mcp__zen__thinkdeep
  │
  └─ "Quick question about approach"
       → Use mcp__zen__chat
```

---

## Integration with Claude Code Agents

**This skill works alongside:**

- **cloudflare-specialist** - Cloudflare-specific architecture
- **code-review-grok** - Wraps `mcp__zen__codereview` with project context
- **security-auditor** - Wraps `mcp__zen__secaudit` with project context
- **performance-analyzer** - Wraps `mcp__zen__thinkdeep` for performance

**Skill activates proactively to ensure:**
- Correct tool selection
- Proper continuation_id management
- Appropriate model selection
- Complete workflow execution

---

## Common Anti-Patterns

### ❌ Don't: Forget continuation_id
```javascript
// First call - gets continuation_id
mcp__zen__debug({ step: "Step 1", ... });

// Second call - WRONG! No continuation_id
mcp__zen__debug({ step: "Step 2", ... });
```

### ✅ Do: Always reuse continuation_id
```javascript
// First call
const result1 = mcp__zen__debug({ step: "Step 1", ... });
const contId = result1.continuation_id;

// Second call - CORRECT!
mcp__zen__debug({ continuation_id: contId, step: "Step 2", ... });
```

---

### ❌ Don't: Use wrong tool for task
```javascript
// Debugging a crash with chat tool (too shallow)
mcp__zen__chat({ prompt: "Why does this crash?" });
```

### ✅ Do: Use systematic debugging tool
```javascript
// Proper systematic investigation
mcp__zen__debug({
  step: "Investigate crash in LibraryView",
  hypothesis: "SwiftData concurrency issue",
  // ...
});
```

---

### ❌ Don't: Skip model selection
```javascript
// No model specified - uses default
mcp__zen__codereview({ step: "Review code", ... });
```

### ✅ Do: Choose appropriate model
```javascript
// Explicit model selection for security expertise
mcp__zen__codereview({
  model: "grok-code-fast-1",  // Security specialist
  step: "Review for OWASP vulnerabilities",
  // ...
});
```

---

## Quick Reference Card

| Task | Tool | Model | Why |
|------|------|-------|-----|
| Debug crash | `debug` | gemini-2.5-pro | Deep analysis, 1M context |
| Review code | `codereview` | grok-code-fast-1 | Code specialist, security focus |
| Security audit | `secaudit` | grok-code-fast-1 | OWASP expertise |
| Plan migration | `planner` | gemini-2.5-pro | Strategic thinking |
| Tech decision | `consensus` | 3+ models | Multiple perspectives |
| Validate commit | `precommit` | grok-code-fast-1 | Quality assurance |
| Analyze problem | `thinkdeep` | gemini-2.5-pro | Deep reasoning |
| Quick question | `chat` | haiku | Fast, efficient |

---

**Last Updated:** December 6, 2025 (v2.0.60)
**Maintained by:** BooksTrack Project
**Related Skills:** cloudflare-api-orchestration
**Related Agents:** code-review-grok, security-auditor, performance-analyzer
