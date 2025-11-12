import { describe, it, expect } from 'vitest';
import { normalizeGoogleBooksToWork, normalizeGoogleBooksToEdition, ensureWorkForEdition } from '../../src/services/normalizers/google-books.js';

describe('normalizeGoogleBooksToWork', () => {
  it('should convert Google Books item to WorkDTO', () => {
    const googleBooksItem = {
      id: 'beSP5CCpiGUC',
      volumeInfo: {
        title: '1984',
        authors: ['George Orwell'],
        publishedDate: '1949-06-08',
        categories: ['Fiction', 'Dystopian'],
        description: 'A dystopian novel...',
        industryIdentifiers: [
          { type: 'ISBN_13', identifier: '9780451524935' }
        ]
      }
    };

    const work = normalizeGoogleBooksToWork(googleBooksItem);

    expect(work.title).toBe('1984');
    expect(work.firstPublicationYear).toBe(1949);
    expect(work.subjectTags).toContain('Fiction');
    expect(work.subjectTags).toContain('Dystopian');
    expect(work.googleBooksVolumeIDs).toContain('beSP5CCpiGUC');
    expect(work.primaryProvider).toBe('google-books');
    expect(work.synthetic).toBe(false);
  });

  it('should handle missing optional fields', () => {
    const minimalItem = {
      id: 'xyz123',
      volumeInfo: {
        title: 'Unknown Book',
        authors: ['Unknown Author']
      }
    };

    const work = normalizeGoogleBooksToWork(minimalItem);

    expect(work.title).toBe('Unknown Book');
    expect(work.firstPublicationYear).toBeUndefined();
    expect(work.subjectTags).toEqual([]);
    expect(work.description).toBeUndefined();
  });
});

describe('normalizeGoogleBooksToEdition', () => {
  it('should convert Google Books item to EditionDTO', () => {
    const googleBooksItem = {
      id: 'beSP5CCpiGUC',
      volumeInfo: {
        title: '1984',
        publisher: 'Penguin',
        publishedDate: '2021-01-05',
        pageCount: 328,
        imageLinks: {
          thumbnail: 'http://books.google.com/covers/1984.jpg'
        },
        industryIdentifiers: [
          { type: 'ISBN_13', identifier: '9780451524935' },
          { type: 'ISBN_10', identifier: '0451524934' }
        ]
      }
    };

    const edition = normalizeGoogleBooksToEdition(googleBooksItem);

    expect(edition.isbn).toBe('9780451524935'); // ISBN-13 preferred
    expect(edition.isbns).toContain('9780451524935');
    expect(edition.isbns).toContain('0451524934');
    expect(edition.publisher).toBe('Penguin');
    expect(edition.publicationDate).toBe('2021-01-05');
    expect(edition.pageCount).toBe(328);
    expect(edition.format).toBe('Hardcover'); // default
    expect(edition.coverImageURL).toBe('https://books.google.com/covers/1984.jpg');
    expect(edition.primaryProvider).toBe('google-books');
  });
});

describe('ensureWorkForEdition', () => {
  it('should synthesize Work from Edition when Work is missing', () => {
    const edition: any = {
      isbn: '9780451524935',
      isbns: ['9780451524935'],
      title: '1984',
      publisher: 'Penguin',
      publicationDate: '2021',
      format: 'Hardcover',
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      amazonASINs: [],
      googleBooksVolumeIDs: ['abc123'],
      librarythingIDs: [],
      isbndbQuality: 0,
    };

    const work = ensureWorkForEdition(edition);

    expect(work.title).toBe('1984');
    expect(work.firstPublicationYear).toBe(2021);
    expect(work.synthetic).toBe(true); // KEY: marks as inferred
    expect(work.primaryProvider).toBe('google-books');
    expect(work.googleBooksVolumeIDs).toContain('abc123');
  });

  it('should handle edition without title', () => {
    const edition: any = {
      isbn: '1234567890',
      isbns: ['1234567890'],
      format: 'Paperback',
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      amazonASINs: [],
      googleBooksVolumeIDs: [],
      librarythingIDs: [],
      isbndbQuality: 0,
    };

    const work = ensureWorkForEdition(edition);

    expect(work.title).toBe('Unknown');
    expect(work.synthetic).toBe(true);
  });

  it('should copy coverImageURL from Edition to Work (Issue #346)', () => {
    const edition: any = {
      isbn: '9780451524935',
      isbns: ['9780451524935'],
      title: '1984',
      publisher: 'Penguin',
      publicationDate: '2021',
      format: 'Hardcover',
      coverImageURL: 'https://books.google.com/covers/1984.jpg',
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      amazonASINs: [],
      googleBooksVolumeIDs: ['abc123'],
      librarythingIDs: [],
      isbndbQuality: 0,
    };

    const work = ensureWorkForEdition(edition);

    expect(work.coverImageURL).toBe('https://books.google.com/covers/1984.jpg');
    expect(work.synthetic).toBe(true);
  });
});
