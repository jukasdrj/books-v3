# Test Fix Plan - TypeScript Import Resolution

**Created:** 2025-10-30
**Status:** 🚨 Blocker for test suite
**Priority:** Medium (production unaffected)

## Problem Statement

After migrating `ai-scanner.js` to use v1 canonical handlers, test suite is failing due to TypeScript import resolution issues.

**Failing Tests:**
- `tests/ai-scanner-metadata.test.js` - Can't load TypeScript module
- `tests/batch-scan.test.js` - Multiple fetch failures
- `test/csv-import-e2e.test.js` - Missing test data files

**Root Cause:**

```javascript
// ai-scanner.js (JavaScript file)
import { handleSearchAdvanced } from '../handlers/v1/search-advanced.js';
//                                                                    ^^^ .js extension
```

The file `search-advanced.ts` exists, but:
1. Vitest can't resolve `.js` imports to `.ts` files automatically
2. Wrangler dev/production handle this fine (built-in TypeScript support)
3. Tests run in Node.js environment without TypeScript resolution

## Production Status

✅ **Production working correctly**
- Wrangler transpiles TypeScript → JavaScript during deployment
- All endpoints returning canonical format as expected
- Deployed version: `fd0716c4-f57e-4fa5-a5eb-858d8db38417`

## Solution Options

### Option 1: Configure Vitest for TypeScript (Recommended)

**Approach:** Add TypeScript resolution to Vitest config

**Implementation:**

1. Create `vitest.config.js`:
```javascript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
  },
  resolve: {
    extensions: ['.js', '.ts', '.jsx', '.tsx', '.json']
  },
  esbuild: {
    // Let vitest transpile TypeScript during tests
    target: 'node18'
  }
});
```

2. Update `package.json`:
```json
{
  "devDependencies": {
    "typescript": "^5.9.3",
    "vitest": "^1.6.1",
    "@types/node": "^20.0.0"
  }
}
```

3. Run tests:
```bash
npm install
npm test
```

**Pros:**
- Handles TypeScript imports automatically
- Future-proof (all v1 handlers are TypeScript)
- Standard Vitest setup

**Cons:**
- Requires vitest config file
- Adds esbuild transpilation overhead

**Effort:** 15-30 minutes

---

### Option 2: Change Import Extensions to .ts

**Approach:** Import `.ts` files directly in JavaScript

**Implementation:**

1. Update `ai-scanner.js`:
```javascript
// BEFORE
import { handleSearchAdvanced } from '../handlers/v1/search-advanced.js';

// AFTER
import { handleSearchAdvanced } from '../handlers/v1/search-advanced.ts';
```

2. Update `index.js`:
```javascript
import { handleSearchTitle } from './handlers/v1/search-title.ts';
import { handleSearchISBN } from './handlers/v1/search-isbn.ts';
import { handleSearchAdvanced } from './handlers/v1/search-advanced.ts';
```

**Pros:**
- Minimal code changes
- Explicit about TypeScript imports

**Cons:**
- ❌ May break Wrangler build (expects `.js` in ESM imports)
- Non-standard (mixing `.ts` in JavaScript imports)
- Requires testing with `wrangler deploy`

**Effort:** 5 minutes + deployment verification

**Risk:** HIGH - may break production

---

### Option 3: Convert ai-scanner.js to TypeScript

**Approach:** Rename `ai-scanner.js` → `ai-scanner.ts`

**Implementation:**

1. Rename file:
```bash
git mv src/services/ai-scanner.js src/services/ai-scanner.ts
```

2. Update imports in `index.js`:
```javascript
import { processScan } from './services/ai-scanner.js';  // Keep .js extension!
```

3. Add type annotations (optional):
```typescript
export async function processScan(
  jobId: string,
  imageDataUrl: string,
  env: any,
  doStub: any
): Promise<void> {
  // ...
}
```

**Pros:**
- Consistent language (all service files TypeScript)
- Type safety benefits
- Vitest will resolve correctly

**Cons:**
- Larger scope (need to type check entire file)
- May require adding types for existing code
- Needs careful testing

**Effort:** 1-2 hours (type annotations + testing)

---

### Option 4: Use Legacy Handler (Temporary Workaround)

**Approach:** Revert `ai-scanner.js` to use legacy `handleAdvancedSearch`

**Implementation:**

1. Revert import:
```javascript
// BEFORE (current)
import { handleSearchAdvanced } from '../handlers/v1/search-advanced.js';

// AFTER (legacy)
import { handleAdvancedSearch } from '../handlers/search-handlers.js';
```

2. Revert enrichment parsing to legacy format

3. Add TODO comment:
```javascript
// TODO: Migrate to v1 canonical handler after test environment setup
```

**Pros:**
- Immediate fix (tests pass again)
- Buys time for proper TypeScript setup

**Cons:**
- ❌ Backend sends canonical format but AI scanner uses legacy handler (mismatch!)
- Temporary solution, needs revisit
- Delays full migration

**Effort:** 10 minutes

**Risk:** MEDIUM - creates format inconsistency

---

## Recommendation

**Primary:** Option 1 (Vitest TypeScript Config)
**Reason:** Proper solution, future-proof, standard setup

**Fallback:** Option 3 (Convert to TypeScript)
**Reason:** If vitest config doesn't work, full TypeScript migration is cleaner than workarounds

**Avoid:** Option 4 (revert) - creates format inconsistency in backend

## Next Steps

1. Implement Option 1 (vitest config)
2. Run full test suite: `npm test`
3. Verify all tests pass
4. If tests still fail, investigate specific failures
5. Commit test config: `git commit -m "test: add TypeScript resolution to vitest config"`

## Test Verification Checklist

After fix:
- [ ] `npm test` exits with code 0
- [ ] `tests/ai-scanner-metadata.test.js` passes
- [ ] `tests/batch-scan.test.js` passes
- [ ] No "Failed to load url" errors
- [ ] Production deployment still works: `npx wrangler deploy`

## Additional Issues Found

**Missing test data files:**
- `test/csv-import-e2e.test.js` expects `/Users/justingardner/Downloads/xcode/books-tracker-v1/docs/testImages/sample-books.csv`
- File doesn't exist in repository

**Action:** Create sample CSV file or update test paths

---

**Status:** Ready to implement Option 1
**Owner:** Backend team
**Timeline:** Next development session
