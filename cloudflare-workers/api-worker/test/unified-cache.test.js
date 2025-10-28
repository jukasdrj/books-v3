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

  test('get falls back to KV on edge miss', async () => {
    const cacheKey = 'search:title:q=obscure-book';
    const mockData = { items: [{ title: 'Obscure Book' }] };

    // Mock edge miss, KV hit
    service.edgeCache.get = vi.fn(async () => null);
    service.kvCache.get = vi.fn(async () => ({
      data: mockData,
      source: 'KV',
      age: 3600,
      latency: '30-50ms'
    }));

    const result = await service.get(cacheKey, 'title', { query: 'obscure-book' });

    expect(result.data).toEqual(mockData);
    expect(result.source).toBe('KV');
    expect(service.edgeCache.get).toHaveBeenCalledWith(cacheKey);
    expect(service.kvCache.get).toHaveBeenCalledWith(cacheKey, 'title');
  });

  test('get populates edge cache after KV hit', async () => {
    const cacheKey = 'search:title:q=book';
    const mockData = { items: [{ title: 'Book' }] };

    service.edgeCache.get = vi.fn(async () => null);
    service.edgeCache.set = vi.fn(async () => {});
    service.kvCache.get = vi.fn(async () => ({
      data: mockData,
      source: 'KV',
      age: 3600
    }));

    await service.get(cacheKey, 'title', { query: 'book' });

    // Should populate edge cache asynchronously
    expect(mockCtx.waitUntil).toHaveBeenCalled();

    // Verify edge.set was called with correct params
    const waitUntilCall = mockCtx.waitUntil.mock.calls[0][0];
    await waitUntilCall; // Resolve the promise

    expect(service.edgeCache.set).toHaveBeenCalledWith(
      cacheKey,
      mockData,
      6 * 60 * 60 // 6h TTL for edge
    );
  });
});
