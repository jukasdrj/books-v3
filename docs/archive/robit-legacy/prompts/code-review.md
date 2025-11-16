# Code Review Prompt Template

Use this template when reviewing code for BooksTrack (or adapt for other Swift/iOS projects).

---

## 🎯 Review Checklist

### Swift 6 Concurrency
- [ ] **Actor isolation correct?** (@MainActor for UI, actors for concurrent logic, nonisolated for pure functions)
- [ ] **No `Timer.publish` in actors?** (Use `Task.sleep` or `AdaptivePollingStrategy`)
- [ ] **Sendable conformance correct?** (No SwiftData models claiming Sendable)
- [ ] **Data races eliminated?** (All shared mutable state protected by actors)

### SwiftData Patterns
- [ ] **`save()` before using `persistentModelID`?** (Never use temporary IDs for futures/deduplication)
- [ ] **Insert before relate?** (Insert both models, THEN set relationships)
- [ ] **`@Bindable` for child views?** (SwiftData models passed to child views need `@Bindable`)
- [ ] **Predicate filtering?** (Filter at database level, not in-memory)
- [ ] **CloudKit sync compliance?** (Inverse relationships on to-many side only)

### iOS 26 HIG Compliance
- [ ] **Push navigation for drill-down?** (Use `.navigationDestination`, not `.sheet`)
- [ ] **No `@FocusState` with `.searchable()`?** (iOS manages focus internally)
- [ ] **WCAG AA contrast?** (4.5:1+ contrast, use system semantic colors)
- [ ] **Proper haptic feedback?** (Use `UIImpactFeedbackGenerator` for actions)
- [ ] **Accessibility labels?** (All interactive elements have labels)

### State Management
- [ ] **`@Observable` not `ObservableObject`?** (Swift 6 pattern)
- [ ] **`@State` not `@StateObject`?** (Modern SwiftUI)
- [ ] **No ViewModels?** (Use `@Observable` models + `@State`)
- [ ] **Property wrappers correct?** (@State, @Bindable, @Environment, @Query)

### Performance
- [ ] **`fetchCount()` for counts?** (10x faster than `fetch().count`)
- [ ] **Database-level filtering?** (Predicates, not in-memory `filter()`)
- [ ] **`CachedAsyncImage` for images?** (Never `AsyncImage` directly)
- [ ] **Lazy initialization?** (Defer heavy work, don't block UI)
- [ ] **Cover image service used?** (`CoverImageService.coverURL()`, not direct access)

### Code Quality
- [ ] **Zero warnings?** (Warnings treated as errors)
- [ ] **No force unwrapping?** (Use `guard let`/`if let`/`??`)
- [ ] **Nested supporting types?** (Enums/structs inside parent class)
- [ ] **Access control correct?** (Minimal public surface area)
- [ ] **Error handling typed?** (Use typed throws in Swift 6)

### Testing
- [ ] **Swift Testing used?** (@Test, #expect, not XCTest)
- [ ] **Test coverage adequate?** (Happy path + error cases)
- [ ] **Parameterized tests?** (Use `arguments:` for multiple inputs)
- [ ] **Real device tested?** (Keyboard, navigation, camera, etc.)

### Security
- [ ] **No hardcoded secrets?** (Use environment variables/keychain)
- [ ] **Input validation?** (Validate and sanitize user input)
- [ ] **Sensitive data redacted in logs?** (No PII in OSLog)
- [ ] **API keys in .gitignore?** (Never committed to git)

---

## 💬 Review Comment Templates

### Swift 6 Concurrency Issue
```
⚠️ **Swift 6 Concurrency Issue**

Using `Timer.publish` in an actor-isolated context will cause compiler errors. Use `Task.sleep` instead:

```swift
// ❌ Wrong
Timer.publish(every: 2, on: .main, in: .common)

// ✅ Correct
while !isCancelled {
    await Task.sleep(for: .seconds(2))
    await doWork()
}
```

**Why:** Combine doesn't integrate with Swift 6 actor isolation.
**Fix:** Replace with `Task.sleep` or use `AdaptivePollingStrategy`.
```

---

### SwiftData Persistent ID Issue
```
🚨 **Critical: Temporary ID Usage**

Using `persistentModelID` before `save()` will crash with "Illegal attempt to create a full future for temporary identifier".

```swift
// ❌ Wrong
let work = Work(title: "...")
modelContext.insert(work)
let id = work.persistentModelID  // ❌ Crash!

// ✅ Correct
let work = Work(title: "...")
modelContext.insert(work)
try modelContext.save()  // IDs become permanent
let id = work.persistentModelID  // ✅ Safe
```

**Why:** SwiftData assigns temporary IDs until `save()` is called.
**Fix:** Always `save()` before using IDs for background tasks, deduplication, etc.
```

---

### Missing @Bindable
```
⚠️ **Missing @Bindable**

SwiftData models passed to child views need `@Bindable` for reactive updates:

```swift
// ❌ Wrong
struct BookDetailView: View {
    let work: Work  // Won't update when work changes
}

// ✅ Correct
struct BookDetailView: View {
    @Bindable var work: Work  // Reactive updates!
}
```

**Why:** SwiftData relies on `@Bindable` for observation in child views.
**Fix:** Add `@Bindable` to the parameter.
```

---

### Performance Issue (N+1 Query)
```
⚡ **Performance Issue: N+1 Query**

Loading all objects to count is 100x slower than `fetchCount()`:

```swift
// ❌ Slow (50ms for 1000 books)
let works = try modelContext.fetch(FetchDescriptor<Work>())
let count = works.count

// ✅ Fast (0.5ms for 1000 books)
let count = try modelContext.fetchCount(FetchDescriptor<Work>())
```

**Why:** `fetchCount()` uses SQL COUNT, not loading all objects.
**Fix:** Replace with `fetchCount()`.
```

---

### Navigation Anti-Pattern
```
⚠️ **Navigation Anti-Pattern**

Using sheets for drill-down navigation breaks iOS 26 HIG:

```swift
// ❌ Wrong
.sheet(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ✅ Correct
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}
```

**Why:** Sheets are for modals, not drill-down navigation (iOS 26 HIG).
**Fix:** Use push navigation (`.navigationDestination`).
```

---

## 🔍 Review Workflow

### 1. Automated Checks
```bash
# Run before manual review
swift build  # Zero warnings required
swift test   # All tests pass
```

### 2. Manual Review
- Read diff carefully (line-by-line)
- Check against patterns.md rules
- Verify tests cover new code
- Test on real device (if UI changes)

### 3. Approval Criteria
- ✅ Zero warnings
- ✅ Tests pass
- ✅ Patterns followed
- ✅ Real device tested (if applicable)
- ✅ Documentation updated (if public API changed)

---

## 🎓 Learning Resources

**For Reviewers:**
- `.robit/patterns.md` - Code standards
- `.robit/context.md` - Codebase structure
- `docs/CONCURRENCY_GUIDE.md` - Swift 6 concurrency deep-dive
- `docs/features/` - Feature-specific implementation details

**External:**
- [Swift 6 Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [iOS 26 HIG](https://developer.apple.com/design/human-interface-guidelines)

---

**Use this template for all code reviews. Adapt checklist for project-specific needs.**
