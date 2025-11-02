/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 * Returns up to 20 results for iOS search UI
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { enrichMultipleBooks } from '../../services/enrichment.js';
import type { AuthorDTO } from '../../types/canonical.js';

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
    return createErrorResponse(
      'At least one of title or author is required',
      'INVALID_QUERY',
      { title, author }
    );
  }

  try {
    console.log(`v1 advanced search - title: "${title}", author: "${author}" (using enrichMultipleBooks, maxResults: 20)`);

    // Use enrichMultipleBooks for search endpoints (returns up to 20 results)
    const works = await enrichMultipleBooks(
      {
        title: hasTitle ? title : undefined,
        author: hasAuthor ? author : undefined
      },
      env,
      { maxResults: 20 }
    );

    if (!works || works.length === 0) {
      // No books found in any provider
      return createSuccessResponse(
        { works: [], authors: [] },
        {
          processingTime: Date.now() - startTime,
          provider: 'none',
          cached: false,
        }
      );
    }

    // Extract all unique authors from works
    const authorsMap = new Map<string, AuthorDTO>();
    works.forEach(work => {
      (work.authors || []).forEach((author: AuthorDTO) => {
        if (!authorsMap.has(author.name)) {
          authorsMap.set(author.name, author);
        }
      });
    });
    const authors = Array.from(authorsMap.values());

    return createSuccessResponse(
      { works, authors },
      {
        processingTime: Date.now() - startTime,
        provider: works[0]?.primaryProvider || 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    console.error('Error in v1 advanced search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
