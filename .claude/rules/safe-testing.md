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

## Emergency Recovery

If system becomes unresponsive:
1. Use `/kill-xcode` immediately
2. Wait 10 seconds
3. Resume with `/quick-validate`
