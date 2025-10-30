/**
 * Google Books API → Canonical DTO Normalizers
 */

import type { WorkDTO, EditionDTO } from '../../types/canonical.js';

/**
 * Extract year from Google Books date string
 * Formats: "1949", "1949-06", "1949-06-08"
 */
function extractYear(dateString?: string): number | undefined {
  if (!dateString) return undefined;
  const match = dateString.match(/^(\d{4})/);
  return match ? parseInt(match[1], 10) : undefined;
}

/**
 * Normalize Google Books volume to WorkDTO
 */
export function normalizeGoogleBooksToWork(item: any): WorkDTO {
  const volumeInfo = item.volumeInfo || {};

  return {
    title: volumeInfo.title || 'Unknown',
    subjectTags: volumeInfo.categories || [],
    originalLanguage: volumeInfo.language,
    firstPublicationYear: extractYear(volumeInfo.publishedDate),
    description: volumeInfo.description,
    synthetic: false,
    primaryProvider: 'google-books',
    contributors: ['google-books'],
    goodreadsWorkIDs: [],
    amazonASINs: [],
    librarythingIDs: [],
    googleBooksVolumeIDs: [item.id],
    isbndbQuality: 0,
    reviewStatus: 'verified',
  };
}
