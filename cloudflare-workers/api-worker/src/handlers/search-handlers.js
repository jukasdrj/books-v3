/**
 * Search handlers for book lookups
 * Extracted to eliminate RPC circular dependencies
 *
 * Optimizations:
 * - Negative caching for 404/5xx responses (5-minute TTL)
 * - Request coalescing to prevent duplicate in-flight calls
 */

import * as externalApis from '../services/external-apis.js';

// Request coalescing: Map of in-flight requests by cache key
const IN_FLIGHT_REQUESTS = new Map();

/**
 * Generate cache key for search parameters
 */
function generateSearchCacheKey(searchParams) {
  const { bookTitle, authorName, isbn } = searchParams;
  const parts = [
    isbn || '',
    bookTitle?.toLowerCase().trim() || '',
    authorName?.toLowerCase().trim() || ''
  ];
  return `search:${parts.filter(Boolean).join(':')}`;
}

/**
 * Check for negative cache entry (previous failed lookup)
 * Returns null if no negative cache, or cached error if exists
 */
async function checkNegativeCache(cacheKey, env) {
  try {
    const negativeKey = `negative:${cacheKey}`;
    const cached = await env.KV_CACHE.get(negativeKey, 'json');

    if (cached && cached.timestamp) {
      const age = Date.now() - cached.timestamp;
      // Return cached error if less than 5 minutes old
      if (age < 300000) {
        console.log(`⚠️ Negative cache HIT: ${cacheKey} (age: ${Math.round(age / 1000)}s)`);
        return cached;
      }
    }
  } catch (error) {
    console.error('Negative cache check failed:', error);
  }
  return null;
}

/**
 * Store failed lookup in negative cache (5-minute TTL)
 * @param {string} cacheKey - Cache key
 * @param {Object} error - Error object with message and status
 * @param {string} type - Type: 'no_results' or 'error'
 * @param {Object} env - Worker environment
 */
async function storeNegativeCache(cacheKey, error, type, env) {
  try {
    const negativeKey = `negative:${cacheKey}`;
    await env.KV_CACHE.put(negativeKey, JSON.stringify({
      type: type || 'error',  // 'no_results' vs 'error'
      error: error.message || 'Unknown error',
      status: error.status || 500,
      timestamp: Date.now()
    }), {
      expirationTtl: 300 // 5 minutes
    });
    console.log(`📝 Stored negative cache: ${cacheKey} (type: ${type})`);
  } catch (err) {
    console.error('Failed to store negative cache:', err);
  }
}

/**
 * Advanced search handler for multi-provider book search
 * Previously called via RPC from bookshelf-ai-worker
 *
 * @param {Object} searchParams - Search parameters
 * @param {string} searchParams.bookTitle - Book title to search
 * @param {string} searchParams.authorName - Author name to search
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results to return (default: 1)
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object>} Search results with items array (Google Books format)
 */
export async function handleAdvancedSearch(searchParams, options = {}, env) {
  const { bookTitle, authorName } = searchParams;
  const maxResults = options.maxResults || 1;
  const cacheKey = generateSearchCacheKey(searchParams);

  console.log(`[AdvancedSearch] Searching for "${bookTitle}" by "${authorName}"`);

  // Check negative cache first (prevents repeated failed lookups)
  const negativeCache = await checkNegativeCache(cacheKey, env);
  if (negativeCache) {
    // Maintain consistent API contract: always return success: true for "no results"
    if (negativeCache.type === 'no_results') {
      return {
        success: true,
        provider: 'none',
        items: [],
        cached: true,
        negativeCache: true
      };
    }
    // Only true errors return success: false
    return {
      success: false,
      error: negativeCache.error,
      items: [],
      cached: true,
      negativeCache: true
    };
  }

  // Check for in-flight request (request coalescing)
  if (IN_FLIGHT_REQUESTS.has(cacheKey)) {
    console.log(`🔄 Request coalescing: Waiting for in-flight request (${cacheKey})`);
    return IN_FLIGHT_REQUESTS.get(cacheKey);
  }

  // Create new request promise
  const requestPromise = (async () => {
    try {
    // Try Google Books first (most reliable for enrichment)
    const query = [bookTitle, authorName].filter(Boolean).join(' ');

    const googleResult = await externalApis.searchGoogleBooks(query, { maxResults }, env);

    if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
      // Convert normalized works back to Google Books volumeInfo format
      // This maintains compatibility with the existing enrichment code
      const items = googleResult.works.flatMap(work =>
        work.editions.map(edition => ({
          id: edition.googleBooksVolumeId || `synthetic-${edition.isbn13 || edition.isbn10}`,
          volumeInfo: {
            title: work.title,
            subtitle: work.subtitle,
            authors: work.authors.map(a => a.name),
            publishedDate: edition.publicationDate || edition.publishDate,
            publisher: edition.publisher,
            pageCount: edition.pageCount || edition.pages,
            categories: edition.genres || [],
            description: edition.description,
            imageLinks: edition.coverImageURL ? {
              thumbnail: edition.coverImageURL,
              smallThumbnail: edition.coverImageURL
            } : undefined,
            industryIdentifiers: [
              edition.isbn13 ? { type: 'ISBN_13', identifier: edition.isbn13 } : null,
              edition.isbn10 ? { type: 'ISBN_10', identifier: edition.isbn10 } : null
            ].filter(Boolean),
            previewLink: edition.previewLink,
            infoLink: edition.infoLink
          }
        }))
      );

      return {
        success: true,
        provider: 'google',
        items: items.slice(0, maxResults),
        cached: false
      };
    }

    // Fallback to OpenLibrary if Google Books fails
    console.log(`[AdvancedSearch] Google Books returned no results, trying OpenLibrary...`);

    const olResult = await externalApis.searchOpenLibrary(query, { maxResults }, env);

    if (olResult.success && olResult.works && olResult.works.length > 0) {
      // Convert OpenLibrary format to Google Books-compatible format
      const items = olResult.works.flatMap(work =>
        work.editions.map(edition => ({
          id: work.externalIds?.openLibraryWorkId || `ol-${work.title.replace(/\s+/g, '-').toLowerCase()}`,
          volumeInfo: {
            title: work.title,
            subtitle: work.subtitle,
            authors: work.authors.map(a => a.name),
            publishedDate: edition.publicationDate,
            publisher: edition.publisher,
            pageCount: edition.pageCount,
            categories: work.subjects?.slice(0, 5) || [],
            imageLinks: edition.coverImageURL ? {
              thumbnail: edition.coverImageURL,
              smallThumbnail: edition.coverImageURL
            } : undefined,
            industryIdentifiers: [
              edition.isbn13 ? { type: 'ISBN_13', identifier: edition.isbn13 } : null,
              edition.isbn10 ? { type: 'ISBN_10', identifier: edition.isbn10 } : null
            ].filter(Boolean)
          }
        }))
      );

      return {
        success: true,
        provider: 'openlibrary',
        items: items.slice(0, maxResults),
        cached: false
      };
    }

      // No results from any provider - store as "no_results" type (not error)
      console.log(`[AdvancedSearch] No results found from any provider`);
      await storeNegativeCache(cacheKey, { message: 'No results found', status: 404 }, 'no_results', env);

      return {
        success: true,
        provider: 'none',
        items: [],
        cached: false
      };

    } catch (error) {
      console.error(`[AdvancedSearch] Error searching for "${bookTitle}":`, error);

      // Store negative cache for 5xx errors only (not client errors)
      if (!error.status || error.status >= 500) {
        await storeNegativeCache(cacheKey, error, 'error', env);
      }

      return {
        success: false,
        error: error.message,
        items: []
      };
    } finally {
      // Clean up in-flight request
      IN_FLIGHT_REQUESTS.delete(cacheKey);
    }
  })();

  // Store promise for request coalescing
  IN_FLIGHT_REQUESTS.set(cacheKey, requestPromise);

  return requestPromise;
}
