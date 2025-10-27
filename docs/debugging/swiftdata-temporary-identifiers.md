# SwiftData Temporary Persistent Identifiers

## The Problem

SwiftData assigns **temporary** persistent identifiers to unsaved model objects. After calling `modelContext.save()`, these temporary IDs are invalidated and replaced with permanent IDs.

**Fatal Error:**
```
Illegal attempt to create a full future for a temporary identifier
cannot fulfill model without a store identifier
Fatal error: This model instance was invalidated because its backing data
could no longer be found the store
```

## Root Cause

Capturing `model.persistentModelID` BEFORE `modelContext.save()`, then using that ID AFTER save.

## The Fix

**❌ WRONG:**
```swift
let work = Work(...)
modelContext.insert(work)
let workID = work.persistentModelID  // ❌ Temporary ID!

try modelContext.save()  // ID becomes permanent

// Later, in background task:
let fetched = context.model(for: workID)  // 💥 CRASH!
```

**✅ CORRECT:**
```swift
let work = Work(...)
modelContext.insert(work)

try modelContext.save()  // Save FIRST

let workID = work.persistentModelID  // ✅ Permanent ID

// Later, in background task:
let fetched = context.model(for: workID)  // ✅ Works!
```

## Best Practice

**Collect model objects, not IDs:**
```swift
var works: [Work] = []
for item in items {
    let work = Work(...)
    modelContext.insert(work)
    works.append(work)  // ✅ Store object
}

try modelContext.save()

// Capture IDs after save
let workIDs = works.map { $0.persistentModelID }
```

## Affected Code

- ✅ Fixed: `ScanResultsView.addAllToLibrary()` (v3.x.x)
- ✅ Fixed: CSV import workflows (v3.1.0+)

## Testing

See `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/BookshelfScanning/ScanResultsModelTests.swift` for regression tests.
