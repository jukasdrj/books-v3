# BooksTrack API Contract v3.0

**Status:** Production ✅
**Last Updated:** November 27, 2025
**Base URL:** `https://api.oooefam.net`

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
```

**Event Types:**
- `initialized`: Job created
- `processing`: Progress update (sent every 2s or on change)
- `completed`: Job finished successfully
- `failed`: Job failed with error
- `error`: Stream error (reconnect recommended)
- `timeout`: No progress for 5 minutes

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
    "ttl": "1 hour"
  }
}
```

**TTL:** Results stored for 1 hour after job completion

---

### 7.5 Bookshelf Photo Scan
```http
POST /api/batch-scan
Content-Type: multipart/form-data

photos: <1-5 JPEG/PNG files>
```

**Response:** Same async job format as CSV import (section 7.1)

**Rate Limit:** 5 req/min per IP

---

## 8. WebSocket API (Legacy)

### 8.1 Connection
```
wss://api.oooefam.net/ws/progress?jobId={jobId}&token={authToken}
```

**Requirements:**
- HTTP/1.1 only (not HTTP/2 or HTTP/3)
- Valid `jobId` and `authToken` from job initiation response

**Lifecycle:**
1. Client connects with jobId + token
2. Client sends `{"type":"ready"}` signal
3. Server sends `{"type":"ready_ack"}`
4. Server streams progress updates
5. Server closes with code 1000 on completion

**Message Format:**
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

**Note:** WebSocket is maintained for backward compatibility. New integrations should use SSE (section 7.2).

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
