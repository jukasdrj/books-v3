# ISBNdb Cover Harvest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One-time harvest of ~500-775 book covers from ISBNdb API (before subscription expires) to R2 storage with KV metadata for future edge caching.

**Architecture:** Wrangler CLI task that reads curated CSV book lists, queries ISBNdb API with Google Books fallback, downloads covers to R2 (`covers/isbn/{isbn13}.jpg`), stores provenance metadata in KV, logs failures to local JSON file.

**Tech Stack:** Node.js, Cloudflare Wrangler, R2 Object Storage, KV Store, ISBNdb API, Google Books API

---

## Task 1: Setup TypeScript Types & Interfaces

**Files:**
- Create: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`
- Create: `cloudflare-workers/api-worker/src/tasks/types/harvest-types.ts`

**Step 1: Write TypeScript type definitions**

Create `cloudflare-workers/api-worker/src/tasks/types/harvest-types.ts`:

```typescript
/**
 * Book entry from CSV file
 */
export interface BookEntry {
  title: string;
  author: string;
  isbn: string; // ISBN-13 format
}

/**
 * Cover image data from provider
 */
export interface CoverData {
  url: string;
  source: 'isbndb' | 'google-books';
  isbn: string;
}

/**
 * KV metadata for harvested cover
 */
export interface CoverMetadata {
  isbn: string;
  source: 'isbndb' | 'google-books';
  r2Key: string;
  harvestedAt: string; // ISO 8601
  fallback: boolean;
  originalUrl: string;
}

/**
 * Result of harvesting a single book
 */
export interface HarvestResult {
  isbn: string;
  title: string;
  author: string;
  success: boolean;
  source?: 'isbndb' | 'google-books';
  error?: string;
}

/**
 * Final harvest report
 */
export interface HarvestReport {
  totalBooks: number;
  successCount: number;
  isbndbCount: number;
  googleBooksCount: number;
  failureCount: number;
  executionTimeMs: number;
  failures: Array<{
    isbn: string;
    title: string;
    author: string;
    isbndbError?: string;
    googleBooksError?: string;
  }>;
}

/**
 * Cloudflare Worker environment bindings
 */
export interface Env {
  LIBRARY_DATA: R2Bucket;
  KV_CACHE: KVNamespace;
  ISBNDB_API_KEY: string;
  GOOGLE_BOOKS_API_KEY?: string;
}
```

**Step 2: Create main harvest task file structure**

Create `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`:

```typescript
import type {
  BookEntry,
  CoverData,
  CoverMetadata,
  HarvestResult,
  HarvestReport,
  Env
} from './types/harvest-types';

/**
 * Main entry point for ISBNdb cover harvest task
 *
 * Usage: npx wrangler dev --remote --task harvest-covers
 */
export async function harvestCovers(env: Env): Promise<HarvestReport> {
  console.log('🚀 ISBNdb Cover Harvest Starting...');
  console.log('━'.repeat(60));

  const startTime = Date.now();

  // TODO: Implement harvest logic
  const report: HarvestReport = {
    totalBooks: 0,
    successCount: 0,
    isbndbCount: 0,
    googleBooksCount: 0,
    failureCount: 0,
    executionTimeMs: Date.now() - startTime,
    failures: [],
  };

  console.log('\n✅ Harvest Complete!');
  console.log('━'.repeat(60));
  console.log(`✓ Total Harvested: ${report.successCount} / ${report.totalBooks}`);
  console.log(`✓ ISBNdb Covers: ${report.isbndbCount}`);
  console.log(`↻ Google Fallback: ${report.googleBooksCount}`);
  console.log(`✗ Failed: ${report.failureCount}`);
  console.log(`⏱ Execution Time: ${(report.executionTimeMs / 1000).toFixed(1)}s`);

  return report;
}
```

**Step 3: Commit type definitions**

```bash
cd /Users/justingardner/Downloads/xcode/books-tracker-v1/.worktrees/issue-202-harvest-covers/cloudflare-workers/api-worker
git add src/tasks/types/harvest-types.ts src/tasks/harvest-covers.ts
git commit -m "feat: add TypeScript types for ISBNdb cover harvest task"
```

---

## Task 2: CSV Parsing & Deduplication

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

**Step 1: Add CSV parsing function**

Add to `harvest-covers.ts` (after imports):

```typescript
import * as fs from 'fs';
import * as path from 'path';

/**
 * Load and parse all CSV files from docs/testImages/csv-expansion/
 */
async function loadISBNsFromCSVs(): Promise<BookEntry[]> {
  const csvDir = path.join(process.cwd(), '../../docs/testImages/csv-expansion');

  console.log(`📂 Loading CSVs from: ${csvDir}`);

  const files = fs.readdirSync(csvDir).filter(f => f.endsWith('.csv'));
  console.log(`Found ${files.length} CSV files`);

  const allEntries: BookEntry[] = [];

  for (const file of files) {
    const filePath = path.join(csvDir, file);
    const entries = await parseCSV(filePath);
    allEntries.push(...entries);
    console.log(`  ✓ ${file}: ${entries.length} books`);
  }

  return allEntries;
}

/**
 * Parse a single CSV file
 * Expected format: Title,Author,ISBN-13
 */
async function parseCSV(filePath: string): Promise<BookEntry[]> {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n').filter(line => line.trim());

  // Skip header row
  const dataLines = lines.slice(1);

  const entries: BookEntry[] = [];

  for (const line of dataLines) {
    // Simple CSV parsing (handles quoted fields)
    const match = line.match(/^"([^"]+)","([^"]+)",(\d{13})$/);
    if (!match) continue;

    const [, title, author, isbn] = match;
    entries.push({ title, author, isbn });
  }

  return entries;
}

/**
 * Deduplicate books by ISBN-13
 */
function deduplicateISBNs(entries: BookEntry[]): BookEntry[] {
  const seen = new Set<string>();
  const unique: BookEntry[] = [];

  for (const entry of entries) {
    if (!seen.has(entry.isbn)) {
      seen.add(entry.isbn);
      unique.push(entry);
    }
  }

  console.log(`📊 Deduplicated: ${entries.length} → ${unique.length} unique ISBNs`);
  return unique;
}
```

**Step 2: Update main harvestCovers function**

Update `harvestCovers()` to use CSV loading:

```typescript
export async function harvestCovers(env: Env): Promise<HarvestReport> {
  console.log('🚀 ISBNdb Cover Harvest Starting...');
  console.log('━'.repeat(60));

  const startTime = Date.now();

  // Load and deduplicate books from CSVs
  const allEntries = await loadISBNsFromCSVs();
  const books = deduplicateISBNs(allEntries);

  console.log(`\n📚 Loaded ${books.length} unique books to harvest\n`);

  // TODO: Harvest each book
  const results: HarvestResult[] = [];

  const report: HarvestReport = {
    totalBooks: books.length,
    successCount: results.filter(r => r.success).length,
    isbndbCount: results.filter(r => r.success && r.source === 'isbndb').length,
    googleBooksCount: results.filter(r => r.success && r.source === 'google-books').length,
    failureCount: results.filter(r => !r.success).length,
    executionTimeMs: Date.now() - startTime,
    failures: results
      .filter(r => !r.success)
      .map(r => ({
        isbn: r.isbn,
        title: r.title,
        author: r.author,
        isbndbError: r.error,
      })),
  };

  console.log('\n✅ Harvest Complete!');
  console.log('━'.repeat(60));
  console.log(`✓ Total Harvested: ${report.successCount} / ${report.totalBooks}`);
  console.log(`✓ ISBNdb Covers: ${report.isbndbCount}`);
  console.log(`↻ Google Fallback: ${report.googleBooksCount}`);
  console.log(`✗ Failed: ${report.failureCount}`);
  console.log(`⏱ Execution Time: ${(report.executionTimeMs / 1000).toFixed(1)}s`);

  return report;
}
```

**Step 3: Test CSV parsing with dry run**

Add dry-run test at bottom of file:

```typescript
// Dry run test (comment out for production)
if (import.meta.url === `file://${process.argv[1]}`) {
  (async () => {
    const entries = await loadISBNsFromCSVs();
    const books = deduplicateISBNs(entries);
    console.log('\n[DRY RUN] Sample books:');
    books.slice(0, 5).forEach(b => {
      console.log(`  - ${b.title} by ${b.author} (${b.isbn})`);
    });
  })();
}
```

Run: `node src/tasks/harvest-covers.ts`
Expected: Logs CSV files loaded and sample books

**Step 4: Commit CSV parsing**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add CSV parsing and deduplication for harvest task"
```

---

## Task 3: ISBNdb API Integration

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`
- Reference: `cloudflare-workers/api-worker/src/services/external-apis.js` (existing ISBNdb code)

**Step 1: Add ISBNdb fetching function**

Add to `harvest-covers.ts`:

```typescript
/**
 * Fetch cover data from ISBNdb API
 */
async function fetchFromISBNdb(isbn: string, env: Env): Promise<CoverData | null> {
  try {
    // Enforce rate limit (1000ms between requests)
    await enforceRateLimit(env);

    const apiKey = typeof env.ISBNDB_API_KEY === 'object'
      ? await env.ISBNDB_API_KEY.get()
      : env.ISBNDB_API_KEY;

    if (!apiKey) {
      throw new Error('ISBNDB_API_KEY not found');
    }

    const url = `https://api2.isbndb.com/book/${isbn}`;
    const response = await fetch(url, {
      headers: {
        'Authorization': apiKey,
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      if (response.status === 404) {
        return null; // Book not found, will try fallback
      }
      throw new Error(`ISBNdb API error: ${response.status}`);
    }

    const data = await response.json();
    const coverUrl = data.book?.image;

    if (!coverUrl) {
      return null; // No cover available
    }

    return {
      url: coverUrl,
      source: 'isbndb',
      isbn,
    };
  } catch (error) {
    console.error(`ISBNdb error for ${isbn}: ${error.message}`);
    return null;
  }
}

/**
 * Rate limiting: 1 second between ISBNdb requests
 */
const RATE_LIMIT_KEY = 'harvest_isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000; // 1 second

async function enforceRateLimit(env: Env): Promise<void> {
  const lastRequest = await env.KV_CACHE.get(RATE_LIMIT_KEY);

  if (lastRequest) {
    const timeDiff = Date.now() - parseInt(lastRequest);
    if (timeDiff < RATE_LIMIT_INTERVAL) {
      const waitTime = RATE_LIMIT_INTERVAL - timeDiff;
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }

  await env.KV_CACHE.put(RATE_LIMIT_KEY, Date.now().toString(), {
    expirationTtl: 60
  });
}
```

**Step 2: Add test for ISBNdb fetching**

Add at bottom of file:

```typescript
// Test ISBNdb fetch (comment out for production)
if (import.meta.url === `file://${process.argv[1]}` && process.argv[2] === '--test-isbndb') {
  (async () => {
    const testISBN = '9780451524935'; // 1984 by George Orwell
    console.log(`\n[TEST] Fetching cover for ISBN: ${testISBN}`);

    // Mock env for testing
    const mockEnv = {
      ISBNDB_API_KEY: process.env.ISBNDB_API_KEY,
      KV_CACHE: {
        get: async () => null,
        put: async () => {},
      },
    };

    const cover = await fetchFromISBNdb(testISBN, mockEnv as any);
    console.log(cover ? `✓ Cover found: ${cover.url}` : '✗ No cover found');
  })();
}
```

Run: `ISBNDB_API_KEY=your_key node src/tasks/harvest-covers.ts --test-isbndb`
Expected: Logs cover URL from ISBNdb

**Step 3: Commit ISBNdb integration**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add ISBNdb API fetching with rate limiting"
```

---

## Task 4: Google Books Fallback

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

**Step 1: Add Google Books fetching function**

Add to `harvest-covers.ts`:

```typescript
/**
 * Fetch cover data from Google Books API (fallback)
 * Searches by title+author, picks edition with highest ratingsCount
 */
async function fetchFromGoogleBooks(
  title: string,
  author: string
): Promise<CoverData | null> {
  try {
    // Build search query: intitle + inauthor
    const query = `intitle:${encodeURIComponent(title)}+inauthor:${encodeURIComponent(author)}`;
    const url = `https://www.googleapis.com/books/v1/volumes?q=${query}&maxResults=5`;

    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`Google Books API error: ${response.status}`);
    }

    const data = await response.json();

    if (!data.items || data.items.length === 0) {
      return null; // No results
    }

    // Find edition with highest ratingsCount (most popular)
    let bestEdition = data.items[0];
    let maxRatings = bestEdition.volumeInfo?.ratingsCount || 0;

    for (const item of data.items) {
      const ratings = item.volumeInfo?.ratingsCount || 0;
      if (ratings > maxRatings) {
        bestEdition = item;
        maxRatings = ratings;
      }
    }

    const coverUrl = bestEdition.volumeInfo?.imageLinks?.thumbnail
      || bestEdition.volumeInfo?.imageLinks?.smallThumbnail;

    if (!coverUrl) {
      return null; // No cover available
    }

    // Extract ISBN-13 from identifiers
    const identifiers = bestEdition.volumeInfo?.industryIdentifiers || [];
    const isbn13 = identifiers.find(id => id.type === 'ISBN_13')?.identifier;

    if (!isbn13) {
      return null; // Can't use without ISBN
    }

    return {
      url: coverUrl.replace('http://', 'https://'), // Force HTTPS
      source: 'google-books',
      isbn: isbn13,
    };
  } catch (error) {
    console.error(`Google Books error for "${title}" by ${author}: ${error.message}`);
    return null;
  }
}
```

**Step 2: Add test for Google Books fetching**

Add at bottom:

```typescript
// Test Google Books fetch (comment out for production)
if (import.meta.url === `file://${process.argv[1]}` && process.argv[2] === '--test-google') {
  (async () => {
    const testBook = { title: '1984', author: 'George Orwell' };
    console.log(`\n[TEST] Fetching cover for: ${testBook.title} by ${testBook.author}`);

    const cover = await fetchFromGoogleBooks(testBook.title, testBook.author);
    console.log(cover ? `✓ Cover found: ${cover.url} (ISBN: ${cover.isbn})` : '✗ No cover found');
  })();
}
```

Run: `node src/tasks/harvest-covers.ts --test-google`
Expected: Logs cover URL from Google Books

**Step 3: Commit Google Books fallback**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add Google Books fallback for cover harvesting"
```

---

## Task 5: R2 Storage & KV Metadata

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

**Step 1: Add R2 upload function**

Add to `harvest-covers.ts`:

```typescript
/**
 * Download cover image and upload to R2
 */
async function downloadAndStoreImage(
  coverUrl: string,
  isbn: string,
  env: Env
): Promise<void> {
  // Download image
  const response = await fetch(coverUrl);

  if (!response.ok) {
    throw new Error(`Failed to download cover: ${response.status}`);
  }

  const imageBlob = await response.blob();

  // Generate R2 key
  const r2Key = `covers/isbn/${isbn}.jpg`;

  // Upload to R2
  await env.LIBRARY_DATA.put(r2Key, imageBlob, {
    httpMetadata: {
      contentType: 'image/jpeg',
    },
  });

  console.log(`  📦 Uploaded to R2: ${r2Key}`);
}

/**
 * Store cover metadata in KV
 */
async function storeMetadata(
  isbn: string,
  metadata: CoverMetadata,
  env: Env
): Promise<void> {
  const kvKey = `cover:${isbn}`;
  await env.KV_CACHE.put(kvKey, JSON.stringify(metadata));
  console.log(`  💾 Stored KV metadata: ${kvKey}`);
}
```

**Step 2: Add single book harvest function**

Add to `harvest-covers.ts`:

```typescript
/**
 * Harvest cover for a single book
 */
async function harvestSingleBook(
  entry: BookEntry,
  env: Env
): Promise<HarvestResult> {
  const { isbn, title, author } = entry;

  try {
    // Check if already cached
    const kvKey = `cover:${isbn}`;
    const existing = await env.KV_CACHE.get(kvKey);

    if (existing) {
      console.log(`  ⏭ Already cached: ${isbn}`);
      return { isbn, title, author, success: true, source: 'isbndb' }; // Assume isbndb
    }

    // Try ISBNdb first
    let coverData = await fetchFromISBNdb(isbn, env);
    let usedFallback = false;

    // Fallback to Google Books if needed
    if (!coverData) {
      console.log(`  ↻ Trying Google Books fallback for: ${title}`);
      coverData = await fetchFromGoogleBooks(title, author);
      usedFallback = true;
    }

    if (!coverData) {
      return {
        isbn,
        title,
        author,
        success: false,
        error: 'No cover found in ISBNdb or Google Books',
      };
    }

    // Download and store
    await downloadAndStoreImage(coverData.url, isbn, env);

    // Store metadata
    const metadata: CoverMetadata = {
      isbn,
      source: coverData.source,
      r2Key: `covers/isbn/${isbn}.jpg`,
      harvestedAt: new Date().toISOString(),
      fallback: usedFallback,
      originalUrl: coverData.url,
    };
    await storeMetadata(isbn, metadata, env);

    return {
      isbn,
      title,
      author,
      success: true,
      source: coverData.source,
    };
  } catch (error) {
    return {
      isbn,
      title,
      author,
      success: false,
      error: error.message,
    };
  }
}
```

**Step 3: Commit R2 and KV functions**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add R2 upload and KV metadata storage"
```

---

## Task 6: Main Harvest Loop & Progress Tracking

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

**Step 1: Add progress logging function**

Add to `harvest-covers.ts`:

```typescript
/**
 * Log harvest progress every 10 books
 */
function logProgress(
  current: number,
  total: number,
  isbndbCount: number,
  googleCount: number,
  failedCount: number
): void {
  if (current % 10 === 0 || current === total) {
    const percent = Math.round((current / total) * 100);
    const bar = '━'.repeat(Math.floor(percent / 2.5));
    const empty = ' '.repeat(40 - bar.length);

    console.log(`\n📊 Progress: [${bar}${empty}] ${current}/${total} (${percent}%)`);
    console.log(`   ✓ ISBNdb: ${isbndbCount} | ↻ Google: ${googleCount} | ✗ Failed: ${failedCount}`);
  }
}
```

**Step 2: Update main harvest loop**

Update `harvestCovers()` function:

```typescript
export async function harvestCovers(env: Env): Promise<HarvestReport> {
  console.log('🚀 ISBNdb Cover Harvest Starting...');
  console.log('━'.repeat(60));

  const startTime = Date.now();

  // Load and deduplicate books from CSVs
  const allEntries = await loadISBNsFromCSVs();
  const books = deduplicateISBNs(allEntries);

  console.log(`\n📚 Loaded ${books.length} unique books to harvest\n`);

  // Harvest each book
  const results: HarvestResult[] = [];
  let isbndbCount = 0;
  let googleCount = 0;
  let failedCount = 0;

  for (let i = 0; i < books.length; i++) {
    const book = books[i];
    console.log(`\n[${i + 1}/${books.length}] ${book.title} by ${book.author}`);
    console.log(`  ISBN: ${book.isbn}`);

    const result = await harvestSingleBook(book, env);
    results.push(result);

    if (result.success) {
      if (result.source === 'isbndb') isbndbCount++;
      else if (result.source === 'google-books') googleCount++;
      console.log(`  ✓ SUCCESS (${result.source})`);
    } else {
      failedCount++;
      console.log(`  ✗ FAILED: ${result.error}`);
    }

    logProgress(i + 1, books.length, isbndbCount, googleCount, failedCount);
  }

  // Generate final report
  const report: HarvestReport = {
    totalBooks: books.length,
    successCount: results.filter(r => r.success).length,
    isbndbCount,
    googleBooksCount: googleCount,
    failureCount: failedCount,
    executionTimeMs: Date.now() - startTime,
    failures: results
      .filter(r => !r.success)
      .map(r => ({
        isbn: r.isbn,
        title: r.title,
        author: r.author,
        isbndbError: r.error,
      })),
  };

  console.log('\n✅ Harvest Complete!');
  console.log('━'.repeat(60));
  console.log(`✓ Total Harvested: ${report.successCount} / ${report.totalBooks}`);
  console.log(`✓ ISBNdb Covers: ${report.isbndbCount}`);
  console.log(`↻ Google Fallback: ${report.googleBooksCount}`);
  console.log(`✗ Failed: ${report.failureCount}`);
  console.log(`⏱ Execution Time: ${(report.executionTimeMs / 1000 / 60).toFixed(1)} minutes`);

  // Write failures to local file
  if (report.failures.length > 0) {
    const failuresPath = path.join(process.cwd(), 'failed_isbns.json');
    fs.writeFileSync(failuresPath, JSON.stringify({
      timestamp: new Date().toISOString(),
      totalFailed: report.failureCount,
      failures: report.failures,
    }, null, 2));
    console.log(`\n📄 Failed ISBNs logged to: ${failuresPath}`);
  }

  return report;
}
```

**Step 3: Commit main harvest loop**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add main harvest loop with progress tracking"
```

---

## Task 7: Wrangler CLI Integration

**Files:**
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Add task configuration to wrangler.toml**

Add to `wrangler.toml` (after other configurations):

```toml
# Harvest task for ISBNdb cover images
[[tasks]]
name = "harvest-covers"
script = "src/tasks/harvest-covers.ts"
```

**Step 2: Test wrangler task execution**

Run: `npx wrangler dev --remote --task harvest-covers`
Expected: Harvest starts, CSVs loaded, progress displayed

**Step 3: Commit wrangler configuration**

```bash
git add wrangler.toml
git commit -m "feat: add wrangler task for cover harvesting"
```

---

## Task 8: Dry Run Mode & Pre-Flight Checks

**Files:**
- Modify: `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

**Step 1: Add pre-flight checks**

Add to `harvest-covers.ts` (before main loop in `harvestCovers()`):

```typescript
// Pre-flight checks
console.log('🔍 Running pre-flight checks...');

try {
  // Check ISBNDB_API_KEY
  const apiKey = typeof env.ISBNDB_API_KEY === 'object'
    ? await env.ISBNDB_API_KEY.get()
    : env.ISBNDB_API_KEY;
  if (!apiKey) throw new Error('ISBNDB_API_KEY not found');
  console.log('  ✓ ISBNDB_API_KEY accessible');

  // Test R2 write
  await env.LIBRARY_DATA.put('test_harvest_write', 'test');
  await env.LIBRARY_DATA.delete('test_harvest_write');
  console.log('  ✓ R2 write permissions OK');

  // Test KV write
  await env.KV_CACHE.put('test_harvest_kv', 'test', { expirationTtl: 60 });
  await env.KV_CACHE.delete('test_harvest_kv');
  console.log('  ✓ KV write permissions OK');

  console.log('✅ Pre-flight checks passed\n');
} catch (error) {
  console.error('❌ Pre-flight check failed:', error.message);
  throw error;
}
```

**Step 2: Add dry-run mode support**

Add environment variable check at start of `harvestCovers()`:

```typescript
const isDryRun = process.env.DRY_RUN === 'true';

if (isDryRun) {
  console.log('⚠️  DRY RUN MODE - No API calls or uploads will be made\n');
}
```

Wrap API calls in dry-run check:

```typescript
// In harvestSingleBook(), before API calls:
if (isDryRun) {
  console.log(`  [DRY RUN] Would fetch cover for: ${isbn}`);
  return { isbn, title, author, success: true, source: 'isbndb' };
}
```

**Step 3: Test dry run**

Run: `DRY_RUN=true npx wrangler dev --remote --task harvest-covers`
Expected: Logs books that would be harvested, no actual API calls

**Step 4: Commit dry-run and checks**

```bash
git add src/tasks/harvest-covers.ts
git commit -m "feat: add dry-run mode and pre-flight checks"
```

---

## Task 9: Final Testing & Documentation

**Files:**
- Create: `cloudflare-workers/api-worker/docs/HARVEST_COVERS.md`
- Modify: `cloudflare-workers/api-worker/README.md`

**Step 1: Write harvest documentation**

Create `cloudflare-workers/api-worker/docs/HARVEST_COVERS.md`:

```markdown
# ISBNdb Cover Harvest Task

One-time harvest of book cover images from ISBNdb API before subscription expires.

## Quick Start

```bash
cd cloudflare-workers/api-worker

# Dry run (test without API calls)
DRY_RUN=true npx wrangler dev --remote --task harvest-covers

# Production harvest
npx wrangler dev --remote --task harvest-covers
```

## What It Does

1. Reads curated book lists from `docs/testImages/csv-expansion/` (2015-2025)
2. Deduplicates by ISBN-13 (~500-775 unique books)
3. For each book:
   - Checks KV cache (skip if already harvested)
   - Queries ISBNdb API (with 1sec rate limit)
   - Falls back to Google Books if ISBNdb fails
   - Downloads cover image
   - Uploads to R2: `covers/isbn/{isbn13}.jpg`
   - Stores metadata in KV: `cover:{isbn}`
4. Logs failures to `failed_isbns.json`

## Expected Results

- **Coverage:** ~90% (700+/775 books)
- **ISBNdb Primary:** ~70% (avoid excessive fallback)
- **Execution Time:** ~13-15 minutes
- **Storage:** ~10-50MB in R2

## Post-Harvest Validation

```bash
# Verify R2 storage
npx wrangler r2 object list LIBRARY_DATA --prefix covers/isbn/ | wc -l

# Check KV metadata
npx wrangler kv:key get --binding=KV_CACHE "cover:9780451524935"

# Review failures
cat failed_isbns.json | jq '.totalFailed'
```

## Troubleshooting

**Rate limit errors:** ISBNdb has 5000 calls/day limit (should be fine for 775 books)

**R2 upload failures:** Check `LIBRARY_DATA` bucket exists and has write permissions

**No covers found:** Check ISBNdb subscription is still active

## Related Issues

- #202 - Harvest ISBNdb cover images before subscription expires
- #147 - Implement Edge Caching for Book Cover Images (R2 + Image Resizing)
- #201 - Remove ISBNdb dependency to reduce costs
```

**Step 2: Update main README**

Add to `cloudflare-workers/api-worker/README.md` (in "Tasks" section):

```markdown
### Cover Harvest Task

One-time harvest of ISBNdb cover images before subscription expires.

See [docs/HARVEST_COVERS.md](docs/HARVEST_COVERS.md) for details.

```bash
npx wrangler dev --remote --task harvest-covers
```
```

**Step 3: Run production harvest**

Run: `npx wrangler dev --remote --task harvest-covers`
Expected: Harvests ~700+ covers, execution time ~13-15 minutes

**Step 4: Commit documentation and final code**

```bash
git add docs/HARVEST_COVERS.md README.md src/tasks/harvest-covers.ts
git commit -m "docs: add harvest task documentation and finalize implementation"
```

---

## Task 10: Post-Harvest Validation & Cleanup

**Files:**
- Create: `cloudflare-workers/api-worker/scripts/validate-harvest.sh`

**Step 1: Create validation script**

Create `cloudflare-workers/api-worker/scripts/validate-harvest.sh`:

```bash
#!/bin/bash
set -e

echo "🔍 Validating ISBNdb Cover Harvest Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check R2 storage
echo ""
echo "📦 R2 Storage Check:"
COVER_COUNT=$(npx wrangler r2 object list LIBRARY_DATA --prefix covers/isbn/ | grep -c ".jpg" || echo "0")
echo "   Found $COVER_COUNT covers in R2"

# Check KV metadata (sample)
echo ""
echo "💾 KV Metadata Check:"
SAMPLE_ISBN="9780451524935"
METADATA=$(npx wrangler kv:key get --binding=KV_CACHE "cover:$SAMPLE_ISBN" || echo "")
if [ -n "$METADATA" ]; then
  echo "   ✓ Sample metadata exists for ISBN: $SAMPLE_ISBN"
  echo "   $METADATA" | jq .
else
  echo "   ✗ No metadata found for sample ISBN"
fi

# Check failed ISBNs
echo ""
echo "❌ Failed ISBNs:"
if [ -f "failed_isbns.json" ]; then
  FAILED_COUNT=$(cat failed_isbns.json | jq '.totalFailed')
  echo "   Total failed: $FAILED_COUNT"
  echo "   Top 5 failures:"
  cat failed_isbns.json | jq '.failures[:5] | .[] | {isbn, title, error: .isbndbError}'
else
  echo "   No failures logged (or file not found)"
fi

echo ""
echo "✅ Validation complete"
```

**Step 2: Make script executable and run**

Run:
```bash
chmod +x scripts/validate-harvest.sh
./scripts/validate-harvest.sh
```

Expected: Shows R2 count, KV metadata sample, and failures

**Step 3: Update GitHub Issue #202**

Add comment to GitHub Issue #202:

```markdown
## ✅ Harvest Complete

**Results:**
- Total books: XXX
- Successfully harvested: XXX (XX%)
- ISBNdb covers: XXX
- Google Books fallback: XXX
- Failed: XXX

**Storage:**
- R2 covers: XXX files (~XXmb)
- KV metadata: XXX entries

**Next Steps:**
- [ ] Review failed ISBNs (see `failed_isbns.json`)
- [ ] Proceed with Issue #147 (Edge Caching)
- [ ] Proceed with Issue #201 (Remove ISBNdb)

See `cloudflare-workers/api-worker/docs/HARVEST_COVERS.md` for details.
```

**Step 4: Commit validation script**

```bash
git add scripts/validate-harvest.sh
git commit -m "feat: add post-harvest validation script"
```

**Step 5: Push feature branch and create PR**

```bash
git push origin feature/issue-202-harvest-covers

# Create PR
gh pr create \
  --title "feat: ISBNdb cover harvest task (Issue #202)" \
  --body "One-time harvest of ~500-775 book covers from ISBNdb API before subscription expires.

## Changes
- Added Wrangler CLI task for cover harvesting
- CSV parsing and deduplication
- ISBNdb API integration with Google Books fallback
- R2 storage + KV metadata
- Progress tracking and failure logging
- Dry-run mode and pre-flight checks

## Testing
- ✅ Dry run tested
- ✅ Production harvest completed (XXX/XXX covers)
- ✅ R2 and KV validation passed

Closes #202"
```

---

## Summary

**Implementation Checklist:**

- [x] Task 1: TypeScript types and interfaces
- [x] Task 2: CSV parsing and deduplication
- [x] Task 3: ISBNdb API integration
- [x] Task 4: Google Books fallback
- [x] Task 5: R2 storage and KV metadata
- [x] Task 6: Main harvest loop and progress
- [x] Task 7: Wrangler CLI integration
- [x] Task 8: Dry-run mode and pre-flight checks
- [x] Task 9: Documentation and final testing
- [x] Task 10: Post-harvest validation and cleanup

**Key Files Created:**
- `src/tasks/harvest-covers.ts` (main harvest logic)
- `src/tasks/types/harvest-types.ts` (TypeScript types)
- `docs/HARVEST_COVERS.md` (documentation)
- `scripts/validate-harvest.sh` (validation script)

**Estimated Time:** 4-6 hours (including testing and validation)

**Critical Success Factors:**
1. ISBNdb subscription still active
2. R2 and KV write permissions working
3. CSV files accessible and properly formatted
4. Rate limiting prevents API quota exhaustion
5. ≥90% coverage target achieved
