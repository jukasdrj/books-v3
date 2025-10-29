# Cache Warming Implementation Plan - Phase 2

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build intelligent cache warming system that seeds from CSV files and auto-discovers related content via Cloudflare Queues.

**Architecture:** CSV Upload → Gemini Parse → Cloudflare Queue → Consumer Workers → Cache Population + Author Discovery

**Tech Stack:** Cloudflare Workers, Cloudflare Queues, KV, Gemini API, UnifiedCacheService

**Prerequisites:**
- Phase 1 complete (UnifiedCacheService, KVCacheService, EdgeCacheService)
- Gemini CSV parser exists (`src/providers/gemini-csv-provider.js`)
- KV namespace `CACHE` configured in `wrangler.toml`

---

## Task 1: Configure Cloudflare Queue Infrastructure

**Files:**
- Modify: `cloudflare-workers/api-worker/wrangler.toml:123-end`

**Step 1: Add Queue producer binding**

In `wrangler.toml`, add after the `[placement]` section:

```toml
# Queues for cache warming (Phase 2)
[[queues.producers]]
binding = "AUTHOR_WARMING_QUEUE"
queue = "author-warming-queue"

[[queues.consumers]]
queue = "author-warming-queue"
max_batch_size = 10
max_batch_timeout = 30
max_retries = 3
dead_letter_queue = "author-warming-dlq"
```

**Step 2: Deploy configuration**

Run: `cd cloudflare-workers/api-worker && npx wrangler deploy`

Expected: `✓ Uploaded api-worker (X.XX sec)` with queue bindings recognized

**Step 3: Create dead letter queue**

Run: `npx wrangler queues create author-warming-dlq`

Expected: `Created queue author-warming-dlq`

**Step 4: Commit**

```bash
git add cloudflare-workers/api-worker/wrangler.toml
git commit -m "feat(cache): add Cloudflare Queue for cache warming"
```

---

## Task 2: CSV Ingestion Endpoint - Request Validation

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/warming-upload.js`
- Test: TDD approach (write failing test first)

**Step 1: Write the failing test**

Create `cloudflare-workers/api-worker/tests/warming-upload.test.js`:

```javascript
import { describe, it, expect, beforeEach } from 'vitest';
import { handleWarmingUpload } from '../src/handlers/warming-upload.js';

describe('handleWarmingUpload', () => {
  let env, ctx;

  beforeEach(() => {
    env = {
      AUTHOR_WARMING_QUEUE: {
        send: async (msg) => ({ id: 'msg-123' })
      },
      CACHE: {
        put: async () => {},
        get: async () => null
      }
    };
    ctx = {
      waitUntil: (promise) => promise
    };
  });

  it('should reject request without csv field', async () => {
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ maxDepth: 2 })
    });

    const response = await handleWarmingUpload(request, env, ctx);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('csv');
  });

  it('should reject invalid maxDepth', async () => {
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ csv: 'base64data', maxDepth: 5 })
    });

    const response = await handleWarmingUpload(request, env, ctx);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('maxDepth must be 1-3');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd cloudflare-workers/api-worker && npm test warming-upload.test.js`

Expected: `FAIL - Cannot find module 'warming-upload.js'`

**Step 3: Write minimal implementation**

Create `cloudflare-workers/api-worker/src/handlers/warming-upload.js`:

```javascript
/**
 * POST /api/warming/upload - Cache warming via CSV upload
 *
 * @param {Request} request - HTTP request with { csv, maxDepth, priority }
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context
 * @returns {Response} Job ID and estimates
 */
export async function handleWarmingUpload(request, env, ctx) {
  try {
    const body = await request.json();

    // Validate required fields
    if (!body.csv) {
      return new Response(JSON.stringify({
        error: 'Missing required field: csv (base64-encoded CSV file)'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate maxDepth
    const maxDepth = body.maxDepth || 2;
    if (maxDepth < 1 || maxDepth > 3) {
      return new Response(JSON.stringify({
        error: 'maxDepth must be 1-3'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // TODO: Parse CSV and queue authors
    return new Response(JSON.stringify({
      jobId: 'placeholder',
      authorsQueued: 0
    }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to process upload',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npm test warming-upload.test.js`

Expected: `PASS (2 tests)`

**Step 5: Commit**

```bash
git add src/handlers/warming-upload.js tests/warming-upload.test.js
git commit -m "feat(cache): add warming upload handler with validation"
```

---

## Task 3: CSV Parsing Integration

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/warming-upload.js:37-40`
- Existing: `cloudflare-workers/api-worker/src/providers/gemini-csv-provider.js`

**Step 1: Write test for CSV parsing**

Add to `tests/warming-upload.test.js`:

```javascript
it('should parse CSV and extract unique authors', async () => {
  const csvData = btoa('title,author,isbn\nBook1,Author A,123\nBook2,Author A,456\nBook3,Author B,789');
  const request = new Request('https://api.example.com/api/warming/upload', {
    method: 'POST',
    body: JSON.stringify({ csv: csvData, maxDepth: 1 })
  });

  // Mock Gemini response
  env.GEMINI_API_KEY = { fetch: async () => ({ text: async () => 'mocked' }) };

  const response = await handleWarmingUpload(request, env, ctx);

  expect(response.status).toBe(202);
  const body = await response.json();
  expect(body.authorsQueued).toBe(2); // Author A and Author B
  expect(body.jobId).toMatch(/^[0-9a-f-]{36}$/); // UUID format
});
```

**Step 2: Run test to verify it fails**

Run: `npm test warming-upload.test.js`

Expected: `FAIL - authorsQueued is 0, expected 2`

**Step 3: Implement CSV parsing**

Modify `src/handlers/warming-upload.js`:

```javascript
import { parseCSVWithGemini } from '../providers/gemini-csv-provider.js';
import { randomUUID } from 'node:crypto';

export async function handleWarmingUpload(request, env, ctx) {
  try {
    const body = await request.json();

    // ... validation code (keep existing) ...

    // Decode CSV
    const csvText = atob(body.csv);

    // Parse with Gemini
    const parseResult = await parseCSVWithGemini(csvText, env);

    if (!parseResult.success) {
      return new Response(JSON.stringify({
        error: 'CSV parsing failed',
        message: parseResult.error
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Extract unique authors
    const authorsSet = new Set();
    for (const book of parseResult.books) {
      if (book.author) {
        authorsSet.add(book.author.trim());
      }
    }

    const uniqueAuthors = Array.from(authorsSet);
    const jobId = randomUUID();

    // TODO: Queue authors

    return new Response(JSON.stringify({
      jobId,
      authorsQueued: uniqueAuthors.length,
      estimatedWorks: uniqueAuthors.length * 15,
      estimatedDuration: '2-4 hours'
    }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to process upload',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npm test warming-upload.test.js`

Expected: `PASS (3 tests)`

**Step 5: Commit**

```bash
git add src/handlers/warming-upload.js tests/warming-upload.test.js
git commit -m "feat(cache): integrate Gemini CSV parsing for warming"
```

---

## Task 4: Queue Author Messages

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/warming-upload.js:82-84`

**Step 1: Write test for queueing**

Add to `tests/warming-upload.test.js`:

```javascript
it('should queue each author with metadata', async () => {
  const messages = [];
  env.AUTHOR_WARMING_QUEUE.send = async (msg) => {
    messages.push(msg);
    return { id: `msg-${messages.length}` };
  };

  const csvData = btoa('title,author,isbn\nBook1,Author A,123');
  const request = new Request('https://api.example.com/api/warming/upload', {
    method: 'POST',
    body: JSON.stringify({ csv: csvData, maxDepth: 2 })
  });

  await handleWarmingUpload(request, env, ctx);

  expect(messages).toHaveLength(1);
  expect(messages[0].author).toBe('Author A');
  expect(messages[0].depth).toBe(0);
  expect(messages[0].source).toBe('csv');
});
```

**Step 2: Run test to verify it fails**

Run: `npm test warming-upload.test.js`

Expected: `FAIL - messages array is empty`

**Step 3: Implement queueing**

Modify `src/handlers/warming-upload.js`:

```javascript
// After extracting uniqueAuthors...

const jobId = randomUUID();

// Queue each author
for (const author of uniqueAuthors) {
  await env.AUTHOR_WARMING_QUEUE.send({
    author: author,
    source: 'csv',
    depth: 0,
    queuedAt: new Date().toISOString(),
    jobId: jobId
  });
}

// Store job metadata in KV
await env.CACHE.put(`warming:job:${jobId}`, JSON.stringify({
  authorsQueued: uniqueAuthors.length,
  maxDepth: maxDepth,
  startedAt: Date.now(),
  status: 'queued'
}), {
  expirationTtl: 7 * 24 * 60 * 60 // 7 days
});

return new Response(JSON.stringify({
  jobId,
  authorsQueued: uniqueAuthors.length,
  estimatedWorks: uniqueAuthors.length * 15,
  estimatedDuration: '2-4 hours'
}), {
  status: 202,
  headers: { 'Content-Type': 'application/json' }
});
```

**Step 4: Run test to verify it passes**

Run: `npm test warming-upload.test.js`

Expected: `PASS (4 tests)`

**Step 5: Commit**

```bash
git add src/handlers/warming-upload.js tests/warming-upload.test.js
git commit -m "feat(cache): queue authors for warming processing"
```

---

## Task 5: Author Discovery Consumer - Message Processing

**Files:**
- Create: `cloudflare-workers/api-worker/src/consumers/author-warming-consumer.js`
- Test: `cloudflare-workers/api-worker/tests/author-warming-consumer.test.js`

**Step 1: Write the failing test**

Create `tests/author-warming-consumer.test.js`:

```javascript
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { processAuthorBatch } from '../src/consumers/author-warming-consumer.js';

describe('processAuthorBatch', () => {
  let env, ctx, batch;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined)
      },
      AUTHOR_WARMING_QUEUE: {
        send: vi.fn().mockResolvedValue({ id: 'msg-123' })
      }
    };
    ctx = {
      waitUntil: vi.fn()
    };
    batch = {
      messages: [
        {
          body: { author: 'Neil Gaiman', depth: 0, source: 'csv', jobId: 'job-1' },
          ack: vi.fn(),
          retry: vi.fn()
        }
      ]
    };
  });

  it('should skip already processed authors', async () => {
    env.CACHE.get.mockResolvedValueOnce(JSON.stringify({
      worksCount: 20,
      lastWarmed: Date.now(),
      depth: 0
    }));

    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    expect(env.CACHE.put).not.toHaveBeenCalled();
  });

  it('should process new author and mark as processed', async () => {
    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    expect(env.CACHE.put).toHaveBeenCalledWith(
      'warming:processed:Neil Gaiman',
      expect.stringContaining('worksCount'),
      expect.objectContaining({ expirationTtl: 90 * 24 * 60 * 60 })
    );
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test author-warming-consumer.test.js`

Expected: `FAIL - Cannot find module 'author-warming-consumer.js'`

**Step 3: Write minimal implementation**

Create `src/consumers/author-warming-consumer.js`:

```javascript
/**
 * Author Warming Consumer - Processes queued authors
 *
 * @param {Object} batch - Batch of queue messages
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context
 */
export async function processAuthorBatch(batch, env, ctx) {
  for (const message of batch.messages) {
    try {
      const { author, depth, source, jobId } = message.body;

      // 1. Check if already processed
      const processed = await env.CACHE.get(`warming:processed:${author}`);
      if (processed) {
        const data = JSON.parse(processed);
        if (depth <= data.depth) {
          console.log(`Skipping ${author}: already processed at depth ${data.depth}`);
          message.ack();
          continue;
        }
      }

      // TODO: Search for author's works
      // TODO: Cache works
      // TODO: Discover co-authors

      // 5. Mark as processed
      await env.CACHE.put(
        `warming:processed:${author}`,
        JSON.stringify({
          worksCount: 0, // Placeholder
          lastWarmed: Date.now(),
          depth: depth
        }),
        { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
      );

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);
      message.retry();
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npm test author-warming-consumer.test.js`

Expected: `PASS (2 tests)`

**Step 5: Commit**

```bash
git add src/consumers/author-warming-consumer.js tests/author-warming-consumer.test.js
git commit -m "feat(cache): add author warming consumer with deduplication"
```

---

## Task 6: Search External APIs for Author Works

**Files:**
- Modify: `cloudflare-workers/api-worker/src/consumers/author-warming-consumer.js:28-31`
- Existing: `cloudflare-workers/api-worker/src/services/external-apis.js`

**Step 1: Write test for API search**

Add to `tests/author-warming-consumer.test.js`:

```javascript
it('should search external APIs and cache works', async () => {
  const mockWorks = [
    { title: 'American Gods', author: 'Neil Gaiman', isbn: '123' },
    { title: 'Good Omens', author: 'Neil Gaiman, Terry Pratchett', isbn: '456' }
  ];

  // Mock searchByAuthor function
  const { searchByAuthor } = await import('../src/services/external-apis.js');
  vi.mocked(searchByAuthor).mockResolvedValueOnce({
    items: mockWorks,
    total: 2
  });

  await processAuthorBatch(batch, env, ctx);

  expect(searchByAuthor).toHaveBeenCalledWith('Neil Gaiman', env);
  expect(env.CACHE.put).toHaveBeenCalledTimes(3); // 2 works + 1 processed marker
});
```

**Step 2: Run test to verify it fails**

Run: `npm test author-warming-consumer.test.js`

Expected: `FAIL - searchByAuthor not called`

**Step 3: Implement API search**

Modify `src/consumers/author-warming-consumer.js`:

```javascript
import { searchByAuthor } from '../services/external-apis.js';
import { generateCacheKey } from '../utils/cache-keys.js';
import { KVCacheService } from '../services/kv-cache.js';

export async function processAuthorBatch(batch, env, ctx) {
  const kvCache = new KVCacheService(env);

  for (const message of batch.messages) {
    try {
      const { author, depth, source, jobId } = message.body;

      // ... deduplication check (keep existing) ...

      // 2. Search external APIs for author's works
      const searchResult = await searchByAuthor(author, env);

      if (!searchResult || !searchResult.items) {
        console.warn(`No works found for ${author}`);
        message.ack();
        continue;
      }

      const works = searchResult.items;

      // 3. Cache each work via KVCacheService
      for (const work of works) {
        const cacheKey = generateCacheKey('search:title', {
          title: work.title.toLowerCase()
        });

        await kvCache.set(cacheKey, { items: [work] }, 'title', {
          ttl: 24 * 60 * 60 // 24h for warmed entries
        });
      }

      // TODO: Discover co-authors

      // 5. Mark as processed
      await env.CACHE.put(
        `warming:processed:${author}`,
        JSON.stringify({
          worksCount: works.length,
          lastWarmed: Date.now(),
          depth: depth
        }),
        { expirationTtl: 90 * 24 * 60 * 60 }
      );

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);
      message.retry();
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npm test author-warming-consumer.test.js`

Expected: `PASS (3 tests)`

**Step 5: Commit**

```bash
git add src/consumers/author-warming-consumer.js tests/author-warming-consumer.test.js
git commit -m "feat(cache): search and cache author works"
```

---

## Task 7: Co-Author Discovery

**Files:**
- Modify: `cloudflare-workers/api-worker/src/consumers/author-warming-consumer.js:52-54`

**Step 1: Write test for co-author discovery**

Add to `tests/author-warming-consumer.test.js`:

```javascript
it('should discover co-authors and queue them', async () => {
  const mockWorks = [
    { title: 'Good Omens', author: 'Neil Gaiman, Terry Pratchett', isbn: '456' }
  ];

  vi.mocked(searchByAuthor).mockResolvedValueOnce({
    items: mockWorks,
    total: 1
  });

  // Set depth to 1 to allow co-author discovery
  batch.messages[0].body.depth = 1;

  // Mock job metadata to check maxDepth
  env.CACHE.get.mockImplementation(async (key) => {
    if (key.startsWith('warming:job:')) {
      return JSON.stringify({ maxDepth: 2 });
    }
    return null;
  });

  await processAuthorBatch(batch, env, ctx);

  expect(env.AUTHOR_WARMING_QUEUE.send).toHaveBeenCalledWith(
    expect.objectContaining({
      author: 'Terry Pratchett',
      depth: 2,
      source: 'discovery'
    })
  );
});
```

**Step 2: Run test to verify it fails**

Run: `npm test author-warming-consumer.test.js`

Expected: `FAIL - send not called with Terry Pratchett`

**Step 3: Implement co-author discovery**

Modify `src/consumers/author-warming-consumer.js`:

```javascript
export async function processAuthorBatch(batch, env, ctx) {
  const kvCache = new KVCacheService(env);

  for (const message of batch.messages) {
    try {
      const { author, depth, source, jobId } = message.body;

      // ... existing code (deduplication, search, cache) ...

      // 4. Discover co-authors (if depth < maxDepth)
      const jobMetadata = await env.CACHE.get(`warming:job:${jobId}`, 'json');
      const maxDepth = jobMetadata?.maxDepth || 2;

      if (depth < maxDepth) {
        const coAuthors = extractCoAuthors(works, author);

        for (const coAuthor of coAuthors) {
          // Check if co-author already processed
          const alreadyProcessed = await env.CACHE.get(`warming:processed:${coAuthor}`);
          if (!alreadyProcessed) {
            await env.AUTHOR_WARMING_QUEUE.send({
              author: coAuthor,
              source: 'discovery',
              depth: depth + 1,
              queuedAt: new Date().toISOString(),
              jobId: jobId
            });
          }
        }
      }

      // 5. Mark as processed (keep existing) ...

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);
      message.retry();
    }
  }
}

/**
 * Extract co-authors from works, excluding the primary author
 * @param {Array} works - Array of works
 * @param {string} primaryAuthor - Author to exclude
 * @returns {Array<string>} Unique co-author names
 */
function extractCoAuthors(works, primaryAuthor) {
  const coAuthorsSet = new Set();

  for (const work of works) {
    if (!work.author) continue;

    // Split by common delimiters
    const authors = work.author.split(/[,&]/).map(a => a.trim());

    for (const author of authors) {
      if (author && author !== primaryAuthor) {
        coAuthorsSet.add(author);
      }
    }
  }

  return Array.from(coAuthorsSet);
}
```

**Step 4: Run test to verify it passes**

Run: `npm test author-warming-consumer.test.js`

Expected: `PASS (4 tests)`

**Step 5: Commit**

```bash
git add src/consumers/author-warming-consumer.js tests/author-warming-consumer.test.js
git commit -m "feat(cache): discover and queue co-authors"
```

---

## Task 8: Wire Queue Consumer to Worker

**Files:**
- Modify: `cloudflare-workers/api-worker/src/index.js:1-13`
- Modify: `cloudflare-workers/api-worker/wrangler.toml:126-134`

**Step 1: Update wrangler.toml with consumer handler**

Modify `wrangler.toml`:

```toml
[[queues.consumers]]
queue = "author-warming-queue"
max_batch_size = 10
max_batch_timeout = 30
max_retries = 3
dead_letter_queue = "author-warming-dlq"
max_concurrency = 5  # Process 5 batches in parallel
```

**Step 2: Add queue handler to index.js**

Modify `src/index.js` (add after imports):

```javascript
import { processAuthorBatch } from './consumers/author-warming-consumer.js';

export default {
  async fetch(request, env, ctx) {
    // ... existing HTTP routing ...
  },

  async queue(batch, env, ctx) {
    // Route queue messages to appropriate consumer
    if (batch.queue === 'author-warming-queue') {
      await processAuthorBatch(batch, env, ctx);
    } else {
      console.error(`Unknown queue: ${batch.queue}`);
    }
  }
};
```

**Step 3: Add warming upload route**

Add to `src/index.js` before the final catch-all:

```javascript
import { handleWarmingUpload } from './handlers/warming-upload.js';

// POST /api/warming/upload - Cache warming via CSV
if (url.pathname === '/api/warming/upload' && request.method === 'POST') {
  return handleWarmingUpload(request, env, ctx);
}
```

**Step 4: Deploy and test**

Run: `npx wrangler deploy`

Expected: `✓ Uploaded api-worker (X.XX sec)` with queue consumer registered

**Step 5: Smoke test**

Run:
```bash
curl -X POST https://api-worker.YOUR-DOMAIN.workers.dev/api/warming/upload \
  -H "Content-Type: application/json" \
  -d '{"csv":"dGl0bGUsYXV0aG9yLGlzYm4KQm9vazEsQXV0aG9yIEEsMTIz","maxDepth":1}'
```

Expected: `{"jobId":"uuid","authorsQueued":1,...}`

**Step 6: Commit**

```bash
git add src/index.js wrangler.toml
git commit -m "feat(cache): wire queue consumer to worker"
```

---

## Task 9: Monitoring & Observability

**Files:**
- Create: `cloudflare-workers/api-worker/src/utils/warming-metrics.js`
- Modify: `cloudflare-workers/api-worker/src/consumers/author-warming-consumer.js`

**Step 1: Create metrics logger**

Create `src/utils/warming-metrics.js`:

```javascript
/**
 * Log cache warming metrics to Analytics Engine
 *
 * @param {Object} env - Worker environment with CACHE_ANALYTICS binding
 * @param {string} event - Event type (author_processed, works_cached, etc.)
 * @param {Object} data - Event data
 */
export function logWarmingMetric(env, event, data) {
  if (!env.CACHE_ANALYTICS) return;

  try {
    env.CACHE_ANALYTICS.writeDataPoint({
      blobs: [event, data.author || ''],
      doubles: [data.worksCount || 0, data.depth || 0, data.duration || 0],
      indexes: [event]
    });
  } catch (error) {
    console.error('Failed to log warming metric:', error);
  }
}
```

**Step 2: Integrate metrics in consumer**

Modify `src/consumers/author-warming-consumer.js`:

```javascript
import { logWarmingMetric } from '../utils/warming-metrics.js';

export async function processAuthorBatch(batch, env, ctx) {
  const kvCache = new KVCacheService(env);

  for (const message of batch.messages) {
    const startTime = Date.now();

    try {
      const { author, depth, source, jobId } = message.body;

      // ... existing processing logic ...

      // Log success metric
      logWarmingMetric(env, 'author_processed', {
        author: author,
        worksCount: works.length,
        depth: depth,
        duration: Date.now() - startTime
      });

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);

      // Log error metric
      logWarmingMetric(env, 'author_failed', {
        author: message.body.author,
        depth: message.body.depth,
        duration: Date.now() - startTime
      });

      message.retry();
    }
  }
}
```

**Step 3: Query metrics (manual verification)**

Run:
```bash
npx wrangler tail api-worker --format pretty
# Trigger warming job and watch for Analytics Engine writes
```

Expected: Log entries like `CACHE_ANALYTICS.writeDataPoint({ blobs: ['author_processed', ...] })`

**Step 4: Commit**

```bash
git add src/utils/warming-metrics.js src/consumers/author-warming-consumer.js
git commit -m "feat(cache): add warming metrics to Analytics Engine"
```

---

## Task 10: Dead Letter Queue Monitoring

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/dlq-monitor.js`

**Step 1: Create DLQ monitoring endpoint**

Create `src/handlers/dlq-monitor.js`:

```javascript
/**
 * GET /api/warming/dlq - Check dead letter queue depth
 *
 * @param {Request} request
 * @param {Object} env
 * @returns {Response} DLQ status
 */
export async function handleDLQMonitor(request, env) {
  try {
    // Query DLQ depth via Wrangler API (requires auth)
    // For now, return placeholder
    return new Response(JSON.stringify({
      queue: 'author-warming-dlq',
      depth: 0,
      warning: 'DLQ monitoring requires Wrangler API integration'
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to check DLQ',
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
import { handleDLQMonitor } from './handlers/dlq-monitor.js';

// GET /api/warming/dlq - Monitor dead letter queue
if (url.pathname === '/api/warming/dlq' && request.method === 'GET') {
  return handleDLQMonitor(request, env);
}
```

**Step 3: Commit**

```bash
git add src/handlers/dlq-monitor.js src/index.js
git commit -m "feat(cache): add DLQ monitoring endpoint"
```

---

## Task 11: Integration Testing

**Files:**
- Create: `cloudflare-workers/api-worker/tests/integration/warming-flow.test.js`

**Step 1: Write end-to-end test**

Create `tests/integration/warming-flow.test.js`:

```javascript
import { describe, it, expect, beforeAll } from 'vitest';

describe('Cache Warming Flow (E2E)', () => {
  let env;

  beforeAll(async () => {
    // Use Miniflare or real dev environment
    env = await setupTestEnvironment();
  });

  it('should complete full warming cycle', async () => {
    // 1. Upload CSV
    const uploadResponse = await fetch('http://localhost:8787/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({
        csv: btoa('title,author,isbn\nBook1,Test Author,123'),
        maxDepth: 1
      })
    });

    expect(uploadResponse.status).toBe(202);
    const { jobId } = await uploadResponse.json();

    // 2. Wait for queue processing (simulate)
    await new Promise(resolve => setTimeout(resolve, 5000));

    // 3. Verify author was processed
    const processed = await env.CACHE.get('warming:processed:Test Author');
    expect(processed).toBeTruthy();

    const data = JSON.parse(processed);
    expect(data.worksCount).toBeGreaterThan(0);
  }, 10000); // 10s timeout
});
```

**Step 2: Run integration test**

Run: `npm test integration/warming-flow.test.js`

Expected: `PASS` (or identify integration issues)

**Step 3: Commit**

```bash
git add tests/integration/warming-flow.test.js
git commit -m "test(cache): add E2E warming flow test"
```

---

## Task 12: Documentation

**Files:**
- Create: `cloudflare-workers/api-worker/docs/CACHE_WARMING.md`

**Step 1: Write usage documentation**

Create `docs/CACHE_WARMING.md`:

```markdown
# Cache Warming - Phase 2

## Overview

Intelligent cache warming system that seeds from CSV files and auto-discovers related content via Cloudflare Queues.

## API Endpoint

**POST /api/warming/upload**

Request:
\`\`\`json
{
  "csv": "base64-encoded CSV file",
  "maxDepth": 2,
  "priority": "normal"
}
\`\`\`

Response:
\`\`\`json
{
  "jobId": "uuid",
  "authorsQueued": 350,
  "estimatedWorks": 5250,
  "estimatedDuration": "2-4 hours"
}
\`\`\`

## Architecture

1. CSV Upload → Gemini Parse → Extract authors
2. Queue each author to `author-warming-queue`
3. Consumer workers process 10 authors/batch
4. Search external APIs → Cache works
5. Discover co-authors → Queue for next depth level

## Monitoring

- **Metrics:** `CACHE_ANALYTICS` dataset
- **DLQ:** Check `/api/warming/dlq` endpoint
- **Queue depth:** Use `wrangler queues list`

## Cost Estimates

- **Queues:** Free (< 1M ops/month)
- **KV writes:** ~$0.003 per 500-book CSV
- **Total:** ~$0.10/month

## Troubleshooting

**Queue not processing:**
1. Check `wrangler tail api-worker` for errors
2. Verify queue binding in `wrangler.toml`
3. Check DLQ depth: `wrangler queues consumer list author-warming-dlq`

**Authors skipped:**
- Check `warming:processed:{author}` KV keys
- Deduplication prevents re-processing within 90 days
```

**Step 2: Commit**

```bash
git add docs/CACHE_WARMING.md
git commit -m "docs(cache): add cache warming usage guide"
```

---

## Verification Checklist

Before considering Phase 2 complete, verify:

- [ ] `npx wrangler deploy` succeeds with queue consumer
- [ ] Upload CSV via curl returns `202 Accepted` with jobId
- [ ] `npx wrangler tail` shows author processing logs
- [ ] `warming:processed:{author}` keys appear in KV
- [ ] Analytics Engine shows `author_processed` events
- [ ] Co-authors are queued at depth+1
- [ ] All tests pass: `npm test`
- [ ] DLQ depth remains 0 (no failures)

---

## Next Steps

After Phase 2 deployment:

1. **Phase 3:** R2 Cold Storage (archival tier)
2. **Phase 4:** Monitoring & Optimization (A/B testing)
3. **Enhancement:** Genre-based discovery
4. **Enhancement:** Priority queue for popular authors
