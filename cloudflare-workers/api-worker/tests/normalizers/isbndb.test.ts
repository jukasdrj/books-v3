import { describe, it, expect } from 'vitest';
import { normalizeISBNdbToWork, normalizeISBNdbToEdition, normalizeISBNdbToAuthor } from '../../src/services/normalizers/isbndb.js';

describe('normalizeISBNdbToWork', () => {
  it('should convert ISBNdb book to WorkDTO', () => {
    const isbndbBook = {
      isbn13: '9780451524935',
      isbn: '0451524934',
      title: '1984',
      title_long: '1984: A Novel',
      authors: ['George Orwell'],
      publisher: 'Penguin Books',
      language: 'en',
      date_published: '1949-06-08',
      subjects: ['Fiction', 'Dystopian', 'Political'],
      synopsis: 'A dystopian social science fiction novel...',
      image: 'https://images.isbndb.com/covers/49/35/9780451524935.jpg',
      pages: 328,
      binding: 'Paperback'
    };

    const work = normalizeISBNdbToWork(isbndbBook);

    expect(work.title).toBe('1984');
    expect(work.firstPublicationYear).toBe(1949);
    expect(work.subjectTags).toBeDefined();
    expect(work.description).toBe('A dystopian social science fiction novel...');
    expect(work.isbndbID).toBe('9780451524935');
    expect(work.primaryProvider).toBe('isbndb');
    expect(work.synthetic).toBe(false);
    expect(work.isbndbQuality).toBeGreaterThan(0);
  });

  it('should handle missing optional fields', () => {
    const minimalBook = {
      isbn13: '9781234567890',
      title: 'Unknown Book',
      authors: ['Unknown Author']
    };

    const work = normalizeISBNdbToWork(minimalBook);

    expect(work.title).toBe('Unknown Book');
    expect(work.firstPublicationYear).toBeUndefined();
    expect(work.subjectTags).toEqual([]);
    expect(work.description).toBeUndefined();
    expect(work.isbndbID).toBe('9781234567890');
  });

  it('should calculate quality score correctly', () => {
    const highQualityBook = {
      isbn13: '9780451524935',
      title: '1984',
      authors: ['George Orwell'],
      publisher: 'Penguin Books',
      date_published: '2020',
      subjects: ['Fiction', 'Dystopian'],
      synopsis: 'A long detailed synopsis with lots of information about the book and its themes.',
      image: 'https://images.isbndb.com/covers/49/35/9780451524935.jpg',
      pages: 328,
      binding: 'Hardcover'
    };

    const work = normalizeISBNdbToWork(highQualityBook);
    expect(work.isbndbQuality).toBeGreaterThanOrEqual(90);

    const lowQualityBook = {
      isbn13: '9781234567890',
      title: 'Unknown Book'
    };

    const lowWork = normalizeISBNdbToWork(lowQualityBook);
    expect(lowWork.isbndbQuality).toBeLessThan(60);
  });
});

describe('normalizeISBNdbToEdition', () => {
  it('should convert ISBNdb book to EditionDTO', () => {
    const isbndbBook = {
      isbn13: '9780451524935',
      isbn: '0451524934',
      title: '1984',
      title_long: '1984: A Novel',
      publisher: 'Penguin Books',
      date_published: '2021-01-05',
      pages: 328,
      binding: 'Hardcover',
      language: 'en',
      synopsis: 'A dystopian novel...',
      image: 'https://images.isbndb.com/covers/49/35/9780451524935.jpg',
      subjects: ['Fiction']
    };

    const edition = normalizeISBNdbToEdition(isbndbBook);

    expect(edition.isbn).toBe('9780451524935'); // ISBN-13 preferred
    expect(edition.isbns).toContain('9780451524935');
    expect(edition.isbns).toContain('0451524934');
    expect(edition.publisher).toBe('Penguin Books');
    expect(edition.publicationDate).toBe('2021-01-05');
    expect(edition.pageCount).toBe(328);
    expect(edition.format).toBe('Hardcover');
    expect(edition.coverImageURL).toBe('https://images.isbndb.com/covers/49/35/9780451524935.jpg');
    expect(edition.editionTitle).toBe('1984: A Novel');
    expect(edition.editionDescription).toBe('A dystopian novel...');
    expect(edition.primaryProvider).toBe('isbndb');
    expect(edition.isbndbID).toBe('9780451524935');
  });

  it('should normalize different binding formats correctly', () => {
    const testBindings = [
      { input: 'Hardcover', expected: 'Hardcover' },
      { input: 'Paperback', expected: 'Paperback' },
      { input: 'Mass Market Paperback', expected: 'Paperback' },
      { input: 'eBook', expected: 'E-book' },
      { input: 'Kindle Edition', expected: 'E-book' },
      { input: 'Audiobook', expected: 'Audiobook' },
      { input: 'Audio CD', expected: 'Audiobook' },
      { input: 'Unknown Format', expected: 'Paperback' } // default
    ];

    testBindings.forEach(({ input, expected }) => {
      const book = {
        isbn13: '9781234567890',
        title: 'Test Book',
        binding: input
      };
      const edition = normalizeISBNdbToEdition(book);
      expect(edition.format).toBe(expected);
    });
  });

  it('should handle edition with only ISBN-10', () => {
    const book = {
      isbn: '0451524934',
      title: '1984',
      binding: 'Paperback'
    };

    const edition = normalizeISBNdbToEdition(book);
    expect(edition.isbn).toBe('0451524934');
    expect(edition.isbns).toContain('0451524934');
  });
});

describe('normalizeISBNdbToAuthor', () => {
  it('should convert author name to AuthorDTO', () => {
    const author = normalizeISBNdbToAuthor('George Orwell');

    expect(author.name).toBe('George Orwell');
    expect(author.gender).toBe('Unknown'); // ISBNdb doesn't provide gender
  });

  it('should handle empty author name', () => {
    const author = normalizeISBNdbToAuthor('');

    expect(author.name).toBe('');
    expect(author.gender).toBe('Unknown');
  });
});
