# BooksTrack API Contract v2.4.1

**Status:** Production ✅
**Effective Date:** November 20, 2025
**Last Updated:** November 20, 2025 (v2.4.1 - WebSocket Performance Optimization)
**Contract Owner:** Backend Team
**Audience:** iOS, Flutter, Web Frontend Teams

---

## 🔥 What's New in v2.4.1 (WebSocket Performance Optimization)

### **⚡ PERFORMANCE: WebSocket Hibernation API (Issue #221)**
- **Change:** Backend migrated to Cloudflare Hibernation WebSocket API
- **Impact:** Zero user-facing changes - API contract unchanged
- **Benefits:**
  - 70-80% reduction in Durable Object costs
  - Automatic memory management (sleep/wake cycles between messages)
  - Improved scalability for high-traffic scenarios
- **Backward Compatibility:** 100% compatible - all message formats unchanged
- **Action Required:** None - transparent backend optimization

**Technical Details:**
- WebSocket connections now use `state.acceptWebSocket()` with automatic hibernation
- State management migrated to Durable Storage (zero in-memory state)
- Message delivery remains identical (same timing, same formats)
- Authentication flow unchanged (see v2.3 for secure subprotocol header method)

**See:** Section 7 (WebSocket API) - no changes to client integration

---

## What's New in v2.4 (P1 Fixes: Image Quality + HATEOAS Links)

### **🔗 NEW: HATEOAS Search Links (Issue #196)**
- **Feature:** All WorkDTO and EditionDTO responses now include optional `searchLinks` field
- **Purpose:** Backend centralizes URL construction - clients just follow links (no URL building logic needed)
- **Providers:** Google Books, OpenLibrary, Amazon
- **Impact:** Fixes iOS "View on Google Books" crash, eliminates duplicated URL logic across platforms
- **Breaking Change:** None - field is optional, backward compatible

**Example Response:**
```json
{
  "title": "The Great Gatsby",
  "searchLinks": {
    "googleBooks": "https://www.googleapis.com/books/v1/volumes?q=isbn:9780743273565",
    "openLibrary": "https://openlibrary.org/isbn/9780743273565",
    "amazon": "https://www.amazon.com/s?k=9780743273565"
  }
}
```

### **📊 IMPROVED: Provider-Agnostic Image Quality Detection (Issue #195)**
- **Fix:** `X-Image-Quality` header now accurate for OpenLibrary/ISBNdb covers (not just Google Books)
- **Method:** Dimension-based detection via HTTP HEAD requests with URL heuristics fallback
- **Caching:** Image dimensions cached for 24h to minimize external calls
- **Impact:** More accurate quality metrics across all providers

**See:** Section 5.1 (WorkDTO) and 5.2 (EditionDTO) for `searchLinks` schema.

---

## ⚠️ BREAKING CHANGE: v2.0 Summary-Only Completion Payloads (Nov 15, 2025)

### **🔥 CRITICAL: WebSocket `job_complete` Schema Migration**

**Status:** ⚠️ **BREAKING CHANGE - Action Required**
**Effective Date:** November 15, 2025 (v2.0)
**Impact:** All WebSocket clients (iOS, Flutter, Web)
**Migration Deadline:** January 15, 2026 (60 days)

> **🚨 HOTFIX AVAILABLE (Nov 20, 2025):** iOS app crashes on `job_complete` due to missing `expiresAt` field.
> **Quick Fix:** Make `expiresAt` optional in Swift decoders: `public let expiresAt: String?`
> **Details:** See `/docs/IOS_HOTFIX_V2_SCHEMA.md` for complete backward-compatible fix.

---

### **What Changed**

WebSocket `job_complete` messages now use a **summary-only format** for mobile optimization. Full results are retrieved via HTTP GET instead of being sent in the WebSocket payload.

**OLD Format (deprecated):**
```json
{
  "payload": {
    "type": "job_complete",
    "pipeline": "csv_import",
    "books": [...],        // ❌ No longer sent (could be 5-10 MB)
    "errors": [...],       // ❌ No longer sent
    "successRate": "45/50" // ❌ No longer sent
  }
}
```

**NEW Format (v2.0+):**
```json
{
  "payload": {
    "type": "job_complete",
    "pipeline": "csv_import",
    "summary": {           // ✅ New lightweight summary
      "totalProcessed": 48,
      "successCount": 48,
      "failureCount": 0,
      "duration": 394,
      "resourceId": "job-results:uuid-12345"  // ✅ Key for HTTP fetch
    },
    "expiresAt": "2025-11-22T03:28:45.382Z"   // ✅ 24h expiry timestamp
  }
}
```

---

### **Why This Change**

**Problem:** Large WebSocket payloads (5-10 MB) caused:
- UI freezes on mobile devices (10+ seconds parsing time)
- Battery drain from JSON parsing
- Memory pressure on low-end devices
- Cloudflare 32 MiB message limit concerns

**Solution:** Send lightweight summary (< 1 KB), store full results in KV cache with 1-hour TTL

---

### **Migration Guide: iOS Swift**

**Step 1: Update Completion Payload Structs**

Replace old structs with new summary-based structs:

```swift
// ✅ NEW: Job Completion Summary (shared across all pipelines)
public struct JobCompletionSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int           // Milliseconds
    public let resourceId: String?     // KV key for HTTP fetch (e.g., "job-results:uuid")
}

// ✅ NEW: CSV Import Completion (Summary-Only)
public struct CSVImportCompletePayload: Codable, Sendable {
    public let type: String            // "job_complete"
    public let pipeline: String        // "csv_import"
    public let summary: JobCompletionSummary  // ✅ Changed from direct fields
    public let expiresAt: String?      // 🚨 HOTFIX: Make optional for backward compatibility
}

// ✅ NEW: Batch Enrichment Completion (Summary-Only)
public struct BatchEnrichmentCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: JobCompletionSummary
    public let expiresAt: String?      // 🚨 HOTFIX: Make optional for backward compatibility
}

// ✅ NEW: AI Scan Completion (Summary-Only with AI-specific stats)
public struct AIScanCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: AIScanSummary  // Extended summary
    public let expiresAt: String?      // 🚨 HOTFIX: Make optional for backward compatibility
}

// ✅ NEW: AI Scan Summary (extends JobCompletionSummary)
public struct AIScanSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int
    public let resourceId: String?

    // AI-specific stats
    public let totalDetected: Int?
    public let approved: Int?
    public let needsReview: Int?
}
```

**Step 2: Update WebSocket Message Handler**

```swift
func handleJobComplete(_ message: WebSocketMessage) async {
    guard case .jobComplete(let payload) = message.payload else { return }

    // Extract pipeline-specific payload
    switch payload {
    case .csvImport(let csvPayload):
        // ✅ NEW: Use summary instead of direct fields
        let summary = csvPayload.summary
        print("CSV import complete: \(summary.successCount)/\(summary.totalProcessed) books")

        // ✅ NEW: Fetch full results via HTTP if needed
        if let resourceId = summary.resourceId {
            await fetchJobResults(jobId: message.jobId)
        }

    case .batchEnrichment(let batchPayload):
        let summary = batchPayload.summary
        print("Batch enrichment complete: \(summary.successCount) books enriched")

        if let resourceId = summary.resourceId {
            await fetchJobResults(jobId: message.jobId)
        }

    case .aiScan(let aiPayload):
        let summary = aiPayload.summary
        print("AI scan complete: \(summary.totalDetected ?? 0) books detected")

        if let resourceId = summary.resourceId {
            await fetchJobResults(jobId: message.jobId)
        }
    }
}
```

**Step 3: Implement HTTP Results Fetching**

```swift
func fetchJobResults(jobId: String) async throws -> JobResults {
    let url = URL(string: "https://api.oooefam.net/v1/jobs/\(jobId)/results")!

    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw JobError.resultsFetchFailed
    }

    // Decode full results (books, errors, etc.)
    let envelope = try JSONDecoder().decode(ResponseEnvelope<JobResults>.self, from: data)

    guard envelope.success, let results = envelope.data else {
        throw JobError.invalidResults
    }

    return results
}

struct JobResults: Codable {
    let books: [ParsedBook]?
    let errors: [ImportError]?
    let enrichedBooks: [EnrichedBookPayload]?
}
```

---

### **Migration Checklist**

- [ ] Update all `*CompletePayload` structs to use `summary` field
- [ ] Remove direct fields: `books`, `errors`, `successRate`, `enrichedBooks`, etc.
- [ ] Add `JobCompletionSummary` struct
- [ ] Add `AIScanSummary` struct (for AI-specific stats)
- [ ] Implement HTTP results fetching via `/v1/jobs/{jobId}/results`
- [ ] Handle `expiresAt` timestamp (show countdown timer if needed)
- [ ] Update UI to show summary stats during WebSocket, full results after HTTP fetch
- [ ] Test with all three pipelines: `csv_import`, `batch_enrichment`, `ai_scan`

---

### **Affected Endpoints**

**WebSocket Messages:**
- `job_complete` for `csv_import` pipeline
- `job_complete` for `batch_enrichment` pipeline
- `job_complete` for `ai_scan` pipeline

**New HTTP Endpoints (for results retrieval):**
- `GET /v1/jobs/{jobId}/results` - Fetch full job results (1-hour TTL)

**Not Affected:**
- `batch-complete` (batch photo scanning still includes full book array)
- `job_progress` messages (unchanged)
- `job_started` messages (unchanged)
- All HTTP search/enrichment endpoints (unchanged)

---

### **Timeline**

- **Nov 15, 2025:** Breaking change deployed (v2.0)
- **Nov 20, 2025:** Migration guide published (this document)
- **Jan 15, 2026:** Migration deadline (clients MUST migrate by this date)
- **Jan 16, 2026:** Old format support removed (clients will fail to decode)

---

## What's New in v2.3 (WebSocket Security Fix)

### **🔒 SECURITY FIX: WebSocket Token Authentication (Issue #163)**
- **Problem:** Tokens passed in URL query parameters leaked in server logs, browser history, and network traffic
- **Solution:** New authentication via `Sec-WebSocket-Protocol` header (secure, not logged)
- **Backward Compatibility:** OLD method (query param) still works but deprecated
- **Migration Required:** Clients should migrate to new method within 90 days
- **Impact:** Critical security improvement - tokens no longer visible in logs

**NEW (Secure):**
```javascript
const ws = new WebSocket(url, ['bookstrack-auth.TOKEN_HERE'])
```

**OLD (Deprecated):**
```javascript
const ws = new WebSocket(`${url}?jobId=xxx&token=yyy`)  // ⚠️ INSECURE
```

**See:** Section 3.1 for complete migration guide with iOS, Web, and Flutter examples.

---

## What's New in v2.2 (Hono Router Complete)

This update documents the **complete Hono router migration** and new default routing behavior:

### **Router Migration (Week 2 - COMPLETE)**
- ✅ **12/12 Endpoints Migrated:** All API endpoints now available in Hono router
- ✅ **Hono Default Enabled:** `ENABLE_HONO_ROUTER != 'false'` (opt-out model)
- ✅ **New Endpoints Added:** `/v1/scan/results/{jobId}`, `/v1/csv/results/{jobId}`, `/POST /api/batch-scan`
- ✅ **Security Hardening:** Input validation (200-char limits), CORS whitelist, error handler tests
- 📊 **Performance Headers:** `X-Router: hono`, `X-Response-Time: {ms}ms` for monitoring

### **New: OpenAPI 3.0.3 Specification (Section 1.4)**
- 📄 **Machine-readable spec available:** [`docs/openapi.yaml`](./openapi.yaml)
- 🔧 **Use cases:** Client SDK generation, Postman import, contract testing, API validation
- ✅ **Production-ready:** All 12 endpoints + WebSocket + 13 message types fully documented
- 🔄 **Sync status:** Kept in sync with this contract on every update

### **New Section 2.1: Router Architecture**
- Feature flag documentation (`ENABLE_HONO_ROUTER`)
- Client detection via `X-Router` header
- Input validation limits (DoS prevention)
- CORS policy details (native app support)
- Rate limiting architecture
- Testing instructions

### **Breaking Changes:** None
- Both routers produce identical responses
- Manual router still available via `ENABLE_HONO_ROUTER=false`
- Rollback time: < 60 seconds via environment variable

### **Previous Update (v2.1 - Issue #67)**
- 7 New WebSocket message types (`ready`, `ready_ack`, `reconnected`, + batch)
- Reconnection support (Section 7.5) with 60-second grace period
- Batch photo scanning (Section 7.6) - 1-5 photos with progress tracking
- Token refresh: ✅ Production Ready (automatic)

**Action Required:**
- Review **Section 2.1** for router architecture and feature flag behavior
- Monitor `X-Router` header in responses (should be `hono` by default)
- No client code changes required (response formats unchanged)

---

## 1. Contract Authority

### 1.1 Source of Truth

This document is the **single source of truth** for the BooksTrack API. All frontend implementations MUST conform to this contract. Any discrepancies between this contract and other documentation should be reported to the backend team immediately.

### 1.2 Change Management

**Breaking Changes:**
- Backend provides **90 days notice** before introducing breaking changes
- Deprecated endpoints remain functional for **180 days** minimum
- All breaking changes will be versioned (e.g., v2 → v3)

**Non-Breaking Changes:**
- Optional fields may be added without notice
- New endpoints may be added without notice
- Performance improvements do not require frontend changes

**Emergency Changes:**
- Security-critical changes may be deployed with **24 hours notice**
- Frontend teams will be notified via email and Slack

### 1.3 Versioning

**Current Version:** `v2.4.1`
**API Version Header:** `X-API-Version: 2.4.1` (optional)
**URL Versioning:** `/v1/*` endpoints (implements v2.x contract), `/v2/*` endpoints (reserved for future breaking changes)

**Version Support Policy:**
- `v1.*` (legacy endpoints like `/search/title`): Deprecated, sunset March 1, 2026
- `v2.*` (new endpoints under `/v1/*` path): Current version (production ready)
- `v3.*`: Not yet planned

**IMPORTANT:** URL path `/v1/*` implements API contract v2.x (not v1.x). The path name is for URL stability while the contract version evolves.

### 1.4 Machine-Readable Specification

**OpenAPI 3.0.3 Specification:** [`docs/openapi.yaml`](./openapi.yaml)

A complete OpenAPI specification is available for programmatic API consumption:

- **Format:** OpenAPI 3.0.3 (YAML)
- **Coverage:** All 12 HTTP endpoints, WebSocket endpoint, complete DTO schemas, all 13 WebSocket message types
- **Use Cases:**
  - Generate client SDKs (iOS, Flutter, web)
  - Import into API development tools (Postman, Insomnia, Paw)
  - Validate requests/responses programmatically
  - Generate API documentation (Swagger UI, Redoc)
  - Contract testing with Pact or Dredd
- **Sync Status:** Kept in sync with this contract document on every update
- **Last Updated:** November 18, 2025 (v2.2)

**Relationship to this document:**
- This `API_CONTRACT.md` is the **human-readable source of truth**
- `openapi.yaml` is the **machine-readable equivalent**
- In case of discrepancies, this document takes precedence (report immediately to backend team)

**Quick Start:**
```bash
# Import into Postman
curl https://api.oooefam.net/docs/openapi.yaml | pbcopy

# Generate TypeScript client
npx @openapitools/openapi-generator-cli generate \
  -i docs/openapi.yaml \
  -g typescript-fetch \
  -o src/generated/api-client

# Validate your requests
npx @stoplight/spectral-cli lint docs/openapi.yaml
```

---

## 2. Base URLs

| Environment | Base URL | WebSocket URL |
|-------------|----------|---------------|
| **Production** | `https://api.oooefam.net` | `wss://api.oooefam.net/ws/progress` |
| **Staging** | `https://staging-api.oooefam.net` | `wss://staging-api.oooefam.net/ws/progress` |
| **Local Dev** | `http://localhost:8787` | `ws://localhost:8787/ws/progress` |

**TLS Requirements:**
- Production: TLS 1.2+ required
- Staging: TLS 1.2+ required
- Local: HTTP allowed for development only

---

## 2.1 Router Architecture (Feature Flag)

**Status:** ✅ **Production Ready** (Hono Router Default as of Week 2)

### Feature Flag: `ENABLE_HONO_ROUTER`

BooksTrack supports two routing implementations for zero-downtime migration:

| Router | Status | Feature Flag | Performance Headers | Default |
|--------|--------|--------------|---------------------|---------|
| **Hono Router** | ✅ Production | `ENABLE_HONO_ROUTER != 'false'` | `X-Router: hono`, `X-Response-Time: {ms}ms` | **Yes (Week 2+)** |
| **Manual Router** | Legacy (Opt-Out) | `ENABLE_HONO_ROUTER = 'false'` | None | No |

**Default Behavior (Week 2+):**
- Hono router is **enabled by default** unless explicitly disabled
- Set `ENABLE_HONO_ROUTER=false` in environment to use legacy manual router
- Rollback time: **< 60 seconds** via environment variable update

**Migration Timeline:**
- ✅ **Week 1 (Complete):** Hono router opt-in, 9/12 endpoints migrated
- ✅ **Week 2 (Current):** Security hardening, 12/12 endpoints, **default enabled**
- 🔄 **Week 3 (Planned):** Monitor production, deprecate manual router
- 🔄 **Week 4 (Planned):** Remove manual router code entirely

### Client Detection

**Detecting Which Router Handled Request:**

```http
HTTP/1.1 200 OK
X-Router: hono
X-Response-Time: 145ms
Content-Type: application/json
```

**Headers:**
- **`X-Router: hono`**: Request was handled by Hono router
- **`X-Response-Time: {ms}ms`**: Processing time (Hono only)
- **No `X-Router` header**: Request was handled by manual router (legacy)

**Client Usage:**
```swift
// Swift example - detect router
if let router = response.value(forHTTPHeaderField: "X-Router") {
    print("Router used: \(router)")  // "hono"
}

if let responseTime = response.value(forHTTPHeaderField: "X-Response-Time") {
    print("Processing time: \(responseTime)")  // "145ms"
}
```

### Input Validation Limits (Hono Router)

The Hono router enforces **input length limits** to prevent DoS attacks:

| Parameter | Limit | Behavior | Endpoint |
|-----------|-------|----------|----------|
| `q` (search query) | 200 chars | Silent truncation | `/v1/search/title` |
| `title` | 200 chars | Silent truncation | `/v1/search/advanced` |
| `author` | 200 chars | Silent truncation | `/v1/search/advanced` |
| `jobId` | 100 chars | Silent truncation | `/ws/progress`, `/v1/*/results/{jobId}` |
| `isbn` | No limit | Regex validation (ISBN-10/13) | `/v1/search/isbn` |

**Note:** Input is truncated **silently** without error. This prevents excessively long queries from causing performance issues.

### CORS Policy (Hono Router)

**Function-Based Origin Validation:**

```javascript
// Allowed origins
const allowedOrigins = [
  'https://bookstrack.oooefam.net',   // Production web app
  'https://harvest.oooefam.net',       // Harvest dashboard
  'capacitor://localhost',              // iOS app (Capacitor)
  'http://localhost:3000',              // Local dev (web)
  'http://localhost:8787'               // Local dev (wrangler)
]

// Requests without Origin header are allowed (native iOS/Android apps)
```

**CORS Headers:**
```http
Access-Control-Allow-Origin: https://bookstrack.oooefam.net
Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Expose-Headers: X-Router, X-Response-Time
Access-Control-Max-Age: 86400
```

**Native App Support:**
- Requests **without `Origin` header** are allowed (native iOS/Android apps)
- iOS Capacitor apps use `capacitor://localhost` origin
- Android apps typically send no `Origin` header

### Rate Limiting (Durable Objects)

Rate limiting is enforced via **Durable Objects** (not router-specific):

**Implementation:**
- Rate limiting logic is in Durable Object (shared across both routers)
- Hono router uses middleware wrapper: `rateLimitMiddleware`
- Manual router calls rate limiter directly

**Endpoints with Rate Limiting:**
- `POST /v1/enrichment/batch` - 10 requests/minute per IP
- `POST /api/scan-bookshelf/batch` - 5 requests/minute per IP
- `POST /api/import/csv-gemini` - 5 requests/minute per IP
- `POST /api/batch-scan` - 5 requests/minute per IP

### Testing the Router

**Local Development:**
```bash
# Test with Hono router (default)
npx wrangler dev

# Test with manual router (opt-out)
ENABLE_HONO_ROUTER=false npx wrangler dev

# Verify router via headers
curl -I http://localhost:8787/health | grep X-Router
```

**Production Testing:**
```bash
# Check which router is active
curl -I https://api.oooefam.net/health | grep X-Router

# Expected: X-Router: hono (Week 2+)
```

---

## 3. Authentication & Authorization

### 3.1 WebSocket Authentication

**Token-Based Auth:** Required for all WebSocket connections.

**SECURITY FIX (Issue #163):** Token authentication method changed to prevent token leakage.

**NEW METHOD (Secure) - Recommended:**
Use WebSocket Subprotocol header to pass token (tokens NOT visible in logs/history):
```
wss://api.oooefam.net/ws/progress?jobId={jobId}
Sec-WebSocket-Protocol: bookstrack-auth.{TOKEN}
```

**OLD METHOD (Deprecated) - Backward Compatible:**
Pass token in URL query parameter (⚠️ INSECURE - leaks tokens in logs):
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**Token Lifecycle:**
1. **Obtain Token:** POST endpoints return `{ jobId, token }` in response
2. **Connect (NEW):** Pass token via `Sec-WebSocket-Protocol: bookstrack-auth.{token}` header
3. **Connect (OLD):** Pass token in URL query param `&token={token}` (deprecated)
4. **Expiration:** Tokens expire after **2 hours** (7200 seconds)
5. **Refresh:** Available within **30-minute window** before expiration

**Token Refresh:**

**Status:** ✅ **Production Ready** (automatic, no client action required)

**Implementation:** Token refresh is handled **automatically by the Durable Object** when the connection is active and approaching expiration (within 30 minutes of expiry).

**Backend Implementation:**
- **Alarm System:** Durable Object schedules alarms every 15 minutes to check token expiration
- **Refresh Window:** Automatic refresh triggers when token has < 30 minutes remaining
- **Method:** `scheduleTokenRefreshCheck()` in `progress-socket.js:698`
- **Auto-Refresh:** `autoRefreshToken()` generates new token and extends expiration by 2 hours
- **Token Storage:** New tokens stored in KV with `authToken` and `authTokenExpiration` keys
- **Token Blacklist:** Old tokens blacklisted with 2.5-hour TTL to prevent reuse
- **Conflict Prevention:** Token refresh alarms delayed if job processing alarm is active (single alarm per DO)

**Refresh Window:**
- Tokens are **automatically refreshed** in the last 30 minutes before expiration
- No client-side code needed - handled server-side via Durable Object alarms
- New token extends expiration by another 2 hours from refresh time
- Client receives updated token via internal state (transparent)
- Old token blacklisted but usable during 5-minute grace period for reconnections

**Client Implementation Examples:**

**iOS (Swift):**
```swift
// NEW METHOD (Secure - Recommended)
let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)")!
let request = URLRequest(url: url)
request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
let webSocket = URLSession.shared.webSocketTask(with: request)

// OLD METHOD (Deprecated - Backward Compatible)
let url = URL(string: "wss://api.oooefam.net/ws/progress?jobId=\(jobId)&token=\(token)")!
let webSocket = URLSession.shared.webSocketTask(with: url)
```

**JavaScript/Web:**
```javascript
// NEW METHOD (Secure - Recommended)
const ws = new WebSocket(
  `wss://api.oooefam.net/ws/progress?jobId=${jobId}`,
  [`bookstrack-auth.${token}`]
);

// OLD METHOD (Deprecated - Backward Compatible)
const ws = new WebSocket(
  `wss://api.oooefam.net/ws/progress?jobId=${jobId}&token=${token}`
);
```

**Flutter/Dart:**
```dart
// NEW METHOD (Secure - Recommended)
final channel = WebSocketChannel.connect(
  Uri.parse('wss://api.oooefam.net/ws/progress?jobId=$jobId'),
  protocols: ['bookstrack-auth.$token']
);

// OLD METHOD (Deprecated - Backward Compatible)
final channel = WebSocketChannel.connect(
  Uri.parse('wss://api.oooefam.net/ws/progress?jobId=$jobId&token=$token')
);
```

**Token Refresh (Automatic):**
```swift
// NO CLIENT ACTION REQUIRED
// The Durable Object automatically extends tokens for active WebSocket connections
// Clients only need to handle token expiration if connection is idle for 2+ hours
```

**Security Notes:**
- Automatic refresh only works for **active WebSocket connections**
- Disconnected clients can reconnect with old token during auto-refresh (5-minute grace period)
- Expired tokens cannot be refreshed (must start new job)

### 3.2 CORS (Cross-Origin Resource Sharing)

**Policy:** Specific origins only (NOT wildcard `*`)

**Allowed Origins:**
- `https://bookstrack.oooefam.net` - Production frontend
- `capacitor://localhost` - iOS/Android Capacitor apps
- `http://localhost:8787` - Local development

**Implementation:** `src/middleware/cors.js`

**Headers Set:**
```
Access-Control-Allow-Origin: {allowed-origin}
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
```

**Preflight Requests:** OPTIONS requests return `204 No Content` with CORS headers

**WebSocket CORS:** WebSocket connections follow same origin policy (validated in Durable Object)

### 3.3 HTTP Headers

**Required Headers:**
- `Content-Type: application/json` - Required for POST/PUT requests with body

**Optional Headers:**
- `Authorization: Bearer {token}` - For future authentication (not currently enforced)
- `User-Agent` - Recommended for analytics/debugging
- `X-Request-ID` - Optional correlation ID for request tracking

**Response Headers:**
All API responses include:
- `Content-Type: application/json`
- `X-Request-ID` - Correlation ID (if provided in request)
- `X-Response-Time` - Server-side processing time in milliseconds

**WebSocket-Specific Headers:**
- `Sec-WebSocket-Protocol: bookstrack-auth.{token}` - Authentication (see 3.1)
- `Upgrade: websocket` - Protocol upgrade
- `Connection: Upgrade`

### 3.4 Rate Limiting

**Global Limits:**
- **1000 requests/hour** per IP address
- **Burst:** 50 requests/minute

**Endpoint-Specific Limits:**
- Search endpoints (`/v1/search/*`): **100 requests/minute** per IP
- Batch enrichment (`/api/enrichment/start`): **10 requests/minute** per IP
- **AI batch scanning (`/api/batch-scan`)**: **5 requests/minute** per IP
  - **Important:** Limit applies per batch request, not per photo
  - Example: 4 photos in 1 batch = 1 request counted
  - Each batch can contain up to 5 photos

**⚠️ IMPORTANT: Common Confusion Clarification**

**"50 photos" is NOT a limit!** The number "50" appears in documentation as:
- **50 MB** - Total batch size limit (5 photos × 10 MB each)
- **50 seconds** - Max processing time (5 photos × 10s each)

**The actual photo limit is 5 photos per batch**, NOT 50.

---

**Batch Scan Rate Limit FAQ:**

Q: If I send 5 photos in a batch, does that count as 5 requests?
A: No, it counts as **1 request** (per-batch, not per-photo).

Q: What happens if I exceed the 5 requests/minute limit?
A: You receive HTTP 429 with `Retry-After` header indicating seconds to wait.

Q: Can I send multiple batches in parallel?
A: Yes, but all requests within a 60-second window count toward the 5/minute limit.

Q: How do I scan more than 5 photos at once?
A: Split into multiple batches. For 20 photos: send 4 batches of 5 photos each (respects 5 req/min limit = ~1 minute total).

Q: Why is the limit 5 photos and not more?
A: AI processing time (Gemini 2.0 Flash) takes ~10 seconds per photo. 5 photos = 50 seconds max, within Cloudflare Workers' 60-second CPU limit.

**Rate Limit Headers:**
```http
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 3
X-RateLimit-Reset: 1700000060
Retry-After: 45
```

**Rate Limit Exceeded (429 Response):**
```json
{
  "error": "Rate limit exceeded. Please try again in 45 seconds.",
  "code": "RATE_LIMIT_EXCEEDED",
  "details": {
    "retryAfter": 45,
    "clientIP": "192.168.1...",
    "requestsRemaining": 0,
    "requestsLimit": 5
  }
}
```

**Example: Batch Scan Rate Limit Response**
```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 45
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1700000060

{
  "error": "Rate limit exceeded. Please try again in 45 seconds.",
  "code": "RATE_LIMIT_EXCEEDED",
  "details": {
    "retryAfter": 45,
    "clientIP": "192.168.1...",
    "requestsRemaining": 0,
    "requestsLimit": 5
  }
}
```

### 3.2.1 WebSocket Connection Limits

**Purpose:** Prevent resource exhaustion and ensure fair allocation of Durable Object resources.

**Concurrent Connections:**
- **5 connections per job** (per Durable Object instance)
- Each job gets its own Durable Object, so total system capacity is unbounded
- Limit applies per-job to prevent single job from monopolizing DO resources

**Limit Exceeded Behavior:**

When the 6th connection attempt is made to the same job, the client receives:

1. **WebSocket Error Message:**
```json
{
  "type": "error",
  "payload": {
    "code": "CONNECTION_LIMIT_EXCEEDED",
    "message": "Maximum concurrent connections (5) exceeded",
    "retryable": true,
    "details": {
      "currentConnections": 5,
      "limit": 5
    }
  }
}
```

2. **WebSocket Close:**
- **Close Code:** `1008` (POLICY_VIOLATION)
- **Close Reason:** "Connection limit exceeded"

**Client Handling:**
```swift
// iOS Example
func webSocket(_ webSocket: URLSessionWebSocket, didCloseWith closeCode: URLSessionWebSocketCloseCode, reason: Data?) {
    if closeCode.rawValue == 1008 {
        // Connection limit exceeded - existing connections need to close first
        print("⚠️ Too many connections to this job. Close existing connections before reconnecting.")
    }
}
```

**Use Cases:**
- **Normal:** User opens app on 1-2 devices simultaneously (< 5 connections)
- **Edge Case:** User opens app on 5+ devices (6th connection rejected)
- **Abuse Prevention:** Prevents single job from exhausting DO memory

**Important Notes:**
- Connections are automatically cleaned up when clients disconnect
- Limit applies **per-job**, not per-user or per-IP
- Different jobs use different Durable Objects (no cross-job limits)

---

## 4. Response Envelope (Universal)

**ALL** `/v1/*` endpoints use this consistent envelope format.

### 4.1 Success Response

```typescript
{
  data: T | null,           // Payload (typed, see DTOs below)
  metadata: {
    timestamp: string,       // ISO 8601 UTC
    processingTime?: number, // Milliseconds
    provider?: string,       // "google-books" | "openlibrary" | "isbndb" | "gemini"
    cached?: boolean         // true if served from cache
  }
}
```

**Example:**
```json
{
  "data": {
    "works": [...],
    "editions": [...],
    "authors": [...]
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 145,
    "provider": "google-books",
    "cached": false
  }
}
```

### 4.2 Error Response

```typescript
{
  data: null,
  metadata: {
    timestamp: string
  },
  error: {
    message: string,         // Human-readable
    code?: string,           // Machine-readable (see Error Codes)
    details?: any            // Optional context
  }
}
```

**Example:**
```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z"
  },
  "error": {
    "message": "Book not found for ISBN 9780000000000",
    "code": "NOT_FOUND",
    "details": {
      "isbn": "9780000000000",
      "providersSearched": ["google-books", "openlibrary", "isbndb"]
    }
  }
}
```

### 4.3 Error Codes

| Code | HTTP Status | Description | Retry? |
|------|-------------|-------------|--------|
| `INVALID_ISBN` | 400 | Invalid ISBN format | No |
| `INVALID_QUERY` | 400 | Missing or invalid query parameter | No |
| `INVALID_REQUEST` | 400 | Malformed request body | No |
| `NOT_FOUND` | 404 | Resource not found | No |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests | Yes (after delay) |
| `PROVIDER_TIMEOUT` | 504 | External API timeout | Yes |
| `PROVIDER_ERROR` | 502 | External API error | Yes |
| `INTERNAL_ERROR` | 500 | Server error | Yes |

---

## 5. Canonical Data Transfer Objects

### 5.1 WorkDTO (Abstract Creative Work)

Represents the abstract concept of a book (e.g., "The Great Gatsby" as a work, not a specific edition).

```typescript
interface WorkDTO {
  // ========== REQUIRED FIELDS ==========
  title: string;
  subjectTags: string[];            // Always present (can be empty array)
  goodreadsWorkIDs: string[];       // Always present (can be empty array)
  amazonASINs: string[];            // Always present (can be empty array)
  librarythingIDs: string[];        // Always present (can be empty array)
  googleBooksVolumeIDs: string[];   // Always present (can be empty array)
  isbndbQuality: number;            // 0-100, always present
  reviewStatus: ReviewStatus;       // Always present

  // ========== OPTIONAL METADATA ==========
  originalLanguage?: string;        // ISO 639-1 code (e.g., "en", "fr")
  firstPublicationYear?: number;    // Year only (e.g., 1925)
  description?: string;             // Synopsis
  coverImageURL?: string;           // High-res cover (1200px width recommended)
                                    // Returns placeholder URL if no cover available (Issue #202)
  searchLinks?: SearchLinksDTO;     // HATEOAS links for external providers (Issue #196)

  // ========== PROVENANCE ==========
  synthetic?: boolean;              // true if Work was inferred from Edition
  primaryProvider?: DataProvider;   // "google-books" | "openlibrary" | "isbndb" | "gemini"
  contributors?: DataProvider[];    // All providers that contributed data

  // ========== EXTERNAL IDs (LEGACY - SINGLE VALUES) ==========
  openLibraryID?: string;           // e.g., "OL12345W"
  openLibraryWorkID?: string;       // Alias for openLibraryID
  isbndbID?: string;
  googleBooksVolumeID?: string;     // e.g., "abc123XYZ"
  goodreadsID?: string;             // Deprecated: use goodreadsWorkIDs[] instead

  // ========== QUALITY METRICS ==========
  lastISBNDBSync?: string;          // ISO 8601 timestamp

  // ========== AI SCAN METADATA ==========
  originalImagePath?: string;       // Source image for AI-detected books
  boundingBox?: BoundingBox;        // Book location in image
}
```

**BoundingBox:**
```typescript
interface BoundingBox {
  x: number;       // X coordinate (0.0-1.0, normalized)
  y: number;       // Y coordinate (0.0-1.0, normalized)
  width: number;   // Width (0.0-1.0, normalized)
  height: number;  // Height (0.0-1.0, normalized)
}
```

**ReviewStatus:**
```typescript
type ReviewStatus = "verified" | "needsReview" | "userEdited";
```

**DataProvider:**
```typescript
type DataProvider = "google-books" | "openlibrary" | "isbndb" | "gemini";
```

**SearchLinksDTO (Issue #196 - HATEOAS Compliance):**
```typescript
interface SearchLinksDTO {
  googleBooks?: string;   // Direct link to Google Books search/volume
  openLibrary?: string;   // Direct link to OpenLibrary ISBN/search
  amazon?: string;        // Direct link to Amazon search
}
```

**Purpose:** Centralize URL construction on backend (HATEOAS principle). Clients never need to construct provider URLs - just follow the links provided.

**Example:**
```json
{
  "searchLinks": {
    "googleBooks": "https://www.googleapis.com/books/v1/volumes?q=isbn:9780743273565",
    "openLibrary": "https://openlibrary.org/isbn/9780743273565",
    "amazon": "https://www.amazon.com/s?k=9780743273565"
  }
}
```

---

### 5.2 EditionDTO (Physical/Digital Manifestation)

Represents a specific publication of a work (e.g., "The Great Gatsby" 1925 Scribner hardcover edition).

```typescript
interface EditionDTO {
  // ========== REQUIRED FIELDS ==========
  isbns: string[];                  // All ISBNs (can be empty array)
  format: EditionFormat;            // Always present
  amazonASINs: string[];            // Always present (can be empty array)
  googleBooksVolumeIDs: string[];   // Always present (can be empty array)
  librarythingIDs: string[];        // Always present (can be empty array)
  isbndbQuality: number;            // 0-100, always present

  // ========== OPTIONAL IDENTIFIERS ==========
  isbn?: string;                    // Primary ISBN (first from isbns array)

  // ========== OPTIONAL METADATA ==========
  title?: string;
  publisher?: string;
  publicationDate?: string;         // YYYY-MM-DD or YYYY
  pageCount?: number;
  coverImageURL?: string;           // Returns placeholder URL if no cover available (Issue #202)
  editionTitle?: string;            // e.g., "Deluxe Illustrated Edition"
  editionDescription?: string;      // Note: NOT 'description' (Swift reserved)
  language?: string;                // ISO 639-1 code
  searchLinks?: SearchLinksDTO;     // HATEOAS links for external providers (Issue #196)

  // ========== PROVENANCE ==========
  primaryProvider?: DataProvider;
  contributors?: DataProvider[];

  // ========== EXTERNAL IDs (LEGACY) ==========
  openLibraryID?: string;
  openLibraryEditionID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;     // Deprecated: use googleBooksVolumeIDs[]
  goodreadsID?: string;

  // ========== QUALITY METRICS ==========
  lastISBNDBSync?: string;          // ISO 8601 timestamp
}
```

**EditionFormat:**
```typescript
type EditionFormat =
  | "Hardcover"
  | "Paperback"
  | "E-book"
  | "Audiobook"
  | "Mass Market";
```

**IMPORTANT:** iOS Swift `@Model` macro reserves the keyword `description`. Use `editionDescription` instead.

---

### 5.3 AuthorDTO (Creator of Works)

```typescript
interface AuthorDTO {
  // ========== REQUIRED FIELDS ==========
  name: string;
  gender: AuthorGender;             // Always present (defaults to "Unknown")

  // ========== OPTIONAL CULTURAL DIVERSITY FIELDS ==========
  culturalRegion?: CulturalRegion;  // Enriched via Wikidata
  nationality?: string;             // e.g., "Nigeria", "United States"
  birthYear?: number;
  deathYear?: number;

  // ========== EXTERNAL IDs ==========
  openLibraryID?: string;
  isbndbID?: string;
  googleBooksID?: string;
  goodreadsID?: string;

  // ========== STATISTICS ==========
  bookCount?: number;               // Total books by this author
}
```

**AuthorGender:**
```typescript
type AuthorGender =
  | "Female"
  | "Male"
  | "Non-binary"
  | "Other"
  | "Unknown";
```

**CulturalRegion:**
```typescript
type CulturalRegion =
  | "Africa"
  | "Asia"
  | "Europe"
  | "North America"
  | "South America"
  | "Oceania"
  | "Middle East"
  | "Caribbean"
  | "Central Asia"
  | "Indigenous"
  | "International";
```

**Cultural Enrichment:**
- Gender, nationality, and cultural region are enriched via **Wikidata API**
- Cache TTL: **7 days** (author metadata is stable)
- Fallback: `gender: "Unknown"` if Wikidata lookup fails

---

### 5.4 DTO Field Defaults

**Default Value Pattern:** Optional fields default to `undefined` (NOT `null` or zero)

**Common Defaults:**

| Field Type | Default Value | Example Fields |
|------------|---------------|----------------|
| Optional string | `undefined` | `originalLanguage`, `description`, `coverImageURL` |
| Optional number | `undefined` | `pageCount`, `firstPublicationYear`, `publicationYear` |
| Optional object | `undefined` | `searchLinks`, `enrichment` |
| Required array | `[]` (empty array) | `subjectTags`, `goodreadsWorkIDs`, `amazonASINs` |
| Optional array | `undefined` | N/A (all arrays are required) |
| Optional boolean | `undefined` | `synthetic` |

**Type Safety Notes:**
- **TypeScript**: Optional fields use `field?: type` (not `field: type | null`)
- **JSON Serialization**: `undefined` fields are omitted from JSON (not sent as `null`)
- **Client Handling**: Check for `undefined` or use nullish coalescing (`??`) for defaults

**Examples:**

```typescript
// ✅ CORRECT: Check for undefined
if (work.searchLinks !== undefined) {
  // searchLinks exists
}

// ✅ CORRECT: Nullish coalescing
const title = work.title ?? "Unknown Title";
const pageCount = edition.pageCount ?? 0;

// ❌ INCORRECT: Checking for null
if (work.searchLinks !== null) { // Will miss undefined
  // ...
}

// ❌ INCORRECT: Assuming default zero
const pages = edition.pageCount; // Could be undefined, not 0!
```

---

### 5.5 BookSearchResponse

Used by: `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`

```typescript
interface BookSearchResponse {
  works: WorkDTO[];
  editions: EditionDTO[];
  authors: AuthorDTO[];
  resultCount: number;              // Number of books found (0 for no results, N for N books)
  totalResults?: number;            // Reserved for future pagination
}
```

**Field Details:**
- **`resultCount`**: Explicitly indicates the number of results found. This disambiguates "no results found" (0) from errors.
  - `0`: Search completed successfully but found no matching books
  - `N > 0`: Search found N matching books
  - Always equals `works.length` in current implementation

**Relationship:**
- Works and Editions are **loosely coupled** (not normalized)
- Authors are **deduplicated** across all works
- Frontend must match Works ↔ Editions ↔ Authors by ID/ISBN

---

## 6. HTTP API Endpoints

### 6.1 Book Search

#### GET /v1/search/isbn

Search for books by ISBN (10 or 13 digits).

**Query Parameters:**
- `isbn` (required): ISBN-10 or ISBN-13 (hyphens optional)

**Request Example:**
```http
GET /v1/search/isbn?isbn=9780439708180 HTTP/1.1
Host: api.oooefam.net
```

**Success Response (200):**
```json
{
  "data": {
    "works": [
      {
        "title": "Harry Potter and the Sorcerer's Stone",
        "subjectTags": ["fantasy", "young-adult", "magic"],
        "firstPublicationYear": 1997,
        "coverImageURL": "https://covers.openlibrary.org/b/id/12345-L.jpg",
        "synthetic": false,
        "primaryProvider": "google-books",
        "goodreadsWorkIDs": ["1234567"],
        "amazonASINs": ["B000ABC123"],
        "isbndbQuality": 85,
        "reviewStatus": "verified"
      }
    ],
    "editions": [
      {
        "isbn": "9780439708180",
        "isbns": ["9780439708180", "0439708184"],
        "title": "Harry Potter and the Sorcerer's Stone",
        "publisher": "Scholastic",
        "publicationDate": "1998-09-01",
        "pageCount": 309,
        "format": "Paperback",
        "coverImageURL": "https://...",
        "amazonASINs": ["B000ABC123"],
        "isbndbQuality": 85
      }
    ],
    "authors": [
      {
        "name": "J.K. Rowling",
        "gender": "Female",
        "culturalRegion": "Europe",
        "nationality": "United Kingdom",
        "birthYear": 1965
      }
    ],
    "resultCount": 1
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 145,
    "provider": "google-books",
    "cached": false
  }
}
```

**Not Found (200):**
```json
{
  "data": {
    "works": [],
    "editions": [],
    "authors": [],
    "resultCount": 0
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 89,
    "provider": "none",
    "cached": false
  }
}
```

**Error (400):**
```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z"
  },
  "error": {
    "message": "Invalid ISBN format. Must be valid ISBN-10 or ISBN-13",
    "code": "INVALID_ISBN",
    "details": {
      "isbn": "123"
    }
  }
}
```

---

#### GET /v1/search/title

Search for books by title (fuzzy matching, up to 20 results).

**Query Parameters:**
- `q` (required): Search query (min 2 characters)

**Request Example:**
```http
GET /v1/search/title?q=great+gatsby HTTP/1.1
Host: api.oooefam.net
```

**Success Response (200):**
Same structure as `/v1/search/isbn`, but `data.works` may contain multiple results.

**Performance:**
- P95 latency: < 500ms (uncached)
- P95 latency: < 50ms (cached)

---

#### GET /v1/search/advanced

Advanced search by title and/or author (up to 20 results).

**Query Parameters:**
- `title` (optional): Title search query
- `author` (optional): Author search query
- **At least one** query parameter required

**Request Example:**
```http
GET /v1/search/advanced?title=gatsby&author=fitzgerald HTTP/1.1
Host: api.oooefam.net
```

**Success Response (200):**
Same structure as `/v1/search/isbn`.

---

### 6.2 Results Retrieval

#### GET /v1/scan/results/{jobId}

Retrieve full AI scan results after WebSocket completion.

**Path Parameters:**
- `jobId` (required): Job identifier from WebSocket completion message

**Request Example:**
```http
GET /v1/scan/results/uuid-12345 HTTP/1.1
Host: api.oooefam.net
```

**Success Response (200):**
```json
{
  "data": {
    "totalDetected": 25,
    "approved": 20,
    "needsReview": 5,
    "expiresAt": "2025-01-16T10:00:00.000Z",
    "books": [
      {
        "title": "The Great Gatsby",
        "author": "F. Scott Fitzgerald",
        "isbn": "9780743273565",
        "confidence": 0.95,
        "boundingBox": {
          "x": 0.12,
          "y": 0.34,
          "width": 0.08,
          "height": 0.25
        },
        "enrichmentStatus": "success",
        "enrichment": {
          "status": "success",
          "work": { /* WorkDTO */ },
          "editions": [ /* EditionDTO[] */ ],
          "authors": [ /* AuthorDTO[] */ ]
        }
      }
    ],
    "metadata": {
      "modelUsed": "gemini-2.0-flash-exp",
      "processingTime": 8500,
      "timestamp": 1700000000000
    }
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 12,
    "cached": true,
    "provider": "kv_cache"
  }
}
```

**Not Found (404):**
```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z"
  },
  "error": {
    "message": "Scan results not found or expired. Results are stored for 24 hours after job completion.",
    "code": "NOT_FOUND",
    "details": {
      "jobId": "uuid-12345",
      "resultsKey": "scan-results:uuid-12345",
      "ttl": "24 hours"
    }
  }
}
```

**Storage:**
- KV Key: `scan-results:{jobId}`
- TTL: **24 hours** from job completion
- Max Size: ~10 MB (100 books @ 100 KB each)

**Field Notes:**
- **`expiresAt`**: ISO 8601 timestamp indicating when results will be deleted from KV cache. Clients should cache results locally before expiry or handle 404 errors gracefully.

---

#### GET /v1/csv/results/{jobId}

Retrieve full CSV import results after WebSocket completion.

**Path Parameters:**
- `jobId` (required): Job identifier from WebSocket completion message

**Request Example:**
```http
GET /v1/csv/results/uuid-67890 HTTP/1.1
Host: api.oooefam.net
```

**Success Response (200):**
```json
{
  "data": {
    "books": [
      {
        "title": "1984",
        "author": "George Orwell",
        "isbn": "9780451524935"
      }
    ],
    "errors": [],
    "successRate": "98/100",
    "timestamp": 1700000000000,
    "expiresAt": "2025-01-16T10:00:00.000Z"
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00.000Z",
    "processingTime": 8,
    "cached": true,
    "provider": "kv_cache"
  }
}
```

**Not Found (404):**
Same structure as `/v1/scan/results/{jobId}`.

**Storage:**
- KV Key: `csv-results:{jobId}`
- TTL: **24 hours** from job completion

**Field Notes:**
- **`expiresAt`**: ISO 8601 timestamp indicating when results will be deleted from KV cache. Clients should cache results locally before expiry or handle 404 errors gracefully.

---

## 7. WebSocket API

> **🚨 BREAKING CHANGE (v2.0.0 - Issue #167):**
> WebSocket error messages now use HTTP canonical format (ResponseEnvelope) for consistency.
> **Deployment:** Coordinated backend + frontend deployment (Nov 19, 2025).
> **Action Required:** Update WebSocket error parsing to new format immediately (see [Migration Guide](#error-migration-guide-v1-v2)).
> **No Backward Compatibility:** v1 format removed - all clients must use v2.

### 7.1 Connection

**URL Pattern:**
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**⚠️ CRITICAL: HTTP/1.1 Required (Issue #227)**

WebSocket connections **MUST** use HTTP/1.1. HTTP/2 and HTTP/3 are not supported by the WebSocket protocol (RFC 6455).

**iOS URLSession Configuration:**
```swift
let configuration = URLSessionConfiguration.default
configuration.httpProtocolOptions = [.http1_1Only: true]
let session = URLSession(configuration: configuration)
let websocketTask = session.webSocketTask(with: request)
```

**Error if using HTTP/2:**
```
HTTP/2 426 Upgrade Required
Expected Upgrade: websocket
```

**Connection Lifecycle:**
1. Client connects with valid `jobId` and `token` (HTTP/1.1 only)
2. Client sends `ready` signal when ready to receive messages
3. Server sends `ready_ack` acknowledgment
4. Server sends job updates (`job_started`, `job_progress`, `job_complete`)
5. Server closes connection with code 1000 (NORMAL_CLOSURE) on completion

**Heartbeat:**
- Not required - Cloudflare Workers automatically handles connection health
- Connections remain active for duration of job (up to 2 hours with auto token refresh)

**Local Testing with Wrangler:**
```bash
# Start local dev server with remote Durable Objects
npx wrangler dev --remote

# WebSocket will be available at:
# ws://localhost:8787/ws/progress?jobId={jobId}&token={token}

# Note: --remote flag required for WebSocket functionality
# Durable Objects must connect to production for WebSocket support
```

**Testing Tools:**
```bash
# wscat (install globally)
npm install -g wscat

# Connect to local dev
wscat -c "ws://localhost:8787/ws/progress?jobId=test-123&token=test-token"

# Connect to production
wscat -c "wss://api.oooefam.net/ws/progress?jobId=test-123&token=test-token"

# Expected: Connection upgrade, then "connected" message
```

---

### 7.2 Message Format

All messages use this envelope:

```typescript
{
  type: MessageType;
  jobId: string;
  pipeline: Pipeline;
  timestamp: number;        // Unix timestamp (milliseconds)
  version: string;          // "1.0.0"
  payload: MessagePayload;  // Type-specific data
}
```

**MessageType:**
```typescript
type MessageType =
  // Job lifecycle messages
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"

  // Client-server handshake
  | "ready"           // Client → Server: Ready to receive updates
  | "ready_ack"       // Server → Client: Acknowledged ready signal

  // Reconnection support
  | "reconnected"     // Server → Client: State sync after reconnect

  // Batch photo scanning
  | "batch-init"      // Server → Client: Batch scan initialization
  | "batch-progress"  // Server → Client: Photo-by-photo progress
  | "batch-complete"  // Server → Client: Batch scan complete
  | "batch-canceling" // Server → Client: Batch cancellation in progress

```

**Pipeline:**
```typescript
type Pipeline =
  | "batch_enrichment"
  | "csv_import"
  | "ai_scan";
```

---

### 7.3 Message Types

#### job_started

Sent when background job begins processing.

```json
{
  "type": "job_started",
  "jobId": "uuid-12345",
  "pipeline": "ai_scan",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_started",
    "totalItems": 10,
    "estimatedDuration": 30000
  }
}
```

---

#### job_progress

Sent periodically during processing (every 5-10% progress).

```json
{
  "type": "job_progress",
  "jobId": "uuid-12345",
  "pipeline": "ai_scan",
  "timestamp": 1700000500000,
  "version": "1.0.0",
  "payload": {
    "type": "job_progress",
    "progress": 0.5,
    "status": "Processing image 5 of 10",
    "processedCount": 5,
    "currentItem": "IMG_1234.jpg"
  }
}
```

---

#### job_complete (Summary-Only)

**CRITICAL:** Completion messages are **summary-only** (no large arrays). Full results must be retrieved via HTTP GET.

```json
{
  "type": "job_complete",
  "jobId": "uuid-12345",
  "pipeline": "csv_import",
  "timestamp": 1700001000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_complete",
    "pipeline": "csv_import",
    "summary": {
      "totalProcessed": 48,
      "successCount": 48,
      "failureCount": 0,
      "duration": 413,
      "resourceId": "job-results:uuid-12345"
    },
    "expiresAt": "2025-01-16T10:00:00.000Z"
  }
}
```

**For AI Scan (pipeline: "ai_scan"):**
```json
{
  "payload": {
    "type": "job_complete",
    "pipeline": "ai_scan",
    "summary": {
      "totalProcessed": 25,
      "successCount": 25,
      "failureCount": 0,
      "duration": 8500,
      "resourceId": "job-results:uuid-12345",
      "totalDetected": 25,
      "approved": 20,
      "needsReview": 5
    },
    "expiresAt": "2025-01-16T10:00:00.000Z"
  }
}
```

**Client Action:**
After receiving `job_complete`, client MUST fetch full results using `resourceId`:
```http
GET https://api.oooefam.net/v1/jobs/{jobId}/results
```

**Why Summary-Only?**
- Large result arrays (5-10 MB) cause UI freezes on mobile
- WebSocket payloads kept < 1 KB for instant parsing
- Results stored in KV with 24-hour TTL

**New Field: `expiresAt` (Issue #169)**
- **Type:** ISO 8601 timestamp string (e.g., `"2025-01-16T10:00:00.000Z"`)
- **Purpose:** Prevents race conditions where clients try to fetch expired results
- **Calculation:** 24 hours from job completion time
- **Usage:** Clients can display countdown timers and handle expiry gracefully

---

#### error

Sent when job fails.

**⚠️ BREAKING CHANGE (v2.0.0):** Error payload now matches HTTP canonical format (ResponseEnvelope) for consistency.

```json
{
  "type": "error",
  "jobId": "uuid-12345",
  "pipeline": "csv_import",
  "timestamp": 1700000700000,
  "version": "2.0.0",
  "payload": {
    "type": "error",
    "data": null,
    "metadata": {
      "timestamp": "2025-01-15T10:00:00.000Z"
    },
    "error": {
      "message": "Invalid CSV format: Missing title column",
      "code": "E_CSV_PROCESSING_FAILED",
      "details": {
        "lineNumber": 42
      }
    },
    "retryable": true
  }
}
```

**Migration Guide (v1 → v2):**

```typescript
// ❌ OLD (v1.0.0) - Deprecated
const { code, message, details } = wsMessage.payload;

// ✅ NEW (v2.0.0) - Canonical format
const { error, retryable } = wsMessage.payload;
const { code, message, details } = error;
```

```swift
// Swift (iOS) Migration Example

// ❌ OLD (v1.0.0) - Deprecated
let code = payload["code"] as? String
let message = payload["message"] as? String
let details = payload["details"] as? [String: Any]

// ✅ NEW (v2.0.0) - Canonical format
let error = payload["error"] as? [String: Any]
let retryable = payload["retryable"] as? Bool
let code = error?["code"] as? String
let message = error?["message"] as? String
let details = error?["details"] as? [String: Any]
```

```dart
// Dart (Flutter) Migration Example

// ❌ OLD (v1.0.0) - Deprecated
final code = payload['code'] as String?;
final message = payload['message'] as String?;
final details = payload['details'] as Map<String, dynamic>?;

// ✅ NEW (v2.0.0) - Canonical format
final error = payload['error'] as Map<String, dynamic>?;
final retryable = payload['retryable'] as bool?;
final code = error?['code'] as String?;
final message = error?['message'] as String?;
final details = error?['details'] as Map<String, dynamic>?;
```

---

#### ready (Client → Server)

**CRITICAL:** Clients MUST send this message after connecting to signal readiness to receive job updates.

```json
{
  "type": "ready"
}
```

**Why Required:**
- Server waits for client ready signal before starting processing (2-5 second timeout)
- Prevents message loss if client connects but isn't ready to receive
- Ensures UI is initialized before progress updates arrive

**Client Implementation:**
```swift
// Swift example for iOS
func webSocketDidConnect(_ webSocket: URLSessionWebSocketTask) {
    let readyMessage = ["type": "ready"]
    let jsonData = try! JSONEncoder().encode(readyMessage)
    webSocket.send(.data(jsonData)) { error in
        if let error = error {
            print("Failed to send ready signal: \(error)")
        }
    }
}
```

---

#### ready_ack (Server → Client)

Server acknowledgment of client ready signal.

```json
{
  "type": "ready_ack",
  "jobId": "uuid-12345",
  "pipeline": "ai_scan",
  "timestamp": 1700000000000,
  "version": "1.0.0",
  "payload": {
    "type": "ready_ack",
    "timestamp": 1700000000000
  }
}
```

**Client Action:** Start listening for `job_started`, `job_progress`, and `job_complete` messages.

---

#### reconnected (Server → Client)

Sent when client reconnects after disconnect, includes current job state for sync.

```json
{
  "type": "reconnected",
  "jobId": "uuid-12345",
  "pipeline": "csv_import",
  "timestamp": 1700005000000,
  "version": "1.0.0",
  "payload": {
    "type": "reconnected",
    "progress": 0.65,
    "status": "processing",
    "processedCount": 65,
    "totalCount": 100,
    "lastUpdate": 1700004950000,
    "message": "Reconnected successfully - resuming job progress"
  }
}
```

**Client Action:** Update UI with current progress state, continue listening for updates.

**See:** Section 7.5 for full reconnection flow.

---

#### batch-init (Server → Client)

Sent when batch photo scan starts (1-5 photos).

```json
{
  "type": "batch-init",
  "jobId": "uuid-12345",
  "timestamp": 1700000000000,
  "data": {
    "type": "batch-init",
    "totalPhotos": 3,
    "status": "processing"
  }
}
```

**See:** Section 7.6 for complete batch scanning documentation.

---

#### batch-progress (Server → Client)

Sent after each photo processes in batch scan.

```json
{
  "type": "batch-progress",
  "jobId": "uuid-12345",
  "timestamp": 1700000500000,
  "data": {
    "type": "batch-progress",
    "currentPhoto": 1,
    "totalPhotos": 3,
    "photoStatus": "complete",
    "booksFound": 12,
    "totalBooksFound": 25,
    "photos": [
      { "index": 0, "status": "complete", "booksFound": 13 },
      { "index": 1, "status": "complete", "booksFound": 12 },
      { "index": 2, "status": "queued", "booksFound": 0 }
    ]
  }
}
```

---

#### batch-complete (Server → Client)

Sent when all photos in batch are processed.

```json
{
  "type": "batch-complete",
  "jobId": "uuid-12345",
  "timestamp": 1700001500000,
  "data": {
    "type": "batch-complete",
    "totalBooks": 37,
    "photoResults": [
      { "photoIndex": 0, "booksFound": 13, "status": "success" },
      { "photoIndex": 1, "booksFound": 12, "status": "success" },
      { "photoIndex": 2, "booksFound": 12, "status": "success" }
    ],
    "books": [
      /* Array of detected books with enrichment */
    ]
  }
}
```

**Note:** Unlike single-photo scans, batch completion includes full book array (not summary-only).

---

#### batch-canceling (Server → Client)

Sent when batch cancellation is requested (graceful shutdown in progress).

```json
{
  "type": "batch-canceling",
  "jobId": "uuid-12345",
  "timestamp": 1700001000000,
  "data": {
    "type": "batch-canceling"
  }
}
```

**Client Action:** Show "Canceling..." UI, wait for connection close with code 1001 (GOING_AWAY).

---

### 7.4 Close Codes

Standard RFC 6455 close codes:

| Code | Name | Description | Client Action |
|------|------|-------------|---------------|
| 1000 | NORMAL_CLOSURE | Job completed successfully | No action needed |
| 1001 | GOING_AWAY | Server shutting down | Retry after 5 seconds |
| 1002 | PROTOCOL_ERROR | Malformed message | Fix client implementation |
| 1008 | POLICY_VIOLATION | Invalid token, auth failure | Re-authenticate |
| 1009 | MESSAGE_TOO_BIG | Payload > 32 MiB | Reduce payload size |
| 1011 | INTERNAL_ERROR | Server error | Retry with exponential backoff |
| 1013 | TRY_AGAIN_LATER | Server overload | Retry after 30 seconds |

---

### 7.5 Reconnection Support

**Status:** ✅ **Production Ready**

#### Overview

WebSocket connections can disconnect due to:
- Network transitions (WiFi ↔ Cellular)
- App backgrounding on iOS
- Temporary network loss
- Server maintenance

The API supports **reconnection with state sync** to resume jobs seamlessly.

#### Reconnection Grace Period

- **60 seconds** after unexpected disconnect (codes other than 1000)
- Auth token and job state preserved in Durable Object storage
- After grace period, job continues but state may be stale

#### Reconnection Flow

**1. Detect Disconnect**
```swift
func webSocket(_ webSocket: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    // Normal closure (1000) - job complete, don't reconnect
    if closeCode == .normalClosure {
        return
    }

    // Unexpected disconnect - attempt reconnection
    print("WebSocket disconnected: code \(closeCode.rawValue)")
    attemptReconnection()
}
```

**2. Reconnect with Query Param**
```swift
func attemptReconnection() {
    // Add reconnect=true to URL
    let reconnectURL = "\(originalURL)&reconnect=true"
    let webSocket = URLSession.shared.webSocketTask(with: URL(string: reconnectURL)!)
    webSocket.resume()
}
```

**3. Receive State Sync**

Server sends `reconnected` message with current progress:
```json
{
  "type": "reconnected",
  "jobId": "uuid-12345",
  "pipeline": "csv_import",
  "timestamp": 1700005000000,
  "version": "1.0.0",
  "payload": {
    "type": "reconnected",
    "progress": 0.65,
    "status": "processing",
    "processedCount": 65,
    "totalCount": 100,
    "lastUpdate": 1700004950000,
    "message": "Reconnected successfully - resuming job progress"
  }
}
```

**4. Update UI and Continue**
```swift
case "reconnected":
    let progress = payload.progress
    let processedCount = payload.processedCount
    // Update UI with synced state
    updateProgressUI(progress: progress, count: processedCount)
    // Continue listening for job_progress and job_complete
```

#### Best Practices

- **Reconnect immediately** after unexpected disconnect (don't wait)
- **Always use `reconnect=true`** query param for state sync
- **Implement exponential backoff** if reconnection fails (1s, 2s, 4s, 8s, max 30s)
- **Max 3 retries** before showing user error
- **Preserve jobId and token** in memory across reconnections

#### Testing Reconnection

```bash
# Connect to local WebSocket
wscat -c "ws://localhost:8787/ws/progress?jobId=test-123&token=test-token"

# Disconnect (Ctrl+C)

# Reconnect with state sync
wscat -c "ws://localhost:8787/ws/progress?jobId=test-123&token=test-token&reconnect=true"

# Expected: "reconnected" message with current progress
```

---

### 7.6 Batch Photo Scanning

**Status:** ✅ **Production Ready** (iOS Multi-Photo Upload Feature)

#### Overview

Batch scanning allows users to upload **1-5 photos** in a single request, with **photo-by-photo progress updates** via WebSocket.

**Why Batch Scanning:**
- Faster than sequential single-photo uploads
- Single WebSocket connection for all photos
- Atomic transaction - all succeed or all fail
- Better UX with photo-level progress tracking

#### Batch Workflow

**1. Upload Batch**
```http
POST /api/batch-scan HTTP/1.1
Host: api.oooefam.net
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="photos[]"; filename="photo1.jpg"
Content-Type: image/jpeg

[Binary data for photo 1]
--boundary
Content-Disposition: form-data; name="photos[]"; filename="photo2.jpg"
Content-Type: image/jpeg

[Binary data for photo 2]
--boundary--
```

**Response (202 Accepted):**
```json
{
  "data": {
    "jobId": "batch-uuid-12345",
    "token": "auth-token-67890",
    "totalPhotos": 2
  },
  "metadata": {
    "timestamp": "2025-11-16T12:00:00.000Z"
  }
}
```

**2. Connect WebSocket**
```swift
let wsURL = "wss://api.oooefam.net/ws/progress?jobId=\(jobId)&token=\(token)"
let webSocket = URLSession.shared.webSocketTask(with: URL(string: wsURL)!)
webSocket.resume()

// Send ready signal
let readyMessage = ["type": "ready"]
webSocket.send(.data(try! JSONEncoder().encode(readyMessage))) { _ in }
```

**3. Receive Batch Messages**

**batch-init** - Scan starting:
```json
{
  "type": "batch-init",
  "jobId": "batch-uuid-12345",
  "timestamp": 1700000000000,
  "data": {
    "type": "batch-init",
    "totalPhotos": 2,
    "status": "processing"
  }
}
```

**batch-progress** - After each photo (sent 2 times for 2 photos):
```json
{
  "type": "batch-progress",
  "jobId": "batch-uuid-12345",
  "timestamp": 1700000500000,
  "data": {
    "type": "batch-progress",
    "currentPhoto": 0,
    "totalPhotos": 2,
    "photoStatus": "complete",
    "booksFound": 15,
    "totalBooksFound": 15,
    "photos": [
      { "index": 0, "status": "complete", "booksFound": 15 },
      { "index": 1, "status": "queued", "booksFound": 0 }
    ]
  }
}
```

**batch-complete** - All photos processed:
```json
{
  "type": "batch-complete",
  "jobId": "batch-uuid-12345",
  "timestamp": 1700001000000,
  "data": {
    "type": "batch-complete",
    "totalBooks": 28,
    "photoResults": [
      { "photoIndex": 0, "booksFound": 15, "status": "success" },
      { "photoIndex": 1, "booksFound": 13, "status": "success" }
    ],
    "books": [
      {
        "title": "The Great Gatsby",
        "author": "F. Scott Fitzgerald",
        "isbn": "9780743273565",
        "confidence": 0.95,
        "boundingBox": { "x": 0.12, "y": 0.34, "width": 0.08, "height": 0.25 },
        "enrichment": {
          "status": "success",
          "work": { /* WorkDTO */ },
          "editions": [ /* EditionDTO[] */ ],
          "authors": [ /* AuthorDTO[] */ ]
        }
      }
      // ... 27 more books
    ]
  }
}
```

#### Photo State Lifecycle

```
queued → processing → complete | error
```

**Photo Status Values:**
- `queued` - Waiting to be processed
- `processing` - Currently being scanned by AI
- `complete` - Successfully processed
- `error` - Failed (see `error` field)

#### Batch Limits

| Limit | Value | Reason |
|-------|-------|--------|
| **Min Photos** | 1 | Single photo uses `/api/scan-bookshelf` endpoint |
| **Max Photos** | **5** | AI processing time (5 photos × 10s = 50s max, within Workers' 60s limit) |
| **Max Photo Size** | 10 MB | Per individual photo (enforced on decoded size to prevent malformed base64 bypass); matches Gemini API limits |
| **Total Upload Size** | 50 MB | Per batch (5 photos × 10 MB each); prevents memory exhaustion |
| **Rate Limit** | 5 requests/minute | Per IP, applies to batch requests (not individual photos) |

**⚠️ Common Mistake:** Confusing "50 MB" with "50 photos". The limit is **5 photos**, not 50.

**Single-Photo Scanning Limits (via `/api/scan-bookshelf`):**
- Max Photo Size: 10 MB per photo (same as batch per-photo limit)
- Enforcement: Checked on imageData byteLength before processing
- Error: Throws error if exceeded, with message suggesting compression

**iOS Pagination Pattern (20+ Photos):**
```swift
// For 20 photos, split into 4 batches of 5
let allPhotos = [/* 20 photos */]
let batchSize = 5

for (index, batch) in allPhotos.chunked(into: batchSize).enumerated() {
    // Respect 5 req/min rate limit: wait 12 seconds between batches
    if index > 0 {
        try await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
    }

    // Upload batch
    let response = try await uploadBatch(batch)

    // Connect WebSocket and track progress
    await trackBatchProgress(response.jobId, response.token)
}
```

#### Cancellation

**Client Cancels:**
```json
{
  "type": "cancel_batch"
}
```

**Server Response:**
```json
{
  "type": "batch-canceling",
  "jobId": "batch-uuid-12345",
  "timestamp": 1700001000000,
  "data": {
    "type": "batch-canceling"
  }
}
```

**Final Close:**
- WebSocket closes with code 1001 (GOING_AWAY)
- Partial results discarded (not saved to KV)

#### Error Handling

**Individual Photo Fails:**
```json
{
  "type": "batch-progress",
  "data": {
    "currentPhoto": 1,
    "photoStatus": "error",
    "photos": [
      { "index": 0, "status": "complete", "booksFound": 15 },
      { "index": 1, "status": "error", "error": "Invalid image format", "booksFound": 0 }
    ]
  }
}
```
- **Batch continues** processing remaining photos
- Failed photos marked with `error` field
- `totalBooksFound` excludes failed photos

**Entire Batch Fails:**
```json
{
  "type": "error",
  "jobId": "uuid-67890",
  "pipeline": "ai_scan",
  "timestamp": 1700000800000,
  "version": "2.0.0",
  "payload": {
    "type": "error",
    "data": null,
    "metadata": {
      "timestamp": "2025-01-15T10:15:00.000Z"
    },
    "error": {
      "message": "All photos failed processing",
      "code": "BATCH_SCAN_ERROR"
    },
    "retryable": true
  }
}
```
- WebSocket closes with code 1011 (INTERNAL_ERROR) after 1 second delay

---

## 8. Service Level Agreements (SLAs)

### 8.1 Availability

| Metric | Target | Measured |
|--------|--------|----------|
| **Uptime** | 99.9% | Monthly |
| **Planned Downtime** | < 4 hours/month | Announced 48h in advance |
| **Incident Response** | < 15 minutes | 24/7 monitoring |

### 8.2 Performance

| Endpoint | P95 Latency (Uncached) | P95 Latency (Cached) |
|----------|----------------------|---------------------|
| `/v1/search/isbn` | < 500ms | < 50ms |
| `/v1/search/title` | < 500ms | < 50ms |
| `/v1/search/advanced` | < 800ms | < 50ms |
| `/v1/scan/results/{jobId}` | N/A | < 50ms |
| `/v1/csv/results/{jobId}` | N/A | < 50ms |

**WebSocket:**
- Connection establishment: < 1 second
- Message latency: < 50ms

### 8.3 Data Quality

| Metric | Target |
|--------|--------|
| **ISBN Match Rate** | > 95% |
| **Cover Image Availability** | > 80% |
| **Author Enrichment Success** | > 70% (Wikidata-dependent) |
| **ISBNdb Quality Score** | > 60 (average) |

---

## 9. Frontend Integration Checklist

### 9.1 Pre-Implementation

- [ ] Review this entire contract document
- [ ] Confirm base URLs for target environment
- [ ] Set up error monitoring (track error codes)
- [ ] Implement retry logic with exponential backoff

### 9.2 HTTP Client Setup

- [ ] Configure timeout: **30 seconds** for search, **60 seconds** for batch
- [ ] Handle all error codes (see section 4.3)
- [ ] Parse `ResponseEnvelope<T>` consistently
- [ ] Log `metadata.processingTime` for performance monitoring

### 9.3 WebSocket Integration

**Basic Setup:**
- [ ] Implement token-based auth (query params: `jobId`, `token`)
- [ ] Send `ready` message immediately after connection (CRITICAL)
- [ ] Listen for `ready_ack` confirmation before expecting job messages
- [ ] Handle all job lifecycle messages (`job_started`, `job_progress`, `job_complete`, `error`)
- [ ] Fetch full results via HTTP GET after `job_complete` (summary-only pattern)
- [ ] Respect close codes (see section 7.4)

**Reconnection Support:**
- [ ] Implement reconnection logic with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- [ ] Add `reconnect=true` query param when reconnecting
- [ ] Handle `reconnected` message and sync UI state
- [ ] Max 3 retry attempts before showing user error
- [ ] Preserve `jobId` and `token` in memory across reconnections

**Batch Photo Scanning (if applicable):**
- [ ] Handle `batch-init` message (totalPhotos count)
- [ ] Update UI for each `batch-progress` message (photo-by-photo)
- [ ] Display photo grid with individual status indicators (queued/processing/complete/error)
- [ ] Handle `batch-complete` with full book array (not summary-only)
- [ ] Implement batch cancellation (`cancel_batch` message)
- [ ] Respect 1-5 photo limit

### 9.4 DTO Mapping

- [ ] Create Swift/Dart models for `WorkDTO`, `EditionDTO`, `AuthorDTO`
- [ ] Map enums correctly: `EditionFormat`, `AuthorGender`, `CulturalRegion`, `ReviewStatus`
- [ ] Handle optional fields gracefully (use `nil`/`null` defaults)
- [ ] **iOS Swift:** Use `editionDescription` (not `description` - reserved keyword)

### 9.5 Cultural Diversity (iOS Insights Tab)

- [ ] Verify `AuthorDTO.gender` is populated (fallback: "Unknown")
- [ ] Use `culturalRegion` for diversity analytics
- [ ] Display nationality if available
- [ ] Handle missing data gracefully (Wikidata enrichment may fail)

### 9.6 Testing

- [ ] Test with invalid ISBNs (expect 400 error)
- [ ] Test with non-existent books (expect empty arrays, not 404)
- [ ] Test rate limiting (expect 429 after burst)
- [ ] Test WebSocket reconnection on network loss
- [ ] Test results retrieval after 24-hour TTL (expect 404)

---

## 10. Migration from v1 to v2

### 10.1 Breaking Changes

**Response Envelope:**
- ❌ **Old:** `{ success: true/false, data: {...}, meta: {...} }`
- ✅ **New:** `{ data: {...}, metadata: {...}, error?: {...} }`

**Action Required:**
- Update response parsing to check for `error` field instead of `success` boolean
- Rename `meta` to `metadata` in client code

**EditionDTO:**
- ❌ **Old:** `isbn10`, `isbn13` (single values)
- ✅ **New:** `isbns: string[]` (array)

**Action Required:**
- Use `isbns[0]` for primary ISBN
- Display all ISBNs if needed (multi-ISBN editions)

### 10.2 Deprecated Endpoints

| Endpoint | Status | Replacement | Sunset Date |
|----------|--------|-------------|-------------|
| `/search/title` | Deprecated | `/v1/search/title` | March 1, 2026 |
| `/search/isbn` | Deprecated | `/v1/search/isbn` | March 1, 2026 |
| `/api/enrichment/start` | Deprecated | `/v1/enrichment/batch` | March 1, 2026 |

### 10.3 New Features (v2 Only)

- ✅ Cultural diversity enrichment (Wikidata)
- ✅ Summary-only WebSocket completions
- ✅ Results retrieval endpoints (`/v1/scan/results`, `/v1/csv/results`)
- ✅ ISBNs array (multiple ISBNs per edition)
- ✅ Quality scoring (`isbndbQuality`)

---

## 11. Support & Contact

### 11.1 Reporting Issues

**Bug Reports:**
- Email: `api-support@oooefam.net`
- Slack: `#bookstrack-api` channel
- GitHub: https://github.com/jukasdrj/bookstrack-backend/issues

**Include:**
- Endpoint URL
- Request/response payloads
- Error code and message
- Timestamp (ISO 8601)

### 11.2 API Status

- **Status Page:** https://status.oooefam.net
- **Incident Notifications:** Subscribe at status page
- **Scheduled Maintenance:** Announced 48 hours in advance

### 11.3 Changelog

- **v2.2 (Nov 18, 2025):** 🚀 **Hono Router Migration Complete** + **OpenAPI Spec** (Phase 1 Week 2)
  - ✅ **12/12 Endpoints Migrated:** All API endpoints available in Hono router
  - ✅ **Hono Default Enabled:** Feature flag now defaults to `true` (opt-out model)
  - 📄 **NEW: OpenAPI 3.0.3 Specification:** Machine-readable spec at [`docs/openapi.yaml`](./openapi.yaml) (Section 1.4)
  - Added Section 2.1: Router Architecture (feature flag, headers, input limits, CORS, testing)
  - New endpoints: `/v1/scan/results/{jobId}`, `/v1/csv/results/{jobId}`, `POST /api/batch-scan`
  - Security hardening: Input validation (200-char limits), CORS whitelist, error handler coverage
  - Performance monitoring: `X-Router` and `X-Response-Time` headers for analytics
  - Zero breaking changes: Both routers produce identical responses
  - Rollback capability: `ENABLE_HONO_ROUTER=false` (< 60 seconds)
- **v2.1 (Nov 16, 2025):** 🔥 **Major WebSocket Documentation Update** (Issue #67)
  - Documented 7 previously undocumented message types (`ready`, `ready_ack`, `reconnected`, batch messages)
  - Added Section 7.5: Reconnection Support with 60-second grace period
  - Added Section 7.6: Batch Photo Scanning (1-5 photos with photo-by-photo progress)
  - Updated token refresh status to ✅ Production Ready
  - Comprehensive iOS Swift code examples for all WebSocket features
  - Updated integration checklist with reconnection and batch requirements
- **v2.0 (Nov 15, 2025):** ⚠️ **BREAKING CHANGE:** Summary-only WebSocket completions (migration guide above)
  - Cultural diversity enrichment (gender, cultural region, LGBTQ+ representation)
  - WebSocket `job_complete` migrated to summary-only format (< 1 KB payloads)
  - New HTTP results endpoint: `GET /v1/jobs/{jobId}/results` (1-hour TTL)
  - Full results now stored in KV cache instead of WebSocket messages
  - Mobile optimization: Eliminated 5-10 MB WebSocket payloads causing UI freezes
  - **Migration Required:** Update all `*CompletePayload` structs by Jan 15, 2026
- **v1.5 (Oct 1, 2025):** ISBNs array, quality scoring
- **v1.0 (Sep 1, 2025):** Initial release

---

## 12. Appendix

### 12.1 Example: Complete Search Flow

```typescript
// 1. Search by ISBN
const response = await fetch('https://api.oooefam.net/v1/search/isbn?isbn=9780439708180');
const envelope = await response.json();

// 2. Check for errors
if (envelope.error) {
  console.error(`Error ${envelope.error.code}: ${envelope.error.message}`);
  return;
}

// 3. Extract data
const { works, editions, authors, resultCount } = envelope.data;

// 4. Display to user
console.log(`Found ${resultCount} works, ${editions.length} editions, ${authors.length} authors`);
console.log(`Primary work: ${works[0].title} by ${authors[0].name}`);
console.log(`Gender: ${authors[0].gender}, Cultural Region: ${authors[0].culturalRegion}`);
```

### 12.2 Example: WebSocket with Results Retrieval

```typescript
// 1. Start AI scan job
const initResponse = await fetch('https://api.oooefam.net/api/batch-scan', {
  method: 'POST',
  body: formData
});
const { jobId, token } = (await initResponse.json()).data;

// 2. Connect WebSocket
const ws = new WebSocket(`wss://api.oooefam.net/ws/progress?jobId=${jobId}&token=${token}`);

ws.onmessage = async (event) => {
  const message = JSON.parse(event.data);

  if (message.type === 'job_progress') {
    console.log(`Progress: ${message.payload.progress * 100}%`);
  }

  if (message.type === 'job_complete') {
    console.log(`Job complete! Fetching results from ${message.payload.resultsUrl}`);

    // 3. Fetch full results via HTTP GET
    const resultsResponse = await fetch(`https://api.oooefam.net${message.payload.resultsUrl}`);
    const resultsEnvelope = await resultsResponse.json();

    console.log(`Retrieved ${resultsEnvelope.data.books.length} books`);
  }
};
```

---

**END OF CONTRACT**

**Questions?** Contact: api-support@oooefam.net
**Last Updated:** November 18, 2025 (v2.2 - Hono Router Migration Complete)
**Next Review:** February 15, 2026
**Related Issues:**
- #67 (API Contract Standardization - v2.1)
- #91 (iOS WebSocket Migration Docs - v2.1)
- PHASE_1_HONO_MIGRATION (Hono Router Week 2 - v2.2)
