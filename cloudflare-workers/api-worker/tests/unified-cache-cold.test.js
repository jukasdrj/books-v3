import { describe, it, expect, beforeEach, vi } from 'vitest';
import { UnifiedCacheService } from '../src/services/unified-cache.js';

describe('UnifiedCacheService - Cold Storage', () => {
  let env, ctx, cache;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn()
      },
      LIBRARY_DATA: {
        get: vi.fn()
      }
    };
    ctx = {
      waitUntil: vi.fn()
    };
    cache = new UnifiedCacheService(env, ctx);
  });

  it('should check cold index after KV miss', async () => {
    // Mock: Edge miss, KV miss, cold index hit
    cache.edgeCache.get = vi.fn().mockResolvedValue(null);
    cache.kvCache.get = vi.fn().mockResolvedValue(null);

    env.CACHE.get.mockResolvedValueOnce(JSON.stringify({
      r2Path: 'cold-cache/2025/10/search:title:q=book.json',
      archivedAt: Date.now(),
      originalTTL: 86400
    }));

    const result = await cache.get('search:title:q=book', 'title');

    expect(result.data).toBeNull(); // User gets fresh data
    expect(ctx.waitUntil).toHaveBeenCalled(); // Rehydration triggered
  });

  it('should return API miss if no cold index', async () => {
    cache.edgeCache.get = vi.fn().mockResolvedValue(null);
    cache.kvCache.get = vi.fn().mockResolvedValue(null);
    env.CACHE.get.mockResolvedValue(null);

    const result = await cache.get('search:title:q=new-book', 'title');

    expect(result.source).toBe('MISS');
  });

  it('should rehydrate from R2 to KV and Edge', async () => {
    const mockR2Object = {
      json: vi.fn().mockResolvedValue({ items: [{ title: 'Book' }] })
    };

    env.LIBRARY_DATA.get.mockResolvedValue(mockR2Object);
    cache.kvCache.set = vi.fn();
    cache.edgeCache.set = vi.fn();
    env.CACHE.delete = vi.fn();

    const coldIndex = {
      r2Path: 'cold-cache/2025/10/search:title:q=book.json',
      archivedAt: Date.now(),
      originalTTL: 86400
    };

    await cache.rehydrateFromR2('search:title:q=book', coldIndex, 'title');

    expect(env.LIBRARY_DATA.get).toHaveBeenCalledWith(coldIndex.r2Path);
    expect(cache.kvCache.set).toHaveBeenCalled();
    expect(cache.edgeCache.set).toHaveBeenCalled();
    expect(env.CACHE.delete).toHaveBeenCalledWith('cold-index:search:title:q=book');
  });
});
