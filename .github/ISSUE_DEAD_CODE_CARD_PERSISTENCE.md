# 🔴 CRITICAL: Dead Code in iOS26AdaptiveBookCard - Non-Functional Add/Wishlist Buttons

**Priority:** CRITICAL (User-Facing Bug)
**Category:** Bug - Data Persistence
**Affects:** v3.0.0+
**Discovered During:** SwiftData Relationship Fixes (Phase 2)

---

## Problem Summary

Three iOS 26 card components have "Add to Library" and "Add to Wishlist" buttons that **create UserLibraryEntry objects but never persist them** due to missing `@Environment(\.modelContext)`. Users click buttons and see no effect.

---

## Affected Files

1. **iOS26AdaptiveBookCard.swift** (Lines 536-549)
   - `addToLibrary()` - Creates entry, never saves
   - `addToWishlist()` - Creates entry, never saves
   - Buttons at lines 63, 66, 271, 474, 478

2. **iOS26FloatingBookCard.swift** (Lines 309, 642) - TBD (needs investigation)

3. **iOS26LiquidListRow.swift** (Line 522) - TBD (needs investigation)

---

## Code Evidence

```swift
// iOS26AdaptiveBookCard.swift:536-544
private func addToLibrary() {
    let primaryEdition = work.availableEditions.first
    _ = UserLibraryEntry.createOwnedEntry(
        for: work,
        edition: primaryEdition ?? Edition(work: work),  // ❌ This creates Edition with old API
        status: .toRead
    )
    // Add to SwiftData context  ❌ COMMENT BUT NO IMPLEMENTATION
}

private func addToWishlist() {
    _ = UserLibraryEntry.createWishlistEntry(for: work)
    // Add to SwiftData context  ❌ COMMENT BUT NO IMPLEMENTATION
}
```

**Problems:**
1. No `@Environment(\.modelContext)` to save entries
2. Factory methods now require `context` parameter (after Phase 1 refactor)
3. Users click buttons → Nothing persists → Confusing UX

---

## Impact

**User Experience:**
- Users click "Add to Library" or "Add to Wishlist"
- Buttons trigger functions that do nothing
- No feedback, no error, no persistence
- Users may add same book multiple times thinking it didn't work

**Technical:**
- Memory leak (creates objects, discards without cleanup)
- Violates SwiftData insert-before-relate pattern
- Dead code increases maintenance burden

---

## Root Cause

These views were likely created as **display-only components** for LibraryView, where users navigate to WorkDetailView for actual persistence. The add/wishlist buttons were **never implemented** but left in the UI.

---

## Proposed Solutions

### Option 1: Remove Dead Code (Recommended)
**Pros:** Clean, no false user expectations
**Cons:** Removes quick-add functionality

```swift
// Delete addToLibrary() and addToWishlist() functions
// Remove buttons from quickActionsMenu at lines 63, 66, 271, 474, 478
```

### Option 2: Implement Properly
**Pros:** Provides quick-add UX
**Cons:** Changes view API (breaking change), needs testing

```swift
struct iOS26AdaptiveBookCard: View {
    let work: Work
    @Environment(\.modelContext) private var modelContext  // ADD THIS

    private func addToLibrary() {
        let primaryEdition = work.availableEditions.first

        // If no edition exists, create one
        let edition = primaryEdition ?? {
            let newEdition = Edition()
            modelContext.insert(newEdition)
            newEdition.work = work
            return newEdition
        }()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        // Entry is auto-saved by factory method
    }
}
```

### Option 3: Disable Buttons (Temporary)
**Pros:** Prevents user confusion during fix
**Cons:** Incomplete solution

```swift
Button("Add to Library") {
    // TODO: Implement persistence (see GitHub issue #XXX)
}
.disabled(true)  // Disable until fixed
```

---

## Verification Steps

After fix:
1. ✅ Build succeeds with zero warnings
2. ✅ Buttons either removed OR fully functional
3. ✅ If implemented: Test on real device
   - Tap "Add to Library" → Work appears in library
   - Tap "Add to Wishlist" → Work appears in wishlist
4. ✅ No memory leaks (Instruments check)

---

## Related Issues

- **SwiftData Relationship Fixes Plan:** `docs/plans/2025-10-31-swiftdata-relationship-fixes-implementation.md`
- Phase 2 blocked on these files

---

## Acceptance Criteria

- [ ] No non-functional buttons in production UI
- [ ] All "Add to Library" / "Add to Wishlist" actions persist correctly OR are removed
- [ ] Zero compiler warnings
- [ ] Real device testing confirms expected behavior
- [ ] Documentation updated if API changes

---

**Recommendation:** Proceed with **Option 1 (Remove Dead Code)** for now. If quick-add functionality is desired, implement properly in a separate feature PR with full testing.
