/**
 * Response Transformer Utilities
 *
 * Shared utilities for transforming API responses in v1 search handlers.
 * Eliminates code duplication across search-title, search-isbn, and search-advanced.
 *
 * Design: Extracted from v1 handlers as part of Phase 1 refactoring (Canonical API Contract Implementation)
 * Refactoring Plan: Backend Handler Deduplication - eliminates 39 lines of duplicated code
 */

import type { WorkDTO, AuthorDTO } from '../types/canonical.js';

/**
 * Extended WorkDTO with authors property
 * external-apis.js returns works with authors array, but canonical WorkDTO doesn't include it
 */
export type WorkDTOWithAuthors = WorkDTO & { authors?: AuthorDTO[] };

/**
 * Extract unique authors from works
 *
 * Deduplicates authors by name across all works in the response.
 * Used by v1 search endpoints to build the top-level authors array.
 *
 * **Deduplication Strategy:** Authors are deduplicated by name only (case-sensitive).
 * If two authors share the same name (e.g., different "John Smith" authors),
 * the first occurrence is kept. This is acceptable for search results where
 * exact author disambiguation is not critical.
 *
 * @param works - Array of works (potentially with embedded authors)
 * @returns Array of unique AuthorDTOs
 *
 * @example
 * const works = [
 *   { title: "Book 1", authors: [{ name: "Alice", gender: "female" }] },
 *   { title: "Book 2", authors: [{ name: "Alice", gender: "female" }, { name: "Bob", gender: "male" }] }
 * ];
 * const authors = extractUniqueAuthors(works);
 * // Returns: [{ name: "Alice", ... }, { name: "Bob", ... }]
 */
export function extractUniqueAuthors(works: WorkDTOWithAuthors[]): AuthorDTO[] {
  const authorsMap = new Map<string, AuthorDTO>();

  works.forEach(work => {
    (work.authors || []).forEach((author: AuthorDTO) => {
      if (!authorsMap.has(author.name)) {
        authorsMap.set(author.name, author);
      }
    });
  });

  return Array.from(authorsMap.values());
}

/**
 * Remove authors property from works
 *
 * Canonical WorkDTO doesn't include authors property (authors are returned separately).
 * This function strips the authors property from enriched works before returning to iOS.
 *
 * @param works - Array of works with embedded authors
 * @returns Array of clean WorkDTOs (without authors property)
 *
 * @example
 * const enrichedWorks = [
 *   { title: "Book 1", authors: [...], subjectTags: [...] }
 * ];
 * const cleanWorks = removeAuthorsFromWorks(enrichedWorks);
 * // Returns: [{ title: "Book 1", subjectTags: [...] }]
 */
export function removeAuthorsFromWorks(works: WorkDTOWithAuthors[]): WorkDTO[] {
  return works.map(work => {
    const { authors: _, ...cleanWork } = work;
    return cleanWork;
  });
}
