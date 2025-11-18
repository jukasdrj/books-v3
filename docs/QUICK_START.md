# BooksTrack Backend - Quick Start Guide

## First Time Here?

**Start with these three files:**

1. **[API_CONTRACT.md](API_CONTRACT.md)** - Canonical API contracts and integration patterns (v2.1)
2. **[FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md)** - Integration guide for iOS and Flutter teams
3. **[../README.md](../README.md)** - Repository overview and features

---

## Common Tasks

### 🔍 I need to...

**Find API documentation**
→ [docs/API_CONTRACT.md](API_CONTRACT.md)

**Deploy to production**
→ [docs/deployment/DEPLOYMENT.md](deployment/DEPLOYMENT.md)

**Setup secrets (GitHub Actions)**
→ [docs/deployment/SECRETS_SETUP.md](deployment/SECRETS_SETUP.md)

**Monitor performance metrics**
→ [MONITORING_GUIDE.md](MONITORING_GUIDE.md)

**Understand ISBNdb cover caching**
→ [docs/guides/ISBNDB-HARVEST-IMPLEMENTATION.md](guides/ISBNDB-HARVEST-IMPLEMENTATION.md)

**Verify the API is working**
→ [docs/guides/VERIFICATION.md](guides/VERIFICATION.md)

**Integrate as iOS/Flutter team**
→ [FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md)

**Review architecture decisions**
→ [../MONOLITH_ARCHITECTURE.md](../MONOLITH_ARCHITECTURE.md)

**See implementation details**
→ [plans/](plans/) folder

**Look at historical documentation**
→ [archives/](archives/) folder

---

## Directory Guide

```
docs/
├── API_CONTRACT.md            ⭐ START HERE (API contracts v2.1)
├── FRONTEND_HANDOFF.md        ⭐ START HERE (Frontend integration)
├── deployment/                🚀 Deployment guides
├── guides/                     📖 Feature documentation
├── plans/                      📋 Implementation plans
├── workflows/                  🔄 Process diagrams
├── robit/                      🤖 AI automation setup
└── archives/                   📦 Historical documentation
```

---

## Running Commands

```bash
# Local development
npm run dev                    # Start npx wrangler dev server

# Testing
npm test                       # Run all tests
npm run test:watch             # Watch mode

# Deployment
npm run deploy                 # Deploy to production

# Monitoring
npm run tail                   # Stream production logs
```

---

## Key Endpoints

**Search:**
- `GET /v1/search/title?q={query}`
- `GET /v1/search/isbn?isbn={isbn}`
- `GET /v1/search/advanced?title={title}&author={author}`

**Background Jobs:**
- `POST /v1/enrichment/batch` (with WebSocket progress)
- `POST /api/batch-scan` (AI scanning - returns jobId)

**Real-time Updates:**
- `GET /ws/progress?jobId={jobId}&token={token}` (WebSocket)

**Health:**
- `GET /health` (API status)

See [API_CONTRACT.md](API_CONTRACT.md) for complete reference.

---

## Rate Limiting

**Global Limits (per IP):**
- 1000 requests/hour (hard limit)
- 50 requests/minute (burst protection)

**Endpoint-Specific Limits:**
- Search endpoints: 100 requests/minute
- Batch enrichment: 10 requests/minute
- AI scanning (`/api/batch-scan`): 5 requests/minute

**Response headers:**
- `X-RateLimit-Limit`: Maximum requests allowed in the window
- `X-RateLimit-Remaining`: Requests remaining in the current window
- `X-RateLimit-Reset`: Unix timestamp when the rate limit window resets
- `Retry-After`: Seconds to wait before making another request (sent with 429 status only)

See [API_CONTRACT.md § 3.2](API_CONTRACT.md#32-rate-limiting) for complete rules.

---

## Support & Help

**For API questions:**
→ Email: api-support@oooefam.net
→ Slack: #bookstrack-api
→ GitHub Issues: https://github.com/jukasdrj/bookstrack-backend/issues

**For integration issues (iOS/Flutter):**
→ See [FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md#support--debugging)

**For deployment issues:**
→ See [docs/deployment/DEPLOYMENT.md](deployment/DEPLOYMENT.md)

**For bug reports:**
→ Include endpoint, timestamp, jobId, and error message

**API Status Page:**
→ https://status.oooefam.net

---

## Related Projects

- **iOS App:** https://github.com/jukasdrj/books-tracker-v1
- **Backend:** https://github.com/jukasdrj/bookstrack-backend

---

**Last Updated:** November 17, 2025 (aligned with API v2.1)
**Next:** Read [API_CONTRACT.md](API_CONTRACT.md) for canonical contracts
