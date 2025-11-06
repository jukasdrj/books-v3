/**
 * ISBNdb API → Canonical DTO Normalizers
 */

import type { WorkDTO, EditionDTO, AuthorDTO } from '../../types/canonical.js';
import type { EditionFormat } from '../../types/enums.js';
import { GenreNormalizer } from '../genre-normalizer.js';

// Create genre normalizer instance (reused across all normalizations)
const genreNormalizer = new GenreNormalizer();

/**
 * Extract year from ISBNdb date string
 * Formats: "2020", "2020-01", "2020-01-15"
 */
function extractYear(dateString?: string): number | undefined {
  if (!dateString) return undefined;
  const match = dateString.match(/^(\d{4})/);
  return match ? parseInt(match[1], 10) : undefined;
}

/**
 * Normalize ISBNdb binding to EditionFormat
 * ISBNdb provides: "Hardcover", "Paperback", "Mass Market Paperback", "eBook", "Library Binding", etc.
 */
function normalizeBinding(binding?: string): EditionFormat {
  if (!binding) return 'Paperback';
  
  const bindingLower = binding.toLowerCase();
  
  if (bindingLower.includes('hardcover') || bindingLower.includes('hardback')) {
    return 'Hardcover';
  }
  if (bindingLower.includes('paperback') || bindingLower.includes('trade paper')) {
    return 'Paperback';
  }
  if (bindingLower.includes('ebook') || bindingLower.includes('kindle') || bindingLower.includes('digital')) {
    return 'E-book';
  }
  if (bindingLower.includes('audio')) {
    return 'Audiobook';
  }
  
  // Default to Paperback
  return 'Paperback';
}

/**
 * Normalize ISBNdb book to WorkDTO
 */
export function normalizeISBNdbToWork(book: any): WorkDTO {
  return {
    title: book.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(book.subjects || [], 'isbndb'),
    originalLanguage: book.language || undefined,
    firstPublicationYear: extractYear(book.date_published),
    description: book.synopsis || undefined,
    synthetic: false,
    primaryProvider: 'isbndb',
    contributors: ['isbndb'],
    isbndbID: book.isbn13 || book.isbn || undefined, // Fallback to ISBN-10 if ISBN-13 missing
    goodreadsWorkIDs: [],
    amazonASINs: [],
    librarythingIDs: [],
    googleBooksVolumeIDs: [],
    isbndbQuality: calculateISBNdbQuality(book),
    reviewStatus: 'verified',
  };
}

/**
 * Normalize ISBNdb book to EditionDTO
 */
export function normalizeISBNdbToEdition(book: any): EditionDTO {
  const isbn13 = book.isbn13;
  const isbn10 = book.isbn;
  const isbns = [isbn13, isbn10].filter(Boolean) as string[];

  return {
    isbn: isbn13 || isbn10,
    isbns,
    title: book.title,
    publisher: book.publisher,
    publicationDate: book.date_published,
    pageCount: book.pages,
    format: normalizeBinding(book.binding),
    coverImageURL: book.image,
    editionTitle: book.title_long !== book.title ? book.title_long : undefined,
    editionDescription: book.synopsis,
    language: book.language,
    primaryProvider: 'isbndb',
    contributors: ['isbndb'],
    isbndbID: book.isbn13 || book.isbn || undefined, // Fallback to ISBN-10 if ISBN-13 missing
    amazonASINs: [],
    googleBooksVolumeIDs: [],
    librarythingIDs: [],
    isbndbQuality: calculateISBNdbQuality(book),
  };
}

/**
 * Normalize ISBNdb author name to AuthorDTO
 */
export function normalizeISBNdbToAuthor(authorName: string): AuthorDTO {
  return {
    name: authorName,
    gender: 'Unknown', // ISBNdb doesn't provide gender info
  };
}

/**
 * Calculate quality score for ISBNdb data (0-100)
 * Based on completeness and publisher reputation
 */
function calculateISBNdbQuality(book: any): number {
  let score = 50; // Base score

  // Add points for data completeness
  if (book.image) score += 20;
  if (book.synopsis && book.synopsis.length > 50) score += 10;
  if (book.pages && book.pages > 0) score += 5;
  if (book.publisher) score += 5;
  if (book.subjects && book.subjects.length > 0) score += 5;
  if (book.authors && book.authors.length > 0) score += 5;

  // Ensure score is always a valid number between 0-100
  const finalScore = Math.min(Math.max(score, 0), 100);
  return isNaN(finalScore) ? 50 : finalScore; // Default to 50 if NaN
}
