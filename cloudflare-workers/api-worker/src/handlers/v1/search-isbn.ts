/**
 * GET /v1/search/isbn
 *
 * Search for books by ISBN using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { normalizeGoogleBooksToWork } from '../../services/normalizers/google-books.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

const GOOGLE_BOOKS_USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com)';

/**
 * Validate ISBN-10 or ISBN-13 format
 * ISBN-10: 10 digits (or 9 digits + X)
 * ISBN-13: 13 digits
 */
function isValidISBN(isbn: string): boolean {
  if (!isbn || isbn.trim().length === 0) return false;

  const cleaned = isbn.replace(/[-\s]/g, ''); // Remove hyphens and spaces

  // ISBN-13: exactly 13 digits
  if (cleaned.length === 13 && /^\d{13}$/.test(cleaned)) return true;

  // ISBN-10: 9 digits + (digit or X)
  if (cleaned.length === 10 && /^\d{9}[\dX]$/i.test(cleaned)) return true;

  return false;
}

export async function handleSearchISBN(
  isbn: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation
  if (!isbn || isbn.trim().length === 0) {
    return createErrorResponse(
      'ISBN is required',
      'INVALID_ISBN',
      { isbn }
    );
  }

  if (!isValidISBN(isbn)) {
    return createErrorResponse(
      'Invalid ISBN format. Must be valid ISBN-10 or ISBN-13',
      'INVALID_ISBN',
      { isbn }
    );
  }

  try {
    console.log(`GoogleBooks v1 ISBN search for "${isbn}"`);

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
    const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=isbn:${encodeURIComponent(isbn)}&key=${apiKey}`;

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
    console.error('Error in v1 ISBN search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
