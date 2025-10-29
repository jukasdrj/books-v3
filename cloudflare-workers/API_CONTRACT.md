# BooksTrack API Contract

**Version:** 3.0.0
**Base URL:** `https://api-worker.jukasdrj.workers.dev`
**Last Updated:** October 28, 2025

## Overview

This document defines the official API contract for the BooksTrack backend (Cloudflare Workers monolith). All endpoints follow REST principles with JSON responses.

## Authentication

Currently, all endpoints are public. Future versions may require API key authentication.

## Common Headers

### Request Headers
- `Content-Type: application/json` (for POST requests with JSON body)
- `Content-Type: image/*` (for image upload endpoints)

### Response Headers
- `Content-Type: application/json`
- `Access-Control-Allow-Origin: *` (CORS enabled)
- `Cache-Control: public, max-age=<seconds>` (for cached endpoints)
- `X-Cache: HIT|MISS` (cache status)
- `X-Provider: <provider>` (data source identifier)

## Error Responses

All endpoints return consistent error format:

```json
{
  "error": "Error category",
  "message": "Human-readable error description"
}
```

HTTP Status Codes:
- `200` - Success
- `202` - Accepted (async job started)
- `400` - Bad Request (invalid parameters)
- `404` - Not Found
- `413` - Payload Too Large
- `500` - Internal Server Error

---

## Search Endpoints

### 1. Search by Title

Search for books by title with intelligent caching.

**Endpoint:** `GET /search/title`

**Query Parameters:**
- `q` (required, string): Search query (title or general search)
- `maxResults` (optional, integer, default 20): Maximum results to return

**Response:**
```json
{
  "success": true,
  "provider": "google-books|openlibrary",
  "works": [
    {
      "title": "Book Title",
      "subtitle": "Subtitle (optional)",
      "authors": [
        {
          "name": "Author Name"
        }
      ],
      "editions": [
        {
          "isbn13": "9781234567890",
          "isbn10": "1234567890",
          "publisher": "Publisher Name",
          "publicationDate": "2024-01-01",
          "publishYear": 2024,
          "pageCount": 350,
          "language": "en",
          "genres": ["Fiction", "Fantasy"],
          "description": "Book description...",
          "coverImageURL": "https://example.com/cover.jpg",
          "googleBooksVolumeId": "abc123",
          "previewLink": "https://books.google.com/...",
          "infoLink": "https://books.google.com/..."
        }
      ],
      "firstPublicationYear": 2024
    }
  ],
  "totalItems": 100,
  "_cacheHeaders": {
    "Cache-Control": "public, max-age=21600",
    "X-Cache": "HIT",
    "X-Provider": "google-books"
  }
}
```

**Cache:** 6 hours (21600 seconds)

**Example:**
```bash
GET /search/title?q=harry%20potter&maxResults=10
```

---

### 2. Search by ISBN

Lookup book by ISBN with extended caching for stable data.

**Endpoint:** `GET /search/isbn`

**Query Parameters:**
- `isbn` (required, string): ISBN-10 or ISBN-13 identifier
- `maxResults` (optional, integer, default 1): Maximum results to return

**Response:** Same format as `/search/title`

**Cache:** 7 days (604800 seconds)

**Example:**
```bash
GET /search/isbn?isbn=9780439139601
```

---

### 3. Search by Author

**✅ STATUS: PRODUCTION**

Search for all books by a specific author (bibliography view).

**Endpoint:** `GET /search/author`

**Query Parameters:**
- `q` (required, string): Author name to search
- `limit` (optional, integer, default 50, max 100): Results per page
- `offset` (optional, integer, default 0): Pagination offset
- `sortBy` (optional, string, default "publicationYear"): Sort order
  - `publicationYear` - Newest first (default)
  - `publicationYearAsc` - Oldest first
  - `title` - Alphabetical by title
  - `popularity` - Most popular first (if available)

**Response:**
```json
{
  "success": true,
  "provider": "openlibrary",
  "author": {
    "name": "Stephen King",
    "openLibraryKey": "/authors/OL2162284A",
    "totalWorks": 437
  },
  "works": [
    {
      "title": "The Shining",
      "subtitle": null,
      "authors": [{"name": "Stephen King"}],
      "editions": [
        {
          "isbn13": "9780385121675",
          "isbn10": "0385121679",
          "publisher": "Doubleday",
          "publicationDate": "1977-01-28",
          "pageCount": 447,
          "coverImageURL": "https://covers.openlibrary.org/b/id/240726-L.jpg"
        }
      ],
      "firstPublicationYear": 1977,
      "subjects": ["Fiction", "Horror", "Psychological thriller"]
    }
  ],
  "pagination": {
    "total": 437,
    "limit": 50,
    "offset": 0,
    "hasMore": true,
    "nextOffset": 50
  }
}
```

**Cache:** 6 hours (21600 seconds) per page

**Implementation Status:**
- ✅ Route handler in `src/index.js`
- ✅ Search logic in `src/handlers/author-search.js`
- ✅ Pagination support (limit/offset)
- ✅ Per-page caching with UnifiedCacheService
- ✅ Sort parameter (publicationYear, title, popularity)
- ✅ Analytics Engine integration
- ✅ Full test coverage

**Use Cases:**
- iOS "Warming" feature (discover more books by favorite authors)
- Author bibliography view
- "More by this author" recommendations

**Edge Cases:**

1. **Prolific Authors (Stephen King, Nora Roberts, Isaac Asimov)**
   - Use pagination with `limit` (default 50, max 100)
   - Total works count in `author.totalWorks` field
   - iOS can implement "Load More" or infinite scroll
   - Cache each page separately (key: `author:{name}:offset:{n}`)

2. **Authors with Common Names (James Smith)**
   - Return multiple author matches with OpenLibrary keys
   - iOS presents disambiguation picker
   - Subsequent requests use `authorKey` param for precision

3. **Authors with Multiple Pseudonyms**
   - Query returns works under searched name only
   - Response includes `author.aliases` field (if available)
   - iOS can make separate requests for each pseudonym

4. **Co-Authored Works**
   - Books with multiple authors appear in all bibliographies
   - `authors` array indicates co-authors
   - iOS can deduplicate if searching multiple authors

**Performance Considerations:**

| Author Type | Typical Works | Recommended Limit | Initial Load Time |
|-------------|---------------|-------------------|-------------------|
| Debut Author | 1-5 | 20 | <1s |
| Mid-Career | 6-20 | 50 | 1-2s |
| Prolific (Stephen King) | 100-500 | 50 | 2-3s |
| Comics/Series (Stan Lee) | 1000+ | 100 | 3-5s |

**Implementation Notes:**
- Backend function exists: `getOpenLibraryAuthorWorks()` in `external-apis.js:248`
- Currently exposed via deprecated `/external/openlibrary-author` route
- Needs to be wired up to `/search/author` with:
  - Pagination support (OpenLibrary API supports `limit` and `offset`)
  - Sort parameter mapping
  - Total count from OpenLibrary author API
  - Per-page caching with cache key: `author:{authorKey}:{limit}:{offset}:{sortBy}`

**Example:**
```bash
# First page (50 books)
GET /search/author?q=Stephen%20King&limit=50&offset=0

# Second page (next 50 books)
GET /search/author?q=Stephen%20King&limit=50&offset=50

# All works sorted alphabetically
GET /search/author?q=Neil%20Gaiman&limit=100&sortBy=title
```

---

### 4. Advanced Search (Multi-Criteria)

Search with multiple criteria (author, title, ISBN) for precise matching.

**Endpoint:** `GET /search/advanced` (primary)
**Alternate:** `POST /search/advanced` (legacy support)

**Query Parameters (GET):**
- `title` OR `bookTitle` (optional, string): Book title
- `author` OR `authorName` (optional, string): Author name
- `isbn` (optional, string): ISBN identifier
- `maxResults` (optional, integer, default 20): Maximum results

**Body Parameters (POST):**
```json
{
  "title": "Book title",
  "author": "Author name",
  "isbn": "1234567890",
  "maxResults": 20
}
```

**Validation:** At least one search parameter required (title, author, or isbn)

**Response:** Same format as `/search/title`

**Cache:** 6 hours for GET requests, no cache for POST

**Example:**
```bash
GET /search/advanced?title=1984&author=George%20Orwell
POST /search/advanced
Body: {"title": "1984", "author": "George Orwell"}
```

---

## Enrichment Endpoints

### 5. Start Batch Enrichment

Enrich multiple books with metadata from external APIs (Google Books, OpenLibrary).

**Endpoint:** `POST /api/enrichment/start`

**Body:**
```json
{
  "jobId": "uuid-string",
  "workIds": ["work-id-1", "work-id-2", "work-id-3"]
}
```

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "started",
  "totalBooks": 3,
  "message": "Enrichment job started. Connect to /ws/progress?jobId=uuid-string for real-time updates."
}
```

**Status:** `202 Accepted` (async processing)

**Progress Tracking:** Use WebSocket endpoint `/ws/progress?jobId={jobId}`

---

### 6. Cancel Enrichment Job

Cancel an in-flight enrichment job (e.g., during library reset).

**Endpoint:** `POST /api/enrichment/cancel`

**Body:**
```json
{
  "jobId": "uuid-string"
}
```

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "canceled",
  "message": "Enrichment job canceled successfully"
}
```

---

## AI Scanner Endpoints

### 7. Scan Bookshelf (Single Photo)

Scan a single bookshelf photo using Gemini 2.0 Flash AI for ISBN detection.

**Endpoint:** `POST /api/scan-bookshelf?jobId={uuid}`

**Headers:**
- `Content-Type: image/jpeg` (or image/png, image/heic)
- `X-AI-Provider: gemini` (optional, default: gemini)

**Body:** Raw image binary data

**Size Limit:** 10MB (configurable via `MAX_SCAN_FILE_SIZE` env var)

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "started",
  "websocketReady": true,
  "message": "AI scan started. Connect to /ws/progress?jobId=uuid-string for real-time updates.",
  "stages": [
    {"name": "Image Quality Analysis", "typicalDuration": 3, "progress": 0.1},
    {"name": "AI Processing", "typicalDuration": 25, "progress": 0.5},
    {"name": "Metadata Enrichment", "typicalDuration": 12, "progress": 1.0}
  ],
  "estimatedRange": [32, 48]
}
```

**Status:** `202 Accepted`

**Processing Time:** 25-40 seconds (AI inference + enrichment)

---

### 8. Batch Scan Bookshelf

Scan multiple bookshelf photos in one session (max 5 photos).

**Endpoint:** `POST /api/scan-bookshelf/batch`

**Body:**
```json
{
  "jobId": "uuid-string",
  "images": [
    {
      "index": 0,
      "data": "base64-encoded-image-data"
    },
    {
      "index": 1,
      "data": "base64-encoded-image-data"
    }
  ]
}
```

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "processing",
  "totalPhotos": 2,
  "message": "Batch scan started. Processing photos sequentially."
}
```

**Status:** `202 Accepted`

**Limits:**
- Max 5 photos per batch
- 10MB per image
- Sequential processing (parallel upload → sequential AI)

---

### 9. Cancel Batch Scan

Cancel an in-flight batch scan job.

**Endpoint:** `POST /api/scan-bookshelf/cancel`

**Body:**
```json
{
  "jobId": "uuid-string"
}
```

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "canceled"
}
```

---

## CSV Import Endpoints

### 10. Gemini CSV Import

AI-powered CSV parsing with zero configuration (auto-detects columns).

**Endpoint:** `POST /api/import/csv-gemini`

**Body:**
```json
{
  "jobId": "uuid-string",
  "csvContent": "base64-encoded-csv-string"
}
```

**Response:**
```json
{
  "jobId": "uuid-string",
  "status": "processing",
  "message": "CSV parsing started with Gemini AI"
}
```

**Status:** `202 Accepted`

**Features:**
- Auto-detects title, author, ISBN columns
- Versioned caching with SHA-256 content hashing
- 10MB file size limit
- RFC 4180 compliant

---

## WebSocket Progress Endpoint

### 11. Real-Time Progress Updates

Unified WebSocket endpoint for all background jobs (enrichment, scanning, CSV import).

**Endpoint:** `GET /ws/progress?jobId={uuid}` (WebSocket upgrade)

**Query Parameters:**
- `jobId` (required, string): Job identifier from async endpoint

**Message Format:**
```json
{
  "type": "progress",
  "jobId": "uuid-string",
  "currentBook": 5,
  "totalBooks": 10,
  "bookTitle": "Current Book Title",
  "status": "processing"
}
```

**Status Values:**
- `started` - Job initialized
- `processing` - Currently processing
- `completed` - Job finished successfully
- `failed` - Job failed with error
- `canceled` - Job canceled by user

**Latency:** ~8ms average (Durable Object WebSocket)

---

## Health Check

### 12. Health Check

Check API status and list available endpoints.

**Endpoint:** `GET /health`

**Response:**
```json
{
  "status": "ok",
  "worker": "api-worker",
  "version": "1.0.0",
  "endpoints": [
    "GET /search/title?q={query}&maxResults={n} - Title search with caching (6h TTL)",
    "GET /search/isbn?isbn={isbn}&maxResults={n} - ISBN search with caching (7 day TTL)",
    "GET /search/advanced?title={title}&author={author} - Advanced search (primary method, 6h cache)",
    "POST /search/advanced - Advanced search (legacy support, JSON body)",
    "POST /api/enrichment/start - Start batch enrichment job",
    "POST /api/enrichment/cancel - Cancel in-flight enrichment job",
    "POST /api/scan-bookshelf?jobId={id} - AI bookshelf scanner",
    "POST /api/scan-bookshelf/batch - Batch AI scanner",
    "GET /ws/progress?jobId={id} - WebSocket progress updates"
  ]
}
```

---

## Legacy/Deprecated Endpoints

These endpoints exist for backward compatibility but should not be used in new code:

- `/external/google-books` - Use `/search/title` instead
- `/external/google-books-isbn` - Use `/search/isbn` instead
- `/external/openlibrary` - Use `/search/title` instead
- `/external/openlibrary-author` - **⚠️ Will be replaced by `/search/author`**
- `/external/isbndb` - Use `/search/advanced` instead
- `/external/isbndb-editions` - Use `/search/advanced` instead
- `/external/isbndb-isbn` - Use `/search/isbn` instead

---

## Rate Limits

**Current:** No rate limits enforced

**Future:** Cloudflare Workers Analytics Engine will track:
- Request rate per IP
- Cache hit rate
- Provider API usage
- Error rates

---

## Data Providers

### Primary Sources
1. **Google Books API** - Primary source for book metadata
2. **OpenLibrary** - Fallback for title/author search, primary for author bibliography
3. **ISBNdb** - ISBN-specific lookups (paid tier)

### AI Providers
1. **Gemini 2.0 Flash** - Bookshelf scanning, CSV parsing (2M token context window)

---

## Caching Strategy

| Endpoint | TTL | Storage |
|----------|-----|---------|
| `/search/title` | 6 hours | Edge Cache + KV |
| `/search/isbn` | 7 days | Edge Cache + KV |
| `/search/author` | 6 hours | Edge Cache + KV |
| `/search/advanced` | 6 hours (GET only) | Edge Cache + KV |

**Cache Keys:** SHA-256 hash of request parameters

**Invalidation:** Automatic TTL expiration (no manual invalidation API)

---

## Roadmap

### Completed Features ✅

1. **`GET /search/author`** - Author search endpoint with pagination
   - Status: **DEPLOYED** (October 2025)
   - Features: Pagination (limit/offset), sorting, per-page caching
   - Handles edge cases: Stephen King (437 works), Isaac Asimov (500+ works)
   - Performance: 1.5s first page load vs 30s timeout without pagination

### Planned Features

1. **Author Disambiguation API** - Resolve ambiguous author names
   - Priority: HIGH (depends on `/search/author`)
   - Estimated: 2 hours
   - Example: "James Smith" → multiple OpenLibrary author keys
   - iOS presents picker, subsequent requests use specific `authorKey`

3. **Authentication** - API key-based auth for production
   - Priority: MEDIUM
   - Protects against abuse and rate limit enforcement

4. **Webhook Progress** - Alternative to WebSocket for better reliability
   - Priority: LOW
   - Use Cloudflare Queues for async delivery

5. **Enhanced Metadata** - Wikipedia summaries, author photos, book awards
   - Priority: MEDIUM
   - Integrate additional data sources

6. **Author Search Analytics** - Track popular authors and cache warming
   - Priority: LOW
   - Use Analytics Engine to identify high-traffic authors
   - Proactively warm cache for Stephen King, J.K. Rowling, etc.

---

## Contributing

API changes require:
1. Update this contract document
2. Implement changes in `cloudflare-workers/api-worker/src/index.js`
3. Update iOS client (`BooksTrackerPackage/Sources/.../BookSearchAPIService.swift`)
4. Add tests for new endpoints
5. Deploy to production via `npm run deploy`

---

## Support

- **GitHub Issues:** https://github.com/jukasdrj/books-tracker-v1/issues
- **Email:** nerd@ooheynerds.com
- **Live Logs:** `npx wrangler tail api-worker --format pretty`
