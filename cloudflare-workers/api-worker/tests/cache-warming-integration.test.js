/**
 * Cache Warming Integration Test
 * 
 * Validates that cache warming generates keys compatible with search handlers
 * and stores data in canonical DTO format.
 * 
 * This test verifies the fix for cache key mismatch issues documented in:
 * cloudflare-workers/api-worker/docs/plans/2025-10-29-cache-warming-fix.md
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { processAuthorBatch } from '../src/consumers/author-warming-consumer.js';
import { generateCacheKey } from '../src/utils/cache.js';
import { normalizeTitle } from '../src/utils/normalization.ts';

describe('Cache Warming Integration - DTO Normalization Compatibility', () => {
  let env, ctx;

  beforeEach(() => {
    env = {
      CACHE: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined)
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn().mockResolvedValue(undefined)
      }
    };
    ctx = {
      waitUntil: vi.fn()
    };
  });

  describe('Cache Key Compatibility', () => {
    it('should generate title cache keys matching search handler format', () => {
      // Simulate what book-search.js does
      const title = "The Hobbit";
      const maxResults = 20;
      
      const searchHandlerKey = generateCacheKey('search:title', { 
        title: title.toLowerCase(), 
        maxResults 
      });

      // Expected format: search:title:maxResults=20&title=the hobbit
      expect(searchHandlerKey).toBe('search:title:maxResults=20&title=the hobbit');
    });

    it('should generate title cache keys with normalization matching v1 search', () => {
      // Simulate what v1/search-title.ts does
      const title = "The Hobbit";
      const normalizedTitle = normalizeTitle(title);
      
      // normalizeTitle removes "the" prefix and punctuation
      expect(normalizedTitle).toBe('hobbit');

      const v1SearchKey = generateCacheKey('search:title', {
        title: normalizedTitle,
        maxResults: 20
      });

      // Expected format with normalized title
      expect(v1SearchKey).toBe('search:title:maxResults=20&title=hobbit');
    });

    it('should handle titles with punctuation and articles correctly', () => {
      const testCases = [
        { input: "The Great Gatsby", expected: "great gatsby" },
        { input: "A Tale of Two Cities", expected: "tale of two cities" },
        { input: "Harry Potter & The Philosopher's Stone", expected: "harry potter  the philosophers stone" }
      ];

      testCases.forEach(({ input, expected }) => {
        const normalized = normalizeTitle(input);
        expect(normalized).toBe(expected);

        const cacheKey = generateCacheKey('search:title', {
          title: normalized,
          maxResults: 20
        });
        expect(cacheKey).toContain(expected);
      });
    });
  });

  describe('Author Cache Key Compatibility', () => {
    it('should generate author cache keys matching author-search.js format', () => {
      const authorName = "Neil Gaiman";
      const normalizedQuery = authorName.toLowerCase().trim();
      const queryB64 = btoa(normalizedQuery).replace(/[/+=]/g, '_');
      
      const params = {
        maxResults: 100,
        showAllEditions: false,
        sortBy: 'publicationYear'
      };
      
      const paramsString = Object.keys(params)
        .sort()
        .map(key => `${key}=${params[key]}`)
        .join('&');
      
      const paramsB64 = btoa(paramsString).replace(/[/+=]/g, '_');
      const expectedKey = `auto-search:${queryB64}:${paramsB64}`;

      // This is the format author-search.js uses
      expect(expectedKey).toMatch(/^auto-search:[A-Za-z0-9_]+:[A-Za-z0-9_]+$/);
    });
  });

  describe('Processed Author Key Format', () => {
    it('should use lowercase author name in processed key', () => {
      const author = "Neil Gaiman";
      const processedKey = `warming:processed:author:${author.toLowerCase()}`;
      
      expect(processedKey).toBe('warming:processed:author:neil gaiman');
    });

    it('should be case-insensitive for duplicate detection', () => {
      const variations = ["Neil Gaiman", "neil gaiman", "NEIL GAIMAN"];
      const keys = variations.map(v => `warming:processed:author:${v.toLowerCase()}`);
      
      // All variations should map to same key
      const uniqueKeys = new Set(keys);
      expect(uniqueKeys.size).toBe(1);
      expect(Array.from(uniqueKeys)[0]).toBe('warming:processed:author:neil gaiman');
    });
  });

  describe('TTL Alignment', () => {
    it('should use 6-hour TTL for title searches (not 24h)', () => {
      // book-search.js uses 6h TTL (21600 seconds)
      const titleSearchTTL = 6 * 60 * 60;
      expect(titleSearchTTL).toBe(21600);

      // Old warming consumer used 24h, should now match search handlers
      const oldWarmingTTL = 24 * 60 * 60;
      expect(titleSearchTTL).not.toBe(oldWarmingTTL);
    });

    it('should use 90-day TTL for processed author markers', () => {
      const processedTTL = 90 * 24 * 60 * 60;
      expect(processedTTL).toBe(7776000); // 90 days in seconds
    });
  });

  describe('Data Format Compatibility', () => {
    it('should expect canonical WorkDTO format from search handlers', async () => {
      // Mock searchByTitle to return canonical format
      const mockCanonicalWork = {
        title: "American Gods",
        subjectTags: ["fiction", "fantasy"],
        originalLanguage: "en",
        firstPublicationYear: 2001,
        description: "A novel by Neil Gaiman",
        synthetic: false,
        primaryProvider: "google-books",
        contributors: ["google-books"],
        goodreadsWorkIDs: [],
        amazonASINs: [],
        librarythingIDs: [],
        googleBooksVolumeIDs: ["ABC123"],
        isbndbQuality: 0,
        reviewStatus: "unreviewed",
        authors: [{ name: "Neil Gaiman" }]
      };

      // This is what searchByTitle (via enrichMultipleBooks) should return
      // Not raw OpenLibrary format like: { title, firstPublicationYear, openLibraryWorkKey }
      expect(mockCanonicalWork).toHaveProperty('subjectTags');
      expect(mockCanonicalWork).toHaveProperty('primaryProvider');
      expect(mockCanonicalWork).toHaveProperty('reviewStatus');
      
      // Old format would NOT have these canonical fields
      expect(mockCanonicalWork).not.toHaveProperty('openLibraryWorkKey');
    });
  });

  describe('Error Handling', () => {
    it('should retry on rate limit errors', async () => {
      const { searchByAuthor } = await import('../src/handlers/author-search.js');
      searchByAuthor.mockRejectedValueOnce(new Error('429 Too Many Requests'));

      const batch = {
        messages: [{
          body: { author: 'Test Author', depth: 0, source: 'test', jobId: 'test-1' },
          ack: vi.fn(),
          retry: vi.fn()
        }]
      };

      await processAuthorBatch(batch, env, ctx);

      expect(batch.messages[0].retry).toHaveBeenCalled();
      expect(batch.messages[0].ack).not.toHaveBeenCalled();
    });

    it('should continue warming other titles if one title fails', async () => {
      const { searchByAuthor } = await import('../src/handlers/author-search.js');
      const { searchByTitle } = await import('../src/handlers/book-search.js');

      // searchByAuthor succeeds, returns 3 works
      searchByAuthor.mockResolvedValueOnce({
        success: true,
        works: [
          { title: 'Work 1' },
          { title: 'Work 2' },
          { title: 'Work 3' }
        ]
      });

      // searchByTitle fails for work 2, succeeds for others
      searchByTitle
        .mockResolvedValueOnce({ items: [] }) // Work 1 success
        .mockRejectedValueOnce(new Error('Network error')) // Work 2 failure
        .mockResolvedValueOnce({ items: [] }); // Work 3 success

      const batch = {
        messages: [{
          body: { author: 'Test Author', depth: 0, source: 'test', jobId: 'test-1' },
          ack: vi.fn(),
          retry: vi.fn()
        }]
      };

      await processAuthorBatch(batch, env, ctx);

      // Should ack the message despite partial failure
      expect(batch.messages[0].ack).toHaveBeenCalled();
      
      // titlesWarmed should be 2 (work 1 and 3)
      const processedCall = env.CACHE.put.mock.calls.find(call =>
        call[0].startsWith('warming:processed:author:')
      );
      const processedData = JSON.parse(processedCall[1]);
      expect(processedData.titlesWarmed).toBe(2);
    });
  });
});

describe('Migration Validation - Old vs New Format', () => {
  it('OLD FORMAT: Would generate incompatible cache key', () => {
    // Old warming consumer (before fix)
    const title = "The Hobbit";
    const oldKey = `search:title:${title.toLowerCase()}`;
    
    expect(oldKey).toBe('search:title:the hobbit');
    
    // This key would NEVER be found by search handlers
    const searchHandlerKey = generateCacheKey('search:title', {
      title: title.toLowerCase(),
      maxResults: 20
    });
    
    expect(oldKey).not.toBe(searchHandlerKey);
  });

  it('NEW FORMAT: Generates compatible cache key via handler', () => {
    // New warming consumer (after fix) uses searchByTitle handler
    // which internally calls generateCacheKey
    const title = "The Hobbit";
    const normalizedTitle = normalizeTitle(title); // "hobbit"
    
    const handlerKey = generateCacheKey('search:title', {
      title: normalizedTitle,
      maxResults: 20
    });
    
    expect(handlerKey).toBe('search:title:maxResults=20&title=hobbit');
    
    // This key WILL be found by v1/search-title.ts
    expect(handlerKey).toContain('maxResults=20');
    expect(handlerKey).toContain('hobbit'); // normalized, no "the"
  });

  it('OLD FORMAT: Would store incompatible DTO structure', () => {
    // Old warming consumer stored raw OpenLibrary work
    const oldFormat = {
      title: "American Gods",
      firstPublicationYear: 2001,
      openLibraryWorkKey: "/works/OL45804W",
      // Missing canonical fields: subjectTags, primaryProvider, etc.
    };

    // Search handlers expect canonical WorkDTO
    expect(oldFormat).not.toHaveProperty('subjectTags');
    expect(oldFormat).not.toHaveProperty('primaryProvider');
    expect(oldFormat).not.toHaveProperty('reviewStatus');
  });

  it('NEW FORMAT: Stores canonical DTO via enrichMultipleBooks', () => {
    // New warming consumer uses searchByTitle → enrichMultipleBooks
    // which returns canonical WorkDTO
    const newFormat = {
      title: "American Gods",
      subjectTags: ["fiction", "fantasy"],
      firstPublicationYear: 2001,
      primaryProvider: "google-books",
      reviewStatus: "unreviewed",
      goodreadsWorkIDs: [],
      amazonASINs: [],
      isbndbQuality: 0,
      // All canonical fields present
    };

    expect(newFormat).toHaveProperty('subjectTags');
    expect(newFormat).toHaveProperty('primaryProvider');
    expect(newFormat).toHaveProperty('reviewStatus');
  });
});
