// src/services/unified-cache.js
import { EdgeCacheService } from './edge-cache.js';
import { KVCacheService } from './kv-cache.js';

/**
 * Unified Cache Service - Single entry point for all cache operations
 *
 * Routes requests intelligently through cache tiers:
 * 1. Edge Cache (caches.default) - 5-10ms, 80% hit rate
 * 2. KV Cache (extended TTLs) - 30-50ms, 15% hit rate
 * 3. External APIs (fallback) - 300-500ms, 5% miss rate
 *
 * Target: 95% overall hit rate, <10ms P50 latency
 */
export class UnifiedCacheService {
  constructor(env, ctx) {
    this.edgeCache = new EdgeCacheService();
    this.kvCache = new KVCacheService(env);
    this.env = env;
    this.ctx = ctx;
  }

  /**
   * Get data from cache tiers (Edge → KV → API)
   * @param {string} cacheKey - Cache key
   * @param {string} endpoint - Endpoint type ('title', 'isbn', 'author')
   * @param {Object} options - Query options (query, maxResults, etc.)
   * @returns {Promise<Object>} Cached or fresh data with metadata
   */
  async get(cacheKey, endpoint, options = {}) {
    const startTime = Date.now();

    // Tier 1: Edge Cache (fastest, 80% hit rate)
    const edgeResult = await this.edgeCache.get(cacheKey);
    if (edgeResult) {
      this.logMetrics('edge_hit', cacheKey, Date.now() - startTime);
      return edgeResult;
    }

    // Tier 2: KV Cache (fast, 15% hit rate)
    const kvResult = await this.kvCache.get(cacheKey, endpoint);
    if (kvResult) {
      // Populate edge cache for next request (async, non-blocking)
      this.ctx.waitUntil(
        this.edgeCache.set(cacheKey, kvResult.data, 6 * 60 * 60) // 6h edge TTL
      );

      this.logMetrics('kv_hit', cacheKey, Date.now() - startTime);
      return kvResult;
    }

    // NEW: Tier 2.5: Check Cold Storage Index
    const coldIndex = await this.env.CACHE.get(`cold-index:${cacheKey}`, 'json');
    if (coldIndex) {
      this.logMetrics('cold_check', cacheKey, Date.now() - startTime);

      // Trigger background rehydration (non-blocking)
      this.ctx.waitUntil(
        this.rehydrateFromR2(cacheKey, coldIndex, endpoint)
      );

      // Return null immediately (user gets fresh API data)
      return { data: null, source: 'COLD', latency: Date.now() - startTime };
    }

    // Tier 3: API Miss
    this.logMetrics('api_miss', cacheKey, Date.now() - startTime);
    return { data: null, source: 'MISS', latency: Date.now() - startTime };
  }

  /**
   * Set data in all cache tiers (Edge → KV → R2 index)
   * @param {string} cacheKey - Cache key
   * @param {Object} data - Data to cache
   * @param {string} endpoint - Endpoint type ('title', 'isbn', 'author')
   * @param {number} ttl - TTL in seconds (default: 6h)
   * @returns {Promise<void>}
   */
  async set(cacheKey, data, endpoint, ttl = 21600) {
    const startTime = Date.now();

    try {
      // Write to all three tiers in parallel
      await Promise.all([
        this.edgeCache.set(cacheKey, data, ttl),           // Tier 1: Edge
        this.kvCache.set(cacheKey, data, endpoint, ttl),   // Tier 2: KV
        this.createColdIndex(cacheKey, data, endpoint)     // Tier 3: R2 index
      ]);

      this.logMetrics('cache_set', cacheKey, Date.now() - startTime);
    } catch (error) {
      console.error(`Failed to set cache for ${cacheKey}:`, error);
      throw error;
    }
  }

  /**
   * Create R2 cold storage index for future rehydration
   * @param {string} cacheKey - Original cache key
   * @param {Object} data - Cached data
   * @param {string} endpoint - Endpoint type
   */
  async createColdIndex(cacheKey, data, endpoint) {
    try {
      const indexKey = `cold-index:${cacheKey}`;
      const indexData = {
        r2Key: `cold-cache/${new Date().toISOString().split('T')[0]}/${cacheKey}`,
        createdAt: Date.now(),
        endpoint: endpoint,
        size: JSON.stringify(data).length
      };

      await this.env.CACHE.put(indexKey, JSON.stringify(indexData), {
        expirationTtl: 90 * 24 * 60 * 60 // 90 days
      });

      console.log(`Created cold index for ${cacheKey}`);
    } catch (error) {
      console.error(`Failed to create cold index for ${cacheKey}:`, error);
      // Don't throw - cold indexing is optional
    }
  }

  /**
   * Rehydrate archived data from R2 to KV and Edge
   *
   * @param {string} cacheKey - Original cache key
   * @param {Object} coldIndex - Cold storage index metadata
   * @param {string} endpoint - Endpoint type
   */
  async rehydrateFromR2(cacheKey, coldIndex, endpoint) {
    try {
      console.log(`Rehydrating ${cacheKey} from R2...`);

      // 1. Fetch from R2
      const r2Object = await this.env.LIBRARY_DATA.get(coldIndex.r2Path);
      if (!r2Object) {
        console.error(`R2 object not found: ${coldIndex.r2Path}`);
        return;
      }

      const data = await r2Object.json();

      // 2. Restore to KV with extended TTL (7 days)
      await this.kvCache.set(cacheKey, data, endpoint, {
        ttl: 7 * 24 * 60 * 60
      });

      // 3. Populate Edge cache
      await this.edgeCache.set(cacheKey, data, 6 * 60 * 60);

      // 4. Remove from cold index (now warm)
      await this.env.CACHE.delete(`cold-index:${cacheKey}`);

      // 5. Log rehydration
      this.logMetrics('r2_rehydrated', cacheKey, 0);

      console.log(`Successfully rehydrated ${cacheKey}`);

    } catch (error) {
      console.error(`Rehydration failed for ${cacheKey}:`, error);
      // Log error but don't throw (background operation)
    }
  }

  /**
   * Log cache metrics to Analytics Engine
   * @param {string} event - Event type (edge_hit, kv_hit, api_miss)
   * @param {string} cacheKey - Cache key
   * @param {number} latency - Latency in milliseconds
   */
  logMetrics(event, cacheKey, latency) {
    if (!this.env.CACHE_ANALYTICS) return;

    try {
      this.env.CACHE_ANALYTICS.writeDataPoint({
        blobs: [event, cacheKey],
        doubles: [latency],
        indexes: [event]
      });
    } catch (error) {
      console.error('Failed to log cache metrics:', error);
    }
  }
}
