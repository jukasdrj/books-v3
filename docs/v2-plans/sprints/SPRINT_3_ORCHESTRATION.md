# Sprint 3: Orchestration - Cloudflare Workflows Migration

**Status:** Planned
**Duration:** 10 working days (2 weeks)
**Sprint Goal:** Replace custom JobStateManagerDO state management with native Cloudflare Workflows API

---

## Executive Summary

**Key Transformation:** Migrate from manual state machine orchestration to Cloudflare's native Workflows API for reliability, simplicity, and automatic state persistence.

**What We're Building:**
1. Book import workflow with 4 steps (metadata → cover → embeddings → database)
2. WebSocket event bridge for real-time progress updates
3. Simplified JobStateManagerDO (60% code reduction)

**Critical Innovation:** D1 dependency eliminated via KV fallback pattern - Sprint 3 can proceed independently of Phase 2 completion.

---

## Architecture Overview

```
BEFORE (Custom State Machine)        AFTER (Cloudflare Workflows)
==============================        ===========================

┌──────────────────────┐             ┌──────────────────────┐
│  JobStateManagerDO   │             │ Cloudflare Workflows │
│                      │             │    (Native API)      │
│  - Manual state      │             │                      │
│  - Retry logic       │────────>    │  - Auto state mgmt   │
│  - Step orchestration│             │  - Built-in retries  │
│  - Error recovery    │             │  - Step coordination │
│  - Timeouts          │             │  - Auto recovery     │
│                      │             │                      │
│  ~1000 LOC          │             │  ~400 LOC (60% ↓)   │
└──────────────────────┘             └──────────────────────┘
         |                                     |
         v                                     v
┌──────────────────────┐             ┌──────────────────────┐
│  Manual State Mgmt   │             │  WebSocket Event     │
│  (Complex Logic)     │             │  Bridge (Clean)      │
└──────────────────────┘             └──────────────────────┘
```

**Migration Strategy:** Parallel deployment with feature flags (10% → 50% → 100% rollout)

---

## Phase 3.1: Book Import Workflow Definition

**Goal:** Create native Cloudflare Workflow for book import orchestration with automatic state management

### Task 3.1.1: Provision Workflows Binding

**Configuration (`wrangler.jsonc`):**
```jsonc
{
  "workflows": [
    {
      "name": "book-import-workflow",
      "binding": "BOOK_IMPORT_WORKFLOW",
      "class_name": "BookImportWorkflow"
    }
  ]
}
```

**Provisioning Command:**
```bash
npx wrangler workflows create book-import-workflow
npx wrangler workflows list  # Verify creation
```

---

### Task 3.1.2: Create Workflow Definition

**File:** `src/workflows/import-book.ts` (NEW)

```typescript
import { WorkflowEntrypoint, WorkflowStep, WorkflowEvent } from 'cloudflare:workers'

export interface BookImportInput {
  isbn: string
  jobId: string
  userId?: string
  source: 'google_books' | 'isbndb' | 'openlibrary'
}

export interface BookMetadata {
  isbn: string
  title: string
  author: string
  description?: string
  coverUrl?: string
  publicationDate?: string
}

export class BookImportWorkflow extends WorkflowEntrypoint<Env, BookImportInput> {
  async run(event: WorkflowEvent<BookImportInput>, step: WorkflowStep) {
    const { isbn, jobId, source } = event.payload

    // Emit start event to WebSocket clients
    await this.emitProgress(jobId, 'started', { isbn }, step)

    // Step 1: Fetch book metadata (Linear retry: 3 attempts, 1s/2s/3s)
    const metadata = await step.do('fetch-metadata', {
      retries: {
        limit: 3,
        delay: 1000,
        backoff: 'linear'
      }
    }, async () => {
      return await this.fetchMetadata(isbn, source)
    })

    await this.emitProgress(jobId, 'metadata_fetched', { metadata }, step)

    // Step 2: Upload cover image to R2 (Exponential retry: 5 attempts)
    let coverR2Key: string | null = null
    if (metadata.coverUrl) {
      coverR2Key = await step.do('upload-cover', {
        retries: {
          limit: 5,
          delay: 500,
          backoff: 'exponential'
        }
      }, async () => {
        return await this.uploadCoverToR2(metadata.coverUrl!, isbn)
      })

      await this.emitProgress(jobId, 'cover_uploaded', { coverR2Key }, step)
    }

    // Step 3: Generate vector embeddings (Optional - Phase 4 dependency)
    let embedding: number[] | null = null
    if (this.env.AI) {
      try {
        embedding = await step.do('generate-embedding', {
          retries: {
            limit: 2,
            delay: 2000,
            backoff: 'linear'
          }
        }, async () => {
          return await this.generateEmbedding(metadata)
        })

        await this.emitProgress(jobId, 'embedding_generated', { dimensions: embedding.length }, step)
      } catch (error) {
        // Non-critical: Continue without embeddings
        console.warn('Embedding generation failed (optional):', error)
      }
    }

    // Step 4: Save to D1 (with KV fallback)
    const saved = await step.do('save-to-database', {
      retries: {
        limit: 3,
        delay: 1000,
        backoff: 'exponential'
      }
    }, async () => {
      return await this.saveBookData(metadata, coverR2Key, embedding)
    })

    await this.emitProgress(jobId, 'completed', { isbn, saved }, step)

    return {
      success: true,
      isbn,
      metadata,
      coverR2Key,
      hasEmbedding: !!embedding
    }
  }

  // Helper: Emit progress to WebSocket clients
  private async emitProgress(
    jobId: string,
    status: string,
    data: any,
    step: WorkflowStep
  ) {
    const doId = this.env.WEBSOCKET_DO.idFromName(jobId)
    const stub = this.env.WEBSOCKET_DO.get(doId)

    await step.do(`emit-${status}`, async () => {
      await stub.broadcastProgress({
        jobId,
        status,
        timestamp: new Date().toISOString(),
        data
      })
    })
  }

  // Step 1 Implementation: Fetch metadata
  private async fetchMetadata(
    isbn: string,
    source: BookImportInput['source']
  ): Promise<BookMetadata> {
    switch (source) {
      case 'google_books':
        return await this.fetchFromGoogleBooks(isbn)
      case 'isbndb':
        return await this.fetchFromISBNdb(isbn)
      case 'openlibrary':
        return await this.fetchFromOpenLibrary(isbn)
      default:
        throw new Error(`Unknown source: ${source}`)
    }
  }

  private async fetchFromGoogleBooks(isbn: string): Promise<BookMetadata> {
    const url = `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`
    const response = await fetch(url, {
      headers: {
        'X-goog-api-key': this.env.GOOGLE_BOOKS_API_KEY
      }
    })

    if (!response.ok) {
      throw new Error(`Google Books API failed: ${response.status}`)
    }

    const data = await response.json()
    if (!data.items || data.items.length === 0) {
      throw new Error(`No book found for ISBN: ${isbn}`)
    }

    const book = data.items[0].volumeInfo
    return {
      isbn,
      title: book.title,
      author: book.authors?.[0] || 'Unknown',
      description: book.description,
      coverUrl: book.imageLinks?.thumbnail,
      publicationDate: book.publishedDate
    }
  }

  private async fetchFromISBNdb(isbn: string): Promise<BookMetadata> {
    // TODO: Implement ISBNdb integration
    throw new Error('ISBNdb not implemented yet')
  }

  private async fetchFromOpenLibrary(isbn: string): Promise<BookMetadata> {
    // TODO: Implement OpenLibrary integration
    throw new Error('OpenLibrary not implemented yet')
  }

  // Step 2 Implementation: Upload cover to R2
  private async uploadCoverToR2(coverUrl: string, isbn: string): Promise<string> {
    const response = await fetch(coverUrl)
    if (!response.ok) {
      throw new Error(`Failed to fetch cover: ${response.status}`)
    }

    const imageBuffer = await response.arrayBuffer()
    const r2Key = `covers/${isbn}.jpg`

    await this.env.R2_BUCKET.put(r2Key, imageBuffer, {
      httpMetadata: {
        contentType: 'image/jpeg'
      }
    })

    return r2Key
  }

  // Step 3 Implementation: Generate embeddings (Phase 4 dependency)
  private async generateEmbedding(metadata: BookMetadata): Promise<number[]> {
    const text = `${metadata.title} by ${metadata.author}. ${metadata.description || ''}`
      .substring(0, 512)

    const response = await this.env.AI.run('@cf/baai/bge-m3', {
      text: [text]
    })

    return Array.from(response.data[0])
  }

  // Step 4 Implementation: Save to D1 (with KV fallback)
  private async saveBookData(
    metadata: BookMetadata,
    coverR2Key: string | null,
    embedding: number[] | null
  ): Promise<boolean> {
    if (this.env.DB) {
      // D1 available - use relational storage
      await this.env.DB.prepare(`
        INSERT INTO books (isbn, title, author, description, cover_r2_key, publication_date)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(isbn) DO UPDATE SET
          title = excluded.title,
          author = excluded.author,
          description = excluded.description,
          cover_r2_key = excluded.cover_r2_key,
          publication_date = excluded.publication_date
      `)
        .bind(
          metadata.isbn,
          metadata.title,
          metadata.author,
          metadata.description || null,
          coverR2Key,
          metadata.publicationDate || null
        )
        .run()

      // If embeddings exist, store in Vectorize
      if (embedding && this.env.BOOK_VECTORS) {
        await this.env.BOOK_VECTORS.insert([{
          id: metadata.isbn,
          values: embedding
        }])
      }

      return true
    } else {
      // D1 not ready - fallback to KV
      console.warn('D1 not available, falling back to KV storage')
      await this.env.BOOK_CACHE.put(
        `book:isbn:${metadata.isbn}`,
        JSON.stringify({ ...metadata, coverR2Key }),
        { expirationTtl: 86400 * 30 }
      )

      return true
    }
  }
}
```

**Key Design Decisions:**
- Each step has independent retry policy (linear for API calls, exponential for uploads)
- Step 3 (embeddings) is optional - continues without failure
- Step 4 has D1 fallback to KV (removes Phase 2 dependency)
- All progress events wrapped in `step.do()` for durability

---

### Task 3.1.3: Create Workflow Trigger Handler

**File:** `src/handlers/workflow-trigger-handler.ts` (NEW)

```typescript
import { createSuccessResponse, createErrorResponse } from '../utils/response-builder.js'
import { BookImportInput } from '../workflows/import-book.js'

export async function triggerBookImportWorkflow(request: Request, env: Env) {
  try {
    const { isbn, source = 'google_books', userId } = await request.json()

    if (!isbn || !/^\d{10,13}$/.test(isbn)) {
      return createErrorResponse(
        'INVALID_ISBN',
        'ISBN must be 10 or 13 digits',
        { statusCode: 400 }
      )
    }

    // Generate unique job ID
    const jobId = `import-${isbn}-${Date.now()}`

    // Create Workflow instance
    const instance = await env.BOOK_IMPORT_WORKFLOW.create({
      params: {
        isbn,
        jobId,
        userId,
        source
      } as BookImportInput
    })

    return createSuccessResponse({
      jobId,
      workflowId: instance.id,
      isbn,
      status: 'started'
    })

  } catch (error) {
    console.error('Workflow trigger failed:', error)
    return createErrorResponse(
      'WORKFLOW_FAILED',
      'Failed to start book import workflow',
      { statusCode: 500 }
    )
  }
}
```

---

### Task 3.1.4: Add Route to Hono Router

**File:** `src/router.ts` (MODIFIED)

```typescript
import { triggerBookImportWorkflow } from './handlers/workflow-trigger-handler.js'

// Add workflow trigger endpoint
router.post('/v2/import/workflow', rateLimitMiddleware, async (c) => {
  return triggerBookImportWorkflow(c.req.raw, c.env)
})
```

---

### Validation Checklist (Phase 3.1)

- [ ] Workflow definition compiles without TypeScript errors
- [ ] Workflow instance created successfully via API
- [ ] Step 1 (fetch metadata) retries on failure (test with invalid ISBN)
- [ ] Step 2 (upload cover) uses exponential backoff
- [ ] Step 3 (embeddings) gracefully skips if Workers AI unavailable
- [ ] Step 4 (save to D1) falls back to KV if D1 not ready
- [ ] Workflow survives Worker restart (trigger restart mid-execution)
- [ ] State size < 128 KB for typical book metadata

**Files Created:**
- `src/workflows/import-book.ts`
- `src/handlers/workflow-trigger-handler.ts`
- `src/router.ts` (MODIFIED - add workflow route)
- `wrangler.jsonc` (MODIFIED - add Workflows binding)

---

## Phase 3.2: WebSocket Event Bridge Implementation

**Goal:** Wire Workflow progress events to WebSocket clients for real-time UI updates

### Architecture: Event Flow

```
Workflow Step Complete
    |
    v
[emitProgress()] → WorkflowStep.do()
    |
    v
[WebSocketConnectionDO.broadcastProgress()]
    |
    v
[Active WebSocket Connections]
    |
    v
Client receives progress update
```

**Key Principle:** Workflows NEVER hold WebSocket connections directly. Events flow through WebSocketConnectionDO as a message broker.

---

### Task 3.2.1: Update WebSocketConnectionDO

**File:** `src/durable-objects/WebSocketConnectionDO.ts` (MODIFIED)

Add new method for Workflow event broadcasting:

```typescript
export class WebSocketConnectionDO extends DurableObject {
  private connections: Map<WebSocket, { userId?: string, jobId?: string }>

  constructor(state: DurableObjectState, env: Env) {
    super(state, env)
    this.connections = new Map()
  }

  // Existing WebSocket handling...
  async fetch(request: Request): Promise<Response> {
    // WebSocket upgrade logic (already implemented)
    // ...
  }

  // NEW: Broadcast progress from Workflow
  async broadcastProgress(event: WorkflowProgressEvent): Promise<void> {
    const { jobId, status, timestamp, data } = event

    const message = JSON.stringify({
      type: 'workflow_progress',
      jobId,
      status,
      timestamp,
      data
    })

    // Broadcast to all connections interested in this jobId
    for (const [ws, meta] of this.connections) {
      if (meta.jobId === jobId && ws.readyState === WebSocket.READY_STATE_OPEN) {
        try {
          ws.send(message)
        } catch (error) {
          console.error('Failed to send workflow progress:', error)
          this.connections.delete(ws)
        }
      }
    }

    // Store last event in DO storage (for late-joining clients)
    await this.state.storage.put(`workflow:${jobId}:latest`, event)
  }

  // NEW: Get latest workflow status
  async getLatestStatus(jobId: string): Promise<WorkflowProgressEvent | null> {
    return await this.state.storage.get(`workflow:${jobId}:latest`)
  }
}

export interface WorkflowProgressEvent {
  jobId: string
  status: 'started' | 'metadata_fetched' | 'cover_uploaded' | 'embedding_generated' | 'completed' | 'failed'
  timestamp: string
  data: any
}
```

---

### Task 3.2.2: Add Workflow Event Types

**File:** `src/types/workflow-events.ts` (NEW)

```typescript
export type WorkflowStatus =
  | 'started'
  | 'metadata_fetched'
  | 'cover_uploaded'
  | 'embedding_generated'
  | 'completed'
  | 'failed'

export interface WorkflowProgressEvent {
  jobId: string
  status: WorkflowStatus
  timestamp: string
  data: {
    isbn?: string
    metadata?: BookMetadata
    coverR2Key?: string
    dimensions?: number
    error?: string
  }
}

export interface WorkflowClientMessage {
  type: 'workflow_progress'
  jobId: string
  status: WorkflowStatus
  timestamp: string
  data: any
}
```

---

### Task 3.2.3: Add Status Endpoint

**File:** `src/handlers/workflow-status-handler.ts` (NEW)

```typescript
import { createSuccessResponse, createErrorResponse } from '../utils/response-builder.js'

export async function getWorkflowStatus(request: Request, env: Env) {
  try {
    const url = new URL(request.url)
    const jobId = url.pathname.split('/').pop()

    if (!jobId) {
      return createErrorResponse('MISSING_JOB_ID', 'Job ID required', { statusCode: 400 })
    }

    // Query WebSocketConnectionDO for latest status
    const doId = env.WEBSOCKET_DO.idFromName(jobId)
    const stub = env.WEBSOCKET_DO.get(doId)
    const latestEvent = await stub.getLatestStatus(jobId)

    if (!latestEvent) {
      return createErrorResponse('JOB_NOT_FOUND', 'No status found for job', { statusCode: 404 })
    }

    return createSuccessResponse({
      jobId,
      status: latestEvent.status,
      lastUpdated: latestEvent.timestamp,
      data: latestEvent.data
    })

  } catch (error) {
    console.error('Status fetch failed:', error)
    return createErrorResponse('STATUS_FAILED', 'Failed to get workflow status', { statusCode: 500 })
  }
}
```

**Add route to `src/router.ts`:**
```typescript
import { getWorkflowStatus } from './handlers/workflow-status-handler.js'

router.get('/v2/import/status/:jobId', async (c) => {
  return getWorkflowStatus(c.req.raw, c.env)
})
```

---

### Task 3.2.4: Client-Side Event Handling

**File:** `docs/WORKFLOW_CLIENT_INTEGRATION.md` (NEW - Frontend documentation)

```markdown
# Workflow Progress WebSocket Integration

## Connecting to Workflow Progress

1. **Trigger Workflow:**
```javascript
const response = await fetch('/v2/import/workflow', {
  method: 'POST',
  body: JSON.stringify({ isbn: '9780451524935', source: 'google_books' }),
  headers: { 'Content-Type': 'application/json' }
})

const { jobId, workflowId } = await response.json()
```

2. **Connect WebSocket:**
```javascript
const ws = new WebSocket(`wss://api.oooefam.net/ws/progress?jobId=${jobId}`)

ws.onmessage = (event) => {
  const message = JSON.parse(event.data)

  switch (message.status) {
    case 'started':
      console.log('Import started:', message.data.isbn)
      break
    case 'metadata_fetched':
      console.log('Metadata:', message.data.metadata)
      break
    case 'cover_uploaded':
      console.log('Cover URL:', message.data.coverR2Key)
      break
    case 'embedding_generated':
      console.log('Embeddings:', message.data.dimensions, 'dimensions')
      break
    case 'completed':
      console.log('Import complete!')
      ws.close()
      break
    case 'failed':
      console.error('Import failed:', message.data.error)
      ws.close()
      break
  }
}
```

3. **Handle Reconnection:**
If client disconnects and reconnects, fetch latest status:

```javascript
const latestStatus = await fetch(`/v2/import/status/${jobId}`)
const { status, lastEvent } = await latestStatus.json()
```
```

---

### Validation Checklist (Phase 3.2)

- [ ] Workflow events delivered to WebSocket clients <100ms
- [ ] Late-joining clients receive latest status via `/status` endpoint
- [ ] Events persist in DO storage for reconnection scenarios
- [ ] Dead WebSocket connections cleaned up automatically
- [ ] Multiple clients can subscribe to same jobId
- [ ] Event order preserved (started → metadata_fetched → ... → completed)

**Files Created/Modified:**
- `src/durable-objects/WebSocketConnectionDO.ts` (MODIFIED - add broadcastProgress)
- `src/types/workflow-events.ts` (NEW)
- `src/workflows/import-book.ts` (MODIFIED - use event bridge)
- `src/handlers/workflow-status-handler.ts` (NEW)
- `src/router.ts` (MODIFIED - add status route)
- `docs/WORKFLOW_CLIENT_INTEGRATION.md` (NEW - frontend docs)

---

## Phase 3.3: JobStateManagerDO Simplification

**Goal:** Remove 60% of code by eliminating manual state management logic

### Current JobStateManagerDO Analysis

**Existing Responsibilities (TO BE REMOVED):**
1. Manual state machine (pending → running → completed)
2. Retry logic for failed steps
3. Step orchestration (Step 1 → Step 2 → Step 3 → Step 4)
4. Error handling and recovery
5. Timeout management
6. State persistence across hibernation

**New Responsibilities (TO BE KEPT):**
1. Simple message forwarding to WebSocket clients
2. Legacy API compatibility (during migration)

**Code Reduction Target:** ~1000 LOC → ~400 LOC (60% reduction)

---

### Task 3.3.1: Create Simplified JobStateManagerDO

**File:** `src/durable-objects/JobStateManagerDO.ts` (MAJOR REFACTOR)

**Before (Complex State Machine):**
```typescript
// BEFORE: ~1000 lines of manual state management
export class JobStateManagerDO extends DurableObject {
  private state: JobState = 'pending'
  private currentStep: number = 0
  private retryCount: Map<number, number> = new Map()

  async processStep(step: number) {
    // Manual retry logic
    const maxRetries = this.getMaxRetries(step)
    if (this.retryCount.get(step) >= maxRetries) {
      this.state = 'failed'
      return
    }

    try {
      switch (step) {
        case 1: await this.fetchMetadata(); break
        case 2: await this.uploadCover(); break
        case 3: await this.generateEmbedding(); break
        case 4: await this.saveToDatabase(); break
      }
      this.currentStep++
    } catch (error) {
      this.retryCount.set(step, (this.retryCount.get(step) || 0) + 1)
      await this.scheduleRetry(step)
    }
  }

  // ... 900+ more lines of orchestration logic
}
```

**After (Simple Message Passer):**
```typescript
// AFTER: ~400 lines - just message forwarding
export class JobStateManagerDO extends DurableObject {
  private workflowId: string | null = null

  // Trigger workflow and store reference
  async startImport(isbn: string, source: string): Promise<string> {
    const jobId = `import-${isbn}-${Date.now()}`

    // Create Workflow instance
    const instance = await this.env.BOOK_IMPORT_WORKFLOW.create({
      params: { isbn, jobId, source }
    })

    this.workflowId = instance.id
    await this.state.storage.put('workflowId', instance.id)

    return jobId
  }

  // Get status from Workflow (not stored locally)
  async getStatus(jobId: string): Promise<WorkflowStatus> {
    const doId = this.env.WEBSOCKET_DO.idFromName(jobId)
    const stub = this.env.WEBSOCKET_DO.get(doId)
    return await stub.getLatestStatus(jobId)
  }

  // Legacy API compatibility (temporary)
  async handleLegacyRequest(request: Request): Promise<Response> {
    const { action } = await request.json()

    switch (action) {
      case 'start':
        const jobId = await this.startImport(...)
        return new Response(JSON.stringify({ jobId }))

      case 'status':
        const status = await this.getStatus(...)
        return new Response(JSON.stringify({ status }))

      default:
        return new Response('Unknown action', { status: 400 })
    }
  }
}
```

**Lines of Code Reduction:**
- Before: ~1000 LOC (state machine + orchestration)
- After: ~400 LOC (simple forwarding)
- Reduction: 60%

---

### Task 3.3.2: Migration Strategy - Feature Flag

**File:** `src/utils/feature-flags.ts` (NEW)

```typescript
export function shouldUseWorkflow(env: Env): boolean {
  const rolloutPercent = parseInt(env.WORKFLOW_ROLLOUT_PERCENT || '0')
  const random = Math.random() * 100
  return random < rolloutPercent
}

export function getImportMethod(env: Env): 'workflow' | 'legacy' {
  return shouldUseWorkflow(env) ? 'workflow' : 'legacy'
}
```

**Configuration (`wrangler.jsonc`):**
```jsonc
{
  "vars": {
    "WORKFLOW_ROLLOUT_PERCENT": "10"
  }
}
```

---

### Task 3.3.3: Unified Import Handler

**File:** `src/handlers/import-handler.ts` (MODIFIED)

```typescript
import { triggerBookImportWorkflow } from './workflow-trigger-handler.js'
import { getImportMethod } from '../utils/feature-flags.js'

export async function handleBookImport(request: Request, env: Env) {
  const method = getImportMethod(env)

  if (method === 'workflow') {
    return await triggerBookImportWorkflow(request, env)
  } else {
    return await handleLegacyImport(request, env)
  }
}

async function handleLegacyImport(request: Request, env: Env) {
  const doId = env.JOB_STATE_MANAGER.newUniqueId()
  const stub = env.JOB_STATE_MANAGER.get(doId)
  return await stub.fetch(request)
}
```

**Update route in `src/router.ts`:**
```typescript
import { handleBookImport } from './handlers/import-handler.js'

router.post('/v2/import', rateLimitMiddleware, async (c) => {
  return handleBookImport(c.req.raw, c.env)
})
```

---

### Task 3.3.4: Monitoring & Comparison

**File:** `src/utils/workflow-metrics.ts` (NEW)

```typescript
export async function logWorkflowMetrics(
  method: 'workflow' | 'legacy',
  isbn: string,
  duration: number,
  success: boolean,
  env: Env
) {
  const metric = {
    method,
    isbn,
    duration,
    success,
    timestamp: new Date().toISOString()
  }

  await env.METRICS_KV?.put(
    `import-metrics:${isbn}:${Date.now()}`,
    JSON.stringify(metric),
    { expirationTtl: 86400 * 7 }
  )

  console.log('Import metrics:', metric)
}
```

---

### Validation Checklist (Phase 3.3)

- [ ] JobStateManagerDO code reduced from ~1000 → ~400 LOC
- [ ] Feature flag controls rollout (10% → 50% → 100%)
- [ ] Both systems (Workflow + legacy) run in parallel
- [ ] Metrics collected for A/B comparison
- [ ] No regression in import success rate
- [ ] Workflow imports complete faster (measure P95 latency)

**Deprecation Timeline:**
- Week 1 Day 1-3: Deploy with 10% Workflow rollout
- Week 1 Day 4-5: Increase to 50% if no issues
- Week 2 Day 1-3: Increase to 100%
- Week 2 Day 4-5: Remove JobStateManagerDO code entirely

**Files Created/Modified:**
- `src/durable-objects/JobStateManagerDO.ts` (MAJOR REFACTOR - 60% reduction)
- `src/utils/feature-flags.ts` (NEW)
- `src/handlers/import-handler.ts` (MODIFIED - unified entry point)
- `src/utils/workflow-metrics.ts` (NEW)
- `src/router.ts` (MODIFIED - route to unified handler)
- `wrangler.jsonc` (MODIFIED - add WORKFLOW_ROLLOUT_PERCENT)

---

## Testing Strategy

### Phase 3.1 Testing (Workflow Definition)

**Unit Tests:**
**File:** `test/workflows/import-book.test.ts` (NEW)

```typescript
import { describe, it, expect, vi } from 'vitest'
import { BookImportWorkflow } from '../../src/workflows/import-book.js'

describe('BookImportWorkflow', () => {
  it('should complete all 4 steps successfully', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      R2_BUCKET: {
        put: vi.fn().mockResolvedValue(undefined)
      },
      DB: {
        prepare: vi.fn().mockReturnValue({
          bind: vi.fn().mockReturnValue({
            run: vi.fn().mockResolvedValue({ success: true })
          })
        })
      },
      WEBSOCKET_DO: {
        idFromName: vi.fn(),
        get: vi.fn().mockReturnValue({
          broadcastProgress: vi.fn().mockResolvedValue(undefined)
        })
      }
    }

    const workflow = new BookImportWorkflow(mockEnv)
    const result = await workflow.run({
      payload: {
        isbn: '9780451524935',
        jobId: 'test-job-123',
        source: 'google_books'
      }
    }, mockStep)

    expect(result.success).toBe(true)
    expect(result.isbn).toBe('9780451524935')
  })

  it('should fall back to KV if D1 not available', async () => {
    const mockEnvNoD1 = {
      DB: null,
      BOOK_CACHE: {
        put: vi.fn().mockResolvedValue(undefined)
      }
    }

    const workflow = new BookImportWorkflow(mockEnvNoD1)
    const saved = await workflow.saveBookData(
      { isbn: '123', title: 'Test', author: 'Author' },
      null,
      null
    )

    expect(saved).toBe(true)
    expect(mockEnvNoD1.BOOK_CACHE.put).toHaveBeenCalledWith(
      'book:isbn:123',
      expect.any(String),
      { expirationTtl: 86400 * 30 }
    )
  })
})
```

---

### Phase 3.2 Testing (WebSocket Event Bridge)

**Integration Tests:**
**File:** `test/integration/workflow-websocket.test.ts` (NEW)

```typescript
import { describe, it, expect } from 'vitest'

describe('Workflow WebSocket Integration', () => {
  it('should deliver progress events to connected clients', async () => {
    const ws = new WebSocket(`ws://localhost:8787/ws/progress?jobId=test-123`)
    const messages = []

    ws.onmessage = (event) => {
      messages.push(JSON.parse(event.data))
    }

    await waitForConnection(ws)

    await fetch('http://localhost:8787/v2/import/workflow', {
      method: 'POST',
      body: JSON.stringify({ isbn: '9780451524935', source: 'google_books' })
    })

    await waitFor(() => messages.length >= 5)

    expect(messages[0].status).toBe('started')
    expect(messages[1].status).toBe('metadata_fetched')
    expect(messages[2].status).toBe('cover_uploaded')
    expect(messages[3].status).toBe('embedding_generated')
    expect(messages[4].status).toBe('completed')

    ws.close()
  })
})
```

---

### Phase 3.3 Testing (A/B Comparison)

**File:** `test/migration/workflow-vs-legacy.test.ts` (NEW)

```typescript
import { describe, it, expect } from 'vitest'

describe('Workflow vs Legacy Comparison', () => {
  it('should produce same results for both systems', async () => {
    const isbn = '9780451524935'

    const legacyResult = await fetch('http://localhost:8787/v2/import', {
      method: 'POST',
      body: JSON.stringify({ isbn, method: 'legacy' })
    })
    const legacyData = await legacyResult.json()

    const workflowResult = await fetch('http://localhost:8787/v2/import/workflow', {
      method: 'POST',
      body: JSON.stringify({ isbn })
    })
    const workflowData = await workflowResult.json()

    expect(legacyData.success).toBe(true)
    expect(workflowData.success).toBe(true)
    expect(legacyData.data.isbn).toBe(workflowData.data.isbn)
  })
})
```

---

## Deployment Plan

### Week 1: Infrastructure & Initial Rollout

**Days 1-2: Setup**
1. Add Workflows binding to `wrangler.jsonc`
2. Create Workflow definition
3. Deploy to staging environment
4. Run unit tests
5. GATE: Workflow definition compiles, tests pass

**Days 3-4: 10% Rollout**
1. Set `WORKFLOW_ROLLOUT_PERCENT=10`
2. Deploy to production
3. Monitor completion rate, event latency, error rate
4. GATE: Zero critical errors

**Day 5: 50% Rollout**
1. Set `WORKFLOW_ROLLOUT_PERCENT=50`
2. Deploy update
3. Monitor A/B metrics
4. GATE: Workflow outperforms legacy

---

### Week 2: Full Migration & Cleanup

**Days 1-2: 100% Rollout**
1. Set `WORKFLOW_ROLLOUT_PERCENT=100`
2. Deploy update
3. Monitor all imports
4. Drain legacy queue
5. GATE: 100% success

**Days 3-4: Code Cleanup**
1. Remove legacy orchestration code
2. Verify 60% LOC reduction
3. Update documentation
4. GATE: All tests passing

**Day 5: Retrospective**
1. Review A/B metrics
2. Document lessons learned
3. Plan Phase 4

---

## Success Metrics

### Phase 3.1 (Workflow Definition)
- Workflow executes all 4 steps successfully
- State persists across Worker restarts
- Workflow state size < 128 KB

### Phase 3.2 (WebSocket Event Bridge)
- Event delivery latency < 100ms (P95)
- Zero event loss during hibernation
- Multiple clients can subscribe

### Phase 3.3 (JobStateManagerDO Simplification)
- Code reduction: 60% (1000 → 400 LOC)
- 20-30% faster completion time
- 99.9%+ success rate
- Zero state loss incidents

---

## Definition of Done

**Sprint 3 is COMPLETE when:**
- Cloudflare Workflows handle 100% of book imports
- JobStateManagerDO code reduced by 60%
- WebSocket events deliver progress < 100ms
- Zero state loss incidents
- All tests passing
- Documentation updated
- Legacy code removed

**Timeline:** 10 working days
**Key Deliverable:** Production-ready Workflows system

---

## Files Created/Modified Summary

**New Files:**
```
src/workflows/import-book.ts
src/handlers/workflow-trigger-handler.ts
src/handlers/workflow-status-handler.ts
src/types/workflow-events.ts
src/utils/feature-flags.ts
src/utils/workflow-metrics.ts
test/workflows/import-book.test.ts
test/integration/workflow-websocket.test.ts
test/migration/workflow-vs-legacy.test.ts
docs/WORKFLOW_CLIENT_INTEGRATION.md
```

**Modified Files:**
```
wrangler.jsonc
src/router.ts
src/durable-objects/WebSocketConnectionDO.ts
src/durable-objects/JobStateManagerDO.ts
src/handlers/import-handler.ts
```

---

**Last Updated:** November 21, 2025
**Plan Status:** Ready for implementation
**Sprint Owner:** Development Team
**Dependencies:** Phase 2 (D1 migration) optional with KV fallback
