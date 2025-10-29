// src/handlers/author-search.js
/**
 * Author bibliography search handler with pagination
 * Uses OpenLibrary API for author work lookups
 */

import * as externalApis from '../services/external-apis.js';
import { setCached, generateCacheKey } from '../utils/cache.js';
import { UnifiedCacheService } from '../services/unified-cache.js';

/**
 * Search books by author with pagination
 * @param {string} authorName - Author name to search
 * @param {Object} options - Search options
 * @param {number} options.limit - Results per page (default: 50, max: 100)
 * @param {number} options.offset - Pagination offset (default: 0)
 * @param {string} options.sortBy - Sort order (publicationYear, title, popularity)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Author bibliography with pagination
 */
export async function searchByAuthor(authorName, options, env, ctx) {
  const { limit = 50, offset = 0, sortBy = 'publicationYear' } = options;

  // Validate pagination parameters
  const validatedLimit = Math.min(Math.max(1, limit), 100);
  const validatedOffset = Math.max(0, offset);

  // Generate cache key with pagination params
  const cacheKey = generateCacheKey('search:author', {
    author: authorName.toLowerCase(),
    limit: validatedLimit,
    offset: validatedOffset,
    sortBy
  });

  // Try UnifiedCache first (Edge → KV tiers)
  const cache = new UnifiedCacheService(env, ctx);
  const cachedResult = await cache.get(cacheKey, 'author', {
    query: authorName,
    limit: validatedLimit,
    offset: validatedOffset
  });

  if (cachedResult && cachedResult.data) {
    const { data, source } = cachedResult;

    // Write cache metrics
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/author',
      cacheHit: true,
      responseTime: 0,
      itemCount: data.works?.length || 0,
      authorName: authorName
    }));

    return {
      ...data,
      cached: true,
      cacheSource: source
    };
  }

  const startTime = Date.now();

  try {
    // Call existing OpenLibrary function
    const olResult = await externalApis.getOpenLibraryAuthorWorks(authorName, env);

    if (!olResult.success) {
      return {
        success: false,
        error: olResult.error || 'Author not found in OpenLibrary',
        works: [],
        pagination: null
      };
    }

    // Apply pagination to works
    const allWorks = olResult.works || [];
    const totalWorks = allWorks.length;

    // Apply sorting
    const sortedWorks = applySorting(allWorks, sortBy);

    // Slice for pagination
    const paginatedWorks = sortedWorks.slice(validatedOffset, validatedOffset + validatedLimit);

    const responseData = {
      success: true,
      provider: 'openlibrary',
      author: {
        name: authorName,
        openLibraryKey: olResult.author?.openLibraryKey || null,
        totalWorks: totalWorks
      },
      works: paginatedWorks,
      pagination: {
        total: totalWorks,
        limit: validatedLimit,
        offset: validatedOffset,
        hasMore: validatedOffset + validatedLimit < totalWorks,
        nextOffset: validatedOffset + validatedLimit < totalWorks
          ? validatedOffset + validatedLimit
          : null
      },
      cached: false,
      responseTime: Date.now() - startTime
    };

    // Cache for 6 hours (per-page caching)
    const ttl = 6 * 60 * 60; // 21600 seconds
    ctx.waitUntil(setCached(cacheKey, responseData, ttl, env));

    // Write cache metrics
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/author',
      cacheHit: false,
      responseTime: Date.now() - startTime,
      itemCount: paginatedWorks.length,
      authorName: authorName
    }));

    return responseData;
  } catch (error) {
    console.error(`Author search failed for "${authorName}":`, error);
    return {
      success: false,
      error: 'Author search failed',
      details: error.message,
      works: [],
      pagination: null
    };
  }
}

/**
 * Apply sorting to works array
 * @param {Array} works - Array of work objects
 * @param {string} sortBy - Sort order
 * @returns {Array} Sorted works
 */
function applySorting(works, sortBy) {
  const sortedWorks = [...works];

  switch (sortBy) {
    case 'publicationYear':
      // Newest first (default)
      return sortedWorks.sort((a, b) =>
        (b.firstPublicationYear || 0) - (a.firstPublicationYear || 0)
      );

    case 'publicationYearAsc':
      // Oldest first
      return sortedWorks.sort((a, b) =>
        (a.firstPublicationYear || 0) - (b.firstPublicationYear || 0)
      );

    case 'title':
      // Alphabetical
      return sortedWorks.sort((a, b) =>
        (a.title || '').localeCompare(b.title || '')
      );

    case 'popularity':
      // Sort by number of editions (proxy for popularity)
      return sortedWorks.sort((a, b) =>
        (b.editions?.length || 0) - (a.editions?.length || 0)
      );

    default:
      return sortedWorks;
  }
}

/**
 * Write cache metrics to Analytics Engine
 * @param {Object} env - Worker environment bindings
 * @param {Object} metrics - Metrics to write
 */
async function writeCacheMetrics(env, metrics) {
  if (!env.CACHE_ANALYTICS) {
    console.warn('CACHE_ANALYTICS binding not available');
    return;
  }

  try {
    await env.CACHE_ANALYTICS.writeDataPoint({
      blobs: [
        metrics.endpoint,
        metrics.authorName,
        metrics.cacheHit ? 'HIT' : 'MISS'
      ],
      doubles: [
        metrics.responseTime,
        metrics.itemCount
      ],
      indexes: [
        metrics.cacheHit ? 'HIT' : 'MISS'
      ]
    });
  } catch (error) {
    console.error('Failed to write cache metrics:', error);
  }
}
