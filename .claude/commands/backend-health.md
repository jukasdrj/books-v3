---
description: Check Cloudflare Worker health and configuration status
---

🏥 **Backend Health Check** 🏥

Comprehensive health check for api-worker with diagnostics and configuration validation.

**Tasks:**

1. **HTTP Health Endpoint**
   - Call `GET https://api-worker.jukasdrj.workers.dev/health`
   - Parse response JSON
   - Display:
     - Worker status (healthy/degraded/down)
     - Version info
     - Binding status (KV, R2, Secrets Store, Durable Objects)
     - Available endpoints

2. **Binding Validation**
   - Check Secrets Store secrets are configured:
     - GEMINI_API_KEY (google_gemini_oooebooks)
     - GOOGLE_BOOKS_API_KEY (Google_books_hardoooe)
     - ISBNDB_API_KEY
   - Verify KV namespace (CACHE / KV_CACHE)
   - Verify R2 buckets (BOOKSHELF_IMAGES, LIBRARY_DATA, API_CACHE_COLD)
   - Verify Durable Object (PROGRESS_WEBSOCKET_DO)
   - Verify Queue (AUTHOR_WARMING_QUEUE)
   - Verify Analytics Engine datasets (4 total)

3. **Test Critical Endpoints**
   - **Search:** `GET /search/title?q=gatsby`
   - **WebSocket:** `GET /ws/progress?jobId=test` (should return upgrade required)
   - **Metrics:** `GET /metrics` (cache analytics)

4. **Configuration Summary**
   - Show environment variables (cache TTLs, logging config)
   - Display cron schedules (daily archival, alert checks)
   - List queue consumers and producers
   - Show worker limits (CPU: 180s, Memory: 256MB)

5. **Diagnostics**
   - Check for recent errors in logs (last 10 minutes)
   - Verify API key access (test Secrets Store `.get()` pattern)
   - Check queue backlog (author-warming-queue)

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
