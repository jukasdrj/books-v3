# BooksTrack Frontend Integration Guide
## iOS (SwiftUI) & Flutter Teams

**Backend:** https://api.oooefam.net (Production-Ready)
**API Version:** v1.0.0 (Canonical TypeScript Contracts)
**Documentation:** [API_README.md](API_README.md)
**GitHub Issues:** Use for cross-repo communication

---

## Current Backend Status

### Production Deployment
- **URL:** https://api.oooefam.net
- **Harvest Dashboard:** https://harvest.oooefam.net
- **CI/CD:** Automated via GitHub Actions (push to main → auto-deploy)
- **Monitoring:** Autonomous agents (cf-ops-monitor, cf-code-reviewer)

### CORS Configuration
**Current Implementation:** `src/middleware/cors.js`

**Allowed Origins:**
```javascript
ALLOWED_ORIGINS = [
  'https://bookstrack.app',           // Production web (when deployed)
  'https://www.bookstrack.app',       // Production with www
  'http://localhost:3000',            // Local web development
  'http://localhost:8080',            // Alternative local port
  'capacitor://localhost',            // iOS Capacitor
  'ionic://localhost'                 // iOS Ionic (if using Ionic framework)
]
```

**Important:** CORS currently returns `'Access-Control-Allow-Origin': 'null'` for blocked origins. Native iOS apps may not send Origin header and will work regardless.

**To Add Flutter Web Origin:**
1. Open GitHub issue in `bookstrack-backend` repo
2. Provide your Flutter web domain (e.g., `https://app.bookstrack.io`)
3. Backend team will add to `ALLOWED_ORIGINS` and deploy

### Rate Limiting
**Implementation:** KV-based token bucket (`src/middleware/rate-limiter.js`)

**Limits:** 10 requests per 60 seconds per IP

**Protected Endpoints:**
- `/api/token/refresh` - Token refresh for long-running jobs
- `/api/scan-bookshelf` - AI bookshelf scanning
- `/api/scan-bookshelf/batch` - Batch bookshelf scanning
- `/api/import/csv-gemini` - CSV import with AI parsing
- `/v1/enrichment/batch` - Batch book enrichment
- `/api/enrichment/start` - Legacy enrichment (deprecated)

**Rate Limit Headers:**
```
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 5
X-RateLimit-Reset: 1699564820000
Retry-After: 42
```

**429 Response:**
```json
{
  "error": "Rate limit exceeded. Please try again in 42 seconds.",
  "code": "RATE_LIMIT_EXCEEDED",
  "details": {
    "retryAfter": 42,
    "clientIP": "203.0.11...",
    "requestsUsed": 10,
    "requestsLimit": 10
  }
}
```

**Frontend Implementation:**
- Respect `Retry-After` header
- Show user-friendly countdown: "Too many requests. Try again in {retryAfter}s."
- Do NOT auto-retry on 429 (user must initiate)

### WebSocket Configuration
**Endpoint:** `wss://api.oooefam.net/ws/progress?jobId={uuid}`
**Durable Object:** `ProgressWebSocketDO`
**Idle Timeout:** 10 minutes (server closes connection)

**Important:** WebSocket is NOT available in local `wrangler dev`. Test against production only.

---

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend Teams                           │
│  ┌──────────────────────┐    ┌──────────────────────┐      │
│  │  iOS (SwiftUI)       │    │  Flutter (Web+Mobile)│      │
│  │  - Capacitor native  │    │  - Multi-platform    │      │
│  │  - SwiftData models  │    │  - Hive/Drift local  │      │
│  └──────────┬───────────┘    └──────────┬───────────┘      │
│             │                           │                   │
│             └───────────┬───────────────┘                   │
└─────────────────────────┼─────────────────────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │   Cloudflare Workers Backend       │
         │   https://api.oooefam.net          │
         │                                    │
         │   Rate Limit: 10 req/min per IP    │
         │   CORS: Whitelist only             │
         │                                    │
         │   Autonomous Agents:               │
         │   - cf-ops-monitor (deploy/logs)   │
         │   - cf-code-reviewer (quality)     │
         └────────────────────────────────────┘
```

---

## Phase 1: API Contracts & Foundation
**Duration:** Weeks 1-2

### Objectives
- Establish API contract understanding across both teams
- Implement basic search endpoints (title, ISBN, advanced)
- Validate DTO parsing and error handling
- Handle CORS and rate limiting
- Achieve 95%+ success rate on production API calls

### Critical Deliverables

**1. API Contract Documentation**

TypeScript → Swift Codable Mappings:
```swift
// Swift DTOs (iOS)
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: APIError?
    let meta: ResponseMetadata
}

struct WorkDTO: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let authors: [AuthorDTO]
    let primaryProvider: String
    let contributors: [String]
    let synthetic: Bool
    // ... remaining fields per API_README.md
}
```

TypeScript → Dart Class Mappings:
```dart
// Dart models (Flutter)
class APIResponse<T> {
  final bool success;
  final T? data;
  final APIError? error;
  final ResponseMetadata meta;

  APIResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJsonT);
}

class WorkDTO {
  final String id;
  final String title;
  final String? subtitle;
  final List<AuthorDTO> authors;
  final String primaryProvider;
  final List<String> contributors;
  final bool synthetic;
  // ... remaining fields
}
```

**2. CORS Setup**

**iOS Capacitor:** `capacitor://localhost` already whitelisted ✅

**Flutter Web:** Open GitHub issue with your domain:
```markdown
Title: Add Flutter web origin to CORS whitelist

Please add the following origin to ALLOWED_ORIGINS in src/middleware/cors.js:
- https://app.bookstrack.io

This is for the Flutter web frontend deployment.
```

**3. Error Code Catalog**

| Error Code | HTTP Status | User-Friendly Message | Frontend Action |
|------------|-------------|----------------------|-----------------|
| INVALID_QUERY | 400 | "Please enter a search term" | Clear input, focus field |
| INVALID_ISBN | 400 | "Invalid ISBN format (use 10 or 13 digits)" | Show ISBN format help |
| PROVIDER_ERROR | 502 | "Book search unavailable. Try again." | Show retry button |
| INTERNAL_ERROR | 500 | "Something went wrong. We've been notified." | Log error, contact support |
| RATE_LIMIT_EXCEEDED | 429 | "Too many requests. Wait {retryAfter}s." | Show countdown timer |

**4. Testing Checklist**

Week 1 - Basic Search:
- [ ] GET `/v1/search/title?q=Harry Potter` → Returns canonical Works/Editions
- [ ] GET `/v1/search/isbn?isbn=9780439708180` → Single Work with metadata
- [ ] GET `/v1/search/isbn?isbn=123` → INVALID_ISBN error (400)
- [ ] Network timeout (airplane mode) → User-friendly error message

Week 2 - Advanced & Error Handling:
- [ ] GET `/v1/search/advanced?title=1984&author=Orwell` → Combined results
- [ ] GET `/v1/search/title?q=` → INVALID_QUERY error (400)
- [ ] 10 consecutive searches → No memory leaks
- [ ] 11th request within 60s → RATE_LIMIT_EXCEEDED (429) with Retry-After header

### Success Metrics
- Both teams complete 10 successful API calls
- Error messages display user-friendly text (not raw JSON)
- Rate limit handling shows countdown timer
- No crashes on edge cases (empty responses, null fields)

---

## Phase 2: WebSocket Real-Time Progress
**Duration:** Weeks 3-4

### Objectives
- Implement WebSocket client for real-time job progress
- Handle reconnection on network interruption
- Manage app lifecycle (backgrounding, pause/resume)
- Display progress UI for batch enrichment and AI scanning
- Achieve 99%+ message delivery reliability

### Critical Deliverables

**1. WebSocket Connection Guide**

iOS (Starscream recommended):
```swift
import Starscream

class ProgressWebSocket: WebSocketDelegate {
    private var socket: WebSocket?
    private var reconnectAttempts = 0

    func connect(jobId: String) {
        var request = URLRequest(url: URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)")!)
        request.timeoutInterval = 10
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        reconnectAttempts = 0
    }

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(_):
            print("[WebSocket] Connected for job")
            reconnectAttempts = 0
        case .text(let text):
            handleProgressMessage(text)
        case .disconnected(let reason, let code):
            print("[WebSocket] Disconnected: \(reason) (\(code))")
            if code != 1000 { // 1000 = normal closure
                reconnectWithBackoff()
            }
        case .error(let error):
            print("[WebSocket] Error: \(error?.localizedDescription ?? "unknown")")
            reconnectWithBackoff()
        default:
            break
        }
    }

    private func reconnectWithBackoff() {
        guard reconnectAttempts < 3 else {
            print("[WebSocket] Max reconnect attempts reached")
            return
        }

        let delay = pow(2.0, Double(reconnectAttempts)) // 1s, 2s, 4s
        reconnectAttempts += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.socket?.connect()
        }
    }
}
```

Flutter (web_socket_channel):
```dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';

class ProgressWebSocket {
  WebSocketChannel? _channel;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  void connect(String jobId) {
    final uri = Uri.parse('wss://api.oooefam.net/ws/progress?jobId=$jobId');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (message) {
        _reconnectAttempts = 0; // Reset on successful message
        _handleProgressMessage(message);
      },
      onError: (error) {
        print('[WebSocket] Error: $error');
        _reconnectWithBackoff(jobId);
      },
      onDone: () {
        print('[WebSocket] Connection closed');
        _reconnectWithBackoff(jobId);
      },
    );
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _reconnectAttempts = 0;
  }

  void _reconnectWithBackoff(String jobId) {
    if (_reconnectAttempts >= 3) {
      print('[WebSocket] Max reconnect attempts reached');
      return;
    }

    final delay = Duration(seconds: (1 << _reconnectAttempts)); // 1s, 2s, 4s
    _reconnectAttempts++;

    _reconnectTimer = Timer(delay, () => connect(jobId));
  }
}
```

**2. Lifecycle Management**

iOS Capacitor:
```swift
// AppDelegate or SwiftUI App
NotificationCenter.default.addObserver(
    forName: UIApplication.didEnterBackgroundNotification,
    object: nil,
    queue: .main
) { _ in
    // Clean disconnect to avoid zombie connections
    progressWebSocket.disconnect()
}

NotificationCenter.default.addObserver(
    forName: UIApplication.willEnterForegroundNotification,
    object: nil,
    queue: .main
) { _ in
    // Reconnect if job still in progress
    if let jobId = currentJobId, !jobCompleted {
        progressWebSocket.connect(jobId: jobId)
    }
}
```

Flutter:
```dart
class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progressWebSocket.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      progressWebSocket.disconnect();
    } else if (state == AppLifecycleState.resumed) {
      if (currentJobId != null && !jobCompleted) {
        progressWebSocket.connect(currentJobId!);
      }
    }
  }
}
```

**3. Progress Message Types**

```json
// Type: progress
{"type": "progress", "percent": 45, "message": "Processing book 9 of 20"}

// Type: book_found (AI scanning only)
{
  "type": "book_found",
  "work": {...}, // WorkDTO
  "editions": [...], // EditionDTO[]
  "confidence": 0.92
}

// Type: complete
{"type": "complete", "totalProcessed": 20, "successful": 19, "failed": 1}

// Type: error
{"type": "error", "code": "AI_TIMEOUT", "message": "Processing timed out after 180s"}
```

**UI State Machine:**
```
connecting → processing (0-100%) → complete/error
     ↓
   failed → reconnecting (with backoff)
```

**4. Testing Against Production**

**Challenge:** No local `wrangler dev` WebSocket support
**Solution:** Test against production with test jobIds

```bash
# 1. Backend team provides test endpoint (or you can trigger yourself):
curl -X POST https://api.oooefam.net/v1/enrichment/batch \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test-ios-001","workIds":["9780439708180"]}'

# 2. Connect WebSocket immediately:
# wss://api.oooefam.net/ws/progress?jobId=test-ios-001
```

**Test Scenarios:**
- [ ] Normal completion (batch enrichment of 20 books)
- [ ] Network interruption mid-job (toggle airplane mode)
- [ ] App backgrounded during job (should disconnect/reconnect)
- [ ] Duplicate connection (server closes previous, keeps new)
- [ ] 10-minute idle timeout (server closes gracefully)
- [ ] Connection before job starts (should wait for messages)

**Debugging WebSocket Issues:**
1. Open GitHub issue with jobId and timestamp
2. Backend team uses cf-ops-monitor to analyze logs:
   ```bash
   npx wrangler tail --format=json | grep "jobId:test-ios-001"
   ```
3. Backend team reports connection status, message delivery, errors

### Success Metrics
- 99%+ message delivery (track missed updates in 100 test jobs)
- Graceful reconnection on network interruption (<5s to reconnect)
- No zombie connections (monitored by backend cf-ops-monitor)
- UI remains responsive during 25-40s AI processing

---

## Phase 3: AI-Powered Features
**Duration:** Weeks 5-6

### Objectives
- Implement bookshelf scanning with image upload
- Integrate CSV import with AI parsing
- Optimize image upload for mobile networks (4G/5G)
- Handle 25-40s AI processing with real-time progress
- Achieve 90%+ successful scan rate

### Critical Deliverables

**1. Image Upload Optimization**

**Backend Limits:**
- Max file size: 10MB (`MAX_SCAN_FILE_SIZE` in `wrangler.toml`)
- Recommended: 2-5MB for good AI accuracy
- Formats: JPEG, PNG, HEIC

iOS Compression:
```swift
import UIKit

func compressImage(_ image: UIImage) -> Data? {
    let maxWidth: CGFloat = 2048
    let scale = min(1.0, maxWidth / max(image.size.width, image.size.height))
    let newSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return resized?.jpegData(compressionQuality: 0.85) // ~2-3MB
}
```

Flutter Compression:
```dart
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<Uint8List?> compressImage(File imageFile) async {
  return await FlutterImageCompress.compressWithFile(
    imageFile.absolute.path,
    quality: 85,
    minWidth: 2048,
    minHeight: 2048,
  );
}
```

**2. Bookshelf Scanning Flow**

```
User selects photo (PHPickerViewController/image_picker)
      |
      v
Compress image to 2-3MB (JPEG 85% quality, max 2048px)
      |
      v
Generate jobId: UUID().uuidString
      |
      v
Connect WebSocket: wss://api.oooefam.net/ws/progress?jobId={uuid}
      |
      v
Upload to: POST /api/scan-bookshelf?jobId={uuid}
Content-Type: multipart/form-data
      |
      v
Show progress bar (listen to WebSocket messages)
      |
      v
Receive book_found messages (canonical WorkDTO/EditionDTO)
      |
      v
Sync to SwiftData (iOS) or local DB (Flutter)
      |
      v
Complete: Display results with confidence scores
```

**Rate Limiting:** `/api/scan-bookshelf` is rate-limited to 10 req/min. Show error if user exceeds limit.

**3. CSV Import Integration**

```swift
// iOS
func importCSV(_ fileURL: URL, jobId: String) async throws {
    let data = try Data(contentsOf: fileURL)

    var request = URLRequest(url: URL(string: "https://api.oooefam.net/api/import/csv-gemini?jobId=\(jobId)")!)
    request.httpMethod = "POST"
    request.setValue("text/csv", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    request.timeoutInterval = 60 // 1 minute upload timeout

    let (_, response) = try await URLSession.shared.data(for: request)

    // Connect WebSocket for AI parsing progress
    progressWebSocket.connect(jobId: jobId)
}
```

**Rate Limiting:** `/api/import/csv-gemini` is rate-limited to 10 req/min.

**4. Performance Targets**

| Metric | WiFi | 4G | 5G |
|--------|------|-----|-----|
| Upload time (4MB) | 3-5s | 7-10s | 4-6s |
| AI processing | 25-40s | 25-40s | 25-40s |
| Total scan time | 35-45s | 40-50s | 35-45s |
| Memory peak | <100MB | <100MB | <100MB |
| Battery impact | <2% | <3% | <2% |

### Testing Checklist
- [ ] Upload 5MB photo on WiFi → Success
- [ ] Upload 5MB photo on 4G → Success (slower but completes)
- [ ] Scan bookshelf with 10 books → Detects 8-9 ISBNs (80-90% accuracy)
- [ ] CSV with 50 books → Parses 95%+ rows correctly
- [ ] Upload during airplane mode → Timeout error with retry option
- [ ] 11 scans within 60s → Rate limit error with countdown

### Success Metrics
- 90%+ scan success rate on production
- <10s upload time on WiFi, <15s on 4G
- No memory warnings during compression
- Accurate confidence scores displayed to user

---

## Phase 4: Production Hardening
**Duration:** Weeks 7-8

### Objectives
- Implement offline-first architecture with smart caching
- Add comprehensive error handling and retry strategies
- Integrate monitoring with backend cf-ops-monitor
- Optimize performance for production workloads
- Achieve App Store/Play Store readiness

### Critical Deliverables

**1. Caching Strategy**

**What to cache:**
- Search results: 24h TTL
- Cover images: 7-day TTL (permanent once fetched)
- User library: Permanent (SwiftData/local DB)
- AI scan results: Permanent (expensive, don't re-scan)

**What NOT to cache:**
- WebSocket messages (real-time only, no replay)
- Batch job status (poll if needed, don't cache stale state)

iOS Implementation:
```swift
// URLCache for HTTP responses
let cache = URLCache(
    memoryCapacity: 50 * 1024 * 1024,    // 50MB
    diskCapacity: 500 * 1024 * 1024,      // 500MB
    diskPath: "book_cache"
)

let config = URLSessionConfiguration.default
config.urlCache = cache
config.requestCachePolicy = .returnCacheDataElseLoad

let session = URLSession(configuration: config)

// SwiftData for structured data (already implemented)
@Model
class Work {
    // Persistent local storage
}
```

Flutter Implementation:
```dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

final cacheOptions = CacheOptions(
  store: MemCacheStore(),
  policy: CachePolicy.request,
  maxStale: const Duration(days: 7),
  priority: CachePriority.high,
);

final dio = Dio()
  ..interceptors.add(DioCacheInterceptor(options: cacheOptions));
```

**2. Retry Strategies**

**Network Errors (Timeout, No Connection):**
```swift
func retryWithExponentialBackoff<T>(
    maxRetries: Int = 3,
    operation: @escaping () async throws -> T
) async throws -> T {
    var delay: UInt64 = 1_000_000_000  // 1s in nanoseconds

    for attempt in 0..<maxRetries {
        do {
            return try await operation()
        } catch {
            if attempt == maxRetries - 1 { throw error }
            try await Task.sleep(nanoseconds: delay)
            delay *= 2  // Exponential backoff: 1s → 2s → 4s
        }
    }
    fatalError("Unreachable")
}

// Usage:
let book = try await retryWithExponentialBackoff {
    try await searchBook(isbn: "9780439708180")
}
```

**Rate Limit Errors (429):**
```swift
if let httpResponse = response as? HTTPURLResponse,
   httpResponse.statusCode == 429 {
    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"

    // Show countdown: "Too many requests. Try again in {retryAfter}s."
    // DO NOT auto-retry, user must initiate

    throw RateLimitError.tooManyRequests(retryAfter: Int(retryAfter) ?? 60)
}
```

**Server Errors (5xx):**
```swift
if (500...599).contains(statusCode) {
    // Backend cf-ops-monitor likely auto-rollback in progress

    // Retry once after 5s delay
    try await Task.sleep(nanoseconds: 5_000_000_000)
    return try await operation()

    // If still failing:
    // Show: "Service temporarily unavailable. We've been notified."
}
```

**3. Monitoring Integration**

**Client-Side Telemetry:**
```swift
import OSLog

let logger = Logger(subsystem: "com.bookstrack.app", category: "network")

func logAPICall(endpoint: String, duration: TimeInterval, success: Bool, statusCode: Int?) {
    logger.info("""
        [API] \(endpoint)
        Duration: \(duration)ms
        Success: \(success)
        Status: \(statusCode ?? 0)
    """)

    // Optional: Send to Firebase/Sentry for aggregation
}
```

**Backend Coordination via GitHub Issues:**

When you encounter persistent errors:
1. Open issue in `bookstrack-backend` repo
2. Include:
   - Endpoint URL
   - Request timestamp (UTC)
   - JobId (if applicable)
   - Error message and status code
   - Network type (WiFi/4G/5G)

Backend team will:
- Use cf-ops-monitor to analyze logs
- Provide wrangler tail output
- Identify root cause and fix

**4. Launch Checklist**

Pre-Launch:
- [ ] All Phase 1-3 features tested on production
- [ ] Offline mode tested (airplane mode → graceful degradation)
- [ ] Error handling covers all documented error codes
- [ ] Performance targets met (P95 <500ms WiFi, <2s 4G)
- [ ] Privacy policy updated (AI scanning disclosure)
- [ ] Rate limit handling tested (show countdown timer)
- [ ] Backend team notified of launch date via GitHub issue

Post-Launch Monitoring (Week 1):
- [ ] Daily GitHub issue updates with crash rates
- [ ] Track API error rates (target <1%)
- [ ] Measure user drop-off during AI scans (target <10%)
- [ ] Report WebSocket disconnection rates

### Success Metrics (8-Week Target)
- **Adoption:** 100+ active users testing all features
- **Reliability:** 99%+ API success rate, 95%+ WebSocket delivery
- **Performance:** P95 search <500ms, scan completion 90%+
- **User Satisfaction:** <5% support tickets for network errors

---

## Communication Protocol

### GitHub Issues (Primary Channel)

**For CORS Updates:**
```markdown
Title: Add Flutter web origin to CORS whitelist

Please add: https://app.bookstrack.io
This is for our Flutter web deployment.
```

**For Debugging:**
```markdown
Title: WebSocket connection failing for jobId test-ios-001

**Details:**
- Endpoint: wss://api.oooefam.net/ws/progress?jobId=test-ios-001
- Timestamp: 2025-11-13T14:30:00Z
- Error: Connection closed immediately after connect
- Network: WiFi
- Platform: iOS 17.2 (Simulator)

**Expected:** Receive progress messages
**Actual:** Immediate disconnect with code 1006
```

**For Feature Requests:**
```markdown
Title: Request: Add pagination support to /v1/search/title

**Use Case:** Loading 100+ search results is slow on mobile
**Proposal:** Add ?page=1&limit=20 query parameters
**Impact:** High - affects all search operations
```

### Backend Team Responsibilities

**Backend team will:**
- Monitor GitHub issues daily
- Use cf-ops-monitor for log analysis when requested
- Provide `wrangler tail` output for debugging
- Update CORS whitelist within 24 hours
- Announce API changes 1 week ahead via GitHub issue

### Frontend Team Responsibilities

**Frontend teams should:**
- Report errors with full context (timestamp, jobId, endpoint)
- Test against production only (no local wrangler dev)
- Respect rate limits (10 req/min)
- Handle CORS errors gracefully (check allowed origins list)
- Update this doc via PR if discrepancies found

---

## API Versioning & Deprecation

### Current Versioning
- `/v1/*` endpoints: Stable, canonical format ✅
- Legacy endpoints: Still active, deprecated (see API_README.md)

### Deprecation Timeline
- **Announcement:** 4 weeks before removal (via GitHub issue)
- **Warning period:** 2 weeks with deprecation headers
- **Removal:** After 4 weeks total

### Breaking Changes
- New version created (e.g., `/v2/*`)
- Old version maintained for 4 weeks minimum
- Backend ensures backward compatibility during transition

---

## Support & Debugging

### When to Contact Backend Team (via GitHub Issue)

**Always report:**
- 5xx errors persisting >5 minutes
- Consistent WebSocket connection failures (>10% disconnect rate)
- Rate limit issues needing quota increase
- CORS errors (wrong origin or unexpected blocking)

**Consider reporting:**
- Slow response times (P95 >2s on WiFi)
- Inconsistent DTO formats (missing/extra fields)
- AI confidence scores consistently <0.5

**Don't report:**
- 429 rate limit errors (expected, user exceeded quota)
- Network timeouts on user's slow connection
- Validation errors (400) for invalid input

### Debugging Tools Available

**Backend team has access to:**
- **cf-ops-monitor:** Autonomous deployment monitoring and log analysis
- **wrangler tail:** Real-time production log streaming
- **Analytics Engine:** Performance metrics, cache hit rates
- **Health endpoint:** https://api.oooefam.net/health

### Response Times

**GitHub Issue SLA:**
- CORS updates: 24 hours
- Critical bugs (5xx errors): 4 hours
- Feature requests: 1 week
- Documentation updates: 3 days

---

## Deployment Coordination

### Backend CI/CD (Already Automated)
```
Push to main → GitHub Actions → wrangler deploy → health check
                                       ↓
                              cf-ops-monitor watches
                                       ↓
                    Auto-rollback if error rate > 5% for 5 minutes
```

### Frontend Release Cadence (Recommended)
- **iOS:** Weekly TestFlight builds, bi-weekly App Store releases
- **Flutter:** Continuous web deployment, weekly mobile builds

### Coordination Protocol
1. Backend team announces changes 1 week ahead (GitHub issue)
2. Frontend teams test against production with test data
3. Backend deploys during off-peak hours (2-4 AM UTC)
4. Frontend teams verify endpoints post-deployment
5. Report issues immediately via GitHub issue

---

## Next Steps

### Week 1 Actions

**Backend Team:**
1. Review allowed CORS origins in `src/middleware/cors.js`
2. Add Flutter web origin if provided (GitHub issue)
3. Create test jobId for WebSocket testing
4. Monitor GitHub issues for integration questions

**iOS Team:**
1. Implement Swift Codable DTOs from TypeScript contracts
2. Set up URLSession with production base URL
3. Test `/v1/search/title` endpoint
4. Validate rate limit handling (11th request)

**Flutter Team:**
1. Implement Dart models from TypeScript contracts
2. Set up http/dio package with production base URL
3. Test `/v1/search/isbn` endpoint
4. Open GitHub issue for CORS whitelist addition

### Documentation References
- **API Contracts:** [API_README.md](API_README.md)
- **Backend Architecture:** [MONOLITH_ARCHITECTURE.md](../MONOLITH_ARCHITECTURE.md)
- **Deployment Guide:** [DEPLOYMENT.md](../DEPLOYMENT.md)
- **Cover Harvest:** [COVER_HARVEST_SYSTEM.md](COVER_HARVEST_SYSTEM.md)

---

## Handoff Complete

Both iOS and Flutter teams now have accurate, production-ready integration guidance for the BooksTrack Cloudflare Workers backend.

**Backend Status:** ✅ Production-ready at https://api.oooefam.net
**Autonomous Agents:** ✅ cf-ops-monitor and cf-code-reviewer available
**Documentation:** ✅ Complete API docs in docs/API_README.md
**Communication:** ✅ GitHub Issues for cross-repo coordination

Questions? Open a GitHub issue in `bookstrack-backend` with the `frontend-integration` label.

---

**Last Updated:** November 13, 2025
**Maintained By:** AI Team (Claude Code, cf-ops-monitor, cf-code-reviewer)
**Review Cadence:** Update after any breaking API changes
