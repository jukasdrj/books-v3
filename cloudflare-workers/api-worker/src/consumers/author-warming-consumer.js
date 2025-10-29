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

      // TODO: Search for author's works
      // TODO: Cache works
      // TODO: Discover co-authors

      // 5. Mark as processed
      await env.CACHE.put(
        `warming:processed:${author}`,
        JSON.stringify({
          worksCount: 0, // Placeholder
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
