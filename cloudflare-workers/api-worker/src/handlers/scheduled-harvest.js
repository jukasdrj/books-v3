/**
 * Scheduled ISBNdb Cover Harvest Handler
 *
 * Daily cron job (3 AM UTC) that harvests book cover images from ISBNdb
 * before paid membership expires. Pre-populates R2 + KV for instant cache hits.
 *
 * Data Sources:
 * 1. User Library ISBNs (from SwiftData sync via CloudKit)
 * 2. Popular Search ISBNs (from Analytics Engine)
 *
 * Flow:
 * 1. Collect ISBNs from both sources
 * 2. Filter out already-harvested covers (check KV)
 * 3. Rate-limited fetch from ISBNdb (10 req/sec)
 * 4. Download cover image
 * 5. Compress to WebP (85% quality, 60% savings)
 * 6. Store in R2 (human-readable key: covers/{isbn13})
 * 7. Index in KV (cover:{isbn} → covers/{isbn})
 *
 * Cron Schedule: 0 3 * * * (daily at 3 AM UTC)
 */

import { ISBNdbAPI } from '../services/isbndb-api.js';
import { RateLimiter } from '../utils/rate-limiter.js';
import { getTopEditions } from '../services/edition-discovery.js';

/**
 * Load curated ISBN list from isbn-harvest-list.txt (478 ISBNs from testImages/csv-expansion)
 */
async function loadCuratedISBNs() {
  try {
    // In Workers, we can't use fs, so we'll inline the ISBN list for now
    // This list is extracted from testImages/csv-expansion/*.csv (2015-2025 bestsellers)
    console.log('📥 Fetching curated ISBNs from GitHub...');
    const response = await fetch('https://raw.githubusercontent.com/jukasdrj/books-tracker-v1/main/testImages/csv-expansion/combined_library_expanded.csv');

    console.log(`GitHub fetch status: ${response.status}`);
    if (!response.ok) {
      console.warn(`Failed to load curated ISBNs from GitHub (HTTP ${response.status}), using inline list`);
      return await loadInlineISBNs();
    }

    const csvText = await response.text();
    console.log(`CSV text length: ${csvText.length} bytes`);

    // Extract ISBNs from CSV (handles both Unix \n and Windows \r\n line endings)
    const isbns = csvText.split(/\r?\n/)
      .map(line => {
        // Match 13-digit ISBN at end of line (with optional trailing whitespace/carriage return)
        const match = line.trim().match(/([0-9]{13})$/);
        return match ? match[1] : null;
      })
      .filter(isbn => isbn !== null);

    console.log(`✅ Loaded ${isbns.length} curated ISBNs from GitHub`);
    if (isbns.length > 0) {
      console.log(`Sample ISBNs: ${isbns.slice(0, 3).join(', ')}`);
    }
    return isbns;
  } catch (error) {
    console.error('❌ Error loading curated ISBNs:', error);
    return await loadInlineISBNs();
  }
}

/**
 * Fallback inline ISBN list (extracted from testImages/csv-expansion)
 */
async function loadInlineISBNs() {
  // Extract ISBNs from local Worker deployment
  // This is a subset - full list will be loaded from GitHub
  const inlineISBNs = [
    '9780385529985', '9780553448122', '9780812986481', '9780735224292',
    '9780743247542', '9781607747307', '9780399590504', '9780062429964',
    '9780062409850', '9781594633940', '9780802124944', '9781451659224',
    '9780345542908', '9780525555360', '9780802123411', '9780812993541',
    '9781594206274', '9781594633661', '9780385353779', '9780385539458'
  ];
  console.log(`Using ${inlineISBNs.length} inline ISBNs as fallback`);
  return inlineISBNs;
}

/**
 * Compress image to WebP using Cloudflare Image Resizing
 * (Reused logic from image-proxy.ts)
 */
async function compressToWebP(imageData, quality = 85) {
  try {
    const imageResponse = new Response(imageData, {
      headers: {
        'Content-Type': 'image/jpeg',
        'CF-Image-Format': 'webp',
        'CF-Image-Quality': quality.toString()
      }
    });

    const transformed = await fetch(imageResponse.url, {
      cf: {
        image: {
          format: 'webp',
          quality: quality
        }
      }
    });

    if (!transformed.ok) {
      return null;
    }

    return await transformed.arrayBuffer();
  } catch (error) {
    console.error('WebP compression error:', error);
    return null;
  }
}

/**
 * Collect ISBNs from Analytics Engine (popular searches)
 * Uses books_api_provider_performance dataset (PROVIDER_ANALYTICS binding)
 *
 * NOTE: GOOGLE_BOOKS_ANALYTICS binding in external-apis.js doesn't exist in wrangler.toml.
 * This is a known issue - Analytics logging is currently broken. Once Priority 1 fix is deployed,
 * this function will start returning ISBNs.
 *
 * Expected Schema (once logging is fixed):
 * - blobs[0] = ISBN
 * - blobs[1] = 'isbn_search' or 'isbn_search_error'
 * - indexes[0] = 'google-books-isbn' or 'google-books-error'
 * - doubles[0] = processing time
 * - doubles[1] = result count
 */
async function collectAnalyticsISBNs(env) {
  try {
    console.log('🔍 Querying Analytics Engine for popular ISBNs...');

    // Check required env vars
    if (!env.CF_ACCOUNT_ID || !env.CF_API_TOKEN) {
      console.warn('⚠️ CF_ACCOUNT_ID or CF_API_TOKEN not configured - skipping Analytics ISBNs');
      return [];
    }

    // Query Analytics Engine for ISBN searches in last 7 days (conservative initial window)
    // Using index1 = 'google-books-isbn' to filter for successful ISBN lookups
    // NOTE: Can expand to 14-30 days after initial testing confirms data collection
    const query = `
      SELECT blob1 as isbn, COUNT(*) as search_count
      FROM books_api_provider_performance
      WHERE timestamp > NOW() - INTERVAL '7' DAY
        AND index1 = 'google-books-isbn'
        AND blob2 = 'isbn_search'
      GROUP BY isbn
      ORDER BY search_count DESC
      LIMIT 500
    `;

    console.log('Analytics Engine query:', query.trim());

    const response = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.CF_API_TOKEN}`,
          'Content-Type': 'text/plain'
        },
        body: query
      }
    );

    console.log(`Analytics API response: ${response.status} ${response.statusText}`);

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ Analytics Engine query failed (${response.status}):`, errorText);
      console.error('This is expected until Priority 1 (GOOGLE_BOOKS_ANALYTICS binding fix) is deployed');
      return [];
    }

    const data = await response.json();
    console.log('Analytics response structure:', JSON.stringify(data, null, 2));

    const isbns = data.data?.map(row => row.isbn).filter(isbn => isbn) || [];
    console.log(`✅ Found ${isbns.length} popular ISBNs from Analytics Engine`);

    if (isbns.length > 0) {
      console.log(`Top 5 ISBNs: ${isbns.slice(0, 5).join(', ')}`);
    } else {
      console.warn('⚠️ Analytics Engine returned 0 ISBNs');
      console.warn('Likely cause: GOOGLE_BOOKS_ANALYTICS binding missing in wrangler.toml (no data being logged)');
      console.warn('Fix: Add binding or update external-apis.js to use PROVIDER_ANALYTICS');
    }

    return isbns;
  } catch (error) {
    console.error('❌ Error collecting Analytics ISBNs:', error.message);
    console.error('Stack trace:', error.stack);
    return [];
  }
}

/**
 * Collect ISBNs from user library (via D1 or KV)
 * Note: This requires user library sync to be implemented
 */
async function collectUserLibraryISBNs(env) {
  // TODO: Implement once CloudKit → D1 sync is active
  // For now, return empty array (Phase 2 feature)
  return [];
}

/**
 * Discover multiple editions for each Work
 * Takes subset of curated ISBNs, queries Google Books for all editions of each Work,
 * and returns expanded ISBN list with 2-3 editions per Work
 *
 * @param {string[]} seedISBNs - Initial ISBN list (e.g., 350 Works)
 * @param {Object} env - Worker environment bindings
 * @param {number} editionsPerWork - Max editions to discover per Work (default: 3)
 * @returns {Promise<string[]>} Expanded ISBN list (e.g., 700-1050 ISBNs)
 */
async function discoverMultiEditionISBNs(seedISBNs, env, editionsPerWork = 3) {
  console.log(`🔍 Discovering multi-edition ISBNs for ${seedISBNs.length} Works...`);

  const allISBNs = new Set();
  const rateLimiter = new RateLimiter(10); // Google Books rate limit: 10 req/sec

  let worksProcessed = 0;
  let editionsDiscovered = 0;

  for (const seedISBN of seedISBNs) {
    await rateLimiter.waitForSlot();

    try {
      // Query Google Books for this ISBN to get Work metadata
      const metadataUrl = new URL('https://www.googleapis.com/books/v1/volumes');
      metadataUrl.searchParams.set('q', `isbn:${seedISBN}`);

      const metadataResponse = await fetch(metadataUrl.toString());

      if (!metadataResponse.ok) {
        console.warn(`Failed to fetch metadata for ${seedISBN}: ${metadataResponse.status}`);
        allISBNs.add(seedISBN); // Fall back to seed ISBN
        continue;
      }

      const metadataData = await metadataResponse.json();

      if (!metadataData.items || metadataData.items.length === 0) {
        console.warn(`No metadata found for ${seedISBN}`);
        allISBNs.add(seedISBN); // Fall back to seed ISBN
        continue;
      }

      const volumeInfo = metadataData.items[0].volumeInfo;
      const title = volumeInfo.title;
      const authors = volumeInfo.authors || [];

      if (!title || authors.length === 0) {
        console.warn(`Incomplete metadata for ${seedISBN}`);
        allISBNs.add(seedISBN); // Fall back to seed ISBN
        continue;
      }

      // Discover top editions for this Work
      const editions = await getTopEditions({ title, authors }, env, editionsPerWork);

      if (editions.length === 0) {
        allISBNs.add(seedISBN); // Fall back to seed ISBN
      } else {
        editions.forEach(ed => allISBNs.add(ed.isbn));
        editionsDiscovered += editions.length;
      }

      worksProcessed++;

      // Progress logging every 50 Works
      if (worksProcessed % 50 === 0) {
        console.log(`  Progress: ${worksProcessed}/${seedISBNs.length} Works, ${allISBNs.size} ISBNs discovered`);
      }

    } catch (error) {
      console.error(`Edition discovery error for ${seedISBN}:`, error);
      allISBNs.add(seedISBN); // Fall back to seed ISBN
    }
  }

  console.log(`✅ Multi-edition discovery complete: ${worksProcessed} Works → ${allISBNs.size} ISBNs (avg ${(allISBNs.size / worksProcessed).toFixed(1)} editions/work)`);

  return Array.from(allISBNs);
}

/**
 * Check if cover already harvested
 */
async function isCoverHarvested(isbn, env) {
  const kvKey = `cover:${isbn}`;
  const existing = await env.KV_CACHE.get(kvKey);
  return existing !== null;
}

/**
 * Harvest single ISBN cover
 */
async function harvestISBN(isbn, isbndbApi, env, stats) {
  const startTime = Date.now();

  try {
    // Check if already harvested
    if (await isCoverHarvested(isbn, env)) {
      console.log(`Skipping ${isbn} - already harvested`);
      stats.skipped++;
      return { isbn, status: 'skipped' };
    }

    // Fetch from ISBNdb
    console.log(`Harvesting ${isbn}...`);
    const bookData = await isbndbApi.fetchBook(isbn);

    if (!bookData) {
      console.log(`No cover for ${isbn}`);
      stats.noCover++;
      return { isbn, status: 'no_cover' };
    }

    // Download image
    const imageResponse = await fetch(bookData.image, {
      headers: { 'User-Agent': 'BooksTrack-Harvest/1.0' }
    });

    if (!imageResponse.ok) {
      throw new Error(`Image download failed: ${imageResponse.status}`);
    }

    const imageData = await imageResponse.arrayBuffer();
    const originalSize = imageData.byteLength;

    // Compress to WebP
    const compressed = await compressToWebP(imageData, 85);
    const finalData = compressed || imageData;
    const compressedSize = finalData.byteLength;
    const savings = Math.round(((originalSize - compressedSize) / originalSize) * 100);

    console.log(`Compressed ${isbn}: ${originalSize} → ${compressedSize} bytes (${savings}% savings)`);

    // Store in R2 (human-readable key)
    const r2Key = `covers/${isbn}`;
    await env.BOOK_COVERS.put(r2Key, finalData, {
      httpMetadata: { contentType: compressed ? 'image/webp' : 'image/jpeg' },
      customMetadata: {
        isbn,
        title: bookData.title,
        authors: bookData.authors.join(', '),
        originalSize: originalSize.toString(),
        compressedSize: compressedSize.toString(),
        compressionSavings: savings.toString(),
        harvestedAt: new Date().toISOString(),
        source: 'isbndb-harvest'
      }
    });

    // Index in KV
    const kvKey = `cover:${isbn}`;
    await env.KV_CACHE.put(kvKey, JSON.stringify({
      r2Key,
      isbn,
      title: bookData.title,
      authors: bookData.authors,
      harvestedAt: new Date().toISOString(),
      originalSize,
      compressedSize,
      savings
    }), {
      expirationTtl: 365 * 24 * 60 * 60 // 1 year
    });

    const processingTime = Date.now() - startTime;
    console.log(`✅ Harvested ${isbn} in ${processingTime}ms`);

    stats.successful++;
    stats.totalSize += compressedSize;
    stats.totalSavings += savings;

    return {
      isbn,
      status: 'success',
      originalSize,
      compressedSize,
      savings,
      processingTime
    };

  } catch (error) {
    console.error(`Error harvesting ${isbn}:`, error.message);
    stats.errors++;
    return { isbn, status: 'error', error: error.message };
  }
}

/**
 * Main handler for scheduled harvest
 */
export async function handleScheduledHarvest(env) {
  const startTime = Date.now();
  console.log('🌾 Starting ISBNdb cover harvest...');

  // Resolve ISBNdb API key (supports both Secrets Store binding and plain string)
  const apiKey = env.ISBNDB_API_KEY?.get
    ? await env.ISBNDB_API_KEY.get()
    : env.ISBNDB_API_KEY;

  if (!apiKey) {
    console.error('❌ ISBNDB_API_KEY not configured');
    return {
      success: false,
      error: 'ISBNDB_API_KEY not configured',
      duration: Date.now() - startTime
    };
  }

  // Initialize services
  const isbndbApi = new ISBNdbAPI(apiKey);
  const rateLimiter = new RateLimiter(10); // 10 req/sec

  // Health check
  const healthy = await isbndbApi.healthCheck();
  if (!healthy) {
    console.error('❌ ISBNdb API health check failed');
    return {
      success: false,
      error: 'ISBNdb API unavailable',
      duration: Date.now() - startTime
    };
  }

  console.log('✅ ISBNdb API healthy');

  // Collect ISBNs from all sources
  console.log('');
  console.log('='.repeat(60));
  console.log('📚 Collecting ISBNs from all sources...');
  console.log('='.repeat(60));

  // Load curated ISBN list from testImages/csv-expansion (478 unique ISBNs)
  // Extracted from yearly bestseller CSVs (2015-2025)
  const curatedISBNs = await loadCuratedISBNs();
  console.log(`1️⃣ Curated ISBNs: ${curatedISBNs.length} (priority 1 - bestsellers 2015-2025)`);

  // Multi-edition discovery: Take 350 Works, discover 2-3 editions each → 700-1050 ISBNs
  console.log('');
  console.log('🔍 Starting multi-edition discovery for top 350 Works...');
  const seedWorks = curatedISBNs.slice(0, 350); // Take first 350 Works
  const multiEditionISBNs = await discoverMultiEditionISBNs(seedWorks, env, 3);
  console.log(`   📚 Multi-edition ISBNs: ${multiEditionISBNs.length} (from ${seedWorks.length} Works)`);

  const analyticsISBNs = await collectAnalyticsISBNs(env);
  console.log(`2️⃣ Analytics ISBNs: ${analyticsISBNs.length} (priority 2 - popular searches)`);

  const userLibraryISBNs = await collectUserLibraryISBNs(env);
  console.log(`3️⃣ User Library ISBNs: ${userLibraryISBNs.length} (priority 3 - user collections)`);

  // Deduplicate with priority ordering (multi-edition > analytics > user library)
  // Slice at 1000 to respect ISBNdb API limit
  const allISBNs = [
    ...new Set([
      ...multiEditionISBNs,  // Priority 1: Multi-edition bestsellers (700-1050 ISBNs)
      ...analyticsISBNs,     // Priority 2: Popular searches (0-300 ISBNs fill remaining capacity)
      ...userLibraryISBNs    // Priority 3: User library collections (future)
    ])
  ].slice(0, 1000);  // Cap at ISBNdb API limit

  const totalBeforeCap = multiEditionISBNs.length + analyticsISBNs.length + userLibraryISBNs.length;
  const duplicatesRemoved = totalBeforeCap - allISBNs.length;

  console.log('');
  console.log('📊 ISBN Collection Summary:');
  console.log(`   Total before dedup: ${totalBeforeCap}`);
  console.log(`   Duplicates removed: ${duplicatesRemoved}`);
  console.log(`   Unique ISBNs: ${allISBNs.length}`);
  console.log(`   Multi-edition: ${multiEditionISBNs.length}`);
  console.log(`   Analytics: ${analyticsISBNs.length}`);
  console.log(`   User Library: ${userLibraryISBNs.length}`);

  if (allISBNs.length >= 1000) {
    console.warn('⚠️ Capped at 1000 ISBNs (ISBNdb API daily limit reached)');
  } else {
    const unused = 1000 - allISBNs.length;
    console.log(`✅ Using ${allISBNs.length}/1000 ISBNdb requests (${unused} unused capacity)`);
  }
  console.log('='.repeat(60));
  console.log('');

  if (allISBNs.length === 0) {
    console.log('✅ No ISBNs to harvest');
    return {
      success: true,
      stats: {
        total: 0,
        successful: 0,
        skipped: 0,
        noCover: 0,
        errors: 0,
        sources: {
          curated: curatedISBNs.length,
          analytics: analyticsISBNs.length,
          userLibrary: userLibraryISBNs.length
        }
      },
      duration: Date.now() - startTime
    };
  }

  // Harvest with rate limiting
  const stats = {
    total: allISBNs.length,
    successful: 0,
    skipped: 0,
    noCover: 0,
    errors: 0,
    totalSize: 0,
    totalSavings: 0
  };

  const results = [];

  for (const isbn of allISBNs) {
    // Rate limiting
    const waitTime = await rateLimiter.acquire();
    if (waitTime > 0) {
      console.log(`Rate limited: waited ${waitTime}ms`);
    }

    const result = await harvestISBN(isbn, isbndbApi, env, stats);
    results.push(result);

    // Log progress every 10 ISBNs
    if (results.length % 10 === 0) {
      console.log(`Progress: ${results.length}/${allISBNs.length} processed`);
    }
  }

  // Calculate averages
  const avgSavings = stats.successful > 0
    ? Math.round(stats.totalSavings / stats.successful)
    : 0;
  const totalSizeMB = (stats.totalSize / 1024 / 1024).toFixed(2);
  const duration = Date.now() - startTime;
  const durationMinutes = (duration / 1000 / 60).toFixed(1);

  console.log('');
  console.log('='.repeat(60));
  console.log('📊 Harvest Summary');
  console.log('='.repeat(60));
  console.log('');
  console.log('📚 ISBN Sources:');
  console.log(`   Curated (priority 1): ${curatedISBNs.length} ISBNs`);
  console.log(`   Analytics (priority 2): ${analyticsISBNs.length} ISBNs`);
  console.log(`   User Library (priority 3): ${userLibraryISBNs.length} ISBNs`);
  console.log(`   Total unique: ${allISBNs.length} ISBNs`);
  console.log('');
  console.log('✅ Processing Results:');
  console.log(`   Total processed: ${stats.total}`);
  console.log(`   Successful: ${stats.successful}`);
  console.log(`   Skipped (already harvested): ${stats.skipped}`);
  console.log(`   No cover available: ${stats.noCover}`);
  console.log(`   Errors: ${stats.errors}`);
  console.log('');
  console.log('💾 Storage:');
  console.log(`   Total size: ${totalSizeMB} MB`);
  console.log(`   Average compression: ${avgSavings}%`);
  console.log('');
  console.log('⏱️ Performance:');
  console.log(`   Duration: ${durationMinutes} minutes (${(duration / 1000).toFixed(1)}s)`);
  console.log(`   ISBNdb API usage: ${allISBNs.length}/1000 daily limit (${Math.round((allISBNs.length / 1000) * 100)}%)`);
  console.log('='.repeat(60));

  return {
    success: true,
    stats: {
      ...stats,
      avgSavings,
      totalSizeMB,
      duration,
      sources: {
        curated: curatedISBNs.length,
        analytics: analyticsISBNs.length,
        userLibrary: userLibraryISBNs.length,
        totalUnique: allISBNs.length
      },
      apiUsage: {
        used: allISBNs.length,
        limit: 1000,
        percentUsed: Math.round((allISBNs.length / 1000) * 100)
      }
    },
    results
  };
}
