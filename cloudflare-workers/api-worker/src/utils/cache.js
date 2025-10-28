/**
 * KV caching utilities
 * Migrated from books-api-proxy caching logic
 */

/**
 * Get cached data from KV store with metadata
 * @param {string} key - Cache key
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object|null>} Cached data with metadata or null if not found
 */
export async function getCached(key, env) {
  try {
    const cached = await env.CACHE.get(key, 'json');
    if (cached) {
      console.log(`Cache HIT: ${key}`);

      // Handle both old format (direct data) and new format (with metadata)
      if (cached.data && cached.cachedAt) {
        // New format with metadata
        const age = Math.floor((Date.now() - cached.cachedAt) / 1000); // Age in seconds
        const ttl = cached.ttl || 0;

        return {
          data: cached.data,
          cacheMetadata: {
            hit: true,
            age: age,
            ttl: ttl
          }
        };
      } else {
        // Old format (direct data) - backward compatibility
        return {
          data: cached,
          cacheMetadata: {
            hit: true,
            age: 0,
            ttl: 0
          }
        };
      }
    }
  } catch (error) {
    console.error('Cache read error:', error);
  }

  console.log(`Cache MISS: ${key}`);
  return null;
}

/**
 * Set cached data in KV store with TTL and metadata
 * @param {string} key - Cache key
 * @param {Object} value - Data to cache
 * @param {number} ttl - Time to live in seconds
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<void>}
 */
export async function setCached(key, value, ttl, env) {
  try {
    const cachedWithMeta = {
      data: value,
      cachedAt: Date.now(),  // Timestamp for age calculation
      ttl: ttl                // Original TTL for headers
    };

    await env.CACHE.put(key, JSON.stringify(cachedWithMeta), {
      expirationTtl: ttl
    });
    console.log(`Cache SET: ${key} (TTL: ${ttl}s)`);
  } catch (error) {
    console.error('Cache write error:', error);
  }
}

/**
 * Generate cache key from prefix and parameters
 * @param {string} prefix - Cache key prefix (e.g., 'search:title', 'search:isbn')
 * @param {Object} params - Key-value pairs to include in cache key
 * @returns {string} Generated cache key
 */
export function generateCacheKey(prefix, params) {
  const sortedParams = Object.keys(params)
    .sort()
    .map(k => `${k}=${params[k]}`)
    .join('&');
  return `${prefix}:${sortedParams}`;
}
