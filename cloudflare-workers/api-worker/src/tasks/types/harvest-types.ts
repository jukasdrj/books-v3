/**
 * Book entry from CSV file
 */
export interface BookEntry {
  title: string;
  author: string;
  isbn: string; // ISBN-13 format
}

/**
 * Cover image data from provider
 */
export interface CoverData {
  url: string;
  source: 'isbndb' | 'google-books';
  isbn: string;
}

/**
 * KV metadata for harvested cover
 */
export interface CoverMetadata {
  isbn: string;
  source: 'isbndb' | 'google-books';
  r2Key: string;
  harvestedAt: string; // ISO 8601
  fallback: boolean;
  originalUrl: string;
}

/**
 * Result of harvesting a single book
 */
export interface HarvestResult {
  isbn: string;
  title: string;
  author: string;
  success: boolean;
  source?: 'isbndb' | 'google-books';
  error?: string;
}

/**
 * Final harvest report
 */
export interface HarvestReport {
  totalBooks: number;
  successCount: number;
  isbndbCount: number;
  googleBooksCount: number;
  failureCount: number;
  executionTimeMs: number;
  failures: Array<{
    isbn: string;
    title: string;
    author: string;
    error?: string;
  }>;
}

/**
 * Cloudflare Worker environment bindings
 */
export interface Env {
  LIBRARY_DATA: R2Bucket;
  KV_CACHE: KVNamespace;
  ISBNDB_API_KEY: string;
  GOOGLE_BOOKS_API_KEY?: string;
}
