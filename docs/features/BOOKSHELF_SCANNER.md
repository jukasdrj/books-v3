# Bookshelf AI Camera Scanner

**Status:** ✅ SHIPPING (Build 46+)
**Swift Version:** 6.1
**iOS Version:** 26.0+
**Last Updated:** October 2025

## Overview

The Bookshelf Scanner uses device camera + multi-model AI (Gemini Flash, LLaVA, Qwen, Llama Vision) to analyze photos of bookshelves and automatically extract book titles/authors for library import. Users can choose between 4 AI models optimizing for speed vs accuracy.

## Quick Start

```swift
// SettingsView - Experimental Features
Button("Scan Bookshelf (Beta)") { showingBookshelfScanner = true }
    .sheet(isPresented: $showingBookshelfScanner) {
        BookshelfScannerView()
    }
```

## Key Files

### Camera Layer
- `BookshelfCameraSessionManager.swift` - AVFoundation session management
- `BookshelfCameraViewModel.swift` - UI state and camera lifecycle
- `BookshelfCameraPreview.swift` - UIViewRepresentable camera preview
- `BookshelfCameraView.swift` - SwiftUI camera interface

### API Layer
- `BookshelfAIService.swift` - Cloudflare Worker communication

### UI Layer
- `BookshelfScannerView.swift` - Main scanner interface
- `ScanResultsView.swift` - Review and import UI

## Architecture: Swift 6.1 Global Actor Pattern

### Global Actor Declaration

```swift
@globalActor
actor BookshelfCameraActor {
    static let shared = BookshelfCameraActor()
}
```

**Why Global Actor?** Plain `actor` isolation prevents cross-actor access patterns required for camera session management. Global actors enable controlled sharing across isolation domains.

### Camera Session Manager

```swift
@BookshelfCameraActor
final class BookshelfCameraSessionManager {
    // Trust Apple's thread-safety guarantee for read-only access
    nonisolated(unsafe) private let captureSession = AVCaptureSession()

    nonisolated init() {}  // Cross-actor instantiation

    func startSession() async -> AVCaptureSession {
        // Configure camera, video input, photo output
        // Returns session for MainActor preview layer configuration
    }

    func capturePhoto(flashMode: FlashMode) async throws -> Data {
        // ✅ Returns Sendable Data (not UIImage!)
        // MainActor creates UIImage from Data
    }
}
```

### Critical Patterns

**1. Global Actor (not plain actor)**
- Required for cross-isolation access
- Enables MainActor to receive AVCaptureSession reference
- Maintains actor isolation safety

**2. nonisolated(unsafe)**
- Trusts AVCaptureSession's documented thread-safety
- Read-only access pattern safe per Apple documentation
- Eliminates unnecessary async overhead

**3. @preconcurrency import**
```swift
@preconcurrency import AVFoundation
```
- Suppresses Sendable warnings for AVFoundation types
- Apple hasn't marked these types Sendable yet
- Safe per Apple's thread-safety guarantees

**4. Data Bridge Pattern**
```swift
// ❌ WRONG: UIImage is not Sendable
func capturePhoto() async throws -> UIImage

// ✅ CORRECT: Data is Sendable
func capturePhoto() async throws -> Data

// MainActor creates UIImage from Data
let imageData = try await cameraManager.capturePhoto(flashMode: .auto)
let uiImage = UIImage(data: imageData)
```

**5. Task Wrapper for Actor Calls**
```swift
// From MainActor view to BookshelfCameraActor
let session = try await Task { @BookshelfCameraActor in
    await cameraManager.startSession()
}.value
```

## AVFoundation Configuration Order

**⚠️ CRITICAL:** Configuration order matters! Wrong order causes runtime crashes.

```swift
// ❌ WRONG: Crashes with activeFormat error
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
captureSession.addOutput(output)

// ✅ CORRECT: Add to session FIRST, then configure
captureSession.addOutput(output)
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
```

**Why?** AVCaptureDevice's activeFormat is only valid after session configuration. Setting maxPhotoDimensions before adding output to session accesses invalid state.

## User Journey

```
Settings → Scan Bookshelf → Camera Button
    ↓
Camera permissions (AVCaptureDevice.requestAccess)
    ↓
Live preview (AVCaptureVideoPreviewLayer)
    ↓
Capture → Review sheet → "Use Photo"
    ↓
Upload to api-worker with selected AI model
    ↓
AI analysis (3-40s depending on model):
  - Gemini Flash: 25-40s (highest accuracy)
  - LLaVA 1.5: 5-12s (balanced)
  - Qwen/UForm: 3-8s (fastest)
  - Llama 3.2 Vision: 8-15s (accurate)
    ↓
Backend enrichment via direct function calls (5-10s)
    ↓
ScanResultsView → Review results
    ↓
Add books to SwiftData library
```

## Backend Integration

### Monolith Architecture (October 2025)

**All bookshelf AI traffic flows through unified `api-worker.jukasdrj.workers.dev`:**

**Endpoint:**
- `POST /api/scan-bookshelf?jobId={uuid}` - Upload image for AI processing
- `GET /ws/progress?jobId={uuid}` - WebSocket for real-time progress (unified for ALL jobs)

**Flow:**
1. iOS generates `jobId = UUID().uuidString`
2. iOS connects to WebSocket: `/ws/progress?jobId={uuid}`
3. iOS uploads image to `/api/scan-bookshelf?jobId={uuid}` (triggers background processing)
4. Worker processes image with Gemini AI (internal function call)
5. Worker enriches detected books via internal search functions (no RPC!)
6. Real-time progress pushed via WebSocket (8ms latency)
7. iOS displays results in real-time

**Architecture Changes:**
- **No polling endpoints** - Removed `/scan/status/{jobId}`, `/scan/ready/{jobId}`
- **WebSocket-only status** - Single ProgressWebSocketDO handles all background jobs
- **Direct function calls** - AI scanner internally calls search handlers (no RPC service bindings)

**Internal Processing Flow:**
```
api-worker/api/scan-bookshelf
    ↓
services/ai-scanner.js
    ├─→ callGeminiVision() - External API call to Gemini
    └─→ handlers/search-handlers.js - Direct function call (no network!)
            └─→ services/external-apis.js - Google Books + OpenLibrary
```

**See:** `cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md` for monolith architecture details.

### Enrichment Integration (Build 49 - October 2025)

Backend enrichment system (89.7% success rate) fully integrated:

**Response Model (BookshelfAIService.swift):**
```swift
struct DetectedBook: Codable, Sendable {
    let title: String
    let author: String?
    let confidence: Double?           // Direct field from Gemini AI
    let enrichmentStatus: String?     // Backend enrichment tracking
    let coverUrl: String?             // Enriched cover URLs
}
```

**Conversion Logic:**
```swift
// Maps enrichment status to detection states
switch enrichmentStatus {
case "ENRICHED", "FOUND":
    state = .detected
case "UNCERTAIN", "NEEDS_REVIEW":
    state = .uncertain
case "REJECTED":
    state = .rejected
default:
    state = .detected  // Graceful fallback
}
```

**Timeout Configuration:**
- Total timeout: 70 seconds
- AI analysis: 25-40 seconds
- Backend enrichment: 5-10 seconds
- Buffer: 15-20 seconds

### Background Enrichment Queue

All scanned books automatically queued for metadata enrichment:

```swift
// ScanResultsView.addAllToLibrary()
let workIds = createdWorks.map(\.persistentModelID)
await EnrichmentQueue.shared.addMultiple(workIds)
```

- Uses shared `EnrichmentQueue.shared` (same system as CSV import)
- Silent background processing
- Progress shown via `EnrichmentProgressBanner` in ContentView
- See Issue #16 for implementation details

## Suggestions Banner System

**Purpose:** AI-generated actionable guidance for improving photo quality

**Suggestion Types (9 total):**
- `unreadable_books` - Some books couldn't be read
- `low_confidence` - Uncertain detections
- `edge_cutoff` - Books cut off at frame edge
- `blurry_image` - Photo out of focus
- `glare_detected` - Lighting reflection issues
- `distance_too_far` - Camera too far from shelf
- `multiple_shelves` - Frame multiple shelves (confusing)
- `lighting_issues` - Poor lighting conditions
- `angle_issues` - Perspective/angle problems

**Architecture: Hybrid Approach**
1. **AI-First:** Backend worker generates contextual suggestions
2. **Client Fallback:** `SuggestionGenerator.swift` provides fallback logic
3. **Unified Display:** `SuggestionViewModel.swift` with templated messages

**Key Files:**
- `SuggestionGenerator.swift` - Client-side fallback logic
- `SuggestionViewModel.swift` - Display logic and templated messages
- `ScanResultsView.swift:suggestionsBanner()` - Liquid Glass banner UI

**Individual Dismissal Pattern:**
```swift
Button("Got it") {
    dismissedSuggestions.insert(suggestion.type)
}
```

## Privacy & Permissions

**Camera Permission:**
- Required: `NSCameraUsageDescription` in Info.plist
- Runtime request: `AVCaptureDevice.requestAccess(for: .video)`

**Photo Processing:**
- Photos uploaded to Cloudflare AI Worker for analysis
- Not stored permanently
- Processed via Gemini 2.5 Flash API
- Results cached temporarily for enrichment

## Critical iOS Background Behavior ⚠️

**IMPORTANT: Idle Timer Management**

iOS bookshelf scans take 25-40 seconds (Gemini AI processing). **The device MUST stay awake** or iOS will kill the app with Signal 9 (SIGKILL).

**Implementation (v3.0.1):**
```swift
// BookshelfScanModel.processImage()
func processImage(_ image: UIImage) async {
    // Disable idle timer to prevent device sleep during AI processing
    UIApplication.shared.isIdleTimerDisabled = true
    print("🔒 Idle timer disabled - device won't sleep during scan")

    do {
        let (books, suggestions) = try await BookshelfAIService.shared.processBookshelfImageWithWebSocket(image) { ... }

        // Re-enable on success
        UIApplication.shared.isIdleTimerDisabled = false
    } catch {
        // CRITICAL: Re-enable on error (prevent battery drain)
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
```

**Why This Matters:**
- WebSocket connections **cannot persist in background** on iOS
- `beginBackgroundTask()` only gives ~30s (risky for 25-40s operations)
- Background URLSession only supports upload/download, NOT WebSockets
- User workflow: Capture photo → Lock phone → **iOS kills app at ~30s**

**Solution: Disable Idle Timer**
- Pattern used by GPS navigation, video recording
- Device stays awake during foreground AI processing
- Properly reset on completion/error to prevent battery drain
- User sees "Keep app open during analysis (25-40s)" message

**Batch Scans:**
- Same pattern applied to `BatchCaptureModel.submitBatch()`
- Can take 2-5 minutes for 5 photos (25-40s each)
- Idle timer re-enabled when `BatchProgress.isComplete == true`

**Files:**
- `BookshelfScannerView.swift:460-511` - Single scan idle timer
- `BatchCaptureView.swift:64-114` - Batch scan idle timer

---

## Testing

**Test Images:**
- `docs/testImages/IMG_0014.jpeg` - 2 unreadable books (tests suggestion system)
- Clear shelf images should produce no suggestions
- Low-light images trigger `lighting_issues` suggestion

**Critical Test Scenarios (v3.0.1):**
1. **Signal 9 Prevention:** Capture photo → Lock device immediately → Wait 40s → Unlock → ✅ Results shown
2. **Batch Stability:** 5 photos → Submit → Lock device → Wait 3min → Unlock → ✅ All processed
3. **Error Recovery:** Start scan → Airplane mode mid-scan → ✅ Idle timer re-enabled

**Quality Checks:**
- Swift 6.1 concurrency compliance: Zero warnings
- Actor isolation correctness: All boundaries checked
- Sendable conformance: Data types properly marked
- Real device testing: iPhone 17 Pro (iOS 26.0.1)
- **Idle timer lifecycle:** Verified re-enabled on all exit paths

## Common Patterns

### Camera Lifecycle Management

```swift
struct BookshelfScannerView: View {
    @State private var cameraManager: BookshelfCameraSessionManager?

    func startCamera() async {
        if cameraManager == nil {
            cameraManager = await BookshelfCameraSessionManager()
        }
        await cameraManager?.startSession()
    }

    func cleanup() {
        Task {
            await cameraManager?.stopSession()
            cameraManager = nil
        }
    }
}
```

### Photo Capture & Conversion

```swift
// Capture on BookshelfCameraActor
let photoData = try await cameraManager.capturePhoto(flashMode: .auto)

// Convert on MainActor
await MainActor.run {
    if let image = UIImage(data: photoData) {
        capturedImage = image
    }
}
```

### API Communication

```swift
let service = BookshelfAIService()
let results = try await service.analyzeBookshelf(image: uiImage)

// Process results
for detected in results {
    let work = Work(
        title: detected.title,
        publicationYear: nil
    )
    modelContext.insert(work)
}
```

## Lessons Learned (Build 46 Development)

### Swift 6.1 Concurrency

**Lesson:** Global actors solve cross-isolation camera access patterns that plain actors cannot handle.

**Context:** Initial implementation used plain `actor BookshelfCameraActor`. This prevented MainActor views from receiving AVCaptureSession references needed for preview layer configuration.

**Solution:** Switched to `@globalActor`, enabling controlled sharing while maintaining isolation safety.

### AVFoundation Configuration

**Lesson:** Always add outputs to session BEFORE configuring output properties.

**Context:** Setting `maxPhotoDimensions` before adding output to session accessed `device.activeFormat` in invalid state, causing crashes.

**Solution:** Strict configuration order enforced in documentation and code comments.

### Data Sendability

**Lesson:** Return `Data` from actors, create `UIImage` on MainActor.

**Context:** UIImage is not Sendable, causing compiler errors when returned from actor methods.

**Solution:** Actor returns `Data` (Sendable), MainActor creates UIImage from data.

## WebSocket Keep-Alive Architecture

**Problem:** Long-running AI processing (25-40s) caused WebSocket timeouts:
- iOS URLSession default: 60s timeout
- Cloudflare Durable Objects: 100s idle timeout

**Symptom:** `NSURLErrorDomain error -1011` after ~30 seconds, WebSocket closes with code 1006.

**Solution:** Server-side keep-alive pings during blocking operations.

### Backend Implementation

```javascript
// cloudflare-workers/bookshelf-ai-worker/src/index.js
const keepAlivePingInterval = setInterval(async () => {
  await pushProgress(env, jobId, {
    progress: 0.3,
    currentStatus: 'Processing with AI...',
    keepAlive: true  // Flag for client optimization
  });
}, 30000);  // Every 30 seconds

try {
  const result = await worker.scanBookshelf(imageData);  // 25-40s
  clearInterval(keepAlivePingInterval);
} catch (error) {
  clearInterval(keepAlivePingInterval);
  throw error;
}
```

### Client Optimization

```swift
// BooksTrackerPackage/Sources/.../BookshelfAIService.swift
wsManager.setProgressHandler { jobProgress in
    // Skip UI updates for keep-alive pings
    guard jobProgress.keepAlive != true else {
        print("🔁 Keep-alive ping received (skipping UI update)")
        return
    }
    progressHandler(jobProgress.fractionCompleted, jobProgress.currentStatus)
}
```

### Data Models

```swift
// ProgressData - WebSocket message payload
struct ProgressData: Codable, Sendable {
    let progress: Double
    let processedItems: Int
    let totalItems: Int
    let currentStatus: String
    let keepAlive: Bool?  // nil for normal updates, true for pings
}

// JobProgress - Client-side progress tracking
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var keepAlive: Bool?
}
```

### Performance

- 📊 Keep-alive pings: 1-2 per scan (30s interval)
- 📦 Overhead: ~200 bytes per ping
- 🔋 Battery impact: Negligible

## Hybrid WebSocket + Polling Fallback

**Problem:** WebSocket connections may fail on:
- Weak cellular networks
- Corporate firewalls
- Proxy servers
- Network handoffs (WiFi ↔ Cellular)

**Solution:** Automatic fallback from WebSocket to HTTP polling.

### Implementation

```swift
func processBookshelfImageWithWebSocket(...) async throws {
    do {
        // Try WebSocket first (8ms latency, preferred)
        return try await processViaWebSocket(...)
    } catch {
        // Fall back to HTTP polling (2s interval, reliable)
        return try await processViaPolling(...)
    }
}
```

### Performance

- **WebSocket:** 8ms latency, single connection
- **Polling:** 2s intervals, 15-30 HTTP requests
- **Fallback rate:** < 5% of scans

### Code Structure

**BookshelfAIService.swift:**
- `processBookshelfImageWithWebSocket()` - Public API with fallback wrapper
- `processViaWebSocket()` - WebSocket implementation
- `processViaPolling()` - HTTP polling implementation (extension)

**ProgressStrategy.swift:**
- Enum tracking which strategy was used (`.webSocket` or `.polling`)
- Analytics integration

### Analytics Tracking

```swift
print("[Analytics] bookshelf_scan_completed - strategy: websocket")
print("[Analytics] bookshelf_scan_completed - strategy: polling_fallback")
```

**See:** `docs/features/WEBSOCKET_FALLBACK_ARCHITECTURE.md` for complete architecture details.

### Testing

```swift
@Test("processBookshelfImageWithWebSocket skips keepAlive progress updates")
@MainActor
func testWebSocketSkipsKeepAliveUpdates() async throws {
    // Simulates 5 progress updates (2 keep-alive pings)
    // Verifies only 3 non-keepAlive updates trigger UI
}
```

## WebSocket Ready Handshake (Race Condition Fix)

**Problem:** Server processed images immediately after upload, before WebSocket connection established, causing lost progress updates.

**Symptom:** Scan appeared frozen, no progress updates for first 2-3 seconds, eventual timeout.

**Solution:** Server-side ready signal handshake - processing blocked until iOS confirms WebSocket ready.

### Implementation

**iOS Client Flow:**
1. Generate `jobId`
2. Connect WebSocket to `/ws/progress?jobId={uuid}`
3. **Send "ready" message** after connection established
4. Wait for "ready_ack" from server
5. Upload image to `/api/scan-bookshelf?jobId={uuid}`
6. Receive real-time progress (guaranteed listening)

**Server Flow:**
1. Receive image upload
2. Get Durable Object stub for `jobId`
3. **Call `doStub.waitForReady(5000)`** - blocks until ready or timeout
4. Start background processing with `ctx.waitUntil()`
5. Send progress updates via WebSocket (client guaranteed ready)

### Code References

**Durable Object (progress-socket.js:10-170):**
- `waitForReady(timeoutMs)` - RPC method to await ready signal
- `isReady` flag - tracks client readiness state
- `readyPromise` - Promise resolved when "ready" message received

**API Handler (index.js:217-230):**
```javascript
const readyResult = await doStub.waitForReady(5000);
if (readyResult.timedOut) {
  console.warn("WebSocket ready timeout, proceeding with polling fallback");
}
ctx.waitUntil(aiScanner.processBookshelfScan(...));
```

**iOS Client (BookshelfAIService.swift:157-170):**
```swift
try await wsManager.establishConnection(jobId: jobId)
try await wsManager.sendReadySignal() // NEW: Ready handshake
let response = try await uploadImage(imageData, jobId: jobId)
```

### Timeout Handling

**5-second timeout** for ready signal:
- Prevents hanging if iOS client fails to send ready
- Allows fallback to polling for older clients
- Logs analytics event for monitoring

### Metrics

- 📊 Ready signal latency: < 100ms typical
- ⏱️ Timeout rate: < 1% (network issues)
- 🔋 Battery impact: Negligible (one extra WebSocket message)

## Completion Metadata

When the scan completes successfully (progress === 1.0), the final WebSocket message includes detailed metadata:

```json
{
  "progress": 1.0,
  "processedItems": 3,
  "totalItems": 3,
  "currentStatus": "Scan complete",
  "jobId": "6AEBDC6E-1F9B-4D20-BE59-84AF61AF8264",
  "result": {
    "totalDetected": 3,
    "approved": 2,
    "needsReview": 1,
    "books": [...],
    "metadata": {
      "processingTime": 42350,
      "enrichedCount": 3,
      "timestamp": "2025-10-27T10:30:45.123Z",
      "modelUsed": "gemini-2.0-flash-exp"
    }
  }
}
```

**Fields:**
- `processingTime`: Total milliseconds from image upload to completion
- `enrichedCount`: Number of books successfully enriched with OpenLibrary metadata
- `timestamp`: ISO 8601 completion timestamp
- `modelUsed`: AI model name (always "gemini-2.0-flash-exp" in current version)

**iOS Usage:**

```swift
if let metadata = result.metadata {
    print("Scan completed in \(metadata.processingTime)ms using \(metadata.modelUsed)")
    print("Enriched \(metadata.enrichedCount)/\(result.totalDetected) books")
}
```

## Future Enhancements

See [GitHub Issue #16](https://github.com/jukasdrj/books-tracker-v1/issues/16) for planned iOS 26 HIG enhancements:
- Haptic feedback on detection
- Improved error states
- Enhanced accessibility labels
- Progress indicators during upload/analysis

---

## Related Documentation

- **Product Requirements:** `docs/product/Bookshelf-Scanner-PRD.md` - Problem statement, user stories, success metrics
- **Workflow Diagrams:** `docs/workflows/bookshelf-scanner-workflow.md` - Visual flows (user journey, batch mode, WebSocket progress)
- **Batch Scanning:** `docs/features/BATCH_BOOKSHELF_SCANNING.md` - Multi-photo scanning
- **Review Queue:** `docs/features/REVIEW_QUEUE.md` - Low-confidence detection handling
- **WebSocket Architecture:** `docs/WEBSOCKET_ARCHITECTURE.md` - Real-time progress implementation
- **Backend Code:** `cloudflare-workers/api-worker/src/services/ai-scanner.js` - Gemini integration
