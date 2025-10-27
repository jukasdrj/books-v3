// test/parallel-enrichment.test.js
import { describe, test, expect, vi } from 'vitest';
import { enrichBooksParallel } from '../src/services/parallel-enrichment.js';

describe('Parallel Enrichment', () => {
  test('enriches books concurrently with concurrency limit', async () => {
    const books = [
      { title: 'Book1', isbn: '111' },
      { title: 'Book2', isbn: '222' },
      { title: 'Book3', isbn: '333' }
    ];

    const mockEnrich = vi.fn(async (book) => ({ ...book, enriched: true }));
    const mockProgress = vi.fn();

    const result = await enrichBooksParallel(books, mockEnrich, mockProgress, 2);

    expect(result).toHaveLength(3);
    expect(result.every(b => b.enriched)).toBe(true);
    expect(mockProgress).toHaveBeenCalledTimes(3);
  });

  test('continues on individual enrichment failures', async () => {
    const books = [
      { title: 'Book1' },
      { title: 'Book2' },
      { title: 'Book3' }
    ];

    const mockEnrich = vi.fn(async (book) => {
      if (book.title === 'Book2') throw new Error('API failed');
      return { ...book, enriched: true };
    });

    const result = await enrichBooksParallel(books, mockEnrich, vi.fn(), 2);

    expect(result).toHaveLength(3);
    expect(result[0].enriched).toBe(true);
    expect(result[1].enrichmentError).toContain('API failed');
    expect(result[2].enriched).toBe(true);
  });
});
