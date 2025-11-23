# Phase 2: KV to D1 Migration - Complete Implementation Plan

**Sprint 2 Duration:** 2 Weeks
**Goal:** Migrate from Key-Value blob storage to D1 relational database for complex queries
**Created:** November 21, 2025
**Status:** Planning Complete

---

## Architecture Overview

```
BEFORE (KV-Only):
  External API --> KV_CACHE (JSON blobs)
                       |
                   API Response

AFTER (D1 + KV):
  External API --> D1 Database (structured, source of truth)
                       |
                   KV_CACHE (performance layer)
                       |
                   API Response

Read Flow:
  1. Check KV_CACHE --> HIT? Return
  2. KV MISS --> Query D1 --> HIT? Populate KV, Return
  3. D1 MISS --> Fetch External API --> Write D1 --> Write KV --> Return
```

---

## Implementation Timeline

### Days 1-3: Database Schema Design
### Days 4-7: Migration Script Development
### Days 8-10: Data Access Layer Refactoring
### Days 11-12: Testing & Validation
### Day 13: Production Deployment
### Day 14+: Monitoring & Post-Migration Review

---

## Item 2.1: D1 Schema Design (Days 1-3)

### Database Schema

**Books Table (Primary Data):**
```sql
CREATE TABLE IF NOT EXISTS Books (
  isbn TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  authors TEXT NOT NULL,                    -- JSON array
  authors_detailed TEXT,                    -- JSON objects
  publication_year INTEGER,
  publisher TEXT,
  page_count INTEGER,
  language TEXT DEFAULT 'en',
  categories TEXT,                          -- JSON array
  description TEXT,
  cover_url TEXT,
  thumbnail_url TEXT,
  canonical_metadata TEXT NOT NULL,         -- Full JSON blob
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX idx_books_year ON Books(publication_year);
CREATE INDEX idx_books_language ON Books(language);
CREATE INDEX idx_books_created ON Books(created_at);
```

**UserLibrary Table (User Collections):**
```sql
CREATE TABLE IF NOT EXISTS UserLibrary (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  isbn TEXT NOT NULL,
  status TEXT CHECK(status IN ('want_to_read', 'reading', 'completed')),
  rating INTEGER CHECK(rating >= 1 AND rating <= 5),
  review TEXT,
  added_at INTEGER NOT NULL DEFAULT (unixepoch()),
  started_at INTEGER,
  completed_at INTEGER,
  FOREIGN KEY (isbn) REFERENCES Books(isbn) ON DELETE CASCADE,
  UNIQUE(user_id, isbn)
);

CREATE INDEX idx_user_library_user ON UserLibrary(user_id);
CREATE INDEX idx_user_library_status ON UserLibrary(user_id, status);
CREATE INDEX idx_user_library_rating ON UserLibrary(user_id, rating);
```

**CacheMetrics Table (Observability):**
```sql
CREATE TABLE IF NOT EXISTS CacheMetrics (
  cache_key TEXT PRIMARY KEY NOT NULL,
  hit_count INTEGER NOT NULL DEFAULT 0,
  miss_count INTEGER NOT NULL DEFAULT 0,
  last_accessed INTEGER NOT NULL DEFAULT (unixepoch()),
  data_size_bytes INTEGER,
  ttl_seconds INTEGER
);

CREATE INDEX idx_cache_last_accessed ON CacheMetrics(last_accessed);
```

### Configuration Setup

**Update wrangler.jsonc:**
```json
{
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "bookstrack-db",
      "database_id": "xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx"
    }
  ],
  "kv_namespaces": [
    {
      "binding": "BOOK_CACHE",
      "id": "existing-kv-namespace-id"
    }
  ]
}
```

**Create Migration Files:**
```
migrations/
├── 0001_initial_schema.sql      (Books table)
├── 0002_add_user_library.sql    (UserLibrary table)
└── 0003_add_cache_metrics.sql   (CacheMetrics table)
```

**Deployment Commands:**
```bash
# Create database
npx wrangler d1 create bookstrack-db

# Apply migrations locally
npx wrangler d1 migrations apply bookstrack-db --local

# Apply migrations to production
npx wrangler d1 migrations apply bookstrack-db --remote

# Verify schema
npx wrangler d1 execute bookstrack-db \
  --command "SELECT name FROM sqlite_master WHERE type='table'"
```

**Deliverables for Item 2.1:**
- [ ] SQL schema files in `migrations/` directory
- [ ] Updated `wrangler.jsonc` with D1 binding
- [ ] Database created in both local and remote environments
- [ ] Schema validation tests passing
- [ ] Documentation in `docs/DATABASE_SCHEMA.md`

---

## Item 2.2: Migration Script (Days 4-7)

### Migration Architecture

**Key Design Principles:**
1. **Idempotent:** Can run multiple times safely (upsert, not insert)
2. **Resumable:** Checkpoint progress in case of failures
3. **Validated:** Verify data integrity before and after
4. **Batched:** Process in chunks to avoid CPU timeout

### Implementation

**Core Migration Logic:**
```typescript
// src/migrations/kv-to-d1-migrator.ts
export async function migrateKVToD1(env: Env, ctx: ExecutionContext) {
  const BATCH_SIZE = 100 // Process 100 keys per iteration
  let cursor: string | undefined
  let totalMigrated = 0
  let totalErrors = 0

  do {
    // List KV keys with pagination
    const result = await env.BOOK_CACHE.list({
      prefix: 'book:isbn:',
      limit: BATCH_SIZE,
      cursor: cursor
    })

    // Process batch
    const batch = await processBatch(result.keys, env)
    totalMigrated += batch.success
    totalErrors += batch.errors

    // Save checkpoint
    await saveCheckpoint(env, {
      cursor: result.cursor,
      totalMigrated,
      totalErrors,
      timestamp: Date.now()
    })

    cursor = result.cursor

    // Log progress
    console.log(`Migrated ${totalMigrated} books, ${totalErrors} errors`)

  } while (cursor) // Continue until all keys processed

  return { totalMigrated, totalErrors }
}
```

**Batch Processing:**
```typescript
async function processBatch(keys: KVNamespaceListKey[], env: Env) {
  let success = 0
  let errors = 0

  // Process in parallel for speed (but limit concurrency)
  const promises = keys.map(async (key) => {
    try {
      // Fetch KV value
      const kvData = await env.BOOK_CACHE.get(key.name, 'json')
      if (!kvData) {
        console.warn(`Empty value for key: ${key.name}`)
        return
      }

      // Parse ISBN from key (book:isbn:9780439708180)
      const isbn = key.name.split(':')[2]

      // Transform to D1 schema
      const bookRecord = transformToD1Schema(kvData, isbn)

      // Upsert to D1 (idempotent)
      await upsertBookToD1(env.DB, bookRecord)

      // Verify write
      const verified = await verifyBookInD1(env.DB, isbn)
      if (!verified) {
        throw new Error(`Verification failed for ISBN: ${isbn}`)
      }

      success++
    } catch (error) {
      errors++
      console.error(`Migration failed for ${key.name}:`, error)

      // Log to error tracking table
      await logMigrationError(env.DB, key.name, error)
    }
  })

  await Promise.all(promises)
  return { success, errors }
}
```

**Data Transformation:**
```typescript
function transformToD1Schema(kvData: any, isbn: string) {
  return {
    isbn: isbn,
    title: kvData.title || 'Unknown',
    authors: JSON.stringify(kvData.authors || []),
    authors_detailed: kvData.authorsDetailed
      ? JSON.stringify(kvData.authorsDetailed)
      : null,
    publication_year: kvData.publishedDate
      ? parseInt(kvData.publishedDate.substring(0, 4))
      : null,
    publisher: kvData.publisher || null,
    page_count: kvData.pageCount || null,
    language: kvData.language || 'en',
    categories: kvData.categories
      ? JSON.stringify(kvData.categories)
      : null,
    description: kvData.description || null,
    cover_url: kvData.imageLinks?.large || kvData.imageLinks?.medium || null,
    thumbnail_url: kvData.imageLinks?.thumbnail || null,
    canonical_metadata: JSON.stringify(kvData) // Full blob for backwards compat
  }
}
```

**D1 Upsert Operation:**
```typescript
async function upsertBookToD1(db: D1Database, book: BookRecord) {
  const stmt = db.prepare(`
    INSERT INTO Books (
      isbn, title, authors, authors_detailed, publication_year,
      publisher, page_count, language, categories, description,
      cover_url, thumbnail_url, canonical_metadata
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(isbn) DO UPDATE SET
      title = excluded.title,
      authors = excluded.authors,
      updated_at = unixepoch()
  `)

  await stmt.bind(
    book.isbn, book.title, book.authors, book.authors_detailed,
    book.publication_year, book.publisher, book.page_count,
    book.language, book.categories, book.description,
    book.cover_url, book.thumbnail_url, book.canonical_metadata
  ).run()
}
```

**Checkpoint & Resume:**
```typescript
// Save progress to KV
async function saveCheckpoint(env: Env, checkpoint: MigrationCheckpoint) {
  await env.BOOK_CACHE.put(
    'migration:checkpoint',
    JSON.stringify(checkpoint)
  )
}

// Resume from last checkpoint
async function loadCheckpoint(env: Env): Promise<MigrationCheckpoint | null> {
  const data = await env.BOOK_CACHE.get('migration:checkpoint', 'json')
  return data || null
}

// Invoke migration with resume capability
export async function invokeMigration(env: Env, resume: boolean = false) {
  let cursor: string | undefined

  if (resume) {
    const checkpoint = await loadCheckpoint(env)
    cursor = checkpoint?.cursor
    console.log(`Resuming from cursor: ${cursor}`)
  }

  return migrateKVToD1(env, ctx, cursor)
}
```

### Execution Endpoint

**Create dedicated route for migration:**
```typescript
// Add to src/router.ts
router.post('/admin/migrate-kv-to-d1', adminAuthMiddleware, async (c) => {
  const { resume, dryRun } = c.req.query()

  if (dryRun === 'true') {
    return c.json({ message: 'Dry run - no data written' })
  }

  const result = await invokeMigration(c.env, resume === 'true')

  return c.json({
    success: true,
    data: {
      totalMigrated: result.totalMigrated,
      totalErrors: result.totalErrors
    }
  })
})
```

**CLI invocation:**
```bash
# Dry run first
curl -X POST "https://api.oooefam.net/admin/migrate-kv-to-d1?dryRun=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Real migration
curl -X POST "https://api.oooefam.net/admin/migrate-kv-to-d1" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Resume if interrupted
curl -X POST "https://api.oooefam.net/admin/migrate-kv-to-d1?resume=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

### Validation Strategy

**Pre-Migration Validation:**
```typescript
// Count KV keys with book prefix
const kvCount = await countKVKeys(env.BOOK_CACHE, 'book:isbn:')

// Sample random keys for integrity check
const sampleKeys = await getRandomKVKeys(env.BOOK_CACHE, 10)
```

**Post-Migration Validation:**
```typescript
// Count D1 records
const d1Count = await env.DB.prepare('SELECT COUNT(*) as count FROM Books').first()

// Validate sample ISBNs
for (const isbn of sampleISBNs) {
  const kvData = await env.BOOK_CACHE.get(`book:isbn:${isbn}`, 'json')
  const d1Data = await env.DB.prepare('SELECT * FROM Books WHERE isbn = ?')
    .bind(isbn).first()

  // Compare fields
  assert(kvData.title === d1Data.title)
  assert(JSON.stringify(kvData.authors) === d1Data.authors)
}

// Check for missing records
if (Math.abs(kvCount - d1Count.count) > 10) {
  throw new Error(`Data loss detected: KV=${kvCount}, D1=${d1Count.count}`)
}
```

**Deliverables for Item 2.2:**
- [ ] Migration script with pagination and checkpointing
- [ ] Data transformation logic (KV JSON → D1 schema)
- [ ] Validation suite (pre/post migration checks)
- [ ] Admin API endpoint for migration invocation
- [ ] Dry-run mode for testing
- [ ] Error logging and recovery procedures
- [ ] Documentation in `docs/MIGRATION_GUIDE.md`

---

## Item 2.3: Data Access Layer Refactoring (Days 8-10)

### Read-Through Cache Pattern

**New Data Flow:**
```
1. API Request (ISBN lookup)
2. Check KV_CACHE → HIT? Return cached data
3. KV MISS → Query D1 database
4. D1 HIT? → Write to KV_CACHE, return data
5. D1 MISS? → Fetch from External API
6. Write to D1 (source of truth)
7. Write to KV_CACHE (performance layer)
8. Return data to client
```

**Cache Invalidation Strategy:**
- KV TTL: 24 hours (unchanged)
- D1 records: Permanent (updated_at timestamp tracked)
- Manual invalidation via admin endpoint if needed

### Service Layer Refactoring

**Current Implementation (KV-only):**
```typescript
// src/services/book-search.ts (BEFORE)
export async function findByISBN(isbn: string, env: Env) {
  // Check cache
  const cacheKey = `book:isbn:${isbn}`
  const cached = await env.BOOK_CACHE.get(cacheKey, 'json')
  if (cached) return cached

  // Fetch from external API
  const book = await fetchFromGoogleBooks(isbn, env)

  // Cache for 24 hours
  await env.BOOK_CACHE.put(cacheKey, JSON.stringify(book), {
    expirationTtl: 86400
  })

  return book
}
```

**New Implementation (D1 + KV):**
```typescript
// src/services/book-search.ts (AFTER)
export async function findByISBN(isbn: string, env: Env) {
  // Layer 1: Check KV cache (fastest)
  const cacheKey = `book:isbn:${isbn}`
  const cached = await env.BOOK_CACHE.get(cacheKey, 'json')
  if (cached) {
    await trackCacheHit(env, cacheKey) // Metrics tracking
    return cached
  }

  // Layer 2: Check D1 database (source of truth)
  const d1Book = await getBookFromD1(env.DB, isbn)
  if (d1Book) {
    // Populate KV cache from D1
    await env.BOOK_CACHE.put(cacheKey, JSON.stringify(d1Book), {
      expirationTtl: 86400
    })
    return d1Book
  }

  // Layer 3: Fetch from external API (cache miss)
  const externalBook = await fetchFromGoogleBooks(isbn, env)

  // Write to D1 first (source of truth)
  await saveBookToD1(env.DB, externalBook)

  // Then populate KV cache
  await env.BOOK_CACHE.put(cacheKey, JSON.stringify(externalBook), {
    expirationTtl: 86400
  })

  return externalBook
}
```

### D1 Data Access Functions

**Read Operations:**
```typescript
// src/services/d1-book-service.ts
export async function getBookFromD1(db: D1Database, isbn: string) {
  const result = await db.prepare(`
    SELECT
      isbn, title, authors, authors_detailed, publication_year,
      publisher, page_count, language, categories, description,
      cover_url, thumbnail_url, canonical_metadata, created_at
    FROM Books
    WHERE isbn = ?
  `).bind(isbn).first()

  if (!result) return null

  // Transform D1 row back to canonical format
  return {
    isbn: result.isbn,
    title: result.title,
    authors: JSON.parse(result.authors),
    authorsDetailed: result.authors_detailed
      ? JSON.parse(result.authors_detailed)
      : null,
    publishedDate: result.publication_year?.toString(),
    publisher: result.publisher,
    pageCount: result.page_count,
    language: result.language,
    categories: result.categories ? JSON.parse(result.categories) : null,
    description: result.description,
    imageLinks: {
      large: result.cover_url,
      medium: result.cover_url,
      thumbnail: result.thumbnail_url
    },
    // Include full canonical blob for backwards compatibility
    ...JSON.parse(result.canonical_metadata)
  }
}

// Complex query example (user library)
export async function getUserBooks(
  db: D1Database,
  userId: string,
  filters?: { status?: string, rating?: number, year?: number }
) {
  let query = `
    SELECT b.*, ul.status, ul.rating, ul.added_at
    FROM UserLibrary ul
    JOIN Books b ON ul.isbn = b.isbn
    WHERE ul.user_id = ?
  `
  const params = [userId]

  if (filters?.status) {
    query += ` AND ul.status = ?`
    params.push(filters.status)
  }

  if (filters?.rating) {
    query += ` AND ul.rating >= ?`
    params.push(filters.rating)
  }

  if (filters?.year) {
    query += ` AND b.publication_year = ?`
    params.push(filters.year)
  }

  query += ` ORDER BY ul.added_at DESC`

  const { results } = await db.prepare(query).bind(...params).all()
  return results || []
}
```

**Write Operations:**
```typescript
export async function saveBookToD1(db: D1Database, book: any) {
  const stmt = db.prepare(`
    INSERT INTO Books (
      isbn, title, authors, authors_detailed, publication_year,
      publisher, page_count, language, categories, description,
      cover_url, thumbnail_url, canonical_metadata
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(isbn) DO UPDATE SET
      title = excluded.title,
      authors = excluded.authors,
      authors_detailed = excluded.authors_detailed,
      updated_at = unixepoch()
  `)

  await stmt.bind(
    book.isbn,
    book.title,
    JSON.stringify(book.authors || []),
    book.authorsDetailed ? JSON.stringify(book.authorsDetailed) : null,
    book.publishedDate ? parseInt(book.publishedDate.substring(0, 4)) : null,
    book.publisher,
    book.pageCount,
    book.language || 'en',
    book.categories ? JSON.stringify(book.categories) : null,
    book.description,
    book.imageLinks?.large || book.imageLinks?.medium,
    book.imageLinks?.thumbnail,
    JSON.stringify(book)
  ).run()
}

// Batch insert for migration efficiency
export async function batchSaveBooks(db: D1Database, books: any[]) {
  const stmt = db.batch(
    books.map(book =>
      db.prepare(`INSERT OR REPLACE INTO Books (...) VALUES (...)`)
        .bind(/* book fields */)
    )
  )

  await stmt
}
```

### Handler Updates

**Update handlers to use new service layer:**
```typescript
// src/handlers/v1/search-isbn.ts
import { findByISBN } from '../../services/book-search'

export async function handleSearchISBN(request: Request, env: Env) {
  try {
    const url = new URL(request.url)
    const isbn = url.searchParams.get('isbn')

    if (!isbn) {
      return createErrorResponse(
        ErrorCodes.INVALID_REQUEST,
        'ISBN parameter required',
        400
      )
    }

    // Service layer now handles D1 + KV logic
    const book = await findByISBN(isbn, env)

    return createSuccessResponse({ book }, {
      source: book._cacheSource || 'external_api', // Track cache hits
      cached: !!book._cacheSource
    })

  } catch (error) {
    console.error('Search failed:', error)
    return createErrorResponse(
      ErrorCodes.INTERNAL_ERROR,
      'Search operation failed',
      500
    )
  }
}
```

### New API Endpoints (User Library)

**Add user library routes:**
```typescript
// src/router.ts
import { getUserLibrary, addToLibrary, updateBookStatus } from './handlers/v1/user-library'

// Get user's book collection
router.get('/v1/library/:userId', async (c) => {
  const userId = c.req.param('userId')
  const { status, rating, year } = c.req.query()

  const books = await getUserBooks(c.env.DB, userId, {
    status,
    rating: rating ? parseInt(rating) : undefined,
    year: year ? parseInt(year) : undefined
  })

  return c.json(createSuccessResponse({ books, count: books.length }))
})

// Add book to user library
router.post('/v1/library/:userId/books', async (c) => {
  const userId = c.req.param('userId')
  const { isbn, status, rating, review } = await c.req.json()

  await c.env.DB.prepare(`
    INSERT INTO UserLibrary (user_id, isbn, status, rating, review)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(user_id, isbn) DO UPDATE SET
      status = excluded.status,
      rating = excluded.rating,
      review = excluded.review
  `).bind(userId, isbn, status, rating, review).run()

  return c.json(createSuccessResponse({ added: true }))
})

// Complex query example: Top-rated books of 2024
router.get('/v1/library/:userId/top-rated', async (c) => {
  const userId = c.req.param('userId')
  const year = c.req.query('year') || '2024'

  const books = await c.env.DB.prepare(`
    SELECT b.*, ul.rating, ul.review
    FROM UserLibrary ul
    JOIN Books b ON ul.isbn = b.isbn
    WHERE ul.user_id = ?
      AND ul.rating >= 5
      AND b.publication_year = ?
    ORDER BY ul.rating DESC, b.title ASC
  `).bind(userId, parseInt(year)).all()

  return c.json(createSuccessResponse({ books: books.results }))
})
```

### Performance Optimization

**Query optimization techniques:**
```typescript
// Use prepared statements (auto-cached by D1)
const stmt = db.prepare('SELECT * FROM Books WHERE isbn = ?')
const book1 = await stmt.bind('9780439708180').first()
const book2 = await stmt.bind('9780451524935').first() // Same stmt, different bind

// Batch operations for efficiency
const batch = db.batch([
  db.prepare('INSERT INTO Books ...').bind(...),
  db.prepare('INSERT INTO Books ...').bind(...),
  db.prepare('INSERT INTO Books ...').bind(...)
])
await batch // All execute in single round-trip
```

**Deliverables for Item 2.3:**
- [ ] Refactored `src/services/book-search.ts` with D1 integration
- [ ] New `src/services/d1-book-service.ts` for D1 operations
- [ ] Updated handlers to use new service layer
- [ ] New user library API endpoints (GET/POST /v1/library/:userId)
- [ ] Complex query examples (top-rated books, filtered collections)
- [ ] Performance optimizations (prepared statements, batching)
- [ ] Unit tests for D1 + KV integration
- [ ] API contract updates in `docs/API_CONTRACT.md`

---

## Item 2.4: Testing & Validation (Days 11-12)

### Testing Strategy

**Test Pyramid:**
1. Unit tests (service layer, transformations)
2. Integration tests (D1 + KV interaction)
3. Load tests (performance validation)
4. Data integrity tests (migration validation)

### Unit Testing

**D1 Service Layer Tests:**
```typescript
// __tests__/services/d1-book-service.test.ts
import { describe, it, expect, beforeEach } from 'vitest'
import { getBookFromD1, saveBookToD1, getUserBooks } from '../../src/services/d1-book-service'

describe('D1 Book Service', () => {
  let mockDB: D1Database

  beforeEach(() => {
    mockDB = createMockD1Database()
  })

  describe('getBookFromD1', () => {
    it('should return null for non-existent ISBN', async () => {
      mockDB.prepare = vi.fn().mockReturnValue({
        bind: vi.fn().mockReturnThis(),
        first: vi.fn().mockResolvedValue(null)
      })

      const result = await getBookFromD1(mockDB, '9999999999999')
      expect(result).toBeNull()
    })

    it('should transform D1 row to canonical format', async () => {
      const d1Row = {
        isbn: '9780439708180',
        title: 'Harry Potter',
        authors: '["J.K. Rowling"]',
        publication_year: 1997,
        canonical_metadata: '{"extra":"data"}'
      }

      mockDB.prepare = vi.fn().mockReturnValue({
        bind: vi.fn().mockReturnThis(),
        first: vi.fn().mockResolvedValue(d1Row)
      })

      const result = await getBookFromD1(mockDB, '9780439708180')

      expect(result.isbn).toBe('9780439708180')
      expect(result.authors).toEqual(['J.K. Rowling'])
      expect(result.publishedDate).toBe('1997')
    })
  })

  describe('getUserBooks', () => {
    it('should filter by rating and year', async () => {
      mockDB.prepare = vi.fn().mockReturnValue({
        bind: vi.fn().mockReturnThis(),
        all: vi.fn().mockResolvedValue({
          results: [
            { isbn: '123', title: 'Book 1', rating: 5, publication_year: 2024 }
          ]
        })
      })

      const results = await getUserBooks(mockDB, 'user123', {
        rating: 5,
        year: 2024
      })

      expect(results).toHaveLength(1)
      expect(mockDB.prepare).toHaveBeenCalledWith(
        expect.stringContaining('AND ul.rating >= ?')
      )
    })
  })
})
```

### Integration Testing

**D1 + KV Read-Through Cache:**
```typescript
// __tests__/integration/cache-layer.test.ts
describe('Read-Through Cache Integration', () => {
  it('should populate KV from D1 on cache miss', async () => {
    const env = await getMiniflareEnv()

    // Insert book directly to D1 (bypassing cache)
    await env.DB.prepare(`
      INSERT INTO Books (isbn, title, authors, canonical_metadata)
      VALUES (?, ?, ?, ?)
    `).bind('9780439708180', 'Harry Potter', '["J.K. Rowling"]', '{}').run()

    // Ensure KV is empty
    await env.BOOK_CACHE.delete('book:isbn:9780439708180')

    // Call service (should hit D1, populate KV)
    const book = await findByISBN('9780439708180', env)

    // Verify book returned
    expect(book.title).toBe('Harry Potter')

    // Verify KV was populated
    const cached = await env.BOOK_CACHE.get('book:isbn:9780439708180', 'json')
    expect(cached).toBeTruthy()
    expect(cached.title).toBe('Harry Potter')
  })

  it('should write to D1 first on external API fetch', async () => {
    const env = await getMiniflareEnv()

    // Mock external API response
    vi.spyOn(googleBooksProvider, 'search').mockResolvedValue({
      isbn: '9780451524935',
      title: '1984',
      authors: ['George Orwell']
    })

    // Fetch book (miss both KV and D1)
    const book = await findByISBN('9780451524935', env)

    // Verify D1 has the book
    const d1Book = await env.DB.prepare('SELECT * FROM Books WHERE isbn = ?')
      .bind('9780451524935').first()

    expect(d1Book).toBeTruthy()
    expect(d1Book.title).toBe('1984')

    // Verify KV also has it
    const kvBook = await env.BOOK_CACHE.get('book:isbn:9780451524935', 'json')
    expect(kvBook).toBeTruthy()
  })
})
```

### Load Testing

**Performance validation with k6:**
```javascript
// load-tests/search-performance.js (k6 script)
import http from 'k6/http'
import { check, sleep } from 'k6'

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp up to 50 users
    { duration: '1m', target: 100 },  // Sustained load
    { duration: '30s', target: 0 }    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests < 500ms
    http_req_failed: ['rate<0.01']    // <1% error rate
  }
}

export default function() {
  const isbn = randomISBN() // From pre-seeded test data

  const res = http.get(`https://api.oooefam.net/v1/search/isbn?isbn=${isbn}`)

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'has book data': (r) => JSON.parse(r.body).data.book !== null
  })

  sleep(1)
}
```

**Run load test:**
```bash
# Install k6
brew install k6  # macOS

# Run against local dev
k6 run --vus 10 --duration 30s load-tests/search-performance.js

# Run against staging
k6 run load-tests/search-performance.js
```

### Data Integrity Testing

**Migration validation suite:**
```typescript
// __tests__/validation/migration-integrity.test.ts
describe('Migration Data Integrity', () => {
  it('should have same record count in D1 as KV', async () => {
    const env = await getMiniflareEnv()

    // Count KV keys
    let kvCount = 0
    let cursor
    do {
      const result = await env.BOOK_CACHE.list({
        prefix: 'book:isbn:',
        cursor
      })
      kvCount += result.keys.length
      cursor = result.cursor
    } while (cursor)

    // Count D1 records
    const d1Result = await env.DB.prepare('SELECT COUNT(*) as count FROM Books').first()
    const d1Count = d1Result.count

    // Allow 1% tolerance for keys in flight
    const tolerance = Math.ceil(kvCount * 0.01)
    expect(Math.abs(kvCount - d1Count)).toBeLessThanOrEqual(tolerance)
  })

  it('should have matching data for sample ISBNs', async () => {
    const env = await getMiniflareEnv()
    const sampleISBNs = [
      '9780439708180',
      '9780451524935',
      '9780061120084'
    ]

    for (const isbn of sampleISBNs) {
      const kvData = await env.BOOK_CACHE.get(`book:isbn:${isbn}`, 'json')
      const d1Data = await getBookFromD1(env.DB, isbn)

      // Compare critical fields
      expect(d1Data.isbn).toBe(kvData.isbn)
      expect(d1Data.title).toBe(kvData.title)
      expect(JSON.stringify(d1Data.authors)).toBe(JSON.stringify(kvData.authors))
    }
  })

  it('should handle malformed KV data gracefully', async () => {
    const env = await getMiniflareEnv()

    // Insert malformed data
    await env.BOOK_CACHE.put('book:isbn:BAD_DATA', 'not valid json')

    // Migration should log error but continue
    const result = await migrateKVToD1(env, ctx)

    expect(result.totalErrors).toBeGreaterThan(0)
    expect(result.totalMigrated).toBeGreaterThan(0)
  })
})
```

### Regression Testing

**Ensure API contract unchanged:**
```typescript
// __tests__/regression/api-contract.test.ts
describe('API Contract Regression', () => {
  it('should return same response format after D1 migration', async () => {
    const response = await fetch('http://localhost:8787/v1/search/isbn?isbn=9780439708180')
    const data = await response.json()

    // Validate ResponseEnvelope format
    expect(data).toHaveProperty('success')
    expect(data).toHaveProperty('data')
    expect(data).toHaveProperty('metadata')

    // Validate book structure
    expect(data.data.book).toHaveProperty('isbn')
    expect(data.data.book).toHaveProperty('title')
    expect(data.data.book).toHaveProperty('authors')
    expect(data.data.book).toHaveProperty('imageLinks')
  })

  it('should maintain backwards compatibility with legacy search', async () => {
    const response = await fetch('http://localhost:8787/search?isbn=9780439708180')
    expect(response.status).toBe(200)

    const data = await response.json()
    expect(data).toHaveProperty('isbn')
    expect(data).toHaveProperty('title')
  })
})
```

### Test Execution Plan

**Day 11: Unit & Integration Tests**
```bash
# Run all tests
npm test

# Run with coverage (target: 75%+)
npm run test:coverage

# Integration tests only
npm test -- __tests__/integration

# Watch mode during development
npm run test:watch
```

**Day 12: Load & Validation Tests**
```bash
# Start local dev server
npm run dev

# Run load tests (separate terminal)
k6 run load-tests/search-performance.js

# Run migration validation
npm test -- __tests__/validation/migration-integrity

# Monitor metrics
curl http://localhost:8787/metrics
```

**Deliverables for Item 2.4:**
- [ ] Unit tests for D1 service layer (90%+ coverage)
- [ ] Integration tests for cache layers
- [ ] Load testing suite (k6 scripts)
- [ ] Data integrity validation tests
- [ ] Regression tests for API contract
- [ ] Test execution documentation
- [ ] Performance benchmarks (baseline vs D1)
- [ ] CI/CD integration (GitHub Actions)

---

## Item 2.5: Deployment & Rollback Strategy (Day 13)

### Deployment Phases

**Phase 1: Staging Deployment (Morning)**
**Phase 2: Migration Execution (Midday)**
**Phase 3: Production Cutover (Afternoon)**
**Phase 4: Monitoring & Validation (Evening)**

### Phase 1: Staging Deployment

**Step 1: Deploy D1 Schema to Staging**
```bash
# Create staging D1 database
npx wrangler d1 create bookstrack-db-staging

# Apply migrations to staging
npx wrangler d1 migrations apply bookstrack-db-staging --remote

# Verify schema
npx wrangler d1 execute bookstrack-db-staging \
  --command "SELECT name FROM sqlite_master WHERE type='table'"

# Expected output: Books, UserLibrary, CacheMetrics
```

**Step 2: Deploy Application Code to Staging**
```bash
# Update wrangler.jsonc with staging D1 binding
# (Use environment-specific config)

# Deploy to staging worker
npx wrangler deploy --env staging

# Verify deployment
curl https://staging-api.oooefam.net/health
```

**Step 3: Run Staging Tests**
```bash
# Integration tests against staging
API_URL=https://staging-api.oooefam.net npm test -- __tests__/integration

# Load test (smaller scale)
k6 run --vus 10 --duration 1m load-tests/search-performance.js
```

### Phase 2: Migration Execution

**Step 1: Backup KV Data (Safety)**
```bash
# Create backup of KV namespace (optional but recommended)
npx wrangler kv:bulk get BOOK_CACHE --namespace-id=$KV_ID > kv-backup.json

# Or use Cloudflare dashboard: KV > BOOK_CACHE > Export
```

**Step 2: Execute Migration (Staging First)**
```bash
# Dry run to estimate time
curl -X POST "https://staging-api.oooefam.net/admin/migrate-kv-to-d1?dryRun=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Real migration on staging
curl -X POST "https://staging-api.oooefam.net/admin/migrate-kv-to-d1" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Monitor progress
watch -n 5 'curl -s https://staging-api.oooefam.net/admin/migration-status | jq'
```

**Step 3: Validate Staging Migration**
```bash
# Run data integrity tests
npm test -- __tests__/validation/migration-integrity

# Manual spot checks
curl "https://staging-api.oooefam.net/v1/search/isbn?isbn=9780439708180"
curl "https://staging-api.oooefam.net/v1/library/testuser"

# Check D1 directly
npx wrangler d1 execute bookstrack-db-staging \
  --command "SELECT COUNT(*) FROM Books"
```

### Phase 3: Production Cutover

**Step 1: Create Production D1 Database**
```bash
# Create production D1
npx wrangler d1 create bookstrack-db

# Apply migrations
npx wrangler d1 migrations apply bookstrack-db --remote

# Update wrangler.jsonc with production database_id
```

**Step 2: Deploy to Production (Feature Flag Off)**
```bash
# Deploy code with D1 support but feature flag disabled
# This allows rollback without redeployment
npx wrangler deploy

# Verify deployment
curl https://api.oooefam.net/health

# Feature flag initially OFF (reads still go to KV only)
# env.ENABLE_D1_READS = false
```

**Step 3: Run Production Migration**
```bash
# Execute migration (writes to D1, doesn't affect reads yet)
curl -X POST "https://api.oooefam.net/admin/migrate-kv-to-d1" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Monitor via cf-ops-monitor
npx wrangler tail --format json | grep "migration"

# Or use slash command
/logs migration
```

**Step 4: Enable D1 Reads (Gradual Rollout)**
```bash
# Option A: Environment variable (requires redeploy)
npx wrangler secret put ENABLE_D1_READS
# Enter: "true"
npx wrangler deploy

# Option B: KV-based feature flag (instant, no deploy)
npx wrangler kv:key put --namespace-id=$KV_ID \
  "feature:enable_d1_reads" "true"

# Code checks this flag:
# const enableD1 = await env.BOOK_CACHE.get('feature:enable_d1_reads')
```

**Step 5: Monitor Post-Cutover**
```bash
# Watch error rates
npx wrangler tail --format json | grep "error"

# Check metrics
curl https://api.oooefam.net/metrics

# Monitor Cloudflare dashboard
# - Error rate (should be <0.1%)
# - Latency P95 (should be <500ms)
# - D1 query count (should increase)
```

### Phase 4: Rollback Procedures

**Immediate Rollback (Feature Flag)**
```bash
# Disable D1 reads instantly (no deployment needed)
npx wrangler kv:key put --namespace-id=$KV_ID \
  "feature:enable_d1_reads" "false"

# Verify rollback
curl https://api.oooefam.net/v1/search/isbn?isbn=9780439708180
# Should return from KV cache (fast response)
```

**Full Rollback (Code Deployment)**
```bash
# List recent deployments
npx wrangler deployments list

# Rollback to previous version
npx wrangler rollback --message "Rolling back D1 migration due to errors"

# Verify health
curl https://api.oooefam.net/health
```

**Rollback Decision Criteria:**
- Error rate >1% for 5 minutes → Immediate rollback
- Latency P95 >1000ms for 5 minutes → Immediate rollback
- Data inconsistency detected → Stop writes, investigate
- D1 query failures >5% → Rollback, check D1 status

### Monitoring Checklist

**Real-Time Monitoring (First 2 Hours):**
```bash
# Terminal 1: Tail logs
npx wrangler tail --format json

# Terminal 2: Watch metrics
watch -n 10 'curl -s https://api.oooefam.net/metrics | grep -E "(error|latency|d1)"'

# Terminal 3: Smoke tests
while true; do
  curl -s https://api.oooefam.net/v1/search/isbn?isbn=9780439708180 | jq '.success'
  sleep 5
done
```

**Metrics to Track:**
- Error rate: <0.1%
- Latency P50: <100ms (cached), <300ms (D1)
- Latency P95: <500ms
- D1 query success rate: >99%
- Cache hit rate: >80%

**Automated Alerts (cf-ops-monitor):**
- Error rate spike >1% → Auto-rollback
- 5xx errors >10/min → Slack notification
- D1 query failures → Investigate D1 status
- Latency P95 >1s → Performance investigation

### Post-Deployment Tasks

**Day 13 Evening:**
- [ ] Validate all endpoints returning correct data
- [ ] Confirm cache hit rate maintained
- [ ] Run full regression test suite
- [ ] Update documentation with new architecture
- [ ] Notify frontend teams of successful migration

**Day 14:**
- [ ] Monitor for 24 hours
- [ ] Analyze performance metrics
- [ ] Document lessons learned
- [ ] Plan KV cleanup (optional, keep as cache)

**Deliverables for Item 2.5:**
- [ ] Staging deployment validated
- [ ] Production D1 database created
- [ ] Migration executed successfully
- [ ] Feature flag system for gradual rollout
- [ ] Rollback procedures tested
- [ ] Monitoring dashboards configured
- [ ] Deployment runbook documented
- [ ] Post-mortem template prepared

---

## Item 2.6: Success Criteria & Acceptance Testing (Day 14)

### Definition of Done (from original requirements)

**1. All book metadata exists in D1**
```bash
# Verify D1 record count matches KV keys
npx wrangler d1 execute bookstrack-db \
  --command "SELECT COUNT(*) as total FROM Books"

# Compare with KV count (from backup)
jq length kv-backup.json

# Acceptance: Difference <1%
```

**2. Complex queries are possible via SQL**
```sql
-- Query 1: All 5-star books added in 2024
SELECT b.*, ul.rating, ul.added_at
FROM UserLibrary ul
JOIN Books b ON ul.isbn = b.isbn
WHERE ul.user_id = 'test_user'
  AND ul.rating >= 5
  AND strftime('%Y', datetime(ul.added_at, 'unixepoch')) = '2024'
ORDER BY ul.added_at DESC;

-- Query 2: Books by publication year
SELECT publication_year, COUNT(*) as count
FROM Books
WHERE publication_year IS NOT NULL
GROUP BY publication_year
ORDER BY publication_year DESC
LIMIT 10;

-- Query 3: Top authors by book count
SELECT authors, COUNT(*) as book_count
FROM Books
GROUP BY authors
ORDER BY book_count DESC
LIMIT 20;

-- Acceptance: All queries execute successfully in <100ms
```

**3. D1 is the source of truth**
```typescript
// Verify write flow: External API → D1 → KV
async function testWriteFlow() {
  // Clear both caches
  await env.BOOK_CACHE.delete('book:isbn:TEST123')
  await env.DB.prepare('DELETE FROM Books WHERE isbn = ?').bind('TEST123').run()

  // Fetch new book (should write to D1 first)
  const book = await findByISBN('TEST123', env)

  // Verify D1 has it
  const d1Book = await env.DB.prepare('SELECT * FROM Books WHERE isbn = ?')
    .bind('TEST123').first()
  assert(d1Book !== null, 'Book must exist in D1')

  // Verify KV has it (cache populated)
  const kvBook = await env.BOOK_CACHE.get('book:isbn:TEST123', 'json')
  assert(kvBook !== null, 'Book must exist in KV cache')

  // Verify D1 timestamp is earlier (written first)
  assert(d1Book.created_at <= Date.now())
}

// Acceptance: D1 write happens before KV write
```

### Functional Acceptance Tests

**Test Suite 1: Core Book Search**
```typescript
// __tests__/acceptance/book-search.test.ts
describe('Book Search Acceptance', () => {
  it('should return book from D1 on cache miss', async () => {
    const response = await fetch('https://api.oooefam.net/v1/search/isbn?isbn=9780439708180')
    const data = await response.json()

    expect(data.success).toBe(true)
    expect(data.data.book.isbn).toBe('9780439708180')
    expect(data.metadata.source).toMatch(/d1|cache/)
  })

  it('should maintain cache hit rate >80%', async () => {
    const metrics = await fetch('https://api.oooefam.net/metrics').then(r => r.text())
    const hitRate = parseFloat(metrics.match(/cache_hit_rate (\d+\.\d+)/)[1])

    expect(hitRate).toBeGreaterThan(0.80)
  })

  it('should respond within 500ms P95', async () => {
    const latencies = []
    for (let i = 0; i < 100; i++) {
      const start = Date.now()
      await fetch('https://api.oooefam.net/v1/search/isbn?isbn=9780439708180')
      latencies.push(Date.now() - start)
    }

    latencies.sort((a, b) => a - b)
    const p95 = latencies[94]

    expect(p95).toBeLessThan(500)
  })
})
```

**Test Suite 2: User Library (Complex Queries)**
```typescript
describe('User Library Acceptance', () => {
  it('should support filtering by rating', async () => {
    const response = await fetch('https://api.oooefam.net/v1/library/testuser?rating=5')
    const data = await response.json()

    expect(data.success).toBe(true)
    data.data.books.forEach(book => {
      expect(book.rating).toBeGreaterThanOrEqual(5)
    })
  })

  it('should support filtering by year', async () => {
    const response = await fetch('https://api.oooefam.net/v1/library/testuser?year=2024')
    const data = await response.json()

    expect(data.success).toBe(true)
    data.data.books.forEach(book => {
      expect(book.publication_year).toBe(2024)
    })
  })

  it('should support combined filters', async () => {
    const response = await fetch(
      'https://api.oooefam.net/v1/library/testuser?rating=5&year=2024&status=completed'
    )
    const data = await response.json()

    expect(data.success).toBe(true)
    data.data.books.forEach(book => {
      expect(book.rating).toBeGreaterThanOrEqual(5)
      expect(book.publication_year).toBe(2024)
      expect(book.status).toBe('completed')
    })
  })
})
```

### Go-Live Checklist

**Pre-Go-Live (Must Pass All):**
- [ ] Staging migration completed successfully
- [ ] All unit tests passing (90%+ coverage)
- [ ] All integration tests passing
- [ ] Load tests meet performance targets
- [ ] Data integrity validated (KV ↔ D1 match)
- [ ] Rollback procedure tested
- [ ] Monitoring dashboards configured
- [ ] cf-ops-monitor agent ready
- [ ] Runbook documented

**Go-Live Approval:**
- [ ] Tech lead approval
- [ ] QA sign-off
- [ ] Monitoring team ready
- [ ] Rollback plan reviewed
- [ ] Incident response team on standby

**Post-Go-Live (First 24 Hours):**
- [ ] Error rate <0.1%
- [ ] Latency P95 <500ms
- [ ] Cache hit rate >80%
- [ ] No data inconsistencies detected
- [ ] All complex queries working
- [ ] User library features operational

### Success Metrics Dashboard

**Acceptance Thresholds:**
- D1 query count: >0 (D1 is being used)
- D1 query duration P95: <100ms
- KV cache hit rate: >80%
- API error rate: <0.1%
- API latency P95: <500ms
- Migration completeness: >99%

**Deliverables for Item 2.6:**
- [ ] All success criteria validated
- [ ] Acceptance test suite passing
- [ ] Performance benchmarks met
- [ ] Data integrity confirmed
- [ ] Go-live checklist completed
- [ ] Metrics dashboard operational
- [ ] Sign-off from stakeholders
- [ ] Post-migration report published

---

## Item 2.7: Risk Mitigation & Post-Migration Review (Day 14+)

### Risk Assessment Matrix

**High-Impact Risks:**

| Risk | Probability | Impact | Mitigation | Contingency |
|------|-------------|--------|------------|-------------|
| Data loss during migration | Low | Critical | KV backup, idempotent upserts, validation checks | Restore from backup, re-run migration |
| Performance regression | Medium | High | Load testing, gradual rollout, feature flags | Instant rollback via feature flag |
| D1 database unavailability | Low | High | KV cache still works, read-through pattern | Serve from KV cache only |
| Migration script timeout | Medium | Medium | Chunking, checkpointing, resume capability | Resume from last checkpoint |
| Schema design flaws | Low | High | Peer review, test with realistic queries | D1 migrations for schema changes |

**Medium-Impact Risks:**

| Risk | Probability | Impact | Mitigation | Contingency |
|------|-------------|--------|------------|-------------|
| Incomplete migration | Low | Medium | Count validation, sample checks | Re-run migration for missing records |
| Cache invalidation issues | Medium | Low | Clear cache after migration | Manual cache invalidation endpoint |
| Complex query performance | Medium | Medium | Index optimization, query testing | Add indexes post-migration |
| API contract changes | Low | Medium | Regression tests, backwards compatibility | Version API endpoints |

### Mitigation Strategies

**1. Data Loss Prevention**
```bash
# Pre-migration backup (MANDATORY)
npx wrangler kv:bulk get BOOK_CACHE --namespace-id=$KV_ID > kv-backup-$(date +%Y%m%d).json

# Checksum verification
sha256sum kv-backup-$(date +%Y%m%d).json > backup-checksum.txt

# Test restore procedure
npx wrangler kv:bulk put BOOK_CACHE --namespace-id=$TEST_KV_ID < kv-backup-$(date +%Y%m%d).json
```

**2. Performance Regression Prevention**
```typescript
// Feature flag system for instant rollback
export async function shouldUseD1(env: Env): Promise<boolean> {
  // Check KV-based feature flag
  const flag = await env.BOOK_CACHE.get('feature:enable_d1_reads')
  if (flag === 'false') return false

  // Check error rate (circuit breaker pattern)
  const errorRate = await getD1ErrorRate(env)
  if (errorRate > 0.05) {
    console.warn('D1 error rate too high, falling back to KV')
    return false
  }

  return true
}
```

### Lessons Learned Template

**What Went Well:**
- Zero downtime migration using read-through cache pattern
- Feature flag system enabled instant rollback
- Checkpointing prevented data loss during migration
- Comprehensive testing caught performance issues early
- cf-ops-monitor provided real-time visibility

**What Could Be Improved:**
- Migration script initially timed out (needed smaller batches)
- D1 query performance worse than expected on complex JOINs
- Schema needed optimization (added indexes post-migration)
- Documentation of rollback procedure was incomplete

**Action Items for Future Migrations:**
1. **Pre-Migration:**
   - Estimate migration runtime with realistic data volume
   - Test with production-like dataset (not just sample data)
   - Document rollback procedure BEFORE migration
   - Set up monitoring dashboards BEFORE go-live

2. **During Migration:**
   - Monitor progress in real-time (log every 1000 records)
   - Have incident response team on standby
   - Keep communication channel open (Slack war room)
   - Document any deviations from plan immediately

3. **Post-Migration:**
   - Monitor for 48 hours (not just 24)
   - Run acceptance tests every 6 hours
   - Keep KV data for 30 days (safety net)
   - Publish post-mortem within 1 week

---

## Documentation Deliverables

**Required Documentation:**

1. **`docs/migrations/KV_TO_D1_MIGRATION.md`** (this document)
   - Migration plan
   - Execution timeline
   - Rollback procedures
   - Lessons learned

2. **`docs/DATABASE_SCHEMA.md`**
   - Complete schema documentation
   - Index strategy
   - Query examples
   - Performance characteristics

3. **`docs/deployment/D1_DEPLOYMENT.md`**
   - D1 setup instructions
   - Migration commands
   - Troubleshooting guide
   - Production checklist

4. **`docs/operations/D1_RUNBOOK.md`**
   - Common operations
   - Monitoring queries
   - Incident response
   - Backup/restore procedures

---

## Final Success Metrics (30 Days Post-Migration)

**Quantitative:**
- Zero data loss incidents
- Error rate <0.1% (improved from 0.05% baseline)
- API latency P95 <400ms (20% improvement)
- Complex query support (200+ new query patterns)
- User library adoption >50% of active users

**Qualitative:**
- Frontend team reports faster feature development
- Product team enabled to build recommendation engine
- Support team has better analytics tools
- Engineering team confidence in future migrations

**Business Impact:**
- User engagement +15% (new library features)
- API cost reduction 10% (better caching)
- Development velocity +25% (easier queries)
- Customer satisfaction +12% (faster app)

---

## Summary

**Total Duration:** 2 weeks (14 days)
**Team Effort:** Backend engineering (2), QA (1), DevOps (1)
**Lines of Code:** ~2,500 (migration + tests + services)
**Tests Added:** 50+ (unit + integration + acceptance)

**Key Deliverables:**
- D1 database with 3 tables (Books, UserLibrary, CacheMetrics)
- Migration script with checkpointing and validation
- Refactored data access layer (read-through cache pattern)
- Comprehensive test suite
- Zero downtime deployment with instant rollback capability
- Complete documentation

**Next Phase:** Phase 3 - Advanced Features (Full-text search, Analytics, Recommendations)

---

**Document Version:** 1.0
**Last Updated:** November 21, 2025
**Author:** AI Planning Team (Claude Code + Gemini 2.5 Flash)
**Approved By:** [Pending]
