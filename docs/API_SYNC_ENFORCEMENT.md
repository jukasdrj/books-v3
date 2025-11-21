# API Documentation Sync Enforcement

**Problem Solved:** Prevents API_CONTRACT.md, openapi.yaml, and TypeScript types from drifting out of sync.

**Incident:** On Nov 20, 2025, openapi.yaml was discovered to be out of sync with the v2.0 breaking change (summary-only WebSocket completions) despite explicit requests to keep documentation in sync.

---

## Automated Enforcement

### 1. Pre-Commit Hook (Local)

**Location:** `.git/hooks/pre-commit`

**Trigger:** Automatically runs when you commit changes to API-related files:
- `docs/API_CONTRACT.md`
- `docs/openapi.yaml`
- `src/types/websocket-messages.ts`
- `src/types/responses.ts`

**What it checks:**
- ✅ Version numbers match between contract and OpenAPI
- ✅ Schema definitions exist in all three sources
- ✅ Pipeline-specific payloads are consistent
- ✅ Field consistency (e.g., `expiresAt`, `summary`, `resourceId`)
- ⚠️  Warns if one file modified without others

**Example output:**
```bash
🔄 Checking API documentation sync...
🔍 Checking API documentation sync...
📋 Checking version consistency...
✓ Versions match: v2.4.1
📋 Checking job_complete schema consistency...
✓ JobCompletePayload exists in OpenAPI
✓ JobCompletePayload exists in TypeScript
📋 Checking summary-only format consistency...
✓ JobCompletionSummary exists in OpenAPI
✓ JobCompletionSummary exists in TypeScript
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All API sync checks passed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**If check fails:**
```bash
❌ ERROR: expiresAt in contract but missing in OpenAPI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Sync check FAILED with 1 error(s) and 0 warning(s)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Fix the errors above before committing.
API_CONTRACT.md, openapi.yaml, and TypeScript types MUST stay in sync.
```

The commit will be **blocked** until you fix the sync issues.

---

### 2. GitHub Actions CI (Remote)

**Location:** `.github/workflows/api-contract-sync-check.yml`

**Trigger:** Runs on every PR and push to main when API files change

**What it checks:**
- Same checks as pre-commit hook
- Plus: Additional cross-file validation
- Plus: Ensures OpenAPI spec is valid YAML

**Prevents:**
- Merging PRs with out-of-sync documentation
- Pushing directly to main with sync issues (if pre-commit hook bypassed)

---

### 3. Manual Checker Script

**Location:** `scripts/check-api-sync.sh`

**Usage:**
```bash
./scripts/check-api-sync.sh
```

**When to use:**
- Before creating a PR (verify sync)
- After making changes to any API file
- During code review (validate contributor's changes)
- When troubleshooting sync issues

---

## Workflow for API Changes

### Scenario 1: Adding a New Field

**Example:** Adding `retryCount` field to `JobProgressPayload`

**Steps:**
1. **TypeScript First** (source of truth):
   ```typescript
   // src/types/websocket-messages.ts
   export interface JobProgressPayload {
     type: "job_progress";
     progress: number;
     status: string;
     retryCount?: number; // ← NEW FIELD
   }
   ```

2. **API Contract** (human-readable):
   ```markdown
   <!-- docs/API_CONTRACT.md -->
   #### job_progress

   payload:
     retryCount (optional): Number of retry attempts (default: 0)
   ```

3. **OpenAPI Spec** (machine-readable):
   ```yaml
   # docs/openapi.yaml
   JobProgressPayload:
     properties:
       retryCount:
         type: integer
         nullable: true
         description: Number of retry attempts
         default: 0
   ```

4. **Commit all three together**:
   ```bash
   git add src/types/websocket-messages.ts docs/API_CONTRACT.md docs/openapi.yaml
   git commit -m "feat: add retryCount to job_progress payload"
   ```

Pre-commit hook will verify they're in sync before allowing the commit.

---

### Scenario 2: Breaking Change

**Example:** Removing a field (like we did with v2.0 summary-only)

**Steps:**
1. **Update all three sources simultaneously**
2. **Add migration guide** (e.g., `WEBSOCKET_MIGRATION_V2.md`)
3. **Update changelog** in API_CONTRACT.md with ⚠️ BREAKING CHANGE notice
4. **Increment version number** in both contract and OpenAPI (v2.4 → v2.5)
5. **Commit together** with descriptive message

**Example commit:**
```bash
git add \
  src/types/websocket-messages.ts \
  docs/API_CONTRACT.md \
  docs/openapi.yaml \
  docs/WEBSOCKET_MIGRATION_V3.md

git commit -m "BREAKING CHANGE: remove deprecated field (v2.5)"
```

---

### Scenario 3: Documentation-Only Update

**Example:** Adding examples to API_CONTRACT.md without changing schema

**Steps:**
1. Make changes to `docs/API_CONTRACT.md` (add examples, clarify wording)
2. Pre-commit hook will **warn** that OpenAPI wasn't updated
3. If intentional, proceed with commit
4. Add comment in commit message: "docs only - no schema changes"

**Example:**
```bash
git commit -m "docs: add usage examples to CSV import endpoint (no schema changes)"
```

---

## What Gets Checked

### Version Consistency
- Contract: `# BooksTrack API Contract v2.4.1`
- OpenAPI: `version: 2.4.1`
- Must match exactly

### Schema Existence
| Contract Mentions | Must Exist In OpenAPI | Must Exist In TypeScript |
|-------------------|----------------------|--------------------------|
| JobCompletePayload | ✅ Yes | ✅ Yes |
| JobCompletionSummary | ✅ Yes | ✅ Yes |
| CSVImportCompletePayload | ✅ Yes | ✅ Yes |
| BatchEnrichmentCompletePayload | ✅ Yes | ✅ Yes |
| AIScanCompletePayload | ✅ Yes | ✅ Yes |

### Field Consistency
| Field | Contract | OpenAPI | TypeScript |
|-------|----------|---------|------------|
| expiresAt | ✅ | ✅ | ✅ |
| summary | ✅ | ✅ | ✅ |
| resourceId | ✅ | ✅ | ✅ |
| pipeline | ✅ | ✅ | ✅ |

---

## Troubleshooting

### "Version mismatch" error

**Problem:**
```
❌ ERROR: Version mismatch!
  API_CONTRACT.md: v2.4.1
  openapi.yaml: v2.4.0
```

**Fix:**
Update the version in both files:
```bash
# API_CONTRACT.md
# BooksTrack API Contract v2.4.1

# openapi.yaml (line ~2)
info:
  version: 2.4.1
```

---

### "JobCompletionSummary missing in OpenAPI" error

**Problem:**
```
❌ ERROR: Contract mentions summary-only but OpenAPI missing JobCompletionSummary
```

**Fix:**
Add the missing schema to `docs/openapi.yaml`:
```yaml
components:
  schemas:
    JobCompletionSummary:
      type: object
      properties:
        totalProcessed:
          type: integer
        # ... other fields
```

---

### "expiresAt in contract but missing in TypeScript" error

**Problem:**
```
❌ ERROR: expiresAt in contract but missing in TypeScript
```

**Fix:**
Add the field to all completion payload interfaces:
```typescript
// src/types/websocket-messages.ts
export interface CSVImportCompletePayload {
  type: "job_complete";
  pipeline: "csv_import";
  summary: JobCompletionSummary;
  expiresAt: string; // ← ADD THIS
}
```

---

### "Warning: API_CONTRACT.md staged but openapi.yaml not staged"

**Problem:**
```
⚠️  WARNING: API_CONTRACT.md staged but openapi.yaml not staged
   Consider if OpenAPI spec needs updating too.
```

**Fix (if intentional):**
If you only updated examples/documentation without changing the schema, proceed:
```bash
git commit -m "docs: add examples (no schema changes)"
```

**Fix (if unintentional):**
Stage the OpenAPI file too:
```bash
git add docs/openapi.yaml
git commit -m "feat: add new field to job_progress"
```

---

## Bypassing Checks (NOT RECOMMENDED)

If you absolutely need to bypass the pre-commit hook (e.g., emergency hotfix):

```bash
git commit --no-verify -m "hotfix: emergency fix"
```

**WARNING:** This bypasses ALL pre-commit checks (security, formatting, sync).

**You MUST:**
1. Fix the sync issues in a follow-up commit immediately
2. Notify the team in Slack #bookstrack-backend
3. Create a GitHub issue to track the technical debt

---

## Maintenance

### Updating the Sync Checker

**When to update:**
- Adding new API files to monitor (e.g., `src/types/http-routes.ts`)
- Adding new schemas that must stay in sync
- Changing version format (e.g., from v2.4 to 2025.01)

**How to update:**
1. Edit `scripts/check-api-sync.sh`
2. Add new patterns to check
3. Test with `./scripts/check-api-sync.sh`
4. Commit changes
5. GitHub Actions will automatically use the updated script

---

## History

**v1.0.0 (Nov 20, 2025):**
- Initial implementation
- Triggered by openapi.yaml drift incident
- Prevents recurrence of v2.0 breaking change documentation gap

**Maintainer:** Backend Team
**Last Updated:** November 20, 2025
