# SwiftData Patterns - Quick Reference

**Essential patterns for SwiftData in BooksTrack** (iOS 26.0+, Swift 6.2+)

---

## 🚨 Critical Rules (NEVER VIOLATE)

### Rule #1: Save Before Using persistentModelID

```swift
// ❌ CRASH: "Illegal attempt to create a full future for temporary identifier"
let work = Work(title: "...")
modelContext.insert(work)
let id = work.persistentModelID  // ❌ Still temporary!

// ✅ CORRECT: Save FIRST
let work = Work(title: "...")
modelContext.insert(work)
try modelContext.save()  // IDs become permanent
let id = work.persistentModelID  // ✅ Safe!
```

**Why:** SwiftData assigns temporary IDs on `insert()`. These are invalid for futures, deduplication, and background tasks. `save()` converts them to permanent IDs.

---

### Rule #2: Insert Before Relate

```swift
// ❌ CRASH: Setting relationship before insert
let work = Work(title: "...", authors: [author])
modelContext.insert(work)

// ✅ CORRECT: Insert both, THEN relate
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]  // After both inserted
```

**Why:** SwiftData requires both objects to be inserted before setting relationships.

---

### Rule #3: Use @Bindable in Child Views

```swift
// ❌ WRONG: View won't update
struct BookDetailView: View {
    let work: Work  // Not reactive!
    var body: some View {
        Text(work.title)
    }
}

// ✅ CORRECT: Reactive updates
struct BookDetailView: View {
    @Bindable var work: Work  // Observes changes!
    var body: some View {
        Text(work.title)
    }
}
```

**Why:** SwiftData relies on `@Bindable` for observation in child views. Without it, UI won't update when model changes.

---

## 🏗️ Model Definition

### Basic Model

```swift
import SwiftData

@Model
public class Work {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    public var genres: [String] = []
    public var originalPublicationYear: Int?

    public init(title: String) {
        self.id = UUID()
        self.title = title
    }
}
```

**Key Points:**
- `@Model` macro required
- All properties need defaults (CloudKit requirement)
- `@Attribute(.unique)` for unique constraints
- Optionals allowed for nullable fields

---

### Relationships

**One-to-Many:**
```swift
@Model
public class Work {
    public var editions: [Edition]? = []  // One-to-many

    // Inverse relationship declared on Edition (to-many side)
}

@Model
public class Edition {
    public var work: Work?  // Many-to-one
    @Relationship(deleteRule: .nullify, inverse: \Edition.work)
}
```

**Many-to-Many:**
```swift
@Model
public class Work {
    public var authors: [Author]? = []  // Many-to-many

    // Inverse relationship declared on Author (to-many side)
}

@Model
public class Author {
    public var works: [Work]? = []  // Many-to-many
    @Relationship(deleteRule: .nullify, inverse: \Work.authors)
}
```

**CloudKit Sync Rules:**
- ✅ Inverse relationships ONLY on to-many side
- ✅ All relationships optional (`?`)
- ✅ Delete rules: `.nullify` (default), `.cascade`, `.deny`
- ❌ Can't declare inverse on both sides (CloudKit limitation)

---

## 🔍 Querying Data

### @Query Property Wrapper

```swift
struct LibraryView: View {
    @Query(sort: \Work.title) var works: [Work]

    // Or with filter:
    @Query(filter: #Predicate<Work> { work in
        work.genres.contains("Science Fiction")
    }) var scifiWorks: [Work]
}
```

---

### FetchDescriptor (Programmatic Queries)

```swift
// Basic fetch
let descriptor = FetchDescriptor<Work>(
    sortBy: [SortDescriptor(\Work.title)]
)
let works = try modelContext.fetch(descriptor)

// With predicate
let descriptor = FetchDescriptor<Work>(
    predicate: #Predicate { $0.originalPublicationYear == 1984 },
    sortBy: [SortDescriptor(\Work.title)]
)
let works = try modelContext.fetch(descriptor)

// Limit + offset
var descriptor = FetchDescriptor<Work>()
descriptor.fetchLimit = 20
descriptor.fetchOffset = 40  // Page 3 (20/page)
let works = try modelContext.fetch(descriptor)
```

---

### Predicate Syntax

```swift
// Equality
#Predicate<Work> { $0.title == "1984" }

// Comparison
#Predicate<Work> { $0.originalPublicationYear > 2000 }

// String contains (case-sensitive!)
#Predicate<Work> { $0.title.contains("Science") }

// String localizedStandardContains (case-insensitive)
#Predicate<Work> { $0.title.localizedStandardContains("science") }

// Array contains
#Predicate<Work> { $0.genres.contains("Fantasy") }

// Multiple conditions (AND)
#Predicate<Work> {
    $0.originalPublicationYear > 2000 &&
    $0.genres.contains("Science Fiction")
}

// Optional unwrapping
#Predicate<UserLibraryEntry> {
    $0.personalRating != nil && $0.personalRating! >= 4
}
```

**Limitations:**
- ❌ Can't filter on to-many relationships (filter in-memory instead)
- ❌ Can't use complex Swift functions (database-level only)
- ❌ Case-sensitive by default (use `localizedStandardContains` for case-insensitive)

---

## ⚡ Performance Patterns

### Use fetchCount() for Counts

```swift
// ✅ FAST: Database-level count (0.5ms for 1000 books)
let count = try modelContext.fetchCount(FetchDescriptor<Work>())

// ❌ SLOW: Load all objects (50ms for 1000 books - 100x slower!)
let works = try modelContext.fetch(FetchDescriptor<Work>())
let count = works.count
```

---

### Filter at Database Level

```swift
// ✅ FAST: Predicate filtering (database-level)
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.status == .reading }
)
let reading = try modelContext.fetch(descriptor)

// ❌ SLOW: In-memory filtering (loads all objects first)
let all = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let reading = all.filter { $0.status == .reading }
```

**Exception:** To-many relationships can't use predicates (CloudKit limitation). Filter in-memory for those:
```swift
// ✅ CORRECT: Filter to-many relationships in-memory
let works = try modelContext.fetch(FetchDescriptor<Work>())
let withLibraryEntries = works.filter { !($0.userLibraryEntries ?? []).isEmpty }
```

---

### Batch Inserts

```swift
// ✅ CORRECT: Insert all, THEN save once
for dto in dtos {
    let work = Work(title: dto.title)
    modelContext.insert(work)
}
try modelContext.save()  // One save for all

// ❌ SLOW: Save after each insert (N saves!)
for dto in dtos {
    let work = Work(title: dto.title)
    modelContext.insert(work)
    try modelContext.save()  // ❌ Expensive!
}
```

---

## 🎨 SwiftUI Integration

### Property Wrappers

| Wrapper | Use Case |
|---------|----------|
| `@Query` | Fetch data (replaces `@FetchRequest`) |
| `@Bindable` | SwiftData models in child views (reactive) |
| `@Environment(\.modelContext)` | Access ModelContext for inserts/saves |

---

### Passing Models to Child Views

```swift
struct ParentView: View {
    @Query var works: [Work]

    var body: some View {
        List(works) { work in
            NavigationLink(value: work) {
                Text(work.title)
            }
        }
        .navigationDestination(for: Work.self) { work in
            WorkDetailView(work: work)  // Pass Work
        }
    }
}

struct WorkDetailView: View {
    @Bindable var work: Work  // ← @Bindable for reactive updates!

    var body: some View {
        Form {
            TextField("Title", text: $work.title)  // Two-way binding
            Text("Rating: \(work.userLibraryEntries?.first?.personalRating ?? 0)")
        }
    }
}
```

---

## 🔄 CRUD Operations

### Create

```swift
let work = Work(title: "1984")
modelContext.insert(work)
try modelContext.save()
```

---

### Read

```swift
// Fetch all
let works = try modelContext.fetch(FetchDescriptor<Work>())

// Fetch one by ID
let id = UUID(...)  // Known UUID
let works = try modelContext.fetch(FetchDescriptor<Work>(
    predicate: #Predicate { $0.id == id }
))
guard let work = works.first else { throw NotFoundError() }
```

---

### Update

```swift
// Option 1: Direct property update
work.title = "Nineteen Eighty-Four"
try modelContext.save()

// Option 2: Fetch, update, save
let works = try modelContext.fetch(FetchDescriptor<Work>(
    predicate: #Predicate { $0.title == "1984" }
))
if let work = works.first {
    work.title = "Nineteen Eighty-Four"
    try modelContext.save()
}
```

---

### Delete

```swift
modelContext.delete(work)
try modelContext.save()

// Cascade delete (if relationship has .cascade rule)
modelContext.delete(work)  // Also deletes all editions (if .cascade)
try modelContext.save()
```

---

## 🔗 Working with Relationships

### Setting Relationships

```swift
// Many-to-one (Edition → Work)
let work = Work(title: "1984")
modelContext.insert(work)

let edition = Edition(isbn13: "9780451524935")
modelContext.insert(edition)

edition.work = work  // Set relationship after both inserted
try modelContext.save()

// Many-to-many (Work ↔ Author)
let author = Author(name: "George Orwell")
modelContext.insert(author)

let work = Work(title: "1984", authors: [])
modelContext.insert(work)

work.authors = [author]  // Set relationship after both inserted
try modelContext.save()
```

---

### Accessing Relationships

```swift
// Optional unwrapping (relationships are optional)
if let editions = work.editions {
    print("Found \(editions.count) editions")
}

// Nil-coalescing
let editions = work.editions ?? []
print("Found \(editions.count) editions")

// Guard let
guard let editions = work.editions, !editions.isEmpty else {
    print("No editions found")
    return
}
```

---

## 🧹 Cleanup & Maintenance

### Clear All Data

```swift
// Delete all instances of a model
let works = try modelContext.fetch(FetchDescriptor<Work>())
for work in works {
    modelContext.delete(work)
}
try modelContext.save()

// Or use custom reset method
LibraryRepository(modelContext: modelContext).resetLibrary()
```

---

### Orphan Cleanup

```swift
// Find orphaned editions (no Work relationship)
let editions = try modelContext.fetch(FetchDescriptor<Edition>())
let orphanedEditions = editions.filter { $0.work == nil }

// Delete orphans
for edition in orphanedEditions {
    modelContext.delete(edition)
}
try modelContext.save()
```

---

## 🔐 CloudKit Sync (Optional)

### Enable Sync

```swift
// In App shell
let container = try ModelContainer(
    for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
    configurations: ModelConfiguration(cloudKitDatabase: .private("iCloud.com.oooefam.booksV3"))
)
```

**Sync Rules:**
- ✅ User must be signed in to iCloud
- ✅ All attributes need defaults (CloudKit requirement)
- ✅ All relationships optional (CloudKit requirement)
- ✅ Inverse relationships on to-many side only
- ✅ Sync happens automatically (no manual code)

---

## 📚 Common Patterns

### Deduplication

```swift
// Check if Work already exists by ISBN
let existingWorks = try modelContext.fetch(FetchDescriptor<Work>(
    predicate: #Predicate { work in
        work.editions?.contains { $0.isbn13 == isbn } ?? false
    }
))

if let existing = existingWorks.first {
    print("Work already exists: \(existing.title)")
} else {
    // Create new Work
    let work = Work(title: "...")
    modelContext.insert(work)
    try modelContext.save()
}
```

---

### Cascade Deletes

```swift
// Define cascade relationship
@Model
public class Work {
    @Relationship(deleteRule: .cascade, inverse: \Edition.work)
    public var editions: [Edition]? = []
}

// Delete Work → All Editions deleted automatically
modelContext.delete(work)
try modelContext.save()  // Editions gone too!
```

---

## 🐛 Common Issues

### Issue: "Temporary identifier" crash
**Cause:** Using `persistentModelID` before `save()`
**Fix:** Always `save()` before using IDs

---

### Issue: View doesn't update when model changes
**Cause:** Missing `@Bindable` in child view
**Fix:** Add `@Bindable var model: Model` (not `let`)

---

### Issue: Relationship crash "object not inserted"
**Cause:** Setting relationship before inserting models
**Fix:** Insert both, THEN set relationships

---

### Issue: Predicate doesn't filter to-many relationships
**Cause:** CloudKit limitation (can't query to-many)
**Fix:** Filter in-memory after fetching

---

**Keep this reference handy! Refer to it when working with SwiftData.**
