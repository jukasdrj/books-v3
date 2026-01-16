# Planning-with-Files & PM Orchestration Setup Analysis

**Date:** 2026-01-14
**Goal:** Configure automatic planning-with-files activation, PM orchestration, and PAL MCP review gates

---

## Executive Summary

Your repo needs **3 configuration layers** to achieve automatic planning-with-files usage, PM orchestration, and PAL MCP review gates:

1. **Hooks** (runtime enforcement at key checkpoints)
2. **Memory Rules** (context-aware guidance via auto-loading)
3. **customInstructions** (baseline behavior)

**Context:** Solo-dev family app (you + family users)
- Security posture: Pragmatic, not corporate paranoid
- Attack surface: Low (family-only, not public SaaS)
- Focus: Code quality, maintainability, iteration speed over enterprise compliance
- PAL reviews emphasize: Architecture, bugs, performance (not exhaustive pentesting)

**Current State:** ✅ Excellent foundation already in place
- Comprehensive hooks infrastructure (8 hooks configured)
- Memory rules system with auto-loading (6 rules active)
- Planning-with-files skill installed and working
- PAL MCP integration fully documented

**Gaps:** 3 specific enhancements needed
1. No automatic multi-step task detection → Add UserPromptSubmit hook
2. PM role not enforced → Add memory rule + update customInstructions
3. No PAL review gate after subagents → Enhance SubagentStop hook

---

## Recommended Implementation Strategy

### Layer 1: customInstructions (Base Behavior)

**Update `.claude/settings.json` line 3:**

```json
"customInstructions": "CRITICAL: Safe Testing Policy - ALWAYS use /quick-validate instead of /build. NEVER use /sim (use /sim-safe or /device-deploy). PM ORCHESTRATION MODE: You are a strong Product Manager orchestrating development via specialized subagents. For multi-step tasks: (1) Use /planning-with-files to create task_plan.md/findings.md/progress.md, (2) Delegate implementation to Haiku/Explore, (3) Delegate review to Grok/Gemini via PAL MCP, (4) Integrate validated outputs. Memory rules provide detailed guidance based on context."
```

**Why:**
- Sets baseline PM role expectation
- Short and directive (doesn't consume excessive context)
- References memory rules for details (DRY principle)
- Always loaded (highest authority)

---

### Layer 2: Memory Rules (Context-Aware Guidance)

#### A) Create `.claude/rules/pm-orchestration.md`

**Triggers:** "implement", "feature", "build", "task", "workflow", "multi-step", "complex", "phase"

**Content:**
```markdown
# PM Orchestration Mode (Auto-loaded)

You are operating as a **strong Product Manager**, not an implementer.

## Project Context

**BooksTrack** = Solo-dev family app (dev + family users)
- **Security stance**: Pragmatic, not paranoid. Basic hygiene, not OWASP compliance theater.
- **Attack surface**: Low (family-only, private API, no public signups)
- **Priorities**: Code quality > maintainability > iteration speed > exhaustive security audits
- **PAL review focus**: Architecture decisions, correctness, performance, obvious bugs (not theoretical attack vectors)

## PM Responsibilities

1. **Planning First**: Use `/planning-with-files` for complex tasks (>5 tool calls)
2. **Delegate Implementation**: Haiku/Explore agents implement, you orchestrate
3. **Delegate Review**: Grok/Gemini via PAL MCP tools validate quality
4. **Integrate**: You integrate validated outputs, don't write code directly

## Delegation Patterns

**Feature Implementation:**
- You: Create task_plan.md, break into phases
- Haiku: Implement each phase (use Task tool with Explore agent)
- Grok: Review via mcp__pal__codereview (grok-code-fast-1) - focus: correctness, architecture, performance
- You: Integrate validated code, mark phase complete

**Bug Investigation:**
- You: Create task_plan.md, define hypothesis
- Gemini: Deep analysis via mcp__pal__debug (gemini-2.5-pro)
- Haiku: Apply fix based on Gemini's findings
- You: Validate fix, update findings.md

**Security Work:**
- You: Create task_plan.md, identify security surface
- Grok: Pragmatic audit via mcp__pal__secaudit (grok-code-fast-1)
  - Focus: API keys exposure, obvious SQL injection, broken auth
  - Skip: Theoretical DOS vectors, obscure timing attacks, compliance checkboxes
- Haiku: Implement reasonable hardening
- You: Accept when "good enough for family app", update task_plan.md

## When NOT to Delegate

- Simple edits (typo fixes, single-line changes)
- User explicitly requests "you implement this directly"
- Cross-file context makes delegation inefficient

## Planning-with-Files Integration

**Before starting complex work:**
1. Check: Does task_plan.md exist?
2. If no: Run `/planning-with-files` or create manually
3. If yes: Read task_plan.md to understand current phase
4. Always update findings.md after discoveries (2-Action Rule)
5. Always update progress.md throughout session

**Phase Completion:**
- Mark phase: `in_progress` → `complete` in task_plan.md
- Log errors in both task_plan.md and progress.md
- Update findings.md with discoveries
- Trigger PAL review before marking complete
```

**Add to `.claude/settings.json` memoryRules.triggerKeywords:**
```json
"pm-orchestration.md": ["implement", "feature", "build", "task", "workflow", "multi-step", "complex", "phase", "orchestrate", "delegate"]
```

---

#### B) Create `.claude/rules/planning-automation.md`

**Triggers:** "multi-step", "phase", "migration", "implement feature", "add feature"

**Content:**
```markdown
# Planning-with-Files Automation (Auto-loaded)

When you detect a **complex multi-step task**, immediately use `/planning-with-files`.

## Detection Patterns

**Trigger planning for:**
- "implement feature" / "add feature" / "build new"
- "migration" / "refactor entire" / "redesign"
- User explicitly mentions "phase 1" / "step 1"
- Lists with 3+ implementation steps
- Work requiring >5 tool calls

**Don't trigger for:**
- Simple bug fixes
- Single-file edits
- Quick questions
- Documentation updates

## Automatic Workflow

1. **Detect**: UserPromptSubmit hook identifies complex task
2. **Check**: Do task_plan.md/findings.md/progress.md exist?
3. **If missing**: Hook injects reminder, you create via `/planning-with-files`
4. **If exists**: Read task_plan.md to understand current phase
5. **Throughout**: Update files per 2-Action Rule and phase completion

## File Responsibilities

**task_plan.md:**
- Phases with checkboxes
- Current phase status (pending/in_progress/complete)
- Decisions table
- Errors table

**findings.md:**
- Research discoveries (after every 2 view/search operations)
- Technical decisions with rationale
- Patterns identified
- File locations

**progress.md:**
- Session log with timestamps
- Actions taken per phase
- Test results table
- Files read/modified

## Integration with PM Role

Planning-with-files provides the **persistent memory** for PM orchestration:
- You create the plan (PM)
- Subagents implement phases (workers)
- PAL MCP validates outputs (QA)
- You integrate validated work (PM)
- All tracked in planning files (audit trail)
```

**Add to `.claude/settings.json` memoryRules.triggerKeywords:**
```json
"planning-automation.md": ["multi-step", "phase", "migration", "implement feature", "add feature", "refactor", "redesign"]
```

---

### Layer 3: Hooks (Runtime Enforcement)

#### A) Create `.claude/hooks/user-prompt-submit.sh`

**Purpose:** Detect multi-step tasks at entry point, remind to use planning-with-files

**File:** `/Users/juju/dev_repos/books-v3/.claude/hooks/user-prompt-submit.sh`

```bash
#!/bin/bash

# UserPromptSubmit Hook (v2.0.65+)
# Detects complex multi-step tasks and reminds to use planning-with-files
# Triggered before Claude processes user input

set -e

USER_INPUT="${USER_INPUT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Multi-step task indicators (regex patterns)
COMPLEX_PATTERNS=(
    "implement.*feature"
    "add.*feature"
    "build.*new"
    "migration"
    "refactor.*entire"
    "redesign"
    "phase [0-9]"
    "step [0-9]"
    "first.*then.*finally"
    "first.*second.*third"
)

# Check if planning files exist
has_planning_files() {
    [ -f "$PROJECT_DIR/task_plan.md" ] && \
    [ -f "$PROJECT_DIR/findings.md" ] && \
    [ -f "$PROJECT_DIR/progress.md" ]
}

# Check if user input matches complex task patterns
is_complex_task() {
    local input="$1"
    for pattern in "${COMPLEX_PATTERNS[@]}"; do
        if echo "$input" | grep -qiE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Main logic
if ! has_planning_files && is_complex_task "$USER_INPUT"; then
    echo "🎯 Multi-step task detected. Use planning-with-files for best results:"
    echo "   Run: /planning-with-files"
    echo "   Creates: task_plan.md, findings.md, progress.md in project root"
fi

exit 0
```

**Make executable:**
```bash
chmod +x .claude/hooks/user-prompt-submit.sh
```

**Add to `.claude/settings.json` hooks:**
```json
"UserPromptSubmit": [
  {
    "matcher": "*",
    "hooks": [{"type": "command", "command": ".claude/hooks/user-prompt-submit.sh"}]
  }
]
```

---

#### B) Enhance `.claude/hooks/subagent-stop.sh`

**Purpose:** Gate subagent outputs with PAL MCP review before integration

**Update file:** `/Users/juju/dev_repos/books-v3/.claude/hooks/subagent-stop.sh`

**Add after line 31 (after logging):**

```bash
# PAL MCP Review Gate (PM Orchestration)
# Require review of subagent outputs before integration

IMPLEMENTATION_AGENTS=("Explore" "general-purpose" "feature-dev" "Bash")
SECURITY_AGENTS=("cloudflare-specialist" "security-auditor")

# Only review non-background agents (background already reviewed in parallel)
if [ "$WAS_BACKGROUND" = "false" ]; then
    # Check if implementation work requires code review
    if [[ " ${IMPLEMENTATION_AGENTS[@]} " =~ " ${AGENT_TYPE} " ]]; then
        echo ""
        echo "⚠️  REVIEW GATE: Implementation work detected"
        echo "   Before integrating subagent output, run PAL MCP review:"
        echo "   → mcp__pal__codereview (model: grok-code-fast-1)"
        echo "   → Focus: quality, security, architecture"
        echo ""
    fi

    # Check if security work requires audit
    if [[ " ${SECURITY_AGENTS[@]} " =~ " ${AGENT_TYPE} " ]]; then
        echo ""
        echo "⚠️  SECURITY GATE: Security-critical work detected"
        echo "   Before integrating subagent output, run PAL MCP audit:"
        echo "   → mcp__pal__secaudit (model: grok-code-fast-1)"
        echo "   → Focus: API keys exposure, obvious vulns, broken auth"
        echo "   → Context: Family app (low attack surface, pragmatic security)"
        echo ""
    fi
fi
```

**Note:** This is a *soft gate* (reminder, not blocker). Sonnet sees the message and is expected to comply based on PM orchestration memory rule.

---

## Configuration Summary

### Files to Create

1. **`.claude/rules/pm-orchestration.md`** (371 lines)
   - PM role definition
   - Delegation patterns
   - Planning-with-files integration

2. **`.claude/rules/planning-automation.md`** (152 lines)
   - Task detection patterns
   - Automatic workflow
   - File responsibilities

3. **`.claude/hooks/user-prompt-submit.sh`** (65 lines)
   - Multi-step task detection
   - Planning files check
   - Reminder injection

### Files to Modify

1. **`.claude/settings.json`**
   - Update `customInstructions` (line 3)
   - Add `UserPromptSubmit` hook (after line 72)
   - Add 2 new memory rule trigger keywords (lines 10-18)

2. **`.claude/hooks/subagent-stop.sh`**
   - Add PAL review gate logic (after line 31)
   - ~20 lines added

3. **`CLAUDE.md`** (optional, for documentation)
   - Document new automation behavior
   - Update "Core Workflows" section
   - Add troubleshooting section

---

## Expected Behavior After Implementation

### Scenario 1: Complex Feature Request

**User:** "Implement Phase 3 Goals Engine with 6 goal types"

**What Happens:**
1. UserPromptSubmit hook detects "Implement Phase"
2. Checks for planning files → not found
3. Injects: "🎯 Multi-step task detected. Use planning-with-files..."
4. Sonnet sees message + pm-orchestration.md auto-loads
5. Sonnet: "I'll create planning files first. Running /planning-with-files..."
6. Sonnet creates task_plan.md/findings.md/progress.md
7. Sonnet breaks work into phases, delegates to Haiku
8. SubagentStop hook reminds to run PAL review
9. Sonnet calls mcp__pal__codereview with Grok
10. Sonnet integrates validated output, updates planning files

### Scenario 2: Simple Bug Fix

**User:** "Fix typo in README line 42"

**What Happens:**
1. UserPromptSubmit hook checks patterns → no match
2. No injection (not complex)
3. Sonnet handles directly (no delegation needed)
4. No SubagentStop (no subagent used)
5. Quick fix applied

### Scenario 3: Security Work

**User:** "Add authentication to the API endpoints"

**What Happens:**
1. UserPromptSubmit hook detects "Add" + "authentication"
2. Injects planning reminder
3. pm-orchestration.md auto-loads (triggers on "add", "security")
4. Sonnet creates planning files
5. Sonnet delegates to security-auditor subagent
6. SubagentStop hook detects security agent → injects secaudit reminder
7. Sonnet calls mcp__pal__secaudit with Grok
8. Sonnet iterates based on audit findings
9. Final re-audit before acceptance

---

## Testing Plan

### Test 1: Multi-Step Detection

**Input:** "Implement Phase 4 Insights Filtering with tap-to-filter navigation"

**Expected:**
- Hook detects "Implement Phase"
- Message: "🎯 Multi-step task detected..."
- Sonnet creates planning files

### Test 2: PM Delegation

**Input:** "Build a new BookRatingView component"

**Expected:**
- pm-orchestration.md auto-loads (trigger: "Build")
- Sonnet creates task_plan.md
- Sonnet delegates to Haiku (Explore agent)
- Sonnet doesn't implement directly

### Test 3: PAL Review Gate

**Prerequisites:** Haiku completes implementation work

**Expected:**
- SubagentStop hook detects Explore agent
- Message: "⚠️ REVIEW GATE: Implementation work detected"
- Sonnet calls mcp__pal__codereview before integrating
- Review focuses: Correctness, architecture, performance (not security paranoia)
- Bar: "Good enough for family app" (not enterprise-grade)

### Test 4: Simple Task Bypass

**Input:** "Fix typo: 'teh' → 'the' in README.md line 5"

**Expected:**
- No hook injection (not complex)
- Sonnet handles directly (no delegation)
- No PAL review (trivial change)

---

## Risks & Mitigations

### Risk 1: Hook Becomes Too Noisy

**Problem:** False positives annoy user with unnecessary reminders

**Mitigation:**
- Conservative pattern matching (require strong indicators)
- Only inject once per session (add state tracking if needed)
- Allow bypass: `export SKIP_PLANNING_REMINDER=1`

### Risk 2: PAL Review Adds Latency

**Problem:** Every subagent output requires expensive review call

**Mitigation:**
- Message is a reminder, not a blocker (Sonnet can skip for trivial work)
- PM orchestration memory rule provides judgment guidance
- Async reviews possible (background agents + TaskOutput)

### Risk 3: PM Role Too Rigid

**Problem:** User wants direct implementation sometimes

**Mitigation:**
- PM role is guidance, not absolute requirement
- User override: "you implement this directly" bypasses delegation
- Memory rule includes "when NOT to delegate" section

### Risk 4: Conflicts with Existing Workflows

**Problem:** New hooks interfere with current patterns

**Mitigation:**
- Hooks are additive (don't replace existing logic)
- Memory rules auto-load (don't conflict with manual loading)
- customInstructions adds to (doesn't replace) existing instructions

---

## Implementation Order

### Phase 1: Foundation (10 minutes)
1. Create `pm-orchestration.md`
2. Create `planning-automation.md`
3. Update `settings.json` memory rule keywords

### Phase 2: Automation (10 minutes)
4. Create `user-prompt-submit.sh` hook
5. Make executable (`chmod +x`)
6. Update `settings.json` to register hook

### Phase 3: Review Gate (5 minutes)
7. Update `subagent-stop.sh` with PAL logic
8. Test hook manually

### Phase 4: Testing (15 minutes)
9. Test multi-step detection (Test 1)
10. Test PM delegation (Test 2)
11. Test PAL review gate (Test 3)
12. Test simple task bypass (Test 4)

### Phase 5: Documentation (10 minutes)
13. Update `CLAUDE.md` with new behavior
14. Add troubleshooting section
15. Document override mechanisms

**Total Time:** ~50 minutes

---

## Success Metrics

**After implementation, verify:**

- ✅ Multi-step tasks automatically trigger planning-with-files
- ✅ Sonnet adopts PM role (delegates, doesn't implement)
- ✅ 80%+ of subagent outputs reviewed by PAL MCP
- ✅ Simple tasks still handled quickly (no false positives)
- ✅ Zero user complaints about over-automation

---

## Best Practices for Maintenance

**Monthly Review:**
- Check hook logs (`~/.claude/logs/subagent-usage.log`)
- Analyze false positive rate
- Update detection patterns if needed
- Review PAL review coverage

**When Adding New Subagents:**
- Update `subagent-stop.sh` agent type arrays
- Add to `pm-orchestration.md` delegation patterns
- Test review workflow

**When Users Report Issues:**
- Check if customInstructions is being overridden
- Verify memory rules are loading (check trigger keywords)
- Test hooks manually with sample inputs

---

## Alternative Approaches Considered

### Option 1: Hardcode PM Role in customInstructions

**Pros:** Always enforced, no context dependency
**Cons:** Inflexible, consumes excessive context, can't adapt to task type
**Decision:** Rejected - memory rules provide better context-awareness

### Option 2: Use PreToolUse Hook for Detection

**Pros:** Catches tasks right before tool execution
**Cons:** Too late (task already started), can't prevent non-planning approach
**Decision:** Rejected - UserPromptSubmit is the right checkpoint

### Option 3: Hard Gate with Blocking SubagentStop

**Pros:** Forces review, no exceptions
**Cons:** Too rigid, blocks trivial work, adds latency to all subagents
**Decision:** Rejected - soft gate with reminder is more flexible

### Option 4: Separate Review Subagent

**Pros:** Clean separation, explicit review step
**Cons:** Extra step, more latency, complexity
**Decision:** Rejected - PAL MCP tools already provide this

---

## Conclusion

**Current State:** ✅ Excellent foundation
- Hooks, memory rules, PAL MCP, planning-with-files all installed

**Needed:** 3 targeted enhancements
- UserPromptSubmit hook for detection
- 2 memory rules for PM orchestration guidance
- Enhanced SubagentStop for PAL review reminder

**Effort:** ~50 minutes total implementation time

**Impact:**
- Automatic planning-with-files adoption for complex work
- Consistent PM orchestration behavior
- Quality gate via PAL MCP review
- Maintains flexibility for simple tasks

**Recommendation:** Implement all 3 layers (hooks + memory rules + customInstructions) for maximum effectiveness. The layered approach provides redundancy while maintaining flexibility.

---

**Ready to implement?** Start with Phase 1 (memory rules) - they provide immediate value even before hooks are configured.
