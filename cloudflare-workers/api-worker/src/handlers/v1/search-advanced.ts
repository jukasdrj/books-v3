/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 * Returns up to 20 results for iOS search UI
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';
import { enrichMultipleBooks } from '../../services/enrichment.ts';
import type { AuthorDTO } from '../../types/canonical.js';
import { normalizeTitle, normalizeAuthor } from '../../utils/normalization.js';

export async function handleSearchAdvanced(
  title: string,
  author: string,
  env: any
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
    const normalizedTitle = hasTitle ? normalizeTitle(title) : undefined;
    const normalizedAuthor = hasAuthor ? normalizeAuthor(author) : undefined;

    console.log(`v1 advanced search - title: "${title}" (normalized: "${normalizedTitle}"), author: "${author}" (normalized: "${normalizedAuthor}") (using enrichMultipleBooks, maxResults: 20)`);

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
    const authorsMap = new Map<string, AuthorDTO>();
    result.works.forEach(work => {
      (work.authors || []).forEach((author: AuthorDTO) => {
        if (!authorsMap.has(author.name)) {
          authorsMap.set(author.name, author);
        }
      });
    });
    const authors = Array.from(authorsMap.values());

    // Remove authors property from works (not part of canonical WorkDTO)
    const cleanWorks = result.works.map(work => {
      const { authors: _, ...cleanWork } = work;
      return cleanWork;
    });

    return createSuccessResponseObject(
      { works: cleanWorks, editions: result.editions, authors },
      {
        processingTime: Date.now() - startTime,
        provider: result.works[0]?.primaryProvider || 'google-books',
        cached: false,
      }
    );
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
