import { describe, test, expect } from 'vitest';
import type { WorkDTO, EditionDTO, AuthorDTO } from '../src/types/canonical';

describe('Canonical DTO Schema Validation', () => {
  test('WorkDTO has all required fields', () => {
    const work: WorkDTO = {
      olid: 'OL123W',
      title: 'The Hobbit',
      authors: [],
      editions: [],
      subjects: [],
      coverImages: {
        small: null,
        medium: null,
        large: null
      },
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      synthetic: false
    };

    expect(work.olid).toBe('OL123W');
    expect(work.title).toBe('The Hobbit');
    expect(work.synthetic).toBe(false);
  });

  test('EditionDTO supports multiple ISBNs', () => {
    const edition: EditionDTO = {
      isbn13: ['9780547928227', '9780547928234'],
      isbn10: ['0547928220'],
      title: 'The Hobbit',
      publisher: 'Houghton Mifflin',
      publishDate: '2012',
      pageCount: 300,
      coverImages: {
        small: null,
        medium: null,
        large: null
      }
    };

    expect(edition.isbn13).toHaveLength(2);
    expect(edition.isbn10).toHaveLength(1);
    expect(edition.pageCount).toBe(300);
  });

  test('AuthorDTO with diversity metadata', () => {
    const author: AuthorDTO = {
      olid: 'OL26320A',
      name: 'J.R.R. Tolkien',
      culturalRegion: 'europe',
      authorGender: 'male',
      isMarginalizedVoice: false
    };

    expect(author.name).toBe('J.R.R. Tolkien');
    expect(author.culturalRegion).toBe('europe');
  });

  test('WorkDTO with null authors decodes correctly', () => {
    const work: WorkDTO = {
      olid: 'OL123W',
      title: 'Anonymous Work',
      authors: null,
      editions: [],
      subjects: [],
      coverImages: {
        small: null,
        medium: null,
        large: null
      },
      primaryProvider: 'google-books',
      contributors: ['google-books'],
      synthetic: false
    };

    expect(work.authors).toBeNull();
  });

  test('EditionDTO with missing ISBN fields', () => {
    const edition: EditionDTO = {
      title: 'Unknown Book',
      publisher: 'Unknown',
      publishDate: '2020',
      coverImages: {
        small: null,
        medium: null,
        large: null
      }
    };

    expect(edition.isbn13).toBeUndefined();
    expect(edition.isbn10).toBeUndefined();
    expect(edition.title).toBe('Unknown Book');
  });
});
