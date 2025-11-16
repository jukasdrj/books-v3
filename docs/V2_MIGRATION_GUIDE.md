# API v2.x Migration Guide

**Target Audience:** iOS and Flutter Frontend Teams
**Current API Version:** v2.1 (WebSocket enhancements)
**Effective Date:** November 16, 2025
**Migration Deadline:** March 1, 2026 (legacy v1.x sunset)
**Status:** Production Ready - Migrate Now

---

## 📋 Table of Contents

1. [Migration Overview](#1-migration-overview)
2. [Breaking Changes](#2-breaking-changes)
3. [Deprecated Endpoints](#3-deprecated-endpoints)
4. [New Features in v2.0](#4-new-features-in-v20)
5. [Step-by-Step Migration](#5-step-by-step-migration)
6. [Testing Strategy](#6-testing-strategy)
7. [Rollback Plan](#7-rollback-plan)
8. [Support & Resources](#8-support--resources)

---

## 1. Migration Overview

### 1.1 Why Migrate?

Legacy API v1.x endpoints (like `/search/title`) will be **sunset on March 1, 2026** (90 days notice). Migrating to v2.x (endpoints under `/v1/*` path) provides:

- ✅ **Unified response envelope** - Consistent error handling
- ✅ **Cultural diversity data** - Gender, nationality, cultural region via Wikidata
- ✅ **Summary-only WebSocket completions** - No more UI freezes from large payloads
- ✅ **Multi-ISBN support** - Array of ISBNs per edition
- ✅ **Quality scoring** - ISBNdb quality metric for data confidence
- ✅ **Results retrieval endpoints** - Fetch scan results via HTTP GET

### 1.2 Timeline

| Phase | Dates | Milestone |
|-------|-------|-----------|
| **Phase 1: Backend Implementation** | ✅ Complete | v2.0 handlers deployed to production |
| **Phase 2: Pre-Notification** | Nov 16-23, 2025 | Deprecation headers active, staging ready |
| **Phase 3: Client Migration** | Nov 23 - Dec 21, 2025 | iOS/Flutter implement v2.0 clients |
| **Phase 4: Production Launch** | Dec 21, 2025 | Go/No-Go decision, monitoring dashboard |
| **Phase 5: Legacy Sunset** | March 1, 2026 | v1.x endpoints disabled |

### 1.3 Migration Approach

**Recommended:** **Dual-client pattern** with feature flag

```swift
// iOS example
enum APIVersion {
    case legacy, v2x  // Renamed for clarity
}

let apiVersion: APIVersion = FeatureFlags.useV2API ? .v2x : .legacy

switch apiVersion {
case .legacy:
    // Legacy endpoint (v1.x): /search/title
    let url = "https://api.oooefam.net/search/title?q=\(query)"
case .v2x:
    // New endpoint (v2.x): /v1/search/title
    // NOTE: URL path is /v1/* but implements v2.x contract (not v1.x)
    let url = "https://api.oooefam.net/v1/search/title?q=\(query)"
}
```

**Benefits:**
- Test v2.0 in production without full rollout
- Instant rollback if issues arise
- Gradual migration by feature area

---

## 2. Breaking Changes

### 2.1 Response Envelope Format

**OLD (v1.x):**
```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "timestamp": "2025-11-16T12:00:00Z"
  }
}
```

**NEW (v2.0):**
```json
{
  "data": { ... },
  "metadata": {
    "timestamp": "2025-11-16T12:00:00.000Z",
    "processingTime": 145,
    "provider": "google-books",
    "cached": false
  }
}
```

**Error Response (v2.0):**
```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-16T12:00:00.000Z"
  },
  "error": {
    "message": "Book not found",
    "code": "NOT_FOUND",
    "details": { ... }
  }
}
```

**Migration Action:**
- Replace `success` boolean check with `error` field check
- Rename `meta` to `metadata`
- Update error handling to use `error.code` instead of `success: false`

**iOS Swift Example:**
```swift
// OLD
struct LegacyResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let meta: Metadata
}

// NEW
struct ResponseEnvelope<T: Codable>: Codable {
    let data: T?
    let metadata: Metadata
    let error: APIError?

    var isSuccess: Bool {
        return error == nil
    }
}

struct APIError: Codable {
    let message: String
    let code: String?
    let details: [String: AnyCodable]?
}
```

---

### 2.2 EditionDTO - ISBNs Array

**OLD (v1.x):**
```typescript
{
  isbn10: "0439708184",
  isbn13: "9780439708180"
}
```

**NEW (v2.0):**
```typescript
{
  isbn: "9780439708180",      // Primary ISBN (first from array)
  isbns: [                     // All ISBNs for this edition
    "9780439708180",
    "0439708184"
  ]
}
```

**Migration Action:**
- Use `isbns[0]` if you need a single ISBN
- Display all ISBNs in edition details view
- Update ISBN validation to handle arrays

---

### 2.3 WebSocket - Summary-Only Completions

**OLD (v1.x):**
```json
{
  "type": "job_complete",
  "payload": {
    "books": [
      // 100 books × 50 KB each = 5 MB payload
      { "title": "...", "author": "...", ... }
    ]
  }
}
```

**NEW (v2.0):**
```json
{
  "type": "job_complete",
  "payload": {
    "totalDetected": 100,
    "approved": 95,
    "needsReview": 5,
    "resultsUrl": "/v1/scan/results/uuid-12345"
  }
}
```

**Migration Action:**
1. When `job_complete` is received, fetch full results via HTTP GET:
   ```swift
   let resultsURL = "https://api.oooefam.net\(payload.resultsUrl)"
   let results = try await fetchResults(from: resultsURL)
   ```
2. Remove WebSocket payload parsing for large arrays
3. Add error handling for results retrieval (404 if expired)

---

## 3. Deprecated Endpoints

All deprecated endpoints return these headers:

```http
Deprecation: true
Sunset: Sat, 1 Mar 2026 00:00:00 GMT
Warning: 299 - "This endpoint is deprecated. Use /v1/* instead. Sunset: March 1, 2026"
Link: <https://api.oooefam.net/v1/*>; rel="alternate"
```

| Legacy Endpoint | Replacement | Notes |
|-----------------|-------------|-------|
| `GET /search/title` | `GET /v1/search/title` | Same parameters |
| `GET /search/isbn` | `GET /v1/search/isbn` | Same parameters |
| `GET /search/author` | `GET /v1/search/advanced` | Use `author` parameter |
| `GET/POST /search/advanced` | `GET /v1/search/advanced` | Prefer GET over POST |
| `POST /api/enrichment/start` | `POST /v1/enrichment/batch` | Different request format |

---

## 4. New Features in v2.0

### 4.1 Cultural Diversity Enrichment

**AuthorDTO** now includes gender, nationality, and cultural region:

```typescript
{
  name: "Chimamanda Ngozi Adichie",
  gender: "Female",                    // NEW
  culturalRegion: "Africa",            // NEW
  nationality: "Nigeria",              // NEW
  birthYear: 1977,
  bookCount: 15
}
```

**Source:** Wikidata API (7-day cache)
**Fallback:** `gender: "Unknown"` if enrichment fails

**iOS Integration:**
```swift
struct AuthorDTO: Codable {
    let name: String
    let gender: AuthorGender
    let culturalRegion: CulturalRegion?
    let nationality: String?
    let birthYear: Int?
}

enum AuthorGender: String, Codable {
    case female = "Female"
    case male = "Male"
    case nonBinary = "Non-binary"
    case other = "Other"
    case unknown = "Unknown"
}

enum CulturalRegion: String, Codable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    // ... see API_CONTRACT.md §5.3
}
```

---

### 4.2 Results Retrieval Endpoints

Fetch AI scan or CSV import results after WebSocket completion:

**Endpoints:**
- `GET /v1/scan/results/{jobId}` - AI scan results (24h TTL)
- `GET /v1/csv/results/{jobId}` - CSV import results (24h TTL)

**Example:**
```swift
// After receiving job_complete via WebSocket
func fetchScanResults(jobId: String) async throws -> ScanResults {
    let url = URL(string: "https://api.oooefam.net/v1/scan/results/\(jobId)")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let envelope = try JSONDecoder().decode(ResponseEnvelope<ScanResults>.self, from: data)

    if let error = envelope.error {
        throw APIError(error.code ?? "UNKNOWN", error.message)
    }

    return envelope.data!
}
```

---

### 4.3 WebSocket Reconnection Support

**NEW:** Auto-reconnect with state sync

```swift
func webSocket(_ webSocket: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    // Reconnect on unexpected disconnect (not 1000 NORMAL_CLOSURE)
    if closeCode != .normalClosure {
        attemptReconnection()
    }
}

func attemptReconnection() {
    // Add reconnect=true to URL
    let reconnectURL = "\(originalURL)&reconnect=true"
    let webSocket = URLSession.shared.webSocketTask(with: URL(string: reconnectURL)!)
    webSocket.resume()
}
```

**Server sends `reconnected` message with current state:**
```json
{
  "type": "reconnected",
  "payload": {
    "progress": 0.65,
    "processedCount": 65,
    "totalCount": 100
  }
}
```

See [API_CONTRACT.md §7.5](./API_CONTRACT.md#75-reconnection-support) for full spec.

---

## 5. Step-by-Step Migration

### 5.1 Phase 1: Add Response Envelope Wrapper

**Goal:** Support both v1 and v2 response formats

```swift
// Create unified response parser
struct APIClient {
    enum APIVersion {
        case v1, v2
    }

    func parseResponse<T: Codable>(_ data: Data, version: APIVersion) throws -> T {
        switch version {
        case .v1:
            let legacy = try JSONDecoder().decode(LegacyResponse<T>.self, from: data)
            if !legacy.success {
                throw APIError("ERROR", "Request failed")
            }
            return legacy.data!

        case .v2:
            let envelope = try JSONDecoder().decode(ResponseEnvelope<T>.self, from: data)
            if let error = envelope.error {
                throw APIError(error.code ?? "UNKNOWN", error.message)
            }
            return envelope.data!
        }
    }
}
```

---

### 5.2 Phase 2: Implement Feature Flag

```swift
// FeatureFlags.swift
struct FeatureFlags {
    @UserDefault(key: "use_api_v2", defaultValue: false)
    static var useV2API: Bool
}

// Remote config (Firebase, LaunchDarkly, etc.)
func fetchFeatureFlags() async {
    let flags = try? await RemoteConfig.shared.fetch()
    FeatureFlags.useV2API = flags?.useV2API ?? false
}
```

---

### 5.3 Phase 3: Migrate Endpoints One-by-One

**Recommended Order:**

1. **Search endpoints** (low risk, high usage)
   - `/search/title` → `/v1/search/title`
   - `/search/isbn` → `/v1/search/isbn`

2. **Advanced search** (medium risk)
   - `/search/advanced` → `/v1/search/advanced`

3. **Enrichment** (high risk, complex request format change)
   - `/api/enrichment/start` → `/v1/enrichment/batch`

4. **WebSocket** (highest risk, requires results retrieval)
   - Update `job_complete` handling
   - Add `GET /v1/scan/results/{jobId}` fetch

---

### 5.4 Phase 4: Update DTOs

**Add new fields to existing models:**

```swift
// WorkDTO.swift
struct WorkDTO: Codable {
    // Existing fields
    let title: String
    let subjectTags: [String]

    // NEW in v2.0
    let goodreadsWorkIDs: [String]
    let amazonASINs: [String]
    let isbndbQuality: Int
    let reviewStatus: ReviewStatus

    // Use default values for backward compat
    enum CodingKeys: String, CodingKey {
        case title, subjectTags
        case goodreadsWorkIDs, amazonASINs, isbndbQuality, reviewStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subjectTags = try container.decode([String].self, forKey: .subjectTags)

        // Default to empty arrays if not present (v1.x response)
        goodreadsWorkIDs = try container.decodeIfPresent([String].self, forKey: .goodreadsWorkIDs) ?? []
        amazonASINs = try container.decodeIfPresent([String].self, forKey: .amazonASINs) ?? []
        isbndbQuality = try container.decodeIfPresent(Int.self, forKey: .isbndbQuality) ?? 0
        reviewStatus = try container.decodeIfPresent(ReviewStatus.self, forKey: .reviewStatus) ?? .needsReview
    }
}
```

---

### 5.5 Phase 5: Enable v2.0 Gradually in Production

**Week 1:** Internal testing (10% of dev team)
```swift
FeatureFlags.useV2API = BuildConfig.isDevelopment && UserDefaults.isInternalTester
```

**Week 2:** Beta testers (20% of TestFlight users)
```swift
FeatureFlags.useV2API = RemoteConfig.shared.useV2API // Remote: 20%
```

**Week 3:** Gradual production rollout (50% → 100%)
```swift
// Firebase Remote Config - production users
useV2API: {
    rollout: 50%,  // Week 3
    increment: 25% per day
}
```

**Week 4:** 100% production rollout
```swift
FeatureFlags.useV2API = true  // Hard-coded after validation
```

**Benefits of Production Testing:**
- Real user traffic patterns
- Real production data
- Instant rollback via remote config (no app release needed)
- Gradual exposure minimizes risk

---

## 6. Testing Strategy

### 6.1 Production Testing with Feature Flags

**Approach:** Test v2.0 directly in production with gradual rollout via feature flags

**Usage:**
```swift
enum APIVersion {
    case v1, v2
}

// Feature flag controls which version to use
let apiVersion: APIVersion = FeatureFlags.useV2API ? .v2 : .v1

let endpoint = apiVersion == .v2 ? "/v1/search/title" : "/search/title"
let url = "https://api.oooefam.net\(endpoint)?q=\(query)"
```

**Rollout Strategy:**
- Week 1: Internal testers only (10%)
- Week 2: Beta testers (20%)
- Week 3: Gradual rollout (50%)
- Week 4: Full rollout (100%)

---

### 6.2 Test Cases

#### Search Endpoints
- [ ] Search by title returns v2.0 envelope
- [ ] Search by ISBN returns `isbns` array
- [ ] Search returns cultural diversity fields
- [ ] Error responses include `error.code`

#### WebSocket
- [ ] `job_complete` returns summary-only payload
- [ ] Results retrieval via `/v1/scan/results/{jobId}` works
- [ ] Reconnection with `reconnect=true` syncs state
- [ ] `ready` signal sent immediately after connection

#### Enrichment
- [ ] `/v1/enrichment/batch` accepts new format
- [ ] Backward compat with legacy `/api/enrichment/start` works

---

### 6.3 Monitoring Dashboard

**URL:** https://api.oooefam.net/metrics

**Key Metrics:**
- Request count by endpoint (/v1/* vs legacy)
- Error rate by endpoint
- P95 latency
- Cache hit rate
- Feature flag adoption rate

**Alert Thresholds:**
- Error rate > 5% → Instant rollback via feature flag
- P95 latency > 1000ms → Investigate
- Cache hit rate < 60% → Check KV

**Rollback:** Update remote config to disable v2.0 (no deployment needed)

---

## 7. Rollback Plan

### 7.1 Feature Flag Rollback

**Instant rollback:**
```swift
// Remote config update (no app release needed)
FeatureFlags.useV2API = false
```

**Backend rollback:**
```bash
# Rollback to previous deployment
npx wrangler rollback --message "Rolling back v2.0 due to error spike"
```

---

### 7.2 Rollback Triggers

Automatically rollback if:
- Error rate > 5% for 15 minutes
- P95 latency > 2x baseline
- WebSocket disconnect rate > 20%
- Cultural diversity enrichment fails > 30%

---

## 8. Support & Resources

### 8.1 Documentation

- **[API_CONTRACT.md](./API_CONTRACT.md)** - Complete API specification
- **[WEBSOCKET_AUDIT_67.md](./WEBSOCKET_AUDIT_67.md)** - WebSocket implementation details
- **[MONITORING_GUIDE.md](./MONITORING_GUIDE.md)** - Dashboard and alerts

### 8.2 Contact

- **Email:** api-support@oooefam.net
- **Slack:** #bookstrack-api
- **GitHub Issues:** https://github.com/bookstrack/backend/issues

### 8.3 Migration Support

**Office Hours:** Every Tuesday/Thursday 2-3 PM EST (Nov 23 - Dec 21, 2025)
**Zoom:** https://zoom.us/j/api-migration-support

---

## Appendix A: Complete Example Migration

### Before (v1.x)

```swift
class BookService {
    func searchByTitle(_ query: String) async throws -> [Book] {
        let url = URL(string: "https://api.oooefam.net/search/title?q=\(query)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(LegacyResponse<SearchResult>.self, from: data)

        if !response.success {
            throw APIError("Request failed")
        }

        return response.data?.books ?? []
    }
}

struct LegacyResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let meta: Metadata
}
```

### After (v2.0)

```swift
class BookService {
    let apiVersion: APIVersion = FeatureFlags.useV2API ? .v2 : .v1

    func searchByTitle(_ query: String) async throws -> [Book] {
        let endpoint = apiVersion == .v2 ? "/v1/search/title" : "/search/title"
        let url = URL(string: "https://api.oooefam.net\(endpoint)?q=\(query)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let envelope = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        if let error = envelope.error {
            throw APIError(error.code ?? "UNKNOWN", error.message)
        }

        return mapToBooks(envelope.data!)
    }

    func mapToBooks(_ response: BookSearchResponse) -> [Book] {
        return response.works.map { work in
            Book(
                title: work.title,
                authors: response.authors.filter { /* match by ID */ },
                editions: response.editions.filter { /* match by work */ },
                culturalRegion: response.authors.first?.culturalRegion  // NEW in v2.0
            )
        }
    }
}

struct ResponseEnvelope<T: Codable>: Codable {
    let data: T?
    let metadata: Metadata
    let error: APIError?
}

struct BookSearchResponse: Codable {
    let works: [WorkDTO]
    let editions: [EditionDTO]
    let authors: [AuthorDTO]
}
```

---

**Last Updated:** November 16, 2025
**Maintained By:** Backend Team
**Next Review:** November 30, 2025
