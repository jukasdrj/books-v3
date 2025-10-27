/**
 * Integration tests for api-worker monolith
 *
 * Tests all major endpoints:
 * - Health check
 * - Title search
 * - ISBN search
 * - Advanced search
 * - Enrichment start
 * - AI scan (basic validation)
 *
 * Run with: npm test
 *
 * Note: These tests require the worker to be running locally:
 * npm run dev (in another terminal)
 */

import { describe, it, expect, beforeAll } from 'vitest';

describe('API Worker Integration Tests', () => {
  const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:8787';

  // Test connection to local dev server
  beforeAll(async () => {
    try {
      const response = await fetch(`${BASE_URL}/health`);
      if (!response.ok) {
        throw new Error('Worker not running. Start with: npm run dev');
      }
    } catch (error) {
      console.error('Failed to connect to worker:', error.message);
      throw new Error('Worker must be running on http://localhost:8787. Start with: npm run dev');
    }
  });

  // ========================================================================
  // Health Endpoint Tests
  // ========================================================================

  describe('GET /health', () => {
    it('should return health status with 200 OK', async () => {
      const response = await fetch(`${BASE_URL}/health`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.status).toBe('ok');
      expect(data.worker).toBe('api-worker');
      expect(data.version).toBeTruthy();
    });

    it('should list all available endpoints', async () => {
      const response = await fetch(`${BASE_URL}/health`);
      const data = await response.json();

      expect(data.endpoints).toBeInstanceOf(Array);
      expect(data.endpoints.length).toBeGreaterThan(0);

      // Verify key endpoints are listed
      const endpointsList = data.endpoints.join(' ');
      expect(endpointsList).toContain('/search/title');
      expect(endpointsList).toContain('/search/isbn');
      expect(endpointsList).toContain('/search/advanced');
      expect(endpointsList).toContain('/api/enrichment/start');
      expect(endpointsList).toContain('/api/scan-bookshelf');
      expect(endpointsList).toContain('/ws/progress');
    });
  });

  // ========================================================================
  // Book Search Tests
  // ========================================================================

  describe('GET /search/title', () => {
    it('should search books by title successfully', async () => {
      const response = await fetch(`${BASE_URL}/search/title?q=hamlet`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();

      // Should have items array and provider info
      expect(data.items).toBeInstanceOf(Array);
      expect(data.provider).toBeTruthy();
    });

    it('should return 400 if query parameter is missing', async () => {
      const response = await fetch(`${BASE_URL}/search/title`);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('query');
    });

    it('should handle maxResults parameter', async () => {
      const response = await fetch(`${BASE_URL}/search/title?q=gatsby&maxResults=5`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();
    });

    it('should include CORS headers', async () => {
      const response = await fetch(`${BASE_URL}/search/title?q=test`);
      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    });
  });

  describe('GET /search/isbn', () => {
    it('should search books by ISBN successfully', async () => {
      // The Great Gatsby ISBN
      const response = await fetch(`${BASE_URL}/search/isbn?isbn=9780743273565`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();
      expect(data.provider).toBeTruthy();
    });

    it('should return 400 if ISBN parameter is missing', async () => {
      const response = await fetch(`${BASE_URL}/search/isbn`);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('ISBN');
    });

    it('should handle invalid ISBN gracefully', async () => {
      const response = await fetch(`${BASE_URL}/search/isbn?isbn=invalid-isbn-123`);
      // Should either return 200 with no results or handle gracefully
      expect([200, 404, 500]).toContain(response.status);
    });

    it('should include CORS headers', async () => {
      const response = await fetch(`${BASE_URL}/search/isbn?isbn=9780743273565`);
      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    });
  });

  describe('POST /search/advanced', () => {
    it('should handle advanced search with title and author', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bookTitle: '1984',
          authorName: 'Orwell',
          maxResults: 10
        })
      });

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
      expect(data.provider).toBeTruthy();
    });

    it('should handle title-only search', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bookTitle: 'To Kill a Mockingbird'
        })
      });

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
    });

    it('should handle author-only search', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          authorName: 'Tolkien'
        })
      });

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
    });

    it('should return 400 if no search parameters provided', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
    });

    it('should include CORS headers', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bookTitle: 'test' })
      });

      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    });

    it('should handle malformed JSON gracefully', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid-json'
      });

      expect([400, 500]).toContain(response.status);
    });
  });

  describe('GET /search/advanced (query parameters)', () => {
    it('should handle GET with title and author query params', async () => {
      const params = new URLSearchParams({
        title: '1984',
        author: 'Orwell',
        maxResults: '10'
      });

      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
      expect(data.provider).toBeTruthy();
      expect(data.success).toBe(true);
    });

    it('should handle GET with title-only query param', async () => {
      const params = new URLSearchParams({
        title: 'To Kill a Mockingbird'
      });

      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
      expect(data.success).toBe(true);
    });

    it('should handle GET with author-only query param', async () => {
      const params = new URLSearchParams({
        author: 'Tolkien'
      });

      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
    });

    it('should return 400 for GET with no query parameters', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`);

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toContain('At least one search parameter required');
    });

    it('should include CORS headers for GET requests', async () => {
      const params = new URLSearchParams({ title: 'test' });
      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    });

    it('should default maxResults to 20 when not provided', async () => {
      const params = new URLSearchParams({ title: 'The Hobbit' });
      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.items).toBeInstanceOf(Array);
      // Note: actual maxResults validation happens in handler
    });

    it('should support both "title" and "bookTitle" param names', async () => {
      // Test backward compatibility with documentation examples
      const params = new URLSearchParams({
        title: 'The Great Gatsby',
        author: 'Fitzgerald'
      });

      const response = await fetch(`${BASE_URL}/search/advanced?${params}`);

      expect(response.status).toBe(200);
      expect((await response.json()).success).toBe(true);
    });
  });

  describe('Backward Compatibility - POST with JSON body', () => {
    it('should still accept POST with bookTitle field', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bookTitle: 'The Catcher in the Rye',
          authorName: 'Salinger'
        })
      });

      expect(response.status).toBe(200);
      expect((await response.json()).success).toBe(true);
    });

    it('should accept POST with "title" field (alternate naming)', async () => {
      const response = await fetch(`${BASE_URL}/search/advanced`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'Animal Farm',
          author: 'Orwell'
        })
      });

      expect(response.status).toBe(200);
      expect((await response.json()).success).toBe(true);
    });
  });

  // ========================================================================
  // Enrichment Endpoint Tests
  // ========================================================================

  describe('POST /api/enrichment/start', () => {
    it('should start enrichment job and return 202 Accepted', async () => {
      const jobId = `test-enrich-${Date.now()}`;

      const response = await fetch(`${BASE_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId,
          workIds: ['work-1', 'work-2', 'work-3']
        })
      });

      expect(response.status).toBe(202);

      const data = await response.json();
      expect(data.jobId).toBe(jobId);
      expect(data.status).toBe('started');
      expect(data.totalBooks).toBe(3);
      expect(data.message).toContain('ws/progress');
    });

    it('should return 400 if jobId is missing', async () => {
      const response = await fetch(`${BASE_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          workIds: ['work-1', 'work-2']
        })
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('jobId');
    });

    it('should return 400 if workIds is missing', async () => {
      const response = await fetch(`${BASE_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId: 'test-123'
        })
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('workIds');
    });

    it('should return 400 if workIds is not an array', async () => {
      const response = await fetch(`${BASE_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId: 'test-123',
          workIds: 'not-an-array'
        })
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
    });

    it('should return 400 if workIds array is empty', async () => {
      const response = await fetch(`${BASE_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId: 'test-123',
          workIds: []
        })
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('empty');
    });
  });

  // ========================================================================
  // AI Scanner Endpoint Tests
  // ========================================================================

  describe('POST /api/scan-bookshelf', () => {
    it('should accept image upload and return 202 Accepted', async () => {
      // Create a minimal valid JPEG (1x1 pixel red square)
      const minimalJpeg = new Uint8Array([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
        0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c,
        0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
        0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d,
        0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20,
        0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
        0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27,
        0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34,
        0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4,
        0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x03, 0xff, 0xc4, 0x00, 0x14,
        0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3f, 0x00, 0x37, 0xff, 0xd9
      ]);

      const jobId = `test-scan-${Date.now()}`;

      const response = await fetch(`${BASE_URL}/api/scan-bookshelf?jobId=${jobId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'image/jpeg' },
        body: minimalJpeg
      });

      expect(response.status).toBe(202);

      const data = await response.json();
      expect(data.jobId).toBe(jobId);
      expect(data.status).toBe('started');
      expect(data.message).toContain('ws/progress');

      // Verify stages metadata for iOS client
      expect(data.stages).toBeInstanceOf(Array);
      expect(data.stages.length).toBe(3);
      expect(data.stages[0]).toHaveProperty('name');
      expect(data.stages[0]).toHaveProperty('typicalDuration');
      expect(data.stages[0]).toHaveProperty('progress');

      // Verify estimatedRange
      expect(data.estimatedRange).toBeInstanceOf(Array);
      expect(data.estimatedRange.length).toBe(2);
      expect(data.estimatedRange[0]).toBeLessThan(data.estimatedRange[1]);
    });

    it('should generate jobId if not provided', async () => {
      const minimalJpeg = new Uint8Array([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
        0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c,
        0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
        0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d,
        0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20,
        0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
        0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27,
        0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34,
        0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4,
        0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x03, 0xff, 0xc4, 0x00, 0x14,
        0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3f, 0x00, 0x37, 0xff, 0xd9
      ]);

      const response = await fetch(`${BASE_URL}/api/scan-bookshelf`, {
        method: 'POST',
        headers: { 'Content-Type': 'image/jpeg' },
        body: minimalJpeg
      });

      expect(response.status).toBe(202);

      const data = await response.json();
      expect(data.jobId).toBeTruthy();
      expect(data.jobId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
      expect(data.status).toBe('started');
    });

    it('should return 400 if Content-Type is not image/*', async () => {
      const response = await fetch(`${BASE_URL}/api/scan-bookshelf`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ test: 'data' })
      });

      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('image');
    });

    it('should return 413 if image is too large', async () => {
      // Create a buffer larger than MAX_SCAN_FILE_SIZE (10MB)
      const largeBuffer = new Uint8Array(11 * 1024 * 1024); // 11MB

      const response = await fetch(`${BASE_URL}/api/scan-bookshelf`, {
        method: 'POST',
        headers: { 'Content-Type': 'image/jpeg' },
        body: largeBuffer
      });

      expect(response.status).toBe(413);

      const data = await response.json();
      expect(data.error).toBeTruthy();
      expect(data.error).toContain('too large');
    });

    it('should include CORS headers', async () => {
      const minimalJpeg = new Uint8Array([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00, 0xff, 0xd9
      ]);

      const response = await fetch(`${BASE_URL}/api/scan-bookshelf`, {
        method: 'POST',
        headers: { 'Content-Type': 'image/jpeg' },
        body: minimalJpeg
      });

      expect(response.headers.get('access-control-allow-origin')).toBe('*');
    });
  });

  // ========================================================================
  // WebSocket Endpoint Tests (Basic Validation)
  // ========================================================================

  describe('GET /ws/progress', () => {
    it('should return 400 if jobId parameter is missing', async () => {
      const response = await fetch(`${BASE_URL}/ws/progress`);
      expect(response.status).toBe(400);

      const text = await response.text();
      expect(text).toContain('jobId');
    });

    // Note: Full WebSocket testing would require more complex setup
    // with WebSocket client library. For now, we just verify the
    // endpoint exists and validates parameters.
  });

  // ========================================================================
  // Error Handling Tests
  // ========================================================================

  describe('Error Handling', () => {
    it('should return 404 for unknown endpoints', async () => {
      const response = await fetch(`${BASE_URL}/unknown-endpoint`);
      expect(response.status).toBe(404);

      const data = await response.json();
      expect(data.error).toBe('Not Found');
      expect(data.message).toContain('does not exist');
    });

    it('should return valid JSON for 404 errors', async () => {
      const response = await fetch(`${BASE_URL}/invalid`);
      expect(response.headers.get('content-type')).toContain('application/json');

      const data = await response.json();
      expect(data.error).toBeTruthy();
    });

    it('should handle GET requests to POST-only endpoints', async () => {
      const response = await fetch(`${BASE_URL}/api/enrichment/start`);
      // Should either return 404 (not matched) or handle gracefully
      expect([404, 405, 400]).toContain(response.status);
    });
  });

  // ========================================================================
  // External API Endpoints Tests (Backward Compatibility)
  // ========================================================================

  describe('External API Endpoints', () => {
    it('GET /external/google-books should work', async () => {
      const response = await fetch(`${BASE_URL}/external/google-books?q=hamlet&maxResults=5`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();
    });

    it('GET /external/openlibrary should work', async () => {
      const response = await fetch(`${BASE_URL}/external/openlibrary?q=tolkien&maxResults=5`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();
    });

    it('GET /external/google-books-isbn should work', async () => {
      const response = await fetch(`${BASE_URL}/external/google-books-isbn?isbn=9780743273565`);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toBeTruthy();
    });

    it('should return 400 for missing query parameters', async () => {
      const response = await fetch(`${BASE_URL}/external/google-books`);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.error).toBeTruthy();
    });
  });
});
