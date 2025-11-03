import type {
  BookEntry,
  CoverData,
  CoverMetadata,
  HarvestResult,
  HarvestReport,
  Env
} from './types/harvest-types';
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

/**
 * Helper to get API key from environment (handles both string and object types)
 */
async function getApiKey(env: Env): Promise<string> {
  const apiKey = typeof env.ISBNDB_API_KEY === 'object'
    ? await env.ISBNDB_API_KEY.get()
    : env.ISBNDB_API_KEY;

  if (!apiKey) {
    throw new Error('ISBNDB_API_KEY not found');
  }

  return apiKey;
}

/**
 * Fetch cover data from ISBNdb API
 */
async function fetchFromISBNdb(isbn: string, env: Env): Promise<CoverData | null> {
  try {
    // Enforce rate limit (1000ms between requests)
    await enforceRateLimit(env);

    const apiKey = await getApiKey(env);

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
    console.error(`ISBNdb error for ${isbn}: ${error instanceof Error ? error.message : String(error)}`);
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
    console.error(`Google Books error for "${title}" by ${author}: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

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
      contentType: response.headers.get('Content-Type') || 'image/jpeg',
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

/**
 * Harvest cover for a single book
 */
async function harvestSingleBook(
  entry: BookEntry,
  env: Env,
  isDryRun: boolean = false
): Promise<HarvestResult> {
  const { isbn, title, author } = entry;

  try {
    // Dry run mode - skip actual work
    if (isDryRun) {
      console.log(`  [DRY RUN] Would fetch cover for: ${isbn}`);
      return { isbn, title, author, success: true, source: 'isbndb' };
    }

    // Check if already cached
    const kvKey = `cover:${isbn}`;
    const existing = await env.KV_CACHE.get(kvKey);

    if (existing) {
      console.log(`  ⏭ Already cached: ${isbn}`);
      try {
        const metadata: CoverMetadata = JSON.parse(existing);
        return { isbn, title, author, success: true, source: metadata.source };
      } catch {
        // If parsing fails, assume isbndb
        return { isbn, title, author, success: true, source: 'isbndb' };
      }
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
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

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

/**
 * Main entry point for ISBNdb cover harvest task
 *
 * Usage: npx wrangler dev --remote --task harvest-covers
 */
export async function harvestCovers(env: Env): Promise<HarvestReport> {
  console.log('🚀 ISBNdb Cover Harvest Starting...');
  console.log('━'.repeat(60));

  const startTime = Date.now();

  // Pre-flight checks
  console.log('🔍 Running pre-flight checks...');

  try {
    // Check ISBNDB_API_KEY
    await getApiKey(env);
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
    console.error('❌ Pre-flight check failed:', error instanceof Error ? error.message : String(error));
    throw error;
  }

  const isDryRun = process.env.DRY_RUN === 'true';

  if (isDryRun) {
    console.log('⚠️  DRY RUN MODE - No API calls or uploads will be made\n');
  }

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

    const result = await harvestSingleBook(book, env, isDryRun);
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
        error: r.error,
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
