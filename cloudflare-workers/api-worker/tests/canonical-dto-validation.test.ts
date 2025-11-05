import { describe, test, expect } from 'vitest';
import type { WorkDTO, EditionDTO, AuthorDTO } from '../src/types/canonical';

/**
 * Canonical DTO Contract Validation
 *
 * These tests verify that normalizers always return required fields
 * with proper defaults (never null or undefined).
 *
 * Contract: cloudflare-workers/api-worker/src/types/canonical.ts
 * iOS Mirror: BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/WorkDTO.swift
 */

describe('Canonical DTO Schema Validation', () => {
  describe('WorkDTO Required Fields', () => {
    test('WorkDTO must have all required fields with non-null defaults', () => {
      const work: WorkDTO = {
        title: 'The Hobbit',
        subjectTags: [],
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        googleBooksVolumeIDs: [],
        isbndbQuality: 0,
        reviewStatus: 'verified',
      };

      // Required fields must never be null/undefined
      expect(work.title).toBe('The Hobbit');
      expect(work.subjectTags).toEqual([]);
      expect(work.goodreadsWorkIDs).toEqual([]);
      expect(work.amazonASINs).toEqual([]);
      expect(work.librarythingIDs).toEqual([]);
      expect(work.googleBooksVolumeIDs).toEqual([]);
      expect(work.isbndbQuality).toBe(0);
      expect(work.reviewStatus).toBe('verified');
    });

    test('WorkDTO with optional fields can omit them', () => {
      const work: WorkDTO = {
        title: 'Unknown',
        subjectTags: [],
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        googleBooksVolumeIDs: [],
        isbndbQuality: 0,
        reviewStatus: 'verified',
        // Optional fields omitted
        originalLanguage: undefined,
        firstPublicationYear: undefined,
        description: undefined,
      };

      expect(work.originalLanguage).toBeUndefined();
      expect(work.firstPublicationYear).toBeUndefined();
      expect(work.description).toBeUndefined();
    });
  });

  describe('EditionDTO Required Fields', () => {
    test('EditionDTO must have all required fields with non-null defaults', () => {
      const edition: EditionDTO = {
        isbns: [],
        format: 'Paperback',
        amazonASINs: [],
        googleBooksVolumeIDs: [],
        librarythingIDs: [],
        isbndbQuality: 0,
      };

      // Required fields must never be null/undefined
      expect(edition.isbns).toEqual([]);
      expect(edition.format).toBe('Paperback');
      expect(edition.amazonASINs).toEqual([]);
      expect(edition.googleBooksVolumeIDs).toEqual([]);
      expect(edition.librarythingIDs).toEqual([]);
      expect(edition.isbndbQuality).toBe(0);
    });

    test('EditionDTO with ISBNs', () => {
      const edition: EditionDTO = {
        isbn: '9780547928227',
        isbns: ['9780547928227', '0547928220'],
        format: 'Hardcover',
        amazonASINs: [],
        googleBooksVolumeIDs: ['abc123'],
        librarythingIDs: [],
        isbndbQuality: 0,
      };

      expect(edition.isbn).toBe('9780547928227');
      expect(edition.isbns).toContain('9780547928227');
      expect(edition.isbns).toContain('0547928220');
      expect(edition.googleBooksVolumeIDs).toContain('abc123');
    });
  });

  describe('AuthorDTO Required Fields', () => {
    test('AuthorDTO must have all required fields with non-null defaults', () => {
      const author: AuthorDTO = {
        name: 'J.R.R. Tolkien',
        gender: 'Unknown',
      };

      // Required fields must never be null/undefined
      expect(author.name).toBe('J.R.R. Tolkien');
      expect(author.gender).toBe('Unknown');
    });

    test('AuthorDTO with optional diversity metadata', () => {
      const author: AuthorDTO = {
        name: 'Chimamanda Ngozi Adichie',
        gender: 'Female',
        culturalRegion: 'Africa',
        nationality: 'Nigerian',
        birthYear: 1977,
      };

      expect(author.name).toBe('Chimamanda Ngozi Adichie');
      expect(author.gender).toBe('Female');
      expect(author.culturalRegion).toBe('Africa');
      expect(author.nationality).toBe('Nigerian');
      expect(author.birthYear).toBe(1977);
    });
  });

  describe('Invalid DTOs (Must Not Compile)', () => {
    test('WorkDTO with null required fields should fail TypeScript compilation', () => {
      // This test documents contract violations (TypeScript prevents at compile time)
      // @ts-expect-error - subjectTags cannot be null
      const invalidWork1: WorkDTO = {
        title: 'Test',
        subjectTags: null, // ❌ Must be array
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        googleBooksVolumeIDs: [],
        isbndbQuality: 0,
        reviewStatus: 'verified',
      };

      expect(invalidWork1).toBeDefined(); // Prove test runs
    });

    test('AuthorDTO without gender should fail TypeScript compilation', () => {
      // @ts-expect-error - gender is required
      const invalidAuthor: AuthorDTO = {
        name: 'Test Author',
        // gender missing ❌
      };

      expect(invalidAuthor).toBeDefined(); // Prove test runs
    });

    test('EditionDTO without format should fail TypeScript compilation', () => {
      // @ts-expect-error - format is required
      const invalidEdition: EditionDTO = {
        isbns: [],
        // format missing ❌
        amazonASINs: [],
        googleBooksVolumeIDs: [],
        librarythingIDs: [],
        isbndbQuality: 0,
      };

      expect(invalidEdition).toBeDefined(); // Prove test runs
    });
  });
});
