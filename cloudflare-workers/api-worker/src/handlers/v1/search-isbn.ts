/**
 * GET /v1/search/isbn
 *
 * Search for books by ISBN using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { searchGoogleBooksByISBN } from '../../services/external-apis.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

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
    // Call existing Google Books ISBN search
    const result = await searchGoogleBooksByISBN(isbn, env);

    if (!result.success) {
      return createErrorResponse(
        result.error || 'ISBN search failed',
        'PROVIDER_ERROR',
        undefined,
        { processingTime: Date.now() - startTime }
      );
    }

    // Convert legacy format to canonical DTOs
    const works: WorkDTO[] = result.works.map((legacyWork: any) => ({
      title: legacyWork.title || 'Unknown',
      subjectTags: legacyWork.subjects || [],
      firstPublicationYear: legacyWork.firstPublishYear,
      description: legacyWork.description,
      originalLanguage: legacyWork.language,
      synthetic: false,
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      goodreadsWorkIDs: [],
      amazonASINs: [],
      librarythingIDs: [],
      googleBooksVolumeIDs: legacyWork.editions?.map((e: any) => e.googleBooksVolumeId).filter(Boolean) || [],
      isbndbQuality: 0,
      reviewStatus: 'verified',
    }));

    const authors: AuthorDTO[] = result.authors?.map((legacyAuthor: any) => ({
      name: legacyAuthor.name,
      gender: 'Unknown',
    })) || [];

    return createSuccessResponse(
      { works, authors },
      {
        processingTime: Date.now() - startTime,
        provider: 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
