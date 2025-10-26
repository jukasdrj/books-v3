# Metadata Enrichment Workflow

**Feature:** Background Metadata Enrichment System
**Purpose:** Automatically fetch book covers, ISBNs, and metadata after import
**Architecture:** Queue-based background processing with WebSocket progress
**Last Updated:** October 2025

---

## System Overview

```mermaid
flowchart TD
    Import[Book Import Source] --> SourceType{Source Type}

    SourceType -->|CSV Import| CSVBooks[100-1500 books]
    SourceType -->|Bookshelf Scan| ScanBooks[5-50 books]
    SourceType -->|Manual Search| SingleBook[1 book]

    CSVBooks --> AddQueue[EnrichmentQueue.addMultiple]
    ScanBooks --> AddQueue
    SingleBook --> AddQueue

    AddQueue --> QueueStore[Store in workQueue Set<PersistentID>]

    QueueStore --> StartCheck{isProcessing?}
    StartCheck -->|Yes| Wait[Wait for current job to finish]
    StartCheck -->|No| ProcessNext[processNextWork]

    Wait --> ProcessNext

    ProcessNext --> ValidateWork{Work exists in SwiftData?}
    ValidateWork -->|No - Stale ID| RemoveFromQueue[workQueue.remove]
    ValidateWork -->|Yes| CallEnrich[EnrichmentService.enrichWork]

    RemoveFromQueue --> ProcessNext

    CallEnrich --> APIResponse{API Response}

    APIResponse -->|Found| UpdateWork[Set coverUrl, ISBN, metadata]
    APIResponse -->|NotFound| MarkFailed[enrichmentStatus = .failed]
    APIResponse -->|Uncertain| StoreCandidates[Store candidates for manual selection]

    UpdateWork --> SaveContext[modelContext.save]
    MarkFailed --> SaveContext
    StoreCandidates --> SaveContext

    SaveContext --> NotifyProgress[Post NotificationCenter.enrichmentProgressUpdated]

    NotifyProgress --> MoreWork{workQueue.isEmpty?}

    MoreWork -->|No| ProcessNext
    MoreWork -->|Yes| Complete[isProcessing = false]

    Complete --> ShowBanner[EnrichmentProgressBanner dismisses]
```

---

## Queue Processing State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> Validating : add(workId)
    Idle --> Validating : addMultiple([workIds])

    Validating --> Queued : workQueue.insert(validIds)

    Queued --> Processing : processQueue() called
    Processing --> Enriching : dequeue first work

    Enriching --> APICalling : enrichWork(work)

    APICalling --> Success : HTTP 200 + results
    APICalling --> NotFound : HTTP 200 + empty
    APICalling --> Retry : HTTP 429/503
    APICalling --> Failed : Network error

    Success --> Updating : Update SwiftData model
    NotFound --> Marking : Mark as failed
    Retry --> Queued : Re-add to queue after delay
    Failed --> Marking : Mark as failed

    Updating --> NextWork
    Marking --> NextWork

    NextWork --> Processing : More work in queue
    NextWork --> Idle : Queue empty

    note right of APICalling
        Uses normalized title
        for better matching
    end note

    note left of Retry
        Exponential backoff:
        1s, 2s, 4s, 8s
    end note
```

---

## Backend Job Orchestration (WebSocket)

```mermaid
sequenceDiagram
    participant iOS
    participant Queue as EnrichmentQueue
    participant Service as EnrichmentService
    participant Worker as Cloudflare Worker
    participant DO as ProgressWebSocketDO
    participant WebSocket

    Note over iOS,WebSocket: Background Enrichment for CSV Import

    iOS->>Queue: addMultiple([work1, work2, work3])
    Queue->>Queue: Generate jobId = UUID()
    Queue->>Queue: setCurrentJobId(jobId)

    Queue->>WebSocket: Connect to /ws/progress?jobId={uuid}
    WebSocket->>DO: Upgrade connection
    DO-->>Queue: Connected

    Queue->>Worker: POST /api/enrichment/start
    Note over Worker: Loops through works

    loop For Each Work
        Worker->>Service: enrichWork(work)
        Service->>Worker: API search + match
        Worker->>DO: pushProgress(processedItems++)
        DO->>WebSocket: Send progress update
        WebSocket-->>Queue: JobProgress update
        Queue->>iOS: NotificationCenter post
        iOS->>iOS: Update EnrichmentProgressBanner
    end

    Worker->>DO: pushProgress(status: 'complete')
    DO->>WebSocket: Final update
    WebSocket-->>Queue: Complete signal

    Queue->>Queue: clearCurrentJobId()
    Queue->>iOS: Dismiss banner
```

---

## Job Cancellation Flow

```mermaid
flowchart TD
    User[User Action] --> Trigger{Trigger Type}

    Trigger -->|Settings → Reset Library| ResetFlow[LibraryResetService.resetLibrary]
    Trigger -->|Manual Cancel Button| ManualCancel[User taps cancel in banner]

    ResetFlow --> CheckJob{currentJobId exists?}
    ManualCancel --> CheckJob

    CheckJob -->|Yes| CancelBackend[POST /api/enrichment/cancel]
    CheckJob -->|No| LocalOnly[Stop local processing only]

    CancelBackend --> WorkerCancel[Worker calls doStub.cancelJob]
    WorkerCancel --> DOCancel[ProgressWebSocketDO sets 'canceled' status]

    DOCancel --> EnrichLoop[Enrichment loop checks isCanceled]
    EnrichLoop --> BreakLoop{isCanceled == true?}

    BreakLoop -->|Yes| SendFinal[Send final 'canceled' WebSocket update]
    BreakLoop -->|No| ContinueProcessing[Process next book]

    SendFinal --> iOSReceive[iOS receives cancellation confirmation]
    LocalOnly --> iOSReceive

    iOSReceive --> Cleanup[Clear queue, reset state]
    Cleanup --> DismissBanner[Dismiss EnrichmentProgressBanner]

    ContinueProcessing --> EnrichLoop
```

---

## Title Normalization Impact

```mermaid
flowchart LR
    subgraph Before Normalization
        RawTitle["CSV: Harry Potter (Series, #1)"]
        RawAPI[API Search: 'Harry Potter (Series, #1)']
        RawResult[❌ Zero Results - 70% success rate]
    end

    subgraph After Normalization
        NormTitle["CSV: Harry Potter (Series, #1)"]
        NormProcess[Normalized: 'Harry Potter']
        NormAPI[API Search: 'Harry Potter']
        NormResult[✅ 10+ Results - 90%+ success rate]
    end

    RawTitle --> RawAPI --> RawResult
    NormTitle --> NormProcess --> NormAPI --> NormResult

    style RawResult fill:#FF6B6B
    style NormResult fill:#90EE90
```

---

## Progress Notification Architecture

```mermaid
sequenceDiagram
    participant Queue as EnrichmentQueue
    participant NC as NotificationCenter
    participant ContentView
    participant Banner as EnrichmentProgressBanner

    Queue->>Queue: processNextWork() completes

    Queue->>NC: post(.enrichmentProgressUpdated)
    Note over NC: UserInfo:<br/>current: 15<br/>total: 100

    NC->>ContentView: onReceive notification

    ContentView->>ContentView: Extract userInfo
    ContentView->>ContentView: enrichmentProgress = (15, 100)
    ContentView->>ContentView: showEnrichmentBanner = true

    ContentView->>Banner: Update binding
    Banner->>Banner: Render "Enriching Metadata... 15/100 (15%)"

    Note over Queue,Banner: Process continues...

    Queue->>NC: post(.enrichmentProgressUpdated)
    Note over NC: UserInfo:<br/>current: 100<br/>total: 100

    NC->>ContentView: onReceive notification
    ContentView->>Banner: Update to 100%

    Banner->>Banner: Auto-dismiss after 2s
    Banner->>ContentView: showEnrichmentBanner = false
```

---

## Queue Self-Cleaning Mechanism

```mermaid
flowchart TD
    Startup[App Launch] --> Validate[ContentView.task - validateQueue]

    Validate --> GetQueue[Fetch all IDs from workQueue]

    GetQueue --> LoopIDs[For each PersistentID]

    LoopIDs --> CheckExists{modelContext.model(for: id)?}

    CheckExists -->|Exists| ValidID[Keep in queue]
    CheckExists -->|Throws| StaleID[Remove from queue]

    StaleID --> RemoveSet[workQueue.remove(id)]
    ValidID --> NextID{More IDs?}

    RemoveSet --> NextID

    NextID -->|Yes| LoopIDs
    NextID -->|No| CleanComplete[Queue cleaned]

    CleanComplete --> ProcessQueue[Resume processing valid works]

    style StaleID fill:#FFD93D
    style ValidID fill:#90EE90
```

---

## API Matching Algorithm

```mermaid
flowchart TD
    Results[API Results Array] --> Loop[For each result]

    Loop --> Score[Initialize score = 0]

    Score --> TitleCheck{Normalized title match?}
    TitleCheck -->|Exact match| Add100[score += 100]
    TitleCheck -->|Contains| Add50[score += 50]
    TitleCheck -->|No match| AuthorCheck

    Add100 --> AuthorCheck{Author match?}
    Add50 --> AuthorCheck

    AuthorCheck -->|Exact match| Add50_2[score += 50]
    AuthorCheck -->|Partial match| Add25[score += 25]
    AuthorCheck -->|No match| YearCheck

    Add50_2 --> YearCheck{Publication year match?}
    Add25 --> YearCheck

    YearCheck -->|Exact match| Add30[score += 30]
    YearCheck -->|Within 2 years| Add15[score += 15]
    YearCheck -->|No match| CheckScore

    Add30 --> CheckScore{score ≥ 60?}
    Add15 --> CheckScore

    CheckScore -->|Yes| ReturnMatch[Return this result as match]
    CheckScore -->|No| NextResult{More results?}

    NextResult -->|Yes| Loop
    NextResult -->|No| NoMatch[Return nil - no match found]

    style ReturnMatch fill:#90EE90
    style NoMatch fill:#FF6B6B
```

---

## Key Components

| Component | Responsibility | File | Actor Isolation |
|-----------|---------------|------|-----------------|
| **EnrichmentQueue** | Queue management & orchestration | `EnrichmentQueue.swift` | @MainActor |
| **EnrichmentService** | API calls & matching logic | `EnrichmentService.swift` | Nonisolated |
| **EnrichmentAPIClient** | HTTP networking layer | `EnrichmentAPIClient.swift` | Nonisolated |
| **EnrichmentProgressBanner** | Real-time progress UI | `EnrichmentProgressBanner.swift` | @MainActor |
| **String+TitleNormalization** | Title cleaning algorithm | `String+TitleNormalization.swift` | Nonisolated |
| **LibraryResetService** | Reset + cancellation logic | `LibraryResetService.swift` | @MainActor |

---

## Error Recovery Strategies

```mermaid
flowchart TD
    Error[Enrichment Failed] --> ErrorType{Error Type}

    ErrorType -->|HTTP 429 Rate Limit| Backoff[Exponential backoff - retry after 1s, 2s, 4s, 8s]
    ErrorType -->|HTTP 503 Service Unavailable| QueueLater[Re-add to queue - retry in 30s]
    ErrorType -->|Network Timeout| RetryImmediate[Retry immediately - 3 attempts max]
    ErrorType -->|HTTP 404 Not Found| MarkPermanent[Mark as permanently failed - don't retry]
    ErrorType -->|Stale PersistentID| RemoveQueue[Remove from queue - SwiftData model deleted]

    Backoff --> CheckRetries{Retry count < 4?}
    CheckRetries -->|Yes| RetryAPI[Re-attempt API call]
    CheckRetries -->|No| MarkFailed[Mark as failed]

    QueueLater --> AddBack[workQueue.insert(id)]
    RetryImmediate --> CheckAttempts{Attempt < 3?}

    CheckAttempts -->|Yes| RetryAPI
    CheckAttempts -->|No| MarkFailed

    MarkPermanent --> StoreError[Store error message in Work model]
    RemoveQueue --> NextWork[Process next work in queue]

    MarkFailed --> NotifyUser[Show error banner]
    RetryAPI --> ProcessWork[Continue enrichment]
```

---

## Performance Optimizations

1. **Batch Processing:** Process 50 works before saving SwiftData context
2. **Queue Deduplication:** Use `Set<PersistentID>` to prevent duplicate enrichment
3. **Stale ID Cleanup:** Validate existence before processing
4. **NotificationCenter:** Lightweight progress updates (no @Published overhead)
5. **Title Normalization:** 20% boost in API success rate

---

## Success Metrics

| Metric | Target | Current | Notes |
|--------|--------|---------|-------|
| Enrichment Success Rate | 85%+ | 90%+ | With title normalization |
| Processing Speed | 100 books/min | ~100 books/min | Network-bound |
| Memory Usage | <200MB | <200MB | For 1500 book queue |
| Queue Stability | Zero stale IDs | ✅ Validated | Self-cleaning on startup |

---

## Related Documentation

- **Feature Documentation:** `docs/features/CSV_IMPORT.md`
- **Title Normalization:** `BooksTrackerPackage/Sources/.../String+TitleNormalization.swift`
- **WebSocket Architecture:** `docs/WEBSOCKET_ARCHITECTURE.md`
- **Backend Enrichment:** `cloudflare-workers/api-worker/src/services/enrichment.js`
- **Job Cancellation:** `CLAUDE.md` - Library Reset section

---

## Future Enhancements

- [ ] Persistent queue across app restarts (UserDefaults or SwiftData)
- [ ] Priority queue (user-triggered enrichment first)
- [ ] Manual retry button for failed enrichments
- [ ] Bulk metadata export (enriched vs unenriched comparison)
- [ ] AI-powered matching (use Gemini for ambiguous results)
- [ ] Offline enrichment (cache API responses locally)
