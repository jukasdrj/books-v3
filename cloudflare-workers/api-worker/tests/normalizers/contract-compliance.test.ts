import { describe, it, expect } from 'vitest';
import { normalizeGoogleBooksToWork, normalizeGoogleBooksToEdition } from '../../src/services/normalizers/google-books.js';
import { normalizeOpenLibraryToWork, normalizeOpenLibraryToAuthor } from '../../src/services/normalizers/openlibrary.js';

/**
 * Normalizer Contract Compliance Tests
 *
 * Validates that all normalizers always return DTOs with required fields
 * populated (never null or undefined).
 *
 * This prevents iOS Codable decoding failures.
 */

describe('Google Books Normalizer Contract Compliance', () => {
  it('normalizeGoogleBooksToWork always returns required array fields', () => {
    const minimalItem = {
      id: 'test-id',
      volumeInfo: {
        title: 'Test Book'
      }
    };

    const work = normalizeGoogleBooksToWork(minimalItem);

    // Required array fields must NEVER be null
    expect(work.subjectTags).toBeInstanceOf(Array);
    expect(work.goodreadsWorkIDs).toBeInstanceOf(Array);
    expect(work.amazonASINs).toBeInstanceOf(Array);
    expect(work.librarythingIDs).toBeInstanceOf(Array);
    expect(work.googleBooksVolumeIDs).toBeInstanceOf(Array);
    
    // Required scalar fields must NEVER be null
    expect(work.isbndbQuality).toBe(0);
    expect(work.reviewStatus).toBe('verified');
    
    // Should include the Google Books ID
    expect(work.googleBooksVolumeIDs).toContain('test-id');
  });

  it('normalizeGoogleBooksToEdition always returns required fields', () => {
    const minimalItem = {
      id: 'test-id',
      volumeInfo: {
        title: 'Test Book'
      }
    };

    const edition = normalizeGoogleBooksToEdition(minimalItem);

    // Required array fields must NEVER be null
    expect(edition.isbns).toBeInstanceOf(Array);
    expect(edition.amazonASINs).toBeInstanceOf(Array);
    expect(edition.googleBooksVolumeIDs).toBeInstanceOf(Array);
    expect(edition.librarythingIDs).toBeInstanceOf(Array);
    
    // Required scalar fields must NEVER be null
    expect(edition.format).toBe('Hardcover');
    expect(edition.isbndbQuality).toBe(0);
    
    // Should include the Google Books ID
    expect(edition.googleBooksVolumeIDs).toContain('test-id');
  });
});

describe('OpenLibrary Normalizer Contract Compliance', () => {
  it('normalizeOpenLibraryToWork always returns required array fields', () => {
    const minimalDoc = {
      title: 'Test Book'
    };

    const work = normalizeOpenLibraryToWork(minimalDoc);

    // Required array fields must NEVER be null
    expect(work.subjectTags).toBeInstanceOf(Array);
    expect(work.goodreadsWorkIDs).toBeInstanceOf(Array);
    expect(work.amazonASINs).toBeInstanceOf(Array);
    expect(work.librarythingIDs).toBeInstanceOf(Array);
    expect(work.googleBooksVolumeIDs).toBeInstanceOf(Array);
    
    // Required scalar fields must NEVER be null
    expect(work.isbndbQuality).toBe(0);
    expect(work.reviewStatus).toBe('verified');
  });

  it('normalizeOpenLibraryToWork handles external IDs correctly', () => {
    const docWithIds = {
      title: 'Test Book',
      key: '/works/OL123W',
      id_goodreads: ['12345'],
      id_amazon: ['B001234'],
      id_librarything: ['456789'],
      id_google: ['google-123']
    };

    const work = normalizeOpenLibraryToWork(docWithIds);

    // External IDs should be populated from source data
    expect(work.openLibraryWorkID).toBe('OL123W');
    expect(work.goodreadsWorkIDs).toContain('12345');
    expect(work.amazonASINs).toContain('B001234');
    expect(work.librarythingIDs).toContain('456789');
    expect(work.googleBooksVolumeIDs).toContain('google-123');
  });

  it('normalizeOpenLibraryToAuthor always includes gender field', () => {
    const author = normalizeOpenLibraryToAuthor('Test Author');

    // Required field must NEVER be null or undefined
    expect(author.name).toBe('Test Author');
    expect(author.gender).toBe('Unknown');
  });
});

describe('Edge Cases - Empty/Invalid Data', () => {
  it('handles Google Books item with no categories', () => {
    const item = {
      id: 'test-id',
      volumeInfo: {
        title: 'Book Without Genres'
        // categories: undefined
      }
    };

    const work = normalizeGoogleBooksToWork(item);

    // Should default to empty array, NOT null
    expect(work.subjectTags).toEqual([]);
  });

  it('handles Google Books item with no ISBNs', () => {
    const item = {
      id: 'test-id',
      volumeInfo: {
        title: 'Book Without ISBN'
        // industryIdentifiers: undefined
      }
    };

    const edition = normalizeGoogleBooksToEdition(item);

    // Should default to empty array, NOT null
    expect(edition.isbns).toEqual([]);
    expect(edition.isbn).toBeUndefined(); // Primary ISBN can be undefined
  });

  it('handles OpenLibrary doc with no external IDs', () => {
    const doc = {
      title: 'Book Without External IDs'
      // No id_goodreads, id_amazon, etc.
    };

    const work = normalizeOpenLibraryToWork(doc);

    // All array fields should default to empty arrays
    expect(work.goodreadsWorkIDs).toEqual([]);
    expect(work.amazonASINs).toEqual([]);
    expect(work.librarythingIDs).toEqual([]);
    expect(work.googleBooksVolumeIDs).toEqual([]);
  });
});

describe('Contract Violation Prevention', () => {
  it('never returns null for required array fields', () => {
    const googleWork = normalizeGoogleBooksToWork({ id: 'test', volumeInfo: { title: 'Test' } });
    const googleEdition = normalizeGoogleBooksToEdition({ id: 'test', volumeInfo: { title: 'Test' } });
    const openLibWork = normalizeOpenLibraryToWork({ title: 'Test' });
    const author = normalizeOpenLibraryToAuthor('Test');

    // Validate WorkDTOs
    [googleWork, openLibWork].forEach(work => {
      expect(work.subjectTags).not.toBeNull();
      expect(work.subjectTags).not.toBeUndefined();
      expect(work.goodreadsWorkIDs).not.toBeNull();
      expect(work.amazonASINs).not.toBeNull();
      expect(work.librarythingIDs).not.toBeNull();
      expect(work.googleBooksVolumeIDs).not.toBeNull();
    });

    // Validate EditionDTO
    expect(googleEdition.isbns).not.toBeNull();
    expect(googleEdition.amazonASINs).not.toBeNull();
    expect(googleEdition.googleBooksVolumeIDs).not.toBeNull();
    expect(googleEdition.librarythingIDs).not.toBeNull();

    // Validate AuthorDTO
    expect(author.gender).not.toBeNull();
    expect(author.gender).not.toBeUndefined();
  });

  it('never returns null for required scalar fields', () => {
    const googleWork = normalizeGoogleBooksToWork({ id: 'test', volumeInfo: { title: 'Test' } });
    const googleEdition = normalizeGoogleBooksToEdition({ id: 'test', volumeInfo: { title: 'Test' } });
    const openLibWork = normalizeOpenLibraryToWork({ title: 'Test' });

    // Validate WorkDTOs
    [googleWork, openLibWork].forEach(work => {
      expect(work.isbndbQuality).not.toBeNull();
      expect(work.isbndbQuality).not.toBeUndefined();
      expect(work.reviewStatus).not.toBeNull();
      expect(work.reviewStatus).not.toBeUndefined();
    });

    // Validate EditionDTO
    expect(googleEdition.format).not.toBeNull();
    expect(googleEdition.format).not.toBeUndefined();
    expect(googleEdition.isbndbQuality).not.toBeNull();
  });
});
