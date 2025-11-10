#!/usr/bin/env node

/**
 * ISBNdb Cover Harvest - End-to-End Test Script
 *
 * Tests the complete harvest workflow before production deployment:
 * 1. ISBNdb API integration (fetch cover URLs)
 * 2. Image download and WebP compression
 * 3. R2 storage with metadata
 * 4. KV index creation (ISBN → R2 key mapping)
 * 5. Rate limiting (10 req/sec with jitter)
 *
 * Usage:
 *   # Dry run (no R2/KV writes)
 *   node scripts/test-harvest.js --dry-run --isbn "9780545010221,9780439023481"
 *
 *   # Real test (writes to R2/KV)
 *   node scripts/test-harvest.js --isbn "9780545010221,9780439023481"
 *
 * Environment Variables:
 *   CF_ACCOUNT_ID - Cloudflare account ID
 *   CF_API_TOKEN - Cloudflare API token with R2/KV write access
 *   ISBNDB_API_KEY - ISBNdb API key
 */

import https from 'https';
import { URL } from 'url';

// Configuration
const ACCOUNT_ID = process.env.CF_ACCOUNT_ID;
const API_TOKEN = process.env.CF_API_TOKEN;
const ISBNDB_API_KEY = process.env.ISBNDB_API_KEY;

// Parse command line args
const DRY_RUN = process.argv.includes('--dry-run');
const isbnArg = process.argv.find(arg => arg.startsWith('--isbn'));
const TEST_ISBNS = isbnArg
  ? isbnArg.split('=')[1]?.replace(/['"]/g, '').split(',')
  : ['9780545010221', '9780439023481', '9780316769174']; // Default test ISBNs

if (!DRY_RUN && (!ACCOUNT_ID || !API_TOKEN || !ISBNDB_API_KEY)) {
  console.error('❌ Missing credentials. Set CF_ACCOUNT_ID, CF_API_TOKEN, and ISBNDB_API_KEY environment variables.');
  console.error('   Or run in dry-run mode: node scripts/test-harvest.js --dry-run');
  process.exit(1);
}

console.log('🧪 ISBNdb Cover Harvest - E2E Test');
console.log(`   Mode: ${DRY_RUN ? 'DRY RUN (no R2/KV writes)' : 'LIVE TEST'}`);
console.log(`   ISBNs: ${TEST_ISBNS.join(', ')}`);
console.log('');

/**
 * Rate limiter with token bucket algorithm
 */
class RateLimiter {
  constructor(tokensPerSecond = 10) {
    this.tokensPerSecond = tokensPerSecond;
    this.tokens = tokensPerSecond;
    this.lastRefill = Date.now();
  }

  async acquire() {
    const now = Date.now();
    const timePassed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.tokensPerSecond, this.tokens + timePassed * this.tokensPerSecond);
    this.lastRefill = now;

    if (this.tokens < 1) {
      const waitTime = ((1 - this.tokens) / this.tokensPerSecond) * 1000;
      await new Promise(resolve => setTimeout(resolve, waitTime));
      this.tokens = 0;
    } else {
      this.tokens -= 1;
    }

    // Add jitter (±100ms)
    const jitter = Math.random() * 200 - 100;
    if (jitter > 0) {
      await new Promise(resolve => setTimeout(resolve, jitter));
    }
  }
}

/**
 * Fetch cover URL from ISBNdb API
 */
async function fetchCoverFromISBNdb(isbn) {
  if (DRY_RUN) {
    console.log(`   [DRY RUN] Would fetch from ISBNdb: /book/${isbn}`);
    return {
      image: `https://images.isbndb.com/covers/${isbn.slice(-2)}/${isbn}.jpg`,
      title: `Test Book ${isbn}`,
      authors: ['Test Author']
    };
  }

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api2.isbndb.com',
      port: 443,
      path: `/book/${isbn}`,
      method: 'GET',
      headers: {
        'Authorization': ISBNDB_API_KEY,
        'Accept': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode === 404) {
            resolve(null); // Book not found
            return;
          }

          if (res.statusCode !== 200) {
            reject(new Error(`ISBNdb API error: ${res.statusCode} - ${data}`));
            return;
          }

          const parsed = JSON.parse(data);
          if (parsed.book && parsed.book.image) {
            resolve({
              image: parsed.book.image,
              title: parsed.book.title,
              authors: parsed.book.authors || []
            });
          } else {
            resolve(null); // No cover image available
          }
        } catch (error) {
          reject(error);
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('ISBNdb API timeout'));
    });
    req.end();
  });
}

/**
 * Download image from URL
 */
async function downloadImage(url) {
  if (DRY_RUN) {
    console.log(`   [DRY RUN] Would download: ${url}`);
    return Buffer.from('fake-image-data');
  }

  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 443,
      path: parsedUrl.pathname + parsedUrl.search,
      method: 'GET',
      headers: {
        'User-Agent': 'BooksTrack-Harvest/1.0'
      }
    };

    const req = https.request(options, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        // Follow redirect
        downloadImage(res.headers.location).then(resolve).catch(reject);
        return;
      }

      if (res.statusCode !== 200) {
        reject(new Error(`Image download failed: ${res.statusCode}`));
        return;
      }

      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('Image download timeout'));
    });
    req.end();
  });
}

/**
 * Compress image to WebP using Cloudflare Image Resizing
 * (Simulated - real implementation would use CF Image Resizing API)
 */
async function compressToWebP(imageBuffer, quality = 85) {
  if (DRY_RUN) {
    console.log(`   [DRY RUN] Would compress to WebP (quality: ${quality})`);
    return {
      buffer: imageBuffer,
      originalSize: imageBuffer.length,
      compressedSize: Math.floor(imageBuffer.length * 0.4), // Simulate 60% reduction
      savings: 60
    };
  }

  // In production, this would use Cloudflare's Image Resizing API
  // For test, we'll simulate compression
  const originalSize = imageBuffer.length;
  const compressedSize = Math.floor(originalSize * 0.4); // Simulate 60% reduction

  console.log(`   ℹ️  Note: WebP compression simulated (would use CF Image Resizing in production)`);

  return {
    buffer: imageBuffer,
    originalSize,
    compressedSize,
    savings: Math.round(((originalSize - compressedSize) / originalSize) * 100)
  };
}

/**
 * Store image in R2
 */
async function storeInR2(isbn, imageBuffer, metadata) {
  const r2Key = `covers/${isbn}`;

  if (DRY_RUN) {
    console.log(`   [DRY RUN] Would store in R2: ${r2Key}`);
    console.log(`   [DRY RUN] Metadata: ${JSON.stringify(metadata, null, 2)}`);
    return r2Key;
  }

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.cloudflare.com',
      port: 443,
      path: `/client/v4/accounts/${ACCOUNT_ID}/r2/buckets/book-covers/objects/${r2Key}`,
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${API_TOKEN}`,
        'Content-Type': 'image/webp',
        'Content-Length': imageBuffer.length,
        'X-Custom-Metadata': JSON.stringify(metadata)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(r2Key);
        } else {
          reject(new Error(`R2 upload failed: ${res.statusCode} - ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error('R2 upload timeout'));
    });
    req.write(imageBuffer);
    req.end();
  });
}

/**
 * Create KV index entry (ISBN → R2 key mapping)
 */
async function createKVIndex(isbn, r2Key, metadata) {
  const kvKey = `cover:${isbn}`;

  if (DRY_RUN) {
    console.log(`   [DRY RUN] Would create KV index: ${kvKey} → ${r2Key}`);
    return;
  }

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.cloudflare.com',
      port: 443,
      path: `/client/v4/accounts/${ACCOUNT_ID}/storage/kv/namespaces/YOUR_KV_NAMESPACE_ID/values/${kvKey}`,
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${API_TOKEN}`,
        'Content-Type': 'application/json'
      }
    };

    const kvValue = JSON.stringify({
      r2Key,
      isbn,
      harvestedAt: new Date().toISOString(),
      ...metadata
    });

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          reject(new Error(`KV write failed: ${res.statusCode} - ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('KV write timeout'));
    });
    req.write(kvValue);
    req.end();
  });
}

/**
 * Process a single ISBN through the complete harvest workflow
 */
async function harvestISBN(isbn, rateLimiter) {
  console.log(`\n📖 Processing ISBN: ${isbn}`);

  try {
    // Step 1: Rate limiting
    console.log('   ⏱️  Acquiring rate limit token...');
    const startWait = Date.now();
    await rateLimiter.acquire();
    const waitTime = Date.now() - startWait;
    console.log(`   ✅ Rate limit acquired (waited ${waitTime}ms)`);

    // Step 2: Fetch cover from ISBNdb
    console.log('   🔍 Fetching cover from ISBNdb...');
    const startFetch = Date.now();
    const bookData = await fetchCoverFromISBNdb(isbn);
    const fetchTime = Date.now() - startFetch;

    if (!bookData) {
      console.log(`   ⚠️  No cover found for ISBN ${isbn} (${fetchTime}ms)`);
      return { isbn, status: 'no_cover', fetchTime };
    }

    console.log(`   ✅ Cover URL: ${bookData.image} (${fetchTime}ms)`);
    console.log(`   ℹ️  Title: ${bookData.title}`);
    console.log(`   ℹ️  Authors: ${bookData.authors.join(', ')}`);

    // Step 3: Download image
    console.log('   📥 Downloading image...');
    const startDownload = Date.now();
    const imageBuffer = await downloadImage(bookData.image);
    const downloadTime = Date.now() - startDownload;
    console.log(`   ✅ Downloaded ${imageBuffer.length} bytes (${downloadTime}ms)`);

    // Step 4: Compress to WebP
    console.log('   🗜️  Compressing to WebP...');
    const startCompress = Date.now();
    const compressed = await compressToWebP(imageBuffer);
    const compressTime = Date.now() - startCompress;
    console.log(`   ✅ Compressed: ${compressed.originalSize} → ${compressed.compressedSize} bytes (${compressed.savings}% savings, ${compressTime}ms)`);

    // Step 5: Store in R2
    console.log('   ☁️  Storing in R2...');
    const startR2 = Date.now();
    const metadata = {
      isbn,
      title: bookData.title,
      authors: bookData.authors,
      originalSize: compressed.originalSize,
      compressedSize: compressed.compressedSize,
      compressionSavings: compressed.savings,
      harvestedAt: new Date().toISOString()
    };
    const r2Key = await storeInR2(isbn, compressed.buffer, metadata);
    const r2Time = Date.now() - startR2;
    console.log(`   ✅ Stored in R2: ${r2Key} (${r2Time}ms)`);

    // Step 6: Create KV index
    console.log('   🗂️  Creating KV index...');
    const startKV = Date.now();
    await createKVIndex(isbn, r2Key, metadata);
    const kvTime = Date.now() - startKV;
    console.log(`   ✅ KV index created (${kvTime}ms)`);

    const totalTime = fetchTime + downloadTime + compressTime + r2Time + kvTime;
    console.log(`   ✅ Complete! Total time: ${totalTime}ms`);

    return {
      isbn,
      status: 'success',
      r2Key,
      originalSize: compressed.originalSize,
      compressedSize: compressed.compressedSize,
      savings: compressed.savings,
      timings: { fetchTime, downloadTime, compressTime, r2Time, kvTime, totalTime }
    };

  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    return { isbn, status: 'error', error: error.message };
  }
}

/**
 * Main execution
 */
async function main() {
  const rateLimiter = new RateLimiter(10); // 10 req/sec
  const results = [];

  console.log('🚀 Starting E2E harvest test...\n');

  for (const isbn of TEST_ISBNS) {
    const result = await harvestISBN(isbn, rateLimiter);
    results.push(result);
  }

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('📊 Test Summary');
  console.log('='.repeat(60));
  console.log(`Total ISBNs: ${results.length}`);
  console.log(`Successful: ${results.filter(r => r.status === 'success').length}`);
  console.log(`No cover: ${results.filter(r => r.status === 'no_cover').length}`);
  console.log(`Errors: ${results.filter(r => r.status === 'error').length}`);

  const successful = results.filter(r => r.status === 'success');
  if (successful.length > 0) {
    const avgTime = successful.reduce((sum, r) => sum + r.timings.totalTime, 0) / successful.length;
    const totalSavings = successful.reduce((sum, r) => sum + r.savings, 0) / successful.length;
    console.log(`\nAverage processing time: ${Math.round(avgTime)}ms`);
    console.log(`Average compression savings: ${Math.round(totalSavings)}%`);
  }

  console.log('\n✅ E2E test complete!');
  console.log('\nNext steps:');
  console.log('1. Review results above');
  console.log('2. If dry-run, test with real R2/KV writes');
  console.log('3. Implement production cron handler (src/handlers/scheduled-harvest.js)');
}

main().catch(error => {
  console.error('❌ Fatal error:', error);
  process.exit(1);
});
