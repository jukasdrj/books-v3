---
description: Stream Cloudflare Worker logs in real-time with pretty formatting
---

📜 **Worker Log Streaming** 📜

Stream real-time logs from api-worker with filtering and formatting.

**Tasks:**

1. **Start Log Stream**
   - Navigate to cloudflare-workers/api-worker/
   - Run `npx wrangler tail api-worker --format pretty`
   - Stream logs continuously until interrupted

2. **Log Filtering Options** (ask user which filter to apply)
   - **All logs:** No filter (default)
   - **Search filter:** `--search "gemini"` (search for specific text)
   - **Status filter:** `--status error` (only errors)
   - **Method filter:** `--method POST` (specific HTTP methods)

3. **Key Log Patterns to Monitor**
   - `[GeminiProvider]` - Gemini API calls and responses
   - `[EnrichmentService]` - Book enrichment operations
   - `[ProgressWebSocketDO]` - WebSocket progress updates
   - `[CacheService]` - KV/R2 cache operations
   - `[SearchHandler]` - Book search queries
   - `ERROR:` - Critical errors
   - `DIAGNOSTIC:` - Debug diagnostics

4. **Common Investigations**
   - **Gemini API issues:** `--search "GeminiProvider"`
   - **Enrichment failures:** `--search "EnrichmentService"`
   - **WebSocket errors:** `--search "ProgressWebSocketDO"`
   - **Cache misses:** `--search "cache_miss"`
   - **All errors:** `--status error`

**Worker:** api-worker
**Format:** pretty (colored, human-readable)
**Sampling:** 100% (all requests logged)

**Tip:** Press Ctrl+C to stop streaming. Logs are ephemeral (not persisted).

**Example Filters:**
```bash
npx wrangler tail api-worker --format pretty --search "gemini"
npx wrangler tail api-worker --format pretty --status error
npx wrangler tail api-worker --format pretty --method POST
```
