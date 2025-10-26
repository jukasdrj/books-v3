# CSV Import Workflow

**Feature:** Bulk Library Import from CSV Exports
**Supported Formats:** Goodreads, LibraryThing, StoryGraph
**Performance:** 100 books/min, <200MB memory (1500+ books)
**Last Updated:** October 2025

---

## User Journey Flow

```mermaid
flowchart TD
    Start([User Opens Settings]) --> TapImport[Tap 'Import CSV Library']

    TapImport --> ShowPicker[System file picker appears]

    ShowPicker --> UserSelect{User Action}
    UserSelect -->|Select CSV| ValidateFile[Validate file extension]
    UserSelect -->|Cancel| End([Exit Flow])

    ValidateFile --> ExtensionCheck{.csv extension?}
    ExtensionCheck -->|No| ShowError[Alert: 'Invalid file type']
    ExtensionCheck -->|Yes| ReadFile[Read file contents]

    ShowError --> End

    ReadFile --> DetectFormat[Auto-detect column mappings]
    DetectFormat --> FormatFound{Format Recognized?}

    FormatFound -->|Goodreads| ShowPreview[Show Goodreads preview]
    FormatFound -->|LibraryThing| ShowPreview
    FormatFound -->|StoryGraph| ShowPreview
    FormatFound -->|Unknown| ShowManualMap[Show manual mapping UI]

    ShowManualMap --> UserMaps[User maps columns]
    UserMaps --> ShowPreview

    ShowPreview --> ChooseStrategy{Duplicate Strategy?}

    ChooseStrategy -->|Smart Replace| SetSmart[strategy = .smart]
    ChooseStrategy -->|Skip Duplicates| SetSkip[strategy = .skipDuplicates]
    ChooseStrategy -->|Replace All| SetReplace[strategy = .replaceAll]

    SetSmart --> StartImport[Tap 'Import']
    SetSkip --> StartImport
    SetReplace --> StartImport

    StartImport --> ParseCSV[CSVParsingActor parses rows]
    ParseCSV --> BatchInsert[Batch SwiftData insertion - 50 rows/batch]

    BatchInsert --> DuplicateCheck{Check duplicates}

    DuplicateCheck -->|Title + Author Match| HandleDupe{Strategy?}
    DuplicateCheck -->|No Match| CreateNew[Create new Work]

    HandleDupe -->|Smart| UpdateMetadata[Update existing work metadata]
    HandleDupe -->|Skip| SkipRow[Skip row, increment counter]
    HandleDupe -->|Replace| DeleteOld[Delete old, create new]

    UpdateMetadata --> NextRow{More rows?}
    SkipRow --> NextRow
    CreateNew --> QueueEnrichment[Add to enrichment queue]
    DeleteOld --> CreateNew

    QueueEnrichment --> NextRow

    NextRow -->|Yes| BatchInsert
    NextRow -->|No| ShowSummary[Display import summary]

    ShowSummary --> StartEnrichment[EnrichmentQueue.shared.processQueue]
    StartEnrichment --> ShowBanner[Display EnrichmentProgressBanner]

    ShowBanner --> Complete([Import Complete])
```

---

## Title Normalization Flow

```mermaid
flowchart LR
    Raw[Raw CSV Title] --> Examples["Examples:<br/>- Harry Potter (Series, #1)<br/>- The da Vinci Code: The Young Adult Adaptation<br/>- 1984 [50th Anniversary Edition]"]

    Examples --> Step1[Remove series markers: \(..., #\d+\)]
    Step1 --> Step2[Remove edition markers: \[...\]]
    Step2 --> Step3[Strip subtitles after ':' if length > 10]
    Step3 --> Step4[Remove abbreviation periods]
    Step4 --> Step5[Normalize whitespace]

    Step5 --> TwoVersions{Store Two Versions}

    TwoVersions -->|Display| Original[work.title = original]
    TwoVersions -->|API Search| Normalized[normalizedTitle used in searches]

    Original --> SwiftData[Save to SwiftData]
    Normalized --> APICall[EnrichmentService.enrichWork]

    APICall --> BetterMatch[90%+ enrichment success rate]

    style BetterMatch fill:#90EE90
```

---

## Duplicate Detection Algorithm

```mermaid
flowchart TD
    NewBook[New Book from CSV] --> Check1{Exact title + author match?}

    Check1 -->|Yes| FoundDupe[Duplicate detected]
    Check1 -->|No| Check2{ISBN match?}

    Check2 -->|Yes| FoundDupe
    Check2 -->|No| Check3{Normalized title + fuzzy author?}

    Check3 -->|Match score > 80| FoundDupe
    Check3 -->|Match score ≤ 80| NotDupe[Not a duplicate]

    FoundDupe --> ApplyStrategy{Duplicate Strategy}

    ApplyStrategy -->|Smart| CompareData{Which has more data?}
    ApplyStrategy -->|Skip| SkipNew[Skip new book, keep existing]
    ApplyStrategy -->|Replace| ReplaceOld[Delete old, insert new]

    CompareData -->|New book richer| UpdateExisting[Merge metadata into existing]
    CompareData -->|Existing richer| KeepExisting[Keep existing, skip new]

    NotDupe --> CreateWork[Insert new Work]

    SkipNew --> IncrementSkipped[duplicates++]
    ReplaceOld --> IncrementReplaced[replaced++]
    UpdateExisting --> IncrementUpdated[updated++]
    CreateWork --> IncrementImported[imported++]

    IncrementSkipped --> Summary[Final ImportSummary]
    IncrementReplaced --> Summary
    IncrementUpdated --> Summary
    IncrementImported --> Summary
```

---

## Background Enrichment State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> Queued : addMultiple(workIds)

    Queued --> Processing : processNextWork()

    Processing --> Calling : enrichWork(work)

    Calling --> Found : API success + match
    Calling --> NotFound : API success + no match
    Calling --> Uncertain : API success + ambiguous
    Calling --> Failed : Network/API error

    Found --> UpdateWork : Set coverUrl, ISBN, metadata
    NotFound --> MarkUnenriched : Set enrichmentStatus
    Uncertain --> MarkUncertain : Store candidates for manual selection
    Failed --> MarkFailed : Retry later

    UpdateWork --> NextInQueue : workQueue.remove(workId)
    MarkUnenriched --> NextInQueue
    MarkUncertain --> NextInQueue
    MarkFailed --> NextInQueue

    NextInQueue --> Processing : More work in queue
    NextInQueue --> Idle : Queue empty

    note right of Calling
        Uses normalized title
        for better API matching
    end note

    note left of Found
        Publishes NotificationCenter
        .enrichmentProgressUpdated
    end note
```

---

## API Integration (Backend)

```mermaid
sequenceDiagram
    participant iOS
    participant EnrichmentService
    participant Worker
    participant GoogleBooks
    participant OpenLibrary
    participant KVCache

    iOS->>EnrichmentService: enrichWork(work)
    EnrichmentService->>EnrichmentService: Normalize title

    Note over EnrichmentService: work.title.normalizedTitleForSearch

    EnrichmentService->>Worker: GET /search/title?q={normalized}

    Worker->>KVCache: Check cache (6h TTL)
    KVCache-->>Worker: Cache miss

    par Parallel Search
        Worker->>GoogleBooks: Search by title + author
        Worker->>OpenLibrary: Search by title + author
    end

    GoogleBooks-->>Worker: 10 results
    OpenLibrary-->>Worker: 8 results

    Worker->>Worker: Deduplicate by ISBN
    Worker->>Worker: Merge metadata (prefer Google Books covers)

    Worker->>KVCache: Cache results (6h)
    Worker-->>EnrichmentService: [SearchResult] array

    EnrichmentService->>EnrichmentService: findBestMatch(results, work)

    Note over EnrichmentService: Scoring algorithm:<br/>- Normalized title match: 100 pts<br/>- Author match: 50 pts<br/>- Year match: 30 pts<br/>- Threshold: 60 pts

    alt Match Found (score ≥ 60)
        EnrichmentService->>iOS: .found(metadata)
        iOS->>iOS: Update work.coverUrl, work.isbn
    else No Match
        EnrichmentService->>iOS: .notFound
        iOS->>iOS: Mark as unenriched
    else Ambiguous (multiple 60+ scores)
        EnrichmentService->>iOS: .uncertain(candidates)
        iOS->>iOS: Show manual selection UI
    end
```

---

## Memory Management (Batch Processing)

```mermaid
flowchart LR
    CSV[1500 book CSV] --> Stream[Streaming Parser]

    Stream --> Batch1[Batch 1: Rows 1-50]
    Stream --> Batch2[Batch 2: Rows 51-100]
    Stream --> Batch3[Batch 3: Rows 101-150]
    Stream --> BatchN[Batch N: Rows 1451-1500]

    Batch1 --> Insert1[SwiftData insert]
    Batch2 --> Insert2[SwiftData insert]
    Batch3 --> Insert3[SwiftData insert]
    BatchN --> InsertN[SwiftData insert]

    Insert1 --> Save1[modelContext.save]
    Insert2 --> Save2[modelContext.save]
    Insert3 --> Save3[modelContext.save]
    InsertN --> SaveN[modelContext.save]

    Save1 --> GC1[Garbage collection]
    Save2 --> GC2[Garbage collection]
    Save3 --> GC3[Garbage collection]
    SaveN --> GCN[Garbage collection]

    GC1 --> Peak[Peak Memory: <200MB]
    GC2 --> Peak
    GC3 --> Peak
    GCN --> Peak

    style Peak fill:#90EE90
```

---

## Key Components

| Component | Responsibility | File |
|-----------|---------------|------|
| **CSVImportFlowView** | Multi-step import wizard UI | `CSVImportFlowView.swift` |
| **CSVParsingActor** | High-performance CSV parsing | `CSVParsingActor.swift` (@globalActor) |
| **CSVImportService** | SwiftData import orchestration | `CSVImportService.swift` |
| **EnrichmentService** | API metadata enrichment | `EnrichmentService.swift` |
| **EnrichmentQueue** | Background enrichment queue | `EnrichmentQueue.swift` (@MainActor) |
| **String+TitleNormalization** | Title normalization algorithm | `String+TitleNormalization.swift` |
| **EnrichmentProgressBanner** | Real-time progress UI | `EnrichmentProgressBanner.swift` |

---

## Error Handling

```mermaid
flowchart TD
    Error[Error Occurred] --> ErrorType{Error Type}

    ErrorType -->|File not readable| ShowFileError[Alert: 'Cannot read file']
    ErrorType -->|Invalid CSV format| ShowFormatError[Alert: 'Invalid CSV structure']
    ErrorType -->|SwiftData save failed| RetryInsert[Retry insertion - 3 attempts]
    ErrorType -->|Network offline during enrichment| QueueForLater[Queue enrichment for later]
    ErrorType -->|Memory pressure| ReduceBatchSize[Reduce batch size from 50 to 25]

    ShowFileError --> End([Exit Import])
    ShowFormatError --> End

    RetryInsert --> AttemptCheck{Retry < 3?}
    AttemptCheck -->|Yes| RetryAPI[Re-attempt save]
    AttemptCheck -->|No| ShowFatalError[Alert: 'Import failed - check storage']

    QueueForLater --> ContinueImport[Continue importing without enrichment]
    ContinueImport --> RetryEnrichment[Retry enrichment when online]

    ReduceBatchSize --> ContinueBatching[Continue with smaller batches]
```

---

## Performance Benchmarks

| Book Count | Import Time | Enrichment Time | Total | Peak Memory |
|-----------|-------------|-----------------|-------|-------------|
| 100       | ~30s        | ~2-3 min        | ~3.5 min | <50MB |
| 500       | ~2.5 min    | ~10-12 min      | ~14 min | <120MB |
| 1500      | ~7.5 min    | ~30-35 min      | ~42 min | <200MB |

**Success Rates:**
- Duplicate detection: 95%+
- Enrichment success (with normalization): 90%+
- Popular books: 95%+
- Obscure/self-published: 70-80%

---

## Related Documentation

- **Feature Documentation:** `docs/features/CSV_IMPORT.md`
- **Title Normalization Tests:** `BooksTrackerPackage/Tests/.../StringTitleNormalizationTests.swift`
- **SyncCoordinator:** `docs/architecture/SyncCoordinator-Architecture.md`
- **Enrichment API:** `cloudflare-workers/api-worker/src/handlers/search.js`

---

## Future Enhancements

- [ ] Progress persistence across app restarts
- [ ] Partial import recovery (resume after crash)
- [ ] Custom column mapping UI (manual field selection)
- [ ] Export enriched library back to CSV
- [ ] Import from iCloud Drive / Dropbox
- [ ] Automatic backup before destructive imports
