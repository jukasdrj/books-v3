import { describe, it, expect } from 'vitest';
import { generateR2Path, parseR2Path } from '../src/utils/r2-paths.js';

describe('R2 Path Utilities', () => {
  it('should generate date-based R2 path', () => {
    const cacheKey = 'search:title:q=obscure-book';
    const path = generateR2Path(cacheKey);

    expect(path).toMatch(/^cold-cache\/\d{4}\/\d{2}\/search:title:q=obscure-book\.json$/);
  });

  it('should parse R2 path back to cache key', () => {
    const path = 'cold-cache/2025/10/search:title:q=obscure-book.json';
    const cacheKey = parseR2Path(path);

    expect(cacheKey).toBe('search:title:q=obscure-book');
  });
});
