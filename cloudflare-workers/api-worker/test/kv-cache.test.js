// test/kv-cache.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { KVCacheService } from '../src/services/kv-cache.js';

describe('KVCacheService', () => {
  let service;
  let mockEnv;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: async () => null,
        put: async () => {},
      }
    };
    service = new KVCacheService(mockEnv);
  });

  test('initializes with extended TTLs', () => {
    expect(service.ttls.title).toBe(24 * 60 * 60); // 24h
    expect(service.ttls.isbn).toBe(30 * 24 * 60 * 60); // 30d
    expect(service.ttls.author).toBe(7 * 24 * 60 * 60); // 7d
  });

  test('get returns null on cache miss', async () => {
    const result = await service.get('search:title:q=nonexistent', 'title');
    expect(result).toBeNull();
  });

  test('assessDataQuality returns 1.0 for complete data', () => {
    const data = {
      items: [
        {
          volumeInfo: {
            industryIdentifiers: [{ type: 'ISBN_13', identifier: '123' }],
            imageLinks: { thumbnail: 'http://example.com/cover.jpg' },
            description: 'A'.repeat(150) // 150 chars
          }
        }
      ]
    };

    const quality = service.assessDataQuality(data);
    expect(quality).toBe(1.0); // Has ISBN (0.4) + cover (0.4) + description (0.2)
  });

  test('assessDataQuality returns 0.4 for ISBN-only data', () => {
    const data = {
      items: [
        {
          volumeInfo: {
            industryIdentifiers: [{ type: 'ISBN_13', identifier: '123' }]
            // No cover, no description
          }
        }
      ]
    };

    const quality = service.assessDataQuality(data);
    expect(quality).toBe(0.4); // Only ISBN (0.4)
  });

  test('adjustTTLByQuality doubles TTL for high quality (>0.8)', () => {
    const baseTTL = 3600; // 1 hour
    const adjusted = service.adjustTTLByQuality(baseTTL, 0.9);
    expect(adjusted).toBe(7200); // 2x for quality > 0.8
  });

  test('adjustTTLByQuality halves TTL for low quality (<0.4)', () => {
    const baseTTL = 3600; // 1 hour
    const adjusted = service.adjustTTLByQuality(baseTTL, 0.3);
    expect(adjusted).toBe(1800); // 0.5x for quality < 0.4
  });

  test('set uses smart TTL for high-quality data', async () => {
    const cacheKey = 'search:title:q=test';
    const highQualityData = {
      items: [
        {
          volumeInfo: {
            industryIdentifiers: [{ type: 'ISBN_13', identifier: '123' }],
            imageLinks: { thumbnail: 'http://example.com/cover.jpg' },
            description: 'A'.repeat(150)
          }
        }
      ]
    };

    // Mock setCached to capture TTL
    let capturedTTL;
    mockEnv.CACHE.put = vi.fn(async (key, value, options) => {
      capturedTTL = options.expirationTtl;
    });

    await service.set(cacheKey, highQualityData, 'title');

    // Base TTL for title is 24h (86400s), high quality doubles it
    expect(capturedTTL).toBe(86400 * 2); // 48 hours
  });
});
