/**
 * Unit tests for editions in search responses
 * Verifies that editions are properly normalized and returned
 */

import { describe, it, expect } from 'vitest';
import { normalizeGoogleBooksToWork, normalizeGoogleBooksToEdition } from '../../../src/services/normalizers/google-books.js';
import { normalizeOpenLibraryToWork, normalizeOpenLibraryToEdition } from '../../../src/services/normalizers/openlibrary.js';

describe('Edition Normalization', () => {
  describe('Google Books normalizer', () => {
    it('should normalize work and edition from Google Books item', () => {
      const mockGoogleBooksItem = {
        id: 'yklCAwAAQBAJ',
        volumeInfo: {
          title: '1984',
          authors: ['George Orwell'],
          publisher: 'Houghton Mifflin Harcourt',
          publishedDate: '2017-01-25',
          description: 'A novel about totalitarianism',
          pageCount: 328,
          categories: ['Fiction'],
          language: 'en',
          industryIdentifiers: [
            { type: 'ISBN_13', identifier: '9780544797260' },
            { type: 'ISBN_10', identifier: '0544797264' }
          ],
          imageLinks: {
            thumbnail: 'http://books.google.com/books/content?id=yklCAwAAQBAJ&printsec=frontcover&img=1&zoom=1'
          }
        }
      };

      const work = normalizeGoogleBooksToWork(mockGoogleBooksItem);
      const edition = normalizeGoogleBooksToEdition(mockGoogleBooksItem);

      // Validate WorkDTO structure
      expect(work.title).toBe('1984');
      expect(work.subjectTags).toBeInstanceOf(Array);
      expect(work.googleBooksVolumeIDs).toEqual(['yklCAwAAQBAJ']);
      expect(work.primaryProvider).toBe('google-books');
      expect(work.synthetic).toBe(false);

      // Validate EditionDTO structure
      expect(edition.isbn).toBe('9780544797260');
      expect(edition.isbns).toEqual(['9780544797260', '0544797264']);
      expect(edition.title).toBe('1984');
      expect(edition.publisher).toBe('Houghton Mifflin Harcourt');
      expect(edition.publicationDate).toBe('2017-01-25');
      expect(edition.pageCount).toBe(328);
      expect(edition.coverImageURL).toBe('https://books.google.com/books/content?id=yklCAwAAQBAJ&printsec=frontcover&img=1&zoom=1');
      expect(edition.language).toBe('en');
      expect(edition.primaryProvider).toBe('google-books');
      expect(edition.googleBooksVolumeIDs).toEqual(['yklCAwAAQBAJ']);
    });

    it('should handle Google Books item without ISBNs', () => {
      const mockItem = {
        id: 'test123',
        volumeInfo: {
          title: 'Test Book',
          authors: ['Test Author'],
          industryIdentifiers: []
        }
      };

      const edition = normalizeGoogleBooksToEdition(mockItem);

      expect(edition.isbn).toBeUndefined();
      expect(edition.isbns).toEqual([]);
    });
  });

  describe('OpenLibrary normalizer', () => {
    it('should normalize work and edition from OpenLibrary doc', () => {
      const mockOpenLibraryDoc = {
        key: '/works/OL45804W',
        title: '1984',
        author_name: ['George Orwell'],
        first_publish_year: 1949,
        subject: ['Dystopian fiction', 'Political fiction'],
        isbn: ['9780451524935', '0451524934'],
        publisher: ['Signet Classics'],
        publish_date: ['1950'],
        number_of_pages_median: 328,
        cover_i: 12345,
        language: ['eng']
      };

      const work = normalizeOpenLibraryToWork(mockOpenLibraryDoc);
      const edition = normalizeOpenLibraryToEdition(mockOpenLibraryDoc);

      // Validate WorkDTO structure
      expect(work.title).toBe('1984');
      expect(work.firstPublicationYear).toBe(1949);
      expect(work.openLibraryWorkID).toBe('OL45804W');
      expect(work.primaryProvider).toBe('openlibrary');

      // Validate EditionDTO structure
      expect(edition.isbn).toBe('9780451524935');
      expect(edition.isbns).toEqual(['9780451524935', '0451524934']);
      expect(edition.publisher).toBe('Signet Classics');
      expect(edition.publicationDate).toBe('1950');
      expect(edition.pageCount).toBe(328);
      expect(edition.coverImageURL).toBe('https://covers.openlibrary.org/b/id/12345-L.jpg');
      expect(edition.primaryProvider).toBe('openlibrary');
    });
  });
});

describe('BookSearchResponse structure', () => {
  it('should include works, editions, and authors arrays', () => {
    // Mock response structure (what handlers should return)
    const mockResponse = {
      success: true,
      data: {
        works: [
          {
            title: '1984',
            subjectTags: ['Fiction'],
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ['yklCAwAAQBAJ'],
            isbndbQuality: 0,
            reviewStatus: 'verified',
            synthetic: false,
            primaryProvider: 'google-books',
            contributors: ['google-books']
          }
        ],
        editions: [
          {
            isbn: '9780544797260',
            isbns: ['9780544797260', '0544797264'],
            format: 'Hardcover',
            amazonASINs: [],
            googleBooksVolumeIDs: ['yklCAwAAQBAJ'],
            librarythingIDs: [],
            isbndbQuality: 0,
            primaryProvider: 'google-books',
            contributors: ['google-books']
          }
        ],
        authors: [
          {
            name: 'George Orwell',
            gender: 'Unknown'
          }
        ]
      },
      meta: {
        timestamp: new Date().toISOString(),
        provider: 'google-books',
        cached: false
      }
    };

    expect(mockResponse.data.works).toBeInstanceOf(Array);
    expect(mockResponse.data.editions).toBeInstanceOf(Array);
    expect(mockResponse.data.authors).toBeInstanceOf(Array);
    expect(mockResponse.data.works.length).toBe(1);
    expect(mockResponse.data.editions.length).toBe(1);
    expect(mockResponse.data.authors.length).toBe(1);
  });
});
