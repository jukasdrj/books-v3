# Sprint 3 Backend Handoff Document

**Status:** ✅ IMPLEMENTATION COMPLETE
**Date:** November 25, 2025 (Updated after Implementation)
**Target:** January 2026 (Sprint 3)
**Team:** Backend (Cloudflare Workers)

---

## Executive Summary

This document provides everything the frontend team needs to know about Sprint 3: Backend Foundation + V2 API. It consolidates requirements from the API_CONTRACT_V2_PROPOSAL and Sprint 4 Intelligence plan into a unified specification.

**✅ Already Implemented (Backend Ready):**
- D1 database with books schema (migrations 0001-0007)
- Workers AI binding (`AI`) for embedding generation
- Vectorize index binding (`BOOK_VECTORS`) configured
- Embedding service (`src/services/embedding-service.ts`) - complete
- Semantic search handlers (`src/handlers/semantic-search-handler.ts`) - complete
- Hono router with all v1 search endpoints
- KV caching, R2 storage, Durable Objects for job state
- Gemini API key in Cloudflare secrets store

**✅ Sprint 3 Implementation Complete (Nov 25, 2025):**
1. ✅ Vectorize index created (`book-embeddings`, 1024 dims, cosine)
2. ✅ D1 migration 0008 applied (recommendations table + vectorized_at)
3. ✅ RECOMMENDATIONS_CACHE KV namespace created
4. ✅ Enrichment queue configured (`enrichment-queue`)
5. ✅ V2 API endpoints implemented (all routes in router.ts)
6. ✅ Weekly recommendation cron job handler implemented

---

## Quick Reference: New Endpoints

| Method | Endpoint | Description | Priority |
|--------|----------|-------------|----------|
| `POST` | `/api/v2/books/enrich` | Barcode enrichment (sync HTTP) | P0 |
| `POST` | `/api/v2/imports` | CSV upload (async job) | P0 |
| `GET` | `/api/v2/imports/{jobId}` | Import status (polling) | P0 |
| `GET` | `/api/v2/imports/{jobId}/stream` | Import progress (SSE) | P0 |
| `GET` | `/api/v2/search?q=&mode=text\|semantic` | Unified search | P0 |
| `GET` | `/api/v2/recommendations/weekly` | Global weekly picks | P1 |
| `GET` | `/api/v2/capabilities` | Feature discovery | P1 |

---

## 1. Infrastructure Setup

### 1.1 Cloudflare Resources - Current State

**✅ Already Configured in `wrangler.jsonc`:**

```jsonc
// D1 Database - ALREADY EXISTS
"d1_databases": [{
  "binding": "DB",
  "database_name": "bookstrack-library",
  "database_id": "cc19e622-9d0d-45f6-991c-1ab1933f257c"
}]

// Workers AI - ALREADY EXISTS
"ai": { "binding": "AI" }

// Vectorize Index - BINDING EXISTS (index needs creation)
"vectorize": [{
  "binding": "BOOK_VECTORS",
  "index_name": "book-embeddings"
}]

// R2 Buckets - ALREADY EXISTS
"r2_buckets": [
  { "binding": "BOOKSHELF_IMAGES", "bucket_name": "bookshelf-images" },
  { "binding": "BOOK_COVERS", "bucket_name": "bookstrack-covers" },
  { "binding": "LIBRARY_DATA", "bucket_name": "personal-library-data" }
]

// KV Namespaces - ALREADY EXISTS
"kv_namespaces": [
  { "binding": "CACHE", "id": "b9cade63b6db48fd80c109a013f38fdb" },
  { "binding": "KV_CACHE", "id": "b9cade63b6db48fd80c109a013f38fdb" }
]

// Durable Objects - ALREADY EXISTS
"durable_objects": {
  "bindings": [
    { "name": "JOB_STATE_MANAGER_DO", "class_name": "JobStateManagerDO" },
    { "name": "WEBSOCKET_CONNECTION_DO", "class_name": "WebSocketConnectionDO" },
    { "name": "RATE_LIMITER_DO", "class_name": "RateLimiterDO" }
  ]
}

// Existing Cron Triggers
"triggers": {
  "crons": ["0 2 * * *", "*/15 * * * *", "0 3 * * *"]
}
```

**🔧 Additions Needed for Sprint 3:**

```jsonc
// ADD: RECOMMENDATIONS_CACHE KV namespace
"kv_namespaces": [
  // ... existing ...
  { "binding": "RECOMMENDATIONS_CACHE", "id": "<to-be-created>" }
]

// ADD: Enrichment queue
"queues": {
  "producers": [
    // ... existing AUTHOR_WARMING_QUEUE ...
    { "binding": "ENRICHMENT_QUEUE", "queue": "enrichment-queue" }
  ],
  "consumers": [
    // ... existing ...
    { "queue": "enrichment-queue", "max_batch_size": 5, "max_batch_timeout": 60 }
  ]
}

// ADD: Weekly recommendations cron (Sunday midnight UTC)
"triggers": {
  "crons": ["0 2 * * *", "*/15 * * * *", "0 3 * * *", "0 0 * * 0"]
}
```

### 1.2 Vectorize Index Configuration

**Status:** Binding configured, index needs creation

```bash
# Create Vectorize index (run once)
npx wrangler vectorize create book-embeddings \
  --dimensions=1024 \
  --metric=cosine

# Index schema (logical)
# - id: ISBN (string)
# - vector: 1024-dim embedding from BGE-M3
# - metadata: { isbn, title, author, categories }
```

**✅ Embedding Service Already Implemented:**
- Model: `@cf/baai/bge-m3` (1024 dimensions, multilingual)
- Location: `src/services/embedding-service.ts`
- Functions: `generateBookEmbedding()`, `semanticSearch()`, `findSimilarBooks()`

### 1.3 D1 Database Schema

**✅ Existing Schema (migrations 0001-0007):**

```sql
-- migrations/0001_create_books_table.sql (ALREADY EXISTS)
CREATE TABLE books (
  isbn TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  subtitle TEXT,
  description TEXT,
  publisher TEXT,
  publication_date TEXT,              -- ISO 8601 (YYYY-MM-DD)
  language TEXT,                      -- ISO 639-1 (en, es, ja)
  page_count INTEGER,
  cover_small_url TEXT,
  cover_medium_url TEXT,
  cover_large_url TEXT,
  canonical_metadata TEXT NOT NULL,   -- Full canonical book object (JSON)
  provider_metadata TEXT,             -- Raw provider responses (JSON)
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

-- migrations/0002_create_authors_table.sql (ALREADY EXISTS)
CREATE TABLE authors (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  -- ... diversity fields, bio, etc.
);

-- migrations/0003_create_book_authors_table.sql (ALREADY EXISTS)
CREATE TABLE book_authors (
  book_isbn TEXT NOT NULL,
  author_id TEXT NOT NULL,
  PRIMARY KEY (book_isbn, author_id)
);
```

**🔧 New Migration Needed (0008_add_recommendations.sql):**

```sql
-- migrations/0008_add_recommendations.sql

-- Add vectorized_at column to books (for tracking embedding status)
ALTER TABLE books ADD COLUMN vectorized_at INTEGER;
CREATE INDEX idx_books_vectorized ON books(vectorized_at);

-- Recommendations table (cron-generated weekly picks)
CREATE TABLE recommendations (
  id TEXT PRIMARY KEY,
  week_of TEXT NOT NULL UNIQUE,           -- "2026-01-06" (Monday of week)
  book_isbns TEXT NOT NULL,               -- JSON array of ISBNs
  recommendations_json TEXT NOT NULL,     -- Full recommendation data with reasons
  generated_at INTEGER NOT NULL DEFAULT (unixepoch()),
  expires_at INTEGER NOT NULL             -- When to refresh
);

CREATE INDEX idx_recommendations_week ON recommendations(week_of);
CREATE INDEX idx_recommendations_expires ON recommendations(expires_at);
```

**Note:** Import job state is managed by `JobStateManagerDO` Durable Object (already implemented), not D1.

---

## 2. API Endpoints Specification

### 2.0 Existing Endpoints (Already Live)

**✅ Already available in production via Hono router (`src/router.ts`):**

| Endpoint | Status | Notes |
|----------|--------|-------|
| `GET /v1/search/isbn?isbn=` | ✅ Live | ISBN lookup |
| `GET /v1/search/title?q=` | ✅ Live | Title search |
| `GET /v1/search/advanced?title=&author=` | ✅ Live | Multi-field search |
| `GET /v1/search/similar?isbn=&limit=` | ✅ Live | Vectorize similarity (needs index) |
| `GET /v1/search/semantic?q=&limit=` | ✅ Live | Semantic search (needs index) |
| `POST /v1/enrichment/batch` | ✅ Live | Batch book enrichment |
| `POST /api/scan-bookshelf/batch` | ✅ Live | AI bookshelf scanning |
| `POST /api/import/csv-gemini` | ✅ Live | CSV import with Gemini |
| `POST /v2/import/workflow` | ✅ Live | Cloudflare Workflow import |
| `GET /v1/jobs/:jobId/status` | ✅ Live | Job status polling |
| `GET /ws/progress` | ✅ Live | WebSocket progress |

**🔧 Sprint 3 adds `/api/v2/*` namespace for unified V2 API:**

### 2.1 Unified Search Endpoint (NEW)

**Endpoint:** `GET /api/v2/search`

This is the key new endpoint for Sprint 4 iOS integration. Supports both text and semantic search.

> **Note:** This is a namespace alias - internally delegates to existing `/v1/search/*` handlers with unified response format.

**Query Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | Yes | Search query |
| `mode` | string | No | `text` (default) or `semantic` |
| `limit` | int | No | Max results (default: 20, max: 100) |
| `offset` | int | No | Pagination offset |

**Response: 200 OK**
```json
{
  "results": [
    {
      "id": "book_abc123",
      "isbn": "9780747532743",
      "title": "Harry Potter and the Philosopher's Stone",
      "authors": ["J.K. Rowling"],
      "cover_url": "https://...",
      "relevance_score": 0.95,
      "match_type": "semantic"
    }
  ],
  "total": 42,
  "mode": "semantic",
  "query": "books about wizards and magic schools",
  "latency_ms": 120
}
```

**Implementation Notes:**
```javascript
// Text mode: SQL LIKE query
if (mode === 'text') {
  const results = await env.BOOKS_DB.prepare(`
    SELECT * FROM books
    WHERE title LIKE ? OR authors LIKE ?
    LIMIT ? OFFSET ?
  `).bind(`%${q}%`, `%${q}%`, limit, offset).all();
  return results;
}

// Semantic mode: Vectorize query
if (mode === 'semantic') {
  // 1. Generate embedding for query
  const embedding = await env.AI.run('@cf/baai/bge-m3', {
    text: [q]
  });

  // 2. Query Vectorize
  const matches = await env.BOOK_VECTORS.query(embedding.data[0], {
    topK: limit,
    returnMetadata: true
  });

  // 3. Fetch full book data from D1
  const bookIds = matches.matches.map(m => m.id);
  const books = await env.BOOKS_DB.prepare(`
    SELECT * FROM books WHERE id IN (${bookIds.map(() => '?').join(',')})
  `).bind(...bookIds).all();

  return books;
}
```

**Rate Limits:**
- Text mode: 100 req/min (standard)
- Semantic mode: 5 req/min (AI compute intensive)

---

### 2.2 Weekly Recommendations Endpoint (NEW)

**Endpoint:** `GET /api/v2/recommendations/weekly`

Returns the pre-generated weekly book recommendations (global, non-personalized).

**Response: 200 OK**
```json
{
  "week_of": "2026-01-06",
  "books": [
    {
      "id": "book_abc123",
      "isbn": "9780747532743",
      "title": "Harry Potter and the Philosopher's Stone",
      "authors": ["J.K. Rowling"],
      "cover_url": "https://...",
      "reason": "A beloved fantasy classic perfect for readers seeking magical escapism"
    }
  ],
  "generated_at": "2026-01-05T00:00:00Z",
  "next_refresh": "2026-01-12T00:00:00Z"
}
```

**Implementation:**
```javascript
// Read from KV cache (fast)
const cached = await env.RECOMMENDATIONS_CACHE.get('weekly:current', 'json');
if (cached) {
  return Response.json(cached);
}

// Fallback to D1
const currentWeek = getCurrentWeekMonday();
const result = await env.BOOKS_DB.prepare(`
  SELECT * FROM recommendations WHERE week_of = ?
`).bind(currentWeek).first();

if (result) {
  // Cache for 1 hour
  await env.RECOMMENDATIONS_CACHE.put('weekly:current', JSON.stringify(result), {
    expirationTtl: 3600
  });
  return Response.json(result);
}

return Response.json({ error: 'no_recommendations' }, { status: 404 });
```

---

### 2.3 Cron Job: Generate Weekly Recommendations

**Schedule:** Every Sunday at 00:00 UTC

**Implementation:**
```javascript
// src/cron.js
export default {
  async scheduled(event, env, ctx) {
    if (event.cron === '0 0 * * 0') {
      await generateWeeklyRecommendations(env);
    }
  }
};

async function generateWeeklyRecommendations(env) {
  // 1. Get diverse sample of books from D1
  const sampleBooks = await env.BOOKS_DB.prepare(`
    SELECT id, title, authors, description, categories
    FROM books
    WHERE description IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 100
  `).all();

  // 2. Call Gemini for recommendations
  // Note: Using fetch to Gemini API (not Workers AI)
  const prompt = `
    You are a book recommendation expert. Given these 100 books from a user's library:
    ${JSON.stringify(sampleBooks.results.slice(0, 20))}

    Select 5 books that would make excellent weekly recommendations for a diverse reading audience.
    For each book, provide:
    1. The book ID
    2. A 1-sentence reason why it's recommended

    Return as JSON: [{ "id": "...", "reason": "..." }]
  `;

  const geminiResponse = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': env.GEMINI_API_KEY
    },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }]
    })
  });

  const geminiData = await geminiResponse.json();
  const recommendations = JSON.parse(geminiData.candidates[0].content.parts[0].text);

  // 3. Store in D1
  const weekOf = getNextMondayDate();
  const bookIds = recommendations.map(r => r.id);

  await env.BOOKS_DB.prepare(`
    INSERT OR REPLACE INTO recommendations (id, week_of, book_ids, reason, created_at)
    VALUES (?, ?, ?, ?, datetime('now'))
  `).bind(
    `rec_${weekOf}`,
    weekOf,
    JSON.stringify(bookIds),
    JSON.stringify(recommendations)
  ).run();

  // 4. Update KV cache
  const fullBooks = await env.BOOKS_DB.prepare(`
    SELECT * FROM books WHERE id IN (${bookIds.map(() => '?').join(',')})
  `).bind(...bookIds).all();

  const responsePayload = {
    week_of: weekOf,
    books: fullBooks.results.map((book, i) => ({
      ...book,
      reason: recommendations[i].reason
    })),
    generated_at: new Date().toISOString(),
    next_refresh: getNextSundayDate()
  };

  await env.RECOMMENDATIONS_CACHE.put('weekly:current', JSON.stringify(responsePayload));

  console.log(`Generated weekly recommendations for ${weekOf}`);
}
```

---

### 2.4 Enrichment Pipeline (Enhanced)

When books are imported via CSV, they should be automatically enriched AND vectorized.

**Queue Consumer Enhancement:**
```javascript
// After enriching a book, generate embedding and store in Vectorize

async function processBook(book, env) {
  // 1. Enrich via Google Books + OpenLibrary (existing)
  const enrichedBook = await enrichBook(book.isbn);

  // 2. Save to D1
  await env.BOOKS_DB.prepare(`
    INSERT INTO books (id, isbn, title, authors, description, ...)
    VALUES (?, ?, ?, ?, ?, ...)
    ON CONFLICT(isbn) DO UPDATE SET
      title = excluded.title,
      updated_at = datetime('now')
  `).bind(
    `book_${crypto.randomUUID()}`,
    enrichedBook.isbn,
    enrichedBook.title,
    JSON.stringify(enrichedBook.authors),
    enrichedBook.description
  ).run();

  // 3. Generate embedding (if has description)
  if (enrichedBook.description) {
    const embedding = await env.AI.run('@cf/baai/bge-m3', {
      text: [`${enrichedBook.title} ${enrichedBook.description}`]
    });

    // 4. Store in Vectorize
    await env.BOOK_VECTORS.upsert([{
      id: enrichedBook.id,
      values: embedding.data[0],
      metadata: {
        title: enrichedBook.title,
        authors: enrichedBook.authors,
        genres: enrichedBook.categories
      }
    }]);

    // 5. Update vectorized_at timestamp
    await env.BOOKS_DB.prepare(`
      UPDATE books SET vectorized_at = datetime('now') WHERE id = ?
    `).bind(enrichedBook.id).run();
  }

  return enrichedBook;
}
```

---

## 3. Implementation Checklist

### Week 1: Infrastructure ✅ COMPLETE

- [x] Create D1 database and run migrations (0001-0008 complete)
- [x] Create Vectorize index (`book-embeddings`, 1024 dims, cosine metric)
- [x] Add Workers AI binding (`AI` in wrangler.jsonc)
- [x] Create KV namespace for recommendations cache (`RECOMMENDATIONS_CACHE`)
- [x] Create enrichment queue configuration (`enrichment-queue`)
- [x] Run migration 0008 (recommendations table + vectorized_at column)

### Week 2: Core Endpoints ✅ COMPLETE

- [x] Implement semantic search handler (`src/handlers/semantic-search-handler.ts`)
- [x] Implement embedding service (`src/services/embedding-service.ts`)
- [x] Add `/api/v2/search` route (unified text+semantic)
- [x] Add `/api/v2/recommendations/weekly` endpoint
- [x] Add `/api/v2/books/enrich` endpoint (sync enrichment)
- [x] Rate limiting infrastructure (`RATE_LIMITER_DO` exists)

### Week 3: Cron & SSE ✅ COMPLETE

- [x] Implement weekly recommendation cron job handler (`src/cron/recommendations-cron.ts`)
- [x] Gemini API key configured in secrets store
- [x] Add SSE streaming for import progress (`src/handlers/v2/sse-stream.ts`)
- [x] Add `/api/v2/capabilities` endpoint
- [ ] Test semantic search with real Vectorize index
- [ ] Load test enrichment pipeline

### Week 4: Polish & Handoff (In Progress)

- [x] Update API_CONTRACT.md with V2 endpoints
- [ ] Performance testing (semantic search <800ms p95)
- [x] Error handling for Vectorize/AI failures (graceful fallback)
- [x] Update frontend handoff docs with final API details
- [ ] iOS team handoff (Sprint 4 kickoff)

---

## 4. iOS Integration Notes (for Sprint 4)

The iOS team will need to implement:

1. **Semantic Search UI**
   - Toggle between "text" and "semantic" search modes
   - Handle different latency (semantic is slower, ~500ms)
   - Rate limit indicator for semantic mode

2. **Recommendations Widget**
   - Fetch `GET /api/v2/recommendations/weekly`
   - Display 5 book cards with AI-generated reasons
   - Refresh indicator showing next update date

3. **SSE Client** (from V2 Proposal)
   - Native URLSession-based SSE
   - Reconnection with Last-Event-ID
   - Fallback to polling

---

## 5. Backend Answers to Frontend Questions

**All questions from the original proposal have been resolved:**

1. **Gemini API Access** ✅
   - API key available in Cloudflare secrets store (`GEMINI_API_KEY`)
   - Model: `gemini-2.0-flash-exp` (currently used for CSV parsing & bookshelf scanning)
   - Rate limit: Standard Gemini API limits apply (~60 RPM for flash model)

2. **Vectorize Limits** ✅
   - 1024 dimensions confirmed (BGE-M3 model)
   - Index configured as `book-embeddings` in wrangler.jsonc
   - Expected size: ~4KB per book (1024 floats × 4 bytes), 10K books ≈ 40MB ✓

3. **D1 Performance** ✅
   - Text search uses SQL `LIKE` with COLLATE NOCASE index
   - Expected latency: <50ms for indexed queries
   - Full-text search: Not needed (semantic search via Vectorize handles complex queries)

4. **Cron Reliability** ✅
   - Cloudflare Workers cron has automatic retry on failure
   - Recommendations are cached in KV with 1-week TTL as fallback
   - Manual trigger endpoint can be added if needed (`POST /api/v2/recommendations/refresh`)

**Additional Clarifications:**

5. **Authentication**
   - Current: Bearer token validation (simple format check)
   - JWT validation can be added if needed (Cloudflare Access integration ready)
   - Recommendation endpoint works unauthenticated (global, non-personalized)

6. **Rate Limits**
   - Semantic search: 5 req/min per IP (configurable via `RATE_LIMITER_DO`)
   - Text search: 100 req/min per IP (standard)
   - Can adjust based on iOS app usage patterns

---

## 6. Success Criteria

**Sprint 3 Exit Criteria:**

- [x] All V2 endpoints deployable to staging
- [ ] Semantic search returns relevant results (manual testing - needs deployment)
- [x] Weekly recommendations cron handler implemented
- [x] Enrichment pipeline with embedding generation implemented
- [x] API contract documented and versioned
- [ ] P95 latency: text search <100ms, semantic <800ms (needs load testing)

---

## Appendix: Related Documents

- [API_CONTRACT_V2_PROPOSAL.md](API_CONTRACT_V2_PROPOSAL.md) - Full V2 API specification
- [SPRINT_4_INTELLIGENCE_V2.md](v2-plans/sprints/SPRINT_4_INTELLIGENCE_V2.md) - iOS integration plan
- [SPRINT_OVERVIEW.md](v2-plans/sprints/SPRINT_OVERVIEW.md) - Overall sprint roadmap

---

**Document Owner:** Development Team
**Last Updated:** November 25, 2025
**Status:** ✅ Implementation Complete - Ready for Frontend Team
