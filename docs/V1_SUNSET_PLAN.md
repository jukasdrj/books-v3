# V1 API Sunset Plan

**Status:** Draft
**Sunset Date:** March 1, 2026
**Created:** December 4, 2025

## Overview

V1 API deprecation headers are currently active (since Nov 2025). This document outlines the complete removal plan for March 1, 2026.

---

## V1 Endpoints Inventory

### Search Endpoints (OpenAPI Routes)
| Endpoint | Handler | Migration Path |
|----------|---------|---------------|
| `GET /v1/search/isbn` | `src/openapi/routes/search.ts:46` → `handleSearchISBN` | ✅ V3 has `/v3/books/:isbn` |
| `GET /v1/search/title` | `src/openapi/routes/search.ts:265` → `handleSearchTitle` | ✅ V3 has `/v3/books/search?q=title` |

### Search Endpoints (Legacy Routes)
| Endpoint | Handler | Migration Path |
|----------|---------|---------------|
| `GET /v1/search/advanced` | `src/handlers/v1/search-advanced.ts` | ⚠️ No V3 equivalent (combine title+author in V3 search) |
| `GET /v1/search/similar` | `handleSimilarBooks` in `semantic-search-handler.ts` | ✅ V3 has `/v3/books/search?mode=similar` |
| `GET /v1/search/semantic` | `handleSemanticSearch` in `semantic-search-handler.ts` | ✅ V3 has `/v3/books/search?mode=semantic` |

### Job/Workflow Endpoints
| Endpoint | Handler | Migration Path |
|----------|---------|---------------|
| `POST /v1/enrichment/batch` | `handleBatchEnrichment` | ✅ V3 has `/v3/books/enrich` (batch via array) |
| `DELETE /v1/jobs/:jobId` | Inline in `router.ts:861` | ⚠️ Keep or migrate to V3? |
| `GET /v1/jobs/:jobId/results` | Inline in `router.ts:996` | ⚠️ Keep or migrate to V3? |
| `GET /v1/editions/search` | `src/handlers/v1/search-editions.ts` | ⚠️ No V3 equivalent yet |

### Results Retrieval Endpoints
| Endpoint | Handler | Migration Path |
|----------|---------|---------------|
| `GET /v1/scan/results/:jobId` | `src/handlers/v1/scan-results.ts` | ⚠️ Keep or migrate to V2/V3? |
| `GET /v1/csv/status/:jobId` | Inline in `router.ts:714` | ⚠️ V2 has `/api/v2/imports/:id/status` |
| `GET /v1/csv/results/:jobId` | `src/handlers/v1/csv-results.ts` | ⚠️ V2 has `/api/v2/imports/:id/results` |

---

## V1 Handler Files

```
src/handlers/v1/
├── csv-results.ts         # GET /v1/csv/results/:jobId
├── scan-results.ts        # GET /v1/scan/results/:jobId
├── search-advanced.ts     # GET /v1/search/advanced
├── search-editions.ts     # GET /v1/editions/search
├── search-isbn.ts         # GET /v1/search/isbn (via OpenAPI)
└── search-title.ts        # GET /v1/search/title (via OpenAPI)
```

---

## Migration Status

### ✅ Ready to Remove (V3 equivalents exist)
- `GET /v1/search/isbn` → Use `GET /v3/books/:isbn`
- `GET /v1/search/title` → Use `GET /v3/books/search?q=title`
- `GET /v1/search/similar` → Use `GET /v3/books/search?mode=similar`
- `GET /v1/search/semantic` → Use `GET /v3/books/search?mode=semantic`
- `POST /v1/enrichment/batch` → Use `POST /v3/books/enrich` (with array)

### ⚠️ Needs Decision
1. **Advanced Search** (`/v1/search/advanced`)
   - **Options:**
     - A) Remove (clients use V3 search with combined query)
     - B) Add to V3 as `/v3/books/search?title=X&author=Y`

2. **Job Management** (`/v1/jobs/*`)
   - **Options:**
     - A) Keep in V2 (`/api/v2/jobs/*`)
     - B) Migrate to V3 (`/v3/jobs/*`)
     - C) Remove (if not used by iOS app)

3. **CSV/Scan Results** (`/v1/csv/*`, `/v1/scan/*`)
   - **Options:**
     - A) Migrate to V2 (`/api/v2/imports/*`, `/api/v2/scans/*`)
     - B) Already in V2, just remove V1 aliases

4. **Editions Search** (`/v1/editions/search`)
   - **Options:**
     - A) Remove (low usage?)
     - B) Add to V3 (`/v3/books/:isbn/editions`)

---

## Client Impact Analysis

### iOS App (BooksTrack)
**Action Required:** Check which V1 endpoints are actively used

```bash
# Search iOS app codebase for V1 API calls
cd /path/to/ios-app
grep -r "/v1/" --include="*.swift"
```

**Known Usage:**
- ✅ `/v1/enrichment/batch` - Has fallback to `/api/batch-enrich`
- ⚠️ `/v1/search/isbn` - May need migration to V3
- ⚠️ `/v1/csv/results/:jobId` - May need migration to V2

### Web App (if exists)
**Action Required:** Audit for V1 API usage

### Third-Party Clients
**Action Required:** Check analytics for V1 traffic from unknown user agents

---

## Removal Plan

### Phase 1: Pre-Sunset Preparation (Now - Feb 1, 2026)

1. **Analytics Audit** (Week 1)
   - [ ] Query Cloudflare Analytics for V1 endpoint usage (last 90 days)
   - [ ] Identify top 5 most-used V1 endpoints
   - [ ] Check for external/third-party clients (non-iOS user agents)
   - [ ] Document findings in `V1_USAGE_REPORT.md`

2. **iOS App Migration** (Week 2-3)
   - [ ] Update iOS app to use V3 for search endpoints
   - [ ] Update iOS app to use V2 for CSV/batch workflows
   - [ ] Test all workflows in iOS app
   - [ ] Deploy iOS app update to TestFlight
   - [ ] Deploy iOS app update to App Store

3. **Communication** (Week 4)
   - [ ] Email known API users (if any)
   - [ ] Update API documentation with migration guide
   - [ ] Add banner to `/v1` endpoints: "30 days until sunset"

### Phase 2: Sunset Day (March 1, 2026)

1. **Remove V1 Routes**
   - [ ] Delete all `app.get("/v1/*)` routes from `src/router.ts`
   - [ ] Delete all `app.post("/v1/*)` routes from `src/router.ts`
   - [ ] Remove V1 deprecation middleware (no longer needed)
   - [ ] Remove V1 contract validation middleware

2. **Remove V1 Handlers**
   - [ ] Delete `src/handlers/v1/` directory
   - [ ] Remove imports in `src/router.ts` (lines 22-26)

3. **Remove V1 OpenAPI Routes**
   - [ ] Delete `searchISBNRoute` and `searchTitleRoute` from `src/openapi/routes/search.ts`
   - [ ] OR update them to use `/v3` paths instead

4. **Update Tests**
   - [ ] Remove V1 endpoint tests from `tests/` directory
   - [ ] Update integration tests to use V3 endpoints

5. **Update Documentation**
   - [ ] Remove V1 references from `CLAUDE.md`
   - [ ] Remove V1 references from `README.md`
   - [ ] Update `docs/openapi.yaml` to remove V1 endpoints (if any)
   - [ ] Archive V1 docs to `docs/archive/v1-api-2024-2026/`

### Phase 3: Post-Sunset Cleanup (March 2026)

1. **Monitoring**
   - [ ] Monitor 404 errors for `/v1/*` patterns (first 7 days)
   - [ ] Track rollback requests (should be zero)
   - [ ] Confirm zero V1 traffic in analytics

2. **Performance Check**
   - [ ] Verify bundle size reduction (fewer routes = smaller worker)
   - [ ] Check cold start time improvement

3. **Documentation**
   - [ ] Create `V1_SUNSET_POSTMORTEM.md` with lessons learned
   - [ ] Update CHANGELOG.md with V1 removal notes

---

## Rollback Plan

If critical issues arise (e.g., iOS app breaks):

1. **Immediate Rollback** (< 5 minutes)
   ```bash
   wrangler rollback --message "Emergency rollback - V1 still needed"
   ```

2. **Temporary V1 Restore** (< 30 minutes)
   - Revert commit that removed V1 endpoints
   - Deploy to production
   - Extend sunset date by 30 days

3. **Root Cause Analysis**
   - Identify which endpoint is needed
   - Create migration path for that specific endpoint
   - Reschedule sunset

---

## Decision Checklist

Before removal on March 1, 2026, confirm:

- [ ] iOS app updated to V3/V2 (version deployed to App Store)
- [ ] Web app updated to V3/V2 (if applicable)
- [ ] No external clients using V1 (verified via analytics)
- [ ] All V1 endpoints have V3/V2 equivalents OR are confirmed unused
- [ ] Migration guide published at `docs/V1_TO_V3_MIGRATION.md`
- [ ] Team approval for removal (stakeholder sign-off)

---

## Questions to Answer

1. **Are job management endpoints (`/v1/jobs/*`) used by iOS app?**
   - If yes, migrate to V2 or V3
   - If no, remove entirely

2. **Is `/v1/search/advanced` still needed?**
   - Check iOS app usage
   - Consider adding to V3 if actively used

3. **Do CSV/scan results need V1 aliases?**
   - Likely not, since V2 has equivalents
   - Verify iOS app uses V2 paths

4. **Is `/v1/editions/search` used?**
   - Check analytics
   - Remove if zero usage

---

## Timeline Summary

| Date | Milestone |
|------|-----------|
| Dec 4, 2025 | V1 sunset plan created |
| Jan 2026 | Analytics audit + iOS app migration |
| Feb 2026 | Final warning communications |
| **Mar 1, 2026** | **V1 API sunset - routes removed** |
| Mar 2026 | Post-sunset monitoring and cleanup |

---

**Next Steps:**
1. Run analytics audit to see V1 usage
2. Check iOS app for V1 dependencies
3. Answer the 4 questions above
4. Get stakeholder approval for removal
