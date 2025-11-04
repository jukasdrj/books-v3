/**
 * Normalizes book title for cache key generation and search matching
 * - Lowercase for case-insensitive matching
 * - Trim whitespace
 * - Remove leading articles (the, a, an) for better deduplication
 * - Remove punctuation for fuzzy matching
 */
export function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .trim()
    .replace(/^(the|a|an)\s+/, '')    // "The Hobbit" → "hobbit"
    .replace(/[^a-z0-9\s]/g, '');     // Remove punctuation
}

/**
 * Normalizes ISBN for cache key generation
 * - Remove hyphens (ISBN-10/ISBN-13 formatting)
 * - Trim whitespace
 * - Preserve digits and 'X' only (ISBN-10 check digit)
 */
export function normalizeISBN(isbn: string): string {
  return isbn.trim().replace(/[^0-9X]/gi, '');
}

/**
 * Normalizes author name for cache matching
 * - Lowercase
 * - Trim whitespace
 */
export function normalizeAuthor(author: string): string {
  return author.toLowerCase().trim();
}

/**
 * Normalizes image URL for cache key generation
 * - Remove query parameters (tracking, sizing hints)
 * - Normalize protocol (http → https)
 * - Trim whitespace
 */
export function normalizeImageURL(url: string): string {
  try {
    const parsed = new URL(url.trim());
    // Remove query params (e.g., ?zoom=1, ?source=gbs_api)
    parsed.search = '';
    // Force HTTPS
    parsed.protocol = 'https:';
    return parsed.toString();
  } catch {
    // Invalid URL, return as-is
    return url.trim();
  }
}
