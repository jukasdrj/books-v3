// src/services/edge-cache.js

/**
 * Edge Cache Service using Cloudflare's caches.default API
 *
 * Provides ultra-fast caching at Cloudflare edge locations (5-10ms latency).
 * Caches are automatically distributed globally and expire based on TTL.
 */
export class EdgeCacheService {
  /**
   * Get cached data from edge cache
   * @param {string} cacheKey - Unique cache identifier
   * @returns {Promise<Object|null>} Cached data with metadata, or null if miss
   */
  async get(cacheKey) {
    try {
      const cache = caches.default;
      const request = new Request(`https://cache.internal/${cacheKey}`, {
        method: 'GET'
      });

      const response = await cache.match(request);
      if (response) {
        const data = await response.json();
        return {
          data,
          source: 'EDGE',
          latency: '<10ms'
        };
      }
    } catch (error) {
      console.error(`Edge cache get failed for ${cacheKey}:`, error);
    }

    return null;
  }

  /**
   * Store data in edge cache with TTL
   * @param {string} cacheKey - Unique cache identifier
   * @param {Object} data - Data to cache (must be JSON-serializable)
   * @param {number} ttl - Time to live in seconds
   * @returns {Promise<void>}
   */
  async set(cacheKey, data, ttl) {
    try {
      const cache = caches.default;
      const request = new Request(`https://cache.internal/${cacheKey}`, {
        method: 'GET'
      });

      const response = new Response(JSON.stringify(data), {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${ttl}, s-maxage=${ttl}`,
          'X-Cache-Source': 'edge',
          'X-Cache-TTL': ttl.toString()
        }
      });

      await cache.put(request, response);
    } catch (error) {
      console.error(`Edge cache set failed for ${cacheKey}:`, error);
      // Don't throw - cache failures shouldn't break user requests
    }
  }
}
