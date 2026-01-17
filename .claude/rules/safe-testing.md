# Safe Testing Rules (v2.0.64)

These rules are automatically loaded into context for testing-related queries.

## Critical: Resource Management

When user requests testing, ALWAYS follow this priority:

1. **Default**: Use `/quick-validate` (safest, fastest)
2. **UI Testing**: Ask user about `/device-deploy` vs `/sim-safe`
3. **Never**: Use `/sim` without explicit user request

## Trigger Keywords

Apply these rules when user mentions:
- "test", "build", "run", "validate", "check"
- "simulator", "device", "Xcode"
- "slow", "crash", "frozen", "RAM", "memory"

## Recommended Option Pattern (v2.0.62)

When presenting testing options, use "(Recommended)" indicator:

```
AskUserQuestion(
  questions: [{
    question: "Which testing approach should I use?",
    header: "Testing",
    options: [
      {label: "/quick-validate (Recommended)", description: "Safe build validation"},
      {label: "/device-deploy", description: "Real device testing"},
      {label: "/sim-safe", description: "Simulator with resource limits"}
    ]
  }]
)
```

## xcsift Integration

All xcodebuild commands should pipe through `xcsift` for enhanced output:

**Standard Pattern:**
```bash
xcodebuild [options] 2>&1 | xcsift --warnings
```

**Key xcsift Flags:**
- `--warnings` or `-w`: Show detailed warnings list
- `--Werror` or `-W`: Treat warnings as errors (enforces zero warnings)
- `--quiet` or `-q`: Suppress output when build succeeds with no issues
- `--coverage` or `-c`: Include code coverage data (auto-converts .xcresult)
- `--build-info`: Show per-target build phases and timing
- `--slow-threshold N`: Flag tests exceeding N seconds (e.g., 1.0)
- `-f toon`: Use TOON format for 30-60% fewer tokens (LLM-friendly)

**Benefits:**
- Structured JSON output for easy parsing
- File:line navigation format (clickable in editors)
- Automatic deduplication of identical errors/warnings
- Build timing metrics and slowest target identification
- Code coverage automation without manual xcrun commands

**Example with Full Options:**
```bash
xcodebuild test \
  -enableCodeCoverage YES \
  2>&1 | xcsift --warnings --coverage --slow-threshold 1.0
```

## Emergency Recovery

If system becomes unresponsive:
1. Use `/kill-xcode` immediately
2. Wait 10 seconds
3. Resume with `/quick-validate`
