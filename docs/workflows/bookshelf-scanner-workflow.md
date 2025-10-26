# Bookshelf Scanner Workflow

**Feature:** AI-Powered Bookshelf Camera Scanner
**Technology:** Gemini 2.0 Flash (2M token context window)
**Primary Flow:** User photographs bookshelf → AI detects books → Review & import
**Last Updated:** October 2025

---

## User Journey Flow

```mermaid
flowchart TD
    Start([User Opens Shelf Tab]) --> ModeCheck{Scanning Mode?}

    ModeCheck -->|Single Photo| SingleMode[Single Photo Mode Active]
    ModeCheck -->|Batch Mode| BatchMode[Batch Mode Active - 5 photos max]

    SingleMode --> RequestPermission{Camera Permission?}
    BatchMode --> RequestPermission

    RequestPermission -->|Not Determined| ShowPermissionPrompt[Request AVCaptureDevice access]
    RequestPermission -->|Denied| ShowSettings[Show 'Enable in Settings' message]
    RequestPermission -->|Authorized| ShowCamera[Display live camera preview]

    ShowPermissionPrompt --> PermissionResponse{User Response}
    PermissionResponse -->|Granted| ShowCamera
    PermissionResponse -->|Denied| ShowSettings

    ShowCamera --> UserCapture[User taps capture button]
    UserCapture --> ShowReview[Show preview sheet]

    ShowReview --> ReviewChoice{User Action?}
    ReviewChoice -->|Retake| ShowCamera
    ReviewChoice -->|Use Photo| ProcessPhoto

    ProcessPhoto --> Preprocess[iOS: Resize to 3072px @ 90% quality]
    Preprocess --> CheckBatch{Batch Mode?}

    CheckBatch -->|No - Single| UploadSingle[Upload to /api/scan-bookshelf]
    CheckBatch -->|Yes| AddToQueue[Add to batch queue]

    AddToQueue --> MorePhotos{Captured < 5 photos?}
    MorePhotos -->|Yes| ShowCamera
    MorePhotos -->|No| UploadBatch[Upload to /api/scan-bookshelf/batch]

    UploadSingle --> ConnectWS[Connect WebSocket /ws/progress]
    UploadBatch --> ConnectWS

    ConnectWS --> WSConnected{WebSocket Status}
    WSConnected -->|Connected| StreamProgress[Stream real-time progress]
    WSConnected -->|Failed| FallbackPolling[Fallback to HTTP polling]

    StreamProgress --> AIProcessing[Gemini 2.0 Flash Analysis - 25-40s]
    FallbackPolling --> AIProcessing

    AIProcessing --> EnrichBooks[Backend enriches metadata - 5-10s]
    EnrichBooks --> ReceiveResults[Receive DetectedBook array]

    ReceiveResults --> ShowResults[Display ScanResultsView]

    ShowResults --> ConfidenceCheck{For each book}
    ConfidenceCheck -->|Confidence ≥ 60%| AutoVerify[Import as .verified]
    ConfidenceCheck -->|Confidence < 60%| NeedsReview[Import as .needsReview]

    AutoVerify --> AddToLibrary[Create Work + UserLibraryEntry]
    NeedsReview --> AddToReviewQueue[Add to Review Queue]

    AddToLibrary --> QueueEnrichment[Queue for background enrichment]
    AddToReviewQueue --> AddToLibrary

    QueueEnrichment --> ShowBanner[Show EnrichmentProgressBanner]
    ShowBanner --> Complete([Scan Complete])

    ShowSettings --> End([User Exits])
    ReviewChoice -->|Cancel| End
```

---

## Batch Scanning Flow (5 Photos Max)

```mermaid
sequenceDiagram
    participant User
    participant iOS
    participant R2Storage
    participant Worker
    participant GeminiAI
    participant WebSocket

    Note over User,WebSocket: Batch Mode Enabled

    User->>iOS: Capture Photo 1
    iOS->>iOS: Preprocess (3072px, 90%)
    iOS->>iOS: Add to batch queue [1/5]

    User->>iOS: Capture Photo 2
    iOS->>iOS: Add to batch queue [2/5]

    Note over User: User can capture up to 5 photos

    User->>iOS: Tap "Process Batch"
    iOS->>WebSocket: Connect to /ws/progress?jobId={uuid}

    par Parallel Upload
        iOS->>R2Storage: Upload Photo 1
        iOS->>R2Storage: Upload Photo 2
        iOS->>R2Storage: Upload Photo 3
    end

    iOS->>Worker: POST /api/scan-bookshelf/batch
    Note over Worker: Sequential Processing

    loop For Each Photo
        Worker->>R2Storage: Fetch photo
        Worker->>GeminiAI: Analyze image
        GeminiAI-->>Worker: Detected books JSON
        Worker->>Worker: Enrich metadata
        Worker->>WebSocket: Push progress (photo 1/3 complete)
        WebSocket-->>iOS: Real-time update
        iOS->>User: Update progress bar
    end

    Worker->>Worker: Deduplicate by ISBN
    Worker-->>iOS: Combined results (all photos)
    iOS->>User: Show ScanResultsView with all books
```

---

## WebSocket Progress State Machine

```mermaid
stateDiagram-v2
    [*] --> Connecting

    Connecting --> Connected : WebSocket handshake success
    Connecting --> Polling : WebSocket failed (fallback)

    Connected --> Uploading : POST /api/scan-bookshelf
    Uploading --> AIAnalyzing : Upload complete (progress: 0.1)

    AIAnalyzing --> Enriching : Gemini returned results (progress: 0.5)
    AIAnalyzing --> KeepAlive : 30s timeout (ping)

    KeepAlive --> AIAnalyzing : Continue processing

    Enriching --> Complete : Metadata enriched (progress: 1.0)

    Polling --> Uploading : Fallback active
    Polling --> Complete : Poll interval 2s

    Complete --> [*]

    note right of KeepAlive
        Server sends keepAlive: true
        every 30s to prevent timeout
    end note
```

---

## Review Queue Integration

```mermaid
flowchart LR
    Results[Scan Results] --> CheckConfidence{For each book}

    CheckConfidence -->|≥60%| HighConf[High Confidence]
    CheckConfidence -->|<60%| LowConf[Low Confidence]

    HighConf --> SetVerified[work.reviewStatus = .verified]
    LowConf --> SetNeedsReview[work.reviewStatus = .needsReview]

    SetNeedsReview --> StoreMetadata[Store originalImagePath + boundingBox]
    StoreMetadata --> SaveWork[Insert Work into SwiftData]

    SetVerified --> SaveWork

    SaveWork --> UserReview[User opens Review Queue]
    UserReview --> CropImage[CorrectionView shows cropped spine]
    CropImage --> UserEdit{User Action}

    UserEdit -->|Edit title/author| MarkEdited[reviewStatus = .userEdited]
    UserEdit -->|No changes| MarkVerified[reviewStatus = .verified]

    MarkEdited --> CleanupCheck[Check if all books from scan reviewed]
    MarkVerified --> CleanupCheck

    CleanupCheck -->|Yes| DeleteImage[Delete temp image file on next launch]
    CleanupCheck -->|No| KeepImage[Keep image for other books]
```

---

## Key Components

| Component | Responsibility | File |
|-----------|---------------|------|
| **BookshelfScannerView** | Main UI coordinator | `BookshelfScannerView.swift` |
| **BookshelfCameraSessionManager** | AVFoundation camera session | `BookshelfCameraSessionManager.swift` (@BookshelfCameraActor) |
| **BookshelfAIService** | API client for scan endpoint | `BookshelfAIService.swift:837` |
| **WebSocketProgressManager** | Real-time progress tracking | `WebSocketProgressManager.swift` |
| **ScanResultsView** | Results display & import | `ScanResultsView.swift` |
| **ReviewQueueView** | Low-confidence book review | `ReviewQueueView.swift` |
| **ImageCleanupService** | Automatic temp file cleanup | `ImageCleanupService.swift` |

---

## Error Handling

```mermaid
flowchart TD
    Error[Error Occurred] --> ErrorType{Error Type}

    ErrorType -->|Camera Permission Denied| ShowPermSettings[Alert: 'Enable camera in Settings']
    ErrorType -->|WebSocket Timeout| FallbackPoll[Automatic fallback to HTTP polling]
    ErrorType -->|Upload Failed| RetryUpload[Show retry button - 3 attempts]
    ErrorType -->|AI Analysis Failed| ShowErrorMsg[Alert: 'AI analysis failed - try different angle']
    ErrorType -->|Network Offline| ShowOffline[Alert: 'No internet connection']

    ShowPermSettings --> UserAction{User Choice}
    UserAction -->|Open Settings| LaunchSettings[UIApplication.openSettingsURL]
    UserAction -->|Cancel| ExitFlow[Return to Shelf tab]

    RetryUpload --> AttemptCount{Retry < 3?}
    AttemptCount -->|Yes| RetryAPI[Re-attempt upload]
    AttemptCount -->|No| ShowFatalError[Alert: 'Upload failed - check connection']

    FallbackPoll --> PollStatus[Poll /scan/status every 2s]
    PollStatus --> CheckComplete{Status = complete?}
    CheckComplete -->|Yes| ReturnResults[Show ScanResultsView]
    CheckComplete -->|No| PollStatus

    ShowErrorMsg --> UserRetry{Retry?}
    UserRetry -->|Yes| ReturnToCamera[Return to camera]
    UserRetry -->|No| ExitFlow
```

---

## Performance Optimizations

1. **iOS Preprocessing:** Resize to 3072px @ 90% quality (400-600KB)
2. **WebSocket Keep-Alive:** 30s pings prevent timeout during 25-40s AI processing
3. **Automatic Fallback:** Switches to HTTP polling if WebSocket fails (<5% fallback rate)
4. **Batch Parallel Upload:** Upload 5 photos concurrently to R2, process sequentially
5. **Temp File Cleanup:** Automatic deletion after all books from scan reviewed

---

## Data Flow (iOS → Backend)

```mermaid
graph LR
    A[UIImage] -->|jpegData 90%| B[Data 400-600KB]
    B -->|URLRequest| C[POST /api/scan-bookshelf]
    C -->|FormData| D[Cloudflare Worker]
    D -->|Base64 encode| E[Gemini Vision API]
    E -->|JSON response| F[DetectedBook array]
    F -->|Enrich metadata| G[Search handlers]
    G -->|Push via WebSocket| H[JobProgress updates]
    H -->|URLSessionWebSocketTask| I[iOS UI update]
```

---

## Related Documentation

- **Feature Documentation:** `docs/features/BOOKSHELF_SCANNER.md`
- **Batch Scanning:** `docs/features/BATCH_BOOKSHELF_SCANNING.md`
- **Review Queue:** `docs/features/REVIEW_QUEUE.md`
- **WebSocket Architecture:** `docs/WEBSOCKET_ARCHITECTURE.md`
- **Backend Implementation:** `cloudflare-workers/api-worker/src/services/ai-scanner.js`

---

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| AI Accuracy (≥60% confidence) | 80%+ | 70-95% (varies by shelf clarity) |
| Processing Time | <60s | 25-40s (AI) + 5-10s (enrichment) |
| WebSocket Success Rate | >95% | ~95% (5% fallback to polling) |
| User Retention (complete scan) | >70% | TBD (analytics pending) |

---

## Future Enhancements

- [ ] Multi-shelf stitching (panorama mode)
- [ ] Real-time detection (live viewfinder overlay)
- [ ] Confidence threshold customization (user setting)
- [ ] Export detected books as CSV
- [ ] Apple Watch remote shutter control
