# Multi-Agent Workflows (v2.0.64)

Auto-loaded when user mentions: "workflow", "multi-agent", "delegation", "parallel", "background", "orchestration"

## Agent Specializations

**Sonnet 4.5 (Primary)** - Orchestration, planning, architecture
**Opus 4.5 (Strategic)** - Complex planning, critical decisions (Plan subagent)
**Haiku 4.5 (Fast)** - Implementation, exploration (Explore subagent, mcp__pal__chat)
**Grok-4 (Expert Review)** - Security, architecture validation (mcp__pal__codereview/secaudit)
**Gemini 2.5 Pro (Deep Analysis)** - Debugging, investigation (mcp__pal__debug/thinkdeep)

## Workflow Patterns

**Fast Feature Implementation:**
Sonnet → Plan → Haiku (implement) → Grok (validate) → Sonnet (integrate)

**Bug Investigation:**
Sonnet → Explore → Gemini (debug) → Haiku (fix) → Sonnet (test)

**Security-Critical:**
Sonnet → Plan → Haiku (implement) → Grok (security audit) → Sonnet (address)

## Delegation Best Practices

**Delegate when:** Task fits specialist strength, parallel work improves speed, expert validation needed
**Don't delegate:** Simple edits, cross-file context needed, user wants you to do it
**Always reuse continuation_id** when resuming conversations

## Async Agents (v2.0.64)

Launch with `run_in_background: true` for:
- Long-running analysis
- Parallel work streams
- Non-blocking investigations

Use `TaskOutput` tool to retrieve results when ready.