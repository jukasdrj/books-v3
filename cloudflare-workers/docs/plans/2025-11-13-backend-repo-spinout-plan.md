# Cloudflare Workers Backend Spin-Out Plan

**Created:** November 13, 2025
**Status:** Planning Phase
**Goal:** Extract `api-worker` from iOS monorepo into standalone `bookstrack-backend` repository

---

## Executive Summary

**Goal:** Extract `api-worker` from the iOS monorepo (`books-tracker-v1`) into a standalone backend repository (`bookstrack-backend`) with full CI/CD automation.

**Current State:**
- Workers code: `books-tracker-v1/cloudflare-workers/api-worker/`
- ~12,500 lines of TypeScript/JavaScript
- Production URLs: `api.oooefam.net`, `harvest.oooefam.net`
- iOS app references backend via hardcoded URLs in `EnrichmentConfig.swift`
- Manual deployment via `wrangler deploy`

**Target State:**
- Standalone `bookstrack-backend` repository
- Automated CI/CD deployment on push to main
- Clean separation of concerns (iOS ↔ Backend)
- Preserved git history for backend files

---

## 1. New Repository Structure Design

```
bookstrack-backend/
├── .github/
│   └── workflows/
│       ├── deploy-production.yml      # Auto-deploy to api.oooefam.net
│       ├── deploy-staging.yml         # Auto-deploy to staging environment
│       └── cache-warming.yml          # Migrated from iOS repo
├── src/                               # Migrated from api-worker/src/
│   ├── index.js
│   ├── durable-objects/
│   ├── handlers/
│   ├── services/
│   ├── providers/
│   ├── middleware/
│   ├── utils/
│   ├── types/
│   └── tasks/
├── tests/                             # Migrated from api-worker/tests/
├── scripts/                           # Migrated from api-worker/scripts/
├── docs/                              # Backend-specific docs
│   ├── architecture/
│   ├── deployment/
│   └── api/
├── wrangler.toml                      # Migrated config
├── package.json                       # Migrated dependencies
├── .gitignore                         # Backend-specific ignores
├── README.md                          # Backend README
├── DEPLOYMENT.md                      # Deployment guide
├── CONTRIBUTING.md                    # Contribution guidelines
├── LICENSE                            # MIT License
└── .env.example                       # Example environment variables
```

---

## 2. Migration Strategy (Preserve Git History)

### Phase 1: Repository Initialization (30 min)

**Option A: Subdirectory Filter (Recommended)**
```bash
# Create new repo with filtered history
cd /tmp
git clone https://github.com/jukasdrj/books-tracker-v1.git bookstrack-backend
cd bookstrack-backend

# Filter to only cloudflare-workers/api-worker/ history
git filter-repo --path cloudflare-workers/api-worker/ --path-rename cloudflare-workers/api-worker/:

# Verify history
git log --oneline src/index.js  # Should show full commit history
```

**Tool Required:** `git-filter-repo` (faster than filter-branch)
```bash
pip install git-filter-repo
```

---

## 3. Subagent Task Breakdown

### Agent 1: Repository Setup Specialist
**Tasks:**
1. Use `git filter-repo` to extract backend with history
2. Create `bookstrack-backend` GitHub repository
3. Push filtered repo to new remote
4. Set repository settings

**Estimated Time:** 1 hour

---

### Agent 2: CI/CD Automation Engineer
**Tasks:**
1. Create GitHub Actions workflows (production, staging, cache-warming)
2. Configure repository secrets (5 secrets)
3. Test deployment via `workflow_dispatch`

**Estimated Time:** 2 hours

---

### Agent 3: Documentation Architect
**Tasks:**
1. Create backend README.md
2. Migrate backend docs from iOS repo
3. Update iOS repo cross-references
4. Add type contract versioning guide

**Estimated Time:** 2 hours

---

### Agent 4: Code Migration Specialist
**Tasks:**
1. Copy source files to new repo
2. Update import paths
3. Update package.json metadata
4. Create .env.example
5. Run tests

**Estimated Time:** 2 hours

---

### Agent 5: iOS Integration Coordinator
**Tasks:**
1. Update `EnrichmentConfig.swift` to use `api.oooefam.net`
2. Search for hardcoded URLs
3. Update Swift DTO comments
4. Test iOS app with deployed backend

**Estimated Time:** 1 hour

---

### Agent 6: QA & Validation Engineer
**Tasks:**
1. Test production deployment
2. Verify all API endpoints
3. Test iOS app integration
4. Monitor logs for errors

**Estimated Time:** 2 hours

---

## 4. Required GitHub Secrets

**Cloudflare Credentials:**
- `CLOUDFLARE_API_TOKEN` (Wrangler deployment token)
- `CLOUDFLARE_ACCOUNT_ID`

**External API Keys:**
- `GOOGLE_BOOKS_API_KEY`
- `GEMINI_API_KEY`
- `ISBNDB_API_KEY`

---

## 5. DNS & Domain Management

**No changes required!** Custom domains configured in `wrangler.toml`:
- `api.oooefam.net` → Already pointing to worker
- `harvest.oooefam.net` → Already pointing to worker

---

## 6. iOS App Updates

**File: `EnrichmentConfig.swift`**
```swift
// Change from:
static let baseURL = "https://api-worker.jukasdrj.workers.dev"

// To:
static let baseURL = "https://api.oooefam.net"
```

---

## 7. Rollback Strategy

### If Deployment Fails
```bash
# Emergency manual deployment
cd bookstrack-backend
npx wrangler deploy
```

### If Migration Goes Wrong
```bash
# Keep backend code in iOS repo for 2 weeks
# Don't delete cloudflare-workers/ until stable
```

---

## 8. Success Criteria

- [ ] Backend repo deployed to `api.oooefam.net`
- [ ] All API endpoints return 200 status
- [ ] iOS app can search, enrich, and scan books
- [ ] CI/CD triggers on push to main
- [ ] Tests pass in CI
- [ ] Zero downtime during migration

---

## 9. Timeline

**Week 1: Preparation & Setup**
- Day 1-2: Repository setup
- Day 3-4: Code migration
- Day 5: Documentation

**Week 2: Testing & Deployment**
- Day 6-7: Integration testing
- Day 8: Production deployment
- Day 9-10: Stabilization

---

## 10. Estimated Effort

**Total Time:** 25-30 hours over 2 weeks

**Breakdown:**
- Repository setup: 3 hours
- CI/CD configuration: 3 hours
- Code migration: 4 hours
- Documentation: 4 hours
- Testing: 6 hours
- iOS integration: 2 hours
- Monitoring & stabilization: 4 hours
- Contingency: 4 hours

---

## Next Steps

1. **Create `bookstrack-backend` GitHub repository**
2. **Extract history with `git-filter-repo`**
3. **Set up CI/CD workflows**
4. **Configure secrets**
5. **Deploy to staging**
6. **Update iOS app**
7. **Deploy to production**
8. **Monitor for 48 hours**

---

**See full plan:** This document contains abbreviated version. Full plan includes:
- Detailed GitHub Actions workflows (YAML)
- Complete documentation examples
- Risk mitigation strategies
- Post-migration cleanup steps
- Key files migration list
