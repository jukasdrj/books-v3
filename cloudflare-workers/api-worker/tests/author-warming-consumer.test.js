import { describe, it, expect, beforeEach, vi } from 'vitest';
import { processAuthorBatch } from '../src/consumers/author-warming-consumer.js';

describe('processAuthorBatch', () => {
  let env, ctx, batch;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined)
      },
      AUTHOR_WARMING_QUEUE: {
        send: vi.fn().mockResolvedValue({ id: 'msg-123' })
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
      lastWarmed: Date.now(),
      depth: 0
    }));

    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    expect(env.CACHE.put).not.toHaveBeenCalled();
  });

  it('should process new author and mark as processed', async () => {
    await processAuthorBatch(batch, env, ctx);

    expect(batch.messages[0].ack).toHaveBeenCalled();
    expect(env.CACHE.put).toHaveBeenCalledWith(
      'warming:processed:Neil Gaiman',
      expect.stringContaining('worksCount'),
      expect.objectContaining({ expirationTtl: 90 * 24 * 60 * 60 })
    );
  });

  it('should search external APIs and cache works', async () => {
    const mockWorks = [
      { title: 'American Gods', firstPublicationYear: 2001, openLibraryWorkKey: '/works/OL45804W' },
      { title: 'Good Omens', firstPublicationYear: 1990, openLibraryWorkKey: '/works/OL45805W' }
    ];

    // Mock getOpenLibraryAuthorWorks
    global.fetch = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL23919A', name: 'Neil Gaiman' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks.map(w => ({
          title: w.title,
          first_publish_year: w.firstPublicationYear,
          key: w.openLibraryWorkKey
        })),
        size: 2
      }), { status: 200 }));

    await processAuthorBatch(batch, env, ctx);

    // Verify author marked as processed with work count
    const processedCall = env.CACHE.put.mock.calls.find(call =>
      call[0] === 'warming:processed:Neil Gaiman'
    );
    expect(processedCall).toBeDefined();
    const processedData = JSON.parse(processedCall[1]);
    expect(processedData.worksCount).toBe(2);
  });
});
