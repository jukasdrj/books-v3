// test/author-search-performance.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { searchByAuthor } from '../src/handlers/author-search.js';

describe('Author Search Performance', () => {
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

    global.caches = {
      default: {
        match: vi.fn(async () => null),
        put: vi.fn(async () => {})
      }
    };

    global.fetch = vi.fn();
  });

  test('should handle Stephen King (437 works) without timeout', async () => {
    // Mock 437 works (Stephen King's actual count)
    const mockWorks = Array.from({ length: 437 }, (_, i) => ({
      title: `Book ${i + 1}`,
      first_publish_year: 1974 + (i % 51), // Spans 1974-2025
      key: `/works/OL${10000 + i}W`
    }));

    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL2162284A', name: 'Stephen King' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks,
        size: 437
      }), { status: 200 }));

    const startTime = Date.now();
    const result = await searchByAuthor('Stephen King', { limit: 50, offset: 0 }, mockEnv, mockCtx);
    const duration = Date.now() - startTime;

    // Performance assertions
    expect(duration).toBeLessThan(3000); // Should complete in <3s
    expect(result.success).toBe(true);
    expect(result.works).toHaveLength(50); // First page only
    expect(result.pagination.total).toBe(437);
    expect(result.pagination.hasMore).toBe(true);
  });

  test('should handle Isaac Asimov (506 works) pagination', async () => {
    const mockWorks = Array.from({ length: 506 }, (_, i) => ({
      title: `Book ${i + 1}`,
      first_publish_year: 1950 + (i % 75),
      key: `/works/OL${20000 + i}W`
    }));

    // Mock for page 1
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL34221A', name: 'Isaac Asimov' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks,
        size: 506
      }), { status: 200 }))
      // Mock for page 2 (same data, different cache key)
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL34221A', name: 'Isaac Asimov' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks,
        size: 506
      }), { status: 200 }))
      // Mock for last page
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL34221A', name: 'Isaac Asimov' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks,
        size: 506
      }), { status: 200 }));

    // Test loading all pages
    const page1 = await searchByAuthor('Isaac Asimov', { limit: 100, offset: 0 }, mockEnv, mockCtx);
    expect(page1.works).toHaveLength(100);
    expect(page1.pagination.nextOffset).toBe(100);

    const page2 = await searchByAuthor('Isaac Asimov', { limit: 100, offset: 100 }, mockEnv, mockCtx);
    expect(page2.works).toHaveLength(100);
    expect(page2.pagination.nextOffset).toBe(200);

    // ... continue until last page
    const lastPage = await searchByAuthor('Isaac Asimov', { limit: 100, offset: 500 }, mockEnv, mockCtx);
    expect(lastPage.works).toHaveLength(6); // Remaining works
    expect(lastPage.pagination.hasMore).toBe(false);
  });

  test('should sort 437 works efficiently', async () => {
    const mockWorks = Array.from({ length: 437 }, (_, i) => ({
      title: `${String.fromCharCode(65 + (i % 26))} Book ${i}`, // Random letters A-Z
      first_publish_year: 1974 + (i % 51),
      key: `/works/OL${10000 + i}W`
    }));

    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({
        docs: [{ key: '/authors/OL2162284A', name: 'Stephen King' }]
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        entries: mockWorks,
        size: 437
      }), { status: 200 }));

    // Test sorting doesn't cause timeout
    const startTime = Date.now();
    const result = await searchByAuthor('Stephen King', { limit: 50, offset: 0, sortBy: 'title' }, mockEnv, mockCtx);
    const duration = Date.now() - startTime;

    expect(duration).toBeLessThan(3000);
    // Verify alphabetical order (first title should be <= second title)
    expect(result.works[0].title.localeCompare(result.works[1].title)).toBeLessThanOrEqual(0);
  });
});
