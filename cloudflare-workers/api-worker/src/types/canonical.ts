/**
 * Canonical Data Transfer Objects
 *
 * Single source of truth for all API responses.
 * iOS Swift Codable structs mirror these interfaces exactly.
 *
 * Design doc: docs/plans/2025-10-29-canonical-data-contracts-design.md
 */

import type {
  EditionFormat,
  AuthorGender,
  CulturalRegion,
  ReviewStatus,
  DataProvider,
} from './enums.js';

// ============================================================================
// CORE ENTITIES
// ============================================================================

/**
 * Work - Abstract representation of a creative work
 * Corresponds to SwiftData Work model
 */
export interface WorkDTO {
  // Required fields
  title: string;
  subjectTags: string[]; // Normalized genres

  // Optional metadata
  originalLanguage?: string;
  firstPublicationYear?: number;
  description?: string;

  // Provenance
  synthetic?: boolean; // True if Work was inferred from Edition data
  primaryProvider?: DataProvider;
  contributors?: DataProvider[];

  // External IDs - Legacy (single values)
  openLibraryID?: string;
  openLibraryWorkID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;
  goodreadsID?: string;

  // External IDs - Modern (arrays)
  goodreadsWorkIDs: string[];
  amazonASINs: string[];
  librarythingIDs: string[];
  googleBooksVolumeIDs: string[];

  // Quality metrics
  lastISBNDBSync?: string; // ISO 8601 timestamp
  isbndbQuality: number; // 0-100

  // Review metadata (for AI-detected books)
  reviewStatus: ReviewStatus;
  originalImagePath?: string;
  boundingBox?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

/**
 * Edition - Physical/digital manifestation of a Work
 * Corresponds to SwiftData Edition model
 */
export interface EditionDTO {
  // Identifiers
  isbn?: string; // Primary ISBN
  isbns: string[]; // All ISBNs

  // Core metadata
  title?: string;
  publisher?: string;
  publicationDate?: string; // YYYY-MM-DD or YYYY
  pageCount?: number;
  format: EditionFormat;
  coverImageURL?: string;
  editionTitle?: string;
  editionDescription?: string; // Note: Can't use 'description' in Swift (@Model macro reserves it)
  language?: string;

  // Provenance
  primaryProvider?: DataProvider;
  contributors?: DataProvider[];

  // External IDs - Legacy
  openLibraryID?: string;
  openLibraryEditionID?: string;
  isbndbID?: string;
  googleBooksVolumeID?: string;
  goodreadsID?: string;

  // External IDs - Modern
  amazonASINs: string[];
  googleBooksVolumeIDs: string[];
  librarythingIDs: string[];

  // Quality metrics
  lastISBNDBSync?: string;
  isbndbQuality: number;
}

/**
 * Author - Creator of works
 * Corresponds to SwiftData Author model
 */
export interface AuthorDTO {
  // Required
  name: string;
  gender: AuthorGender;

  // Optional
  culturalRegion?: CulturalRegion;
  nationality?: string;
  birthYear?: number;
  deathYear?: number;

  // External IDs
  openLibraryID?: string;
  isbndbID?: string;
  googleBooksID?: string;
  goodreadsID?: string;

  // Statistics
  bookCount?: number;
}
