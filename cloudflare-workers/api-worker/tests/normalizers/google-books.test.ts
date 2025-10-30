import { describe, it, expect } from 'vitest';
import { normalizeGoogleBooksToWork } from '../../src/services/normalizers/google-books.js';

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
    expect(work.subjectTags).toEqual(['Fiction', 'Dystopian']);
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
