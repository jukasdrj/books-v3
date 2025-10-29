---
description: Deploy Cloudflare Workers backend (api-worker monolith)
---

☁️ **Cloudflare Backend Deployment** ☁️

Deploy the api-worker monolith to Cloudflare Workers with validation and health checks.

**Tasks:**

1. **Pre-Deployment Checks**
   - Verify wrangler.toml configuration
   - Check secrets store bindings (GEMINI_API_KEY, GOOGLE_BOOKS_API_KEY, ISBNDB_API_KEY)
   - Validate KV namespaces, R2 buckets, and Durable Object bindings
   - Review analytics engine datasets

2. **Deploy Worker**
   - Navigate to cloudflare-workers/api-worker/
   - Run `npx wrangler deploy`
   - Report deployment status and version ID
   - Show all bindings (KV, R2, Secrets Store, Analytics Engine)

3. **Post-Deployment Validation**
   - Test health endpoint: `GET https://api-worker.jukasdrj.workers.dev/health`
   - Verify WebSocket endpoint: `GET https://api-worker.jukasdrj.workers.dev/ws/progress`
   - Check cron triggers (daily archival, alert monitoring)
   - Verify queue consumers (author-warming-queue)

4. **Resource Summary**
   - List all bindings (11 total expected)
   - Show environment variables
   - Display cron schedules
   - Report worker URL and version

**Worker Name:** api-worker
**Production URL:** https://api-worker.jukasdrj.workers.dev
**Architecture:** Monolith (all services in one worker)

**Critical Bindings:**
- ProgressWebSocketDO (Durable Object for WebSocket progress)
- GEMINI_API_KEY (Secrets Store: google_gemini_oooebooks)
- CACHE / KV_CACHE (KV namespace)
- BOOKSHELF_IMAGES (R2 bucket)
- AUTHOR_WARMING_QUEUE (Queue for cache warming)

If deployment fails, show error details and suggest fixes.
