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
 */
async function collectAnalyticsISBNs(env) {
  try {
    // Query Analytics Engine for ISBN searches in last 7 days
    const query = `
      SELECT DISTINCT blob2 as isbn
      FROM books_api_cache_metrics
      WHERE timestamp > NOW() - INTERVAL '7' DAY
        AND blob1 = 'isbn'
      LIMIT 100
    `;

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

    if (!response.ok) {
      console.warn('Analytics Engine query failed:', response.status);
      return [];
    }

    const data = await response.json();
    return data.data?.map(row => row.isbn) || [];
  } catch (error) {
    console.error('Error collecting Analytics ISBNs:', error);
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

  // Initialize services
  const isbndbApi = new ISBNdbAPI(env.ISBNDB_API_KEY);
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
  console.log('📚 Collecting ISBNs...');
  const analyticsISBNs = await collectAnalyticsISBNs(env);
  const userLibraryISBNs = await collectUserLibraryISBNs(env);

  // Deduplicate and prioritize
  const allISBNs = [...new Set([...analyticsISBNs, ...userLibraryISBNs])];
  console.log(`Found ${allISBNs.length} unique ISBNs (${analyticsISBNs.length} analytics, ${userLibraryISBNs.length} library)`);

  if (allISBNs.length === 0) {
    console.log('✅ No ISBNs to harvest');
    return {
      success: true,
      stats: { total: 0, successful: 0, skipped: 0, noCover: 0, errors: 0 },
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

  console.log('');
  console.log('='.repeat(60));
  console.log('📊 Harvest Summary');
  console.log('='.repeat(60));
  console.log(`Total ISBNs: ${stats.total}`);
  console.log(`Successful: ${stats.successful}`);
  console.log(`Skipped (already harvested): ${stats.skipped}`);
  console.log(`No cover: ${stats.noCover}`);
  console.log(`Errors: ${stats.errors}`);
  console.log(`Total size: ${totalSizeMB} MB`);
  console.log(`Average compression: ${avgSavings}%`);
  console.log(`Duration: ${(duration / 1000).toFixed(1)}s`);
  console.log('='.repeat(60));

  return {
    success: true,
    stats: {
      ...stats,
      avgSavings,
      totalSizeMB,
      duration
    },
    results
  };
}
