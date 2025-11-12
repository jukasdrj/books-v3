/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 * Returns up to 20 results for iOS search UI
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';
import { enrichMultipleBooks } from '../../services/enrichment.ts';
import { normalizeTitle, normalizeAuthor } from '../../utils/normalization.js';
import { setCached, generateCacheKey } from '../../utils/cache.js';
import { UnifiedCacheService } from '../../services/unified-cache.js';
import { extractUniqueAuthors, removeAuthorsFromWorks } from '../../utils/response-transformer.js';

export async function handleSearchAdvanced(
  title: string,
  author: string,
  env: any,
  ctx: ExecutionContext
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation - require at least one parameter
  const hasTitle = title && title.trim().length > 0;
  const hasAuthor = author && author.trim().length > 0;

  if (!hasTitle && !hasAuthor) {
    return createErrorResponseObject(
      'At least one of title or author is required',
      'INVALID_QUERY',
      { title, author }
    );
  }

  try {
    // Normalize both title and author for consistent cache keys
    const normalizedTitle = hasTitle ? normalizeTitle(title) : '';
    const normalizedAuthor = hasAuthor ? normalizeAuthor(author) : '';

    // Check cache first
    const cacheKey = generateCacheKey('v1:advanced', {
      title: normalizedTitle,
      author: normalizedAuthor
    });

    const cache = new UnifiedCacheService(env, ctx);
    const cachedResult = await cache.get(cacheKey, 'advanced', {
      query: `${title} ${author}`.trim()
    });

    if (cachedResult?.data) {
      console.log(`✅ Cache HIT: /v1/search/advanced (${cacheKey})`);
      return {
        ...cachedResult.data,
        meta: {
          ...cachedResult.data.meta,
          cached: true,
          cacheSource: cachedResult.source // EDGE or KV
        }
      };
    }

    console.log(
      `v1 advanced search - title: "${title}" (normalized: "${normalizedTitle}"), ` +
      `author: "${author}" (normalized: "${normalizedAuthor}") ` +
      `(using enrichMultipleBooks, maxResults: 20)`
    );

    // Use enrichMultipleBooks for search endpoints (returns up to 20 results)
    const result = await enrichMultipleBooks(
      {
        title: normalizedTitle,
        author: normalizedAuthor
      },
      env,
      { maxResults: 20 }
    );

    if (!result || !result.works || result.works.length === 0) {
      // No books found in any provider
      return createSuccessResponseObject(
        { works: [], editions: [], authors: [] },
        {
          processingTime: Date.now() - startTime,
          provider: 'none',
          cached: false,
        }
      );
    }

    // Extract all unique authors from works
    const authors = extractUniqueAuthors(result.works);

    // Remove authors property from works (not part of canonical WorkDTO)
    const cleanWorks = removeAuthorsFromWorks(result.works);

    const response = createSuccessResponseObject(
      { works: cleanWorks, editions: result.editions, authors },
      {
        processingTime: Date.now() - startTime,
        provider: cleanWorks[0]?.primaryProvider, // Use actual provider from enriched work
        cached: false,
      }
    );

    // Write to cache (6h TTL, same as /search/title)
    const ttl = 6 * 60 * 60; // 21600 seconds
    ctx.waitUntil(setCached(cacheKey, response, ttl, env));
    console.log(`💾 Cache WRITE: /v1/search/advanced (${cacheKey}, TTL: ${ttl}s)`);

    return response;
  } catch (error: any) {
    console.error('Error in v1 advanced search:', error);
    return createErrorResponseObject(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
