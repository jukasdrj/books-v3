/**
 * GET /v1/search/title
 *
 * Search for books by title using canonical response format
 * Returns up to 20 results for iOS search UI
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';
import { enrichMultipleBooks } from '../../services/enrichment.ts';
import { normalizeTitle } from '../../utils/normalization.js';
import { extractUniqueAuthors, removeAuthorsFromWorks } from '../../utils/response-transformer.js';

export async function handleSearchTitle(
  query: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation
  if (!query || query.trim().length === 0) {
    return createErrorResponseObject(
      'Search query is required',
      'INVALID_QUERY',
      { query }
    );
  }

  try {
    // Normalize title for consistent cache keys
    const normalizedTitle = normalizeTitle(query);
    console.log(`v1 title search for "${query}" (normalized: "${normalizedTitle}") (using enrichMultipleBooks, maxResults: 20)`);

    // Use enrichMultipleBooks for search endpoints (returns up to 20 results)
    const result = await enrichMultipleBooks({ title: normalizedTitle }, env, { maxResults: 20 });

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

    return createSuccessResponseObject(
      { works: cleanWorks, editions: result.editions, authors },
      {
        processingTime: Date.now() - startTime,
        provider: cleanWorks[0]?.primaryProvider, // Use actual provider from enriched work
        cached: false,
      }
    );
  } catch (error: any) {
    console.error('Error in v1 title search:', error);
    return createErrorResponseObject(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
