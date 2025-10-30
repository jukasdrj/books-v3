/**
 * Canonical Enum Types
 *
 * These match Swift enums in BooksTrackerFeature exactly.
 * DO NOT modify without updating iOS Swift enums.
 */

export type EditionFormat =
  | 'Hardcover'
  | 'Paperback'
  | 'E-book'
  | 'Audiobook'
  | 'Mass Market';

export type AuthorGender =
  | 'Female'
  | 'Male'
  | 'Non-binary'
  | 'Other'
  | 'Unknown';

export type CulturalRegion =
  | 'Africa'
  | 'Asia'
  | 'Europe'
  | 'North America'
  | 'South America'
  | 'Oceania'
  | 'Middle East'
  | 'Caribbean'
  | 'Central Asia'
  | 'Indigenous'
  | 'International';

export type ReviewStatus =
  | 'verified'
  | 'needsReview'
  | 'userEdited';

/**
 * Provider identifiers for attribution
 */
export type DataProvider =
  | 'google-books'
  | 'openlibrary'
  | 'isbndb'
  | 'gemini';

/**
 * Error codes for structured error handling
 */
export type ApiErrorCode =
  | 'INVALID_ISBN'
  | 'INVALID_QUERY'
  | 'PROVIDER_TIMEOUT'
  | 'PROVIDER_ERROR'
  | 'NOT_FOUND'
  | 'RATE_LIMIT_EXCEEDED'
  | 'INTERNAL_ERROR';
