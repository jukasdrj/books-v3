// src/services/kv-cache.js
import { getCached, setCached } from '../utils/cache.js';

/**
 * KV Cache Service with extended TTLs optimized for Paid Plan
 *
 * TTL Strategy (vs Original PRD):
 * - Title: 24h (vs 6h) - Paid plan KV is cheap, longer = fewer API calls
 * - ISBN: 30d (vs 7d) - ISBN metadata never changes
 * - Author: 7d (vs 12h) - Popular authors stable
 * - Enrichment: 90d - Metadata very stable
 */
export class KVCacheService {
  constructor(env) {
    this.env = env;
    this.ttls = {
      title: 24 * 60 * 60,        // 24 hours
      isbn: 30 * 24 * 60 * 60,     // 30 days
      author: 7 * 24 * 60 * 60,    // 7 days
      enrichment: 90 * 24 * 60 * 60 // 90 days
    };
  }
}
