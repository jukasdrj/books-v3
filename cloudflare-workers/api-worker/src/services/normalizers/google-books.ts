/**
 * Google Books API → Canonical DTO Normalizers
 */

import type { WorkDTO, EditionDTO } from '../../types/canonical.js';
import { GenreNormalizer } from '../genre-normalizer.js';

// Create genre normalizer instance (reused across all normalizations)
const genreNormalizer = new GenreNormalizer();

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
 * Get high-resolution cover URL from Google Books API thumbnail link
 */
function getHighResCoverURL(imageLinks?: { thumbnail?: string }): string | undefined {
  const thumbnailURL = imageLinks?.thumbnail?.replace('http:', 'https:');
  if (!thumbnailURL) return undefined;

  // Request high-resolution image by changing zoom parameter.
  // This removes any existing zoom parameter and adds our preferred one.
  return thumbnailURL.replace(/&zoom=\d/, '') + '&zoom=3';
}

/**
 * Normalize Google Books volume to WorkDTO
 */
export function normalizeGoogleBooksToWork(item: any): WorkDTO {
  const volumeInfo = item.volumeInfo || {};

  return {
    title: volumeInfo.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(volumeInfo.categories || [], 'google-books'),
    originalLanguage: volumeInfo.language,
    firstPublicationYear: extractYear(volumeInfo.publishedDate),
    description: volumeInfo.description,
    coverImageURL: getHighResCoverURL(volumeInfo.imageLinks),
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

/**
 * Normalize Google Books volume to EditionDTO
 */
export function normalizeGoogleBooksToEdition(item: any): EditionDTO {
  const volumeInfo = item.volumeInfo || {};
  const identifiers = volumeInfo.industryIdentifiers || [];

  const isbn13 = identifiers.find((id: any) => id.type === 'ISBN_13')?.identifier;
  const isbn10 = identifiers.find((id: any) => id.type === 'ISBN_10')?.identifier;
  const isbns = [isbn13, isbn10].filter(Boolean) as string[];

  return {
    isbn: isbn13 || isbn10,
    isbns,
    title: volumeInfo.title,
    publisher: volumeInfo.publisher,
    publicationDate: volumeInfo.publishedDate,
    pageCount: volumeInfo.pageCount,
    format: 'Hardcover', // Google Books doesn't provide format
    coverImageURL: getHighResCoverURL(volumeInfo.imageLinks),
    editionTitle: undefined,
    editionDescription: volumeInfo.description,
    language: volumeInfo.language,
    primaryProvider: 'google-books',
    contributors: ['google-books'],
    amazonASINs: [],
    googleBooksVolumeIDs: [item.id],
    librarythingIDs: [],
    isbndbQuality: 0,
  };
}

/**
 * Synthesize Work from Edition when Work data is missing
 * Sets synthetic: true to indicate inferred data
 */
export function ensureWorkForEdition(edition: EditionDTO): WorkDTO {
  return {
    title: edition.title || 'Unknown',
    subjectTags: [], // No genres available from Edition data
    firstPublicationYear: extractYear(edition.publicationDate),
    coverImageURL: edition.coverImageURL, // FIX #346: Copy cover URL from Edition
    synthetic: true, // KEY: indicates this Work was inferred
    primaryProvider: edition.primaryProvider,
    contributors: edition.contributors,
    goodreadsWorkIDs: [],
    amazonASINs: edition.amazonASINs,
    librarythingIDs: edition.librarythingIDs,
    googleBooksVolumeIDs: edition.googleBooksVolumeIDs,
    isbndbQuality: edition.isbndbQuality,
    reviewStatus: 'verified',
  };
}
