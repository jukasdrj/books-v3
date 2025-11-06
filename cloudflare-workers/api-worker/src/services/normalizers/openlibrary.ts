/**
 * OpenLibrary API → Canonical DTO Normalizers
 */

import type { WorkDTO, EditionDTO, AuthorDTO } from '../../types/canonical.js';
import { GenreNormalizer } from '../genre-normalizer.js';

// Create genre normalizer instance (reused across all normalizations)
const genreNormalizer = new GenreNormalizer();

/**
 * Extract year from various date formats
 * OpenLibrary uses inconsistent formats: "1949", "Jun 8, 1949", etc.
 */
function extractYear(dateString?: string | number): number | undefined {
  if (!dateString) return undefined;
  
  // Handle numeric year directly
  if (typeof dateString === 'number') return dateString;
  
  // Extract year from string
  const match = dateString.match(/\b(\d{4})\b/);
  return match ? parseInt(match[1], 10) : undefined;
}

/**
 * Normalize OpenLibrary search result to WorkDTO
 */
export function normalizeOpenLibraryToWork(doc: any): WorkDTO {
  return {
    title: doc.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(doc.subject || [], 'openlibrary'),
    originalLanguage: doc.language?.[0],
    firstPublicationYear: extractYear(doc.first_publish_year),
    description: undefined, // OpenLibrary search doesn't include descriptions
    coverImageURL: doc.cover_i
      ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg`
      : undefined,
    synthetic: false,
    primaryProvider: 'openlibrary',
    contributors: ['openlibrary'],
    openLibraryWorkID: extractWorkId(doc.key), // Canonical field
    goodreadsWorkIDs: doc.id_goodreads || [],
    amazonASINs: doc.id_amazon || [],
    librarythingIDs: doc.id_librarything || [],
    googleBooksVolumeIDs: doc.id_google || [],
    isbndbQuality: 0,
    reviewStatus: 'verified',
  };
}

/**
 * Normalize OpenLibrary search result to EditionDTO
 * Note: OpenLibrary search results are often Work-level, not Edition-level
 */
export function normalizeOpenLibraryToEdition(doc: any): EditionDTO {
  const isbn13 = doc.isbn?.find((isbn: string) => isbn.length === 13);
  const isbn10 = doc.isbn?.find((isbn: string) => isbn.length === 10);
  const isbns = [isbn13, isbn10].filter(Boolean) as string[];

  return {
    isbn: isbn13 || isbn10,
    isbns,
    title: doc.title,
    publisher: doc.publisher?.[0],
    publicationDate: doc.publish_date?.[0],
    pageCount: doc.number_of_pages_median,
    format: inferFormat(doc),
    coverImageURL: doc.cover_i
      ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg`
      : undefined,
    language: doc.language?.[0],
    primaryProvider: 'openlibrary',
    contributors: ['openlibrary'],
    openLibraryID: extractEditionId(doc.key),
    openLibraryEditionID: extractEditionId(doc.key),
    amazonASINs: doc.id_amazon || [],
    googleBooksVolumeIDs: doc.id_google || [],
    librarythingIDs: doc.id_librarything || [],
    isbndbQuality: 0,
  };
}

/**
 * Normalize OpenLibrary author to AuthorDTO
 */
export function normalizeOpenLibraryToAuthor(authorName: string): AuthorDTO {
  return {
    name: authorName,
    gender: 'Unknown', // OpenLibrary doesn't provide gender info
  };
}

/**
 * Extract Work ID from OpenLibrary key
 * Example: "/works/OL45804W" → "OL45804W"
 */
function extractWorkId(key?: string): string | undefined {
  if (!key) return undefined;
  const match = key.match(/\/works\/([^\/]+)/);
  return match ? match[1] : undefined;
}

/**
 * Extract Edition ID from OpenLibrary key
 * Example: "/books/OL7353617M" → "OL7353617M"
 */
function extractEditionId(key?: string): string | undefined {
  if (!key) return undefined;
  const match = key.match(/\/books\/([^\/]+)/);
  return match ? match[1] : undefined;
}

/**
 * Infer format from OpenLibrary data
 * OpenLibrary doesn't always provide format explicitly
 */
function inferFormat(doc: any): 'Paperback' | 'Hardcover' | 'E-book' {
  // Default to Paperback (most common format)
  return 'Paperback';
}
