/**
 * GET /v1/search/isbn
 *
 * Search for books by ISBN using canonical response format
 * Refactored to use shared enrichMultipleBooks() service for consistency
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../../types/responses.js';
import { enrichMultipleBooks } from '../../services/enrichment.ts';
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
    console.log(`v1 ISBN search for "${isbn}" (normalized: "${normalizedISBN}") (using enrichMultipleBooks)`);

    // Use enrichMultipleBooks for consistency with other v1 search endpoints
    const result = await enrichMultipleBooks({ isbn: normalizedISBN }, env, { maxResults: 1 });

    if (!result || !result.works || result.works.length === 0) {
      // Book not found in any provider
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
    console.error('Error in v1 ISBN search:', error);
    return createErrorResponseObject(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
