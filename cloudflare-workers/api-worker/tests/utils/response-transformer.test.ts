/**
 * Unit tests for ResponseTransformer utilities
 *
 * Tests extraction of unique authors and removal of authors property from works.
 */

import { describe, it, expect } from 'vitest';
import { extractUniqueAuthors, removeAuthorsFromWorks, type WorkDTOWithAuthors } from '../../src/utils/response-transformer.js';
import type { AuthorDTO, WorkDTO } from '../../src/types/canonical.js';

describe('ResponseTransformer', () => {
  describe('extractUniqueAuthors', () => {
    it('should extract unique authors from works', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' },
            { name: 'Bob', gender: 'male' }
          ]
        },
        {
          title: 'Book 2',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' }, // Duplicate
            { name: 'Charlie', gender: 'male' }
          ]
        }
      ];

      const authors = extractUniqueAuthors(works);

      expect(authors).toHaveLength(3);
      expect(authors.map(a => a.name)).toEqual(['Alice', 'Bob', 'Charlie']);
    });

    it('should handle works with no authors', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: []
        }
      ];

      const authors = extractUniqueAuthors(works);

      expect(authors).toHaveLength(0);
    });

    it('should handle works with missing authors property', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified'
          // No authors property
        }
      ];

      const authors = extractUniqueAuthors(works);

      expect(authors).toHaveLength(0);
    });

    it('should handle empty works array', () => {
      const works: WorkDTOWithAuthors[] = [];

      const authors = extractUniqueAuthors(works);

      expect(authors).toHaveLength(0);
    });

    it('should preserve author metadata', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            {
              name: 'Alice',
              gender: 'female',
              culturalRegion: 'northAmerica',
              birthYear: 1990,
              deathYear: undefined,
              bookCount: 5
            }
          ]
        }
      ];

      const authors = extractUniqueAuthors(works);

      expect(authors).toHaveLength(1);
      expect(authors[0]).toEqual({
        name: 'Alice',
        gender: 'female',
        culturalRegion: 'northAmerica',
        birthYear: 1990,
        deathYear: undefined,
        bookCount: 5
      });
    });
  });

  describe('removeAuthorsFromWorks', () => {
    it('should remove authors property from works', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: ['Fiction'],
          googleBooksVolumeIDs: ['vol1'],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' }
          ]
        }
      ];

      const cleanWorks = removeAuthorsFromWorks(works);

      expect(cleanWorks).toHaveLength(1);
      expect(cleanWorks[0]).toEqual({
        title: 'Book 1',
        subjectTags: ['Fiction'],
        googleBooksVolumeIDs: ['vol1'],
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        isbndbQuality: 0,
        reviewStatus: 'verified'
      });
      expect(cleanWorks[0]).not.toHaveProperty('authors');
    });

    it('should preserve all other WorkDTO properties', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'The Great Gatsby',
          subjectTags: ['Fiction', 'Classic Literature'],
          originalLanguage: 'en',
          firstPublicationYear: 1925,
          description: 'A classic novel',
          coverImageURL: 'https://example.com/cover.jpg',
          synthetic: false,
          primaryProvider: 'google-books',
          contributors: ['google-books'],
          googleBooksVolumeIDs: ['vol123'],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 85,
          reviewStatus: 'verified',
          authors: [
            { name: 'F. Scott Fitzgerald', gender: 'male' }
          ]
        }
      ];

      const cleanWorks = removeAuthorsFromWorks(works);

      expect(cleanWorks[0]).toEqual({
        title: 'The Great Gatsby',
        subjectTags: ['Fiction', 'Classic Literature'],
        originalLanguage: 'en',
        firstPublicationYear: 1925,
        description: 'A classic novel',
        coverImageURL: 'https://example.com/cover.jpg',
        synthetic: false,
        primaryProvider: 'google-books',
        contributors: ['google-books'],
        googleBooksVolumeIDs: ['vol123'],
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        isbndbQuality: 85,
        reviewStatus: 'verified'
      });
    });

    it('should handle works without authors property', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified'
          // No authors property
        }
      ];

      const cleanWorks = removeAuthorsFromWorks(works);

      expect(cleanWorks).toHaveLength(1);
      expect(cleanWorks[0]).not.toHaveProperty('authors');
    });

    it('should handle empty works array', () => {
      const works: WorkDTOWithAuthors[] = [];

      const cleanWorks = removeAuthorsFromWorks(works);

      expect(cleanWorks).toHaveLength(0);
    });

    it('should not mutate original works array', () => {
      const works: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: [],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' }
          ]
        }
      ];

      const cleanWorks = removeAuthorsFromWorks(works);

      // Original works should still have authors property
      expect(works[0]).toHaveProperty('authors');
      expect(works[0].authors).toHaveLength(1);

      // Clean works should not have authors property
      expect(cleanWorks[0]).not.toHaveProperty('authors');
    });
  });

  describe('Integration: extractUniqueAuthors + removeAuthorsFromWorks', () => {
    it('should work together to transform v1 search response', () => {
      // Simulate enrichMultipleBooks result
      const enrichedWorks: WorkDTOWithAuthors[] = [
        {
          title: 'Book 1',
          subjectTags: ['Fiction'],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' },
            { name: 'Bob', gender: 'male' }
          ]
        },
        {
          title: 'Book 2',
          subjectTags: ['Non-Fiction'],
          googleBooksVolumeIDs: [],
          goodreadsWorkIDs: [],
          amazonASINs: [],
          librarythingIDs: [],
          isbndbQuality: 0,
          reviewStatus: 'verified',
          authors: [
            { name: 'Alice', gender: 'female' } // Duplicate
          ]
        }
      ];

      // Transform for v1 response
      const authors = extractUniqueAuthors(enrichedWorks);
      const cleanWorks = removeAuthorsFromWorks(enrichedWorks);

      // Verify v1 response structure
      expect(authors).toHaveLength(2);
      expect(authors.map(a => a.name)).toEqual(['Alice', 'Bob']);

      expect(cleanWorks).toHaveLength(2);
      expect(cleanWorks[0]).not.toHaveProperty('authors');
      expect(cleanWorks[1]).not.toHaveProperty('authors');
      expect(cleanWorks[0].title).toBe('Book 1');
      expect(cleanWorks[1].title).toBe('Book 2');
    });
  });
});
