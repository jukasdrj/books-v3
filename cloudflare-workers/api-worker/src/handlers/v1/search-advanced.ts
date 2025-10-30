/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { searchGoogleBooks } from '../../services/external-apis.js';
import type { WorkDTO, AuthorDTO } from '../../types/canonical.js';

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
    // Combine title and author into query
    const query = [title, author].filter(Boolean).join(' ');

    // Call existing Google Books search
    const result = await searchGoogleBooks(query, { maxResults: 20 }, env);

    if (!result.success) {
      return createErrorResponse(
        result.error || 'Advanced search failed',
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
