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
}
