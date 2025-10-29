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
});
