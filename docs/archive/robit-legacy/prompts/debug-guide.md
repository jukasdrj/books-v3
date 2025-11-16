# Systematic Debugging Guide

Use this structured approach when debugging issues in BooksTrack (or any Swift/iOS project).

---

## 🎯 Debugging Workflow

### Phase 1: Reproduce & Observe

**1. Reproduce the Issue**
- [ ] Can you consistently reproduce it? (Yes/No/Sometimes)
- [ ] What are the exact steps to reproduce?
- [ ] Does it happen on simulator, real device, or both?
- [ ] iOS version? Device model? Build configuration (Debug/Release)?

**2. Gather Evidence**
- [ ] Error message (if any)
- [ ] Console logs (Xcode Console output)
- [ ] Crash stack trace (if crash)
- [ ] User actions leading to issue
- [ ] Expected vs actual behavior

**Example Evidence:**
```
Issue: App crashes when tapping "Add to Library"
Reproduces: Yes, 100% on real iPhone 15 Pro (iOS 26.0), simulator works fine
Error: "Illegal attempt to create a full future for temporary identifier"
Stack trace: EnrichmentQueue.enqueue() → persistentModelID access
Expected: Book added to library
Actual: Crash
```

---

### Phase 2: Hypothesis Formation

**3. Form Initial Hypotheses**

Based on error message and context, list 2-4 possible root causes:

**Example Hypotheses:**
1. **Temporary ID issue:** Using `persistentModelID` before calling `save()`
2. **Threading issue:** Accessing SwiftData from background thread
3. **ModelContext issue:** Using wrong context (background vs main)
4. **Relationship issue:** Setting relationship before inserting models

**Rank by likelihood:**
- 🔥 **High:** Temporary ID issue (error message matches known pattern)
- 🟡 **Medium:** Threading issue (not on main thread?)
- 🟢 **Low:** ModelContext issue (unlikely, using @Environment)
- 🟢 **Low:** Relationship issue (inserting before relating)

---

### Phase 3: Investigation

**4. Test Top Hypothesis**

**Hypothesis:** Temporary ID issue (using `persistentModelID` before `save()`)

**Evidence to collect:**
- [ ] Where is `persistentModelID` accessed? (code location)
- [ ] Is there a `save()` call before that access? (Yes/No)
- [ ] What triggers the `enqueue()` call? (user action? automatic?)

**Investigation:**
```swift
// Found in AddBookView.swift:123
let work = Work(title: title)
modelContext.insert(work)
// ❌ No save() here!
EnrichmentQueue.shared.enqueue(work.persistentModelID)  // ← Crash here!
```

**Conclusion:** ✅ Hypothesis confirmed! Missing `save()` before `enqueue()`.

---

### Phase 4: Root Cause Analysis

**5. Confirm Root Cause**

**Root Cause:** Using `persistentModelID` before calling `save()` on ModelContext.

**Why this breaks:**
- SwiftData assigns temporary IDs on `insert()`
- Temporary IDs are invalid for futures/deduplication
- `save()` converts temporary IDs to permanent IDs
- Background tasks (EnrichmentQueue) need permanent IDs

**Evidence:**
- ✅ Error message: "temporary identifier"
- ✅ Code inspection: No `save()` before `enqueue()`
- ✅ Known pattern: See `.robit/patterns.md` Rule #1

---

### Phase 5: Fix Implementation

**6. Implement Fix**

**Fix:**
```swift
// Before (crashes):
let work = Work(title: title)
modelContext.insert(work)
EnrichmentQueue.shared.enqueue(work.persistentModelID)  // ❌ Crash!

// After (works):
let work = Work(title: title)
modelContext.insert(work)
work.authors = [author]  // Set relationships
try modelContext.save()  // ✅ Make IDs permanent!
EnrichmentQueue.shared.enqueue(work.persistentModelID)  // ✅ Safe!
```

**7. Verify Fix**
- [ ] Build succeeds (no warnings)
- [ ] Reproduce steps no longer crash
- [ ] Test on simulator (works)
- [ ] Test on real device (works)
- [ ] Add regression test (prevent future breakage)

**Regression Test:**
```swift
@Test("EnrichmentQueue handles new works correctly")
func testEnqueueNewWork() async throws {
    let work = Work(title: "Test Book")
    modelContext.insert(work)

    // ✅ Must save before enqueuing
    try modelContext.save()

    let id = work.persistentModelID
    #expect(!EnrichmentQueue.shared.contains(id))

    EnrichmentQueue.shared.enqueue(id)
    #expect(EnrichmentQueue.shared.contains(id))
}
```

---

## 🔍 Common Issue Patterns

### SwiftData Crashes

**Symptom:** Crash with "temporary identifier" error
**Root Cause:** Using `persistentModelID` before `save()`
**Fix:** Always `save()` before using IDs
**See:** `.robit/patterns.md` Rule #1

---

**Symptom:** View doesn't update when SwiftData model changes
**Root Cause:** Missing `@Bindable` in child view
**Fix:** Add `@Bindable var work: Work` (not `let work: Work`)
**See:** `.robit/patterns.md` Rule #3

---

**Symptom:** Relationship crash "object not inserted"
**Root Cause:** Setting relationship before inserting models
**Fix:** Insert both models, THEN set relationships
**See:** `.robit/patterns.md` Rule #2

---

### Swift 6 Concurrency Errors

**Symptom:** Compiler error "Timer.publish unavailable in actor"
**Root Cause:** Combine doesn't integrate with actor isolation
**Fix:** Replace with `Task.sleep` or `AdaptivePollingStrategy`
**See:** `.robit/patterns.md` Rule #4

---

**Symptom:** Data race warnings in console
**Root Cause:** Shared mutable state without protection
**Fix:** Use actors, `@MainActor`, or `nonisolated`
**See:** `docs/CONCURRENCY_GUIDE.md`

---

### UI/Navigation Issues

**Symptom:** Keyboard doesn't appear when searching
**Root Cause:** Mixing `@FocusState` with `.searchable()`
**Fix:** Remove `@FocusState`, let `.searchable()` manage focus
**See:** `.robit/patterns.md` Rule #5

---

**Symptom:** Back button doesn't work after navigation
**Root Cause:** Using sheets for drill-down navigation
**Fix:** Use push navigation (`.navigationDestination`)
**See:** `.robit/patterns.md` Rule #6

---

### Performance Issues

**Symptom:** Slow scrolling in library view
**Root Cause:** Loading all objects to count (N+1 query)
**Fix:** Use `fetchCount()` instead of `fetch().count`
**See:** `.robit/patterns.md` Performance section

---

**Symptom:** Images load slowly, re-download every time
**Root Cause:** Using `AsyncImage` directly (no cache)
**Fix:** Use `CachedAsyncImage` everywhere
**See:** `.robit/patterns.md` Performance section

---

## 🛠️ Debugging Tools

### Xcode Tools

**Console (Cmd+Shift+Y):**
- View logs from `OSLog`, `print()`, `dump()`
- Filter by subsystem/category
- Copy stack traces for crashes

**Breakpoints:**
- Set breakpoints on error throws
- Symbolic breakpoint: `swift_willThrow` (catches all throws)
- Conditional breakpoints (only trigger if condition true)

**Instruments:**
- Time Profiler (find slow code)
- Allocations (memory leaks)
- SwiftUI (view updates, body calls)
- Network (API calls, latency)

**View Debugger (Cmd+Shift+M):**
- 3D view hierarchy
- Inspect view frames, constraints
- Debug layout issues

---

### Command Line Tools

**Tail Logs (Backend):**
```bash
# Real-time backend logs
npx wrangler tail api-worker --format pretty

# Filter by search term
npx wrangler tail api-worker --search "error"

# Follow specific jobId
npx wrangler tail api-worker --search "jobId:abc-123"
```

**cURL Testing:**
```bash
# Test API endpoint
curl "https://api.oooefam.net/v1/search/isbn?isbn=9780134685991" | jq

# Test with verbose output
curl -v "https://api.oooefam.net/health"

# Test POST endpoint
curl -X POST "https://api.oooefam.net/v1/enrichment/batch" \
  -H "Content-Type: application/json" \
  -d '{"workIds":["uuid1","uuid2"]}'
```

---

## 📋 Debugging Checklist

Before asking for help, ensure you've:

- [ ] **Reproduced consistently** (know exact steps)
- [ ] **Gathered evidence** (error messages, logs, stack traces)
- [ ] **Formed hypotheses** (2-4 possible causes)
- [ ] **Tested top hypothesis** (collected evidence)
- [ ] **Checked common patterns** (see patterns.md)
- [ ] **Searched codebase** (similar issues fixed before?)
- [ ] **Read documentation** (feature docs, architecture docs)
- [ ] **Tested on real device** (simulator bugs differ)
- [ ] **Simplified reproduction** (minimal test case)

---

## 💡 Pro Tips

### 1. **Rubber Duck Debugging**
Explain the problem out loud (to a duck, AI, or teammate). Often helps clarify thinking.

### 2. **Binary Search**
If unsure where issue occurs, comment out half the code. Does it still happen? Narrow down.

### 3. **Git Bisect**
If issue recently appeared, use `git bisect` to find the commit that introduced it.

### 4. **Check Recent Changes**
Look at git log for recent commits to affected files. Did something change?

### 5. **Read Error Messages Carefully**
Error messages contain clues! "temporary identifier" → SwiftData ID issue.

### 6. **Test Assumptions**
Don't assume code works as expected. Add `print()` or breakpoints to verify.

### 7. **Simplify**
Remove unnecessary code to create minimal reproduction. Easier to debug.

---

## 🎓 When to Ask for Help

Ask for help if:
- ✅ You've followed this guide completely
- ✅ You've tested top 2-3 hypotheses (no luck)
- ✅ You've checked common patterns (not a known issue)
- ✅ You've simplified to minimal reproduction
- ✅ You've spent 30+ minutes debugging

**When asking, provide:**
- Issue description (expected vs actual)
- Reproduction steps (exact, repeatable)
- Evidence (error messages, logs, stack traces)
- Hypotheses tested (what you've already tried)
- Minimal code example (relevant snippets only)

---

**Systematic debugging saves time. Don't guess—investigate!**
