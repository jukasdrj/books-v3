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
   * Set data in Edge Cache
   * @param {string} cacheKey - Cache key
   * @param {Object} data - Data to cache
   * @param {number} ttl - TTL in seconds
   * @returns {Promise<void>}
   */
  async set(cacheKey, data, ttl) {
    try {
      const cache = caches.default;
      const url = `https://cache.internal/${cacheKey}`;

      const response = new Response(JSON.stringify({
        data: data,
        cachedAt: Date.now(),
        ttl: ttl,
        source: 'EDGE'
      }), {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${ttl}`
        }
      });

      await cache.put(url, response);
      console.log(`Edge cache SET: ${cacheKey}`);
    } catch (error) {
      console.error(`Edge cache set error for ${cacheKey}:`, error);
      throw error;
    }
  }
}
