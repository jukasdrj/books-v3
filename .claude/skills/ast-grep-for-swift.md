---
name: ast-grep-for-swift
description: Use ast-grep (sg) for all Swift code searches - syntax-aware, no false positives, refactoring-safe. Replaces ripgrep for Swift.
trigger: Before ANY Swift code search (finding classes, methods, properties, patterns)
---

# AST-Grep for Swift Code Search

**MANDATORY:** Use `ast-grep` (alias: `sg`) for ALL Swift code searches. Do NOT use `grep` or `ripgrep` for Swift syntax queries.

## Why AST-Grep?

- **Syntax-Aware:** Understands Swift AST (classes, methods, properties, generics)
- **No False Positives:** Won't match strings/comments that look like code
- **Refactoring-Safe:** Matches code structure, not text patterns
- **Faster for Code:** Pre-built Swift parser, optimized for syntax queries

## Installation Check

```bash
which ast-grep
```

Expected: `/opt/homebrew/bin/ast-grep` or similar path

If missing, install via Homebrew:
```bash
brew install ast-grep
```

## Common Swift Patterns

### Find All Public Methods

```bash
ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' .
```

**Pattern Breakdown:**
- `public func` - Literal keywords
- `$METHOD` - Matches method name (single identifier)
- `($$$)` - Matches any parameter list
- `{ $$$ }` - Matches any method body

### Find All @MainActor Classes

```bash
ast-grep --lang swift --pattern '@MainActor class $NAME { $$$ }' .
```

**Use Case:** Audit Swift 6 concurrency compliance

### Find All SwiftData @Model Classes

```bash
ast-grep --lang swift --pattern '@Model public class $NAME { $$$ }' .
```

**Use Case:** Inventory data models for schema migrations

### Find Force Unwraps (!)

```bash
ast-grep --lang swift --pattern '$VAR!' .
```

**Use Case:** Security audit - find potential crash points

### Find All @Observable Classes

```bash
ast-grep --lang swift --pattern '@Observable class $NAME { $$$ }' .
```

**Use Case:** Find state management objects

### Find Task.sleep Calls

```bash
ast-grep --lang swift --pattern 'Task.sleep(for: $DURATION)' .
```

**Use Case:** Check for proper async patterns (vs Timer.publish in actors)

### Find All Actors

```bash
ast-grep --lang swift --pattern 'actor $NAME { $$$ }' .
```

**Use Case:** Audit actor isolation boundaries

### Find Property Wrappers

```bash
# Find all @State properties
ast-grep --lang swift --pattern '@State private var $NAME' .

# Find all @Bindable properties
ast-grep --lang swift --pattern '@Bindable var $NAME' .

# Find all @Environment properties
ast-grep --lang swift --pattern '@Environment(\.$NAME) private var $VAR' .
```

## Pattern Syntax

| Syntax | Meaning | Example |
|--------|---------|---------|
| `$VAR` | Single identifier | `$METHOD`, `$NAME`, `$PARAM` |
| `$$$` | Multiple items (variadic) | `($$$)` matches any param list |
| `{ $$$ }` | Any block contents | Method/closure bodies |
| Literal text | Exact match | `public`, `func`, `@MainActor` |

## When to Use Ripgrep Instead

**Use ripgrep (`rg`) for:**
- Searching non-Swift files (Markdown, JSON, TypeScript)
- Simple text search in logs/error messages
- Multi-language searches (Swift + JavaScript)
- Searching for strings/comments (not code structure)

**Example:**
```bash
# Use ripgrep for non-code searches
rg "TODO" docs/
rg "FIXME" --type md
rg "error.*failed" --type json
```

## Workflow Integration

**Before:**
```bash
# ❌ DON'T: Use ripgrep for Swift syntax
rg "class.*@Observable" --type swift
rg "public func" BooksTrackerPackage/
```

**After:**
```bash
# ✅ DO: Use ast-grep for Swift syntax
ast-grep --lang swift --pattern '@Observable class $NAME { $$$ }' .
ast-grep --lang swift --pattern 'public func $METHOD($$$) { $$$ }' BooksTrackerPackage/
```

## Error Handling

**If ast-grep not found:**
1. Check installation: `which ast-grep`
2. Install if missing: `brew install ast-grep`
3. Verify Swift support: `ast-grep --lang swift --pattern 'func test() {}' --help`

**If pattern doesn't match:**
1. Test pattern in isolation (create small Swift file)
2. Check AST structure: `ast-grep --lang swift --debug-query '$PATTERN'`
3. Simplify pattern (remove optional parts)
4. Consult ast-grep docs: https://ast-grep.github.io/guide/pattern-syntax.html

## Performance

- **Small repos (<1000 files):** ast-grep ≈ ripgrep (both <1s)
- **Large repos (5000+ files):** ast-grep can be slower (AST parsing overhead)
- **Mitigation:** Limit scope to specific directories (`ast-grep ... BooksTrackerPackage/Sources/`)

## Checklist

Before ANY Swift code search:

- [ ] Am I searching Swift syntax (classes, methods, properties)?
  - **Yes** → Use ast-grep
  - **No** → Use ripgrep

- [ ] Do I need to match code structure (not text patterns)?
  - **Yes** → Use ast-grep
  - **No** → Use ripgrep

- [ ] Am I searching across multiple languages?
  - **Yes** → Use ripgrep
  - **No, Swift only** → Use ast-grep

## Examples in BooksTrack

**Find all services using @MainActor:**
```bash
ast-grep --lang swift --pattern '@MainActor class $NAME { $$$ }' BooksTrackerPackage/Sources/
```

**Find all SwiftData relationships:**
```bash
ast-grep --lang swift --pattern '@Relationship var $NAME: [$TYPE]' BooksTrackerPackage/Sources/
```

**Find all async throws functions:**
```bash
ast-grep --lang swift --pattern 'func $NAME($$$) async throws -> $RETURN { $$$ }' .
```

**Find all force unwraps (security audit):**
```bash
ast-grep --lang swift --pattern '$VAR!' . | grep -v "// Known safe"
```

---

**Remember:** ast-grep is the standard for Swift code searches. Use it proactively!
