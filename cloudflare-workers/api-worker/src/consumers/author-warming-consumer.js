import { getOpenLibraryAuthorWorks } from '../services/external-apis.js';

/**
 * Author Warming Consumer - Processes queued authors
 *
 * @param {Object} batch - Batch of queue messages
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context
 */
export async function processAuthorBatch(batch, env, ctx) {
  for (const message of batch.messages) {
    try {
      const { author, depth, source, jobId } = message.body;

      // 1. Check if already processed
      const processed = await env.CACHE.get(`warming:processed:${author}`);
      if (processed) {
        const data = JSON.parse(processed);
        if (depth <= data.depth) {
          console.log(`Skipping ${author}: already processed at depth ${data.depth}`);
          message.ack();
          continue;
        }
      }

      // 2. Search external APIs for author's works
      const searchResult = await getOpenLibraryAuthorWorks(author, env);

      if (!searchResult || !searchResult.success) {
        console.warn(`No works found for ${author}`);
        message.ack();
        continue;
      }

      const works = searchResult.works || [];

      // 3. Cache each work via KV
      for (const work of works) {
        const cacheKey = `search:title:${work.title.toLowerCase()}`;
        await env.CACHE.put(cacheKey, JSON.stringify({
          items: [work],
          cached: true,
          timestamp: Date.now()
        }), {
          expirationTtl: 24 * 60 * 60 // 24h for warmed entries
        });
      }

      // 4. Co-author discovery skipped (Phase 3 optimization)
      // OpenLibrary's /authors/{id}/works.json doesn't include co-author data
      // Would require GET /works/{id}.json per work (expensive)

      // 5. Mark as processed
      await env.CACHE.put(
        `warming:processed:${author}`,
        JSON.stringify({
          worksCount: works.length,
          lastWarmed: Date.now(),
          depth: depth
        }),
        { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
      );

      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);
      message.retry();
    }
  }
}
