import { describe, it, expect, beforeEach, vi } from 'vitest';
import { selectArchivalCandidates } from '../src/workers/archival-worker.js';

describe('selectArchivalCandidates', () => {
  let env;

  beforeEach(() => {
    env = {
      CACHE: {
        list: vi.fn().mockResolvedValue({
          keys: [
            { name: 'search:title:q=old-book' },
            { name: 'search:title:q=popular-book' }
          ]
        }),
        getWithMetadata: vi.fn()
      }
    };
  });

  it('should select entries that are old AND rarely accessed', async () => {
    const accessStats = {
      'search:title:q=old-book': 5,
      'search:title:q=popular-book': 100
    };

    const now = Date.now();
    const thirtyOneDaysAgo = now - (31 * 24 * 60 * 60 * 1000);

    env.CACHE.getWithMetadata.mockImplementation(async (key) => {
      if (key === 'search:title:q=old-book') {
        return {
          value: JSON.stringify({ items: [] }),
          metadata: { cachedAt: thirtyOneDaysAgo }
        };
      } else {
        return {
          value: JSON.stringify({ items: [] }),
          metadata: { cachedAt: now }
        };
      }
    });

    const candidates = await selectArchivalCandidates(env, accessStats);

    expect(candidates).toHaveLength(1);
    expect(candidates[0].key).toBe('search:title:q=old-book');
  });

  it('should NOT archive entries that are frequently accessed', async () => {
    const accessStats = {
      'search:title:q=popular-book': 100
    };

    // Mock: Only return the popular book in the list
    env.CACHE.list.mockResolvedValue({
      keys: [
        { name: 'search:title:q=popular-book' }
      ]
    });

    env.CACHE.getWithMetadata.mockResolvedValue({
      value: JSON.stringify({ items: [] }),
      metadata: { cachedAt: Date.now() - (40 * 24 * 60 * 60 * 1000) } // 40 days old
    });

    const candidates = await selectArchivalCandidates(env, accessStats);

    expect(candidates).toHaveLength(0); // Excluded because accessCount > 10
  });
});
