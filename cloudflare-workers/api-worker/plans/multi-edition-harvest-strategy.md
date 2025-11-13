# Multi-Edition Harvest Strategy

**Status:** Planning Complete
**Priority:** 3 (Implement after Priority 1 & 2 deployed)
**Goal:** Reach 5000+ cached covers by harvesting multiple editions per book
**Timeline:** 5 days (after Priority 1 & 2 provide base capacity)
**Created:** November 2025

## Executive Summary

Currently harvesting 478 curated ISBNs/day (280 successful). With Priority 1 & 2 deployed, we'll reach 800-1000 ISBNs/day. To maximize the 5000 cover cache capacity, we need to harvest multiple editions (Hardcover, Paperback, Limited) for each popular book, plus cache entire author bibliographies for high-demand authors.

**Key Innovation:** Use free Google Books API to discover editions, then fetch high-quality covers from ISBNdb (1000 req/day limit). This multiplies our cache capacity 3-5x per Work.

## Problem Statement

### Current Limitations
1. **Single Edition Per Work:** Only harvesting one ISBN per book (primary edition)
2. **Underutilized API Quota:** ISBNdb allows 1000 req/day, we're using 478-800
3. **Missing Author Context:** Users often browse by author, but we cache books individually
4. **Cover Quality Gaps:** Some editions have better covers (First Edition, Illustrated)

### User Impact
- Library shows low-quality covers when user owns a different edition than cached
- Slow load times when browsing popular authors (cache misses)
- Inconsistent cover art across Works by same author

## Solution Overview

### Four-Phase Approach

1. **Edition Discovery Service** (Day 1-2)
   - Query Google Books API for all editions of a Work
   - Score and prioritize editions (Hardcover > Paperback > eBook)
   - Build edition manifest for ISBNdb harvest

2. **Enhanced Harvest Script** (Day 3)
   - Load 350 Works (instead of 1000 ISBNs)
   - Discover 2-3 editions per Work via Google Books
   - Harvest 700-1050 covers from ISBNdb (within 1000 req/day limit)
   - Store with edition-specific metadata

3. **Author Bibliography Cache** (Day 4)
   - Identify high-demand authors from Analytics
   - Cache all books by top 50 authors
   - Pre-fetch covers for entire author catalogs

4. **Quality Validation Dashboard** (Day 5)
   - Monitor cache hit rates by edition type
   - Track cover quality scores
   - Identify gaps for manual curation

## Technical Design

### Phase 1: Edition Discovery Service

**New File:** `src/services/edition-discovery.js`

```javascript
/**
 * Edition Discovery Service
 * Uses Google Books API (free) to find all editions of a Work
 * Returns scored and prioritized edition list
 */

import { GoogleBooksAPI } from '../providers/google-books-api.js';

export class EditionDiscoveryService {
  constructor(env) {
    this.googleBooks = new GoogleBooksAPI(env);
  }

  /**
   * Find all editions for a Work identified by primary ISBN
   * @param {string} primaryISBN - ISBN of any known edition
   * @returns {Promise<EditionManifest>}
   */
  async discoverEditions(primaryISBN) {
    try {
      // Step 1: Get Work metadata from primary ISBN
      const primaryBook = await this.googleBooks.searchByISBN(primaryISBN);
      if (!primaryBook) {
        return { primaryISBN, editions: [], error: 'Primary ISBN not found' };
      }

      const { title, authors } = primaryBook;

      // Step 2: Search for all editions by title + author
      const query = `intitle:"${title}" inauthor:"${authors[0]}"`;
      const searchResults = await this.googleBooks.search(query, { maxResults: 40 });

      // Step 3: Filter for same Work (fuzzy title match)
      const editions = searchResults
        .filter(book => this.isSameWork(title, book.title))
        .map(book => this.extractEditionMetadata(book))
        .filter(edition => edition.isbn13 && edition.isbn13 !== primaryISBN);

      // Step 4: Score and sort editions
      const scoredEditions = editions
        .map(edition => ({
          ...edition,
          score: this.scoreEdition(edition)
        }))
        .sort((a, b) => b.score - a.score);

      return {
        primaryISBN,
        work: { title, authors },
        editions: [
          { isbn13: primaryISBN, type: 'PRIMARY', score: 100 },
          ...scoredEditions.slice(0, 3)  // Top 3 additional editions
        ],
        totalFound: scoredEditions.length
      };
    } catch (error) {
      console.error(`Edition discovery failed for ${primaryISBN}:`, error);
      return { primaryISBN, editions: [], error: error.message };
    }
  }

  /**
   * Fuzzy title matching (handles subtitle differences)
   */
  isSameWork(title1, title2) {
    const normalize = (str) => str.toLowerCase()
      .replace(/[:\-—–]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .split(' ')
      .slice(0, 5)  // First 5 words
      .join(' ');

    const normalized1 = normalize(title1);
    const normalized2 = normalize(title2);

    // Must match at least 4 out of 5 words
    const words1 = normalized1.split(' ');
    const words2 = normalized2.split(' ');
    const commonWords = words1.filter(w => words2.includes(w)).length;

    return commonWords >= Math.min(4, words1.length - 1);
  }

  /**
   * Extract edition metadata from Google Books response
   */
  extractEditionMetadata(book) {
    return {
      isbn13: book.industryIdentifiers?.find(id => id.type === 'ISBN_13')?.identifier,
      isbn10: book.industryIdentifiers?.find(id => id.type === 'ISBN_10')?.identifier,
      type: this.detectEditionType(book),
      format: book.printType,  // BOOK, MAGAZINE
      pageCount: book.pageCount,
      publisher: book.publisher,
      publishedDate: book.publishedDate,
      language: book.language,
      coverURL: book.imageLinks?.thumbnail
    };
  }

  /**
   * Detect edition type from metadata
   */
  detectEditionType(book) {
    const title = book.title.toLowerCase();
    const description = (book.description || '').toLowerCase();

    if (title.includes('illustrated') || description.includes('illustrated edition')) {
      return 'ILLUSTRATED';
    }
    if (title.includes('first edition') || title.includes('1st edition')) {
      return 'FIRST_EDITION';
    }
    if (title.includes('anniversary') || description.includes('anniversary edition')) {
      return 'ANNIVERSARY';
    }
    if (title.includes('hardcover') || book.printType === 'BOOK') {
      return 'HARDCOVER';
    }
    if (title.includes('paperback') || title.includes('mass market')) {
      return 'PAPERBACK';
    }
    return 'STANDARD';
  }

  /**
   * Edition Scoring Algorithm (100-point scale)
   */
  scoreEdition(edition) {
    let score = 50;  // Base score

    // Edition type bonus (0-30 points)
    const typeBonus = {
      'ILLUSTRATED': 30,
      'FIRST_EDITION': 25,
      'ANNIVERSARY': 20,
      'HARDCOVER': 15,
      'PAPERBACK': 10,
      'STANDARD': 5
    };
    score += typeBonus[edition.type] || 0;

    // Page count bonus (0-10 points) - fuller editions preferred
    if (edition.pageCount > 300) score += 10;
    else if (edition.pageCount > 200) score += 5;

    // Cover availability bonus (0-15 points)
    if (edition.coverURL) {
      const urlLower = edition.coverURL.toLowerCase();
      if (urlLower.includes('zoom=1')) score += 15;  // High-res
      else if (urlLower.includes('zoom=0')) score += 5;  // Low-res
      else score += 10;  // Standard
    }

    // Recency bonus (0-10 points) - newer editions may have better covers
    const year = parseInt(edition.publishedDate?.substring(0, 4));
    if (year >= 2020) score += 10;
    else if (year >= 2010) score += 5;

    // Language bonus (0-5 points)
    if (edition.language === 'en') score += 5;

    return Math.min(100, score);
  }

  /**
   * Batch discover editions for multiple Works
   * @param {string[]} isbns - Array of primary ISBNs
   * @returns {Promise<EditionManifest[]>}
   */
  async batchDiscover(isbns, options = {}) {
    const { concurrency = 5, delayMs = 200 } = options;
    const results = [];

    for (let i = 0; i < isbns.length; i += concurrency) {
      const batch = isbns.slice(i, i + concurrency);
      const batchResults = await Promise.all(
        batch.map(isbn => this.discoverEditions(isbn))
      );
      results.push(...batchResults);

      // Rate limiting (Google Books: 1000 req/day)
      if (i + concurrency < isbns.length) {
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    }

    return results;
  }
}
```

**Key Design Decisions:**

1. **Free API First:** Google Books API is free and excellent for edition discovery
2. **Fuzzy Matching:** Handles subtitle variations ("The Great Gatsby" vs "The Great Gatsby: A Novel")
3. **Edition Scoring:** Prioritizes Illustrated > First Edition > Hardcover > Paperback
4. **Rate Limiting:** 5 concurrent requests, 200ms delay (safe for Google's 1000 req/day limit)

### Phase 2: Enhanced Harvest Script

**Modified File:** `src/handlers/scheduled-harvest.js`

```javascript
// NEW: Import Edition Discovery Service
import { EditionDiscoveryService } from '../services/edition-discovery.js';

/**
 * Enhanced harvest strategy with multi-edition support
 */
async function enhancedHarvestWithEditions(env, isbns) {
  console.log('🔄 Starting enhanced multi-edition harvest...');

  // Step 1: Deduplicate Works (group ISBNs by Work if possible)
  const uniqueWorks = await deduplicateWorks(env, isbns);
  console.log(`📚 Identified ${uniqueWorks.length} unique Works from ${isbns.length} ISBNs`);

  // Step 2: Select 350 Works for edition discovery (leaves budget for Analytics ISBNs)
  const worksToExpand = uniqueWorks.slice(0, 350);
  console.log(`🎯 Selected ${worksToExpand.length} Works for edition expansion`);

  // Step 3: Discover editions for selected Works
  const editionService = new EditionDiscoveryService(env);
  const editionManifests = await editionService.batchDiscover(
    worksToExpand.map(w => w.primaryISBN),
    { concurrency: 5, delayMs: 200 }
  );

  // Step 4: Flatten to ISBN list (primary + top 2 editions per Work)
  const allISBNs = editionManifests.flatMap(manifest =>
    manifest.editions.slice(0, 3).map(e => e.isbn13)
  ).filter(isbn => isbn);

  console.log(`📖 Expanded to ${allISBNs.length} total ISBNs (target: 700-1050)`);
  console.log(`   ${uniqueWorks.length} Works × 2-3 editions = ${allISBNs.length} covers`);

  // Step 5: Add remaining Analytics ISBNs to reach 1000 limit
  const analyticsISBNs = await collectAnalyticsISBNs(env);
  const remainingBudget = 1000 - allISBNs.length;
  const finalISBNs = [
    ...allISBNs,
    ...analyticsISBNs.slice(0, remainingBudget)
  ];

  console.log(`✅ Final harvest list: ${finalISBNs.length}/1000 ISBNs`);
  console.log(`   ${allISBNs.length} multi-edition + ${Math.min(remainingBudget, analyticsISBNs.length)} analytics`);

  // Step 6: Execute ISBNdb harvest
  const results = await harvestCoversFromISBNdb(env, finalISBNs);

  // Step 7: Store edition metadata alongside covers
  await storeEditionMetadata(env, editionManifests, results);

  return results;
}

/**
 * Deduplicate ISBNs into unique Works
 * (Best effort - perfect deduplication requires OpenLibrary Work IDs)
 */
async function deduplicateWorks(env, isbns) {
  // Simple approach: Keep all ISBNs as separate Works for now
  // TODO: Future enhancement - query OpenLibrary for Work IDs
  return isbns.map(isbn => ({ primaryISBN: isbn }));
}

/**
 * Store edition metadata in KV for enrichment lookups
 */
async function storeEditionMetadata(env, manifests, harvestResults) {
  for (const manifest of manifests) {
    const { primaryISBN, work, editions } = manifest;

    // Store edition index: work:{primaryISBN} -> list of edition ISBNs
    const editionList = editions
      .filter(e => harvestResults.successful.includes(e.isbn13))
      .map(e => ({
        isbn13: e.isbn13,
        type: e.type,
        score: e.score,
        format: e.format
      }));

    await env.BOOKS_CACHE.put(
      `work-editions:${primaryISBN}`,
      JSON.stringify({ work, editions: editionList }),
      { expirationTtl: 86400 * 365 }  // 1 year
    );
  }

  console.log(`💾 Stored edition metadata for ${manifests.length} Works`);
}
```

**API Budget Allocation:**

| Source | ISBNs | Purpose |
|--------|-------|---------|
| Curated Works (expanded) | 700-1050 | 350 Works × 2-3 editions |
| Analytics Popular ISBNs | 0-300 | Fill remaining budget |
| **Total** | **1000** | ISBNdb daily limit |

### Phase 3: Author Bibliography Cache

**New File:** `src/services/author-bibliography.js`

```javascript
/**
 * Author Bibliography Caching Service
 * Pre-fetches covers for all books by high-demand authors
 */

import { GoogleBooksAPI } from '../providers/google-books-api.js';
import { ISBNdbAPI } from '../providers/isbndb-api.js';

export class AuthorBibliographyService {
  constructor(env) {
    this.googleBooks = new GoogleBooksAPI(env);
    this.isbndb = new ISBNdbAPI(env);
  }

  /**
   * Identify top authors from Analytics Engine
   * @returns {Promise<Author[]>}
   */
  async getTopAuthors(env) {
    const query = `
      SELECT blob2 as author, COUNT(*) as search_count
      FROM books_api_provider_performance
      WHERE timestamp > NOW() - INTERVAL '30' DAY
        AND index1 = 'google-books-author'
      GROUP BY author
      ORDER BY search_count DESC
      LIMIT 50
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
      console.error('Analytics query failed:', response.status);
      return [];
    }

    const data = await response.json();
    return data.data || [];
  }

  /**
   * Cache all books by an author
   * @param {string} authorName - Author to cache
   * @returns {Promise<BibliographyResult>}
   */
  async cacheAuthorBibliography(authorName) {
    try {
      // Step 1: Search Google Books for all books by author
      const query = `inauthor:"${authorName}"`;
      const books = await this.googleBooks.search(query, { maxResults: 40 });

      console.log(`📚 Found ${books.length} books by ${authorName}`);

      // Step 2: Extract ISBNs
      const isbns = books
        .map(book => book.industryIdentifiers?.find(id => id.type === 'ISBN_13')?.identifier)
        .filter(isbn => isbn);

      // Step 3: Check which covers are already cached
      const uncachedISBNs = [];
      for (const isbn of isbns) {
        const exists = await this.env.BOOKS_CACHE.get(`cover:${isbn}`);
        if (!exists) uncachedISBNs.push(isbn);
      }

      console.log(`   ${uncachedISBNs.length} covers need harvesting`);

      // Step 4: Harvest missing covers from ISBNdb
      const results = await this.harvestCovers(uncachedISBNs);

      return {
        author: authorName,
        totalBooks: books.length,
        cachedBefore: isbns.length - uncachedISBNs.length,
        harvested: results.successful.length,
        failed: results.failed.length
      };
    } catch (error) {
      console.error(`Author bibliography cache failed for ${authorName}:`, error);
      return { author: authorName, error: error.message };
    }
  }

  /**
   * Batch cache top authors
   * @param {number} limit - Number of top authors to cache
   */
  async batchCacheTopAuthors(env, limit = 50) {
    const topAuthors = await this.getTopAuthors(env);
    console.log(`👥 Caching bibliographies for top ${Math.min(limit, topAuthors.length)} authors...`);

    const results = [];
    for (const { author } of topAuthors.slice(0, limit)) {
      const result = await this.cacheAuthorBibliography(author);
      results.push(result);

      // Rate limiting (Google Books: 1000 req/day)
      await new Promise(resolve => setTimeout(resolve, 500));
    }

    const totalHarvested = results.reduce((sum, r) => sum + (r.harvested || 0), 0);
    console.log(`✅ Author bibliography cache complete: ${totalHarvested} new covers`);

    return results;
  }
}
```

**Integration with Harvest Script:**

```javascript
// In scheduled-harvest.js scheduled() handler:

export default {
  async scheduled(event, env, ctx) {
    // Existing harvest
    const harvestResults = await enhancedHarvestWithEditions(env, isbns);

    // NEW: Author bibliography cache (runs after main harvest)
    const authorService = new AuthorBibliographyService(env);
    const authorResults = await authorService.batchCacheTopAuthors(env, 10);

    console.log('📊 Combined harvest stats:');
    console.log(`   Main harvest: ${harvestResults.successful.length} covers`);
    console.log(`   Author bibliographies: ${authorResults.reduce((sum, r) => sum + (r.harvested || 0), 0)} covers`);
  }
};
```

### Phase 4: Quality Validation Dashboard

**New File:** `src/handlers/admin/harvest-dashboard.js`

```javascript
/**
 * Admin dashboard for monitoring harvest quality
 * GET /admin/harvest-dashboard
 */

export async function handleHarvestDashboard(env) {
  // Fetch cache stats from KV
  const stats = await env.BOOKS_CACHE.get('harvest-stats', 'json');

  if (!stats) {
    return new Response('No harvest data available', { status: 404 });
  }

  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>ISBNdb Harvest Dashboard</title>
      <style>
        body { font-family: system-ui; max-width: 1200px; margin: 40px auto; padding: 0 20px; }
        .metric { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 8px; }
        .metric h3 { margin: 0 0 10px 0; color: #333; }
        .metric .value { font-size: 36px; font-weight: bold; color: #0066cc; }
        .metric .label { color: #666; font-size: 14px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f5f5f5; font-weight: 600; }
        .success { color: #00aa00; }
        .warning { color: #ff8800; }
        .error { color: #cc0000; }
      </style>
    </head>
    <body>
      <h1>📊 ISBNdb Harvest Dashboard</h1>

      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px;">
        <div class="metric">
          <h3>Total Covers Cached</h3>
          <div class="value">${stats.totalCovers.toLocaleString()}</div>
          <div class="label">Target: 5,000</div>
        </div>

        <div class="metric">
          <h3>Today's Harvest</h3>
          <div class="value">${stats.todayHarvested}</div>
          <div class="label">${stats.todayFailed} failed</div>
        </div>

        <div class="metric">
          <h3>Cache Hit Rate</h3>
          <div class="value">${(stats.cacheHitRate * 100).toFixed(1)}%</div>
          <div class="label">Last 7 days</div>
        </div>
      </div>

      <h2>Edition Type Distribution</h2>
      <table>
        <thead>
          <tr>
            <th>Edition Type</th>
            <th>Count</th>
            <th>Avg Quality Score</th>
            <th>Cache Hits</th>
          </tr>
        </thead>
        <tbody>
          ${Object.entries(stats.editionTypes || {}).map(([type, data]) => `
            <tr>
              <td>${type}</td>
              <td>${data.count}</td>
              <td>${data.avgQuality.toFixed(1)}</td>
              <td class="${data.hitRate > 0.7 ? 'success' : 'warning'}">${(data.hitRate * 100).toFixed(1)}%</td>
            </tr>
          `).join('')}
        </tbody>
      </table>

      <h2>Top Authors Cached</h2>
      <table>
        <thead>
          <tr>
            <th>Author</th>
            <th>Books Cached</th>
            <th>Search Volume</th>
          </tr>
        </thead>
        <tbody>
          ${(stats.topAuthors || []).map(author => `
            <tr>
              <td>${author.name}</td>
              <td>${author.booksCached}</td>
              <td>${author.searchCount.toLocaleString()}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>

      <h2>API Budget Utilization</h2>
      <div class="metric">
        <div class="value">${stats.todayAPIRequests}/1000</div>
        <div class="label">ISBNdb requests today (${((stats.todayAPIRequests / 1000) * 100).toFixed(1)}% utilized)</div>
      </div>

      <p style="color: #666; font-size: 14px; margin-top: 40px;">
        Last updated: ${new Date(stats.lastUpdate).toLocaleString()}
      </p>
    </body>
    </html>
  `;

  return new Response(html, {
    headers: { 'Content-Type': 'text/html' }
  });
}
```

**Stats Collection (in scheduled-harvest.js):**

```javascript
async function updateHarvestStats(env, results, editionManifests) {
  const stats = await env.BOOKS_CACHE.get('harvest-stats', 'json') || {
    totalCovers: 0,
    editionTypes: {},
    topAuthors: [],
    history: []
  };

  // Update totals
  stats.totalCovers += results.successful.length;
  stats.todayHarvested = results.successful.length;
  stats.todayFailed = results.failed.length;
  stats.todayAPIRequests = results.successful.length + results.failed.length;
  stats.lastUpdate = new Date().toISOString();

  // Update edition type distribution
  for (const manifest of editionManifests) {
    for (const edition of manifest.editions) {
      if (!stats.editionTypes[edition.type]) {
        stats.editionTypes[edition.type] = { count: 0, avgQuality: 0, hitRate: 0 };
      }
      stats.editionTypes[edition.type].count++;
    }
  }

  // Store updated stats
  await env.BOOKS_CACHE.put('harvest-stats', JSON.stringify(stats));
}
```

## Implementation Timeline

### Day 1: Edition Discovery Foundation
- [ ] Create `src/services/edition-discovery.js`
- [ ] Implement `discoverEditions()` and `scoreEdition()`
- [ ] Write unit tests for fuzzy title matching
- [ ] Test with 10 sample Works (Harry Potter, 1984, etc.)

### Day 2: Edition Discovery Refinement
- [ ] Implement `batchDiscover()` with rate limiting
- [ ] Add edition type detection logic
- [ ] Test with 100 Works from curated list
- [ ] Validate scoring algorithm output

### Day 3: Enhanced Harvest Integration
- [ ] Modify `scheduled-harvest.js` to use edition discovery
- [ ] Implement `enhancedHarvestWithEditions()`
- [ ] Add edition metadata storage in KV
- [ ] Deploy and test with 350 Works

### Day 4: Author Bibliography System
- [ ] Create `src/services/author-bibliography.js`
- [ ] Implement `getTopAuthors()` Analytics query
- [ ] Add `cacheAuthorBibliography()` logic
- [ ] Test with 10 popular authors

### Day 5: Quality Dashboard
- [ ] Create `src/handlers/admin/harvest-dashboard.js`
- [ ] Implement stats collection in harvest script
- [ ] Add dashboard route to `src/index.js`
- [ ] Monitor for 24 hours, validate metrics

## Success Metrics

### Cache Growth
- **Day 0:** 280 covers (baseline)
- **Day 1:** 500 covers (Priority 1 & 2 deployed)
- **Day 3:** 1,500 covers (multi-edition harvest)
- **Day 5:** 5,000+ covers (author bibliographies)

### Quality Metrics
- **Cache Hit Rate:** >75% (up from current ~60%)
- **Cover Quality Score:** >85/100 avg (vs ~70 baseline)
- **API Utilization:** 900-1000/1000 requests (vs 478 baseline)

### User Impact
- **Load Time Reduction:** 40% faster for popular books
- **Cover Quality:** 30% fewer low-quality covers in library
- **Author Browse:** 2x faster browsing popular authors

## Risk Analysis

### Technical Risks

**Risk 1: Google Books API Rate Limits**
- **Probability:** Medium
- **Impact:** High (blocks edition discovery)
- **Mitigation:**
  - Implement exponential backoff
  - Cache edition manifests for 7 days
  - Fall back to single-edition harvest if quota exceeded

**Risk 2: ISBNdb Cost Overruns**
- **Probability:** Low
- **Impact:** Medium (user pays per-request)
- **Mitigation:**
  - Cap at 1000 req/day (existing limit)
  - Monitor spend via ISBNdb dashboard
  - Add alert at $50/month threshold

**Risk 3: Edition Deduplication Accuracy**
- **Probability:** Medium
- **Impact:** Low (wasted API calls)
- **Mitigation:**
  - Conservative fuzzy matching (4/5 words)
  - Manual review of top 100 Works
  - Dashboard to flag suspicious duplicates

### Operational Risks

**Risk 4: Storage Cost Growth**
- **Probability:** Low
- **Impact:** Low ($0.40/month worst case)
- **Current:** 280 covers × 40KB avg = 11.36 MB
- **Projected:** 5000 covers × 40KB avg = 200 MB
- **Cost:** R2: $0.015/GB/month = $0.003/month
- **Cost:** KV: $0.50/GB/month = $0.10/month
- **Total:** ~$0.10/month (negligible)

**Risk 5: Harvest Job Duration**
- **Probability:** Medium
- **Impact:** Low (job timeout)
- **Current:** 478 ISBNs = 8-12 minutes
- **Projected:** 1000 ISBNs = 18-25 minutes
- **Mitigation:**
  - Workers have 30-minute CPU time limit (safe)
  - Parallelize ISBNdb requests (10 concurrent)
  - Add progress logging every 100 ISBNs

## Dependencies

### External APIs
- **Google Books API** - Free, 1000 req/day, used for edition discovery
- **ISBNdb API** - Paid ($39/month), 1000 req/day, used for cover harvesting
- **Cloudflare Analytics Engine** - Included, used for author popularity

### Internal Services
- **Priority 1 (Analytics Logging)** - Must be deployed first for author identification
- **Priority 2 (Enhanced Harvest)** - Provides base capacity for expansion
- **CoverImageService.swift** - iOS service that consumes cached covers

## Future Enhancements

### Phase 5: OpenLibrary Work Integration (Optional)
- Query OpenLibrary for canonical Work IDs
- Perfect deduplication across all providers
- Link editions to Works in KV schema

### Phase 6: User-Requested Covers (Optional)
- Allow users to request specific edition covers
- Queue user requests for next harvest cycle
- Priority boost for user-owned editions

### Phase 7: AI-Powered Cover Selection (Optional)
- Use Cloudflare Workers AI to analyze cover aesthetics
- Automatically select "best" cover per Work
- Demote covers with occlusion, poor lighting, etc.

## Conclusion

This multi-edition harvest strategy multiplies our cache capacity 3-5x by harvesting multiple editions per Work and caching entire author bibliographies. By using Google Books API (free) for edition discovery and ISBNdb (paid) for high-quality covers, we maximize value within API budget constraints.

**Key Benefits:**
- 5000+ covers cached (vs 280 baseline)
- 75%+ cache hit rate (vs 60% baseline)
- 30% better cover quality (Edition-specific > Generic)
- 40% faster load times for popular books

**Implementation Effort:** 5 days
**Operational Cost:** +$0.10/month storage (negligible)
**User Impact:** Significantly better cover quality and load times

---

**Next Steps:**
1. Deploy Priority 1 & 2 changes
2. Test Analytics ISBN logging (2-3 searches)
3. Wait 24 hours for Analytics data accumulation
4. Begin Phase 1 implementation (Edition Discovery Service)
