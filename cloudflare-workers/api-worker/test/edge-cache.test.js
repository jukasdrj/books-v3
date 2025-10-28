// test/edge-cache.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { EdgeCacheService } from '../src/services/edge-cache.js';

describe('EdgeCacheService', () => {
  let service;
  let mockCache;

  beforeEach(() => {
    // Mock Cloudflare caches.default API
    mockCache = {
      match: vi.fn(async () => null),
      put: vi.fn(async () => {})
    };

    vi.stubGlobal('caches', { default: mockCache });
    service = new EdgeCacheService();
  });

  test('get returns null on cache miss', async () => {
    const result = await service.get('nonexistent-key');
    expect(result).toBeNull();
  });

  test('set stores data and get retrieves it', async () => {
    const cacheKey = 'test:key:123';
    const testData = { title: 'Test Book', items: [1, 2, 3] };
    const ttl = 3600; // 1 hour

    // Mock cache.match to return cached data
    mockCache.match = vi.fn(async () => {
      return new Response(JSON.stringify(testData), {
        headers: { 'Content-Type': 'application/json' }
      });
    });

    await service.set(cacheKey, testData, ttl);

    const result = await service.get(cacheKey);
    expect(result).not.toBeNull();
    expect(result.data).toEqual(testData);
    expect(result.source).toBe('EDGE');
    expect(result.latency).toMatch(/<\d+ms/);
  });
});
