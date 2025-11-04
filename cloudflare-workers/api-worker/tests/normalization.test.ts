import { describe, test, expect } from 'vitest';
import { normalizeTitle, normalizeISBN, normalizeAuthor, normalizeImageURL } from '../src/utils/normalization';

describe('normalizeTitle', () => {
  test('removes leading "The"', () => {
    expect(normalizeTitle('The Hobbit')).toBe('hobbit');
  });

  test('removes leading "A"', () => {
    expect(normalizeTitle('A Tale of Two Cities')).toBe('tale of two cities');
  });

  test('removes leading "An"', () => {
    expect(normalizeTitle('An American Tragedy')).toBe('american tragedy');
  });

  test('lowercases and trims', () => {
    expect(normalizeTitle('  THE HOBBIT  ')).toBe('hobbit');
  });

  test('removes punctuation', () => {
    expect(normalizeTitle('The Hobbit: An Unexpected Journey')).toBe('hobbit an unexpected journey');
  });

  test('handles empty string', () => {
    expect(normalizeTitle('')).toBe('');
  });
});

describe('normalizeISBN', () => {
  test('removes hyphens from ISBN-13', () => {
    expect(normalizeISBN('978-0-547-92822-7')).toBe('9780547928227');
  });

  test('removes spaces from ISBN', () => {
    expect(normalizeISBN('978 0 547 92822 7')).toBe('9780547928227');
  });

  test('preserves X in ISBN-10', () => {
    expect(normalizeISBN('043942089X')).toBe('043942089X');
  });

  test('trims whitespace', () => {
    expect(normalizeISBN('  9780547928227  ')).toBe('9780547928227');
  });

  test('handles already normalized ISBN', () => {
    expect(normalizeISBN('9780547928227')).toBe('9780547928227');
  });
});

describe('normalizeAuthor', () => {
  test('lowercases and trims', () => {
    expect(normalizeAuthor('  J.R.R. Tolkien  ')).toBe('j.r.r. tolkien');
  });

  test('handles empty string', () => {
    expect(normalizeAuthor('')).toBe('');
  });
});

describe('normalizeImageURL', () => {
  test('removes query parameters', () => {
    const url = 'http://books.google.com/covers/abc.jpg?zoom=1&source=gbs_api';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('forces HTTPS', () => {
    const url = 'http://books.google.com/covers/abc.jpg';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('handles already normalized URL', () => {
    const url = 'https://books.google.com/covers/abc.jpg';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('trims whitespace', () => {
    const url = '  https://books.google.com/covers/abc.jpg  ';
    expect(normalizeImageURL(url)).toBe('https://books.google.com/covers/abc.jpg');
  });

  test('handles invalid URL gracefully', () => {
    expect(normalizeImageURL('not a url')).toBe('not a url');
  });
});
