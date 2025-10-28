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

    // TODO: Add external API fallback
    return { data: null, source: 'MISS', latency: Date.now() - startTime };
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
