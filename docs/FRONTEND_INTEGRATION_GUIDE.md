# BooksTrack API - Frontend Integration Guide

**Status:** ✅ Production Ready
**API Version:** v2.7.0
**Last Updated:** November 25, 2025
**Audience:** iOS, Flutter, Web Frontend Teams

---

## 🚀 Quick Start

**Production API Base URL:** `https://api.oooefam.net`

**Health Check:**
```bash
curl https://api.oooefam.net/health
```

**Full API Contract:** See [`API_CONTRACT.md`](API_CONTRACT.md) for complete specifications.

---

## 📋 All Available Endpoints

### V1 Search Endpoints (Production)

| Method | Endpoint | Description | iOS Implementation |
|--------|----------|-------------|-------------------|
| `GET` | `/v1/search/title?q={query}` | Title search | ✅ BookSearchAPIService.swift:40-41 |
| `GET` | `/v1/search/isbn?isbn={isbn}` | ISBN lookup | ✅ BookSearchAPIService.swift:51-52 |
| `GET` | `/v1/search/advanced?title=&author=` | Multi-field search | ✅ BookSearchAPIService.swift:47-48 |
| `GET` | `/v1/search/similar?isbn={isbn}` | Similar books (semantic) | ✅ **IMPLEMENTED** (src/handlers/semantic-search-handler.ts) |
| `GET` | `/v1/search/semantic?q={query}` | Semantic search | ✅ **IMPLEMENTED** (src/handlers/semantic-search-handler.ts) |

### V2 API Endpoints (NEW - Sprint 3)

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| `GET` | `/api/v2/search?q=&mode=text\|semantic` | Unified search | ✅ **LIVE** (src/handlers/v2/search.ts) |
| `GET` | `/api/v2/recommendations/weekly` | AI weekly picks | ✅ **LIVE** (src/handlers/v2/recommendations.ts) |
| `GET` | `/api/v2/capabilities` | Feature discovery | ✅ **LIVE** (src/handlers/v2/capabilities.ts) |
| `POST` | `/api/v2/books/enrich` | Sync HTTP enrichment | ✅ **LIVE** (src/handlers/v2/enrich.ts) |
| `POST` | `/api/v2/imports` | CSV upload | ✅ **LIVE** (src/router.ts:1370) |
| `GET` | `/api/v2/imports/{jobId}` | Import status polling | ✅ **LIVE** (src/router.ts:1375) |
| `GET` | `/api/v2/imports/{jobId}/stream` | SSE progress stream | ✅ **LIVE** (src/handlers/v2/sse-stream.ts) |

### Enrichment & Import Endpoints

| Method | Endpoint | Description | iOS Implementation |
|--------|----------|-------------|-------------------|
| `POST` | `/v1/enrichment/batch` | Batch book enrichment | ✅ **LIVE** |
| `POST` | `/api/scan-bookshelf/batch` | AI bookshelf scan | ⚠️ **PATH CORRECTED** (was documented as /api/batch-scan) |
| `POST` | `/api/import/csv-gemini` | CSV import (v1) | ✅ EnrichmentConfig.swift:66 |
| `POST` | `/v2/import/workflow` | Workflow-based import | ✅ **LIVE** |
| `GET` | `/v1/jobs/:jobId/status` | Job status | ✅ **LIVE** |

### WebSocket Endpoints

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| `GET` | `/ws/progress?jobId={id}` | WebSocket progress | ✅ EnrichmentConfig.swift:86-88 |

### Admin & Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/metrics` | Prometheus metrics |
| `GET` | `/api/cache-metrics` | KV cache performance |
| `GET` | `/admin/harvest-dashboard` | Cover harvest dashboard |

---

## 🆕 V2 API Details

### 1. Unified Search

**Endpoint:** `GET /api/v2/search`

**Query Parameters:**
- `q` (required): Search query
- `mode` (optional): `text` (default) or `semantic`
- `limit` (optional): Max results (default: 20, max: 100)
- `offset` (optional): Pagination offset

**Example (Text Mode):**
```http
GET /api/v2/search?q=harry+potter&mode=text&limit=10
```

**Example (Semantic Mode):**
```http
GET /api/v2/search?q=books+about+wizards&mode=semantic&limit=10
```

**Response:**
```json
{
  "results": [
    {
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

**Rate Limits:**
- Text mode: 100 req/min
- Semantic mode: 5 req/min (AI compute intensive)

---

### 2. Weekly Recommendations

**Endpoint:** `GET /api/v2/recommendations/weekly`

**Response:**
```json
{
  "week_of": "2025-11-25",
  "books": [
    {
      "isbn": "9780747532743",
      "title": "Harry Potter and the Philosopher's Stone",
      "authors": ["J.K. Rowling"],
      "cover_url": "https://...",
      "reason": "A beloved fantasy classic perfect for readers seeking magical escapism"
    }
  ],
  "generated_at": "2025-11-24T00:00:00Z",
  "next_refresh": "2025-12-01T00:00:00Z"
}
```

**Notes:**
- Generated every Sunday at midnight UTC via cron job
- Cached in KV (1-week TTL)
- Non-personalized (global picks)

---

### 3. Capabilities Discovery

**Endpoint:** `GET /api/v2/capabilities`

**Response:**
```json
{
  "features": {
    "semantic_search": true,
    "similar_books": true,
    "weekly_recommendations": true,
    "sse_streaming": true,
    "batch_enrichment": true,
    "csv_import": true
  },
  "limits": {
    "semantic_search_rpm": 5,
    "text_search_rpm": 100,
    "csv_max_rows": 500,
    "batch_max_photos": 5
  },
  "version": "2.7.0"
}
```

**Use Case:** Client feature detection on app launch

---

### 4. Sync Book Enrichment

**Endpoint:** `POST /api/v2/books/enrich`

**Request:**
```json
{
  "barcode": "9780747532743",
  "prefer_provider": "auto",
  "idempotency_key": "scan_20251125_abc123"
}
```

**Response (200 OK):**
```json
{
  "isbn": "9780747532743",
  "title": "Harry Potter and the Philosopher's Stone",
  "authors": ["J.K. Rowling"],
  "publisher": "Bloomsbury",
  "published_date": "1997-06-26",
  "page_count": 223,
  "cover_url": "https://...",
  "description": "Harry Potter has never been...",
  "provider": "orchestrated:google+openlibrary",
  "enriched_at": "2025-11-25T10:30:00Z"
}
```

**Error Response (404):**
```json
{
  "error": {
    "code": "BOOK_NOT_FOUND",
    "message": "No book data found for ISBN 9780747532743",
    "providers_checked": ["google", "openlibrary"]
  }
}
```

---

### 5. CSV Import (V2)

**Step 1: Upload CSV**

**Endpoint:** `POST /api/v2/imports`

**Request (multipart/form-data):**
```
file: <CSV binary data>
options: {"auto_enrich": true, "skip_duplicates": true}
```

**Response (202 Accepted):**
```json
{
  "job_id": "import_abc123def456",
  "status": "queued",
  "created_at": "2025-11-25T10:30:00Z",
  "sse_url": "/api/v2/imports/import_abc123def456/stream",
  "status_url": "/api/v2/imports/import_abc123def456",
  "estimated_rows": 150
}
```

**Step 2: Stream Progress (SSE)**

**Endpoint:** `GET /api/v2/imports/{jobId}/stream`

**Headers:**
```
Accept: text/event-stream
Cache-Control: no-cache
```

**SSE Events:**
```
event: started
data: {"status": "processing", "total_rows": 150}

event: progress
data: {"progress": 0.5, "processed_rows": 75}

event: complete
data: {"status": "complete", "result_summary": {...}}
```

**Step 3: Polling Fallback**

**Endpoint:** `GET /api/v2/imports/{jobId}`

**Response (200 OK):**
```json
{
  "job_id": "import_abc123def456",
  "status": "processing",
  "progress": 0.67,
  "total_rows": 150,
  "processed_rows": 100,
  "successful_rows": 95,
  "failed_rows": 5
}
```

---

## ⚠️ Path Corrections

### Batch Scan Endpoint

**❌ INCORRECT (old documentation):**
```
POST /api/batch-scan
```

**✅ CORRECT (actual implementation):**
```
POST /api/scan-bookshelf/batch
```

**iOS Implementation:** ✅ Already correct in `EnrichmentConfig.swift:54`

---

### CSV Status Endpoint

**Note:** iOS currently uses `/v1/csv/status/{jobId}` but should migrate to:
- V2 Polling: `GET /api/v2/imports/{jobId}`
- V2 SSE: `GET /api/v2/imports/{jobId}/stream`

---

## 🔗 Infrastructure (Sprint 3)

**All deployed and production-ready:**

| Component | Status | Details |
|-----------|--------|---------|
| D1 Database | ✅ Live | `bookstrack-library` with migrations 0001-0008 |
| Vectorize Index | ✅ Created | `book-embeddings` (1024 dims, cosine) |
| Workers AI | ✅ Bound | `AI` binding for BGE-M3 embeddings |
| Embedding Service | ✅ Live | `src/services/embedding-service.ts` |
| Semantic Search | ✅ Live | `src/handlers/semantic-search-handler.ts` |
| KV Cache | ✅ Created | `RECOMMENDATIONS_CACHE` namespace |
| Enrichment Queue | ✅ Created | `enrichment-queue` |
| Cron Triggers | ✅ Configured | Sunday midnight UTC for recommendations |
| Gemini API Key | ✅ In Secrets | Available as `GEMINI_API_KEY` |

---

## 📊 Performance SLAs

| Metric | Target | Notes |
|--------|--------|-------|
| Uptime | 99.9% | Cloudflare Workers SLA |
| Text search latency (P95) | < 100ms | D1 SQL queries |
| Semantic search latency (P95) | < 800ms | Vectorize + AI |
| ISBN lookup (P95) | < 500ms | With KV cache |
| CSV import (150 rows) | < 2 min | With enrichment |
| WebSocket connection stability | > 95% | Auto-reconnect |
| SSE connection success rate | > 80% | Polling fallback |

---

## 🔒 Authentication

**Current:** Bearer token validation (simple format check)

**Header:**
```
Authorization: Bearer <token>
```

**Future:** JWT validation with Cloudflare Access (when needed)

---

## 📚 Complete Documentation

| Document | Purpose |
|----------|---------|
| **[API_CONTRACT.md](API_CONTRACT.md)** | **Complete API specification** (source of truth) |
| [API_CONTRACT_V2_SPEC.md](API_CONTRACT_V2_SPEC.md) | Detailed V2 API implementation spec |
| [SPRINT_3_BACKEND_HANDOFF.md](SPRINT_3_BACKEND_HANDOFF.md) | Backend infrastructure details |
| [openapi.yaml](openapi.yaml) | OpenAPI 3.0 specification |
| [README.md](../README.md) | Project overview |

---

## ✅ Frontend Validation Checklist

**Verify these endpoints are working:**

1. ✅ `/v1/search/title?q=harry`
2. ✅ `/v1/search/isbn?isbn=9780747532743`
3. ✅ `/v1/search/advanced?title=harry&author=rowling`
4. ✅ `/api/v2/search?q=wizards&mode=semantic`
5. ✅ `/api/v2/recommendations/weekly`
6. ✅ `/api/v2/capabilities`
7. ✅ `/api/v2/books/enrich` (POST)
8. ✅ `/api/v2/imports` (POST)
9. ✅ `/api/v2/imports/{jobId}/stream` (SSE)
10. ✅ `/api/scan-bookshelf/batch` (POST) ← **Corrected path**

---

## 🐛 Known Issues & Migrations

### Issue: PRD Documents Non-Existent Endpoint Names

**Problem:** Some PRD documents reference aspirational v2 endpoint names that don't match production.

**Resolution:** This document provides the **actual production endpoints**. All endpoints listed here are ✅ **LIVE and tested**.

### Migration: WebSocket → V2 SSE

**Current:** WebSocket API (`/ws/progress`) remains fully supported
**Future:** Optional migration to V2 SSE (`/api/v2/imports/{jobId}/stream`)

**Benefits of V2 SSE:**
- Survives network transitions (WiFi ↔ cellular)
- Works through firewalls/proxies
- Battery-efficient (radio sleep between events)

**Timeline:** No sunset date for WebSocket - migrate when convenient

---

## 💬 Support

**Questions?**
- Check [`API_CONTRACT.md`](API_CONTRACT.md) first (comprehensive specs)
- Review [`openapi.yaml`](openapi.yaml) for machine-readable schema
- Contact backend team with specific endpoint questions

**Report Issues:**
- Production errors: Include Cloudflare Ray ID from response headers
- API contract violations: Reference section number in API_CONTRACT.md
- Performance issues: Include timestamps and endpoint paths

---

**Last Updated:** November 25, 2025
**Document Owner:** Backend Team
**Maintained By:** Development Team

