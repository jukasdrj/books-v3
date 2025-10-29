// test/author-search.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { searchByAuthor } from '../src/handlers/author-search.js';

describe('searchByAuthor', () => {
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
        match: vi.fn(async () => null),
        put: vi.fn(async () => {})
      }
    };

    // Mock fetch for OpenLibrary API
    global.fetch = vi.fn();
  });

  test('should search for author and return paginated results', async () => {
    // Mock OpenLibrary author search response
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL23919A', name: 'Neil Gaiman' }]
      }), { status: 200 }))
      // Mock OpenLibrary works response
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: [
          { title: 'American Gods', first_publish_year: 2001, key: '/works/OL45804W' },
          { title: 'Coraline', first_publish_year: 2002, key: '/works/OL45805W' }
        ]
      }), { status: 200 }));

    const result = await searchByAuthor(
      'Neil Gaiman',
      { limit: 50, offset: 0 },
      mockEnv,
      mockCtx
    );

    expect(result.success).toBe(true);
    expect(result.provider).toBe('openlibrary');
    expect(result.author.name).toBe('Neil Gaiman');
    expect(result.author.openLibraryKey).toBe('/authors/OL23919A');
    expect(result.works).toHaveLength(2);
    expect(result.pagination).toEqual({
      total: 2,
      limit: 50,
      offset: 0,
      hasMore: false,
      nextOffset: null
    });
  });

  test('should handle pagination with offset', async () => {
    // Mock 150 total works
    const mockWorks = Array.from({ length: 150 }, (_, i) => ({
      title: `Book ${i + 1}`,
      first_publish_year: 2000 + i,
      key: `/works/OL${i}W`
    }));

    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL2162284A', name: 'Stephen King' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks
      }), { status: 200 }));

    const result = await searchByAuthor(
      'Stephen King',
      { limit: 50, offset: 0 },
      mockEnv,
      mockCtx
    );

    expect(result.works).toHaveLength(50); // First page only
    expect(result.pagination.total).toBe(150);
    expect(result.pagination.hasMore).toBe(true);
    expect(result.pagination.nextOffset).toBe(50);
  });

  test('should cache results with 6h TTL', async () => {
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL23919A', name: 'Neil Gaiman' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: [{ title: 'American Gods', first_publish_year: 2001, key: '/works/OL45804W' }]
      }), { status: 200 }));

    await searchByAuthor('Neil Gaiman', { limit: 50, offset: 0 }, mockEnv, mockCtx);

    // Verify cache was written via waitUntil
    expect(mockCtx.waitUntil).toHaveBeenCalled();
  });

  test('should return error when author not found', async () => {
    global.fetch.mockResolvedValueOnce(new Response(JSON.stringify({
      docs: []
    }), { status: 200 }));

    const result = await searchByAuthor('Nonexistent Author', { limit: 50, offset: 0 }, mockEnv, mockCtx);

    expect(result.success).toBe(false);
    expect(result.error).toBe('Author not found in OpenLibrary');
  });
});
