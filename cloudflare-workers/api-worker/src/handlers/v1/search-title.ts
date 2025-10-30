/**
 * GET /v1/search/title
 *
 * Search for books by title using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { searchGoogleBooks } from '../../services/external-apis.js';
import { normalizeGoogleBooksToWork } from '../../services/normalizers/google-books.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

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
    // Call existing Google Books search
    const result = await searchGoogleBooks(query, { maxResults: 20 }, env);

    if (!result.success) {
      return createErrorResponse(
        result.error || 'Search failed',
        'PROVIDER_ERROR',
        undefined,
        { processingTime: Date.now() - startTime }
      );
    }

    // Convert legacy format to canonical DTOs
    const works: WorkDTO[] = result.works.map((legacyWork: any) => {
      // Legacy work format has: title, subjects, firstPublishYear, editions
      return {
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
      };
    });

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
