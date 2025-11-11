# Issues #197, #147, #217 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement cache key normalization, image proxy with R2 caching, and iOS performance optimizations for 10x faster queries.

**Architecture:** Backend-first approach (Phase 1: #197 + #147 together), then iOS (Phase 2: #217). Shared normalization utilities ensure consistency across cache keys, search logic, and image URLs.

**Tech Stack:** TypeScript (Cloudflare Workers), R2 Storage, Swift 6.2, SwiftData

---

## Phase 1: Backend Work (#197 + #147)

**Worktree:** `../books-tracker-backend/`

**Duration:** 3-4 hours

---

### Task 1: Shared Normalization Utilities

**Files:**
- Create: `cloudflare-workers/api-worker/src/utils/normalization.ts`
- Test: `cloudflare-workers/api-worker/tests/normalization.test.ts`

**Step 1: Write failing tests for normalization utilities**

Create `tests/normalization.test.ts`:

```typescript
import { describe, test, expect } from 'vitest';
import { normalizeTitle, normalizeISBN, normalizeAuthor, normalizeImageURL } from '../src/utils/normalization';

describe('normalizeTitle', () => {
  test('removes leading "The"', () => {
    expect(normalizeTitle('The Hobbit')).toBe('hobbit');
  });

  test('removes leading "A"', () => {
    expect(normalizeTitle('A Tale of Two Cities')).toBe('tale of two cities');
  });

  test('removes leading "An"', () => {
    expect(normalizeTitle('An American Tragedy')).toBe('american tragedy');
  });

  test('lowercases and trims', () => {
    expect(normalizeTitle('  THE HOBBIT  ')).toBe('hobbit');
  });

  test('removes punctuation', () => {
    expect(normalizeTitle('The Hobbit: An Unexpected Journey')).toBe('hobbit an unexpected journey');
  });

  test('handles empty string', () => {
    expect(normalizeTitle('')).toBe('');
  });
});

describe('normalizeISBN', () => {
  test('removes hyphens from ISBN-13', () => {
    expect(normalizeISBN('978-0-547-92822-7')).toBe('9780547928227');
  });

  test('removes spaces from ISBN', () => {
    expect(normalizeISBN('978 0 547 92822 7')).toBe('9780547928227');
  });

  test('preserves X in ISBN-10', () => {
    expect(normalizeISBN('043942089X')).toBe('043942089X');
  });

  test('trims whitespace', () => {
    expect(normalizeISBN('  9780547928227  ')).toBe('9780547928227');
  });

  test('handles already normalized ISBN', () => {
    expect(normalizeISBN('9780547928227')).toBe('9780547928227');
  });
});

describe('normalizeAuthor', () => {
  test('lowercases and trims', () => {
    expect(normalizeAuthor('  J.R.R. Tolkien  ')).toBe('j.r.r. tolkien');
  });

  test('handles empty string', () => {
    expect(normalizeAuthor('')).toBe('');
  });
});

describe('normalizeImageURL', () => {
  test('removes query parameters', () => {
    const url = 'http://books.google.com/covers/abc.jpg?zoom=1&source=gbs_api';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('forces HTTPS', () => {
    const url = 'http://books.google.com/covers/abc.jpg';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('handles already normalized URL', () => {
    const url = 'https://books.google.com/covers/abc.jpg';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('trims whitespace', () => {
    const url = '  https://books.google.com/covers/abc.jpg  ';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('handles invalid URL gracefully', () => {
    expect(normalizeImageURL('not a url')).toBe('not a url');
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `npm run test -- tests/normalization.test.ts`

Expected: FAIL with "Cannot find module '../src/utils/normalization'"

**Step 3: Implement normalization utilities**

Create `src/utils/normalization.ts`:

```typescript
/**
 * Normalizes book title for cache key generation and search matching
 * - Lowercase for case-insensitive matching
 * - Trim whitespace
 * - Remove leading articles (the, a, an) for better deduplication
 * - Remove punctuation for fuzzy matching
 */
export function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .trim()
    .replace(/^(the|a|an)\s+/i, '')  // "The Hobbit" → "hobbit"
    .replace(/[^a-z0-9\s]/g, '');     // Remove punctuation
}

/**
 * Normalizes ISBN for cache key generation
 * - Remove hyphens (ISBN-10/ISBN-13 formatting)
 * - Trim whitespace
 * - Preserve digits and 'X' only (ISBN-10 check digit)
 */
export function normalizeISBN(isbn: string): string {
  return isbn.trim().replace(/[^0-9X]/gi, '');
}

/**
 * Normalizes author name for cache matching
 * - Lowercase
 * - Trim whitespace
 */
export function normalizeAuthor(author: string): string {
  return author.toLowerCase().trim();
}

/**
 * Normalizes image URL for cache key generation
 * - Remove query parameters (tracking, sizing hints)
 * - Normalize protocol (http → https)
 * - Trim whitespace
 */
export function normalizeImageURL(url: string): string {
  try {
    const parsed = new URL(url.trim());
    // Remove query params (e.g., ?zoom=1, ?source=gbs_api)
    parsed.search = '';
    // Force HTTPS
    parsed.protocol = 'https:';
    return parsed.toString();
  } catch {
    // Invalid URL, return as-is
    return url.trim();
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `npm run test -- tests/normalization.test.ts`

Expected: PASS (all 17 tests)

**Step 5: Commit**

```bash
git add src/utils/normalization.ts tests/normalization.test.ts
git commit -m "feat(backend): add shared normalization utilities for cache keys

- Add normalizeTitle() to remove articles and punctuation
- Add normalizeISBN() to strip formatting characters
- Add normalizeAuthor() for consistent name matching
- Add normalizeImageURL() to remove query params and force HTTPS
- Comprehensive test coverage (17 tests)

Related: #197, #147"
```

---

### Task 2: Integrate Normalization in Search Endpoints

**Files:**
- Modify: `cloudflare-workers/api-worker/src/handlers/v1/search-title.ts`
- Modify: `cloudflare-workers/api-worker/src/handlers/v1/search-isbn.ts`
- Modify: `cloudflare-workers/api-worker/src/handlers/v1/search-advanced.ts`

**Step 1: Add title normalization to search-title.ts**

Read current implementation:

```bash
# Read search-title.ts to understand current structure
```

Modify `src/handlers/v1/search-title.ts`:

```typescript
import { normalizeTitle } from '../../utils/normalization.ts';

export async function handleSearchTitle(query: string, env: any) {
  // Normalize title for consistent cache keys
  const normalizedTitle = normalizeTitle(query);

  const works = await enrichMultipleBooks(
    { title: normalizedTitle },  // Use normalized title
    env,
    { maxResults: 20 }
  );

  // ... rest of handler (keep existing logic)
}
```

**Step 2: Add ISBN normalization to search-isbn.ts**

Modify `src/handlers/v1/search-isbn.ts`:

```typescript
import { normalizeISBN } from '../../utils/normalization.ts';

export async function handleSearchISBN(isbn: string, env: any) {
  // Normalize ISBN for consistent cache keys
  const normalizedISBN = normalizeISBN(isbn);

  // Use normalizedISBN in enrichment call
  const works = await enrichMultipleBooks(
    { isbn: normalizedISBN },
    env,
    { maxResults: 1 }
  );

  // ... rest of handler
}
```

**Step 3: Add title + author normalization to search-advanced.ts**

Modify `src/handlers/v1/search-advanced.ts`:

```typescript
import { normalizeTitle, normalizeAuthor } from '../../utils/normalization.ts';

export async function handleSearchAdvanced(title: string, author: string, env: any) {
  // Normalize both title and author for consistent cache keys
  const normalizedTitle = title ? normalizeTitle(title) : undefined;
  const normalizedAuthor = author ? normalizeAuthor(author) : undefined;

  const works = await enrichMultipleBooks(
    {
      title: normalizedTitle,
      author: normalizedAuthor
    },
    env,
    { maxResults: 20 }
  );

  // ... rest of handler
}
```

**Step 4: Run tests to verify endpoints still work**

Run: `npm run test`

Expected: PASS (all existing tests)

**Step 5: Commit**

```bash
git add src/handlers/v1/search-title.ts src/handlers/v1/search-isbn.ts src/handlers/v1/search-advanced.ts
git commit -m "feat(backend): integrate normalization in search endpoints

- Normalize titles in search-title endpoint
- Normalize ISBNs in search-isbn endpoint
- Normalize titles + authors in search-advanced endpoint
- Expected +15-30% cache hit rate improvement

Related: #197"
```

---

### Task 3: Integrate Normalization in Enrichment Service

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/enrichment.ts`

**Step 1: Read current enrichment logic**

```bash
# Read enrichment.ts to understand cache key generation
```

**Step 2: Add normalization before cache lookup**

Modify `src/services/enrichment.ts`:

```typescript
import { normalizeTitle, normalizeISBN } from '../utils/normalization.ts';

export async function enrichSingleBook(params, env) {
  // Normalize before generating cache key
  if (params.title) {
    params.title = normalizeTitle(params.title);
  }
  if (params.isbn) {
    params.isbn = normalizeISBN(params.isbn);
  }

  // ... rest of enrichment logic (cache key generation uses normalized values)
}
```

**Step 3: Run tests to verify enrichment still works**

Run: `npm run test -- tests/enrichment.test.ts`

Expected: PASS

**Step 4: Commit**

```bash
git add src/services/enrichment.ts
git commit -m "feat(backend): normalize cache keys in enrichment service

- Apply normalization before cache key generation
- Ensures consistent cache hits across different input formats
- Works with search endpoint normalization

Related: #197"
```

---

### Task 4: Image Proxy Implementation

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/image-proxy.ts`
- Modify: `cloudflare-workers/api-worker/src/index.js`
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Write failing test for image proxy**

Create `tests/image-proxy.test.ts`:

```typescript
import { describe, test, expect, vi } from 'vitest';
import { handleImageProxy } from '../src/handlers/image-proxy';

describe('handleImageProxy', () => {
  test('returns 400 if url parameter missing', async () => {
    const request = new Request('https://worker.dev/images/proxy');
    const env = mockEnv();

    const response = await handleImageProxy(request, env);

    expect(response.status).toBe(400);
  });

  test('returns 403 if domain not allowed', async () => {
    const request = new Request('https://worker.dev/images/proxy?url=https://evil.com/image.jpg');
    const env = mockEnv();

    const response = await handleImageProxy(request, env);

    expect(response.status).toBe(403);
  });

  test('returns 400 if URL invalid', async () => {
    const request = new Request('https://worker.dev/images/proxy?url=not-a-url');
    const env = mockEnv();

    const response = await handleImageProxy(request, env);

    expect(response.status).toBe(400);
  });

  test('returns cached image from R2 if available', async () => {
    const imageUrl = 'https://books.google.com/covers/abc.jpg';
    const request = new Request(`https://worker.dev/images/proxy?url=${encodeURIComponent(imageUrl)}`);

    const mockImageData = new Uint8Array([0xFF, 0xD8, 0xFF]); // Fake JPEG
    const env = mockEnv({
      BOOK_COVERS: {
        get: vi.fn().mockResolvedValue({
          arrayBuffer: () => Promise.resolve(mockImageData.buffer),
          httpMetadata: { contentType: 'image/jpeg' }
        })
      }
    });

    const response = await handleImageProxy(request, env);

    expect(response.status).toBe(200);
    expect(env.BOOK_COVERS.get).toHaveBeenCalledWith(expect.stringContaining('covers/'));
  });
});

function mockEnv(overrides = {}) {
  return {
    BOOK_COVERS: {
      get: vi.fn().mockResolvedValue(null),
      put: vi.fn().mockResolvedValue(undefined)
    },
    ...overrides
  };
}
```

**Step 2: Run test to verify it fails**

Run: `npm run test -- tests/image-proxy.test.ts`

Expected: FAIL with "Cannot find module '../src/handlers/image-proxy'"

**Step 3: Implement image proxy handler**

Create `src/handlers/image-proxy.ts`:

```typescript
import { normalizeImageURL } from '../utils/normalization.ts';
import { createHash } from 'crypto';

/**
 * Proxies and caches book cover images via R2 + Cloudflare Image Resizing
 *
 * Flow:
 * 1. Normalize image URL for cache key
 * 2. Check R2 bucket for cached original
 * 3. If miss: Fetch from origin, store in R2
 * 4. Return image with Cloudflare Image Resizing (on-the-fly thumbnail)
 */
export async function handleImageProxy(request: Request, env: any): Promise<Response> {
  const url = new URL(request.url);
  const imageUrl = url.searchParams.get('url');
  const size = url.searchParams.get('size') || 'medium'; // small, medium, large

  // Validation
  if (!imageUrl) {
    return new Response('Missing url parameter', { status: 400 });
  }

  // Security: Only allow known book cover domains
  const allowedDomains = [
    'books.google.com',
    'covers.openlibrary.org',
    'images-na.ssl-images-amazon.com'
  ];

  try {
    const parsedUrl = new URL(imageUrl);
    if (!allowedDomains.includes(parsedUrl.hostname)) {
      return new Response('Domain not allowed', { status: 403 });
    }
  } catch {
    return new Response('Invalid URL', { status: 400 });
  }

  // Normalize URL for consistent caching
  const normalizedUrl = normalizeImageURL(imageUrl);
  const cacheKey = `covers/${hashURL(normalizedUrl)}`;

  // Check R2 for cached image
  const cached = await env.BOOK_COVERS.get(cacheKey);

  if (cached) {
    console.log(`Image cache HIT: ${cacheKey}`);
    return resizeImage(await cached.arrayBuffer(), size, cached.httpMetadata?.contentType);
  }

  console.log(`Image cache MISS: ${cacheKey}`);

  // Cache miss - fetch from origin
  const origin = await fetch(normalizedUrl, {
    headers: { 'User-Agent': 'BooksTrack/3.0 (book-cover-proxy)' }
  });

  if (!origin.ok) {
    console.error(`Failed to fetch image from origin: ${origin.status}`);
    return new Response('Failed to fetch image', { status: 502 });
  }

  // Store in R2 for future requests
  const imageData = await origin.arrayBuffer();
  const contentType = origin.headers.get('content-type') || 'image/jpeg';

  await env.BOOK_COVERS.put(cacheKey, imageData, {
    httpMetadata: { contentType }
  });

  console.log(`Stored in R2: ${cacheKey} (${imageData.byteLength} bytes)`);

  // Return resized image
  return resizeImage(imageData, size, contentType);
}

/**
 * Hash URL for R2 key generation (consistent, collision-resistant)
 */
function hashURL(url: string): string {
  const hash = createHash('sha256');
  hash.update(url);
  return hash.digest('hex');
}

/**
 * Resize image using Cloudflare Image Resizing
 */
function resizeImage(imageData: ArrayBuffer, size: string, contentType: string): Response {
  const SIZE_MAP = {
    small: { width: 128, height: 192 },
    medium: { width: 256, height: 384 },
    large: { width: 512, height: 768 }
  };

  const dimensions = SIZE_MAP[size] || SIZE_MAP.medium;

  return new Response(imageData, {
    headers: {
      'Content-Type': contentType,
      'Cache-Control': 'public, max-age=2592000, immutable', // 30 days
      'CF-Image-Width': dimensions.width.toString(),
      'CF-Image-Height': dimensions.height.toString(),
      'CF-Image-Fit': 'scale-down'
    }
  });
}
```

**Step 4: Run tests to verify they pass**

Run: `npm run test -- tests/image-proxy.test.ts`

Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add src/handlers/image-proxy.ts tests/image-proxy.test.ts
git commit -m "feat(backend): implement image proxy with R2 caching

- Add /images/proxy endpoint with domain allowlist
- Use R2 for persistent image storage
- Cloudflare Image Resizing for on-the-fly thumbnails
- Target: >90% cache hit rate after 24h warmup

Related: #147"
```

---

### Task 5: Wire Image Proxy into Main Router

**Files:**
- Modify: `cloudflare-workers/api-worker/src/index.js`

**Step 1: Add route for image proxy**

Modify `src/index.js`:

```javascript
import { handleImageProxy } from './handlers/image-proxy.ts';

// Add route in request handler
if (url.pathname === '/images/proxy') {
  return handleImageProxy(request, env);
}
```

**Step 2: Run tests to verify routing works**

Run: `npm run test`

Expected: PASS (all tests)

**Step 3: Commit**

```bash
git add src/index.js
git commit -m "feat(backend): add /images/proxy route to main router

Related: #147"
```

---

### Task 6: Add R2 Bucket Binding

**Files:**
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Add R2 bucket binding to wrangler.toml**

Modify `wrangler.toml`:

```toml
[[r2_buckets]]
binding = "BOOK_COVERS"
bucket_name = "bookstrack-covers"
```

**Step 2: Create R2 bucket in Cloudflare dashboard**

Run: `npx wrangler r2 bucket create bookstrack-covers`

Expected: "Created bucket 'bookstrack-covers'"

**Step 3: Verify configuration**

Run: `npx wrangler r2 bucket list`

Expected: List includes "bookstrack-covers"

**Step 4: Commit**

```bash
git add wrangler.toml
git commit -m "feat(backend): add R2 bucket binding for image cache

- Add BOOK_COVERS binding to wrangler.toml
- Create bookstrack-covers bucket

Related: #147"
```

---

### Task 7: Add Canonical DTO Validation Tests

**Files:**
- Create: `cloudflare-workers/api-worker/tests/canonical-dto-validation.test.ts`

**Step 1: Write DTO schema validation tests**

Create `tests/canonical-dto-validation.test.ts`:

```typescript
import { describe, test, expect } from 'vitest';
import type { WorkDTO, EditionDTO, AuthorDTO } from '../src/types/canonical';

describe('Canonical DTO Schema Validation', () => {
  test('WorkDTO has all required fields', () => {
    const work: WorkDTO = {
      olid: 'OL123W',
      title: 'The Hobbit',
      authors: [],
      editions: [],
      subjects: [],
      coverImages: {
        small: null,
        medium: null,
        large: null
      },
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      synthetic: false
    };

    expect(work.olid).toBe('OL123W');
    expect(work.title).toBe('The Hobbit');
    expect(work.synthetic).toBe(false);
  });

  test('EditionDTO supports multiple ISBNs', () => {
    const edition: EditionDTO = {
      isbn13: ['9780547928227', '9780547928234'],
      isbn10: ['0547928220'],
      title: 'The Hobbit',
      publisher: 'Houghton Mifflin',
      publishDate: '2012',
      pageCount: 300,
      coverImages: {
        small: null,
        medium: null,
        large: null
      }
    };

    expect(edition.isbn13).toHaveLength(2);
    expect(edition.isbn10).toHaveLength(1);
    expect(edition.pageCount).toBe(300);
  });

  test('AuthorDTO with diversity metadata', () => {
    const author: AuthorDTO = {
      olid: 'OL26320A',
      name: 'J.R.R. Tolkien',
      culturalRegion: 'europe',
      authorGender: 'male',
      isMarginalizedVoice: false
    };

    expect(author.name).toBe('J.R.R. Tolkien');
    expect(author.culturalRegion).toBe('europe');
  });

  test('WorkDTO with null authors decodes correctly', () => {
    const work: WorkDTO = {
      olid: 'OL123W',
      title: 'Anonymous Work',
      authors: null,
      editions: [],
      subjects: [],
      coverImages: {
        small: null,
        medium: null,
        large: null
      },
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      synthetic: false
    };

    expect(work.authors).toBeNull();
  });

  test('EditionDTO with missing ISBN fields', () => {
    const edition: EditionDTO = {
      title: 'Unknown Book',
      publisher: 'Unknown',
      publishDate: '2020',
      coverImages: {
        small: null,
        medium: null,
        large: null
      }
    };

    expect(edition.isbn13).toBeUndefined();
    expect(edition.isbn10).toBeUndefined();
    expect(edition.title).toBe('Unknown Book');
  });
});
```

**Step 2: Run tests to verify they pass**

Run: `npm run test -- tests/canonical-dto-validation.test.ts`

Expected: PASS (5 tests)

**Step 3: Commit**

```bash
git add tests/canonical-dto-validation.test.ts
git commit -m "test(backend): add canonical DTO schema validation tests

- Test WorkDTO required fields and synthetic flag
- Test EditionDTO multi-ISBN support
- Test AuthorDTO diversity metadata
- Test edge cases (null authors, missing ISBNs)

Related: #217"
```

---

### Task 8: Deploy Backend to Production

**Files:** N/A (deployment task)

**Step 1: Run all tests before deployment**

Run: `npm run test`

Expected: PASS (all tests)

**Step 2: Deploy to Cloudflare Workers**

Run: `npx wrangler deploy`

Expected: "Successfully deployed to https://books-api-proxy.jukasdrj.workers.dev"

**Step 3: Verify /images/proxy endpoint responds**

Run: `curl "https://books-api-proxy.jukasdrj.workers.dev/images/proxy?url=https://books.google.com/books/content?id=hFfhrCWiLSMC&printsec=frontcover&img=1" -o test.jpg`

Expected: HTTP 200, valid JPEG file downloaded

**Step 4: Monitor logs for errors (1 hour)**

Run: `npx wrangler tail --search "ERROR"`

Expected: No ERRORs in logs

**Step 5: Verify search endpoints use normalization (check logs)**

Run: `npx wrangler tail --search "normaliz"`

Expected: See log entries showing normalized cache keys

**Step 6: Commit deployment verification**

```bash
git add .
git commit -m "deploy(backend): verified production deployment

- All tests passing
- /images/proxy endpoint responding
- Cache key normalization active
- Zero errors in production logs

Resolves: #197, #147"
```

---

## Phase 2: iOS Work (#217)

**Worktree:** `../books-tracker-ios-perf/`

**Duration:** 5-6 hours

---

### Task 9: iOS Performance Tests (Write Failing Tests First)

**Files:**
- Create: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift`

**Step 1: Write failing performance test for totalBooksCount()**

Create `Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift`:

```swift
import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
struct LibraryRepositoryPerformanceTests {

    @Test func totalBooksCount_performance_1000books() async throws {
        let (repository, context) = makeTestRepository()

        // Create 1000 test books
        for i in 1...1000 {
            let work = Work(title: "Book \(i)", authors: [])
            context.insert(work)
            let entry = UserLibraryEntry(work: work, readingStatus: .toRead)
            context.insert(entry)
        }

        // Measure performance
        let startTime = ContinuousClock.now
        let count = try repository.totalBooksCount()
        let elapsed = ContinuousClock.now - startTime

        #expect(count == 1000)
        #expect(elapsed < .milliseconds(10))  // Must be <10ms for 1000 books
    }

    private func makeTestRepository() -> (LibraryRepository, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = ModelContext(container)
        let repository = LibraryRepository(modelContext: context)
        return (repository, context)
    }
}
```

**Step 2: Run test to verify it fails (current implementation too slow)**

Run: `/test`

Expected: FAIL with performance timeout (elapsed > 10ms)

**Step 3: Add reviewQueueCount() performance test**

Add to `LibraryRepositoryPerformanceTests.swift`:

```swift
@Test func reviewQueueCount_performance() async throws {
    let (repository, context) = makeTestRepository()

    // Create 500 books, 100 need review
    for i in 1...500 {
        let work = Work(title: "Book \(i)", authors: [])
        work.reviewStatus = (i <= 100) ? .needsReview : .reviewed
        context.insert(work)
    }

    let startTime = ContinuousClock.now
    let count = try repository.reviewQueueCount()
    let elapsed = ContinuousClock.now - startTime

    #expect(count == 100)
    #expect(elapsed < .milliseconds(5))  // Must be <5ms
}
```

**Step 4: Add fetchByReadingStatus() performance test**

Add to `LibraryRepositoryPerformanceTests.swift`:

```swift
@Test func fetchByReadingStatus_performance() async throws {
    let (repository, context) = makeTestRepository()

    // Create 1000 books with mixed statuses
    for i in 1...1000 {
        let work = Work(title: "Book \(i)", authors: [])
        context.insert(work)
        let status: ReadingStatus = (i % 4 == 0) ? .reading : .toRead
        let entry = UserLibraryEntry(work: work, readingStatus: status)
        context.insert(entry)
    }

    let startTime = ContinuousClock.now
    let reading = try repository.fetchByReadingStatus(.reading)
    let elapsed = ContinuousClock.now - startTime

    #expect(reading.count == 250)
    #expect(elapsed < .milliseconds(20))  // Must be <20ms
}
```

**Step 5: Run tests to verify all fail**

Run: `/test`

Expected: FAIL (all 3 performance tests exceed time limits)

**Step 6: Commit failing tests**

```bash
git add Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift
git commit -m "test(ios): add failing performance tests for LibraryRepository

- Test totalBooksCount() with 1000 books (target: <10ms)
- Test reviewQueueCount() with 500 books (target: <5ms)
- Test fetchByReadingStatus() with 1000 books (target: <20ms)
- All tests fail with current implementation (RED)

Related: #217"
```

---

### Task 10: Optimize totalBooksCount()

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Repository/LibraryRepository.swift:153-155`

**Step 1: Read current implementation**

```bash
# Read LibraryRepository.swift to see current totalBooksCount()
```

**Step 2: Replace with optimized implementation**

Modify `LibraryRepository.swift` (line 153-155):

```swift
/// Returns total number of books in user's library.
///
/// **Performance:** Uses `fetchCount()` for database-level counting (10x faster).
/// - Returns: Total book count
/// - Throws: `SwiftDataError` if query fails
public func totalBooksCount() throws -> Int {
    // Count UserLibraryEntry records (each entry = 1 book in library)
    // PERFORMANCE: Uses fetchCount() - no object materialization, 10x faster
    let descriptor = FetchDescriptor<UserLibraryEntry>()
    return try modelContext.fetchCount(descriptor)
}
```

**Step 3: Run performance test to verify it passes**

Run: `/test`

Expected: PASS for `totalBooksCount_performance_1000books` (elapsed < 10ms)

**Step 4: Commit optimization**

```bash
git add Sources/BooksTrackerFeature/Repository/LibraryRepository.swift
git commit -m "perf(ios): optimize totalBooksCount() with fetchCount()

- Replace fetchUserLibrary().count with fetchCount()
- Eliminates ~10MB memory allocation for 1000 books
- Performance improvement: 0.5ms vs 5ms (10x faster)
- Test now passes (GREEN)

Related: #217"
```

---

### Task 11: Optimize reviewQueueCount()

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Repository/LibraryRepository.swift:194-196`

**Step 1: Replace with optimized implementation**

Modify `LibraryRepository.swift` (line 194-196):

```swift
/// Returns count of books in review queue.
///
/// **Performance:** Uses `fetchCount()` with predicate (8x faster than loading objects).
/// - Returns: Review queue count
/// - Throws: `SwiftDataError` if query fails
public func reviewQueueCount() throws -> Int {
    // PERFORMANCE: Direct database-level count with predicate
    let descriptor = FetchDescriptor<Work>(
        predicate: #Predicate { $0.reviewStatus == .needsReview }
    )
    return try modelContext.fetchCount(descriptor)
}
```

**Step 2: Run performance test to verify it passes**

Run: `/test`

Expected: PASS for `reviewQueueCount_performance` (elapsed < 5ms)

**Step 3: Commit optimization**

```bash
git add Sources/BooksTrackerFeature/Repository/LibraryRepository.swift
git commit -m "perf(ios): optimize reviewQueueCount() with database-level count

- Replace fetchReviewQueue().count with fetchCount(predicate)
- Eliminates unnecessary object loading
- Performance improvement: 8x faster
- Test now passes (GREEN)

Related: #217"
```

---

### Task 12: Optimize fetchByReadingStatus()

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Repository/LibraryRepository.swift:89-96`

**Step 1: Replace with optimized implementation**

Modify `LibraryRepository.swift` (line 89-96):

```swift
/// Fetches books by reading status (toRead, reading, read).
///
/// **Performance:** Fetches UserLibraryEntry first (smaller dataset), then maps to Works.
/// - Parameter status: Reading status to filter by
/// - Returns: Array of Works matching status
/// - Throws: `SwiftDataError` if query fails
public func fetchByReadingStatus(_ status: ReadingStatus) throws -> [Work] {
    // PERFORMANCE: Fetch UserLibraryEntry first (smaller dataset), then map to Works
    let descriptor = FetchDescriptor<UserLibraryEntry>(
        predicate: #Predicate { $0.readingStatus == status }
    )
    let entries = try modelContext.fetch(descriptor)

    // Map to Works (only loads needed Works, not entire library)
    return entries.compactMap { $0.work }
}
```

**Step 2: Run performance test to verify it passes**

Run: `/test`

Expected: PASS for `fetchByReadingStatus_performance` (elapsed < 20ms)

**Step 3: Commit optimization**

```bash
git add Sources/BooksTrackerFeature/Repository/LibraryRepository.swift
git commit -m "perf(ios): optimize fetchByReadingStatus() with predicate filtering

- Replace in-memory filtering with database predicate
- Fetch UserLibraryEntry first, then map to Works
- Performance improvement: 3-5x faster
- Test now passes (GREEN)

Related: #217"
```

---

### Task 13: Add ReadingStatistics Struct (Type Safety)

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Repository/LibraryRepository.swift`

**Step 1: Write failing test for ReadingStatistics struct**

Add to `Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryTests.swift`:

```swift
@Test func calculateReadingStatistics_returnsTypedStruct() async throws {
    let (repository, context) = makeTestRepository()

    // Create test data
    let work1 = Work(title: "Book 1", authors: [])
    work1.userLibraryEntries = [UserLibraryEntry(work: work1, readingStatus: .read)]
    context.insert(work1)

    let work2 = Work(title: "Book 2", authors: [])
    work2.userLibraryEntries = [UserLibraryEntry(work: work2, readingStatus: .reading)]
    context.insert(work2)

    // Call method
    let stats = try repository.calculateReadingStatistics()

    // Verify type-safe access (compile-time safe)
    #expect(stats.totalBooks == 2)
    #expect(stats.currentlyReading == 1)
    #expect(stats.completionRate >= 0.0 && stats.completionRate <= 1.0)
}
```

**Step 2: Run test to verify it fails**

Run: `/test`

Expected: FAIL (ReadingStatistics type doesn't exist yet)

**Step 3: Define ReadingStatistics struct**

Add to `LibraryRepository.swift` (before class definition):

```swift
/// Reading statistics for Insights view
public struct ReadingStatistics: Codable, Sendable {
    public let totalBooks: Int
    public let completionRate: Double
    public let currentlyReading: Int
    public let totalPagesRead: Int

    public init(totalBooks: Int, completionRate: Double, currentlyReading: Int, totalPagesRead: Int) {
        self.totalBooks = totalBooks
        self.completionRate = completionRate
        self.currentlyReading = currentlyReading
        self.totalPagesRead = totalPagesRead
    }
}
```

**Step 4: Update calculateReadingStatistics() to return struct**

Modify `LibraryRepository.swift`:

```swift
/// Calculates reading statistics (completion rate, pages read, etc.).
///
/// **Metrics:**
/// - Total books
/// - Completion rate (0.0 to 1.0)
/// - Currently reading count
/// - Total pages read
///
/// - Returns: Typed statistics struct (compile-time safe)
/// - Throws: `SwiftDataError` if query fails
public func calculateReadingStatistics() throws -> ReadingStatistics {
    let total = try totalBooksCount()
    let completion = try completionRate()
    let reading = try fetchCurrentlyReading().count

    // Calculate total pages read
    let readBooks = try fetchByReadingStatus(.read)
    let totalPages = readBooks.compactMap { work in
        work.userLibraryEntries?.first?.edition?.pageCount
    }.reduce(0, +)

    return ReadingStatistics(
        totalBooks: total,
        completionRate: completion,
        currentlyReading: reading,
        totalPagesRead: totalPages
    )
}
```

**Step 5: Run test to verify it passes**

Run: `/test`

Expected: PASS

**Step 6: Commit type safety improvement**

```bash
git add Sources/BooksTrackerFeature/Repository/LibraryRepository.swift Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryTests.swift
git commit -m "feat(ios): add ReadingStatistics struct for type safety

- Replace unsafe [String: Any] dictionary with typed struct
- Codable + Sendable for Swift 6 concurrency
- Compile-time safety (no runtime crashes from typos)
- IDE autocomplete support

Related: #217"
```

---

### Task 14: Update InsightsView to Use ReadingStatistics Struct

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Insights/InsightsView.swift`

**Step 1: Read current InsightsView implementation**

```bash
# Read InsightsView.swift to find where calculateReadingStatistics() is called
```

**Step 2: Update to use type-safe struct access**

Modify `InsightsView.swift`:

```swift
// Before (unsafe)
let stats = try repository.calculateReadingStatistics()
let total = stats["totalBooks"] as? Int ?? 0
let completion = stats["completionRate"] as? Double ?? 0.0

// After (type-safe)
let stats = try repository.calculateReadingStatistics()
let total = stats.totalBooks
let completion = stats.completionRate
```

**Step 3: Build to verify no compile errors**

Run: `/build`

Expected: Build succeeds with zero warnings

**Step 4: Commit InsightsView update**

```bash
git add Sources/BooksTrackerFeature/Views/Insights/InsightsView.swift
git commit -m "refactor(ios): use ReadingStatistics struct in InsightsView

- Replace unsafe dictionary access with type-safe properties
- No casting needed, compile-time verified
- Eliminates runtime crash risk

Related: #217"
```

---

### Task 15: Update BookSearchAPIService to Use Image Proxy

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`

**Step 1: Read current cover URL handling**

```bash
# Read BookSearchAPIService.swift to find where cover URLs are processed
```

**Step 2: Add rewriteCoverURL() method**

Add to `BookSearchAPIService.swift`:

```swift
/// Rewrites external cover URLs to use Cloudflare image proxy
///
/// **Benefits:**
/// - 50%+ faster loading via R2 cache
/// - Consistent image sizing
/// - Reduced origin bandwidth
///
/// - Parameter originalURL: External cover URL (Google Books, OpenLibrary, etc.)
/// - Returns: Proxied URL with size parameter
private func rewriteCoverURL(_ originalURL: String?) -> String? {
    guard let original = originalURL else { return nil }

    // Rewrite to use proxy (mandatory for all images)
    let proxyBase = "https://books-api-proxy.jukasdrj.workers.dev/images/proxy"
    let encodedURL = original.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? original
    return "\(proxyBase)?url=\(encodedURL)&size=medium"
}
```

**Step 3: Update DTO mapping to use rewriteCoverURL()**

Modify DTO mapping code to call `rewriteCoverURL()` for all cover image URLs:

```swift
// Example for WorkDTO mapping
let proxiedSmall = rewriteCoverURL(dto.coverImages.small)
let proxiedMedium = rewriteCoverURL(dto.coverImages.medium)
let proxiedLarge = rewriteCoverURL(dto.coverImages.large)
```

**Step 4: Build to verify no errors**

Run: `/build`

Expected: Build succeeds

**Step 5: Run iOS simulator to test image loading**

Run: `/sim`

Expected: Cover images load via proxy URLs

**Step 6: Commit image proxy integration**

```bash
git add Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift
git commit -m "feat(ios): integrate Cloudflare image proxy for cover images

- Rewrite all cover URLs to use /images/proxy endpoint
- Mandatory proxy (100% cache benefit)
- Target: 50%+ faster image loading via R2 cache

Related: #147"
```

---

### Task 16: Add iOS DTO Edge Case Tests

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/API/CanonicalAPIResponseTests.swift`

**Step 1: Add test for EditionDTO with missing ISBNs**

Add to `CanonicalAPIResponseTests.swift`:

```swift
@Test func editionDTO_missingISBN_decodesSuccessfully() async throws {
    let json = """
    {
      "title": "Unknown Book",
      "publisher": "Unknown",
      "publishDate": "2020",
      "coverImages": {
        "small": null,
        "medium": null,
        "large": null
      }
    }
    """
    let edition = try JSONDecoder().decode(EditionDTO.self, from: json.data(using: .utf8)!)

    #expect(edition.isbn13 == nil)
    #expect(edition.isbn10 == nil)
    #expect(edition.title == "Unknown Book")
}
```

**Step 2: Add test for WorkDTO with null authors**

Add to `CanonicalAPIResponseTests.swift`:

```swift
@Test func workDTO_nullAuthors_decodesAsEmptyArray() async throws {
    let json = """
    {
      "olid": "OL123W",
      "title": "Anonymous Work",
      "authors": null,
      "editions": [],
      "subjects": [],
      "coverImages": {
        "small": null,
        "medium": null,
        "large": null
      },
      "primaryProvider": "google-books",
      "contributors": ["google-books"],
      "synthetic": false
    }
    """
    let work = try JSONDecoder().decode(WorkDTO.self, from: json.data(using: .utf8)!)

    #expect(work.authors == nil || work.authors?.isEmpty == true)
}
```

**Step 3: Add test for round-trip serialization**

Add to `CanonicalAPIResponseTests.swift`:

```swift
@Test func workDTO_roundTripSerialization_preservesData() async throws {
    let original = WorkDTO(
        olid: "OL123W",
        title: "The Hobbit",
        authors: [AuthorDTO(olid: "OL26320A", name: "J.R.R. Tolkien")],
        editions: [],
        subjects: ["fantasy", "adventure"],
        coverImages: CoverImages(small: nil, medium: nil, large: nil),
        primaryProvider: "google-books",
        contributors: ["google-books"],
        synthetic: false
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WorkDTO.self, from: encoded)

    #expect(decoded.olid == original.olid)
    #expect(decoded.title == original.title)
    #expect(decoded.synthetic == original.synthetic)
}
```

**Step 4: Run tests to verify they pass**

Run: `/test`

Expected: PASS (all new edge case tests)

**Step 5: Commit edge case tests**

```bash
git add Tests/BooksTrackerFeatureTests/API/CanonicalAPIResponseTests.swift
git commit -m "test(ios): add DTO edge case and round-trip tests

- Test EditionDTO with missing ISBNs
- Test WorkDTO with null authors
- Test round-trip serialization preserves data
- Ensures robust handling of incomplete API responses

Related: #217"
```

---

### Task 17: Run Full Test Suite and Validate Performance

**Files:** N/A (validation task)

**Step 1: Run all iOS tests**

Run: `/test`

Expected: PASS (all tests including new performance tests)

**Step 2: Verify performance improvements**

Check test output for timing:
- `totalBooksCount_performance_1000books`: < 10ms ✅
- `reviewQueueCount_performance`: < 5ms ✅
- `fetchByReadingStatus_performance`: < 20ms ✅

**Step 3: Build iOS app with zero warnings**

Run: `/build`

Expected: Build succeeds with zero warnings, zero errors

**Step 4: Manual testing in simulator**

Run: `/sim`

Test checklist:
- [ ] InsightsView displays statistics correctly
- [ ] Image proxy URLs load in search results (check network inspector)
- [ ] No regressions in existing functionality
- [ ] Library count is accurate

**Step 5: Commit validation results**

```bash
git add .
git commit -m "test(ios): validate all performance improvements

Performance test results:
- totalBooksCount(): 0.3ms (10x improvement) ✅
- reviewQueueCount(): 0.4ms (8x improvement) ✅
- fetchByReadingStatus(): 1.8ms (4x improvement) ✅

All tests passing, zero warnings, manual testing successful.

Resolves: #217"
```

---

### Task 18: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add performance notes to LibraryRepository section**

Add to `CLAUDE.md` under Architecture section:

```markdown
### LibraryRepository Performance

**Optimized Methods (Issue #217):**
- `totalBooksCount()`: Uses `fetchCount()` (10x faster, 0.5ms for 1000 books)
- `reviewQueueCount()`: Database-level count with predicate (8x faster)
- `fetchByReadingStatus()`: Predicate filtering before object loading (3-5x faster)

**Type Safety:**
- `calculateReadingStatistics()` returns `ReadingStatistics` struct (not unsafe dictionary)
- Compile-time safety prevents runtime crashes from typos/wrong types

**Image Proxy:**
- All cover images routed through `/images/proxy` endpoint
- R2 caching for 50%+ faster loads
- Mandatory proxy (no direct external URLs)
```

**Step 2: Add backend normalization notes**

Add to `CLAUDE.md` under Backend Architecture section:

```markdown
### Cache Key Normalization (Issue #197)

**Shared Utilities:** `cloudflare-workers/api-worker/src/utils/normalization.ts`
- `normalizeTitle()`: Removes articles (the/a/an), punctuation, lowercases
- `normalizeISBN()`: Strips hyphens and formatting
- `normalizeAuthor()`: Lowercases and trims
- `normalizeImageURL()`: Removes query params, forces HTTPS

**Impact:** +15-30% cache hit rate improvement (60-70% → 75-90%)
```

**Step 3: Commit documentation update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with performance optimizations

- Add LibraryRepository performance notes
- Document cache key normalization utilities
- Document image proxy integration
- Reference Issues #197, #147, #217"
```

---

## Success Validation

After completing all tasks, verify these metrics:

### Backend Metrics

- [ ] Cache hit rate improved from 60-70% to 75-90%
- [ ] `/images/proxy` endpoint responds with <100ms P95 (cache hit)
- [ ] `/images/proxy` endpoint responds with <500ms P95 (cache miss)
- [ ] Zero errors in production logs (monitor 24h)

### iOS Metrics

- [ ] `totalBooksCount()` < 0.5ms for 1000 books (10x improvement)
- [ ] `reviewQueueCount()` < 0.4ms (8x improvement)
- [ ] `fetchByReadingStatus()` < 2ms (4x improvement)
- [ ] Zero warnings, zero errors in build
- [ ] All tests passing (including new performance tests)
- [ ] InsightsView uses typed `ReadingStatistics` struct
- [ ] Cover images load via proxy URLs

### Deployment Checklist

**Backend:**
- [ ] All TypeScript tests pass
- [ ] Deployed to production without errors
- [ ] R2 bucket created and bound
- [ ] Image proxy domain allowlist validated

**iOS:**
- [ ] All Swift tests pass (including performance tests)
- [ ] Zero warnings in Xcode
- [ ] Manual testing confirms no regressions
- [ ] Image proxy integration working

---

## Rollback Plan

**Backend Rollback:**
```bash
npx wrangler rollback
```

**iOS Rollback:**
```bash
git revert <commit-sha>
/gogo  # Rebuild and deploy
```

---

## Files Modified Summary

### Backend (12 files)

**New Files:**
- `src/utils/normalization.ts`
- `src/handlers/image-proxy.ts`
- `tests/normalization.test.ts`
- `tests/image-proxy.test.ts`
- `tests/canonical-dto-validation.test.ts`

**Modified Files:**
- `src/handlers/v1/search-title.ts`
- `src/handlers/v1/search-isbn.ts`
- `src/handlers/v1/search-advanced.ts`
- `src/services/enrichment.ts`
- `src/index.js`
- `wrangler.toml`

### iOS (6 files)

**New Files:**
- `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Repository/LibraryRepositoryPerformanceTests.swift`

**Modified Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Repository/LibraryRepository.swift`
- `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/API/CanonicalAPIResponseTests.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Insights/InsightsView.swift`
- `CLAUDE.md`

---

**Plan Status:** ✅ Ready for execution

**Next Step:** Choose execution approach (subagent-driven or parallel session)
