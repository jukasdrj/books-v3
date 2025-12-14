# Swift 6 Concurrency Rules (v2.0.64)

These rules are automatically loaded for Swift concurrency-related code.

## Zero Warnings Policy

BooksTrack enforces zero warnings with `-Werror`. All concurrency issues MUST be resolved.

## Required Patterns

### Observable Classes
```swift
// REQUIRED: @MainActor for all Observable classes
@MainActor
class SearchModel: Observable {
    var state: SearchViewState = .initial
}
```

### SwiftData in Child Views
```swift
// REQUIRED: @Bindable for SwiftData models in child views
struct BookDetailView: View {
    @Bindable var work: Work  // NOT @Binding or plain var
}
```

### SwiftData Relationships
```swift
// REQUIRED: Insert before relate, save before using persistentModelID
let work = Work(title: "...")
modelContext.insert(work)       // INSERT FIRST
work.authors = [author]         // SET RELATIONSHIP AFTER
try modelContext.save()         // SAVE BEFORE using persistentModelID
```

### Actors (No Timer.publish)
```swift
// FORBIDDEN in actors:
Timer.publish(every: 1.0, on: .main, in: .common)

// USE INSTEAD:
Task {
    try await Task.sleep(for: .seconds(1))
}
```

## Auto-Validation

When reviewing Swift code, verify:
- [ ] All Observable classes have @MainActor
- [ ] SwiftData models use @Bindable in child views
- [ ] No Timer.publish in actors
- [ ] Insert before relate pattern followed
- [ ] Nested supporting types (not top-level)
