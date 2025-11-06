# CSV Import Workflow

**Feature:** AI-Powered CSV Import (Gemini)
**Status:** ✅ Production (v3.1.0+)
**Supported Formats:** Any CSV with title/author/ISBN (auto-detected by Gemini)
**Performance:** Backend-processed with real-time WebSocket progress
**Last Updated:** October 2025

**⚠️ Note:** This doc describes the **current Gemini AI-powered import**. Legacy manual CSV import was deprecated in v3.3.0 (October 2025) and archived to `docs/archive/features-removed/CSV_IMPORT.md`.

---

## User Journey Flow (Gemini AI Import)

```mermaid
flowchart TD
    Start([User Opens Settings]) --> TapImport[Tap 'AI-Powered CSV Import']

    TapImport --> ShowPicker[System file picker appears]

    ShowPicker --> UserSelect{User Action}
    UserSelect -->|Select CSV| ValidateFile[Validate file < 10MB]
    UserSelect -->|Cancel| End([Exit Flow])

    ValidateFile --> SizeCheck{File ≤ 10MB?}
    SizeCheck -->|No| ShowError[Alert: 'File too large']
    SizeCheck -->|Yes| ReadFile[Read CSV contents]

    ShowError --> End

    ReadFile --> UploadStart[Upload CSV to backend]
    UploadStart --> ShowUploading[Show uploading spinner]

    ShowUploading --> BackendParse[Backend: Gemini parses CSV]

    BackendParse --> ConnectWS[Connect WebSocket for progress]

    ConnectWS --> ParsePhase[Phase 1: Gemini Parsing - 5-50%]
    ParsePhase --> ParseComplete{Gemini Success?}

    ParseComplete -->|Success| EnrichPhase[Phase 2: Enrichment - 50-100%]
    ParseComplete -->|Failed| ShowError2[Show Gemini parse error]

    EnrichPhase --> ProcessBooks[Process each parsed book]

    ProcessBooks --> NextBook{More books?}
    NextBook -->|Yes| EnrichBook[Enrich metadata via /search]
    NextBook -->|No| Complete

    EnrichBook --> InsertWork[Insert Work + Author + Edition]
    InsertWork --> InsertLibraryEntry[🔥 Insert UserLibraryEntry .toRead]
    InsertLibraryEntry --> UpdateProgress[WebSocket: Update progress %]
    UpdateProgress --> ProcessBooks
    
    style InsertLibraryEntry fill:#ff6b6b,stroke:#c92a2a,color:#fff

    Complete --> ShowSummary[Display import summary]
    ShowSummary --> End2([Import Complete])

    ShowError2 --> End
```

**🔥 CRITICAL: UserLibraryEntry Creation**

The `UserLibraryEntry` step (highlighted in red above) is **required** for books to appear in the Library view:

- **Without UserLibraryEntry:** Books are saved to SwiftData but remain invisible in the UI
- **Why:** `LibraryFilterService.filterLibraryWorks()` filters out works with empty `userLibraryEntries`
- **Default Status:** CSV imports create entries with `.toRead` status
- **Code Reference:** `GeminiCSVImportView.swift:505-510`, `LibraryFilterService.swift:20-30`

This step was added in commit 086384b to fix the "CSV import books not appearing in library" issue.

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

## Key Components (Gemini CSV Import)

| Component | Responsibility | File |
|-----------|---------------|------|
| **GeminiCSVImportView** | Upload + progress UI + **UserLibraryEntry creation** | `GeminiCSVImport/GeminiCSVImportView.swift` |
| **GeminiCSVImportService** | Backend API client | `GeminiCSVImport/GeminiCSVImportService.swift` |
| **EnrichmentService** | Fetches book metadata | `Enrichment/EnrichmentService.swift` |
| **EnrichmentQueue** | Manages background enrichment | `Enrichment/EnrichmentQueue.swift` |
| **LibraryFilterService** | Filters works by UserLibraryEntry (line 20-30) | `Services/LibraryFilterService.swift` |
| **api-worker** | Gemini parsing + enrichment | `cloudflare-workers/api-worker/src/handlers/gemini-csv-import.js` |
| **ProgressWebSocketDO** | Real-time progress updates | `cloudflare-workers/api-worker/src/durable-objects/ProgressWebSocketDO.js` |

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

- **Feature Documentation:** `docs/features/GEMINI_CSV_IMPORT.md`
- **Legacy CSV Import (Archived):** `docs/archive/features-removed/CSV_IMPORT.md`
- **WebSocket Progress:** `docs/workflows/enrichment-workflow.md` (shared pattern)
- **Backend Handler:** `cloudflare-workers/api-worker/src/handlers/gemini-csv-import.js`

---

## Future Enhancements

- [ ] Progress persistence across app restarts
- [ ] Partial import recovery (resume after crash)
- [ ] Custom column mapping UI (manual field selection)
- [ ] Export enriched library back to CSV
- [ ] Import from iCloud Drive / Dropbox
- [ ] Automatic backup before destructive imports
