# Search Workflow

**Feature:** Multi-Mode Book Search (Title, ISBN, Advanced)
**Primary Flow:** User searches for books by title, author, or ISBN using canonical V1 endpoints
**Last Updated:** October 31, 2025
**Related PRD:** [Search PRD](../product/Search-PRD.md)

---

## User Journey Flow

```mermaid
flowchart TD
    Start([User Opens Search Tab]) --> Initial[Show Trending Books & Recent Searches]

    Initial --> Choice{User Action?}

    Choice -->|Types in search bar| TextSearch[Enter search query]
    Choice -->|Taps ISBN scanner| ISBNScanner[Open Camera Scanner]
    Choice -->|Taps trending book| DirectDetail[Navigate to WorkDetailView]

    TextSearch --> ValidateQuery{Query length ≥ 2?}
    ValidateQuery -->|No| ShowError[Show inline validation]
    ValidateQuery -->|Yes| CallAPI[Call /v1/search/title API]

    ISBNScanner --> ScanBarcode[Scan ISBN barcode]
    ScanBarcode --> ISBNSuccess{Barcode detected?}
    ISBNSuccess -->|Yes| CallISBN[Call /v1/search/isbn API]
    ISBNSuccess -->|No| ScanBarcode

    CallAPI --> APIResponse{API Response}
    CallISBN --> APIResponse

    APIResponse -->|Success with results| ShowResults[Display search results]
    APIResponse -->|Success but empty| ShowEmpty[Show 'No results found']
    APIResponse -->|Network error| ShowRetry[Show retry button]
    APIResponse -->|Timeout| ShowRetry

    ShowResults --> UserSelect{User taps result?}
    UserSelect -->|Yes| NavigateDetail[Navigate to WorkDetailView]
    UserSelect -->|No| ShowResults

    NavigateDetail --> DetailActions{User action on detail?}
    DetailActions -->|Add to Library| CreateEntry[Create UserLibraryEntry]
    DetailActions -->|Back| ShowResults
    DetailActions -->|Change status| UpdateEntry[Update reading status]

    CreateEntry --> SaveContext[Save SwiftData ModelContext]
    UpdateEntry --> SaveContext

    SaveContext --> End([Search Complete])
    ShowEmpty --> End
    ShowRetry --> Choice
    DirectDetail --> DetailActions
```

---

## State Machine

```mermaid
stateDiagram-v2
    [*] --> Initial

    Initial --> Searching : User types query
    Initial --> Scanning : User taps ISBN scanner

    Searching --> Results : API success (items > 0)
    Searching --> Empty : API success (items = 0)
    Searching --> Error : Network/API failure

    Scanning --> Searching : ISBN detected
    Scanning --> Scanning : No barcode found

    Results --> Detail : User taps result
    Detail --> Results : User taps back
    Detail --> LibraryUpdated : User adds/updates entry

    Empty --> Initial : User clears search
    Error --> Searching : User retries

    LibraryUpdated --> [*]
    Results --> [*] : User navigates away
```

---

## Sequence Diagram (API Integration)

```mermaid
sequenceDiagram
    participant User
    participant SearchView
    participant SearchModel
    participant APIClient
    participant CloudflareWorker
    participant GoogleBooks
    participant OpenLibrary

    User->>SearchView: Types "Harry Potter"
    SearchView->>SearchModel: updateSearchQuery("Harry Potter")

    Note over SearchModel: Debounce 300ms

    SearchModel->>SearchModel: validateQuery() ✓ (length ≥ 2)
    SearchModel->>APIClient: searchTitle("Harry Potter")

    APIClient->>CloudflareWorker: GET /v1/search/title?q=Harry+Potter

    alt Cache Hit (KV)
        CloudflareWorker-->>APIClient: Cached ResponseEnvelope (6h TTL)
    else Cache Miss
        CloudflareWorker->>GoogleBooks: Search volumes
        CloudflareWorker->>CloudflareWorker: Normalize to canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)
        CloudflareWorker->>CloudflareWorker: Apply genre normalization
        CloudflareWorker->>CloudflareWorker: Wrap in ResponseEnvelope
        CloudflareWorker->>CloudflareWorker: Cache in KV (6h)
        CloudflareWorker-->>APIClient: ResponseEnvelope<WorkDTO[], EditionDTO[], AuthorDTO[]>
    end

    APIClient->>APIClient: Parse ResponseEnvelope
    APIClient->>DTOMapper: mapToWorks(data, modelContext)
    DTOMapper-->>APIClient: [Work] array
    SearchModel->>SearchModel: state = .results(items, query)
    SearchModel-->>SearchView: UI update
    SearchView-->>User: Display results list

    User->>SearchView: Taps first result
    SearchView->>WorkDetailView: Navigate with Work object
```

---

## Key Components

| Component | Responsibility | File |
|-----------|---------------|------|
| **SearchView** | UI rendering, user input | `SearchView.swift` |
| **SearchModel** | State management (@Observable) | `SearchModel.swift:1129` |
| **SearchViewState** | Enum-based state representation | `SearchModel.swift:18-31` |
| **BookSearchAPIService** | HTTP requests to `/v1/*` endpoints | `Services/BookSearchAPIService.swift` |
| **DTOMapper** | Converts canonical DTOs to SwiftData models | `Services/DTOMapper.swift` |
| **ISBNScannerView** | VisionKit barcode scanner | `ISBNScannerView.swift` |

---

## Error Handling

```mermaid
flowchart LR
    Error[API Error] --> CheckType{Error Type}

    CheckType -->|URLError.notConnectedToInternet| OfflineMsg[Show 'No internet connection']
    CheckType -->|URLError.timedOut| TimeoutMsg[Show 'Request timed out']
    CheckType -->|HTTP 429| RateLimitMsg[Show 'Too many requests']
    CheckType -->|HTTP 500-599| ServerMsg[Show 'Server error - try again']
    CheckType -->|Other| GenericMsg[Show 'Something went wrong']

    OfflineMsg --> RetryButton[Show retry button]
    TimeoutMsg --> RetryButton
    RateLimitMsg --> RetryButton
    ServerMsg --> RetryButton
    GenericMsg --> RetryButton

    RetryButton --> UserRetry{User taps retry?}
    UserRetry -->|Yes| RetryAPI[Re-attempt API call]
    UserRetry -->|No| StayError[Remain in error state]
```

---

## Performance Optimizations

1. **Query Debouncing:** 300ms delay prevents API spam during typing
2. **KV Cache:** 6-hour TTL reduces redundant API calls (Cloudflare Worker)
3. **Batch Deduplication:** Merges Google Books + OpenLibrary results server-side
4. **Lazy Loading:** Results rendered on-demand (no pagination yet)

---

## Related Documentation

- **PRD:** `docs/product/Search-PRD.md` (this feature)
- **V1 API Handlers:**
  - `cloudflare-workers/api-worker/src/handlers/v1/search-title.ts`
  - `cloudflare-workers/api-worker/src/handlers/v1/search-isbn.ts`
  - `cloudflare-workers/api-worker/src/handlers/v1/search-advanced.ts`
- **Canonical DTOs:** `docs/product/Canonical-Data-Contracts-PRD.md`
- **Backend Architecture:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md`
- **Barcode Scanner:** `docs/product/VisionKit-Barcode-Scanner-PRD.md`
- **DTOMapper:** `docs/product/DTOMapper-PRD.md`

---

## Future Enhancements

- [ ] Infinite scroll pagination (GitHub Issue TBD)
- [ ] Voice search integration
- [ ] Search history persistence (SwiftData)
- [ ] Advanced filters (genre, publication year)
- [ ] Offline search (local SwiftData cache)
