// test/unified-cache.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { UnifiedCacheService } from '../src/services/unified-cache.js';

describe('UnifiedCacheService', () => {
  let service;
  let mockEnv;
  let mockCtx;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: vi.fn(async () => null),
        put: vi.fn(async () => {})
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn(async () => {})
      }
    };
    mockCtx = {
      waitUntil: vi.fn((promise) => promise)
    };

    service = new UnifiedCacheService(mockEnv, mockCtx);
  });

  test('initializes with edge, KV, and external API services', () => {
    expect(service.edgeCache).toBeDefined();
    expect(service.kvCache).toBeDefined();
    expect(service.env).toBe(mockEnv);
    expect(service.ctx).toBe(mockCtx);
  });

  test('get returns from edge cache on hit', async () => {
    const cacheKey = 'search:title:q=hamlet';
    const mockData = { items: [{ title: 'Hamlet' }] };

    // Mock edge cache hit
    service.edgeCache.get = vi.fn(async () => ({
      data: mockData,
      source: 'EDGE',
      latency: '<10ms'
    }));

    const result = await service.get(cacheKey, 'title', { query: 'hamlet' });

    expect(result.data).toEqual(mockData);
    expect(result.source).toBe('EDGE');
    expect(service.edgeCache.get).toHaveBeenCalledWith(cacheKey);
  });
});
