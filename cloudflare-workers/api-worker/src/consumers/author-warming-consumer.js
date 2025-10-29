import { getOpenLibraryAuthorWorks } from '../services/external-apis.js';
import { generateCacheKey } from '../utils/cache.js';
import { UnifiedCacheService } from '../services/unified-cache.js';

/**
 * Author Warming Consumer - Processes queued authors
 *
 * Strategy: Fetch author works from OpenLibrary and cache them using
 * UnifiedCacheService to populate all three tiers (Edge, KV, R2).
 *
 * Note: Does NOT warm individual title searches (would hit subrequest limits).
 * Focuses on caching author bibliographies with proper tier distribution.
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

      // 2. Fetch author's works from OpenLibrary
      const searchResult = await getOpenLibraryAuthorWorks(author, env);

      if (!searchResult || !searchResult.success || !searchResult.works) {
        console.warn(`No works found for ${author}, skipping`);
        message.ack();
        continue;
      }

      const works = searchResult.works;
      console.log(`Found ${works.length} works for ${author}`);

      // 3. Cache author search result using UnifiedCacheService
      // This populates all three tiers: Edge, KV, and R2 index
      const authorCacheKey = generateCacheKey('search:author', {
        author: author.toLowerCase(),
        limit: 100,
        offset: 0,
        sortBy: 'publicationYear'
      });

      await unifiedCache.set(
        authorCacheKey,
        {
          success: true,
          works: works,
          author: author,
          totalWorks: works.length,
          cached: true,
          cacheSource: 'warming'
        },
        'author',
        21600 // 6h TTL
      );

      console.log(`✅ Cached author "${author}" with ${works.length} works`);
      console.log(`   Cache key: ${authorCacheKey}`);
      console.log(`   Tiers populated: Edge (6h), KV (6h), R2 index (90d)`);

      // 4. Cache individual work titles for basic title searches
      // Uses minimal data to avoid subrequest limits
      let titlesCached = 0;
      for (const work of works) {
        if (!work.title) continue;

        try {
          // Generate title cache key matching search endpoint format
          const titleCacheKey = generateCacheKey('search:title', {
            title: work.title.toLowerCase(),
            maxResults: 20
          });

          // Cache minimal work data (just OpenLibrary, no Google Books)
          // This provides SOME cache hits for title searches, though not as rich
          await unifiedCache.set(
            titleCacheKey,
            {
              kind: 'books#volumes',
              totalItems: 1,
              items: [{
                volumeInfo: {
                  title: work.title,
                  authors: [author],
                  publishedDate: work.first_publish_year?.toString(),
                  description: work.subtitle || '',
                  industryIdentifiers: work.isbn ? [{
                    type: 'ISBN_13',
                    identifier: work.isbn[0]
                  }] : []
                },
                searchInfo: {
                  textSnippet: `OpenLibrary work by ${author}`
                }
              }],
              cached: true,
              cacheSource: 'warming',
              provider: 'openlibrary-minimal'
            },
            'title',
            21600 // 6h TTL
          );

          titlesCached++;

        } catch (titleError) {
          console.error(`Failed to cache title "${work.title}":`, titleError);
          // Continue with next title
        }
      }

      console.log(`✅ Cached ${titlesCached} individual titles from author's works`);

      // 5. Mark author as processed (90-day TTL)
      await env.CACHE.put(
        processedKey,
        JSON.stringify({
          worksCount: works.length,
          titlesCached: titlesCached,
          lastWarmed: Date.now(),
          jobId: jobId,
          strategy: 'openlibrary-minimal'
        }),
        { expirationTtl: 90 * 24 * 60 * 60 } // 90 days
      );

      // 6. Analytics
      if (env.CACHE_ANALYTICS) {
        await env.CACHE_ANALYTICS.writeDataPoint({
          blobs: ['warming', author, source],
          doubles: [works.length, titlesCached, 0],
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
