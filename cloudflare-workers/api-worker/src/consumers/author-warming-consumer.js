import { searchByTitle } from '../handlers/book-search.js';
import { searchByAuthor } from '../handlers/author-search.js';
import { generateCacheKey } from '../utils/cache.js';
import { UnifiedCacheService } from '../services/unified-cache.js';

/**
 * Author Warming Consumer - Processes queued authors with hierarchical warming
 *
 * Flow:
 * 1. Warm author bibliography (searchByAuthor) → Cache author page
 * 2. Extract titles from author's works
 * 3. Warm each title (searchByTitle) → Cache title searches
 *
 * @param {Object} batch - Batch of queue messages
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context
 */
export async function processAuthorBatch(batch, env, ctx) {
  const unifiedCache = new UnifiedCacheService(env, ctx);

  for (const message of batch.messages) {
    try {
      const { author, source, jobId } = message.body;

      // 1. Check if already processed (90-day deduplication)
      const processedKey = `warming:processed:author:${author.toLowerCase()}`;
      const processed = await env.CACHE.get(processedKey, 'json');

      if (processed) {
        const age = Math.floor((Date.now() - processed.lastWarmed) / (24 * 60 * 60 * 1000));
        console.log(`Skipping ${author}: already processed ${age} days ago`);
        message.ack();
        continue;
      }

      console.log(`\n=== Warming author: ${author} ===`);

      // 2. STEP 1: Warm author bibliography
      console.log(`Step 1: Fetching author works for "${author}"...`);
      const authorResult = await searchByAuthor(author, {
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      }, env, ctx);

      if (!authorResult.success || !authorResult.works || authorResult.works.length === 0) {
        console.warn(`No works found for ${author}, skipping`);
        message.ack();
        continue;
      }

      console.log(`Found ${authorResult.works.length} works for ${author}`);

      // Cache author search result
      const authorCacheKey = generateCacheKey('search:author', {
        author: author.toLowerCase(),
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      });

      await unifiedCache.set(authorCacheKey, authorResult, 'author', 21600); // 6h TTL
      console.log(`✅ Cached author "${author}" (key: ${authorCacheKey})`);

      // 3. STEP 2: Extract titles and warm each one
      console.log(`Step 2: Warming ${authorResult.works.length} titles...`);
      let titlesWarmed = 0;
      let titlesSkipped = 0;

      for (const work of authorResult.works) {
        try {
          if (!work.title) {
            titlesSkipped++;
            continue;
          }

          // Search by title to get full orchestrated data (Google + OpenLibrary)
          const titleResult = await searchByTitle(work.title, {
            maxResults: 20
          }, env, ctx);

          if (titleResult && titleResult.items && titleResult.items.length > 0) {
            const titleCacheKey = generateCacheKey('search:title', {
              title: work.title.toLowerCase(),
              maxResults: 20
            });

            await unifiedCache.set(titleCacheKey, titleResult, 'title', 21600); // 6h TTL
            titlesWarmed++;

            if (titlesWarmed % 10 === 0) {
              console.log(`  Progress: ${titlesWarmed}/${authorResult.works.length} titles warmed`);
            }
          } else {
            titlesSkipped++;
          }

          // Rate limiting: Small delay between title searches
          await sleep(100); // 100ms between titles

        } catch (titleError) {
          console.error(`Failed to warm title "${work.title}":`, titleError);
          titlesSkipped++;
          // Continue with next title (don't fail entire batch)
        }
      }

      console.log(`✅ Warmed ${titlesWarmed} titles for author "${author}" (${titlesSkipped} skipped)`);

      // 4. Mark author as processed (90-day TTL)
      await env.CACHE.put(
        processedKey,
        JSON.stringify({
          worksCount: authorResult.works.length,
          titlesWarmed: titlesWarmed,
          titlesSkipped: titlesSkipped,
          lastWarmed: Date.now(),
          jobId: jobId
        }),
        { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
      );

      // 5. Analytics
      if (env.CACHE_ANALYTICS) {
        await env.CACHE_ANALYTICS.writeDataPoint({
          blobs: ['warming', author, source],
          doubles: [authorResult.works.length, titlesWarmed, titlesSkipped],
          indexes: ['cache-warming']
        });
      }

      console.log(`=== Completed warming for ${author} ===\n`);
      message.ack();

    } catch (error) {
      console.error(`Failed to process author ${message.body.author}:`, error);

      // Retry on rate limits, fail otherwise
      if (error.message.includes('429') || error.message.includes('rate limit')) {
        console.error('Rate limit detected, will retry with backoff');
        message.retry();
      } else {
        console.error('Non-retryable error, sending to DLQ after retries');
        message.retry(); // Retry up to 3 times, then DLQ
      }
    }
  }
}

/**
 * Sleep utility for rate limiting
 * @param {number} ms - Milliseconds to sleep
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
