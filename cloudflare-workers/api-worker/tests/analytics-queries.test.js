import { describe, it, expect, vi } from 'vitest';
import { queryAccessFrequency } from '../src/utils/analytics-queries.js';

describe('queryAccessFrequency', () => {
  it('should return access counts per cache key', async () => {
    const mockEnv = {
      CACHE_ANALYTICS: {
        query: vi.fn().mockResolvedValue({
          results: [
            { cacheKey: 'search:title:q=hamlet', accessCount: 150 },
            { cacheKey: 'search:isbn:isbn=123', accessCount: 5 }
          ]
        })
      }
    };

    const stats = await queryAccessFrequency(mockEnv, 30);

    expect(stats['search:title:q=hamlet']).toBe(150);
    expect(stats['search:isbn:isbn=123']).toBe(5);
  });
});
