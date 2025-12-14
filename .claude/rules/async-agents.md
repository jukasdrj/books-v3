# Async Agent Rules (v2.0.64)

These rules govern the use of background/async agents introduced in v2.0.64.

## Key Features

### Background Agents
Agents and bash commands can now run asynchronously:
- Launch with `run_in_background: true` parameter
- Use `TaskOutput` tool to retrieve results when ready
- Background agents can send messages to wake up main agent

### TaskOutput Tool (Unified)
Replaced both `AgentOutputTool` and `BashOutputTool`:
```javascript
TaskOutput({
  task_id: "agent_xyz123",
  block: true,      // Wait for completion (default)
  timeout: 30000    // Max wait time in ms
})
```

## When to Use Background Agents

**Good candidates:**
- Long-running analysis (performance profiling, security audits)
- Parallel work streams (analyze while implementing)
- Non-blocking investigations
- Resource-intensive tasks

**Avoid background for:**
- Quick file searches
- Simple code generation
- Tasks requiring immediate results
- Operations that block subsequent work

## Named Sessions (v2.0.64)

Sessions can now be named and resumed:
- `/rename <name>` - Name current session
- `/resume <name>` - Resume named session (REPL)
- `claude --resume <name>` - Resume from terminal

### /resume Screen Shortcuts
- `P` - Preview session
- `R` - Rename session
- Grouped forked sessions for clarity

## Model Switching (v2.0.65)

Switch models while writing a prompt:
- **macOS**: `option+p`
- **Linux/Windows**: `alt+p`

Context window info now shown in status line.
