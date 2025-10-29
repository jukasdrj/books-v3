# R2 Cold Storage Implementation Plan - Phase 3

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build R2-based cold storage tier for rarely-accessed cache entries with background rehydration.

**Architecture:** Scheduled Archival (Hybrid: Age + Access Frequency) → R2 Storage → Background Rehydration on Access

**Tech Stack:** Cloudflare Workers, R2, KV, Analytics Engine, Cron Triggers

**Prerequisites:**
- Phase 1 complete (UnifiedCacheService, KVCacheService, EdgeCacheService)
- R2 bucket `LIBRARY_DATA` configured in `wrangler.toml`
- Analytics Engine `CACHE_ANALYTICS` logging cache hits

---

## Task 1: Analytics Engine Access Frequency Query

**Files:**
- Create: `cloudflare-workers/api-worker/src/utils/analytics-queries.js`
- Test: `cloudflare-workers/api-worker/tests/analytics-queries.test.js`

**Step 1: Write the failing test**

Create `tests/analytics-queries.test.js`:

```javascript
import { describe, it, expect, vi } from 'vitest';
import { queryAccessFrequency } from '../src/utils/analytics-queries.js';

describe('queryAccessFrequency', () => {
  it('should return access counts per cache key', async () => {
    const mockEnv = {
      CACHE_ANALYTICS: {
        query: vi.fn().mockResolvedValue({
          results: [
            { cacheKey: 'search:title:q=hamlet', accessCount: 150 },
            { cacheKey: 'search:isbn:isbn=123', accessCount: 5 }
          ]
        })
      }
    };

    const stats = await queryAccessFrequency(mockEnv, 30);

    expect(stats['search:title:q=hamlet']).toBe(150);
    expect(stats['search:isbn:isbn=123']).toBe(5);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test analytics-queries.test.js`

Expected: `FAIL - Cannot find module 'analytics-queries.js'`

**Step 3: Write minimal implementation**

Create `src/utils/analytics-queries.js`:

```javascript
/**
 * Query cache access frequency from Analytics Engine
 *
 * @param {Object} env - Worker environment with CACHE_ANALYTICS binding
 * @param {number} days - Number of days to look back
 * @returns {Promise<Object>} Map of cacheKey → accessCount
 */
export async function queryAccessFrequency(env, days) {
  if (!env.CACHE_ANALYTICS) {
    console.warn('CACHE_ANALYTICS binding not available');
    return {};
  }

  try {
    const query = `
      SELECT
        blob2 as cacheKey,
        COUNT(*) as accessCount
      FROM CACHE_ANALYTICS
      WHERE timestamp > NOW() - INTERVAL '${days}' DAY
      GROUP BY blob2
    `;

    const result = await env.CACHE_ANALYTICS.query(query);

    const stats = {};
    for (const row of result.results || []) {
      stats[row.cacheKey] = row.accessCount;
    }

    return stats;

  } catch (error) {
    console.error('Failed to query Analytics Engine:', error);
    return {};
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npm test analytics-queries.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/utils/analytics-queries.js tests/analytics-queries.test.js
git commit -m "feat(cache): add Analytics Engine access frequency query"
```

---

## Task 2: R2 Path Generation Utility

**Files:**
- Create: `cloudflare-workers/api-worker/src/utils/r2-paths.js`
- Test: `cloudflare-workers/api-worker/tests/r2-paths.test.js`

**Step 1: Write the failing test**

Create `tests/r2-paths.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { generateR2Path, parseR2Path } from '../src/utils/r2-paths.js';

describe('R2 Path Utilities', () => {
  it('should generate date-based R2 path', () => {
    const cacheKey = 'search:title:q=obscure-book';
    const path = generateR2Path(cacheKey);

    expect(path).toMatch(/^cold-cache\/\d{4}\/\d{2}\/search:title:q=obscure-book\.json$/);
  });

  it('should parse R2 path back to cache key', () => {
    const path = 'cold-cache/2025/10/search:title:q=obscure-book.json';
    const cacheKey = parseR2Path(path);

    expect(cacheKey).toBe('search:title:q=obscure-book');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test r2-paths.test.js`

Expected: `FAIL - Cannot find module 'r2-paths.js'`

**Step 3: Write minimal implementation**

Create `src/utils/r2-paths.js`:

```javascript
/**
 * Generate R2 path for cold cache entry
 *
 * Format: cold-cache/YYYY/MM/cache-key.json
 *
 * @param {string} cacheKey - Original cache key
 * @returns {string} R2 object path
 */
export function generateR2Path(cacheKey) {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');

  return `cold-cache/${year}/${month}/${cacheKey}.json`;
}

/**
 * Parse cache key from R2 path
 *
 * @param {string} r2Path - R2 object path
 * @returns {string} Original cache key
 */
export function parseR2Path(r2Path) {
  // Remove prefix and .json suffix
  const filename = r2Path.split('/').pop();
  return filename.replace(/\.json$/, '');
}
```

**Step 4: Run test to verify it passes**

Run: `npm test r2-paths.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/utils/r2-paths.js tests/r2-paths.test.js
git commit -m "feat(cache): add R2 path generation utilities"
```

---

## Task 3: Archival Worker - Candidate Selection

**Files:**
- Create: `cloudflare-workers/api-worker/src/workers/archival-worker.js`
- Test: `cloudflare-workers/api-worker/tests/archival-worker.test.js`

**Step 1: Write the failing test**

Create `tests/archival-worker.test.js`:

```javascript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { selectArchivalCandidates } from '../src/workers/archival-worker.js';

describe('selectArchivalCandidates', () => {
  let env;

  beforeEach(() => {
    env = {
      CACHE: {
        list: vi.fn().mockResolvedValue({
          keys: [
            { name: 'search:title:q=old-book' },
            { name: 'search:title:q=popular-book' }
          ]
        }),
        getWithMetadata: vi.fn()
      }
    };
  });

  it('should select entries that are old AND rarely accessed', async () => {
    const accessStats = {
      'search:title:q=old-book': 5,
      'search:title:q=popular-book': 100
    };

    const now = Date.now();
    const thirtyOneDaysAgo = now - (31 * 24 * 60 * 60 * 1000);

    env.CACHE.getWithMetadata.mockImplementation(async (key) => {
      if (key === 'search:title:q=old-book') {
        return {
          value: JSON.stringify({ items: [] }),
          metadata: { cachedAt: thirtyOneDaysAgo }
        };
      } else {
        return {
          value: JSON.stringify({ items: [] }),
          metadata: { cachedAt: now }
        };
      }
    });

    const candidates = await selectArchivalCandidates(env, accessStats);

    expect(candidates).toHaveLength(1);
    expect(candidates[0].key).toBe('search:title:q=old-book');
  });

  it('should NOT archive entries that are frequently accessed', async () => {
    const accessStats = {
      'search:title:q=popular-book': 100
    };

    env.CACHE.getWithMetadata.mockResolvedValue({
      value: JSON.stringify({ items: [] }),
      metadata: { cachedAt: Date.now() - (40 * 24 * 60 * 60 * 1000) } // 40 days old
    });

    const candidates = await selectArchivalCandidates(env, accessStats);

    expect(candidates).toHaveLength(0); // Excluded because accessCount > 10
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test archival-worker.test.js`

Expected: `FAIL - Cannot find module 'archival-worker.js'`

**Step 3: Write minimal implementation**

Create `src/workers/archival-worker.js`:

```javascript
/**
 * Select cache entries that qualify for R2 archival
 *
 * Criteria: age > 30 days AND accessCount < 10/month
 *
 * @param {Object} env - Worker environment
 * @param {Object} accessStats - Map of cacheKey → accessCount
 * @returns {Promise<Array>} Archival candidates
 */
export async function selectArchivalCandidates(env, accessStats) {
  const candidates = [];

  // List all KV keys (excluding cold-index and warming metadata)
  const kvKeys = await env.CACHE.list();

  for (const key of kvKeys.keys) {
    // Skip internal keys
    if (key.name.startsWith('cold-index:') ||
        key.name.startsWith('warming:') ||
        key.name.startsWith('config:')) {
      continue;
    }

    // Get metadata
    const entry = await env.CACHE.getWithMetadata(key.name);
    if (!entry || !entry.metadata || !entry.metadata.cachedAt) {
      continue;
    }

    const age = Date.now() - entry.metadata.cachedAt;
    const accessCount = accessStats[key.name] || 0;

    // Hybrid archival criteria
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    if (age > thirtyDaysMs && accessCount < 10) {
      candidates.push({
        key: key.name,
        data: entry.value,
        age: age,
        accessCount: accessCount
      });
    }
  }

  return candidates;
}
```

**Step 4: Run test to verify it passes**

Run: `npm test archival-worker.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/workers/archival-worker.js tests/archival-worker.test.js
git commit -m "feat(cache): add archival candidate selection logic"
```

---

## Task 4: Archival Worker - R2 Write & Index

**Files:**
- Modify: `cloudflare-workers/api-worker/src/workers/archival-worker.js`

**Step 1: Write test for archival**

Add to `tests/archival-worker.test.js`:

```javascript
import { archiveCandidates } from '../src/workers/archival-worker.js';

it('should archive candidates to R2 and create index', async () => {
  env.LIBRARY_DATA = {
    put: vi.fn().mockResolvedValue(undefined)
  };

  const candidates = [
    {
      key: 'search:title:q=old-book',
      data: JSON.stringify({ items: [] }),
      age: 40 * 24 * 60 * 60 * 1000,
      accessCount: 3
    }
  ];

  await archiveCandidates(candidates, env);

  expect(env.LIBRARY_DATA.put).toHaveBeenCalledWith(
    expect.stringContaining('cold-cache/'),
    expect.any(String),
    expect.objectContaining({
      customMetadata: expect.objectContaining({
        originalKey: 'search:title:q=old-book'
      })
    })
  );

  expect(env.CACHE.put).toHaveBeenCalledWith(
    'cold-index:search:title:q=old-book',
    expect.any(String)
  );

  expect(env.CACHE.delete).toHaveBeenCalledWith('search:title:q=old-book');
});
```

**Step 2: Run test to verify it fails**

Run: `npm test archival-worker.test.js`

Expected: `FAIL - archiveCandidates is not a function`

**Step 3: Implement archival**

Add to `src/workers/archival-worker.js`:

```javascript
import { generateR2Path } from '../utils/r2-paths.js';

/**
 * Archive candidates to R2 and create cold index
 *
 * @param {Array} candidates - Archival candidates
 * @param {Object} env - Worker environment
 * @returns {Promise<number>} Count of archived entries
 */
export async function archiveCandidates(candidates, env) {
  let archivedCount = 0;

  for (const candidate of candidates) {
    try {
      const r2Path = generateR2Path(candidate.key);

      // 1. Write to R2
      await env.LIBRARY_DATA.put(r2Path, candidate.data, {
        customMetadata: {
          originalKey: candidate.key,
          archivedAt: Date.now().toString(),
          originalTTL: '86400',
          accessCount: candidate.accessCount.toString()
        }
      });

      // 2. Create cold storage index in KV
      await env.CACHE.put(`cold-index:${candidate.key}`, JSON.stringify({
        r2Path: r2Path,
        archivedAt: Date.now(),
        originalTTL: 86400,
        archiveReason: `age=${Math.floor(candidate.age / (24 * 60 * 60 * 1000))}d, access=${candidate.accessCount}/month`
      }));

      // 3. Delete from KV
      await env.CACHE.delete(candidate.key);

      archivedCount++;

    } catch (error) {
      console.error(`Failed to archive ${candidate.key}:`, error);
      // Continue with next candidate (don't fail entire batch)
    }
  }

  return archivedCount;
}
```

**Step 4: Run test to verify it passes**

Run: `npm test archival-worker.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/workers/archival-worker.js tests/archival-worker.test.js
git commit -m "feat(cache): implement R2 archival with cold index"
```

---

## Task 5: Scheduled Archival Cron Handler

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/scheduled-archival.js`
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Add cron trigger to wrangler.toml**

Modify `wrangler.toml` (add at end):

```toml
# Scheduled tasks
[triggers]
crons = ["0 2 * * *"]  # Daily at 2:00 AM UTC
```

**Step 2: Create cron handler**

Create `src/handlers/scheduled-archival.js`:

```javascript
import { queryAccessFrequency } from '../utils/analytics-queries.js';
import { selectArchivalCandidates, archiveCandidates } from '../workers/archival-worker.js';

/**
 * Scheduled handler for daily archival process
 *
 * @param {Object} env - Worker environment
 * @param {ExecutionContext} ctx - Execution context
 */
export async function handleScheduledArchival(env, ctx) {
  const startTime = Date.now();

  try {
    console.log('Starting scheduled archival process...');

    // 1. Query Analytics Engine for access stats (last 30 days)
    const accessStats = await queryAccessFrequency(env, 30);

    // 2. Select archival candidates
    const candidates = await selectArchivalCandidates(env, accessStats);

    console.log(`Found ${candidates.length} archival candidates`);

    if (candidates.length === 0) {
      console.log('No entries to archive');
      return;
    }

    // 3. Archive to R2
    const archivedCount = await archiveCandidates(candidates, env);

    // 4. Log metrics
    const duration = Date.now() - startTime;
    console.log(`Archived ${archivedCount}/${candidates.length} entries in ${duration}ms`);

    // Log to Analytics Engine
    if (env.CACHE_ANALYTICS) {
      env.CACHE_ANALYTICS.writeDataPoint({
        blobs: ['archival_completed', ''],
        doubles: [archivedCount, duration],
        indexes: ['archival_completed']
      });
    }

  } catch (error) {
    console.error('Scheduled archival failed:', error);

    // Log error metric
    if (env.CACHE_ANALYTICS) {
      env.CACHE_ANALYTICS.writeDataPoint({
        blobs: ['archival_failed', error.message],
        doubles: [Date.now() - startTime],
        indexes: ['archival_failed']
      });
    }
  }
}
```

**Step 3: Wire to index.js**

Modify `src/index.js` (add scheduled handler):

```javascript
import { handleScheduledArchival } from './handlers/scheduled-archival.js';

export default {
  async fetch(request, env, ctx) {
    // ... existing HTTP routing ...
  },

  async queue(batch, env, ctx) {
    // ... existing queue routing ...
  },

  async scheduled(event, env, ctx) {
    // Run daily archival process
    await handleScheduledArchival(env, ctx);
  }
};
```

**Step 4: Deploy and verify**

Run: `npx wrangler deploy`

Expected: `✓ Uploaded api-worker (X.XX sec)` with cron trigger registered

**Step 5: Test cron manually**

Run: `npx wrangler tail api-worker --format pretty`

Trigger manually (via Cloudflare dashboard Cron Triggers tab or wait for scheduled run)

Expected: Logs showing `Starting scheduled archival process...`

**Step 6: Commit**

```bash
git add src/handlers/scheduled-archival.js src/index.js wrangler.toml
git commit -m "feat(cache): add scheduled R2 archival cron handler"
```

---

## Task 6: UnifiedCacheService - Cold Storage Check

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/unified-cache.js:50-54`

**Step 1: Write test for cold storage check**

Create `tests/unified-cache-cold.test.js`:

```javascript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { UnifiedCacheService } from '../src/services/unified-cache.js';

describe('UnifiedCacheService - Cold Storage', () => {
  let env, ctx, cache;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn()
      },
      LIBRARY_DATA: {
        get: vi.fn()
      }
    };
    ctx = {
      waitUntil: vi.fn()
    };
    cache = new UnifiedCacheService(env, ctx);
  });

  it('should check cold index after KV miss', async () => {
    // Mock: Edge miss, KV miss, cold index hit
    cache.edgeCache.get = vi.fn().mockResolvedValue(null);
    cache.kvCache.get = vi.fn().mockResolvedValue(null);

    env.CACHE.get.mockResolvedValueOnce(JSON.stringify({
      r2Path: 'cold-cache/2025/10/search:title:q=book.json',
      archivedAt: Date.now(),
      originalTTL: 86400
    }));

    const result = await cache.get('search:title:q=book', 'title');

    expect(result.data).toBeNull(); // User gets fresh data
    expect(ctx.waitUntil).toHaveBeenCalled(); // Rehydration triggered
  });

  it('should return API miss if no cold index', async () => {
    cache.edgeCache.get = vi.fn().mockResolvedValue(null);
    cache.kvCache.get = vi.fn().mockResolvedValue(null);
    env.CACHE.get.mockResolvedValue(null);

    const result = await cache.get('search:title:q=new-book', 'title');

    expect(result.source).toBe('MISS');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test unified-cache-cold.test.js`

Expected: `FAIL - cold storage not checked`

**Step 3: Implement cold storage check**

Modify `src/services/unified-cache.js`:

```javascript
async get(cacheKey, endpoint, options = {}) {
  const startTime = Date.now();

  // Tier 1: Edge Cache
  const edgeResult = await this.edgeCache.get(cacheKey);
  if (edgeResult) {
    this.logMetrics('edge_hit', cacheKey, Date.now() - startTime);
    return edgeResult;
  }

  // Tier 2: KV Cache
  const kvResult = await this.kvCache.get(cacheKey, endpoint);
  if (kvResult) {
    this.ctx.waitUntil(
      this.edgeCache.set(cacheKey, kvResult.data, 6 * 60 * 60)
    );
    this.logMetrics('kv_hit', cacheKey, Date.now() - startTime);
    return kvResult;
  }

  // NEW: Tier 2.5: Check Cold Storage Index
  const coldIndex = await this.env.CACHE.get(`cold-index:${cacheKey}`, 'json');
  if (coldIndex) {
    this.logMetrics('cold_check', cacheKey, Date.now() - startTime);

    // Trigger background rehydration (non-blocking)
    this.ctx.waitUntil(
      this.rehydrateFromR2(cacheKey, coldIndex, endpoint)
    );

    // Return null immediately (user gets fresh API data)
    return { data: null, source: 'COLD', latency: Date.now() - startTime };
  }

  // Tier 3: API Miss
  this.logMetrics('api_miss', cacheKey, Date.now() - startTime);
  return { data: null, source: 'MISS', latency: Date.now() - startTime };
}
```

**Step 4: Run test to verify it passes**

Run: `npm test unified-cache-cold.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/services/unified-cache.js tests/unified-cache-cold.test.js
git commit -m "feat(cache): add cold storage check to UnifiedCacheService"
```

---

## Task 7: Background Rehydration

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/unified-cache.js`

**Step 1: Write test for rehydration**

Add to `tests/unified-cache-cold.test.js`:

```javascript
import { UnifiedCacheService } from '../src/services/unified-cache.js';

it('should rehydrate from R2 to KV and Edge', async () => {
  const mockR2Object = {
    json: vi.fn().mockResolvedValue({ items: [{ title: 'Book' }] })
  };

  env.LIBRARY_DATA.get.mockResolvedValue(mockR2Object);
  cache.kvCache.set = vi.fn();
  cache.edgeCache.set = vi.fn();
  env.CACHE.delete = vi.fn();

  const coldIndex = {
    r2Path: 'cold-cache/2025/10/search:title:q=book.json',
    archivedAt: Date.now(),
    originalTTL: 86400
  };

  await cache.rehydrateFromR2('search:title:q=book', coldIndex, 'title');

  expect(env.LIBRARY_DATA.get).toHaveBeenCalledWith(coldIndex.r2Path);
  expect(cache.kvCache.set).toHaveBeenCalled();
  expect(cache.edgeCache.set).toHaveBeenCalled();
  expect(env.CACHE.delete).toHaveBeenCalledWith('cold-index:search:title:q=book');
});
```

**Step 2: Run test to verify it fails**

Run: `npm test unified-cache-cold.test.js`

Expected: `FAIL - rehydrateFromR2 is not a function`

**Step 3: Implement rehydration**

Add to `src/services/unified-cache.js`:

```javascript
/**
 * Rehydrate archived data from R2 to KV and Edge
 *
 * @param {string} cacheKey - Original cache key
 * @param {Object} coldIndex - Cold storage index metadata
 * @param {string} endpoint - Endpoint type
 */
async rehydrateFromR2(cacheKey, coldIndex, endpoint) {
  try {
    console.log(`Rehydrating ${cacheKey} from R2...`);

    // 1. Fetch from R2
    const r2Object = await this.env.LIBRARY_DATA.get(coldIndex.r2Path);
    if (!r2Object) {
      console.error(`R2 object not found: ${coldIndex.r2Path}`);
      return;
    }

    const data = await r2Object.json();

    // 2. Restore to KV with extended TTL (7 days)
    await this.kvCache.set(cacheKey, data, endpoint, {
      ttl: 7 * 24 * 60 * 60
    });

    // 3. Populate Edge cache
    await this.edgeCache.set(cacheKey, data, 6 * 60 * 60);

    // 4. Remove from cold index (now warm)
    await this.env.CACHE.delete(`cold-index:${cacheKey}`);

    // 5. Log rehydration
    this.logMetrics('r2_rehydrated', cacheKey, 0);

    console.log(`Successfully rehydrated ${cacheKey}`);

  } catch (error) {
    console.error(`Rehydration failed for ${cacheKey}:`, error);
    // Log error but don't throw (background operation)
  }
}
```

**Step 4: Add KVCacheService.set() method**

Modify `src/services/kv-cache.js` (add method):

```javascript
/**
 * Set cached data in KV
 * @param {string} cacheKey - Cache key
 * @param {Object} data - Data to cache
 * @param {string} endpoint - Endpoint type ('title', 'isbn', 'author')
 * @param {Object} options - Options (ttl override)
 * @returns {Promise<void>}
 */
async set(cacheKey, data, endpoint, options = {}) {
  try {
    const ttl = options.ttl || this.ttls[endpoint] || this.ttls.title;

    await this.env.CACHE.put(cacheKey, JSON.stringify(data), {
      expirationTtl: ttl,
      metadata: {
        cachedAt: Date.now(),
        endpoint: endpoint
      }
    });

  } catch (error) {
    console.error(`KV cache set failed for ${cacheKey}:`, error);
  }
}
```

**Step 5: Run test to verify it passes**

Run: `npm test unified-cache-cold.test.js`

Expected: `PASS`

**Step 6: Commit**

```bash
git add src/services/unified-cache.js src/services/kv-cache.js tests/unified-cache-cold.test.js
git commit -m "feat(cache): implement R2 background rehydration"
```

---

## Task 8: R2 Lifecycle Configuration

**Files:**
- Create: `cloudflare-workers/api-worker/scripts/setup-r2-lifecycle.sh`

**Step 1: Create lifecycle setup script**

Create `scripts/setup-r2-lifecycle.sh`:

```bash
#!/bin/bash
# Setup R2 lifecycle rules for automatic deletion

echo "Setting up R2 lifecycle for cold-cache..."

# Create lifecycle rule (deletes objects older than 1 year)
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/personal-library-data/lifecycle" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "rules": [
      {
        "id": "cold-cache-expiration",
        "status": "Enabled",
        "filter": {
          "prefix": "cold-cache/"
        },
        "expiration": {
          "days": 365
        }
      }
    ]
  }'

echo "Lifecycle rule created: cold-cache entries expire after 365 days"
```

**Step 2: Make executable**

Run: `chmod +x scripts/setup-r2-lifecycle.sh`

**Step 3: Document usage**

Add to `docs/CACHE_WARMING.md`:

```markdown
## R2 Lifecycle Management

**Automatic Deletion:**
Run once to configure:
\`\`\`bash
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
./scripts/setup-r2-lifecycle.sh
\`\`\`

**Manual Purge:**
\`\`\`bash
# Delete all 2024 archives
npx wrangler r2 object bulk-delete \\
  --bucket personal-library-data \\
  --prefix cold-cache/2024/
\`\`\`
```

**Step 4: Commit**

```bash
git add scripts/setup-r2-lifecycle.sh docs/CACHE_WARMING.md
git commit -m "feat(cache): add R2 lifecycle configuration script"
```

---

## Task 9: Cost & Performance Metrics

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/cache-metrics.js`

**Step 1: Create metrics endpoint**

Create `src/handlers/cache-metrics.js`:

```javascript
/**
 * GET /api/cache/metrics - Cache performance and cost metrics
 *
 * @param {Request} request
 * @param {Object} env
 * @returns {Response} Metrics summary
 */
export async function handleCacheMetrics(request, env) {
  try {
    const url = new URL(request.url);
    const period = url.searchParams.get('period') || '24h';

    // Query Analytics Engine for cache tier distribution
    const query = `
      SELECT
        index1 as cache_tier,
        COUNT(*) as hits
      FROM CACHE_ANALYTICS
      WHERE timestamp > NOW() - INTERVAL '${period}'
      GROUP BY index1
    `;

    const result = await env.CACHE_ANALYTICS.query(query);

    const metrics = {
      period: period,
      tiers: {},
      totalRequests: 0
    };

    for (const row of result.results || []) {
      metrics.tiers[row.cache_tier] = row.hits;
      metrics.totalRequests += row.hits;
    }

    // Calculate hit rates
    const edgeHits = metrics.tiers.edge_hit || 0;
    const kvHits = metrics.tiers.kv_hit || 0;
    const r2Rehydrations = metrics.tiers.r2_rehydrated || 0;
    const apiMisses = metrics.tiers.api_miss || 0;

    metrics.hitRates = {
      edge: ((edgeHits / metrics.totalRequests) * 100).toFixed(1),
      kv: ((kvHits / metrics.totalRequests) * 100).toFixed(1),
      combined: (((edgeHits + kvHits) / metrics.totalRequests) * 100).toFixed(1)
    };

    // Estimate costs (simplified)
    metrics.estimatedCosts = {
      kvReads: `$${(kvHits * 0.50 / 1000000).toFixed(4)}/period`,
      r2Reads: `$${(r2Rehydrations * 0.36 / 1000000).toFixed(4)}/period`,
      total: `$${((kvHits * 0.50 + r2Rehydrations * 0.36) / 1000000).toFixed(4)}/period`
    };

    return new Response(JSON.stringify(metrics, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to fetch metrics',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
```

**Step 2: Add route to index.js**

Modify `src/index.js`:

```javascript
import { handleCacheMetrics } from './handlers/cache-metrics.js';

// GET /api/cache/metrics - Cache performance metrics
if (url.pathname === '/api/cache/metrics' && request.method === 'GET') {
  return handleCacheMetrics(request, env);
}
```

**Step 3: Deploy and test**

Run: `npx wrangler deploy`

Test:
```bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/api/cache/metrics?period=24h"
```

Expected: JSON with hit rates and cost estimates

**Step 4: Commit**

```bash
git add src/handlers/cache-metrics.js src/index.js
git commit -m "feat(cache): add cache metrics endpoint"
```

---

## Task 10: Integration Testing

**Files:**
- Create: `cloudflare-workers/api-worker/tests/integration/r2-archival.test.js`

**Step 1: Write E2E test**

Create `tests/integration/r2-archival.test.js`:

```javascript
import { describe, it, expect, beforeAll } from 'vitest';

describe('R2 Cold Storage Flow (E2E)', () => {
  let env;

  beforeAll(async () => {
    env = await setupTestEnvironment();
  });

  it('should archive old entry and rehydrate on access', async () => {
    // 1. Manually create old cache entry
    await env.CACHE.put('search:title:q=test-old-book', JSON.stringify({
      items: [{ title: 'Test Old Book' }]
    }), {
      metadata: {
        cachedAt: Date.now() - (40 * 24 * 60 * 60 * 1000) // 40 days old
      }
    });

    // 2. Run archival process
    await handleScheduledArchival(env, { waitUntil: (p) => p });

    // 3. Verify archived to R2
    const coldIndex = await env.CACHE.get('cold-index:search:title:q=test-old-book', 'json');
    expect(coldIndex).toBeTruthy();
    expect(coldIndex.r2Path).toMatch(/^cold-cache\/\d{4}\/\d{2}\//);

    // 4. Verify deleted from KV
    const kvEntry = await env.CACHE.get('search:title:q=test-old-book');
    expect(kvEntry).toBeNull();

    // 5. Access via UnifiedCacheService (triggers rehydration)
    const cache = new UnifiedCacheService(env, { waitUntil: (p) => p });
    const result = await cache.get('search:title:q=test-old-book', 'title');

    expect(result.source).toBe('COLD'); // First access = miss

    // 6. Wait for rehydration
    await new Promise(resolve => setTimeout(resolve, 2000));

    // 7. Verify rehydrated to KV
    const rehydrated = await env.CACHE.get('search:title:q=test-old-book');
    expect(rehydrated).toBeTruthy();

    // 8. Verify cold index removed
    const indexAfter = await env.CACHE.get('cold-index:search:title:q=test-old-book');
    expect(indexAfter).toBeNull();
  }, 15000); // 15s timeout
});
```

**Step 2: Run integration test**

Run: `npm test integration/r2-archival.test.js`

Expected: `PASS` (or identify integration issues)

**Step 3: Commit**

```bash
git add tests/integration/r2-archival.test.js
git commit -m "test(cache): add E2E R2 archival and rehydration test"
```

---

## Task 11: Documentation

**Files:**
- Create: `cloudflare-workers/api-worker/docs/R2_COLD_STORAGE.md`

**Step 1: Write usage documentation**

Create `docs/R2_COLD_STORAGE.md`:

```markdown
# R2 Cold Storage - Phase 3

## Overview

Reduces KV costs by archiving rarely-accessed cache entries to R2, with background rehydration on access.

## Architecture

**Archival Criteria (Hybrid):**
- Age > 30 days
- Access count < 10 requests/month

**Schedule:** Daily at 2:00 AM UTC (Cron trigger)

**User Experience:**
- First request after archival: Fresh API data (no latency penalty)
- Second request: Served from KV (~30-50ms, rehydrated in background)
- Third+ requests: Served from Edge (<10ms)

## Cost Savings

**Example (10K entries, 30% archival rate):**
- Before: $1.75/month (all in KV)
- After: $1.53/month (70% KV, 30% R2)
- **Savings: 12%**

**Break-even:** Entries accessed < 0.5x/month are cheaper in R2

## Monitoring

**Metrics Endpoint:**
\`\`\`bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/api/cache/metrics?period=24h"
\`\`\`

**Response:**
\`\`\`json
{
  "hitRates": {
    "edge": "78.2%",
    "kv": "16.5%",
    "combined": "94.7%"
  },
  "tiers": {
    "r2_rehydrated": 50
  }
}
\`\`\`

**Analytics Engine Query:**
\`\`\`sql
SELECT
  DATE_TRUNC('day', timestamp) as day,
  COUNT(CASE WHEN index1 = 'r2_rehydrated' THEN 1 END) as rehydrations
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '30' DAY
GROUP BY day
ORDER BY day DESC;
\`\`\`

## Troubleshooting

**Archival not running:**
1. Check cron trigger: `wrangler deployments list`
2. Verify scheduled handler logs: `wrangler tail api-worker`

**Rehydration failures:**
1. Check R2 object exists: `wrangler r2 object get personal-library-data <r2Path>`
2. Verify cold index: `wrangler kv:key get CACHE "cold-index:<cacheKey>"`

**High R2 costs:**
- Check rehydration rate (should be < 1% of requests)
- Increase archival threshold (e.g., age > 60 days)
```

**Step 2: Commit**

```bash
git add docs/R2_COLD_STORAGE.md
git commit -m "docs(cache): add R2 cold storage usage guide"
```

---

## Verification Checklist

Before considering Phase 3 complete, verify:

- [ ] Cron trigger deploys successfully
- [ ] Scheduled archival runs at 2:00 AM UTC
- [ ] Old entries archived to R2 (check `wrangler r2 object list`)
- [ ] Cold index created in KV (`cold-index:*` keys)
- [ ] Rehydration triggered on access
- [ ] Metrics endpoint returns hit rates
- [ ] Analytics Engine shows `r2_rehydrated` events
- [ ] All tests pass: `npm test`

---

## Next Steps

After Phase 3 deployment:

1. **Phase 4:** Monitoring & Optimization (alerts, A/B testing)
2. **Enhancement:** Predictive rehydration (ML-based)
3. **Enhancement:** Compression (Gzip before R2 write)
4. **Enhancement:** Cross-region R2 replication
