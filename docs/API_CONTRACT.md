# BooksTrack API Contract v2.0

**Status:** Production ✅
**Effective Date:** November 15, 2025
**Last Updated:** November 15, 2025
**Contract Owner:** Backend Team
**Audience:** iOS, Flutter, Web Frontend Teams

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

**Current Version:** `v2.0`
**API Version Header:** `X-API-Version: 2.0` (optional)
**URL Versioning:** `/v1/*` endpoints (stable), `/v2/*` endpoints (future)

**Version Support Policy:**
- `v1.*`: Supported until March 1, 2026 (deprecated)
- `v2.*`: Current version (production ready)
- `v3.*`: Not yet planned

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

## 3. Authentication & Authorization

### 3.1 WebSocket Authentication

**Token-Based Auth:** Required for all WebSocket connections.

**Token Lifecycle:**
1. **Obtain Token:** POST endpoints return `{ jobId, token }` in response
2. **Connect:** Use token in WebSocket URL: `wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}`
3. **Expiration:** Tokens expire after **2 hours** (7200 seconds)
4. **Refresh:** Available within **30-minute window** before expiration

**Token Refresh (Future):**
```http
POST /v1/token/refresh
Content-Type: application/json

{
  "jobId": "uuid-12345",
  "oldToken": "eyJhbGc..."
}

Response:
{
  "data": {
    "newToken": "eyJhbGc...",
    "expiresAt": "2025-11-15T22:00:00Z"
  },
  "metadata": {
    "timestamp": "2025-11-15T20:00:00Z"
  }
}
```

**Status:** ⚠️ Token refresh endpoint not yet implemented. Tokens are single-use only.

### 3.2 Rate Limiting

**Global Limits:**
- **1000 requests/hour** per IP address
- **Burst:** 50 requests/minute

**Endpoint-Specific Limits:**
- Search: **100 requests/minute** per IP
- Batch Enrichment: **10 requests/minute** per IP
- AI Scan: **5 requests/minute** per IP (expensive AI operations)

**Rate Limit Headers:**
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1700000000
```

**Rate Limit Exceeded:**
```json
{
  "data": null,
  "metadata": {
    "timestamp": "2025-11-15T20:00:00Z"
  },
  "error": {
    "message": "Rate limit exceeded. Try again in 45 seconds.",
    "code": "RATE_LIMIT_EXCEEDED",
    "details": {
      "retryAfter": 45,
      "limit": 100,
      "window": "1 minute"
    }
  }
}
```

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
  coverImageURL?: string;
  editionTitle?: string;            // e.g., "Deluxe Illustrated Edition"
  editionDescription?: string;      // Note: NOT 'description' (Swift reserved)
  language?: string;                // ISO 639-1 code

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

### 5.4 BookSearchResponse

Used by: `/v1/search/title`, `/v1/search/isbn`, `/v1/search/advanced`

```typescript
interface BookSearchResponse {
  works: WorkDTO[];
  editions: EditionDTO[];
  authors: AuthorDTO[];
  totalResults?: number;            // Reserved for future pagination
}
```

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
    ]
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
    "authors": []
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
    "timestamp": 1700000000000
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

---

## 7. WebSocket API

### 7.1 Connection

**URL Pattern:**
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={token}
```

**Connection Lifecycle:**
1. Client connects with valid `jobId` and `token`
2. Server sends `connected` acknowledgment
3. Server sends job updates (`job_started`, `job_progress`, `job_complete`)
4. Server closes connection with code 1000 (NORMAL_CLOSURE) on completion

**Heartbeat:**
- Server sends `ping` every 30 seconds
- Client should respond with `pong` (optional)

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
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"
  | "ping"
  | "pong";
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
  "pipeline": "ai_scan",
  "timestamp": 1700001000000,
  "version": "1.0.0",
  "payload": {
    "type": "job_complete",
    "totalDetected": 25,
    "approved": 20,
    "needsReview": 5,
    "resultsUrl": "/v1/scan/results/uuid-12345",
    "metadata": {
      "modelUsed": "gemini-2.0-flash-exp",
      "processingTime": 8500
    }
  }
}
```

**Client Action:**
After receiving `job_complete`, client MUST fetch full results:
```http
GET https://api.oooefam.net/v1/scan/results/uuid-12345
```

**Why Summary-Only?**
- Large result arrays (5-10 MB) cause UI freezes on mobile
- WebSocket payloads kept < 1 KB for instant parsing
- Results stored in KV with 24-hour TTL

---

#### error

Sent when job fails.

```json
{
  "type": "error",
  "jobId": "uuid-12345",
  "pipeline": "csv_import",
  "timestamp": 1700000700000,
  "version": "1.0.0",
  "payload": {
    "type": "error",
    "code": "E_CSV_PROCESSING_FAILED",
    "message": "Invalid CSV format: Missing title column",
    "retryable": true,
    "details": {
      "lineNumber": 42
    }
  }
}
```

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

- [ ] Implement token-based auth (query params)
- [ ] Handle all message types (`job_started`, `job_progress`, `job_complete`, `error`)
- [ ] Implement reconnection logic (exponential backoff, max 3 retries)
- [ ] Respect close codes (see section 7.4)
- [ ] Fetch full results via HTTP GET after `job_complete`

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
- GitHub: https://github.com/bookstrack/backend/issues

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

- **v2.0 (Nov 15, 2025):** Cultural diversity enrichment, summary-only completions, results endpoints
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
const { works, editions, authors } = envelope.data;

// 4. Display to user
console.log(`Found ${works.length} works, ${editions.length} editions, ${authors.length} authors`);
console.log(`Primary work: ${works[0].title} by ${authors[0].name}`);
console.log(`Gender: ${authors[0].gender}, Cultural Region: ${authors[0].culturalRegion}`);
```

### 12.2 Example: WebSocket with Results Retrieval

```typescript
// 1. Start AI scan job
const initResponse = await fetch('https://api.oooefam.net/api/scan-bookshelf/batch', {
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
**Last Updated:** November 15, 2025
**Next Review:** February 15, 2026
