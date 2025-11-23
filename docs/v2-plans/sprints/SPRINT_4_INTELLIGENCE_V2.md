# Sprint 4: Intelligence V2 - Semantic Search & AI Recommendations

**Status:** Planned
**Duration:** 7 days (accelerated from original 14-day estimate)
**Sprint Goal:** Launch semantic search and AI-powered book recommendations using Cloudflare Vectorize, Workers AI, and Gemini

---

## Executive Summary

**Key Innovation:** Ship semantic search WITHOUT waiting for Phase 2 D1 migration by building on existing KV infrastructure first.

**What We're Building:**
1. Vector-based semantic search (natural language queries)
2. AI-powered weekly book recommendations
3. Auto-vectorization pipeline for book metadata

**Critical Decision:** Use incremental approach (KV → Vectorize now, add D1 sync later) to deliver user value immediately instead of waiting months for Phase 2 completion.

---

## Architecture Overview

```
Current State (V1)              Target State (V2)
==================              =================

┌─────────────┐                 ┌─────────────┐
│   Workers   │                 │   Workers   │
│  + Custom   │                 │  + Workers  │
│     DOs     │                 │     AI      │
└─────────────┘                 └─────────────┘
       |                               |
       v                               v
┌─────────────┐                 ┌─────────────┐
│  KV Cache   │                 │  Vectorize  │
│  (JSON)     │───────────────> │  (Vectors)  │
└─────────────┘                 └─────────────┘
       |                               |
       v                               v
┌─────────────┐                 ┌─────────────┐
│   String    │                 │  Semantic   │
│   Search    │                 │   Search    │
└─────────────┘                 └─────────────┘

Phase 4.1-4.3: Build Vectorize + KV (INDEPENDENT)
Phase 4.4: Add D1 sync when Phase 2 completes (OPTIONAL)
```

---

## Phase 4.1: Vectorize Infrastructure Setup

**Goal:** Provision Vectorize index and create embedding service (NO D1 dependency)

### Task 4.1.1: Provision Vectorize Index

**Configuration (`wrangler.jsonc`):**
```jsonc
{
  "vectorize": {
    "bindings": [
      {
        "binding": "BOOK_VECTORS",
        "index_name": "bookstrack-semantic-index",
        "dimensions": 1024,
        "metric": "cosine"
      }
    ]
  }
}
```

**Provisioning Command:**
```bash
npx wrangler vectorize create bookstrack-semantic-index \
  --dimensions=1024 \
  --metric=cosine
```

**Validation:**
```bash
npx wrangler vectorize list
# Expected: bookstrack-semantic-index (1024 dims, cosine)
```

---

### Task 4.1.2: Add Workers AI Binding

**Configuration (`wrangler.jsonc`):**
```jsonc
{
  "ai": {
    "binding": "AI"
  }
}
```

**Model Used:** `@cf/baai/bge-m3`
- Output: 1024-dimensional vectors
- Max input: 512 tokens
- Best for: Multilingual semantic search

---

### Task 4.1.3: Create Embedding Service

**File:** `src/services/ai/embedding-service.js`

```javascript
/**
 * Generate semantic embeddings using Workers AI BGE-M3
 * @param {string} text - Book metadata (title + description + author)
 * @param {Object} env - Cloudflare env with AI binding
 * @returns {Promise<number[]>} 1024-dimensional vector
 */
export async function generateEmbedding(text, env) {
  const response = await env.AI.run('@cf/baai/bge-m3', {
    text: [text]  // BGE-M3 expects array
  })

  return response.data[0]  // Returns Float32Array[1024]
}

/**
 * Create searchable text from book metadata
 */
export function createBookText(book) {
  return `${book.title} by ${book.author}. ${book.description || ''}`
    .substring(0, 512)  // BGE-M3 max input tokens
}
```

**Key Design Decisions:**
- Truncate to 512 chars (BGE-M3 limit)
- Include title + author + description (semantic richness)
- Return Float32Array for efficiency

---

### Task 4.1.4: Create Vector Insert Service

**File:** `src/services/ai/vectorize-service.js`

```javascript
import { generateEmbedding, createBookText } from './embedding-service.js'

export async function insertBookVector(book, env) {
  try {
    const text = createBookText(book)
    const embedding = await generateEmbedding(text, env)

    await env.BOOK_VECTORS.insert([
      {
        id: book.isbn,  // Use ISBN as vector ID
        values: embedding,
        metadata: {
          title: book.title,
          author: book.author,
          insertedAt: new Date().toISOString()
        }
      }
    ])

    return { success: true, isbn: book.isbn }
  } catch (error) {
    console.error('Vector insert failed:', error)
    throw error
  }
}
```

**Error Handling:**
- Retry on transient failures (network errors)
- Log failed ISBNs for manual review
- Continue processing remaining books

---

### Validation Checklist (Phase 4.1)

- [ ] Vectorize index shows in `wrangler vectorize list`
- [ ] Test embedding generation returns 1024-dim vector
- [ ] Insert 10 test books, verify with `wrangler vectorize query`
- [ ] Vector quality: average cosine similarity > 0.7
- [ ] Zero insertion failures in test batch

**Files Created:**
- `src/services/ai/embedding-service.js`
- `src/services/ai/vectorize-service.js`

---

## Phase 4.2: Semantic Search API Implementation

**Goal:** Create `GET /v2/search/semantic` endpoint for natural language queries

### Task 4.2.1: Create Semantic Search Handler

**File:** `src/handlers/search-semantic-handler.js`

```javascript
import { createSuccessResponse, createErrorResponse } from '../utils/response-builder.js'
import { generateEmbedding } from '../services/ai/embedding-service.js'

export async function handleSemanticSearch(request, env) {
  try {
    const url = new URL(request.url)
    const query = url.searchParams.get('q')
    const limit = parseInt(url.searchParams.get('limit') || '10')

    if (!query || query.length < 3) {
      return createErrorResponse(
        'INVALID_REQUEST',
        'Query must be at least 3 characters',
        { statusCode: 400 }
      )
    }

    // Step 1: Convert query to vector embedding
    const queryEmbedding = await generateEmbedding(query, env)

    // Step 2: Search Vectorize for similar books
    const vectorResults = await env.BOOK_VECTORS.query(queryEmbedding, {
      topK: limit,
      returnMetadata: true
    })

    // Step 3: Fetch full book details from KV (or D1 when available)
    const books = await Promise.all(
      vectorResults.matches.map(async (match) => {
        const cacheKey = `book:isbn:${match.id}`
        const bookData = await env.BOOK_CACHE.get(cacheKey, 'json')

        return {
          ...bookData,
          relevanceScore: match.score,  // Cosine similarity (0-1)
          matchReason: 'semantic'
        }
      })
    )

    return createSuccessResponse({
      results: books.filter(b => b !== null),  // Remove nulls
      query,
      totalResults: books.length,
      searchType: 'semantic'
    }, {
      headers: {
        'X-Search-Type': 'semantic-vectorize',
        'X-Model': 'bge-m3'
      }
    })

  } catch (error) {
    console.error('Semantic search failed:', error)
    return createErrorResponse(
      'SEARCH_FAILED',
      'Semantic search unavailable',
      { statusCode: 500 }
    )
  }
}
```

**Data Flow:**
```
User Query ("sad sci-fi about robots")
    |
    v
[Generate Embedding] (Workers AI BGE-M3)
    |
    v
[Vectorize Query] (Cosine similarity search)
    |
    v
[ISBN List] (e.g., 9780156030083)
    |
    v
[KV Fetch] (Full book details)
    |
    v
[Response] (Flowers for Algernon + relevance score)
```

---

### Task 4.2.2: Add Route to Hono Router

**File:** `src/router.ts` (add new route)

```typescript
import { handleSemanticSearch } from './handlers/search-semantic-handler.js'

// Add semantic search endpoint
router.get('/v2/search/semantic', rateLimitMiddleware, async (c) => {
  return handleSemanticSearch(c.req.raw, c.env)
})
```

---

### Task 4.2.3: Add Rate Limiting for AI Endpoints

**Rationale:** Semantic search uses Workers AI (costly operation)

**Configuration:**
- Limit: 5 requests/minute per IP (stricter than standard 100/min)
- Use existing rate limiter with custom config
- Return 429 with Retry-After header on limit

**Implementation:**
```javascript
const AI_RATE_LIMIT = {
  requestsPerMinute: 5,
  burstSize: 10
}
```

---

### Task 4.2.4: Create Test Suite

**File:** `test/handlers/search-semantic-handler.test.js`

```javascript
import { describe, it, expect, vi } from 'vitest'
import { handleSemanticSearch } from '../../src/handlers/search-semantic-handler.js'

describe('Semantic Search Handler', () => {
  it('should return relevant books for natural language query', async () => {
    const mockEnv = {
      AI: { run: vi.fn().mockResolvedValue({ data: [new Float32Array(1024)] }) },
      BOOK_VECTORS: {
        query: vi.fn().mockResolvedValue({
          matches: [
            { id: '9780451524935', score: 0.89 },  // 1984 by Orwell
            { id: '9780061120084', score: 0.85 }   // Brave New World
          ]
        })
      },
      BOOK_CACHE: {
        get: vi.fn().mockImplementation((key) => {
          if (key.includes('9780451524935')) {
            return Promise.resolve({ isbn: '9780451524935', title: '1984' })
          }
          return Promise.resolve({ isbn: '9780061120084', title: 'Brave New World' })
        })
      }
    }

    const request = new Request('http://localhost/v2/search/semantic?q=dystopian future')
    const response = await handleSemanticSearch(request, mockEnv)
    const data = await response.json()

    expect(data.success).toBe(true)
    expect(data.data.results).toHaveLength(2)
    expect(data.data.results[0].relevanceScore).toBeGreaterThan(0.8)
  })

  it('should reject queries shorter than 3 characters', async () => {
    const request = new Request('http://localhost/v2/search/semantic?q=ab')
    const response = await handleSemanticSearch(request, {})
    const data = await response.json()

    expect(data.success).toBe(false)
    expect(data.error.code).toBe('INVALID_REQUEST')
  })
})
```

---

### Validation Checklist (Phase 4.2)

- [ ] Query "emotional sci-fi" returns "Flowers for Algernon" (no keyword match needed)
- [ ] P95 latency < 800ms (embedding 200ms + search 100ms + fetch 500ms)
- [ ] Relevance score > 0.7 for top 5 results
- [ ] Rate limiting blocks > 5 req/min
- [ ] All tests passing

**API Example:**
```bash
GET /v2/search/semantic?q=sad%20sci-fi%20about%20robots&limit=5

Response:
{
  "success": true,
  "data": {
    "results": [
      {
        "isbn": "9780156030083",
        "title": "Flowers for Algernon",
        "author": "Daniel Keyes",
        "relevanceScore": 0.89,
        "matchReason": "semantic"
      }
    ],
    "query": "sad sci-fi about robots",
    "totalResults": 5,
    "searchType": "semantic"
  }
}
```

**Files Created/Modified:**
- `src/handlers/search-semantic-handler.js` (NEW)
- `src/router.ts` (MODIFIED - add route)
- `test/handlers/search-semantic-handler.test.js` (NEW)

---

## Phase 4.3: AI Recommendation Engine

**Goal:** Create weekly automated book recommendations using user reading history + Gemini AI

### Task 4.3.1: Create Recommendation Service

**File:** `src/services/ai/recommendation-service.js`

```javascript
import { generateEmbedding } from './embedding-service.js'

/**
 * Generate book recommendations using Gemini AI
 * @param {Array} readBooks - User's reading history (max 5 books)
 * @param {Object} env - Cloudflare env with Gemini API key
 * @returns {Promise<Array>} 3 recommended ISBNs
 */
export async function generateRecommendations(readBooks, env) {
  const prompt = `
Based on these books the user has read:
${readBooks.map(b => `- "${b.title}" by ${b.author}`).join('\n')}

Recommend 3 similar books they might enjoy. Return ONLY valid ISBN-13 numbers, one per line.
Focus on: similar themes, writing style, and genre.
Ensure diversity: no duplicate authors.
`

  const response = await fetch(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': env.GEMINI_API_KEY
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }]
      })
    }
  )

  const data = await response.json()
  const isbns = data.candidates[0].content.parts[0].text
    .split('\n')
    .filter(line => /^\d{13}$/.test(line.trim()))
    .slice(0, 3)

  return isbns
}

/**
 * Validate ISBNs exist in our catalog
 */
export async function validateRecommendations(isbns, env) {
  const validated = await Promise.all(
    isbns.map(async (isbn) => {
      const cached = await env.BOOK_CACHE.get(`book:isbn:${isbn}`, 'json')
      return cached ? isbn : null
    })
  )

  return validated.filter(isbn => isbn !== null)
}
```

**Prompt Engineering:**
- Clear instructions: "Return ONLY ISBN-13 numbers"
- Constraints: "No duplicate authors" (diversity)
- Context: User reading history (5 books max)

---

### Task 4.3.2: Create Scheduled Cron Handler

**File:** `src/handlers/scheduled-recommendations.js`

```javascript
import { generateRecommendations, validateRecommendations } from '../services/ai/recommendation-service.js'

export async function handleScheduledRecommendations(env) {
  console.log('Running weekly recommendation generation...')

  try {
    // TODO: When D1 is ready, fetch actual user reading history
    // For now, use sample data or skip user-specific logic

    // Example: Get active users from D1 (future)
    // const users = await env.DB.prepare('SELECT DISTINCT user_id FROM reading_history').all()

    // Sample implementation: Generate global recommendations
    const sampleBooks = [
      { title: '1984', author: 'George Orwell' },
      { title: 'Brave New World', author: 'Aldous Huxley' },
      { title: 'Fahrenheit 451', author: 'Ray Bradbury' },
      { title: 'The Handmaid\'s Tale', author: 'Margaret Atwood' },
      { title: 'Animal Farm', author: 'George Orwell' }
    ]

    const recommendedISBNs = await generateRecommendations(sampleBooks, env)
    const validISBNs = await validateRecommendations(recommendedISBNs, env)

    // Cache recommendations for 7 days
    await env.BOOK_CACHE.put(
      'recommendations:weekly',
      JSON.stringify({
        isbns: validISBNs,
        generatedAt: new Date().toISOString()
      }),
      { expirationTtl: 604800 } // 7 days
    )

    console.log(`Generated ${validISBNs.length} recommendations`)
    return { success: true, count: validISBNs.length }

  } catch (error) {
    console.error('Recommendation generation failed:', error)
    return { success: false, error: error.message }
  }
}
```

**Caching Strategy:**
- TTL: 7 days (weekly refresh)
- Key: `recommendations:weekly` (global for now)
- Future: `recommendations:user:{userId}` (personalized)

---

### Task 4.3.3: Add Cron Trigger

**Configuration (`wrangler.jsonc`):**
```jsonc
{
  "triggers": {
    "crons": [
      "0 0 * * 1"  // Every Monday at midnight UTC
    ]
  }
}
```

**Schedule:** Weekly on Monday 00:00 UTC

---

### Task 4.3.4: Update Main Worker

**File:** `src/index.js` (add scheduled handler)

```javascript
import { handleScheduledRecommendations } from './handlers/scheduled-recommendations.js'

export default {
  async fetch(request, env, ctx) {
    // Existing Hono router logic
    return router.fetch(request, env, ctx)
  },

  async scheduled(event, env, ctx) {
    // Run weekly recommendation generation
    await handleScheduledRecommendations(env)
  }
}
```

---

### Task 4.3.5: Create Recommendation Fetch Endpoint

**File:** `src/handlers/recommendations-handler.js`

```javascript
import { createSuccessResponse, createErrorResponse } from '../utils/response-builder.js'

export async function handleGetRecommendations(request, env) {
  try {
    const cached = await env.BOOK_CACHE.get('recommendations:weekly', 'json')

    if (!cached) {
      return createErrorResponse(
        'NO_RECOMMENDATIONS',
        'Weekly recommendations not yet generated',
        { statusCode: 404 }
      )
    }

    // Fetch full book details
    const books = await Promise.all(
      cached.isbns.map(isbn =>
        env.BOOK_CACHE.get(`book:isbn:${isbn}`, 'json')
      )
    )

    return createSuccessResponse({
      recommendations: books.filter(b => b !== null),
      generatedAt: cached.generatedAt,
      source: 'gemini-ai'
    })

  } catch (error) {
    return createErrorResponse(
      'RECOMMENDATIONS_FAILED',
      'Could not fetch recommendations',
      { statusCode: 500 }
    )
  }
}
```

**Add route to `router.ts`:**
```typescript
router.get('/v2/recommendations/weekly', async (c) => {
  return handleGetRecommendations(c.req.raw, c.env)
})
```

---

### Validation Checklist (Phase 4.3)

- [ ] Cron runs every Monday at midnight UTC
- [ ] Generates 3 valid ISBNs (exist in catalog)
- [ ] No duplicate authors in recommendations
- [ ] Cached for 7 days in KV
- [ ] GET /v2/recommendations/weekly returns fresh picks

**Files Created:**
- `src/services/ai/recommendation-service.js`
- `src/handlers/scheduled-recommendations.js`
- `src/handlers/recommendations-handler.js`
- `src/index.js` (MODIFIED - add scheduled export)
- `wrangler.jsonc` (MODIFIED - add cron trigger)

---

## Testing Strategy

### Phase 4.1 Testing (Infrastructure)

**File:** `test/services/ai/embedding-service.test.js`

```javascript
describe('Embedding Service', () => {
  it('should generate 1024-dimensional vectors', async () => {
    const mockEnv = {
      AI: {
        run: vi.fn().mockResolvedValue({
          data: [new Float32Array(1024).fill(0.5)]
        })
      }
    }

    const embedding = await generateEmbedding('Test book title', mockEnv)
    expect(embedding).toHaveLength(1024)
    expect(embedding[0]).toBeCloseTo(0.5)
  })

  it('should truncate long text to 512 chars', () => {
    const longText = 'a'.repeat(1000)
    const book = { title: longText, author: 'Test', description: '' }
    const text = createBookText(book)
    expect(text.length).toBeLessThanOrEqual(512)
  })
})
```

---

### Manual Quality Testing

```bash
# Test vector quality with 100 real books
npm run test:vector-quality

# Expected output:
# - Generated 100 embeddings
# - Average cosine similarity: 0.82 (>0.7 threshold)
# - Duplicate detection: 0 identical vectors
```

---

### Phase 4.2 Testing (Semantic Search)

**Test Cases:**
- Query "emotional sci-fi" should return "Flowers for Algernon"
- Query "dystopian society" should return 1984, Brave New World
- Query "magic school" should return Harry Potter series
- Latency: P95 < 800ms (measure with `wrangler tail`)

---

### Phase 4.3 Testing (Recommendations)

```bash
# Trigger cron manually for testing
npx wrangler dev --test-scheduled

# Verify recommendations
curl http://localhost:8787/v2/recommendations/weekly
```

---

## Deployment Plan

### Week 1 Rollout

**Days 1-2: Infrastructure Setup**
1. Create Vectorize index: `wrangler vectorize create bookstrack-semantic-index --dimensions=1024 --metric=cosine`
2. Update `wrangler.jsonc` with Vectorize + AI bindings
3. Deploy embedding services (no user-facing changes yet)
4. Run quality tests with 100 books
5. **GATE:** Vector quality >0.7 average similarity

**Days 3-5: Semantic Search Launch**
1. Deploy search endpoint to production
2. Enable rate limiting (5 req/min)
3. Monitor error rates (<1% threshold)
4. A/B test: 10% of users get semantic search link
5. **GATE:** P95 latency <800ms, relevance score >0.7

**Days 6-7: Recommendations Launch**
1. Deploy cron job (Monday midnight UTC)
2. Generate first weekly picks
3. Add recommendation widget to frontend
4. Monitor Gemini API quota usage
5. **GATE:** 3 valid recommendations generated, no duplicate authors

---

## Risk Mitigation

### Risk 1: Poor Vector Quality (High Impact)
- **Detection:** Average cosine similarity <0.7 in tests
- **Mitigation:** Switch to @cf/baai/bge-base-en-v1.5 (simpler model)
- **Rollback:** Disable semantic search, fallback to keyword matching

### Risk 2: Vectorize Free Tier Exhausted (Medium Impact)
- **Detection:** 10M stored dimensions limit reached
- **Calculation:** 10K books × 1024 dims = 10.2M (at limit!)
- **Mitigation:** Upgrade to paid plan for 50M dims
- **Alternative:** Implement vector pruning (remove old/unused books)

### Risk 3: High Latency (Medium Impact)
- **Detection:** P95 latency >1.5s (kills UX)
- **Mitigation:** Cache frequent queries in KV (24hr TTL)
- **Alternative:** Pre-compute embeddings for popular queries

### Risk 4: Gemini Hallucinations (Low Impact)
- **Detection:** Recommended ISBNs don't exist in catalog
- **Mitigation:** Validate ISBNs before caching (already implemented)
- **Fallback:** Use Vectorize similarity search only (skip Gemini)

### Risk 5: D1 Migration Delays Phase 4 (NOW RESOLVED)
- **Original Plan:** Wait for D1 before starting Phase 4
- **Resolution:** Build on KV first, add D1 sync later in Phase 4.4
- **Benefit:** Ship semantic search in Week 1 instead of waiting months

---

## Success Metrics

### Phase 4.1 (Infrastructure)
- Vectorize index operational
- 100% of new books auto-vectorized
- Vector quality score >0.7
- Zero vector insertion failures

### Phase 4.2 (Semantic Search)
- 100+ semantic queries/day within 1 week
- P95 latency <800ms
- User satisfaction: 80%+ relevant results (survey)
- Fallback rate <5% (when semantic search fails)

### Phase 4.3 (Recommendations)
- Weekly cron runs successfully (100% uptime)
- 3 valid recommendations generated per run
- Click-through rate >15% (users explore recommendations)
- Zero duplicate authors in top 3 picks

---

## Future Enhancements (Phase 4.4+)

### When D1 Migration Completes (Phase 2)
1. Add D1 trigger: Auto-vectorize on book insert
2. User-specific recommendations (reading history from D1)
3. Collaborative filtering (users with similar taste)

### Advanced Features (Phase 5)
1. Hybrid search (semantic + keyword + filters)
2. Query expansion ("sci-fi" → "science fiction", "SF")
3. Re-ranking with user preferences
4. Real-time recommendations (not just weekly)

---

## Definition of Done

**Phase 4 is COMPLETE when:**
- Vectorize index deployed and operational
- GET /v2/search/semantic returns relevant results
- Query "books like 1984" works without keyword matching
- Weekly cron generates 3 valid recommendations
- All tests passing (>80% coverage for new code)
- Documentation updated (API_CONTRACT.md)
- Monitoring dashboard tracks vector quality + latency
- Production deployment successful with <1% error rate

**Timeline:** 7 days (accelerated from 14)
**Blocker Resolution:** KV-first approach removes D1 dependency

---

## Files Created/Modified Summary

**New Files:**
```
src/services/ai/
  ├── embedding-service.js         (Workers AI BGE-M3 integration)
  ├── vectorize-service.js         (Vector insert/query)
  └── recommendation-service.js    (Gemini AI recommendations)

src/handlers/
  ├── search-semantic-handler.js   (Semantic search endpoint)
  ├── scheduled-recommendations.js (Weekly cron job)
  └── recommendations-handler.js   (Recommendation fetch endpoint)

test/services/ai/
  └── embedding-service.test.js

test/handlers/
  └── search-semantic-handler.test.js
```

**Modified Files:**
```
wrangler.jsonc          (Vectorize + AI bindings, cron trigger)
src/router.ts           (Add semantic search + recommendations routes)
src/index.js            (Add scheduled handler)
```

---

**Last Updated:** November 21, 2025
**Plan Status:** Ready for implementation
**Sprint Owner:** Development Team
**Stakeholders:** Product, Engineering, AI/ML
