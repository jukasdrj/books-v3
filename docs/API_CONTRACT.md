# BooksTrack API Contract v3.2

**Status:** Production ✅
**Last Updated:** November 27, 2025
**Base URL:** `https://api.oooefam.net`

---

## Changelog

### v3.2 (November 27, 2025)
- **SECURITY:** `DELETE /v1/jobs/{jobId}` now requires Bearer token authentication (Issue #102)

### v3.1 (November 27, 2025)
- **NEW:** `DELETE /v1/jobs/{jobId}` - Job cancellation with R2/KV cleanup (§7.5)
- **NEW:** WebSocket late-connect support - clients connecting after job completes receive results immediately (§8.3)
- **NEW:** `enrichmentStatus: "circuit_open"` - explicit status for circuit breaker failures (§7.6.1)
- **SECURITY:** WebSocket token via `Sec-WebSocket-Protocol` header (recommended) - query param deprecated (§8.1)
- **FIX:** Results TTL now 2 hours (was 1 hour) to match token expiry
- **FIX:** Summary counts clarified: `photosProcessed`, `booksDetected`, `booksUnique`, `booksEnriched`
- **FIX:** D1-primary persistence pattern (D1 first, then KV cache)

---

## 1. Overview

BooksTrack is a Cloudflare Workers API providing book search, enrichment, and AI-powered scanning. All endpoints return canonical JSON responses with `success` discriminator.

**Core Features:**
- ISBN/title/author search across Google Books, OpenLibrary, ISBNdb
- Book enrichment with OpenLibrary work/edition metadata
- CSV import with Gemini AI parsing
- Bookshelf photo scanning with Gemini Vision
- Semantic search using vector embeddings (Vectorize)
- Real-time progress via WebSocket or SSE

---

## 2. Authentication

**Current:** No authentication required (public API)
**Rate Limiting:** Per-IP, endpoint-specific (see section 8)

---

## 3. Response Format

### 3.1 Success Response
```json
{
  "success": true,
  "data": { /* endpoint-specific data */ },
  "metadata": {
    "timestamp": "2025-11-27T10:30:00Z",
    "cached": false,
    "source": "google_books"
  }
}
```

### 3.2 Error Response
```json
{
  "success": false,
  "error": {
    "code": "NOT_FOUND",
    "message": "Book not found",
    "details": { /* optional context */ },
    "retryable": false
  }
}
```

### 3.3 Error Codes
| Code | HTTP | Description | Retryable |
|------|------|-------------|-----------|
| `NOT_FOUND` | 404 | Resource not found | No |
| `INVALID_REQUEST` | 400 | Invalid parameters | No |
| `RATE_LIMIT_EXCEEDED` | 429 | Rate limit hit | Yes (retry after header) |
| `CIRCUIT_OPEN` | 503 | Provider circuit breaker open | Yes (retry after N seconds) |
| `API_ERROR` | 502 | External API failure | Depends (check `retryable`) |
| `NETWORK_ERROR` | 504 | Timeout or network issue | Yes |
| `INTERNAL_ERROR` | 500 | Server error | Maybe |

---

## 4. Book Data Model

### 4.1 Canonical Book Object
```json
{
  "isbn": "9780439708180",
  "isbn13": "9780439708180",
  "title": "Harry Potter and the Sorcerer's Stone",
  "authors": ["J.K. Rowling"],
  "publisher": "Scholastic",
  "publishedDate": "1998-09-01",
  "description": "...",
  "pageCount": 320,
  "categories": ["Fiction", "Fantasy"],
  "language": "en",
  "coverUrl": "https://covers.openlibrary.org/b/isbn/9780439708180-L.jpg",
  "averageRating": 4.5,
  "ratingsCount": 8000000
}
```

### 4.2 Enriched Book Object
Includes additional OpenLibrary metadata:
```json
{
  ...canonical_fields,
  "work": {
    "id": "/works/OL82563W",
    "title": "Harry Potter and the Philosopher's Stone",
    "subjects": ["Magic", "Wizards", "Hogwarts"],
    "firstPublishYear": 1997
  },
  "edition": {
    "id": "/books/OL26331930M",
    "numberOfPages": 320,
    "physicalFormat": "Hardcover",
    "publishers": ["Scholastic Inc."]
  },
  "authors": [
    {
      "name": "J.K. Rowling",
      "key": "/authors/OL23919A",
      "birth_date": "1965-07-31"
    }
  ]
}
```

---

## 5. Search Endpoints

### 5.1 ISBN Search
```http
GET /v1/search/isbn?isbn=9780439708180
```

**Response:**
```json
{
  "success": true,
  "data": { /* canonical book object */ },
  "metadata": {
    "source": "google_books",
    "cached": true,
    "timestamp": "2025-11-27T10:30:00Z"
  }
}
```

**Rate Limit:** 100 req/min per IP

---

### 5.2 Title Search
```http
GET /v1/search/title?q=harry+potter&limit=10
```

**Query Parameters:**
- `q` (required): Search query
- `limit` (optional): Results per page (1-100, default 20)

**Response:**
```json
{
  "success": true,
  "data": {
    "books": [ /* array of canonical book objects */ ],
    "totalResults": 250,
    "query": "harry potter"
  }
}
```

**Rate Limit:** 100 req/min per IP

---

### 5.3 Author Search
```http
GET /v1/search/author?name=rowling&limit=20
```

**Response:**
```json
{
  "success": true,
  "data": {
    "authors": [
      {
        "name": "J.K. Rowling",
        "key": "/authors/OL23919A",
        "works": [ /* array of book objects */ ],
        "workCount": 50
      }
    ]
  }
}
```

**Rate Limit:** 100 req/min per IP

---

### 5.4 Semantic Search
```http
GET /api/v2/search?mode=semantic&q=books+about+magic+schools&limit=10
```

**Features:**
- Natural language queries
- Vector similarity matching (Cloudflare Vectorize)
- BGE-M3 embeddings (1024 dimensions)

**Response:** Same as title search (section 5.2)

**Rate Limit:** 5 req/min per IP (AI compute intensive)

---

### 5.5 Similar Books
```http
GET /v1/search/similar?isbn=9780439708180&limit=5
```

**Response:**
```json
{
  "success": true,
  "data": {
    "sourceBook": { /* canonical book object */ },
    "similarBooks": [ /* array of canonical book objects */ ]
  }
}
```

**Rate Limit:** 10 req/min per IP

---

## 6. Enrichment Endpoints

### 6.1 Single Book Enrichment (V2)
```http
POST /api/v2/books/enrich
Content-Type: application/json

{
  "barcode": "9780439708180",
  "vectorize": true
}
```

**Parameters:**
- `barcode` (required): ISBN-10 or ISBN-13
- `vectorize` (optional): Generate embeddings for semantic search (default: false)

**Success Response:**
```json
{
  "success": true,
  "data": {
    "work": { /* OpenLibrary work metadata */ },
    "edition": { /* OpenLibrary edition metadata */ },
    "authors": [ /* enriched author objects */ ]
  }
}
```

**Error Response (Circuit Breaker):**
```json
{
  "success": false,
  "error": {
    "code": "CIRCUIT_OPEN",
    "message": "Provider google-books circuit breaker is open",
    "provider": "google-books",
    "retryable": true,
    "retryAfterMs": 45000
  }
}
```

**Rate Limit:** 5 req/min per IP

---

### 6.2 Batch Enrichment
```http
POST /api/batch-enrich
Content-Type: application/json

{
  "barcodes": ["9780439708180", "9780747532699"],
  "vectorize": false
}
```

**Response (Async Job):**
```json
{
  "success": true,
  "data": {
    "jobId": "batch_abc123",
    "authToken": "uuid-token",
    "message": "Batch enrichment initiated",
    "websocketUrl": "/ws/progress?jobId=batch_abc123&token=uuid-token"
  }
}
```

**Rate Limit:** 10 req/min per IP

---

## 7. Import & Scanning

### 7.1 CSV Import (V2)
```http
POST /api/v2/imports
Content-Type: multipart/form-data

file: <CSV binary data>
```

**CSV Format:**
- Required columns: `Title`, `Author`, `ISBN`
- Optional: `Publisher`, `Year`, `Pages`
- Max file size: 8MB (2M token limit for Gemini)

**Response:**
```json
{
  "success": true,
  "data": {
    "jobId": "import_abc123",
    "authToken": "uuid-token",
    "sseUrl": "/api/v2/imports/import_abc123/stream",
    "statusUrl": "/api/v2/imports/import_abc123"
  }
}
```

**Rate Limit:** 5 req/min per IP

---

### 7.2 SSE Progress Stream (V2)
```http
GET /api/v2/imports/{jobId}/stream
Accept: text/event-stream
```

**SSE Events:**
```
event: initialized
data: {"jobId":"...","status":"initialized","progress":0,"processedCount":0,"totalCount":100}

event: processing
data: {"jobId":"...","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

event: completed
data: {"jobId":"...","status":"completed","progress":1.0,"processedCount":100,"totalCount":100}

event: failed
data: {"jobId":"...","status":"failed","progress":0.3,"processedCount":30,"totalCount":100,"error":{"code":"E_CSV_PARSE_FAILED","message":"Invalid CSV format at row 31","retryable":false,"details":{"row":31}}}
```

**Event Types:**
- `initialized`: Job created
- `processing`: Progress update (sent every 2s or on change)
- `completed`: Job finished successfully
- `failed`: Job failed with structured error (see Error Object below)
- `error`: Stream error (reconnect recommended)
- `timeout`: No progress for 5 minutes

**Error Object Structure (for `failed` events):**
```typescript
{
  "code": string,        // Machine-readable error code (e.g., "E_CSV_PARSE_FAILED")
  "message": string,     // Human-readable error message
  "retryable": boolean,  // Whether the operation can be retried
  "details"?: object     // Optional additional context (row numbers, field names, etc.)
}
```

**Reconnection:**
- Client sends `Last-Event-ID` header with last received event ID
- Server resumes from that point (skips duplicate events)
- Retry interval: 5000ms (5 seconds)

**Heartbeat:** Server sends `: heartbeat` comment every 30 seconds during idle periods

**No Authentication Required:** SSE streams are public (jobId is sufficient)

---

### 7.3 Job Status (Polling Fallback)
```http
GET /api/v2/imports/{jobId}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "jobId": "import_abc123",
    "status": "processing",
    "progress": 0.67,
    "totalCount": 150,
    "processedCount": 100,
    "pipeline": "csv_import"
  }
}
```

**Rate Limit:** 30 req/min per IP

---

### 7.4 Job Results
```http
GET /api/v2/imports/{jobId}/results
```

**Response:**
```json
{
  "success": true,
  "data": {
    "booksCreated": 145,
    "booksUpdated": 0,
    "duplicatesSkipped": 5,
    "enrichmentSucceeded": 140,
    "enrichmentFailed": 5,
    "errors": [
      {"row": 15, "isbn": "1234567890", "error": "Invalid ISBN"}
    ]
  },
  "metadata": {
    "cached": true,
    "ttl": "2 hours"
  }
}
```

**TTL:** Results stored for 2 hours after job completion (matches token expiry)

---

### 7.5 Job Cancellation

```http
DELETE /v1/jobs/{jobId}
Authorization: Bearer <token>
```

**Authentication:** Required. Bearer token must match the token returned when the job was created.

**Response:**
```json
{
  "success": true,
  "data": {
    "jobId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "canceled",
    "message": "Job canceled successfully",
    "cleanup": {
      "r2ObjectsDeleted": 3,
      "kvCacheCleared": true
    }
  }
}
```

**Error Responses:**
- `401 Unauthorized` - Missing or invalid Authorization header
- `401 Unauthorized` - Token expired or doesn't match job
- `404 Not Found` - Job ID not found

**Behavior:**
- Validates Bearer token before any cleanup
- Cancels the job (sets `canceled: true` in DO state)
- Deletes R2 images for bookshelf scans
- Clears KV cache entries for job results
- Returns partial results if processing was in progress

**Note:** This is an idempotent operation. Calling DELETE on an already-canceled or completed job returns success.

---

### 7.6 Bookshelf Photo Scan
```http
POST /api/batch-scan
Content-Type: multipart/form-data

photos: <1-5 JPEG/PNG files>
```

**Response:** Same async job format as CSV import (section 7.1)

**Rate Limit:** 5 req/min per IP

#### 7.6.1 Detected Book Object

Each detected book in the results array has the following structure:

```json
{
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",
  "isbn": "9780743273565",
  "confidence": 0.92,
  "boundingBox": { "x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4 },
  "enrichmentStatus": "success",
  "enrichment": {
    "status": "success",
    "work": { /* WorkDTO */ },
    "editions": [ /* EditionDTO[] */ ],
    "authors": [ /* AuthorDTO[] */ ],
    "provider": "google_books",
    "cachedResult": true
  }
}
```

**enrichmentStatus Values:**
| Status | Description |
|--------|-------------|
| `pending` | Enrichment not yet attempted |
| `success` | Book found and enriched with metadata |
| `not_found` | No matching book found in providers |
| `error` | Enrichment failed (transient error) |
| `circuit_open` | Provider circuit breaker is open; retry later |

**circuit_open Details:**

When `enrichmentStatus: "circuit_open"`, the `enrichment` object includes:
```json
{
  "status": "circuit_open",
  "error": "Provider google_books temporarily unavailable",
  "retryAfterMs": 60000,
  "work": null,
  "editions": [],
  "authors": []
}
```

The `retryAfterMs` field indicates when the client can retry enrichment.

---

## 8. WebSocket API

### 8.1 Connection

**Secure Method (Recommended):**
```javascript
// Token via Sec-WebSocket-Protocol header (secure, not logged)
const ws = new WebSocket(
  'wss://api.oooefam.net/ws/progress?jobId={jobId}',
  ['bookstrack-auth.{authToken}']
);
```

**Legacy Method (Deprecated):**
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={authToken}
```
⚠️ **Warning:** URL query param tokens are logged in browser history and server logs. This method is deprecated and will be removed when `REQUIRE_SUBPROTOCOL_AUTH=true` is enabled.

**Requirements:**
- HTTP/1.1 only (not HTTP/2 or HTTP/3)
- Valid `jobId` and `authToken` from job initiation response
- Token valid for 2 hours from job creation

### 8.2 Lifecycle

1. Client connects with jobId + token (subprotocol preferred)
2. **NEW:** If job already complete, server sends `job_complete` immediately and closes
3. Client sends `{"type":"ready"}` signal
4. Server sends `{"type":"ready_ack"}`
5. Server streams progress updates
6. Server closes with code 1000 on completion

### 8.3 Late-Connect Support

**NEW (v3.0):** If client connects after job completes, the server will:
1. Send the stored `job_complete` message immediately
2. Close the connection with code 1000

This ensures clients that reconnect or connect late still receive results without polling.

### 8.4 Message Format

**Progress Update:**
```json
{
  "type": "job_progress",
  "payload": {
    "jobId": "...",
    "progress": 0.5,
    "processedCount": 50,
    "totalCount": 100
  }
}
```

**Job Complete (AI Scan):**
```json
{
  "type": "job_complete",
  "payload": {
    "summary": {
      "photosProcessed": 3,
      "booksDetected": 25,
      "booksUnique": 20,
      "booksEnriched": 18,
      "approved": 15,
      "needsReview": 5,
      "duration": 12500,
      "resourceId": "scan-results:{jobId}"
    }
  }
}
```

**Summary Field Semantics:**
- `booksEnriched`: Count of books with `enrichmentStatus: "success"` ONLY. Does NOT include books with status `not_found`, `error`, or `circuit_open`.
- `booksUnique`: Total unique books after ISBN deduplication (all statuses).
- For complete enrichment metrics, calculate `booksUnique - booksEnriched` to find books that failed enrichment.

**Note:** SSE is now the recommended method for new integrations (section 7.2).

---

## 9. Health & Monitoring

### 9.1 Health Check
```http
GET /health
```

**Response:**
```json
{
  "data": {
    "status": "ok",
    "worker": "api-worker",
    "version": "2.1.0",
    "router": "hono"
  }
}
```

---

### 9.2 Capabilities Discovery
```http
GET /api/v2/capabilities
```

**Response:**
```json
{
  "success": true,
  "data": {
    "version": "2.7.1",
    "features": {
      "semantic_search": {
        "enabled": true,
        "embedding_model": "bge-m3",
        "dimensions": 1024
      },
      "circuit_breaker": {
        "enabled": true,
        "providers": ["google-books", "open-library", "isbndb"]
      }
    }
  }
}
```

---

## 10. Rate Limits

| Endpoint | Limit | Window | Notes |
|----------|-------|--------|-------|
| Search (ISBN, title, author) | 100 req | 1 min | Per IP |
| Semantic search | 5 req | 1 min | AI compute intensive |
| Enrichment (single) | 5 req | 1 min | Per IP |
| Batch operations | 10 req | 1 min | Per IP |
| CSV/Photo import | 5 req | 1 min | Per IP |
| Job status polling | 30 req | 1 min | Per IP |

**Rate Limit Response:**
```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded",
    "retryAfter": 60
  }
}
```

**Header:** `Retry-After: 60` (seconds until reset)

---

## 11. CORS Policy

**Allowed Origins:**
- `https://bookstrack.oooefam.net` (production web)
- `capacitor://localhost` (iOS app)
- `http://localhost:3000` (local dev)
- `http://localhost:8787` (wrangler dev)

**Allowed Methods:** GET, POST, OPTIONS, PUT, DELETE

**Exposed Headers:** `X-Router`, `X-Response-Time`, `Retry-After`

**Preflight Cache:** 24 hours

---

## 12. Circuit Breaker

**Purpose:** Fail-fast when external providers (Google Books, OpenLibrary, ISBNdb) are down

**Configuration:**
- Failure threshold: 5 consecutive failures → OPEN
- Success threshold: 2 successes → CLOSED
- Cooldown: 60 seconds before retry
- Per-provider tracking

**States:**
- **CLOSED:** Normal operation (all requests flow through)
- **OPEN:** Provider failing (requests fail immediately with `CIRCUIT_OPEN`)
- **HALF_OPEN:** Testing recovery (limited requests allowed)

**Error Response:**
```json
{
  "success": false,
  "error": {
    "code": "CIRCUIT_OPEN",
    "message": "Provider google-books circuit breaker is open",
    "provider": "google-books",
    "retryable": true,
    "retryAfterMs": 45000
  }
}
```

**Client Handling:**
1. Check `error.code === "CIRCUIT_OPEN"`
2. Wait `error.retryAfterMs` milliseconds
3. Retry or fallback to alternative provider

---

## 13. Deprecation Policy

**Notice Period:** 90 days minimum for breaking changes

**Current Deprecations:** None

**Versioning:** Major version changes (v2 → v3) may introduce breaking changes with migration guide

---

## 14. Support

**API Issues:** https://github.com/yourusername/bookstrack/issues
**Status Page:** https://status.oooefam.net
**Contact:** api-support@oooefam.net

---

## Appendix A: HTTP Headers

### Standard Request Headers
- `Content-Type`: `application/json` or `multipart/form-data`
- `Accept`: `application/json` (or `text/event-stream` for SSE)

### Standard Response Headers
- `Content-Type`: `application/json` or `text/event-stream`
- `X-Response-Format`: `v2.0` (canonical format version)
- `X-Router`: `hono` (router used)
- `X-Response-Time`: `45ms` (processing time)
- `Cache-Control`: Varies by endpoint

### CORS Headers
- `Access-Control-Allow-Origin`: (matched from allowed list)
- `Access-Control-Allow-Methods`: `GET, POST, OPTIONS, PUT, DELETE`
- `Access-Control-Expose-Headers`: `X-Router, X-Response-Time, Retry-After`
- `Access-Control-Max-Age`: `86400`

---

**End of Contract**
