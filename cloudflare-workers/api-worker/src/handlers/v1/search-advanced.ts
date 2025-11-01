/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { normalizeGoogleBooksToWork } from '../../services/normalizers/google-books.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

const GOOGLE_BOOKS_USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com)';

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
    console.log(`GoogleBooks v1 advanced search - title: "${title}", author: "${author}"`);

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

    // Build Google Books query with intitle and inauthor filters
    const queryParts: string[] = [];
    if (hasTitle) queryParts.push(`intitle:${title}`);
    if (hasAuthor) queryParts.push(`inauthor:${author}`);
    const query = queryParts.join('+');

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
    // Single-pass iteration: build works and extract authors simultaneously
    const { works, authorsSet } = (data.items || []).reduce(
      (acc, item: any) => {
        acc.works.push(normalizeGoogleBooksToWork(item));
        const itemAuthors = item.volumeInfo?.authors || [];
        itemAuthors.forEach((author: string) => acc.authorsSet.add(author));
        return acc;
      },
      { works: [] as WorkDTO[], authorsSet: new Set<string>() }
    );

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
    console.error('Error in v1 advanced search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
