/**
 * Book search handlers with KV caching
 * Migrated from books-api-proxy
 *
 * Caching rules:
 * - Title search: 6 hour TTL (21600 seconds)
 * - ISBN search: 7 day TTL (604800 seconds) - ISBN data is stable
 */

import * as externalApis from '../services/external-apis.js';
import { getCached, setCached, generateCacheKey } from '../utils/cache.js';

/**
 * Search books by title with multi-provider orchestration
 * @param {string} title - Book title to search
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results to return (default: 20)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Search results in Google Books format
 */
export async function searchByTitle(title, options, env, ctx) {
  const { maxResults = 20 } = options;
  const cacheKey = generateCacheKey('search:title', { title: title.toLowerCase(), maxResults });

  // Try cache first
  const cachedResult = await getCached(cacheKey, env);
  if (cachedResult) {
    const { data, cacheMetadata } = cachedResult;
    const headers = generateCacheHeaders(true, cacheMetadata.age, cacheMetadata.ttl, data.items);

    // Write cache metrics to Analytics Engine
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/title',
      cacheHit: true,
      responseTime: 0, // Cache hits are instant
      imageQuality: headers['X-Image-Quality'],
      dataCompleteness: parseInt(headers['X-Data-Completeness']),
      itemCount: data.items?.length || 0
    }));

    return {
      ...data,
      cached: true,
      _cacheHeaders: headers
    };
  }

  const startTime = Date.now();

  try {
    // Search both Google Books and OpenLibrary in parallel
    const searchPromises = [
      externalApis.searchGoogleBooks(title, { maxResults }, env),
      externalApis.searchOpenLibrary(title, { maxResults }, env)
    ];

    const results = await Promise.allSettled(searchPromises);

    let finalItems = [];
    let successfulProviders = [];

    // Process Google Books results
    if (results[0].status === 'fulfilled' && results[0].value.success) {
      const googleData = results[0].value;
      if (googleData.items && googleData.items.length > 0) {
        finalItems = [...finalItems, ...googleData.items];
        successfulProviders.push('google');
      }
    }

    // Process OpenLibrary results
    if (results[1].status === 'fulfilled' && results[1].value.success) {
      const olData = results[1].value;
      if (olData.works && olData.works.length > 0) {
        // Transform OpenLibrary works to Google Books format
        const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
        finalItems = [...finalItems, ...transformedItems];
        successfulProviders.push('openlibrary');
      }
    }

    // Simple deduplication by title
    const dedupedItems = deduplicateByTitle(finalItems);

    const responseData = {
      kind: "books#volumes",
      totalItems: dedupedItems.length,
      items: dedupedItems.slice(0, maxResults),
      provider: `orchestrated:${successfulProviders.join('+')}`,
      cached: false,
      responseTime: Date.now() - startTime,
      _cacheHeaders: generateCacheHeaders(false, 0, 6 * 60 * 60, dedupedItems) // TTL: 6h
    };

    // Cache for 6 hours
    const ttl = 6 * 60 * 60; // 21600 seconds
    ctx.waitUntil(setCached(cacheKey, responseData, ttl, env));

    // Write cache metrics to Analytics Engine
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/title',
      cacheHit: false,
      responseTime: Date.now() - startTime,
      imageQuality: responseData._cacheHeaders['X-Image-Quality'],
      dataCompleteness: parseInt(responseData._cacheHeaders['X-Data-Completeness']),
      itemCount: dedupedItems.length
    }));

    return responseData;
  } catch (error) {
    console.error(`Title search failed for "${title}":`, error);
    return {
      error: 'Title search failed',
      details: error.message,
      items: [],
      _cacheHeaders: generateCacheHeaders(false, 0, 0, [])
    };
  }
}

/**
 * Search books by ISBN with multi-provider orchestration
 * @param {string} isbn - ISBN-10 or ISBN-13
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results to return (default: 1)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Book details in Google Books format
 */
export async function searchByISBN(isbn, options, env, ctx) {
  const { maxResults = 1 } = options;
  const cacheKey = generateCacheKey('search:isbn', { isbn });

  // Try cache first
  const cachedResult = await getCached(cacheKey, env);
  if (cachedResult) {
    const { data, cacheMetadata } = cachedResult;
    const headers = generateCacheHeaders(true, cacheMetadata.age, cacheMetadata.ttl, data.items);

    // Write cache metrics to Analytics Engine
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/isbn',
      cacheHit: true,
      responseTime: 0, // Cache hits are instant
      imageQuality: headers['X-Image-Quality'],
      dataCompleteness: parseInt(headers['X-Data-Completeness']),
      itemCount: data.items?.length || 0
    }));

    return {
      ...data,
      cached: true,
      _cacheHeaders: headers
    };
  }

  const startTime = Date.now();

  try {
    // Search both Google Books and OpenLibrary in parallel
    const searchPromises = [
      externalApis.searchGoogleBooksByISBN(isbn, env),
      externalApis.searchOpenLibrary(isbn, { maxResults, isbn }, env)
    ];

    const results = await Promise.allSettled(searchPromises);

    let finalItems = [];
    let successfulProviders = [];

    // Process Google Books results
    if (results[0].status === 'fulfilled' && results[0].value.success) {
      const googleData = results[0].value;
      if (googleData.items && googleData.items.length > 0) {
        finalItems = [...finalItems, ...googleData.items];
        successfulProviders.push('google');
      }
    }

    // Process OpenLibrary results
    if (results[1].status === 'fulfilled' && results[1].value.success) {
      const olData = results[1].value;
      if (olData.works && olData.works.length > 0) {
        const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
        finalItems = [...finalItems, ...transformedItems];
        successfulProviders.push('openlibrary');
      }
    }

    // Simple deduplication by ISBN
    const dedupedItems = deduplicateByISBN(finalItems);

    const responseData = {
      kind: "books#volumes",
      totalItems: dedupedItems.length,
      items: dedupedItems.slice(0, maxResults),
      provider: `orchestrated:${successfulProviders.join('+')}`,
      cached: false,
      responseTime: Date.now() - startTime,
      _cacheHeaders: generateCacheHeaders(false, 0, 7 * 24 * 60 * 60, dedupedItems) // TTL: 7d
    };

    // Cache for 7 days (ISBN data is stable)
    const ttl = 7 * 24 * 60 * 60; // 604800 seconds
    ctx.waitUntil(setCached(cacheKey, responseData, ttl, env));

    // Write cache metrics to Analytics Engine
    ctx.waitUntil(writeCacheMetrics(env, {
      endpoint: '/search/isbn',
      cacheHit: false,
      responseTime: Date.now() - startTime,
      imageQuality: responseData._cacheHeaders['X-Image-Quality'],
      dataCompleteness: parseInt(responseData._cacheHeaders['X-Data-Completeness']),
      itemCount: dedupedItems.length
    }));

    return responseData;
  } catch (error) {
    console.error(`ISBN search failed for "${isbn}":`, error);
    return {
      error: 'ISBN search failed',
      details: error.message,
      items: [],
      _cacheHeaders: generateCacheHeaders(false, 0, 0, [])
    };
  }
}

/**
 * Transform OpenLibrary work to Google Books format
 * Simplified version for api-worker
 */
function transformWorkToGoogleFormat(work) {
  const primaryEdition = work.editions && work.editions.length > 0 ? work.editions[0] : null;

  // Handle different author formats
  let authors = [];
  if (work.authors) {
    if (Array.isArray(work.authors)) {
      authors = work.authors.map(a => {
        if (typeof a === 'string') return a;
        if (a && a.name) return a.name;
        return String(a);
      });
    } else if (typeof work.authors === 'string') {
      authors = [work.authors];
    }
  }

  // If no authors in work, try edition
  if (authors.length === 0 && primaryEdition?.authors) {
    authors = Array.isArray(primaryEdition.authors)
      ? primaryEdition.authors.map(a => typeof a === 'string' ? a : a.name || String(a))
      : [String(primaryEdition.authors)];
  }

  // Prepare industry identifiers
  const industryIdentifiers = [];
  if (primaryEdition?.isbn13) {
    industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn13 });
  }
  if (primaryEdition?.isbn10) {
    industryIdentifiers.push({ type: "ISBN_10", identifier: primaryEdition.isbn10 });
  }

  const volumeInfo = {
    title: work.title,
    subtitle: work.subtitle || "",
    authors: authors,
    publisher: primaryEdition?.publisher || "",
    publishedDate: work.firstPublicationYear ? work.firstPublicationYear.toString() : (primaryEdition?.publicationDate || ""),
    description: work.description || primaryEdition?.description || "",
    industryIdentifiers: industryIdentifiers,
    pageCount: primaryEdition?.pageCount || 0,
    categories: work.subjects || [],
    imageLinks: primaryEdition?.coverImageURL ? {
      thumbnail: primaryEdition.coverImageURL,
      smallThumbnail: primaryEdition.coverImageURL
    } : undefined
  };

  const volumeId = work.id ||
    work.openLibraryWorkKey ||
    `synthetic-${work.title.replace(/\s+/g, '-').toLowerCase()}`;

  return {
    kind: "books#volume",
    id: volumeId,
    volumeInfo: volumeInfo
  };
}

/**
 * Deduplicate items by title (case-insensitive)
 */
function deduplicateByTitle(items) {
  const seen = new Set();
  return items.filter(item => {
    const title = item.volumeInfo?.title?.toLowerCase() || '';
    if (seen.has(title)) {
      return false;
    }
    seen.add(title);
    return true;
  });
}

/**
 * Deduplicate items by ISBN
 */
function deduplicateByISBN(items) {
  const seen = new Set();
  return items.filter(item => {
    const identifiers = item.volumeInfo?.industryIdentifiers || [];
    const isbns = identifiers.map(id => id.identifier).join(',');
    if (!isbns) return true; // Keep items without ISBNs
    if (seen.has(isbns)) {
      return false;
    }
    seen.add(isbns);
    return true;
  });
}

/**
 * Generate cache health headers for response
 * @param {boolean} cacheHit - Whether request was served from cache
 * @param {number} age - Cache age in seconds
 * @param {number} ttl - Cache TTL in seconds
 * @param {Array} items - Search result items for quality analysis
 * @returns {Object} Headers object
 */
function generateCacheHeaders(cacheHit, age, ttl, items = []) {
  const headers = {};

  // Cache status
  headers['X-Cache-Status'] = cacheHit ? 'HIT' : 'MISS';

  // Cache age (seconds since write)
  headers['X-Cache-Age'] = age.toString();

  // Cache TTL (remaining seconds before expiry)
  headers['X-Cache-TTL'] = ttl.toString();

  // Image quality analysis
  const imageQuality = analyzeImageQuality(items);
  headers['X-Image-Quality'] = imageQuality;

  // Data completeness (% with ISBN + cover)
  const completeness = calculateDataCompleteness(items);
  headers['X-Data-Completeness'] = completeness.toString();

  return headers;
}

/**
 * Analyzes cover image quality from URLs
 * @param {Array} items - Search result items in Google Books format
 * @returns {string} 'high' | 'medium' | 'low' | 'missing'
 */
function analyzeImageQuality(items) {
  if (!items || items.length === 0) return 'missing';

  let highCount = 0;
  let mediumCount = 0;
  let lowCount = 0;
  let missingCount = 0;

  for (const item of items) {
    const imageLinks = item.volumeInfo?.imageLinks;
    const coverURL = imageLinks?.thumbnail || imageLinks?.smallThumbnail || '';

    if (!coverURL) {
      missingCount++;
    } else if (coverURL.includes('zoom=1') || coverURL.includes('zoom=2')) {
      highCount++; // High zoom = high quality
    } else if (coverURL.includes('zoom=0')) {
      lowCount++; // Low zoom = low quality
    } else {
      mediumCount++; // Default quality
    }
  }

  // Return dominant quality level
  const total = items.length;
  if (highCount / total > 0.5) return 'high';
  if (mediumCount / total > 0.3) return 'medium';
  if (missingCount / total > 0.5) return 'missing';
  return 'low';
}

/**
 * Calculates data completeness percentage
 * @param {Array} items - Search result items in Google Books format
 * @returns {number} Percentage (0-100) of items with ISBN + cover
 */
function calculateDataCompleteness(items) {
  if (!items || items.length === 0) return 0;

  let completeCount = 0;

  for (const item of items) {
    const volumeInfo = item.volumeInfo;
    const hasISBN = volumeInfo?.industryIdentifiers?.length > 0;
    const hasCover = volumeInfo?.imageLinks?.thumbnail || volumeInfo?.imageLinks?.smallThumbnail;

    if (hasISBN && hasCover) {
      completeCount++;
    }
  }

  return Math.round((completeCount / items.length) * 100);
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
        metrics.imageQuality
      ],
      doubles: [
        metrics.responseTime,
        metrics.dataCompleteness,
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
