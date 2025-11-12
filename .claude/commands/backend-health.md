---
description: Check Cloudflare Worker health and configuration status
---

🏥 **Backend Health Check** 🏥

Comprehensive health check for api-worker using Cloudflare MCP tools for deep diagnostics.

**Tasks:**

1. **Worker Details (via MCP)**
   - Use `mcp__cloudflare-observability__workers_get_worker` with scriptName: "api-worker"
   - Display:
     - Deployment status
     - Last modified date
     - Active bindings configuration
     - Environment variables
     - Routes and triggers

2. **HTTP Health Endpoint**
   - Call `GET https://api-worker.jukasdrj.workers.dev/health`
   - Parse response JSON
   - Display:
     - Worker status (healthy/degraded/down)
     - Version info
     - Binding status (KV, R2, Secrets Store, Durable Objects)
     - Available endpoints

3. **Binding Validation**
   - Check Secrets Store secrets are configured:
     - GEMINI_API_KEY (google_gemini_oooebooks)
     - GOOGLE_BOOKS_API_KEY (Google_books_hardoooe)
     - ISBNDB_API_KEY
   - Verify KV namespace (CACHE / KV_CACHE)
   - Verify R2 buckets (BOOKSHELF_IMAGES, LIBRARY_DATA, API_CACHE_COLD)
   - Verify Durable Object (PROGRESS_WEBSOCKET_DO)
   - Verify Queue (AUTHOR_WARMING_QUEUE)
   - Verify Analytics Engine datasets (4 total)

4. **Test Critical Endpoints**
   - **Search:** `GET /search/title?q=gatsby`
   - **WebSocket:** `GET /ws/progress?jobId=test` (should return upgrade required)
   - **Metrics:** `GET /metrics` (cache analytics)

5. **Recent Error Check (via MCP)**
   - Use `mcp__cloudflare-observability__query_worker_observability`
   - Query for errors in last 10 minutes:
     - View: events
     - Filters: $metadata.level = "error"
     - Timeframe: Last 10 minutes
     - Limit: 10
   - Display error count and recent error messages

6. **Performance Metrics (via MCP)**
   - Query p50/p99 response times for last hour
   - Check request success rate
   - Identify slow endpoints (>5s response time)

**Expected Response:**
```json
{
  "status": "healthy",
  "worker": "api-worker",
  "version": "3.0.1",
  "endpoints": ["/search/title", "/search/isbn", "/api/scan-bookshelf", ...],
  "bindings": {
    "kv": ["CACHE", "KV_CACHE"],
    "r2": ["BOOKSHELF_IMAGES", "LIBRARY_DATA", "API_CACHE_COLD"],
    "secrets": ["GEMINI_API_KEY", "GOOGLE_BOOKS_API_KEY", "ISBNDB_API_KEY"],
    "durableObjects": ["PROGRESS_WEBSOCKET_DO"],
    "queues": ["AUTHOR_WARMING_QUEUE"],
    "analytics": ["PERFORMANCE_ANALYTICS", "CACHE_ANALYTICS", ...]
  }
}
```

**Health Indicators:**
- ✅ All bindings present
- ✅ Secrets accessible
- ✅ Endpoints responding
- ✅ No recent errors
- ⚠️ Degraded: Some bindings missing or slow
- ❌ Down: Worker not responding

If health check fails, provide diagnostic steps and suggest fixes.
