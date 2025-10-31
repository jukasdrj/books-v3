# Canonical Data Contracts Workflow

**Feature:** TypeScript-First API Contracts (v1.0.0)
**Last Updated:** October 31, 2025
**Related PRD:** [Canonical Data Contracts PRD](../product/Canonical-Data-Contracts-PRD.md)

---

## Overview

This workflow shows how backend normalizes provider-specific data into canonical DTOs and how iOS consumes them consistently, regardless of data provider.

---

## Happy Path: Title Search with Genre Normalization

```mermaid
sequenceDiagram
    actor User
    participant iOS as iOS SearchView
    participant APIService as BookSearchAPIService
    participant V1Handler as /v1/search/title
    participant GoogleBooks as Google Books API
    participant GenreNorm as Genre Normalizer
    participant Normalizer as normalizeGoogleBooksToWork
    participant DTOMapper
    participant SwiftData

    User->>iOS: Search "The Great Gatsby"
    iOS->>APIService: searchByTitle("The Great Gatsby")
    APIService->>V1Handler: GET /v1/search/title?q=The+Great+Gatsby

    V1Handler->>GoogleBooks: GET /books/v1/volumes?q=The+Great+Gatsby
    GoogleBooks-->>V1Handler: Raw JSON:<br/>{<br/>  volumeInfo: {<br/>    title: "The Great Gatsby",<br/>    categories: ["Fiction", "Thrillers", "MYSTERY"],<br/>    ...<br/>  }<br/>}

    Note over V1Handler: Normalize provider data to canonical DTOs

    V1Handler->>Normalizer: normalizeGoogleBooksToWork(volumeInfo)
    Normalizer->>GenreNorm: normalizeGenres(["Fiction", "Thrillers", "MYSTERY"])
    GenreNorm->>GenreNorm: Apply rules:<br/>- Lowercase matching<br/>- Depluralize (Thrillers → Thriller)<br/>- Canonical map (MYSTERY → Mystery)
    GenreNorm-->>Normalizer: ["Fiction", "Thriller", "Mystery"]

    Normalizer-->>V1Handler: WorkDTO {<br/>  title: "The Great Gatsby",<br/>  subjectTags: ["Fiction", "Thriller", "Mystery"],<br/>  synthetic: true,<br/>  primaryProvider: "google-books"<br/>}

    V1Handler->>V1Handler: Wrap in ResponseEnvelope
    V1Handler-->>APIService: ResponseEnvelope {<br/>  success: true,<br/>  data: { works: [...], editions: [...] },<br/>  meta: { provider: "google-books", cached: false }<br/>}

    APIService->>DTOMapper: mapToWorks(data, modelContext)
    DTOMapper->>SwiftData: Create Work models
    DTOMapper->>DTOMapper: Apply genres (already normalized)
    DTOMapper->>DTOMapper: Deduplicate synthetic works
    DTOMapper-->>iOS: Work[]

    iOS-->>User: Show search results with normalized genres
```

**Key Points:**
- **Backend normalization:** Genres normalized BEFORE iOS receives data
- **Zero iOS logic:** DTOMapper applies genres directly (no normalization code)
- **Synthetic flag:** Google Books volumes marked `synthetic: true` for deduplication
- **Provenance:** `primaryProvider: "google-books"` tracks data source

---

## ISBN Search with Deduplication

```mermaid
sequenceDiagram
    actor User
    participant iOS
    participant V1ISBN as /v1/search/isbn
    participant GoogleBooks
    participant Normalizer
    participant DTOMapper
    participant SwiftData

    User->>iOS: Scan ISBN: 978-0-12345-678-9
    iOS->>V1ISBN: GET /v1/search/isbn?isbn=978-0-12345-678-9

    V1ISBN->>V1ISBN: Validate ISBN format (checksum)
    V1ISBN->>GoogleBooks: GET /books/v1/volumes?q=isbn:978-0-12345-678-9

    Note over GoogleBooks: Returns 5 editions (volumes) of same book

    GoogleBooks-->>V1ISBN: 5 volumes (different publishers, years)

    V1ISBN->>Normalizer: Loop: normalizeGoogleBooksToWork(each volume)
    Normalizer-->>V1ISBN: 5 WorkDTOs (all synthetic: true, same ISBN)

    V1ISBN-->>iOS: ResponseEnvelope {<br/>  works: [work1, work2, work3, work4, work5],<br/>  editions: [ed1, ed2, ed3, ed4, ed5]<br/>}

    iOS->>DTOMapper: mapToWorks(data, modelContext)
    DTOMapper->>DTOMapper: Detect synthetic works (all have synthetic: true)
    DTOMapper->>DTOMapper: Group by ISBN: 978-0-12345-678-9
    DTOMapper->>SwiftData: Create 1 Work with 5 editions
    DTOMapper-->>iOS: [Work] (1 work, not 5)

    iOS-->>User: Show "The Great Gatsby" (1 work) with edition picker (5 editions)
```

**Key Points:**
- **Synthetic flag:** Signals iOS to deduplicate (group by ISBN)
- **Edition preservation:** All 5 editions preserved under single Work
- **User experience:** Library shows 1 book, edition picker shows 5 options

---

## Advanced Search (Title + Author)

```mermaid
sequenceDiagram
    actor User
    participant iOS
    participant V1Advanced as /v1/search/advanced
    participant GoogleBooks
    participant Normalizer
    participant DTOMapper

    User->>iOS: Search: title="1984", author="Orwell"
    iOS->>V1Advanced: GET /v1/search/advanced?title=1984&author=Orwell

    V1Advanced->>GoogleBooks: GET /books/v1/volumes?q=intitle:1984+inauthor:Orwell
    GoogleBooks-->>V1Advanced: Volumes matching both criteria

    V1Advanced->>Normalizer: normalizeGoogleBooksToWork(volumeInfo)
    Normalizer->>Normalizer: Extract authors from volumeInfo.authors
    Normalizer->>Normalizer: Create AuthorDTOs
    Normalizer-->>V1Advanced: WorkDTO + EditionDTO + AuthorDTO[]

    V1Advanced-->>iOS: ResponseEnvelope {<br/>  works: [work],<br/>  editions: [edition],<br/>  authors: [{ name: "George Orwell", gender: "male" }]<br/>}

    iOS->>DTOMapper: mapToWorks(data, modelContext)
    DTOMapper->>DTOMapper: Create Work, Edition, Author models
    DTOMapper->>DTOMapper: Set relationships (work.authors = [author])
    DTOMapper-->>iOS: Work[]

    iOS-->>User: Show "1984" by George Orwell
```

**Key Points:**
- **Combined query:** Backend merges title + author filters
- **Author normalization:** AuthorDTO includes gender, cultural region (if available)
- **Relationships:** DTOMapper sets work ↔ author relationships

---

## Error Path: Invalid ISBN

```mermaid
sequenceDiagram
    actor User
    participant iOS
    participant V1ISBN as /v1/search/isbn
    participant ISBNValidator

    User->>iOS: Scan barcode: "123456" (invalid)
    iOS->>V1ISBN: GET /v1/search/isbn?isbn=123456

    V1ISBN->>ISBNValidator: validate("123456")
    ISBNValidator->>ISBNValidator: Check format: Not 10 or 13 digits
    ISBNValidator-->>V1ISBN: Invalid ISBN

    V1ISBN-->>iOS: ResponseEnvelope {<br/>  success: false,<br/>  error: {<br/>    code: "INVALID_ISBN",<br/>    message: "Invalid ISBN format",<br/>    details: { isbn: "123456" }<br/>  },<br/>  meta: { provider: "validation" }<br/>}

    iOS->>iOS: Parse error response
    iOS-->>User: Show error: "Invalid ISBN. Please try again."
```

**Key Points:**
- **Structured errors:** Error code (`INVALID_ISBN`) + message + details
- **User-friendly:** iOS translates error code to user message
- **No crash:** iOS handles error response gracefully

---

## Error Path: Provider Failure (Google Books Timeout)

```mermaid
sequenceDiagram
    actor User
    participant iOS
    participant V1Title as /v1/search/title
    participant GoogleBooks
    participant KVCache

    User->>iOS: Search "Rare Book Title"
    iOS->>V1Title: GET /v1/search/title?q=Rare+Book+Title

    V1Title->>KVCache: Check cache: "search:title:rare-book-title"
    KVCache-->>V1Title: Cache miss

    V1Title->>GoogleBooks: GET /books/v1/volumes?q=Rare+Book+Title
    Note over GoogleBooks: Request timeout (10s)
    GoogleBooks--xV1Title: Timeout error

    V1Title-->>iOS: ResponseEnvelope {<br/>  success: false,<br/>  error: {<br/>    code: "PROVIDER_ERROR",<br/>    message: "Google Books is unavailable",<br/>    details: { provider: "google-books", error: "timeout" }<br/>  },<br/>  meta: { provider: "google-books" }<br/>}

    iOS-->>User: Show error: "Search failed. Please try again."
```

**Key Points:**
- **Graceful degradation:** Timeout doesn't crash app
- **Error details:** Provider name + error type for debugging
- **Retry:** User can retry search (might succeed if Google Books recovers)

---

## Multi-Provider Enrichment (Future)

```mermaid
sequenceDiagram
    participant iOS
    participant Enrichment as /api/enrichment/start
    participant GoogleBooks
    participant OpenLibrary
    participant MergeService

    iOS->>Enrichment: POST { isbns: ["978-0-123..."] }

    Enrichment->>GoogleBooks: GET volumeInfo
    Enrichment->>OpenLibrary: GET works/OL123W (parallel)
    GoogleBooks-->>Enrichment: Cover + basic metadata
    OpenLibrary-->>Enrichment: Detailed description + real Work

    Enrichment->>MergeService: merge(googleData, openLibraryData)
    MergeService->>MergeService: Prefer best field from each:<br/>- Cover: Google Books (higher quality)<br/>- Description: OpenLibrary (more detailed)<br/>- Genres: Merge both, deduplicate
    MergeService-->>Enrichment: WorkDTO {<br/>  coverImageURL: googleBooks.imageLinks.thumbnail,<br/>  description: openLibrary.description,<br/>  subjectTags: mergedGenres,<br/>  primaryProvider: "google-books",<br/>  contributors: ["google-books", "openlibrary"]<br/>}

    Enrichment-->>iOS: ResponseEnvelope { data: mergedWork }
```

**Key Points:**
- **Future enhancement:** Not yet implemented (October 2025)
- **Multi-provider:** Fetch from Google Books AND OpenLibrary
- **Best-of-breed:** Use best field from each provider
- **Provenance:** `contributors` lists all providers

---

## Genre Normalization Detail

```mermaid
flowchart TD
    A[Raw Genres from Provider] --> B{Normalize Each Genre}
    B --> C[Lowercase: "Thrillers" → "thrillers"]
    C --> D[Depluralize: "thrillers" → "thriller"]
    D --> E{Check Canonical Map}
    E -->|Found| F[Map to Canonical: "thriller" → "Thriller"]
    E -->|Not Found| G[Preserve Original: "Solarpunk" → "Solarpunk"]
    F --> H[Normalized Genres Array]
    G --> H
    H --> I[Return: ["Fiction", "Thriller", "Mystery"]]

    style A fill:#f9f,stroke:#333
    style H fill:#9f9,stroke:#333
    style I fill:#9f9,stroke:#333
```

**Canonical Genre Map (Sample):**
```typescript
const CANONICAL_GENRES = {
  'fiction': 'Fiction',
  'thriller': 'Thriller',
  'mystery': 'Mystery',
  'classics': 'Classic Literature',
  'science fiction': 'Science Fiction',
  'fantasy': 'Fantasy',
  // ... 30+ mappings
};
```

**Rules:**
1. Lowercase all genres
2. Depluralize (remove trailing 's')
3. Check canonical map
4. If found: Use canonical value
5. If not found: Preserve original (no data loss)

---

## Synthetic Work Deduplication Detail

```mermaid
flowchart TD
    A[WorkDTO Array from Backend] --> B{Check Synthetic Flag}
    B -->|synthetic: false| C[Keep as-is: Real Work]
    B -->|synthetic: true| D[Group by ISBN]
    D --> E{Count Works per ISBN}
    E -->|1 work| F[Keep as-is: Unique edition]
    E -->|2+ works| G[Merge into Single Work]
    G --> H[Combine editions from all works]
    G --> I[Keep first work's metadata]
    G --> J[Delete duplicate works]
    H --> K[Single Work with Multiple Editions]
    I --> K
    J --> K
    C --> L[Final Work Array]
    F --> L
    K --> L

    style A fill:#f9f,stroke:#333
    style L fill:#9f9,stroke:#333
```

**Example:**
- **Input:** 5 WorkDTOs (all synthetic, ISBN: 978-0-123...)
- **Process:** Group by ISBN → Detect 5 works with same ISBN
- **Output:** 1 Work with 5 editions (each edition from original WorkDTO)

---

## Performance Characteristics

### Timing Breakdown

| Phase | Duration | Notes |
|-------|----------|-------|
| iOS → Backend | 50-100ms | Network latency (CDN edge) |
| Backend → Google Books | 300-1000ms | Google Books API avg 500ms |
| Genre normalization | <5ms | Local TypeScript logic |
| DTO wrapping | <5ms | JSON serialization |
| Backend → iOS | 50-100ms | Network latency |
| iOS DTO parsing | 10-50ms | Swift Codable decoding |
| DTOMapper conversion | 20-100ms | SwiftData model creation |
| **Total (uncached)** | **500-1500ms** | Avg 800ms |
| **Total (cached)** | **50-150ms** | KV cache hit |

### Caching Strategy

**Endpoint:** `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`

**Cache Layers:**
1. **Cloudflare KV:**
   - Title search: 6 hours
   - ISBN search: 7 days
   - Advanced search: 6 hours
2. **Edge Cache:** 1 hour (Cloudflare CDN)
3. **iOS URLCache:** System-managed

**Cache Keys:**
```typescript
// Title search
`search:title:${query.toLowerCase().replace(/\s+/g, '-')}`

// ISBN search
`search:isbn:${isbn}`

// Advanced search
`search:advanced:${title}-${author}`
```

---

## DTO Field Mapping (TypeScript ↔ Swift)

### WorkDTO

| TypeScript Field | Swift Field | Type | Notes |
|------------------|-------------|------|-------|
| `title` | `title` | `String` | Required |
| `subjectTags` | `subjectTags` | `[String]` | Required (can be empty) |
| `synthetic` | `synthetic` | `Bool?` | Optional (default: false) |
| `primaryProvider` | `primaryProvider` | `String?` | Optional |
| `contributors` | `contributors` | `[String]?` | Optional |
| `googleBooksVolumeIDs` | `googleBooksVolumeIDs` | `[String]` | Required (can be empty) |

### EditionDTO

| TypeScript Field | Swift Field | Type | Notes |
|------------------|-------------|------|-------|
| `isbn` | `isbn` | `String?` | Optional (some editions lack ISBNs) |
| `isbns` | `isbns` | `[String]` | Required (can be empty) |
| `publisher` | `publisher` | `String?` | Optional |
| `coverImageURL` | `coverImageURL` | `String?` | Optional |
| `primaryProvider` | `primaryProvider` | `String?` | Optional |

### AuthorDTO

| TypeScript Field | Swift Field | Type | Notes |
|------------------|-------------|------|-------|
| `name` | `name` | `String` | Required |
| `gender` | `gender` | `DTOAuthorGender` | Required (enum) |
| `culturalRegion` | `culturalRegion` | `DTOCulturalRegion?` | Optional (enum) |

**Enum Sync:**
- TypeScript: `type AuthorGender = 'male' | 'female' | 'nonBinary' | 'other' | 'unknown'`
- Swift: `enum DTOAuthorGender: String, Codable { case male, female, nonBinary, other, unknown }`

---

## Integration Points

### Backend Services Using Canonical DTOs

**1. Search:**
- `/v1/search/title` - Title search
- `/v1/search/isbn` - ISBN lookup
- `/v1/search/advanced` - Multi-field search

**2. Enrichment:**
- `/api/enrichment/start` - Uses `/v1/search/isbn` internally

**3. Bookshelf Scanner:**
- `/api/scan-bookshelf` - AI scanner uses `/v1/search/isbn` after detection

**4. CSV Import:**
- `/api/import/csv-gemini` - Uses `/v1/search/title` for metadata lookup

### iOS Services Consuming Canonical DTOs

**1. BookSearchAPIService:**
- Calls `/v1/search/*` endpoints
- Parses `ResponseEnvelope<SearchResponseData>`
- Passes to DTOMapper

**2. EnrichmentService:**
- Background enrichment calls `/v1/search/isbn`
- DTOMapper converts to SwiftData models

**3. BookshelfScannerService:**
- AI-detected ISBNs call `/v1/search/isbn`
- DTOMapper handles synthetic work deduplication

---

## Testing Scenarios

### Backend Test (Vitest)

**File:** `cloudflare-workers/api-worker/tests/handlers/v1/search-title.test.ts`

```typescript
test('V1 title search returns canonical DTOs', async () => {
  const response = await fetch('/v1/search/title?q=The+Great+Gatsby');
  const json = await response.json();

  expect(json.success).toBe(true);
  expect(json.data.works[0].title).toBe('The Great Gatsby');
  expect(json.data.works[0].subjectTags).toContain('Fiction');
  expect(json.data.works[0].synthetic).toBe(true);
  expect(json.data.works[0].primaryProvider).toBe('google-books');
  expect(json.meta.provider).toBe('google-books');
});
```

### iOS Test (Swift Testing)

**File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/CanonicalAPIResponseTests.swift`

```swift
@Test func parseWorkDTO() throws {
    let json = """
    {
      "title": "The Great Gatsby",
      "subjectTags": ["Fiction", "Classic Literature"],
      "synthetic": true,
      "primaryProvider": "google-books",
      "googleBooksVolumeIDs": [],
      "goodreadsWorkIDs": [],
      "amazonASINs": [],
      "librarythingIDs": [],
      "isbndbQuality": 0,
      "reviewStatus": "unreviewed"
    }
    """
    let dto = try JSONDecoder().decode(WorkDTO.self, from: json.data(using: .utf8)!)
    #expect(dto.title == "The Great Gatsby")
    #expect(dto.subjectTags == ["Fiction", "Classic Literature"])
    #expect(dto.synthetic == true)
}
```

---

## Future Workflow Enhancements

### OpenLibrary Provider Integration (Planned)

```mermaid
sequenceDiagram
    participant iOS
    participant V1Title as /v1/search/title
    participant GoogleBooks
    participant OpenLibrary
    participant MergeService

    iOS->>V1Title: GET /v1/search/title?q=The+Great+Gatsby

    par Google Books
        V1Title->>GoogleBooks: Search volumes
        GoogleBooks-->>V1Title: Synthetic works (editions)
    and OpenLibrary
        V1Title->>OpenLibrary: Search works
        OpenLibrary-->>V1Title: Real works
    end

    V1Title->>MergeService: merge(googleData, openLibraryData)
    MergeService->>MergeService: Prefer OpenLibrary Work (real)<br/>Use Google Books cover (higher quality)
    MergeService-->>V1Title: WorkDTO {<br/>  synthetic: false,<br/>  primaryProvider: "openlibrary",<br/>  contributors: ["google-books", "openlibrary"]<br/>}

    V1Title-->>iOS: ResponseEnvelope { data: mergedWork }
```

**Estimated Effort:** 3-4 days

---

## Conclusion

Canonical Data Contracts eliminate provider-specific logic in iOS, ensure genre consistency, and enable provenance tracking. Key benefits:

- ✅ **Zero iOS provider logic:** Single DTOMapper for all providers
- ✅ **Genre normalization:** Consistent genres (Fiction → Fiction, not fiction/FICTION)
- ✅ **Synthetic work deduplication:** 5 editions → 1 work in library
- ✅ **Provenance tracking:** Know which provider contributed data
- ✅ **Type safety:** TypeScript + Swift Codable catch errors at compile time

---

**Workflow Status:** ✅ Complete and Validated
**Last Tested:** October 31, 2025 (v1 endpoints production)
**Related PRD:** [Canonical Data Contracts PRD](../product/Canonical-Data-Contracts-PRD.md)
