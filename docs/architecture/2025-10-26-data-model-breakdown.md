# BooksTrack Data Model Architecture

**Date:** 2025-10-26
**Status:** Active
**Models:** Work, Edition, Author, UserLibraryEntry

## Overview

BooksTrack uses four SwiftData models that work together to separate the abstract concept of a book from its physical manifestations and your personal tracking data. This separation enables wishlist functionality, multi-edition support, and cultural diversity insights.

## Model Breakdown

### 1. Work - The Abstract Book Concept

Represents the conceptual book (e.g., "The Great Gatsby" as an idea).

**Core Properties:**
- `title: String` - Book title
- `originalLanguage: String?` - Original publication language
- `firstPublicationYear: Int?` - When first published
- `subjectTags: [String]` - Genre/topic tags

**External API Identifiers:**
- `openLibraryWorkID: String?` - OpenLibrary Work ID
- `isbndbID: String?` - ISBNDB identifier
- `googleBooksVolumeID: String?` - Google Books ID (legacy single)
- `goodreadsWorkIDs: [String]` - Multiple Goodreads Work IDs
- `amazonASINs: [String]` - Amazon identifiers
- `librarythingIDs: [String]` - LibraryThing IDs
- `googleBooksVolumeIDs: [String]` - Google Books IDs (array)

**AI Review Queue Properties:**
- `reviewStatus: ReviewStatus` - Verified/pending (.verified default)
- `originalImagePath: String?` - Temp storage of bookshelf scan
- `boundingBoxX/Y/Width/Height: Double?` - Spine cropping coordinates
- `boundingBox: CGRect?` - Computed property for bounding box

**Metadata:**
- `dateCreated: Date`
- `lastModified: Date`
- `lastISBNDBSync: Date?` - Cache optimization
- `isbndbQuality: Int` - Data quality score (0-100)

**Relationships:**
- `authors: [Author]?` - Many-to-many, nullify on delete
- `editions: [Edition]?` - One-to-many, cascade delete
- `userLibraryEntries: [UserLibraryEntry]?` - One-to-many, cascade delete

**Key Methods:**
- `primaryAuthor` - First author in list
- `authorNames` - Formatted string of all authors
- `culturalRegion` - From primary author
- `isInLibrary` / `isOwned` / `isOnWishlist` - Ownership checks
- `addAuthor()` / `removeAuthor()` - Relationship management
- `mergeExternalIDs()` - Sync API identifiers

---

### 2. Edition - Specific Published Versions

Represents a specific publication (e.g., "The Great Gatsby - 2004 Scribner hardcover").

**Core Properties:**
- `isbn: String?` - Primary ISBN (backward compatibility)
- `isbns: [String]` - All ISBNs (ISBN-10, ISBN-13, etc.)
- `publisher: String?` - Publishing house
- `publicationDate: String?` - Publication date
- `pageCount: Int?` - Number of pages
- `format: EditionFormat` - Physical format (enum)
- `coverImageURL: String?` - Cover image URL
- `editionTitle: String?` - Special edition info

**External API Identifiers:**
- `openLibraryEditionID: String?` - OpenLibrary Edition ID
- `isbndbID: String?` - ISBNDB edition identifier
- `googleBooksVolumeID: String?` - Google Books ID (legacy single)
- `amazonASINs: [String]` - Amazon ASINs for this edition
- `googleBooksVolumeIDs: [String]` - Google Books IDs (array)
- `librarythingIDs: [String]` - LibraryThing edition IDs

**Metadata:**
- `dateCreated: Date`
- `lastModified: Date`
- `lastISBNDBSync: Date?`
- `isbndbQuality: Int`

**Relationships:**
- `work: Work?` - Many-to-one (inverse at Work.swift:78)
- `userLibraryEntries: [UserLibraryEntry]?` - One-to-many, nullify on delete

**Key Methods:**
- `primaryISBN` - Returns best ISBN (prefers ISBN-13 > ISBN-10 > any)
- `addISBN()` / `removeISBN()` - ISBN collection management
- `hasISBN()` - Check for specific ISBN
- `displayTitle` - Work title + edition info
- `coverURL` - Computed URL from string
- `mergeExternalIDs()` - Sync API identifiers

**Supporting Enum - EditionFormat:**
- hardcover, paperback, ebook, audiobook, massMarket
- Includes icon, displayName, shortName properties

---

### 3. Author - Book Creators

Represents people who write books, with cultural diversity tracking.

**Core Properties:**
- `name: String` - Author's full name
- `nationality: String?` - Country/nationality
- `gender: AuthorGender` - Gender identity enum
- `culturalRegion: CulturalRegion?` - Geographic/cultural region enum
- `birthYear: Int?` - Birth year
- `deathYear: Int?` - Death year (if deceased)

**External API Identifiers:**
- `openLibraryID: String?` - OpenLibrary author ID
- `isbndbID: String?` - ISBNDB author ID
- `googleBooksID: String?` - Google Books author ID
- `goodreadsID: String?` - Goodreads author ID

**Metadata:**
- `dateCreated: Date`
- `lastModified: Date`
- `bookCount: Int` - Cached count of works

**Relationships:**
- `works: [Work]?` - Many-to-many, nullify on delete (inverse at Work.swift:74)

**Key Methods:**
- `displayName` - Name with birth/death years
- `representsMarginalizedVoices()` - Non-male OR underrepresented regions
- `representsIndigenousVoices()` - Indigenous-specific check
- `updateStatistics()` - Refresh book count

**Supporting Enums:**

**AuthorGender:**
- female, male, nonBinary, other, unknown
- Includes icon and displayName properties

**CulturalRegion (11 regions):**
- africa, asia, europe, northAmerica, southAmerica, oceania
- middleEast, caribbean, centralAsia, indigenous, international
- Includes displayName, shortName, emoji, icon properties

---

### 4. UserLibraryEntry - Personal Reading Tracking

Your personal data connecting you to books and tracking reading progress.

**Core Properties:**
- `dateAdded: Date` - When added to library
- `readingStatus: ReadingStatus` - Current status enum
- `currentPage: Int` - Current page number
- `readingProgress: Double` - Progress as decimal (0.0-1.0)
- `rating: Int?` - Star rating (1-5)
- `personalRating: Double?` - Granular rating (0.0-5.0)
- `notes: String?` - Personal notes (max 2000 chars)
- `tags: [String]` - Custom tags

**Reading Tracking:**
- `dateStarted: Date?` - When started reading
- `dateCompleted: Date?` - When finished
- `estimatedFinishDate: Date?` - Calculated prediction

**Metadata:**
- `lastModified: Date`

**Relationships:**
- `work: Work?` - Many-to-one (inverse at Work.swift:80)
- `edition: Edition?` - Many-to-one (inverse at Edition.swift:43), nil for wishlist

**Key Concepts:**
- **Wishlist**: `readingStatus = .wishlist` AND `edition = nil`
- **Owned**: `edition != nil`

**Key Methods:**
- `updateReadingProgress()` - Auto-calc from page/pageCount, auto-complete at 100%
- `markAsCompleted()` - Sets read status, fills dates
- `startReading()` - Transitions toRead → reading
- `acquireEdition()` - Converts wishlist → owned
- `readingPace` - Calculates pages/day
- `calculateEstimatedFinishDate()` - Predicts finish date

**Supporting Enum - ReadingStatus:**
- **wishlist** - Want to have/read but don't own
- **toRead** - Own it, plan to read (TBR)
- **reading** - Currently reading
- **read** - Finished
- **onHold** - Paused
- **dnf** - Did not finish

Each includes displayName, description, systemImage, color properties.

**CSV Import Support:**
- `ReadingStatus.from(string:)` - Parses Goodreads/LibraryThing/StoryGraph formats
- Handles variants like "want to read", "currently reading", "to-be-read"

---

## Relationship Architecture

### Hierarchy Overview

```
Work (abstract concept)
  ↓ one-to-many
Edition (specific versions)
  ↓ selected by
UserLibraryEntry (tracking data)

Work ←→ Author (many-to-many)
```

### Detailed Relationships

**1. Work → Edition (One-to-Many, Cascade Delete)**
- Work.editions → [Edition] (Work.swift:78)
- Edition.work → Work (Edition.swift:39)
- Deleting Work deletes all Editions
- Example: "The Great Gatsby" has 50+ edition records

**2. Work → UserLibraryEntry (One-to-Many, Cascade Delete)**
- Work.userLibraryEntries → [UserLibraryEntry] (Work.swift:80)
- UserLibraryEntry.work → Work (UserLibraryEntry.swift:25)
- Deleting Work deletes tracking data
- Constraint: One entry per Work per user

**3. Edition → UserLibraryEntry (One-to-Many, Nullify)**
- Edition.userLibraryEntries → [UserLibraryEntry] (Edition.swift:43)
- UserLibraryEntry.edition → Edition (UserLibraryEntry.swift:29)
- Deleting Edition nullifies entry's edition (becomes wishlist-like)
- Example: Edition removed → progress preserved, edition = nil

**4. Work ←→ Author (Many-to-Many, Nullify)**
- Work.authors → [Author] (Work.swift:74)
- Author.works → [Work] (Author.swift:29-30)
- Deleting either doesn't delete the other
- Example: "Good Omens" has 2 authors, each has multiple works

### CloudKit Constraints

- All relationships are optional (nullable)
- Inverse relationships declared on "to-many" side only
- All properties require default values
- Predicates cannot filter on to-many relationships (filter in-memory)

---

## Data Flow Examples

### Adding a Book

1. **Search** returns book data
2. **Create/find Work** and **Author(s)**
3. **Link Work ←→ Author** (many-to-many)
4. **Create Edition** records for each version
5. **Link Edition → Work** (one-to-many)
6. **User adds to wishlist** → Create UserLibraryEntry with work, no edition
7. **User acquires book** → Call `entry.acquireEdition(specificEdition)`

### Reading Progress Flow

1. User starts reading → `entry.startReading()` (status: toRead → reading)
2. User updates page → `entry.currentPage = 150; entry.updateReadingProgress()`
3. Progress auto-calculates → `readingProgress = 150 / pageCount`
4. At 100% → Auto-calls `markAsCompleted()` (status → read, sets dates)

### Wishlist → Owned Transition

1. Add to wishlist: `UserLibraryEntry.createWishlistEntry(for: work)`
   - work = Work object
   - edition = nil
   - readingStatus = .wishlist
2. Acquire physical copy: `entry.acquireEdition(specificEdition, status: .toRead)`
   - edition = Edition object
   - readingStatus = .toRead
   - dateAdded unchanged (preserves history)

---

## Special Features

### External ID Management

**Purpose:** Enable deduplication and cross-platform enrichment.

**Pattern (all models):**
- `mergeExternalIDs(from:)` - Merges API response data
- `externalIDsDictionary` - Exports IDs for API calls
- Individual `add*ID()` methods prevent duplicates and call `touch()`

**Storage Strategy:**
- **Work**: Arrays for Goodreads, Amazon, LibraryThing, Google Books IDs
- **Edition**: Arrays for Amazon, Google Books, LibraryThing IDs
- **Author**: Single IDs for each platform (OpenLibrary, ISBNDB, Google, Goodreads)

### AI Bookshelf Scanning Integration

Work model supports Review Queue feature:
- `reviewStatus: ReviewStatus` - Verified vs pending review
- `originalImagePath: String?` - Temp file path to bookshelf scan
- `boundingBoxX/Y/Width/Height: Double?` - Coordinates for spine crop
- `boundingBox: CGRect?` - Computed property combining components

Enables human-in-the-loop correction for low-confidence AI detections.

### Progress Tracking Intelligence

UserLibraryEntry auto-calculates:
- **Reading pace**: Pages/day from `dateStarted` and `currentPage`
- **Estimated finish**: Uses pace + remaining pages
- **Auto-completion**: `updateReadingProgress()` marks as read at 100%

### Cache Optimization

Both Work and Edition track:
- `lastISBNDBSync: Date?` - Prevents redundant API calls
- `isbndbQuality: Int` - Quality score (0-100) prioritizes enrichment

### Audit Trail

Every model maintains:
- `dateCreated: Date` - Immutable
- `lastModified: Date` - Updated via `touch()` on any change
- Relationship changes trigger `touch()` (e.g., adding author updates Work)

---

## Design Patterns

### Touch Pattern

All models implement `touch()`:
```swift
func touch() {
    lastModified = Date()
}
```

Called automatically by:
- Property setters (manual call)
- Relationship management methods
- External ID merge operations

### Optional Relationship Pattern

CloudKit requires optional relationships:
```swift
@Relationship(deleteRule: .cascade, inverse: \Edition.work)
var editions: [Edition]?  // Optional array
```

Always use safe unwrapping:
```swift
guard let editions = work.editions else { return [] }
```

### Computed Property Pattern

Avoid storing CGRect directly (SwiftData encoding issues):
```swift
// Store as primitives
var boundingBoxX: Double?
var boundingBoxY: Double?
var boundingBoxWidth: Double?
var boundingBoxHeight: Double?

// Compute as needed
var boundingBox: CGRect? {
    get { /* construct from primitives */ }
    set { /* decompose to primitives */ }
}
```

### Array-Based External IDs

Modern pattern for flexible cross-referencing:
```swift
// OLD: Single ID (backward compatibility)
var goodreadsID: String?

// NEW: Multiple IDs (current standard)
var goodreadsWorkIDs: [String] = []

func addGoodreadsWorkID(_ id: String) {
    guard !id.isEmpty && !goodreadsWorkIDs.contains(id) else { return }
    goodreadsWorkIDs.append(id)
    touch()
}
```

---

## Key Invariants

1. **One UserLibraryEntry per Work per user** - Enforced by app logic
2. **Wishlist items have nil edition** - `readingStatus = .wishlist AND edition = nil`
3. **Owned items have non-nil edition** - `edition != nil`
4. **All relationships are optional** - CloudKit constraint
5. **Inverse on to-many side only** - CloudKit constraint
6. **Cascade deletes for owned data** - Work owns Editions and UserLibraryEntries
7. **Nullify deletes for shared data** - Authors and Works are independent
8. **Touch on all mutations** - Maintains lastModified accuracy

---

## File Locations

- `BooksTrackerPackage/Sources/BooksTrackerFeature/Work.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Edition.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Author.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/ModelTypes.swift` (enums)

---

## Related Documentation

- **CLAUDE.md** - Quick reference for active development
- **docs/features/CSV_IMPORT.md** - CSV import with ReadingStatus parsing
- **docs/features/BOOKSHELF_SCANNER.md** - AI review queue integration
- **docs/features/REVIEW_QUEUE.md** - Human-in-the-loop corrections
- **docs/workflows/** - Mermaid diagrams for visual flows
