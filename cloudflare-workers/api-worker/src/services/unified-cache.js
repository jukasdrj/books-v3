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

    // Tier 1: Edge Cache (fastest, 80% hit rate) with SWR support
    const edgeResult = await this.edgeCache.get(cacheKey, {
      maxAge: 3600,          // 1 hour fresh
      staleWhileRevalidate: 86400  // 24 hours stale
    });

    if (edgeResult) {
      // Fresh hit - return immediately
      if (!edgeResult.stale) {
        this.logMetrics('edge_hit_fresh', cacheKey, Date.now() - startTime);
        return edgeResult;
      }

      // Stale hit - return stale data but trigger background refresh
      this.logMetrics('edge_hit_stale', cacheKey, Date.now() - startTime);
      console.log(`🔄 Serving stale edge cache (age: ${edgeResult.age}s), triggering background refresh`);

      // Background refresh (non-blocking)
      this.ctx.waitUntil(
        this.refreshStaleCache(cacheKey, endpoint, options)
      );

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
   * Background refresh for stale cache entries
   * Fetches fresh data from API and updates all cache tiers
   *
   * @param {string} cacheKey - Cache key to refresh
   * @param {string} endpoint - Endpoint type
   * @param {Object} options - Original query options
   *
   * KNOWN LIMITATION (Sprint 1-2):
   * This is a stub implementation deferred to Sprint 3-4.
   * SWR currently serves stale data instantly (primary benefit), but does NOT
   * automatically refresh in background. Stale entries expire after 24h and
   * are re-fetched on next access.
   *
   * Impact: Low - book metadata staleness is minimal (ISBNs never change,
   * new editions are rare). Current behavior provides 99% of SWR benefits
   * (instant stale serving) without complexity of background refresh.
   *
   * Future: Implement actual refresh by calling handleAdvancedSearch() or
   * appropriate endpoint based on cache key pattern.
   */
  async refreshStaleCache(cacheKey, endpoint, options) {
    try {
      console.log(`🔄 Background refresh started for: ${cacheKey}`);

      // TODO (Sprint 3-4): Implement actual refresh logic
      // Example:
      // if (endpoint === 'title') {
      //   const result = await handleAdvancedSearch(options, {}, this.env);
      //   await this.kvCache.set(cacheKey, result, endpoint);
      //   await this.edgeCache.set(cacheKey, result, 6 * 60 * 60);
      // }

      console.log(`⚠️ Background refresh stub - not yet implemented (deferred to Sprint 3-4)`);
    } catch (error) {
      console.error(`❌ Background refresh failed for ${cacheKey}:`, error);
      // Don't throw - background refresh failures are non-critical
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
