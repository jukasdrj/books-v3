# WebSocket Authentication - iOS Implementation Plan

**Date:** November 10, 2025
**Status:** 🚧 Ready for Implementation
**Priority:** HIGH (Blocks custom domain deployment)
**Estimated Effort:** 2-3 hours

## Problem Statement

Backend worker now requires authentication tokens for WebSocket connections to prevent hijacking. iOS client must be updated to:
1. Extract `token` from enrichment start response
2. Include token in WebSocket connection URL
3. Handle 401 Unauthorized errors gracefully

**Backend Changes (Deployed):**
- ✅ `ProgressWebSocketDO` validates auth tokens
- ✅ `/api/enrichment/batch` returns tokens in response
- ⚠️ CSV import and AI scanner handlers need similar updates

**iOS Changes (This Document):**
- Modify `EnrichmentAPIClient` to capture token from response
- Update `EnrichmentWebSocketHandler` to include token in URL
- Add error handling for 401 responses

---

## Current Implementation Analysis

### 1. EnrichmentAPIClient (Actor)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/EnrichmentAPIClient.swift`

**Current Response Struct:**
```swift
struct EnrichmentResult: Codable, Sendable {
    let success: Bool
    let processedCount: Int
    let totalCount: Int
    // ❌ Missing: token field
}
```

**Current Flow:**
```swift
func startEnrichment(jobId: String, books: [Book]) async throws -> EnrichmentResult {
    // ... POST to /api/enrichment/batch
    let result = envelope.data  // ❌ Doesn't capture token
    return result
}
```

### 2. EnrichmentWebSocketHandler (MainActor)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentWebSocketHandler.swift`

**Current Connection:**
```swift
func connect() async {
    guard let url = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)") else { return }
    // ❌ Missing: &token=\(token) in query params
    webSocket = session.webSocketTask(with: url)
    webSocket?.resume()
}
```

### 3. EnrichmentQueue Integration

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentQueue.swift`

**Current WebSocket Setup:**
```swift
webSocketHandler = EnrichmentWebSocketHandler(
    jobId: jobId,  // ❌ Missing: token parameter
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
await webSocketHandler?.connect()
```

---

## Implementation Plan

### Phase 1: Update Data Models (5 min)

#### 1.1 Add Token to EnrichmentResult

**File:** `EnrichmentAPIClient.swift:8-12`

```swift
struct EnrichmentResult: Codable, Sendable {
    let success: Bool
    let processedCount: Int
    let totalCount: Int
    let token: String  // NEW: Auth token for WebSocket
}
```

**Rationale:** Backend now returns `token` field in response. iOS must capture it.

---

### Phase 2: Update WebSocket Handler (15 min)

#### 2.1 Add Token Property

**File:** `EnrichmentWebSocketHandler.swift:5-20`

```swift
@MainActor
final class EnrichmentWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let token: String  // NEW: Auth token
    private let progressHandler: @MainActor (Int, Int, String) -> Void
    private let completionHandler: @MainActor ([EnrichedBookPayload]) -> Void
    private var isConnected = false

    init(
        jobId: String,
        token: String,  // NEW: Required parameter
        progressHandler: @escaping @MainActor (Int, Int, String) -> Void,
        completionHandler: @escaping @MainActor ([EnrichedBookPayload]) -> Void
    ) {
        self.jobId = jobId
        self.token = token  // NEW: Store token
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }
```

#### 2.2 Include Token in WebSocket URL

**File:** `EnrichmentWebSocketHandler.swift:23-24`

```swift
func connect() async {
    // NEW: Include token in query parameters
    guard let url = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)&token=\(token)") else { return }
    let session = URLSession(configuration: .default)
    webSocket = session.webSocketTask(with: url)
    webSocket?.resume()

    // ... rest of connection logic unchanged
}
```

#### 2.3 Handle 401 Errors

**File:** `EnrichmentWebSocketHandler.swift:30-42`

```swift
if let webSocket = webSocket {
    do {
        try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
        isConnected = true
        listenForMessages()
    } catch {
        // NEW: Check for 401 Unauthorized
        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
            #if DEBUG
            print("❌ WebSocket authentication failed: Invalid or expired token")
            #endif
        } else {
            #if DEBUG
            print("EnrichmentWebSocket connection failed: \(error)")
            #endif
        }
        isConnected = false
    }
}
```

---

### Phase 3: Update EnrichmentService (10 min)

#### 3.1 Pass Token Through Chain

**File:** `EnrichmentService.swift:100-127`

**Current:**
```swift
let result = try await apiClient.startEnrichment(jobId: jobId, books: books)
// ❌ Doesn't use result.token
```

**New:**
```swift
let result = try await apiClient.startEnrichment(jobId: jobId, books: books)

#if DEBUG
print("✅ Enrichment job accepted. Token: \(result.token.prefix(8))...")
#endif

// Store token for WebSocket connection (pass to EnrichmentQueue)
return BatchEnrichmentResult(
    successCount: 0,
    failureCount: 0,
    errors: [],
    token: result.token  // NEW: Include token in result
)
```

#### 3.2 Update BatchEnrichmentResult

**File:** `EnrichmentService.swift` (add near EnrichmentResult)

```swift
public struct BatchEnrichmentResult {
    public let successCount: Int
    public let failureCount: Int
    public let errors: [EnrichmentError]
    public let token: String?  // NEW: Optional token for WebSocket auth

    public init(successCount: Int, failureCount: Int, errors: [EnrichmentError], token: String? = nil) {
        self.successCount = successCount
        self.failureCount = failureCount
        self.errors = errors
        self.token = token
    }
}
```

---

### Phase 4: Update EnrichmentQueue (20 min)

#### 4.1 Add Token Storage

**File:** `EnrichmentQueue.swift:30-33`

```swift
private var webSocketHandler: EnrichmentWebSocketHandler?
private var currentJobId: String?
private var currentAuthToken: String?  // NEW: Store auth token
private var lastActivityTime = Date()
```

#### 4.2 Store Token After API Call

**File:** `EnrichmentQueue.swift` (in processWithAPI method - around line 262)

**Find this section:**
```swift
let result = await enrichmentService.batchEnrichWorks(works, jobId: jobId, in: modelContext)
```

**Add after:**
```swift
// NEW: Store auth token for WebSocket connection
if let token = result.token {
    self.currentAuthToken = token
    #if DEBUG
    print("🔐 Auth token stored for job: \(jobId)")
    #endif
}
```

#### 4.3 Pass Token to WebSocket Handler

**File:** `EnrichmentQueue.swift` (around line 280)

**Find:**
```swift
webSocketHandler = EnrichmentWebSocketHandler(
    jobId: jobId,
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

**Replace with:**
```swift
// NEW: Pass auth token to WebSocket handler
guard let authToken = self.currentAuthToken else {
    #if DEBUG
    print("❌ No auth token available for WebSocket connection")
    #endif
    // Fall back to old behavior (will fail with 401 on backend)
    return
}

webSocketHandler = EnrichmentWebSocketHandler(
    jobId: jobId,
    token: authToken,  // NEW: Include token
    progressHandler: progressHandler,
    completionHandler: completionHandler
)
```

#### 4.4 Clear Token on Job Completion

**File:** `EnrichmentQueue.swift` (in cleanup/defer blocks)

```swift
defer {
    self.processing = false
    self.currentTask = nil
    self.currentJobId = nil
    self.currentAuthToken = nil  // NEW: Clear token
    NotificationCoordinator.postEnrichmentCompleted()
}
```

---

## Error Handling Strategy

### 1. Missing Token (Backward Compatibility)

**Scenario:** Backend hasn't returned token yet (gradual rollout)

**Handling:**
```swift
guard let authToken = self.currentAuthToken else {
    #if DEBUG
    print("⚠️ No auth token - backend may not support authentication yet")
    #endif
    // Could: Retry without token or show user error
    // For now: Log and fail gracefully
    return
}
```

### 2. 401 Unauthorized from WebSocket

**Scenario:** Token expired or invalid

**Handling:**
```swift
// In EnrichmentWebSocketHandler.connect()
catch let urlError as URLError where urlError.code == .userAuthenticationRequired {
    #if DEBUG
    print("❌ WebSocket authentication failed - token may be expired")
    #endif
    // Could: Request new token and retry
    // For now: Log and disconnect
}
```

### 3. Token in URL Query Params

**Security Note:** Tokens in URLs are visible in logs. For production, consider:
- Using WebSocket subprotocols (pass token in `Sec-WebSocket-Protocol` header)
- Short-lived tokens (10 min expiration already implemented)

**Current approach is acceptable because:**
- Tokens are single-use per job
- 10-minute expiration
- HTTPS encrypts URLs in transit
- iOS logs are sandboxed

---

## Testing Checklist

### Unit Tests

- [ ] `EnrichmentAPIClient` decodes token from response
- [ ] `EnrichmentWebSocketHandler` includes token in URL
- [ ] `EnrichmentQueue` stores and passes token correctly

### Integration Tests

- [ ] End-to-end enrichment with token authentication
- [ ] WebSocket connection succeeds with valid token
- [ ] WebSocket connection fails with invalid token (401)
- [ ] WebSocket connection fails with missing token (401)

### Manual Testing

```bash
# 1. Start local worker
cd cloudflare-workers/api-worker
npx wrangler dev

# 2. Run iOS app in simulator
# 3. Trigger enrichment (import CSV or add books manually)
# 4. Verify in console:
#    - ✅ "Auth token stored for job: ..."
#    - ✅ "WebSocket connection accepted"
#    - ✅ Progress updates received
```

### Staging Testing

```bash
# 1. Deploy backend to staging
npx wrangler deploy --env staging

# 2. Point iOS to staging URL
# Update EnrichmentConfig.baseURL

# 3. Test with TestFlight build
# 4. Verify Cloudflare logs show token validation
npx wrangler tail api-worker --env staging | grep "Token validated"
```

---

## Rollback Plan

If issues arise after deployment:

### Option 1: Make Token Optional (Quick Fix)

**Backend Change:**
```javascript
// In progress-socket.js:fetch()
const token = url.searchParams.get('token');
const storedToken = await this.storage.get('authToken');

// Allow if NO stored token (legacy) OR token matches
if (!storedToken || (token && token === storedToken)) {
  // Allow connection
}
```

### Option 2: Revert iOS Changes

1. Revert to previous commit
2. Deploy iOS update
3. Investigation continues offline

---

## Dependencies

### Backend (Already Deployed)
- ✅ `ProgressWebSocketDO.setAuthToken()` method
- ✅ `/api/enrichment/batch` returns token
- ⚠️ CSV import handler needs token generation
- ⚠️ AI scanner handler needs token generation

### iOS (This Implementation)
- 🚧 `EnrichmentAPIClient` token field
- 🚧 `EnrichmentWebSocketHandler` token parameter
- 🚧 `EnrichmentQueue` token storage and passing

---

## Success Criteria

- [ ] iOS app compiles with zero warnings
- [ ] All existing tests pass
- [ ] New tests for token handling pass
- [ ] Manual testing shows WebSocket authentication works
- [ ] No 401 errors in production logs after deployment
- [ ] Enrichment progress updates still work correctly

---

## Timeline

| Phase | Estimated Time | Status |
|-------|---------------|--------|
| Update data models | 5 min | 🚧 Pending |
| Update WebSocket handler | 15 min | 🚧 Pending |
| Update EnrichmentService | 10 min | 🚧 Pending |
| Update EnrichmentQueue | 20 min | 🚧 Pending |
| Write tests | 30 min | 🚧 Pending |
| Manual testing | 30 min | 🚧 Pending |
| **Total** | **~2 hours** | 🚧 Pending |

---

## Related Documentation

- Backend Implementation: `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js:52-71`
- Security Report: `docs/plans/2025-11-10-security-hardening-report.md`
- WebSocket Helpers: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/WebSocketHelpers.swift`

---

## Notes

- Token-based auth is BREAKING change - requires coordinated deployment
- Consider gradual rollout: Make token optional for 2 weeks, then required
- CSV import and AI scanner need similar updates (separate tasks)
- Custom domain deployment blocked until this is complete

---

**Author:** Claude Code
**Reviewers:** iOS Team, Backend Team
**Approval Required:** Yes (Security-critical change)
