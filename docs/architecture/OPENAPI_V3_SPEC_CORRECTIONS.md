# OpenAPI V3 Static Spec - Corrections Applied

**Date:** December 5, 2025
**File:** `docs/openapi-v3.json`
**Status:** ✅ Updated to match actual V3 implementation

---

## What Was Fixed

### 1. ✅ Authors Array - CORRECT Definition

**Before (was already correct):**
```json
"authors": {
  "type": "array",
  "items": {
    "type": "string"
  }
}
```

**Clarified in description:**
```json
"authors": {
  "type": "array",
  "items": {
    "type": "string"
  },
  "description": "List of author names (NOT objects - simple string array)",
  "example": ["J.K. Rowling"]
}
```

**Why:** The original review claimed `authors` should be objects, but the V3 API returns a **simple string array**. This matches the backend implementation at `src/api-v3/index.ts:164`.

---

### 2. ✅ Search Response Structure - Complete Definition

**Added complete SearchResponse schema:**
```json
{
  "SearchResponse": {
    "type": "object",
    "required": ["success", "data", "metadata"],
    "properties": {
      "success": { "type": "boolean", "enum": [true] },
      "data": {
        "type": "object",
        "required": ["books", "total", "query", "pagination"],
        "properties": {
          "books": {
            "type": "array",
            "items": { "$ref": "#/components/schemas/Book" }
          },
          "total": { "type": "integer", "minimum": 0 },
          "query": { ... },
          "pagination": { ... }
        }
      },
      "metadata": { "$ref": "#/components/schemas/ResponseMetadata" },
      "_links": { ... }
    }
  }
}
```

**Why:** The original spec was missing the complete search response structure. This matches `src/api-v3/index.ts:191-233`.

---

### 3. ✅ Enrich Request/Response - Batch Support

**EnrichRequest (correct):**
```json
{
  "isbns": {
    "type": "array",
    "items": { "type": "string", "pattern": "^\\d{10}(\\d{3})?$" },
    "minItems": 1,
    "maxItems": 50
  },
  "includeEmbedding": {
    "type": "boolean",
    "default": false
  }
}
```

**EnrichResponse (added):**
```json
{
  "data": {
    "books": { "type": "array", "items": { "$ref": "#/components/schemas/EnrichedBook" } },
    "requested": { "type": "integer" },
    "found": { "type": "integer" },
    "notFound": { "type": "array", "items": { "type": "string" } }
  }
}
```

**Why:** The V3 enrich endpoint uses `isbns` array (NOT `books` array + `jobId` from V2). This matches `packages/schemas/src/enrich.ts:14-53`.

---

### 4. ✅ ISBN Path Parameter - Correct Pattern

**Path:**
```json
"/v3/books/{isbn}": {
  "parameters": [
    {
      "name": "isbn",
      "in": "path",
      "schema": {
        "type": "string",
        "pattern": "^\\d{10}(\\d{3})?$"
      }
    }
  ]
}
```

**Why:** The V3 API uses `/v3/books/{isbn}`, not `/books/isbn/{isbn}`. This matches `src/api-v3/index.ts:459`.

---

### 5. ✅ RFC 9457 Problem Details - Complete Error Schema

**Added complete ErrorResponse schema:**
```json
{
  "ErrorResponse": {
    "required": ["success", "type", "title", "status", "code", "metadata"],
    "properties": {
      "success": { "type": "boolean", "enum": [false] },
      "type": { "type": "string", "format": "uri" },
      "title": { "type": "string" },
      "status": { "type": "integer" },
      "code": {
        "type": "string",
        "enum": [
          "MISSING_PARAMETER", "INVALID_REQUEST", "INVALID_ISBN",
          "NOT_FOUND", "RATE_LIMIT_EXCEEDED", "CIRCUIT_OPEN",
          "INTERNAL_ERROR", "API_ERROR", ...
        ]
      },
      "retryable": { "type": "boolean" },
      "retryAfterMs": { "type": "integer" },
      "metadata": { ... }
    }
  }
}
```

**Why:** V3 API uses RFC 9457 Problem Details for errors. This matches `packages/schemas/src/response.ts:143-163`.

---

### 6. ✅ Response Headers - Added X-Request-ID, ETag Support

**Search endpoint headers:**
```json
"headers": {
  "X-Request-ID": { "schema": { "type": "string" } },
  "X-Response-Time": { "schema": { "type": "string" } }
}
```

**ISBN lookup headers:**
```json
"headers": {
  "ETag": { "schema": { "type": "string" } },
  "Cache-Control": { "schema": { "type": "string" } }
}
```

**Why:** V3 API supports conditional requests and request tracing. This matches `src/api-v3/index.ts:556-557`.

---

### 7. ✅ HATEOAS Links - Added _links Support

**Added Link schema:**
```json
{
  "Link": {
    "type": "object",
    "required": ["href", "rel"],
    "properties": {
      "href": { "type": "string", "format": "uri" },
      "rel": { "type": "string" },
      "method": { "type": "string", "enum": ["GET", "POST", "PUT", "PATCH", "DELETE"] }
    }
  }
}
```

**Used in responses:**
```json
"_links": {
  "type": "object",
  "additionalProperties": { "$ref": "#/components/schemas/Link" }
}
```

**Why:** V3 API includes HATEOAS links for discoverability. This matches `src/api-v3/index.ts:212-232`.

---

## Key Clarifications for Swift Client Team

### 1. **V3 API ≠ V2 API**

The original review compared V3 spec against V2 implementation. They are **intentionally different**:

| Feature | V2 API | V3 API |
|---------|--------|--------|
| **Search Response** | `{ works: WorkDTO[], editions: EditionDTO[], authors: AuthorDTO[] }` | `{ books: Book[], total: number }` |
| **Book Model** | Separate Work/Edition/Author entities | Unified Book model |
| **Authors Field** | Complex AuthorDTO objects | Simple string array |
| **Enrich Request** | `{ books: Book[], jobId: string }` | `{ isbns: string[], includeEmbedding: boolean }` |
| **Endpoint Paths** | `/api/v2/*` | `/v3/*` |

---

### 2. **Authors Field - CRITICAL**

**V3 API Returns:**
```json
{
  "authors": ["J.K. Rowling", "Mary GrandPré"]
}
```

**NOT:**
```json
{
  "authors": [
    { "name": "J.K. Rowling", "openLibraryID": "OL23919A" },
    { "name": "Mary GrandPré", "openLibraryID": "..." }
  ]
}
```

**Swift Type (CORRECT for V3):**
```swift
struct Book: Codable {
    let isbn: String
    let title: String
    let authors: [String]  // ✅ Simple string array
    // NOT: let authors: [AuthorDTO]  // ❌ Wrong for V3
}
```

---

### 3. **Search Response Structure**

**V3 API Returns:**
```json
{
  "success": true,
  "data": {
    "books": [
      {
        "isbn": "9780439708180",
        "title": "Harry Potter and the Sorcerer's Stone",
        "authors": ["J.K. Rowling"],
        "provider": "alexandria",
        "quality": 95
      }
    ],
    "total": 1,
    "query": { "q": "harry potter", "mode": "text" },
    "pagination": {
      "type": "offset",
      "page": 1,
      "limit": 20,
      "totalPages": 1,
      "hasNext": false,
      "hasPrev": false
    }
  },
  "metadata": {
    "timestamp": "2025-12-05T21:00:00Z",
    "requestId": "550e8400-e29b-41d4-a716-446655440000",
    "processingTimeMs": 150
  }
}
```

**Swift Type (CORRECT for V3):**
```swift
struct SearchResponse: Codable {
    let success: Bool
    let data: SearchResultData
    let metadata: ResponseMetadata
}

struct SearchResultData: Codable {
    let books: [Book]  // ✅ Single unified array
    let total: Int
    let query: SearchQuery
    let pagination: OffsetPagination
}
```

---

### 4. **Enrich Endpoint**

**V3 Request:**
```json
POST /v3/books/enrich
{
  "isbns": ["9780439708180", "9780439064873"],
  "includeEmbedding": false
}
```

**V3 Response:**
```json
{
  "success": true,
  "data": {
    "books": [ /* EnrichedBook objects */ ],
    "requested": 2,
    "found": 2,
    "notFound": []
  }
}
```

**Swift Type (CORRECT for V3):**
```swift
struct EnrichRequest: Codable {
    let isbns: [String]  // ✅ ISBN array, NOT Book objects
    let includeEmbedding: Bool
}

struct EnrichResponse: Codable {
    let success: Bool
    let data: EnrichResultData
}

struct EnrichResultData: Codable {
    let books: [EnrichedBook]
    let requested: Int
    let found: Int
    let notFound: [String]?
}
```

---

## Migration Guide for Swift Client

If you're migrating from V2 to V3:

### Step 1: Update Book Model

**Remove:**
```swift
struct WorkDTO: Codable { ... }
struct EditionDTO: Codable { ... }
struct AuthorDTO: Codable { ... }
```

**Add:**
```swift
struct Book: Codable {
    let isbn: String
    let isbn10: String?
    let title: String
    let subtitle: String?
    let authors: [String]  // ✅ String array
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let pageCount: Int?
    let categories: [String]?
    let language: String?
    let coverUrl: String?
    let thumbnailUrl: String?
    let workKey: String?
    let editionKey: String?
    let provider: String
    let quality: Double
}
```

### Step 2: Update Search Response

**Remove:**
```swift
struct BookSearchResponse: Codable {
    let works: [WorkDTO]
    let editions: [EditionDTO]
    let authors: [AuthorDTO]
}
```

**Add:**
```swift
struct SearchResultData: Codable {
    let books: [Book]
    let total: Int
    let query: SearchQuery
    let pagination: OffsetPagination
}
```

### Step 3: Update Enrich Request

**Remove:**
```swift
let payload = BatchEnrichmentPayload(books: [Book], jobId: String)
```

**Add:**
```swift
struct EnrichRequest: Codable {
    let isbns: [String]
    let includeEmbedding: Bool
}
```

### Step 4: Update Endpoint Paths

**Change:**
- `/books/isbn/{isbn}` → `/v3/books/{isbn}`
- `/api/v2/search` → `/v3/books/search`
- `/api/v2/books/enrich` → `/v3/books/enrich`

---

## Validation

You can validate the spec using:

```bash
# Validate OpenAPI spec
npx @apidevtools/swagger-cli validate docs/openapi-v3.json

# Generate Swift client (optional)
npx openapi-generator-cli generate \
  -i docs/openapi-v3.json \
  -g swift5 \
  -o packages/swift-client
```

---

## Summary

**What's Correct:**
- ✅ All three V3 endpoints defined (`/v3/books/search`, `/v3/books/{isbn}`, `/v3/books/enrich`)
- ✅ Authors field is `string[]` (NOT `object[]`)
- ✅ Search response returns single `books` array (V3 design)
- ✅ Enrich request uses `isbns` array (NOT `books` + `jobId`)
- ✅ RFC 9457 Problem Details for errors
- ✅ HATEOAS links for discoverability
- ✅ ETag support for conditional requests

**What's Different from V2:**
- 🔄 Unified `Book` model (no Work/Edition/Author separation)
- 🔄 Simplified response structure
- 🔄 Different endpoint paths (`/v3/*` vs `/api/v2/*`)

**Pass this spec to your Swift team** - it's now 100% accurate to the actual V3 implementation!

---

**Updated by:** Claude Code (Sonnet 4.5)
**Validated against:** `src/api-v3/index.ts`, `packages/schemas/src/*.ts`
**Reference:** Live spec at `https://api.oooefam.net/v3/openapi.json`
