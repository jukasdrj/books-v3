// test/book-search-integration.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { searchByTitle, searchByISBN } from '../src/handlers/book-search.js';

describe('searchByTitle with UnifiedCache', () => {
  let mockEnv;
  let mockCtx;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: vi.fn(async () => null),
        put: vi.fn(async () => {})
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn(async () => {})
      }
    };
    mockCtx = {
      waitUntil: vi.fn((promise) => promise)
    };

    // Mock global caches for edge cache
    global.caches = {
      default: {
        match: vi.fn(async () => {
          return new Response(JSON.stringify({
            items: [{ volumeInfo: { title: 'Hamlet' } }]
          }), {
            headers: { 'Content-Type': 'application/json' }
          });
        }),
        put: vi.fn(async () => {})
      }
    };
  });

  test('uses UnifiedCacheService for cache operations', async () => {
    const result = await searchByTitle('hamlet', { maxResults: 20 }, mockEnv, mockCtx);

    expect(result.cached).toBe(true);
    expect(result.cacheSource).toBe('EDGE');
    expect(result.items).toBeDefined();
  });
});

describe('searchByISBN with UnifiedCache', () => {
  let mockEnv;
  let mockCtx;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: vi.fn(async () => null),
        put: vi.fn(async () => {})
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn(async () => {})
      }
    };
    mockCtx = {
      waitUntil: vi.fn((promise) => promise)
    };

    // Mock global caches for edge cache
    global.caches = {
      default: {
        match: vi.fn(async () => {
          return new Response(JSON.stringify({
            items: [{ volumeInfo: { industryIdentifiers: [{ identifier: '9780743273565' }] } }]
          }), {
            headers: { 'Content-Type': 'application/json' }
          });
        }),
        put: vi.fn(async () => {})
      }
    };
  });

  test('uses unified cache', async () => {
    const result = await searchByISBN('9780743273565', { maxResults: 1 }, mockEnv, mockCtx);

    expect(result.cached).toBe(true);
    expect(result.cacheSource).toBe('EDGE');
  });
});
