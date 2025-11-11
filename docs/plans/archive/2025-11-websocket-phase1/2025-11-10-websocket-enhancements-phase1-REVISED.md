# WebSocket Enhancements - Phase 1 Implementation Plan (REVISED)

**Date:** November 10, 2025
**Status:** 🚧 Ready for Implementation
**Priority:** CRITICAL
**Expert Review:** Gemini 2.5 Pro via Zen MCP
**Continuation ID:** `e595f68c-4e00-4bb3-b019-41141703d68d`

## Revision Summary

**Original Plan Issues Identified:**
1. Task 2 (16h) was too massive - lumped types, factory, AND 3 pipeline migrations together
2. Batch enrichment migration was missing (plan only covered CSV/AI)
3. No iOS app lifecycle handling (backgrounding closes WebSocket connections)
4. Task ordering had dependencies backwards (Task 3 needs Task 2's types)
5. iOS resilience patterns (network monitoring, reconnect) were buried in Task 3

**Key Changes:**
- Split Task 2 into 2a/2b/2c for incremental delivery
- Moved Task 3 earlier (after types, before migrations)
- Added Task 4 for iOS resilience patterns
- Extended timeline to 5-6 days (42h vs 36h)
- Explicit batch enrichment migration

---

## Revised Timeline: 42h over 5-6 days

```
DEPENDENCY FLOW:
┌─────────────────────────────────────────────────────────────┐
│  Day 1: Task 1 (Token Auth)          [INDEPENDENT]          │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│  Day 2: Task 2a (Schema Types)       [FOUNDATION]           │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┴────────────────┐
          │                                │
┌─────────▼────────────┐      ┌───────────▼────────────────┐
│  Day 3: Task 3       │      │  Day 4: Task 2b            │
│  (DO Persistence)    │      │  (Batch Enrichment)        │
└──────────────────────┘      └───────────┬────────────────┘
                                          │
                              ┌───────────▼────────────────┐
                              │  Day 5: Task 2c            │
                              │  (CSV + AI Scanner)        │
                              └───────────┬────────────────┘
                                          │
                              ┌───────────▼────────────────┐
                              │  Day 6: Task 4             │
                              │  (iOS Resilience)          │
                              └────────────────────────────┘
```

---

## Day 1: Task 1 - Token Authentication (6h)

**Issue:** #362
**Priority:** CRITICAL (Security)
**Status:** Ready to start immediately (no dependencies)

### Problem Statement
CSV import and AI bookshelf scanner lack WebSocket authentication, creating security vulnerabilities and potential cost inflation through DDoS attacks.

### Backend Changes

#### 1.1 Update CSV Import Handler

**File:** `cloudflare-workers/api-worker/src/handlers/csv-import.js`

**Location:** After Durable Object stub creation (~line 50-60)

```javascript
// SECURITY: Generate authentication token for WebSocket connection
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

console.log(`[CSV Import] Auth token generated for job ${jobId}`);
```

**Response Update:**
```javascript
return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW: Token for WebSocket authentication
  message: 'CSV parsing started'
}, {}, 202);
```

#### 1.2 Update Bookshelf Scanner Handler

**File:** `cloudflare-workers/api-worker/src/handlers/bookshelf-scanner.js`

**Single Photo Scan (~line 100-120):**
```javascript
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW
  message: 'Scan started'
}, {}, 202);
```

**Batch Scan (~line 200-220):**
```javascript
const authToken = crypto.randomUUID();
await doStub.setAuthToken(authToken);

return createSuccessResponse({
  success: true,
  jobId,
  token: authToken,  // NEW
  totalPhotos: photos.length,
  message: 'Batch scan started'
}, {}, 202);
```

#### 1.3 Update ProgressWebSocketDO

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

**Add token storage method:**
```javascript
async setAuthToken(token) {
  await this.storage.put('authToken', token);
  // Tokens expire after 2 hours
  await this.storage.put('authTokenExpiration', Date.now() + (2 * 60 * 60 * 1000));
  console.log(`[${this.jobId}] Auth token set`);
}
```

**Update WebSocket upgrade handler:**
```javascript
async handleWebSocketUpgrade(request) {
  const url = new URL(request.url);
  const providedToken = url.searchParams.get('token');

  // Validate token
  const storedToken = await this.storage.get('authToken');
  const expiration = await this.storage.get('authTokenExpiration');

  if (!storedToken || !providedToken || storedToken !== providedToken) {
    return new Response('Unauthorized', { status: 401 });
  }

  if (Date.now() > expiration) {
    return new Response('Token expired', { status: 401 });
  }

  // ... existing WebSocket upgrade logic
}
```

### iOS Changes

#### 1.4 Update CSV Import Service

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/GeminiCSVImport/GeminiCSVImportService.swift`

**Response Struct Update (~line 20-25):**
```swift
struct CSVImportResponse: Codable, Sendable {
    let success: Bool
    let jobId: String
    let token: String  // NEW: Auth token for WebSocket
    let message: String?
}
```

**WebSocket Handler Initialization (~line 80-100):**
```swift
guard let token = response.token else {
    #if DEBUG
    print("⚠️ No auth token received - WebSocket may fail")
    #endif
    throw CSVImportError.missingToken
}

#if DEBUG
print("🔐 Auth token received: \(token.prefix(8))...")
#endif

let wsHandler = CSVWebSocketHandler(
    jobId: jobId,
    token: token,  // NEW: Pass token
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

#### 1.5 Update Bookshelf Scanner Service

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Scanner/BookshelfScannerService.swift`

**Response Struct Update (~line 15-20):**
```swift
struct ScanResponse: Codable, Sendable {
    let success: Bool
    let jobId: String
    let token: String  // NEW: Auth token for WebSocket
    let message: String?
}
```

**WebSocket Handler Initialization (~line 60-80):**
```swift
guard let token = scanResponse.token else {
    #if DEBUG
    print("⚠️ No auth token received - WebSocket may fail")
    #endif
    throw ScanError.missingToken
}

#if DEBUG
print("🔐 Auth token received for scan job: \(jobId)")
#endif

let wsHandler = ScanWebSocketHandler(
    jobId: jobId,
    token: token,  // NEW: Pass token
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

#### 1.6 Update WebSocket URL Construction

**Both handlers need URL update:**
```swift
// OLD
let url = URL(string: "\(baseURL)/ws/progress?jobId=\(jobId)")

// NEW
let url = URL(string: "\(baseURL)/ws/progress?jobId=\(jobId)&token=\(token)")
```

### Testing

**Backend Tests:**
```bash
# Test CSV import token generation
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/import/csv-gemini \
  -F "file=@docs/testImages/goodreads_library_export.csv" \
  | jq '.data.token'

# Test bookshelf scanner token generation
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/scan-bookshelf \
  -F "image=@docs/testImages/bookshelf-test.jpg" \
  | jq '.data.token'

# Test WebSocket authentication (should fail without token)
wscat -c "wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123"
# Expected: 401 Unauthorized

# Test WebSocket authentication (should succeed with token)
wscat -c "wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123&token=valid-token"
# Expected: 101 Switching Protocols
```

**iOS Tests:**
1. Settings → Library Management → AI-Powered CSV Import
2. Upload test CSV
3. Verify console logs:
   - ✅ "🔐 Auth token received: [8 chars]..."
   - ✅ "✅ WebSocket connected with authentication"
   - ✅ Progress updates received
4. Shelf tab → Capture photo
5. Verify same token flow

### Success Criteria
- [ ] CSV import endpoint generates tokens
- [ ] Bookshelf scanner endpoint generates tokens
- [ ] ProgressWebSocketDO validates tokens
- [ ] iOS CSV service uses token authentication
- [ ] iOS scanner service uses token authentication
- [ ] WebSocket connections fail with 401 if token missing/invalid
- [ ] Zero warnings in iOS build
- [ ] Manual testing confirms progress updates work

---

## Day 2: Task 2a - Schema Types & Factory (8h)

**Priority:** HIGH (Foundation for all future work)
**Status:** No pipeline changes yet - just type definitions

### Problem Statement
Current WebSocket messages lack consistency:
- Backend sends: `{type, data: {progress, status}}`
- iOS expects: `{type, processedCount, totalCount, currentTitle}`
- No support for concurrent jobs
- No versioning or pipeline identification

### Unified Schema Design

**Base Message Envelope:**
```typescript
interface WebSocketMessage {
  type: MessageType;
  jobId: string;           // Client correlation
  pipeline: PipelineType;  // Source identification
  timestamp: number;       // Server time (ms since epoch)
  version: string;         // Schema version (e.g., "1.0.0")
  payload: MessagePayload; // Type-specific data
}

type MessageType =
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"
  | "ping"
  | "pong";

type PipelineType =
  | "batch_enrichment"
  | "csv_import"
  | "ai_scan";
```

### Backend Implementation

**File:** `cloudflare-workers/api-worker/src/types/websocket-messages.ts` (NEW)

Full type definitions from original plan (lines 399-549).

**Update ProgressWebSocketDO:**

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

Add factory-based methods:
- `sendJobStarted(pipeline, payload)`
- `updateProgressV2(pipeline, payload)`
- `completeV2(pipeline, payload)`
- `sendError(pipeline, payload)`

**Backward Compatibility:**
Keep legacy `updateProgress()` method with deprecation warning.

### iOS Implementation

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/WebSocketMessages.swift` (NEW)

Full Swift types from original plan (lines 724-887).

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/GenericWebSocketHandler.swift` (NEW)

Generic handler from original plan (lines 892-1064).

### Testing

**Schema Validation Tests:**
```typescript
// Backend
describe('WebSocketMessageFactory', () => {
  it('creates valid job_started message', () => {
    const msg = WebSocketMessageFactory.createJobStarted(
      'test-job-123',
      'batch_enrichment',
      { totalCount: 50 }
    );
    expect(msg.version).toBe('1.0.0');
  });
});
```

```swift
// iOS
func testJobStartedMessageParsing() async throws {
    let json = """
    {"type":"job_started","jobId":"test-123",...}
    """
    let message = try TypedWebSocketMessage(from: json.data(using: .utf8)!)
    // Verify parsing
}
```

### Success Criteria
- [ ] TypeScript types defined and exported
- [ ] Swift Codable structs defined and tested
- [ ] Factory methods create valid messages
- [ ] iOS parses all message types correctly
- [ ] Backward compatibility maintained
- [ ] Unit tests pass (100% coverage on schema)
- [ ] No deployment yet (types only)

---

## Day 3: Task 3 - Durable Object State Persistence (6h)

**Priority:** HIGH
**Status:** Needs Task 2a types, independent of pipeline migrations

### Problem Statement
All state is in-memory only - lost on DO eviction, no recovery from restarts.

### Implementation

**File:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`

Add state management methods from original plan (lines 1207-1336):
- `initializeJobState(pipeline, totalCount)`
- `updateJobState(updates)` - Throttled (every 5 updates or 10s)
- `getJobState()`
- `completeJobState(results)`
- `failJobState(error)`
- `alarm()` - 24h cleanup

Update existing methods to persist state.

Add RPC method: `syncJobState()` for reconnecting clients.

### Testing

```javascript
describe('ProgressWebSocketDO State Persistence', () => {
  it('persists job state on initialization', async () => {
    await doStub.initializeJobState('batch_enrichment', 100);
    const state = await doStub.getJobState();
    expect(state.totalCount).toBe(100);
  });

  it('throttles state updates', async () => {
    // Send 4 updates - should not persist yet
    // 5th update triggers persistence
  });

  it('cleans up after 24 hours', async () => {
    await simulateAlarm(doStub, Date.now() + (24 * 60 * 60 * 1000));
    expect(await doStub.getJobState()).toBeNull();
  });
});
```

### Success Criteria
- [ ] Job state persisted to Durable Storage
- [ ] State survives DO evictions/restarts
- [ ] Throttling prevents excessive writes
- [ ] Cleanup alarm removes old state after 24h
- [ ] Backend tests pass

---

## Day 4: Task 2b - Pipeline Migration Part 1 (8h)

**Priority:** MEDIUM (Lower risk - internal feature)
**Status:** Needs Task 2a types

### Migrate Batch Enrichment

**Backend:**
- Update `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`
- Replace `updateProgress()` with `updateProgressV2()`
- Use factory methods for all messages
- Test with legacy iOS client (should still work via compatibility layer)

**iOS:**
- Update `EnrichmentQueue.swift`
- Replace custom WebSocket handler with `GenericWebSocketHandler`
- Handle new message types
- Update progress UI bindings

### Testing
- Deploy backend first, then iOS
- Test enrichment flow end-to-end
- Monitor for parsing errors
- Verify progress updates display correctly

### Success Criteria
- [ ] Backend sends new message format
- [ ] iOS parses and displays progress
- [ ] Legacy compatibility maintained
- [ ] Zero warnings in iOS build
- [ ] Manual testing confirms functionality

---

## Day 5: Task 2c - Pipeline Migration Part 2 (8h)

**Priority:** HIGH (User-facing features)
**Status:** Needs Task 2a types + Task 2b validation

### Migrate CSV Import & AI Scanner

**Backend:**
- `csv-import.js` - Migrate to new schema
- `bookshelf-scanner.js` - Migrate single + batch scan

**iOS:**
- `CSVImportService.swift` - Use `GenericWebSocketHandler`
- `BookshelfScannerService.swift` - Use `GenericWebSocketHandler`

### Testing
- Settings → AI-Powered CSV Import → Upload test CSV
- Shelf tab → Capture photo
- Batch scan with 3 photos
- Verify progress updates, completion messages, error handling

### Success Criteria
- [ ] CSV import uses new schema
- [ ] AI scanner uses new schema
- [ ] Batch scan uses new schema
- [ ] All progress updates display correctly
- [ ] Error messages are user-friendly
- [ ] Zero warnings in iOS build

---

## Day 6: Task 4 - iOS Resilience & Integration Testing (6h)

**Priority:** MEDIUM
**Status:** Polish and edge cases

### iOS Implementation

**Add Network Monitoring:**
```swift
import Network

@MainActor
public class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    @Published public var isConnected = true
    // Implementation from original plan (lines 1508-1527)
}
```

**Update GenericWebSocketHandler:**
- Add `connectWithRetry()` with exponential backoff (2s, 4s, 8s, 16s, 30s max)
- Add `requestStateSync()` after reconnect
- Handle app backgrounding (close connections gracefully)
- Cancel reconnection on user-initiated stop

### Integration Testing
- Toggle airplane mode during enrichment
- Background app during CSV import
- Kill backend Worker mid-job
- Test all 3 pipelines (enrichment, CSV, AI scanner)
- Verify state recovery after network restoration

### Success Criteria
- [ ] Auto-reconnect with exponential backoff
- [ ] State sync after reconnect
- [ ] Graceful handling of app backgrounding
- [ ] Network transitions handled smoothly
- [ ] All pipelines work end-to-end
- [ ] Zero warnings in iOS build

---

## Deployment Strategy

**Critical Rules:**
1. Deploy backend changes BEFORE iOS for each task
2. Test thoroughly at each boundary (don't stack changes)
3. Monitor Worker logs for token validation errors
4. Keep legacy code until all migrations verified
5. Use feature flags if possible for gradual rollout

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Schema migration breaks existing clients | HIGH | Maintain backward compatibility, gradual rollout |
| DO state persistence degrades performance | MEDIUM | Throttle writes (5 updates or 10s), monitor metrics |
| iOS auto-reconnect drains battery | MEDIUM | Cap retries at 5, exponential backoff (max 30s) |
| Token auth blocks legitimate users | HIGH | Clear error messages, 2h token expiration, retry logic |
| App backgrounding breaks long jobs | MEDIUM | Graceful connection close, state persistence for resume |

---

## Success Metrics

- ✅ Zero 401 errors from authenticated clients
- ✅ <1% message parsing failures (iOS)
- ✅ 100% state recovery after DO restart
- ✅ <2% reconnect failures
- ✅ Zero warnings in iOS build
- ✅ All tests passing (backend + iOS)

---

## Original Plan Reference

Original plan: `docs/plans/2025-11-10-websocket-enhancements-phase1.md`

**This revised plan addresses all expert-identified gaps and provides a more realistic, incremental implementation path.**
