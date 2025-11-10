// src/services/edge-cache.js

/**
 * Edge Cache Service using Cloudflare's caches.default API
 *
 * Provides ultra-fast caching at Cloudflare edge locations (5-10ms latency).
 * Caches are automatically distributed globally and expire based on TTL.
 *
 * Optimizations:
 * - Stale-While-Revalidate (SWR): Serve stale content while fetching fresh data
 * - Reduces latency during cache misses and upstream failures
 */
export class EdgeCacheService {
  /**
   * Get cached data from edge cache with SWR support
   * @param {string} cacheKey - Unique cache identifier
   * @param {Object} options - Cache options
   * @param {number} options.maxAge - Fresh TTL in seconds (default: 3600)
   * @param {number} options.staleWhileRevalidate - Stale TTL in seconds (default: 86400)
   * @returns {Promise<Object|null>} Cached data with metadata, or null if miss
   */
  async get(cacheKey, options = {}) {
    const maxAge = options.maxAge || 3600; // 1 hour fresh
    const staleWhileRevalidate = options.staleWhileRevalidate || 86400; // 24 hours stale

    try {
      const cache = caches.default;
      const request = new Request(`https://cache.internal/${cacheKey}`, {
        method: 'GET'
      });

      const response = await cache.match(request);
      if (response) {
        const age = parseInt(response.headers.get('Age') || '0');
        const data = await response.json();

        // Fresh hit
        if (age < maxAge) {
          return {
            data,
            source: 'EDGE_FRESH',
            age,
            latency: '<10ms'
          };
        }

        // Stale hit (serve stale, background refresh handled by caller)
        if (age < maxAge + staleWhileRevalidate) {
          return {
            data,
            source: 'EDGE_STALE',
            age,
            stale: true,
            latency: '<10ms'
          };
        }
      }
    } catch (error) {
      console.error(`Edge cache get failed for ${cacheKey}:`, error);
    }

    return null;
  }

  /**
   * Store data in edge cache with TTL and SWR support
   * @param {string} cacheKey - Unique cache identifier
   * @param {Object} data - Data to cache (must be JSON-serializable)
   * @param {number} ttl - Fresh TTL in seconds (max-age)
   * @param {number} staleWhileRevalidate - Stale TTL in seconds (default: 24 hours)
   * @returns {Promise<void>}
   */
  async set(cacheKey, data, ttl, staleWhileRevalidate = 86400) {
    try {
      const cache = caches.default;
      const request = new Request(`https://cache.internal/${cacheKey}`, {
        method: 'GET'
      });

      const response = new Response(JSON.stringify(data), {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${ttl}, s-maxage=${ttl}, stale-while-revalidate=${staleWhileRevalidate}`,
          'X-Cache-Source': 'edge',
          'X-Cache-TTL': ttl.toString(),
          'X-Cache-SWR': staleWhileRevalidate.toString()
        }
      });

      await cache.put(request, response);
    } catch (error) {
      console.error(`Edge cache set failed for ${cacheKey}:`, error);
      // Don't throw - cache failures shouldn't break user requests
    }
  }
}
