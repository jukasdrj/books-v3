# Swift 6.2 Master - Quick Reference

**Invoke:** `/skill swift62-master`

**Purpose:** Validate Swift 6.2 strict concurrency, @MainActor isolation, iOS 26 HIG compliance, and SwiftData best practices.

---

## When to Use

### Automatic Triggers (via skill-rules.json)
The skill auto-suggests when you mention:
- Concurrency issues (@MainActor, actor isolation, Sendable)
- Swift 6/6.2 compliance
- Persistent identifier crashes
- @Bindable/@Observable missing
- iOS 26 HIG patterns
- Navigation issues
- Timer.publish in actors
- SwiftData lifecycle (save before persistentModelID)
- Glass overlay hit testing
- Keyboard focus conflicts

### Manual Invocation
Use when you need:
- Pre-commit Swift 6.2 validation
- iOS 26 HIG compliance check
- SwiftData relationship audit
- Concurrency violation detection
- Performance review (app launch, lazy loading)

---

## Key Validation Areas

### 1. Swift 6.2 Strict Concurrency
- ✅ @MainActor on all Observable classes
- ✅ No Timer.publish in actors (use Task.sleep)
- ✅ Sendable only for value types (NOT SwiftData models)
- ✅ nonisolated functions don't access actor state
- ✅ Custom actors for domain-specific work (@CameraSessionActor)

### 2. SwiftUI Property Wrappers
- ✅ @Bindable for SwiftData models in child views
- ✅ @Query only at root level
- ✅ @State for view-local Observable objects
- ✅ @Environment for shared state
- ✅ No @StateObject (deprecated iOS 26)
- ✅ No @FocusState with .searchable()

### 3. SwiftData Lifecycle
- ✅ insert() immediately after model creation
- ✅ Relationships set AFTER both objects inserted
- ✅ save() called BEFORE using persistentModelID
- ✅ Inverse relationships only on to-many side
- ✅ All attributes have defaults
- ✅ All relationships optional

### 4. iOS 26 HIG
- ✅ Push navigation for hierarchical content
- ✅ Sheets for modal presentations
- ✅ No .navigationBarDrawer(displayMode: .always)
- ✅ Glass overlays have .allowsHitTesting(false)
- ✅ WCAG AA contrast (4.5:1+)
- ✅ VoiceOver labels

### 5. Performance
- ✅ Lazy properties for expensive initialization
- ✅ fetchCount() instead of loading objects
- ✅ Predicate filtering at database level
- ✅ BackgroundTaskScheduler for deferred tasks
- ✅ Image preprocessing on background queues

---

## Example Usage

```bash
# Pre-commit validation
/skill swift62-master
> "Validate all Swift files for Swift 6.2 compliance"

# Specific file check
/skill swift62-master
> "Check SearchModel.swift for @MainActor violations"

# Full project audit
/skill swift62-master
> "Audit entire BooksTrackerPackage for concurrency issues"

# Performance review
/skill swift62-master
> "Review app launch performance and lazy loading patterns"
```

---

## Output Format

The skill generates violation reports with:

### Critical Violations (Must Fix)
- File:line location
- Specific issue (missing @MainActor, etc.)
- Recommended fix
- Impact explanation

### Warnings (Should Fix)
- Non-critical but important improvements
- Performance optimizations
- Code style suggestions

### Suggestions (Consider)
- Best practices
- Alternative approaches
- Future-proofing

---

## Integration with Other Skills

**Works with:**
- `project-manager` - Receives delegation for Swift compliance
- `xcode-agent` - Validates before `/build` and `/test`
- `zen-mcp-master` - Complements `codereview` with Swift-specific rules

**Workflow:**
1. swift62-master validates code
2. Reports violations
3. xcode-agent runs `/build` to confirm fixes
4. zen-mcp-master does deep review if needed

---

## Common Patterns Checked

### ✅ CORRECT Patterns
```swift
// Observable with @MainActor
@MainActor
class SearchModel: Observable { }

// @Bindable for SwiftData reactivity
struct BookDetailView: View {
    @Bindable var work: Work
}

// Save before using persistentModelID
modelContext.insert(work)
try modelContext.save()
let id = work.persistentModelID  // Safe!

// Task.sleep instead of Timer.publish
actor Tracker {
    func poll() async {
        try await Task.sleep(for: .seconds(2))
    }
}
```

### ❌ WRONG Patterns (Detected & Flagged)
```swift
// Missing @MainActor
class SearchModel: Observable { }  // ❌ WARNING

// Missing @Bindable
struct BookDetailView: View {
    let work: Work  // ❌ No reactivity
}

// Using ID before save
modelContext.insert(work)
let id = work.persistentModelID  // ❌ CRASH!

// Timer.publish in actor
actor Tracker {
    Timer.publish(...)  // ❌ Swift 6 incompatible
}
```

---

## Checklist (Auto-Generated in Reports)

### Concurrency
- [ ] All Observable classes have @MainActor
- [ ] No Timer.publish in actors
- [ ] SwiftData models use @MainActor (not Sendable)
- [ ] nonisolated functions don't access state

### SwiftUI
- [ ] @Bindable for SwiftData in child views
- [ ] No @StateObject (use @State + @Observable)
- [ ] No @FocusState with .searchable()

### SwiftData
- [ ] insert() before setting relationships
- [ ] save() before using persistentModelID
- [ ] Inverse only on to-many side

### iOS 26 HIG
- [ ] Push navigation (not sheets)
- [ ] Glass overlays non-interactive
- [ ] WCAG AA contrast

### Performance
- [ ] Lazy expensive properties
- [ ] fetchCount() for totals
- [ ] Predicate filtering

---

## Success Metrics

**Zero Warnings Policy:** All Swift 6.2 concurrency warnings must be resolved

**Performance Targets:**
- App launch: <600ms cold start
- Build time: <30s incremental
- Test suite: <2min

**Compliance:**
- 100% iOS 26 HIG
- 100% Swift 6.2 concurrency
- 100% SwiftData best practices

---

**Status:** ✅ Production Ready
**Version:** 1.0.0
**Last Updated:** November 14, 2025
**Integration:** Automated via skill-rules.json
