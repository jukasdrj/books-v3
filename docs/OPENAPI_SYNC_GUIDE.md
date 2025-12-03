# OpenAPI Sync Guide

**Status:** ✅ Automated (Balanced Approach)
**Last Updated:** December 3, 2025
**Owner:** books-v3 iOS Team

---

## Overview

books-v3 uses **live OpenAPI spec syncing** from the backend API at https://api.oooefam.net/v3/openapi.json to generate type-safe Swift client code via Apple's `swift-openapi-generator`.

**Key Features:**
- 🔄 Automatic spec fetching from live backend
- 🔧 Swift OpenAPI Generator compatibility patches (3.1.0 → 3.0.3)
- ⚠️ Pre-commit hook warns when spec is >7 days old
- 📦 Generates 2,322 lines of type-safe Swift code (3 endpoints)

---

## Architecture

```
Backend (Hono/Cloudflare)
  ↓ (auto-generates at runtime)
https://api.oooefam.net/v3/openapi.json (OpenAPI 3.1.0)
  ↓ (fetch + patch)
.claude/scripts/sync-openapi.sh
  ↓ (compatibility patches)
BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json (OpenAPI 3.0.3)
  ↓ (Swift Package Manager build plugin)
swift-openapi-generator
  ↓ (generates)
Types.swift (106KB) + Client.swift (19KB)
```

---

## Quick Start

### Sync OpenAPI Spec (Manual)

```bash
# From project root
./.claude/scripts/sync-openapi.sh
```

**Output:**
```
📥 Fetching OpenAPI spec from https://api.oooefam.net/v3/openapi.json...
🔧 Applying Swift OpenAPI Generator compatibility patches...
✅ OpenAPI spec updated successfully
📋 Spec version: 3.0.0
📊 Endpoints: 3
🔧 Patched: OpenAPI 3.1.0 → 3.0.3 for Swift compatibility
```

### Rebuild Swift Client

```bash
# Quick validation (recommended)
/quick-validate

# Or full rebuild
cd BooksTrackerPackage && swift build
```

---

## Automation (Balanced Approach)

**Pre-commit Hook:** `.claude/hooks/pre-commit.sh`

- ✅ **Checks spec freshness** on every commit
- ⚠️ **Warns if >7 days old** (suggests manual sync)
- ❌ **Does NOT auto-sync** (prevents unexpected API changes)

**Example Output:**
```bash
📋 Checking OpenAPI spec freshness...
⚠ OpenAPI spec is 9 days old
  Consider syncing: ./.claude/scripts/sync-openapi.sh
```

---

## Compatibility Patches

The sync script applies these patches for Swift OpenAPI Generator:

### 1. OpenAPI Version Downgrade

```json
// Backend: OpenAPI 3.1.0
{"openapi": "3.1.0"}

// After patch: OpenAPI 3.0.3 (Swift-compatible)
{"openapi": "3.0.3"}
```

### 2. exclusiveMinimum Conversion

**Problem:** Swift OpenAPI Generator doesn't support OpenAPI 3.1.0's boolean `exclusiveMinimum`.

**Backend (3.1.0):**
```json
{
  "type": "integer",
  "minimum": 0,
  "exclusiveMinimum": true  // Boolean format
}
```

**After Patch (3.0.3):**
```json
{
  "type": "integer",
  "minimum": 1  // Converts to minimum = minimum + 1
}
```

**Rationale:** `minimum: 0, exclusiveMinimum: true` means "greater than 0", which is equivalent to `minimum: 1` for integers.

---

## Generated Code

**Location:** `BooksTrackerPackage/.build/plugins/outputs/bookstrackerpackage/BooksTrackerFeature/destination/OpenAPIGenerator/GeneratedSources/`

**Files:**
- `Types.swift` - 106KB (models, enums, schemas)
- `Client.swift` - 19KB (API client methods)
- `Server.swift` - Empty (not used)

**Total:** 2,322 lines of type-safe Swift code

**Endpoints:**
1. `GET /v3/books/search` - Search books by title
2. `POST /v3/books/enrich` - Enrich book metadata
3. `GET /v3/books/:isbn` - Get book by ISBN

---

## Comparison: V2 vs V3 Workflows

| Aspect | V2 API (Manual) | V3 API (Automated) |
|--------|----------------|-------------------|
| **Spec Location** | `docs/openapi.yaml` (manual) | Live endpoint (auto-generated) |
| **Update Process** | Edit YAML manually | Deploy backend code |
| **Client Generation** | Manual `npm run generate` | Swift Package Manager plugin |
| **Publishing** | Manual (npm publish) | Automatic (fetch + rebuild) |
| **Frontend Sync** | Manual copy | Script + build hook |
| **Freshness Check** | None | Pre-commit hook |

---

## Troubleshooting

### Build Fails: "Expected `exclusiveMinimum` value... to be parsable as Bool"

**Cause:** Backend changed OpenAPI spec without compatibility patch.

**Fix:**
```bash
# Re-sync with patches
./.claude/scripts/sync-openapi.sh

# Rebuild
/quick-validate
```

### Spec is Stale (>7 days old)

**Cause:** Backend API changed, local spec not updated.

**Fix:**
```bash
# Sync latest spec
./.claude/scripts/sync-openapi.sh

# Check for breaking changes
git diff BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json

# Rebuild and test
/quick-validate
```

### Generated Code Out of Sync

**Cause:** Swift Package Manager cache stale.

**Fix:**
```bash
cd BooksTrackerPackage
swift package clean
swift build
```

---

## When to Sync

### ✅ Always Sync When:
- Starting work on V3 API integration
- Backend team deploys API changes
- Pre-commit hook warns spec is stale
- Build fails with OpenAPI errors

### ❌ Don't Need to Sync When:
- Working on UI-only changes
- Backend API stable (no changes)
- Spec synced within last 7 days

---

## Related Documentation

- **Backend API Contract:** `docs/API_CONTRACT.md`
- **V3 Migration Plan:** `V3_MIGRATION_PLAN.md`
- **Safe Testing Guide:** `.claude/SAFE_TESTING.md`
- **AGENTS.md:** Universal AI agent guide

**Live API Documentation:**
- OpenAPI Spec: https://api.oooefam.net/v3/openapi.json
- Swagger UI: https://api.oooefam.net/v3/docs

---

## Future Enhancements

### Option 1: Pre-Build Auto-Sync (Aggressive)

Add to `.claude/hooks/pre-build.sh`:
```bash
./.claude/scripts/sync-openapi.sh || echo "⚠️ OpenAPI sync failed, using cached spec"
```

**Pros:** Always latest spec
**Cons:** Unexpected breaking changes during builds

### Option 2: CI/CD Integration

GitHub Actions workflow:
```yaml
- name: Sync OpenAPI Spec
  run: ./.claude/scripts/sync-openapi.sh
- name: Check for changes
  run: git diff --exit-code BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json
```

**Pros:** Catches API drift early
**Cons:** Requires CI/CD setup

---

## Maintenance

**Script Location:** `.claude/scripts/sync-openapi.sh`
**Hook Location:** `.claude/hooks/pre-commit.sh` (lines 84-100)
**Spec Files:**
- Build source: `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json`
- Documentation copy: `docs/openapi-v3.json`

**Last Tested:** December 3, 2025 (Build ✅ SUCCESS, 0 warnings)

---

**Questions?** See `CLAUDE.md` or `AGENTS.md` for AI agent workflows.
