# BooksTracker V3 Data Models 📊

Clean Work/Edition architecture with proper normalization and user intent modeling.

**Note on File Location:**
Core model files are located in `BooksTrackerPackage/Sources/BooksTrackerFeature/` for historical reasons, while newer models reside in `Models/`.
- `Work.swift`
- `Edition.swift`
- `Author.swift`
- `UserLibraryEntry.swift`

## Core Entities

### Work 📖
**Represents the conceptual book** - the intellectual creation independent of specific publications.

```swift
@Model
final class Work {
    var title: String
    var authors: [Author]          // ✅ Normalized relationship (not string)
    var originalLanguage: String?
    var firstPublicationYear: Int?
    var subjectTags: [String]

    // Relationships
    @Relationship(deleteRule: .cascade)
    var editions: [Edition]        // One-to-many

    @Relationship(deleteRule: .cascade)
    var userLibraryEntries: [UserLibraryEntry] // One-to-many
}
```

**Key Benefits:**
- Single search result per work (no duplicate "Huckleberry Finn" entries)
- Proper author normalization enables complex queries
- Cultural data derived from author relationships

### Edition 📚
**Represents a specific published version** of a work with physical/digital characteristics.

```swift
@Model
final class Edition {
    var isbn: String?
    var publisher: String?
    var publicationDate: String?
    var pageCount: Int?
    var format: BookFormat        // .physical, .ebook, .audiobook
    var coverImageURL: String?
    var editionTitle: String?     // "Deluxe Edition", "Abridged"

    // Relationship
    var work: Work?               // Many-to-one
}
```

**Key Benefits:**
- Multiple editions per work (hardcover, paperback, ebook)
- ISBN-specific metadata for precise tracking
- Edition-specific features (page count, cover art)

### UserLibraryEntry 👤
**Represents user's relationship** to a Work/Edition with proper ownership semantics.

```swift
@Model
final class UserLibraryEntry {
    var work: Work?               // Always present
    var edition: Edition?         // Nil for wishlist items
    var readingStatus: ReadingStatus
    var currentPage: Int
    var rating: Int?
    var notes: String?

    // Reading tracking
    var dateStarted: Date?
    var dateCompleted: Date?
}
```

**Status Logic:**
- **Wishlist**: "Want to have/read but don't own" → `edition = nil`
- **To Read**: "Have it and want to read" → `edition != nil`
- **Reading**: Currently reading owned edition
- **Read**: Finished reading owned edition
- **On Hold**: Paused reading owned edition
- **DNF**: Did not finish owned edition

### Author 👨‍💼
**Normalized author entity** with cultural diversity tracking.

```swift
@Model
final class Author {
    var name: String
    var nationality: String?
    var gender: AuthorGender
    var culturalRegion: CulturalRegion?
    var birthYear: Int?
    var deathYear: Int?

    // Relationship
    var works: [Work]             // Many-to-many
}
```

**Key Benefits:**
- No duplicate author data across works
- Enables "find all books by author" queries
- Cultural analytics across entire catalog

## Relationship Summary

```
Author ←→ Work → Edition
   ↑        ↓
   └── UserLibraryEntry
```

### Relationship Rules

1. **Author ←→ Work**: Many-to-many (co-authors, multiple works)
2. **Work → Edition**: One-to-many (multiple publications)
3. **Work → UserLibraryEntry**: One-to-many (multiple users, status changes)
4. **Edition → UserLibraryEntry**: Many-to-one (user owns specific edition)

### "Insert-Before-Relate" Pattern
**Crucial:** Parent objects (Work, Edition) must be inserted into the ModelContext *before* being assigned to relationships on a new child object.

## Migration from Legacy

### V3 Benefits
- ✅ Clean 4-model architecture
- ✅ Proper database normalization
- ✅ SwiftData-optimized relationships
- ✅ Clear user intent modeling (wishlist vs owned)
- ✅ Scalable foundation for V3+ features

This architecture directly implements the V3 specification requirements for Work/Edition separation and proper user-book relationship tracking.
