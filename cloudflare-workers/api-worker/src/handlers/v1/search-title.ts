/**
 * GET /v1/search/title
 *
 * Search for books by title using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { normalizeGoogleBooksToWork } from '../../services/normalizers/google-books.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

const GOOGLE_BOOKS_USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com)';

export async function handleSearchTitle(
  query: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation
  if (!query || query.trim().length === 0) {
    return createErrorResponse(
      'Search query is required',
      'INVALID_QUERY',
      { query }
    );
  }

  try {
    console.log(`GoogleBooks v1 title search for "${query}"`);

    // Get API key (handle both secrets store and direct env var)
    const apiKey = env.GOOGLE_BOOKS_API_KEY?.get
      ? await env.GOOGLE_BOOKS_API_KEY.get()
      : env.GOOGLE_BOOKS_API_KEY;

    if (!apiKey) {
      return createErrorResponse(
        'Google Books API key not configured',
        'INTERNAL_ERROR',
        undefined,
        { processingTime: Date.now() - startTime }
      );
    }

    // Call Google Books API directly
    const maxResults = 20;
    const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(query)}&maxResults=${maxResults}&key=${apiKey}`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': GOOGLE_BOOKS_USER_AGENT,
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      return createErrorResponse(
        `Google Books API error: ${response.status} ${response.statusText}`,
        'PROVIDER_ERROR',
        undefined,
        { processingTime: Date.now() - startTime }
      );
    }

    const data = await response.json();

    // Use canonical normalizer with genre normalization
    const works: WorkDTO[] = (data.items || []).map((item: any) =>
      normalizeGoogleBooksToWork(item)
    );

    // Extract unique authors from all works
    const authorsSet = new Set<string>();
    data.items?.forEach((item: any) => {
      const authors = item.volumeInfo?.authors || [];
      authors.forEach((author: string) => authorsSet.add(author));
    });

    const authors: AuthorDTO[] = Array.from(authorsSet).map(name => ({
      name,
      gender: 'Unknown',
    }));

    return createSuccessResponse(
      { works, authors },
      {
        processingTime: Date.now() - startTime,
        provider: 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    console.error('Error in v1 title search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
