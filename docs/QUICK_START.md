# BooksTrack Backend - Quick Start Guide

## First Time Here?

**Start with these three files:**

1. **[API_README.md](API_README.md)** - Canonical API contracts and integration patterns
2. **[FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md)** - Integration guide for iOS and Flutter teams
3. **[../README.md](../README.md)** - Repository overview and features

---

## Common Tasks

### 🔍 I need to...

**Find API documentation**
→ [docs/API_README.md](API_README.md)

**Deploy to production**
→ [docs/deployment/DEPLOYMENT.md](deployment/DEPLOYMENT.md)

**Setup secrets (GitHub Actions)**
→ [docs/deployment/SECRETS_SETUP.md](deployment/SECRETS_SETUP.md)

**Monitor performance metrics**
→ [docs/guides/METRICS.md](guides/METRICS.md)

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
├── API_README.md              ⭐ START HERE (API contracts)
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
npm run dev                    # Start wrangler dev server

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
- `POST /api/scan-bookshelf?jobId={uuid}` (AI scanning)

**Real-time Updates:**
- `GET /ws/progress?jobId={uuid}` (WebSocket)

**Health:**
- `GET /health` (API status)

See [API_README.md](API_README.md) for complete reference.

---

## Rate Limiting

**Limit:** 10 requests per 60 seconds per IP

**Protected endpoints:**
- `/api/token/refresh`
- `/api/scan-bookshelf`
- `/api/import/csv-gemini`
- `/v1/enrichment/batch`

**Response header:** `Retry-After: {seconds}`

---

## Support & Help

**For API questions:**
→ Open GitHub issue in `bookstrack-backend` repo

**For integration issues (iOS/Flutter):**
→ See [FRONTEND_HANDOFF.md](FRONTEND_HANDOFF.md#support--debugging)

**For deployment issues:**
→ See [docs/deployment/DEPLOYMENT.md](deployment/DEPLOYMENT.md)

**For bug reports:**
→ Include endpoint, timestamp, jobId, and error message

---

## Related Projects

- **iOS App:** https://github.com/jukasdrj/books-tracker-v1
- **Backend:** https://github.com/jukasdrj/bookstrack-backend

---

**Last Updated:** November 13, 2025
**Next:** Read [API_README.md](API_README.md) for canonical contracts
