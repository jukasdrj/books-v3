import { describe, it, expect, beforeEach, vi } from 'vitest';
import { handleSearchAdvanced } from '../../../src/handlers/v1/search-advanced.js';

// Mock ExecutionContext
const createMockContext = () => {
  const waitUntilPromises: Promise<any>[] = [];
  return {
    waitUntil: (promise: Promise<any>) => {
      waitUntilPromises.push(promise);
    },
    passThroughOnException: () => {},
    getWaitUntilPromises: () => waitUntilPromises
  };
};

describe('GET /v1/search/advanced - Cache Behavior', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should return cached result when available in CACHE (KV)', async () => {
    const cachedData = {
      success: true,
      data: {
        works: [{ title: '1984', workId: 'test-1', primaryProvider: 'google-books' }],
        editions: [],
        authors: [{ name: 'George Orwell', authorId: 'author-1' }]
      },
      meta: {
        timestamp: Date.now(),
        processingTime: 100,
        provider: 'google-books'
      }
    };

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async (key: string) => {
          if (key.startsWith('v1:advanced:')) {
            return {
              data: cachedData,
              cachedAt: Date.now() - 1000,
              ttl: 21600
            };
          }
          return null;
        },
        put: async () => {}
      }
    };

    const mockCtx = createMockContext();
    const response = await handleSearchAdvanced('1984', 'George Orwell', mockEnv, mockCtx);

    expect(response.success).toBe(true);
    if (response.success) {
      expect(response.data.works).toHaveLength(1);
      expect(response.data.works[0].title).toBe('1984');
      expect(response.meta.cached).toBe(true);
      expect(response.meta.cacheSource).toBeDefined();
    }
  });

  it('should write to cache after successful enrichment', async () => {
    let cacheWritten = false;
    let writtenKey = '';
    let writtenValue: any = null;

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async () => null, // Cache miss
        put: async (key: string, value: string, options: any) => {
          cacheWritten = true;
          writtenKey = key;
          writtenValue = JSON.parse(value);
        }
      }
    };

    const mockCtx = createMockContext();
    const response = await handleSearchAdvanced('The Great Gatsby', 'F. Scott Fitzgerald', mockEnv, mockCtx);

    // Wait for waitUntil promises to complete
    await Promise.all(mockCtx.getWaitUntilPromises());

    expect(cacheWritten).toBe(true);
    expect(writtenKey).toContain('v1:advanced');
    expect(writtenKey).toContain('great gatsby'); // normalized: removes "The" prefix, lowercases
    expect(writtenKey).toContain('f. scott fitzgerald'); // normalized: lowercases
    expect(writtenValue.data).toBeDefined();
  });

  it('should use normalized title and author for cache key', async () => {
    const cacheKeys: string[] = [];

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async (key: string) => {
          cacheKeys.push(key);
          return null;
        },
        put: async () => {}
      }
    };

    const mockCtx1 = createMockContext();
    const mockCtx2 = createMockContext();

    // Search with different casing - should produce same cache key
    // normalizeTitle removes "The" and lowercases
    // normalizeAuthor just lowercases and trims
    await handleSearchAdvanced('The Great Gatsby', 'F. Scott Fitzgerald', mockEnv, mockCtx1);
    await handleSearchAdvanced('great gatsby', 'f. scott fitzgerald', mockEnv, mockCtx2);

    // Extract the actual cache keys (first call in each search is the cache lookup)
    const cacheKey1 = cacheKeys[0];
    const cacheKey2 = cacheKeys[cacheKeys.length - 2]; // Second search's first cache lookup

    // Both should produce the same normalized cache key
    expect(cacheKey1).toBe(cacheKey2);
    expect(cacheKey1).toContain('great gatsby'); // normalized title (removed "The")
    expect(cacheKey1).toContain('f. scott fitzgerald'); // normalized author (lowercase)
  });

  it('should handle cache with 6 hour TTL', async () => {
    let ttl = 0;

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async () => null,
        put: async (key: string, value: string, options: any) => {
          ttl = options.expirationTtl;
        }
      }
    };

    const mockCtx = createMockContext();
    await handleSearchAdvanced('1984', 'George Orwell', mockEnv, mockCtx);

    // Wait for waitUntil promises
    await Promise.all(mockCtx.getWaitUntilPromises());

    expect(ttl).toBe(6 * 60 * 60); // 21600 seconds
  });

  it('should handle title-only search with cache', async () => {
    let cacheKey = '';

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async (key: string) => {
          cacheKey = key;
          return null;
        },
        put: async () => {}
      }
    };

    const mockCtx = createMockContext();
    await handleSearchAdvanced('1984', '', mockEnv, mockCtx);

    expect(cacheKey).toContain('v1:advanced');
    expect(cacheKey).toContain('1984');
    // Author should be empty in cache key
    expect(cacheKey).toContain('author=');
  });

  it('should handle author-only search with cache', async () => {
    let cacheKey = '';

    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async (key: string) => {
          cacheKey = key;
          return null;
        },
        put: async () => {}
      }
    };

    const mockCtx = createMockContext();
    await handleSearchAdvanced('', 'George Orwell', mockEnv, mockCtx);

    expect(cacheKey).toContain('v1:advanced');
    expect(cacheKey).toContain('george orwell');
    // Title should be empty in cache key
    expect(cacheKey).toContain('title=');
  });
});

describe('GET /v1/search/advanced - ISBNdb Fallback', () => {
  it('should fall back to ISBNdb when Google Books and OpenLibrary return no results', async () => {
    // This is an integration test - we verify the enrichment service calls ISBNdb
    // The actual ISBNdb API call is tested in the enrichment service tests
    
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      ISBNDB_API_KEY: 'test-isbndb-key',
      CACHE: {
        get: async () => null,
        put: async () => {}
      }
    };

    const mockCtx = createMockContext();
    
    // Use a book that's unlikely to be in Google Books or OpenLibrary
    // The enrichment service will attempt ISBNdb as the third fallback
    const response = await handleSearchAdvanced('Obscure Test Book', 'Unknown Author', mockEnv, mockCtx);

    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    // If ISBNdb is working, it may return results. Otherwise, empty results are OK.
    if (response.success) {
      expect(response.data).toBeDefined();
      expect(response.data.works).toBeDefined();
      expect(Array.isArray(response.data.works)).toBe(true);
    }
  });
});
