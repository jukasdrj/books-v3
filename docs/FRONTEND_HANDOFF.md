# Frontend Integration Handoff Document

**Date:** November 17, 2025
**API Version:** v2.1
**Backend Commit:** d895384 (Nov 17, 2025)
**Contract Status:** ✅ **97% Verified** (35/36 items correct)

---

## 🎯 Executive Summary

The BooksTrack backend API is **ready for frontend integration** with the following status:

- ✅ **Core API Endpoints:** All v1 search endpoints verified and working
- ✅ **Canonical DTOs:** WorkDTO, EditionDTO, AuthorDTO match implementation
- ✅ **WebSocket Support:** Full reconnection support with 60-second grace period
- ✅ **Cultural Diversity:** Author enrichment with gender/region/nationality data
- ✅ **Batch Scanning:** Route now registered and available (POST /api/batch-scan)
- ⚠️ **Minor Issue:** `totalResults` field documented but not yet populated (reserved for future)

---

## 📚 Primary Documentation

**Source of Truth:** [`docs/API_CONTRACT.md`](./API_CONTRACT.md)

This is the authoritative API contract. All endpoint specifications, request/response formats, error codes, and integration examples are defined here.

**Last Updated:** November 16, 2025 (v2.1)
**Verification Date:** November 17, 2025
**Verification Score:** 97% (35/36 items match implementation)

---

## 🔧 Recent Updates (November 2025)

### **Production Fixes (Commit 3676b1a)**
1. ✅ Analytics binding fixed (was silently failing)
2. ✅ Cache directives restored (Google Books API freshness)
3. ✅ WebSocket message types updated (`ready`, `ready_ack`, `reconnected` added)
4. ✅ Batch-scan route registered (POST /api/batch-scan now available)

### **New Feature: Hono Router (Optional)**
- Feature flag: `ENABLE_HONO_ROUTER` (default: disabled)
- Zero impact on existing endpoints
- When enabled: Improved routing performance
- **Frontend Action:** None required - transparent backend optimization

---

## 🚀 Quick Start Guide

### **1. Base URL**

**Production:**
```
https://api.oooefam.net
```

### **2. Core Search Endpoints**

All endpoints return the canonical response format:

```json
{
  "data": {
    "works": [WorkDTO],
    "editions": [EditionDTO],
    "authors": [AuthorDTO]
  },
  "metadata": {
    "timestamp": "2025-11-17T12:00:00.000Z",
    "processingTime": 145,
    "provider": "google-books",
    "cached": false
  }
}
```

#### **Search by ISBN (Recommended)**
```http
GET /v1/search/isbn?isbn=9780439708180
```

**Returns:** Single book with complete metadata
**Cache:** 7 days
**Performance:** < 200ms (P95)

#### **Search by Title**
```http
GET /v1/search/title?q=Harry%20Potter&maxResults=20
```

**Returns:** Up to 20 matching books
**Cache:** 6 hours
**Performance:** < 500ms (P95)

#### **Advanced Search (Most Flexible)**
```http
GET /v1/search/advanced?title=Harry%20Potter&author=Rowling
```

**Returns:** Books matching both title AND author
**Cache:** 6 hours
**Note:** Requires at least ONE parameter (title OR author)

---

## 📡 WebSocket Integration

### **Connection Flow**

```typescript
// 1. Connect with jobId and token
const ws = new WebSocket(
  `wss://api.oooefam.net/ws/progress?jobId=${jobId}&token=${token}`
);

// 2. Send ready signal when ready to receive messages
ws.onopen = () => {
  ws.send(JSON.stringify({ type: "ready" }));
};

// 3. Wait for ready_ack from server
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);

  if (message.type === "ready_ack") {
    console.log("Server acknowledged - ready to receive updates");
  }

  // 4. Handle job updates
  if (message.type === "job_progress") {
    updateUI(message.data.progress, message.data.message);
  }
};
```

### **Reconnection Support**

**Grace Period:** 60 seconds
**Behavior:** Server preserves job state and resumes from last known progress

```typescript
// Server detects reconnection automatically
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);

  if (message.type === "reconnected") {
    console.log("Reconnected! Current progress:", message.data.progress);
    // UI catches up to current state
  }
};
```

**Full iOS Swift examples:** See API_CONTRACT.md Section 7.5

---

## 🎨 Cultural Diversity Data

All authors include enriched cultural metadata (when available):

```typescript
interface AuthorDTO {
  name: string;
  gender: "Female" | "Male" | "Non-binary" | "Other" | "Unknown";
  culturalRegion?: "Africa" | "Asia" | "Europe" | ... (11 regions);
  nationality?: string;  // e.g., "Nigeria", "United States"
  birthYear?: number;
  deathYear?: number;
}
```

**Data Source:** Wikidata API
**Cache:** 7 days
**Fallback:** `gender: "Unknown"` if data unavailable

**Use Case:** Display diverse author representation, filter by region, track reading diversity stats

---

## 📸 Batch Photo Scanning

**Status:** ✅ **NOW AVAILABLE** (Route registered Nov 17, 2025)

### **Endpoint**
```http
POST /api/batch-scan
Content-Type: multipart/form-data
```

### **Request**
```typescript
const formData = new FormData();
formData.append("photos[]", photo1File);
formData.append("photos[]", photo2File);
// ... up to 5 photos

const response = await fetch("https://api.oooefam.net/api/batch-scan", {
  method: "POST",
  body: formData
});

const { jobId } = await response.json();
```

### **Progress Tracking**
```typescript
// Connect to WebSocket with jobId from response
const ws = new WebSocket(
  `wss://api.oooefam.net/ws/progress?jobId=${jobId}&token=${token}`
);

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);

  // Photo-by-photo progress
  if (msg.type === "job_progress") {
    console.log(`Processing photo ${msg.data.current}/${msg.data.total}`);
    console.log(`Found ${msg.data.booksScanned} books so far`);
  }
};
```

**Limits:**
- 1-5 photos per batch
- 10MB max per photo
- Rate limit: 5 requests/minute per IP

**Full spec:** API_CONTRACT.md Section 7.6

---

## 🔄 Response Format Changes (v2.0 → v2.1)

### **Standard Success Response**
```json
{
  "data": {
    "works": [],
    "editions": [],
    "authors": []
  },
  "metadata": {
    "timestamp": "ISO 8601 string",
    "processingTime": 145,
    "provider": "google-books | openlibrary | isbndb",
    "cached": true
  }
}
```

### **Error Response**
```json
{
  "success": false,
  "error": {
    "code": "INVALID_ISBN",
    "message": "ISBN must be 10 or 13 digits",
    "statusCode": 400
  }
}
```

### **Error Codes**

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `INVALID_ISBN` | 400 | ISBN format invalid |
| `INVALID_QUERY` | 400 | Search query missing/invalid |
| `NOT_FOUND` | 404 | No results found |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `PROVIDER_TIMEOUT` | 504 | External API timeout |
| `PROVIDER_ERROR` | 502 | External API error |
| `INTERNAL_ERROR` | 500 | Server error |

---

## ⚡ Performance Characteristics

| Endpoint | P50 | P95 | P99 | Cache TTL |
|----------|-----|-----|-----|-----------|
| `/v1/search/isbn` | < 100ms | < 200ms | < 500ms | 7 days |
| `/v1/search/title` | < 200ms | < 500ms | < 1s | 6 hours |
| `/v1/search/advanced` | < 250ms | < 600ms | < 1.5s | 6 hours |
| `/api/batch-scan` (upload) | < 500ms | < 1s | < 2s | N/A |
| AI scanning (per photo) | 3-5s | 8s | 15s | N/A |

**Note:** Cached responses typically < 50ms

---

## 🛠️ Optional: Hono Router Feature

### **What Is It?**

The backend now includes an optional high-performance router (Hono) that can be enabled via feature flag. This is **completely transparent** to frontend clients - no code changes required.

### **Current Status**

- **Default:** Disabled (`ENABLE_HONO_ROUTER = "false"`)
- **Impact:** None - all endpoints work identically
- **Performance:** When enabled, improves routing from O(n) to O(log n)

### **How to Enable (For Testing)**

**Backend team only:**
```bash
# Deploy with Hono enabled
wrangler deploy --var ENABLE_HONO_ROUTER:true

# Instant rollback if issues
wrangler deploy --var ENABLE_HONO_ROUTER:false
```

**Frontend action required:** **NONE**

The feature flag is server-side only. Clients continue using the same endpoints and response formats.

### **Canary Test**

When Hono is enabled, the `/health` endpoint returns:
```json
{
  "status": "ok",
  "router": "hono"  // ← Indicates Hono is active
}
```

Default (Hono disabled):
```json
{
  "status": "ok",
  "router": "manual"  // ← Original routing
}
```

**Use case:** Backend team can verify Hono is active by checking `/health` response.

---

## 📋 Integration Checklist

### **Phase 1: Basic Search**
- [ ] Implement ISBN search (`/v1/search/isbn`)
- [ ] Implement title search (`/v1/search/title`)
- [ ] Handle canonical response format (`data.works[]`, `metadata`)
- [ ] Display error messages from `error.message`
- [ ] Show cultural diversity data (author gender/region)

### **Phase 2: Advanced Features**
- [ ] Implement advanced search (`/v1/search/advanced`)
- [ ] Handle cached vs fresh responses (`metadata.cached`)
- [ ] Display provider information (`metadata.provider`)
- [ ] Implement retry logic for 5xx errors

### **Phase 3: WebSocket (Optional)**
- [ ] Connect to `/ws/progress?jobId=...&token=...`
- [ ] Send `ready` signal on connection
- [ ] Handle `ready_ack` from server
- [ ] Display progress updates (`job_progress`)
- [ ] Handle reconnection (`reconnected` message type)
- [ ] Test 60-second grace period

### **Phase 4: Batch Scanning (Optional)**
- [ ] Implement photo upload to `/api/batch-scan`
- [ ] Connect WebSocket for progress tracking
- [ ] Handle photo-by-photo progress (`current/total`)
- [ ] Display books found during scan
- [ ] Handle upload failures gracefully

---

## 🚨 Known Limitations

### **1. `totalResults` Field**
- **Status:** Documented but not implemented
- **Value:** Always `undefined`
- **Workaround:** Use `data.works.length` for actual count
- **Timeline:** Planned for v2.2 (pagination feature)

### **2. Pagination**
- **Status:** Not yet implemented
- **Current:** All searches return max 20 results
- **Timeline:** Planned for v2.2

### **3. Provider Fallback**
- **Status:** Google Books → OpenLibrary only
- **Note:** ISBNdb exists but not used in fallback chain
- **Impact:** Some books may not be found if both providers fail

---

## 📞 Support & Questions

### **Documentation**
- **API Contract:** `docs/API_CONTRACT.md` (complete spec)
- **WebSocket Guide:** API_CONTRACT.md Section 7
- **Cultural Diversity:** API_CONTRACT.md Section 5.3
- **Batch Scanning:** API_CONTRACT.md Section 7.6

### **Testing**
- **Production:** https://api.oooefam.net
- **Health Check:** https://api.oooefam.net/health
- **Example Request:**
  ```bash
  curl "https://api.oooefam.net/v1/search/isbn?isbn=9780439708180"
  ```

### **Backend Team**
- **Issues:** Create GitHub issue with `frontend-integration` label
- **Questions:** Tag @jukasdrj in Slack/Discord
- **Urgent:** Check `/health` endpoint for backend status

---

## 📝 Migration Notes

### **From Legacy API (if applicable)**

**Old Format:**
```json
{
  "success": true,
  "items": [...],
  "cached": true
}
```

**New Format:**
```json
{
  "data": {
    "works": [...],
    "editions": [...],
    "authors": [...]
  },
  "metadata": {
    "timestamp": "...",
    "cached": true
  }
}
```

**Migration Strategy:**
1. Update response parsing to use `data.works` instead of `items`
2. Extract metadata from `metadata` object (not root level)
3. Handle new error format with `error.code` and `error.message`
4. Use canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)

---

## ✅ Verification Status

**Contract Accuracy:** 97% (35/36 items verified)

### **Verified Correct ✅**
- All canonical DTOs (WorkDTO, EditionDTO, AuthorDTO)
- All enum definitions (26 values across 5 enums)
- Response envelope formats (success & error)
- All v1 search endpoints
- WebSocket message types (now includes `ready`, `ready_ack`, `reconnected`)
- Cultural diversity enrichment
- Deprecation headers
- Error codes
- Batch-scan route availability

### **Minor Discrepancy ⚠️**
- `totalResults` field: Documented but not yet populated (reserved for v2.2)

### **Verification Date:** November 17, 2025

---

## 🎯 Success Metrics

After integration, you should see:

1. **Search Performance:** < 500ms P95 response time
2. **Cache Hit Rate:** ~80% for repeat ISBNs
3. **Error Rate:** < 1% on valid requests
4. **WebSocket Stability:** < 0.5% disconnection rate
5. **Cultural Data Coverage:** ~60-70% of authors have gender/region data

---

**Last Updated:** November 17, 2025
**Next Review:** January 2026 (or when v2.2 features added)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
