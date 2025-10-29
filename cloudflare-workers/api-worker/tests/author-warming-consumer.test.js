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
});
