# Attribution Rules (v2.0.62)

Commit and PR attribution is now configured via the `attribution` setting.

## Configuration

```json
{
  "attribution": {
    "commit": {
      "trailer": "Co-Authored-By: Claude <noreply@anthropic.com>",
      "footer": "Generated with [Claude Code](https://claude.com/claude-code)"
    },
    "pr": {
      "footer": "Generated with [Claude Code](https://claude.com/claude-code)"
    }
  }
}
```

## Migration Note

The `includeCoAuthoredBy` setting is **deprecated** in v2.0.62.
Use the `attribution` setting instead for more flexible configuration.

## BooksTrack Standard

Commits should include:
- Footer: `Generated with [Claude Code](https://claude.com/claude-code)`
- Trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`

PRs should include:
- Footer: `Generated with [Claude Code](https://claude.com/claude-code)`

## AskUserQuestion "(Recommended)" Pattern

When presenting multiple-choice questions, place recommended option first
and add "(Recommended)" indicator:

```javascript
options: [
  {label: "Option A (Recommended)", description: "Best for most cases"},
  {label: "Option B", description: "Alternative approach"},
  {label: "Option C", description: "Legacy fallback"}
]
```
