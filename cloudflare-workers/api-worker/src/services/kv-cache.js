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

  /**
   * Get cached data from KV
   * @param {string} cacheKey - Cache key
   * @param {string} endpoint - Endpoint type ('title', 'isbn', 'author')
   * @returns {Promise<Object|null>} Cached data with metadata or null
   */
  async get(cacheKey, endpoint) {
    try {
      const result = await getCached(cacheKey, this.env);
      if (result) {
        return {
          data: result.data,
          source: 'KV',
          age: result.cacheMetadata.age,
          latency: '30-50ms'
        };
      }
    } catch (error) {
      console.error(`KV cache get failed for ${cacheKey}:`, error);
    }

    return null;
  }

  /**
   * Assess data quality for smart TTL adjustment
   * @param {Object} data - Response data with items array
   * @returns {number} Quality score 0.0 to 1.0
   */
  assessDataQuality(data) {
    const items = data.items || [];
    if (items.length === 0) return 0;

    let score = 0;
    for (const item of items) {
      const volumeInfo = item.volumeInfo;
      const hasISBN = volumeInfo?.industryIdentifiers?.length > 0;
      const hasCover = volumeInfo?.imageLinks?.thumbnail;
      const hasDescription = volumeInfo?.description?.length > 100;

      if (hasISBN) score += 0.4;
      if (hasCover) score += 0.4;
      if (hasDescription) score += 0.2;
    }

    return score / items.length; // Average quality across all items
  }

  /**
   * Adjust TTL based on data quality
   * @param {number} baseTTL - Base TTL in seconds
   * @param {number} quality - Quality score 0.0 to 1.0
   * @returns {number} Adjusted TTL in seconds
   */
  adjustTTLByQuality(baseTTL, quality) {
    if (quality > 0.8) return baseTTL * 2;      // High quality → 2x TTL
    if (quality < 0.4) return baseTTL * 0.5;    // Low quality → 0.5x TTL
    return baseTTL; // Medium quality → unchanged
  }

  /**
   * Store data in KV with smart TTL adjustment
   * @param {string} cacheKey - Cache key
   * @param {Object} data - Data to cache
   * @param {string} endpoint - Endpoint type ('title', 'isbn', 'author')
   * @param {Object} options - Optional overrides
   * @returns {Promise<void>}
   */
  async set(cacheKey, data, endpoint, options = {}) {
    try {
      const baseTTL = options.ttl || this.ttls[endpoint] || this.ttls.title;

      // Smart TTL adjustment based on data quality
      const quality = this.assessDataQuality(data);
      const adjustedTTL = this.adjustTTLByQuality(baseTTL, quality);

      await setCached(cacheKey, data, adjustedTTL, this.env);
    } catch (error) {
      console.error(`KV cache set failed for ${cacheKey}:`, error);
      // Don't throw - cache failures shouldn't break user requests
    }
  }
}
