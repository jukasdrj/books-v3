# SwiftData Relationship Initialization Fixes - Implementation Plan

**Created:** October 31, 2025
**Priority:** CRITICAL (Crash Fix)
**Estimated Effort:** 4-6 hours
**Risk Level:** Medium (touching core data models)

## Executive Summary

Fix SwiftData crash caused by setting relationships on models before they receive permanent IDs from ModelContext. This violates SwiftData's requirement that models must be inserted before relationships can be established.

**Root Cause:** `UserLibraryEntry` and `Edition` initializers accept relationship objects as parameters and set relationships immediately, before models are inserted into context.

**Impact:** App crashes with "temporary identifier" errors when creating new library entries or editions.

## Issues Summary (Priority Ordered)

### 🔴 HIGH PRIORITY - Crash Source
**Problem:** Initializers set relationships before ModelContext insertion
**Files Affected:** 15+ production & test files
**Timeline:** Fix immediately (Phases 1-2)

### 🟡 MEDIUM PRIORITY - Data Integrity Bug
**Problem:** `Work.userEntry` doesn't prioritize owned entries
**Files Affected:** 1 file
**Timeline:** Fix after crash resolution (Phase 3)

### 🟢 LOW PRIORITY - Delete Rule Issue
**Problem:** `.nullify` delete rule creates inconsistent state
**Files Affected:** 1 file
**Timeline:** Fix after data integrity (Phase 4)

---

## Phase 1: Model Refactoring (HIGH PRIORITY)

### Task 1.1: Refactor UserLibraryEntry Initializer

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift`

**Current Implementation (Lines 31-41) - UNSAFE:**
```swift
public init(
    work: Work,
    edition: Edition? = nil,
    readingStatus: ReadingStatus = ReadingStatus.toRead
) {
    self.work = work
    self.edition = edition
    self.readingStatus = readingStatus
    self.dateAdded = Date()
    self.lastModified = Date()
}
```

**New Implementation - SAFE:**
```swift
public init(
    readingStatus: ReadingStatus = ReadingStatus.toRead
) {
    self.readingStatus = readingStatus
    self.dateAdded = Date()
    self.lastModified = Date()
    // CRITICAL: work and edition MUST be set AFTER insert
    // Usage: let entry = UserLibraryEntry(); context.insert(entry); entry.work = work
}
```

**Rationale:** Remove relationship parameters to prevent developers from setting relationships before insertion.

---

### Task 1.2: Update UserLibraryEntry Factory Methods

**Location:** Same file, lines 44-52

**Current Factory Methods - UNSAFE:**
```swift
/// Create wishlist entry (want to read but don't own)
public static func createWishlistEntry(for work: Work) -> UserLibraryEntry {
    let entry = UserLibraryEntry(work: work, edition: nil, readingStatus: ReadingStatus.wishlist)
    return entry
}

/// Create owned entry (have specific edition)
public static func createOwnedEntry(for work: Work, edition: Edition, status: ReadingStatus = ReadingStatus.toRead) -> UserLibraryEntry {
    let entry = UserLibraryEntry(work: work, edition: edition, readingStatus: status)
    return entry
}
```

**New Factory Methods - SAFE:**
```swift
/// Create wishlist entry (want to read but don't own)
/// CRITICAL: Caller MUST have already inserted work into context
public static func createWishlistEntry(for work: Work, context: ModelContext) -> UserLibraryEntry {
    let entry = UserLibraryEntry(readingStatus: .wishlist)
    context.insert(entry)  // Get permanent ID first
    entry.work = work      // Set relationship after insert
    return entry
}

/// Create owned entry (have specific edition)
/// CRITICAL: Caller MUST have already inserted work and edition into context
public static func createOwnedEntry(
    for work: Work,
    edition: Edition,
    status: ReadingStatus = .toRead,
    context: ModelContext
) -> UserLibraryEntry {
    let entry = UserLibraryEntry(readingStatus: status)
    context.insert(entry)  // Get permanent ID first
    entry.work = work      // Set relationships after insert
    entry.edition = edition
    return entry
}
```

**Breaking Change:** Factory methods now require `ModelContext` parameter.

**Migration Strategy:**
1. Add new factory methods with `context` parameter
2. Update all callsites to pass context
3. Remove old factory methods

---

### Task 1.3: Refactor Edition Initializer

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift`

**Current Implementation (Lines 54-79) - UNSAFE:**
```swift
public init(
    isbn: String? = nil,
    publisher: String? = nil,
    publicationDate: String? = nil,
    pageCount: Int? = nil,
    format: EditionFormat = EditionFormat.hardcover,
    coverImageURL: String? = nil,
    editionTitle: String? = nil,
    editionDescription: String? = nil,
    work: Work? = nil,  // ❌ REMOVE THIS PARAMETER
    primaryProvider: String? = nil
) {
    self.isbn = isbn
    self.publisher = publisher
    self.publicationDate = publicationDate
    self.pageCount = pageCount
    self.format = format
    self.coverImageURL = coverImageURL
    self.editionTitle = editionTitle
    self.editionDescription = editionDescription
    self.work = work  // ❌ REMOVE THIS LINE
    self.primaryProvider = primaryProvider
    self.contributors = []
    self.dateCreated = Date()
    self.lastModified = Date()
}
```

**New Implementation - SAFE:**
```swift
public init(
    isbn: String? = nil,
    publisher: String? = nil,
    publicationDate: String? = nil,
    pageCount: Int? = nil,
    format: EditionFormat = EditionFormat.hardcover,
    coverImageURL: String? = nil,
    editionTitle: String? = nil,
    editionDescription: String? = nil,
    // work: Work? parameter REMOVED
    primaryProvider: String? = nil
) {
    self.isbn = isbn
    self.publisher = publisher
    self.publicationDate = publicationDate
    self.pageCount = pageCount
    self.format = format
    self.coverImageURL = coverImageURL
    self.editionTitle = editionTitle
    self.editionDescription = editionDescription
    // CRITICAL: work MUST be set AFTER insert
    // Usage: let edition = Edition(); context.insert(edition); edition.work = work
    self.primaryProvider = primaryProvider
    self.contributors = []
    self.dateCreated = Date()
    self.lastModified = Date()
}
```

**Breaking Change:** Removes `work` parameter from initializer.

---

## Phase 2: Update All Callsites (HIGH PRIORITY)

### Standard Insert-Before-Relate Pattern

**Apply this pattern to ALL callsites:**

```swift
// ❌ OLD (CRASHES)
let edition = Edition(work: work)
context.insert(edition)

// ✅ NEW (SAFE)
let edition = Edition()
context.insert(work)      // Insert parent first (if not already inserted)
context.insert(edition)   // Insert child second
edition.work = work       // Set relationship AFTER both have permanent IDs
```

### Task 2.1: Update Production Code (8 files)

#### File 1: WorkDetailView.swift

**Location:** Line 23
**Current:**
```swift
Edition(work: work)
```

**Fix:**
```swift
// Need to review context - WorkDetailView may be read-only preview
// If creating persistent edition, must insert before relate
let edition = Edition()
context.insert(edition)
edition.work = work
```

**Action:** Review if this is preview-only or creates persistent data.

---

#### File 2: iOS26AdaptiveBookCard.swift

**Location:** Line 540
**Current:**
```swift
edition: primaryEdition ?? Edition(work: work)
```

**Context:** This appears to be for preview/display purposes.

**Fix:**
```swift
// If this is display-only, create transient edition
edition: primaryEdition ?? {
    let edition = Edition()
    edition.work = work  // OK for transient (non-persisted) objects
    return edition
}()
```

**Action:** Verify if this edition is ever persisted. If not, transient relationship is OK.

---

#### File 3: iOS26FloatingBookCard.swift

**Locations:** Lines 309, 642 (2 occurrences)
**Current:** Same as AdaptiveBookCard above
**Fix:** Apply same pattern as File 2

---

#### File 4: iOS26LiquidListRow.swift

**Location:** Line 522
**Current:** Same as AdaptiveBookCard above
**Fix:** Apply same pattern as File 2

---

#### File 5: WorkDiscoveryView.swift

**Locations:** Lines 394, 512

**Line 394:**
```swift
edition: edition ?? createDefaultEdition(work: work)
```

**Line 512 - Helper Function:**
```swift
private func createDefaultEdition(work: Work) -> Edition {
    // Implementation TBD
}
```

**Fix - Refactor Helper:**
```swift
private func createDefaultEdition(work: Work, context: ModelContext) -> Edition {
    let edition = Edition()
    context.insert(edition)
    edition.work = work
    return edition
}

// Usage at line 394:
edition: edition ?? createDefaultEdition(work: work, context: modelContext)
```

**Action:** Pass ModelContext to helper, apply insert-before-relate.

---

#### File 6: DTOMapper.swift

**Location:** Line 58
**Method:** `mapToEdition(_ dto: EditionDTO)`

**Action:** Review implementation to ensure:
1. Edition created without `work` parameter
2. If edition needs work relationship, caller must insert both and set relationship

**Likely Fix:**
```swift
public func mapToEdition(_ dto: EditionDTO) throws -> Edition {
    let edition = Edition(
        isbn: dto.isbn,
        publisher: dto.publisher,
        // ... other fields
        // work: NO PARAMETER HERE
    )
    // Caller responsible for: context.insert(edition); edition.work = work
    return edition
}
```

---

#### File 7: ContentView.swift

**Locations:** Lines 166, 175, 184 (3 preview editions)

**Current Pattern (Example):**
```swift
let klaraEdition = Edition(
    isbn: "9780593318171",
    publisher: "Knopf",
    publicationDate: "2021",
    pageCount: 320,
    format: .hardcover,
    coverImageURL: "...",
    work: klaraWork  // ❌ REMOVE
)
```

**Fix:**
```swift
let klaraEdition = Edition(
    isbn: "9780593318171",
    publisher: "Knopf",
    publicationDate: "2021",
    pageCount: 320,
    format: .hardcover,
    coverImageURL: "..."
    // work parameter removed
)

// In preview setup:
modelContext.insert(klaraWork)
modelContext.insert(klaraEdition)
klaraEdition.work = klaraWork  // Set after insert
```

**Action:** Update all 3 preview editions (Klara, Kindred, Americanah).

---

#### File 8: ScanResultsView.swift

**Location:** Line 563

**Action:** Review implementation to verify insert-before-relate pattern is followed.

---

### Task 2.2: Update Test Code (5 files)

#### File 1: RelationshipCascadeTests.swift

**3 problematic lines:**

**Line 16:**
```swift
// ❌ OLD
let entry = UserLibraryEntry(work: work, readingStatus: .toRead)

// ✅ NEW
let entry = UserLibraryEntry(readingStatus: .toRead)
context.insert(work)
context.insert(entry)
entry.work = work
```

**Line 70:**
```swift
// ❌ OLD
let edition = Edition(isbn: "1234567890", format: .hardcover, work: work)

// ✅ NEW
let edition = Edition(isbn: "1234567890", format: .hardcover)
context.insert(work)
context.insert(edition)
edition.work = work
```

**Line 95:**
```swift
// ❌ OLD
let entry = UserLibraryEntry(work: work, readingStatus: .read)

// ✅ NEW
let entry = UserLibraryEntry(readingStatus: .read)
context.insert(work)
context.insert(entry)
entry.work = work
```

**Note:** Line 94 already shows CORRECT pattern - use as reference!

---

#### File 2: LibraryFilterServiceTests.swift

**Line 20:**
```swift
// ❌ OLD
let entry = UserLibraryEntry(work: work1, readingStatus: .toRead)

// ✅ NEW
let entry = UserLibraryEntry(readingStatus: .toRead)
context.insert(work1)
context.insert(entry)
entry.work = work1
```

---

#### File 3: LibraryResetCrashTests.swift

**3 problematic lines (25, 73, 81):**

Apply same pattern as RelationshipCascadeTests above.

---

#### File 4: ReadingStatsTests.swift

**5 problematic lines:**

**Lines 18, 44:**
```swift
// ❌ OLD
let edition = Edition(pageCount: 300, work: work)

// ✅ NEW
let edition = Edition(pageCount: 300)
context.insert(work)
context.insert(edition)
edition.work = work
```

**Lines 94-96 (3 editions):**
Apply same pattern.

---

#### File 5: InsightsIntegrationTests.swift

**Lines 42-44 (3 editions):**
Apply same pattern as ReadingStatsTests.

---

## Phase 3: Data Integrity Fix (MEDIUM PRIORITY)

### Task 3.1: Fix Work.userEntry Prioritization

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift`
**Location:** Lines 149-151

**Problem:** Current implementation returns first entry arbitrarily. If user has both wishlist and owned entries, might return wishlist entry, breaking `primaryEdition` logic.

**Current Implementation - BUGGY:**
```swift
/// Get the user's library entry for this work (if any)
var userEntry: UserLibraryEntry? {
    return userLibraryEntries?.first
}
```

**New Implementation - CORRECT:**
```swift
/// Get the user's library entry for this work (if any)
/// Prioritizes owned entries over wishlist entries to ensure correct edition selection
var userEntry: UserLibraryEntry? {
    // First, try to find an owned entry (has edition, not wishlist status)
    if let ownedEntry = userLibraryEntries?.first(where: { $0.isOwned }) {
        return ownedEntry
    }

    // Fallback to wishlist entry if no owned entry exists
    return userLibraryEntries?.first(where: { $0.isWishlistItem })
}
```

**Verification:** Requires `isOwned` and `isWishlistItem` properties exist in UserLibraryEntry (they do - lines 117-124).

**Test Case to Add:**
```swift
@Test("Work.userEntry prioritizes owned over wishlist")
func testUserEntryPrioritization() throws {
    let context = createTestContext()

    let work = Work(title: "Test Book")
    let edition = Edition(isbn: "123")

    context.insert(work)
    context.insert(edition)
    edition.work = work

    // Create wishlist entry first
    let wishlistEntry = UserLibraryEntry(readingStatus: .wishlist)
    context.insert(wishlistEntry)
    wishlistEntry.work = work

    // Create owned entry second
    let ownedEntry = UserLibraryEntry(readingStatus: .toRead)
    context.insert(ownedEntry)
    ownedEntry.work = work
    ownedEntry.edition = edition

    work.userLibraryEntries = [wishlistEntry, ownedEntry]
    try context.save()

    // Verify owned entry is returned, not wishlist
    #expect(work.userEntry?.isOwned == true)
    #expect(work.userEntry?.edition != nil)
}
```

---

## Phase 4: Delete Rule Fix (LOW PRIORITY)

### Task 4.1: Change Edition Delete Rule to .deny

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift`
**Location:** Line 51

**Problem:** `.nullify` delete rule causes inconsistent state. If user deletes Edition, UserLibraryEntry.edition becomes nil, but status might be `.toRead` (not `.wishlist`), creating invalid state.

**Current Implementation:**
```swift
@Relationship(deleteRule: .nullify, inverse: \UserLibraryEntry.edition)
var userLibraryEntries: [UserLibraryEntry]?
```

**New Implementation:**
```swift
@Relationship(deleteRule: .deny, inverse: \UserLibraryEntry.edition)
var userLibraryEntries: [UserLibraryEntry]?
```

**Impact:** Attempting to delete Edition with active UserLibraryEntries will fail. User must:
1. Delete library entry first, OR
2. Convert entry to wishlist (sets edition to nil)

**UX Consideration:** Add user-facing error message:
```swift
// In deletion handler
do {
    context.delete(edition)
    try context.save()
} catch {
    showError("Cannot delete edition while books in library reference it. Remove books from library first.")
}
```

**Test Case:**
```swift
@Test("Edition delete with .deny rule fails when entries exist")
func testEditionDenyDeleteRule() throws {
    let context = createTestContext()

    let work = Work(title: "Test")
    let edition = Edition(isbn: "123")
    let entry = UserLibraryEntry(readingStatus: .toRead)

    context.insert(work)
    context.insert(edition)
    context.insert(entry)

    edition.work = work
    entry.work = work
    entry.edition = edition
    try context.save()

    // Attempt to delete edition
    context.delete(edition)

    // Should throw error due to .deny rule
    #expect(throws: Error.self) {
        try context.save()
    }
}
```

---

## Phase 5: Validation & Testing

### Task 5.1: Add Runtime Validation (Optional)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift`

**Add Validation Method:**
```swift
// MARK: - Validation

/// Validate entry is in consistent state before saving
/// Throws ValidationError if state is invalid
func validate() throws {
    // Rule 1: Wishlist items cannot have editions
    if readingStatus == .wishlist && edition != nil {
        throw ValidationError.wishlistCannotHaveEdition
    }

    // Rule 2: Work relationship must exist
    guard work != nil else {
        throw ValidationError.missingWorkRelationship
    }

    // Note: We don't enforce "owned must have edition" because
    // .deny delete rule on Edition prevents edition deletion if entries exist
}

enum ValidationError: Error, LocalizedError {
    case wishlistCannotHaveEdition
    case missingWorkRelationship

    var errorDescription: String? {
        switch self {
        case .wishlistCannotHaveEdition:
            return "Wishlist items cannot have a specific edition"
        case .missingWorkRelationship:
            return "Library entry must be associated with a work"
        }
    }
}
```

**Usage:**
```swift
// Before saving
try entry.validate()
try context.save()
```

---

### Task 5.2: Update Existing Tests

**Test Files to Update:**
1. ✅ RelationshipCascadeTests.swift - Already has good delete cascade tests
2. ✅ LibraryResetCrashTests.swift - Tests library reset flow
3. Add new test for Work.userEntry prioritization (see Phase 3)
4. Add new test for Edition .deny delete rule (see Phase 4)

**New Test File:** `SwiftDataRelationshipSafetyTests.swift`

```swift
import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

@Suite("SwiftData Relationship Safety")
@MainActor
struct SwiftDataRelationshipSafetyTests {

    @Test("Insert-before-relate pattern prevents crashes")
    func testInsertBeforeRelate() throws {
        let context = createTestContext()

        // Create models WITHOUT relationships
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "123")
        let entry = UserLibraryEntry(readingStatus: .toRead)

        // Insert BEFORE setting relationships (get permanent IDs)
        context.insert(work)
        context.insert(edition)
        context.insert(entry)

        // Set relationships AFTER insert
        edition.work = work
        entry.work = work
        entry.edition = edition

        // Save should succeed
        try context.save()

        // Verify relationships persisted
        #expect(edition.work?.title == "Test Book")
        #expect(entry.work?.title == "Test Book")
        #expect(entry.edition?.isbn == "123")
    }

    @Test("Work.userEntry prioritizes owned over wishlist")
    func testUserEntryPrioritization() throws {
        // Implementation from Phase 3
    }

    @Test("Edition delete denied when entries exist")
    func testEditionDeleteDeny() throws {
        // Implementation from Phase 4
    }

    private func createTestContext() -> ModelContext {
        let schema = Schema([Work.self, Author.self, Edition.self, UserLibraryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
```

---

### Task 5.3: Real Device Testing

**Test Scenarios:**

1. **Create Wishlist Entry**
   - Search for book
   - Tap "Add to Wishlist"
   - Verify no crash
   - Verify entry created with status=.wishlist, edition=nil

2. **Acquire Edition (Wishlist → Owned)**
   - Select wishlist entry
   - Tap "I Own This" → Select edition
   - Verify entry.edition set correctly
   - Verify status changed to .toRead

3. **Delete Work (Cascade Test)**
   - Create work with entry
   - Delete work
   - Verify entry also deleted (cascade rule)

4. **Attempt Edition Deletion (Deny Test)**
   - Create owned entry with edition
   - Attempt to delete edition
   - Verify error shown
   - Verify edition NOT deleted

5. **Complex Relationship Graph**
   - Create Author → Work → Edition → UserLibraryEntry chain
   - Save and force-quit app
   - Reopen app
   - Verify all relationships intact

---

## Success Criteria

- [ ] All model initializers follow insert-before-relate pattern
- [ ] Zero compiler warnings related to SwiftData relationships
- [ ] All unit tests pass (existing + new)
- [ ] All integration tests pass
- [ ] App builds with zero warnings
- [ ] Real device testing: No crashes during normal workflows
- [ ] Work.userEntry prioritizes owned entries correctly
- [ ] Edition deletion blocked when library entries exist
- [ ] Documentation updated (CLAUDE.md, data model docs)

---

## Rollback Plan

**If issues arise post-deployment:**

1. **Immediate:** Revert model initializer changes
2. **Short-term:** Keep insert-before-relate pattern in new code only
3. **Long-term:** Gradual migration of existing callsites

**Git Strategy:**
- Create feature branch: `fix/swiftdata-relationship-safety`
- Commit each phase separately for granular rollback
- Tag commit before merge: `v3.x.x-pre-relationship-fix`

---

## Documentation Updates

### Update CLAUDE.md

Add to "SwiftData Models" section:

```markdown
**🚨 CRITICAL: Insert-Before-Relate Lifecycle**

SwiftData models MUST be inserted into ModelContext BEFORE setting relationships.

```swift
// ❌ WRONG: Crash with "temporary identifier"
let edition = Edition(work: work)
context.insert(edition)

// ✅ CORRECT: Insert BEFORE setting relationships
let edition = Edition()
context.insert(work)    // Get permanent ID
context.insert(edition) // Get permanent ID
edition.work = work     // Safe - both have permanent IDs
```

**Rule:** ALWAYS call `modelContext.insert()` IMMEDIATELY after creating a new model, BEFORE setting any relationships.
```

### Update Data Model Docs

**File:** `docs/architecture/2025-10-26-data-model-breakdown.md`

Add section on relationship safety patterns.

---

## Estimated Timeline

| Phase | Estimated Time | Notes |
|-------|----------------|-------|
| Phase 1: Model Refactoring | 1 hour | 3 files, straightforward changes |
| Phase 2: Production Callsites | 2 hours | 8 files, varying complexity |
| Phase 2: Test Callsites | 1 hour | 5 files, mechanical changes |
| Phase 3: Data Integrity Fix | 30 min | 1 file, simple logic change |
| Phase 4: Delete Rule Fix | 30 min | 1 file + UX error handling |
| Phase 5: Testing | 1-2 hours | Unit + integration + device |
| **Total** | **6-7 hours** | |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking existing functionality | Medium | High | TDD approach, comprehensive tests |
| Missing callsites during migration | Low | High | Compiler errors will catch missing context param |
| .deny delete rule too restrictive | Low | Medium | Add clear error messages, document UX flow |
| Performance regression | Very Low | Low | Insert-before-relate is standard pattern |

---

## Questions for Review

1. **Preview Code:** Do transient Edition objects (created for preview purposes, never persisted) need insert-before-relate pattern?
   - **Recommendation:** No - only enforce for persisted objects

2. **Factory Method Compatibility:** Should we keep old factory methods temporarily for backward compatibility?
   - **Recommendation:** No - force migration via compiler errors (safer)

3. **Validation Enforcement:** Should we call `validate()` automatically before every save?
   - **Recommendation:** Optional - add as enhancement later

4. **Delete Rule UX:** What error message should users see when Edition deletion is denied?
   - **Recommendation:** "Cannot delete this edition while it's in your library. Remove it from your library first, or change the entry to 'Wishlist'."

---

## Next Steps

1. Review this plan
2. Get approval for breaking changes (factory method signatures)
3. Create feature branch
4. Execute Phase 1 (Model Refactoring)
5. Run tests after each phase
6. Deploy to TestFlight for beta testing
7. Monitor crash reports
8. Merge to main after validation

---

**Plan Status:** Ready for Review
**Reviewers:** @jukasdrj
**Approval Required Before:** Starting Phase 1 implementation
