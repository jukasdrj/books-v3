/**
 * GET /v1/search/isbn
 *
 * Search for books by ISBN using canonical response format
 * Refactored to use shared enrichSingleBook() service (Task 2)
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';
import { enrichSingleBook } from '../../services/enrichment.ts';
import type { AuthorDTO } from '../../types/canonical.js';
import { normalizeISBN } from '../../utils/normalization.js';

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
    return createErrorResponseObject(
      'ISBN is required',
      'INVALID_ISBN',
      { isbn }
    );
  }

  if (!isValidISBN(isbn)) {
    return createErrorResponseObject(
      'Invalid ISBN format. Must be valid ISBN-10 or ISBN-13',
      'INVALID_ISBN',
      { isbn }
    );
  }

  try {
    // Normalize ISBN for consistent cache keys
    const normalizedISBN = normalizeISBN(isbn);
    console.log(`v1 ISBN search for "${isbn}" (normalized: "${normalizedISBN}") (using enrichSingleBook)`);

    // Use shared enrichment service (DRY - multi-provider fallback included)
    const result = await enrichSingleBook({ isbn: normalizedISBN }, env);

    if (!result) {
      // Book not found in any provider
      return createSuccessResponseObject(
        { works: [], authors: [] },
        {
          processingTime: Date.now() - startTime,
          provider: 'none',
          cached: false,
        }
      );
    }

    // enrichSingleBook returns a single WorkDTO with embedded authors
    // Extract authors from the work for the canonical response format
    const authors: AuthorDTO[] = result.authors || [];

    return createSuccessResponseObject(
      { works: [result], authors },
      {
        processingTime: Date.now() - startTime,
        provider: result.primaryProvider || 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    console.error('Error in v1 ISBN search:', error);
    return createErrorResponseObject(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
