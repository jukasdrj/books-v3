import { describe, it, expect, beforeEach, vi } from 'vitest';
import { processAuthorBatch } from '../src/consumers/author-warming-consumer.js';

// Mock the search handlers
vi.mock('../src/handlers/book-search.js', () => ({
  searchByTitle: vi.fn().mockResolvedValue({
    kind: "books#volumes",
    totalItems: 1,
    items: [{
      volumeInfo: {
        title: 'Test Book',
        authors: ['Test Author']
      }
    }],
    cached: false
  })
}));

vi.mock('../src/handlers/author-search.js', () => ({
  searchByAuthor: vi.fn().mockResolvedValue({
    success: true,
    provider: 'openlibrary',
    author: {
      name: 'Neil Gaiman',
      openLibraryKey: '/authors/OL23919A',
      totalWorks: 2
    },
    works: [
      { title: 'American Gods', firstPublicationYear: 2001 },
      { title: 'Good Omens', firstPublicationYear: 1990 }
    ],
    cached: false
  })
}));

describe('processAuthorBatch', () => {
  let env, ctx, batch;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined)
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn().mockResolvedValue(undefined)
      }
    };
    ctx = {
      waitUntil: vi.fn()
    };
    batch = {
      messages: [
        {
          body: { author: 'Neil Gaiman', depth: 0, source: 'csv', jobId: 'job-1' },
          ack: vi.fn(),
          retry: vi.fn()
        }
      ]
    };
  });

  it('should skip already processed authors', async () => {
    env.CACHE.get.mockResolvedValueOnce(JSON.stringify({
      worksCount: 20,
      titlesWarmed: 18,
      lastWarmed: Date.now(),
      depth: 0
    }));

    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    // Should not call put for processing since already processed
    const processedCalls = env.CACHE.put.mock.calls.filter(call =>
      call[0].startsWith('warming:processed:')
    );
    expect(processedCalls.length).toBe(0);
  });

  it('should process new author and mark as processed', async () => {
    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    expect(env.CACHE.put).toHaveBeenCalledWith(
      'warming:processed:author:neil gaiman',
      expect.stringContaining('worksCount'),
      expect.objectContaining({ expirationTtl: 90 * 24 * 60 * 60 })
    );
  });

  it('should use searchByAuthor and searchByTitle handlers for cache consistency', async () => {
    const { searchByAuthor } = await import('../src/handlers/author-search.js');
    const { searchByTitle } = await import('../src/handlers/book-search.js');

    await processAuthorBatch(batch, env, ctx);

    // Verify searchByAuthor was called with correct parameters
    expect(searchByAuthor).toHaveBeenCalledWith(
      'Neil Gaiman',
      expect.objectContaining({
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      }),
      env,
      ctx
    );

    // Verify searchByTitle was called for each work
    expect(searchByTitle).toHaveBeenCalledTimes(2);
    expect(searchByTitle).toHaveBeenCalledWith(
      'American Gods',
      { maxResults: 20 },
      env,
      ctx
    );
    expect(searchByTitle).toHaveBeenCalledWith(
      'Good Omens',
      { maxResults: 20 },
      env,
      ctx
    );
  });

  it('should track titlesWarmed count separately from worksCount', async () => {
    await processAuthorBatch(batch, env, ctx);

    // Verify processed data includes both counts
    const processedCall = env.CACHE.put.mock.calls.find(call =>
      call[0] === 'warming:processed:author:neil gaiman'
    );
    expect(processedCall).toBeDefined();
    const processedData = JSON.parse(processedCall[1]);
    expect(processedData.worksCount).toBe(2);
    expect(processedData.titlesWarmed).toBe(2);
    expect(processedData.jobId).toBe('job-1');
  });

  it('should write analytics for warming activity', async () => {
    await processAuthorBatch(batch, env, ctx);

    expect(ctx.waitUntil).toHaveBeenCalled();
    expect(env.CACHE_ANALYTICS.writeDataPoint).toHaveBeenCalledWith(
      expect.objectContaining({
        blobs: ['warming', 'Neil Gaiman', 'csv'],
        doubles: [2, 2],
        indexes: ['cache-warming']
      })
    );
  });

  it('should retry on rate limit errors', async () => {
    const { searchByAuthor } = await import('../src/handlers/author-search.js');
    searchByAuthor.mockRejectedValueOnce(new Error('429 rate limit exceeded'));

    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].retry).toHaveBeenCalled();
    expect(batch.messages[0].ack).not.toHaveBeenCalled();
  });
});

// Note: This implementation now uses searchByAuthor and searchByTitle handlers
// to ensure cache key consistency and canonical DTO format.
// Per 2025-10-29-cache-warming-fix.md design doc.
