# MCP Server Integration Guide

**Last Updated:** November 11, 2025
**Version:** 1.0.0

## Overview

BooksTrack integrates with **two Model Context Protocol (MCP) servers** to enhance Claude Code's capabilities:

1. **Zen MCP** - Advanced AI reasoning and code analysis
2. **Cloudflare Observability MCP** - Worker logs, metrics, and diagnostics

These integrations enable powerful workflows for debugging, planning, code review, and backend monitoring.

---

## Active MCP Servers

### 1. Zen MCP (`mcp__zen__*`)

**Purpose:** Multi-model reasoning, systematic debugging, code review, and architectural planning.

**Available Tools:**

| Tool | Description | When to Use |
|------|-------------|-------------|
| `chat` | General brainstorming and discussion | Getting second opinions, exploring ideas |
| `thinkdeep` | Multi-stage investigation with hypothesis testing | Complex bugs, architecture decisions, security analysis |
| `debug` | Systematic debugging with root cause analysis | Mysterious errors, race conditions, performance issues |
| `codereview` | Structured code review (quality, security, performance) | PR reviews, security audits, refactoring validation |
| `planner` | Interactive planning with revision/branching | Complex features, migrations, system design |
| `consensus` | Multi-model debate for decision-making | Technology choices, architectural decisions |
| `precommit` | Git change validation before commits | Pre-commit checks, change impact assessment |
| `challenge` | Critical analysis of statements | Validating assumptions, sanity checks |
| `apilookup` | Current API/SDK documentation lookup | Version info, breaking changes, migration guides |
| `listmodels` | Show available AI models across providers | Model selection, capability comparison |
| `clink` | Link to external AI CLI tools | Reusing Gemini CLI, Qwen CLI capabilities |

**Key Features:**
- Multi-step workflows with continuation support
- Expert model validation (Gemini 2.5 Pro, GPT-5 Pro, etc.)
- Token tracking and cost optimization
- Thinking modes (minimal → max reasoning depth)

**Best Practices:**
- Use `thinkdeep` for multi-step investigations (3+ steps)
- Use `debug` when you have clear symptoms but unknown root cause
- Use `codereview` with `review_type: "security"` for security audits
- Use `planner` for features requiring architectural decisions
- Always reuse `continuation_id` to preserve conversation context

---

### 2. Cloudflare Observability MCP (`mcp__cloudflare-observability__*`)

**Purpose:** Query Worker logs, analyze metrics, and monitor backend health.

**Available Tools:**

| Tool | Description | When to Use |
|------|-------------|-------------|
| `accounts_list` | List all Cloudflare accounts | Initial setup, account verification |
| `set_active_account` | Set active account for queries | Switching between accounts |
| `workers_list` | List all Workers in account | Overview of deployed Workers |
| `workers_get_worker` | Get details of specific Worker | Configuration validation, binding checks |
| `workers_get_worker_code` | Get Worker source code | Code inspection (may be bundled) |
| `query_worker_observability` | **MAIN TOOL** - Query logs/metrics | Error investigation, performance analysis |
| `observability_keys` | Discover available log fields | Before filtering, find valid keys |
| `observability_values` | Find valid values for a field | Verify actual log values before filtering |
| `search_cloudflare_documentation` | Search Cloudflare docs | Feature research, API questions |
| `migrate_pages_to_workers_guide` | Migration guide for Pages → Workers | Planning migrations |

**Query Views:**
1. **Events** - Browse individual request logs (default limit: 5)
2. **Calculations** - Compute metrics (avg, p99, count, etc.)
3. **Invocations** - Find specific requests by criteria

**Key Metadata Fields (Fast & Always Available):**
- `$metadata.service` - Worker name ("api-worker")
- `$metadata.origin` - Trigger type ("fetch", "scheduled")
- `$metadata.trigger` - Route pattern ("GET /search/title")
- `$metadata.message` - Log message text
- `$metadata.error` - Error message (when present)
- `$metadata.requestId` - Unique request identifier
- `$metadata.level` - Log level ("info", "error", "warn")

**Custom Fields (Feature-Specific):**
- `provider` - API provider ("google-books", "gemini")
- `isbn` - ISBN being processed
- `jobId` - Background job ID
- `confidence` - AI confidence score
- `tokensUsed` - Gemini token consumption
- `cacheHit` - Cache status
- `processingTime` - Request duration (ms)

**Best Practices:**
1. **Always use 3-step workflow:**
   - Step 1: `observability_keys` to discover available fields
   - Step 2: `observability_values` to verify actual values
   - Step 3: `query_worker_observability` with verified keys/values
2. **Use preferred keys** - `$metadata.*` fields are faster
3. **Appropriate time ranges** - Default: 1 hour, Max: 7 days
4. **Narrow before broadening** - Start specific, relax if no results

---

## Integration Points

### Slash Commands

The following slash commands leverage MCP tools:

| Command | MCP Tools Used | Purpose |
|---------|----------------|---------|
| `/query-logs` | `observability_keys`, `observability_values`, `query_worker_observability` | Structured log queries with filters |
| `/backend-health` | `workers_get_worker`, `query_worker_observability` | Worker health + recent errors |
| `/logs` | *(none - uses wrangler tail)* | Real-time log streaming |

### Hooks

**Skill Activation Hook** (`~/.claude/hooks/skill-activation-prompt.sh`)

Automatically suggests relevant skills based on user prompts:

**Cloudflare Observability Triggers:**
- Keywords: "worker logs", "query logs", "observability", "worker metrics", "log search", "error logs", "trace request", "gemini calls"
- Intent Patterns: "show.*logs", "find.*errors.*worker", "query.*worker.*logs", "investigate.*worker"

**Zen MCP Triggers:**
- Keywords: "debug", "review", "plan", "analyze", "architecture", "investigate", "complex issue"
- Intent Patterns: "help.*debug", "review.*code", "plan.*feature", "complex.*bug"

**Configuration:** `.claude/skills/skill-rules.json`

---

## Common Workflows

### 1. Debugging Worker Errors

**Goal:** Find and analyze errors in api-worker

**Steps:**
1. Run `/query-logs` or directly use MCP:
   ```
   Use mcp__cloudflare-observability__query_worker_observability:
   - View: events
   - Filters: $metadata.level = "error"
   - Timeframe: Last 30 minutes
   - Limit: 10
   ```
2. If root cause unclear, escalate to Zen:
   ```
   Use mcp__zen__debug:
   - Provide error logs as context
   - Let Zen guide multi-step investigation
   - Use continuation_id to preserve context
   ```
3. Fix identified issues
4. Verify fix with another `/query-logs` query

---

### 2. Performance Analysis

**Goal:** Analyze Worker response times and identify bottlenecks

**Steps:**
1. Discover performance keys:
   ```
   Use mcp__cloudflare-observability__observability_keys:
   - keyNeedle: "time" (case-insensitive)
   - Timeframe: Last 6 hours
   - Limit: 1000
   ```
2. Query performance metrics:
   ```
   Use mcp__cloudflare-observability__query_worker_observability:
   - View: calculations
   - Calculations:
     - avg(processingTime) as avgTime
     - p99(processingTime) as p99Time
     - count() as requestCount
   - GroupBy: $metadata.trigger
   - OrderBy: p99Time DESC
   - Timeframe: Last 24 hours
   ```
3. Analyze results and identify slow endpoints
4. Use Zen `thinkdeep` for optimization planning if needed

---

### 3. Pre-Deployment Health Check

**Goal:** Validate Worker health before deploying changes

**Steps:**
1. Run `/backend-health`:
   - Checks Worker details via MCP
   - Tests HTTP health endpoint
   - Queries recent errors (last 10 min)
   - Calculates performance metrics
2. If issues found, investigate with `/query-logs`
3. Use Zen `precommit` to validate git changes
4. Deploy with `/deploy-backend`

---

### 4. Feature Investigation (Gemini API Calls)

**Goal:** Analyze all Gemini API calls to debug bookshelf scanning

**Steps:**
1. Find Gemini-related keys:
   ```
   Use observability_keys:
   - keyNeedle: "gemini"
   - Filters: $metadata.service = "api-worker"
   ```
2. Query Gemini events:
   ```
   Use query_worker_observability:
   - View: events
   - Filters: $metadata.message includes "Gemini"
   - Timeframe: Last 1 hour
   - Limit: 20
   ```
3. Calculate Gemini token usage:
   ```
   Use query_worker_observability:
   - View: calculations
   - Calculations:
     - sum(tokensUsed) as totalTokens
     - avg(tokensUsed) as avgTokens
     - count() as apiCalls
   - Timeframe: Last 24 hours
   ```
4. If patterns emerge, use Zen `thinkdeep` for deeper analysis

---

### 5. Code Review Before PR

**Goal:** Systematic review of changes before creating PR

**Steps:**
1. Use Zen `precommit`:
   ```
   Use mcp__zen__precommit:
   - path: /Users/.../books-tracker-v1
   - include_staged: true
   - include_unstaged: true
   - precommit_type: external (for expert validation)
   - focus_on: "security, performance"
   ```
2. Address issues identified
3. Run `/test` to validate fixes
4. Create PR with confidence

---

## Model Selection

Zen MCP supports multiple AI models across providers. Use `mcp__zen__listmodels` to see all options.

**Top Models (as of Nov 2025):**

| Model | Score | Context | Best For |
|-------|-------|---------|----------|
| `gemini-2.5-pro-computer-use` | 100 | 1.0M | Thinking, code generation |
| `gemini-2.5-pro` | 100 | 1.0M | General reasoning |
| `gpt-5-pro` | 100 | 400K | Architectural planning |
| `grok-4` | 100 | 256K | Code review |
| `grok-4-heavy` | 100 | 256K | Deep analysis |

**Selection Strategy:**
- **Default:** Auto-select (Zen chooses best model)
- **User-specified:** Use exact model name (e.g., "use gpt5 for this")
- **Cost-optimization:** Prefer `haiku` for quick tasks (Fast Tool)
- **Deep reasoning:** Use `thinking_mode: "max"` with large context models

---

## Troubleshooting

### Cloudflare Observability Issues

**Problem:** "No results found" when querying logs

**Solutions:**
1. Broaden time range (extend from 1hr → 6hr → 24hr)
2. Relax filters (remove restrictive conditions)
3. Verify keys exist using `observability_keys`
4. Verify values exist using `observability_values`
5. Use preferred keys (`$metadata.*` fields)

---

**Problem:** "Invalid field name" error

**Solutions:**
1. Always use `observability_keys` first to discover valid fields
2. Don't guess field names (common mistake!)
3. Check for typos (case-sensitive matching)
4. Use `keyNeedle` to search for similar keys

---

**Problem:** Slow queries

**Solutions:**
1. Reduce time range (7 days → 24hr → 1hr)
2. Use `$metadata.*` fields (faster, always indexed)
3. Avoid custom fields for broad queries
4. Add more specific filters to narrow results

---

### Zen MCP Issues

**Problem:** "Lost context" after multiple steps

**Solutions:**
1. Always reuse `continuation_id` from previous responses
2. Check that `next_step_required: true` was set
3. Don't create new conversations mid-investigation
4. Use same tool (debug/thinkdeep/etc.) throughout workflow

---

**Problem:** Expert validation not triggered

**Solutions:**
1. Ensure `use_assistant_model: true` (default)
2. Set `next_step_required: true` until final step
3. For precommit/codereview: Use `external` validation type
4. Check `confidence` level isn't set to "certain" prematurely

---

**Problem:** Model selection issues

**Solutions:**
1. Use exact model names from `listmodels` output
2. Don't abbreviate (use "gpt-5-pro", not "gpt5")
3. Let auto-selection work (omit `model` parameter)
4. Check provider availability (some models region-locked)

---

## Cost Optimization

### Cloudflare Observability
- **Free** - No costs for MCP queries (native Cloudflare API)
- Optimize by narrowing time ranges and using preferred keys

### Zen MCP
- **Costs vary by model** - Consult `listmodels` for provider pricing
- **Strategies:**
  1. Use `thinking_mode: "low"` for simple queries
  2. Set `temperature: 0` for deterministic tasks
  3. Use `haiku` model for quick validations (Fast Tool)
  4. Reuse `continuation_id` to avoid re-sending context
  5. Set `use_assistant_model: false` for internal-only validation

---

## Configuration Files

**Skill Rules:** `.claude/skills/skill-rules.json`
```json
{
  "skills": {
    "cloudflare-observability": { "priority": "high" },
    "mcp-zen-usage": { "priority": "medium" }
  }
}
```

**Hooks:** `~/.claude/settings.json`
```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/skill-activation-prompt.sh"
      }]
    }]
  }
}
```

**Slash Commands:** `.claude/commands/*.md`
- `query-logs.md` - Cloudflare log queries
- `backend-health.md` - Worker health checks
- `logs.md` - Real-time streaming

---

## Next Steps

1. **Try It Out:**
   - Run `/query-logs` to see Cloudflare MCP in action
   - Use Zen `chat` for brainstorming ideas
   - Run `/backend-health` for full diagnostics

2. **Learn More:**
   - Explore `mcp__zen__listmodels` for available models
   - Check Cloudflare docs with `search_cloudflare_documentation`
   - Review `.claude/skills/skill-rules.json` for trigger patterns

3. **Customize:**
   - Add project-specific triggers to `skill-rules.json`
   - Create custom slash commands in `.claude/commands/`
   - Configure preferred models in Zen workflows

---

## Related Documentation

- **MCP Setup Guide:** `MCP_SETUP.md`
- **Slash Commands:** `.claude/commands/` directory
- **Cloudflare Workers:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md`
- **Main Guide:** `CLAUDE.md`

---

**Questions?** Check skill activation hooks in `~/.claude/hooks/skill-activation-prompt.ts` for live suggestions during development.
