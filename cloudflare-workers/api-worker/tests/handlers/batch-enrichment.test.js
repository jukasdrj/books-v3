/**
 * Unit tests for batch enrichment handler
 *
 * Tests that the /api/enrichment/batch endpoint returns the correct
 * response structure expected by iOS EnrichmentAPIClient.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleBatchEnrichment } from '../../src/handlers/batch-enrichment.js';

// Mock environment and context
const createMockEnv = () => ({
  PROGRESS_WEBSOCKET_DO: {
    idFromName: vi.fn((name) => `mock-id-${name}`),
    get: vi.fn(() => ({
      updateProgress: vi.fn(),
      complete: vi.fn(),
      fail: vi.fn()
    }))
  }
});

const createMockContext = () => ({
  waitUntil: vi.fn()
});

describe('handleBatchEnrichment', () => {
  let mockEnv;
  let mockCtx;

  beforeEach(() => {
    mockEnv = createMockEnv();
    mockCtx = createMockContext();
  });

  describe('Response structure validation', () => {
    it('should return correct structure with success, processedCount, and totalCount', async () => {
      const books = [
        { title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', isbn: '9780743273565' },
        { title: '1984', author: 'George Orwell', isbn: '9780451524935' },
        { title: 'To Kill a Mockingbird', author: 'Harper Lee', isbn: '9780061120084' }
      ];
      const jobId = 'test-job-123';

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books, jobId })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);

      expect(response.status).toBe(202);

      const body = await response.json();

      // Validate envelope structure
      expect(body).toHaveProperty('data');
      expect(body).toHaveProperty('metadata');
      expect(body.data).toBeDefined();
      expect(body.metadata).toBeDefined();

      // Validate iOS expected fields in data
      expect(body.data).toHaveProperty('success');
      expect(body.data).toHaveProperty('processedCount');
      expect(body.data).toHaveProperty('totalCount');

      // Validate field values
      expect(body.data.success).toBe(true);
      expect(body.data.processedCount).toBe(0); // Job just started, nothing processed yet
      expect(body.data.totalCount).toBe(3); // Should match books array length

      // Validate metadata
      expect(body.metadata.timestamp).toBeDefined();
      expect(typeof body.metadata.timestamp).toBe('string');
    });

    it('should set totalCount to match books array length', async () => {
      const books = Array.from({ length: 48 }, (_, i) => ({
        title: `Book ${i + 1}`,
        author: `Author ${i + 1}`,
        isbn: null
      }));
      const jobId = 'test-job-csv-import';

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books, jobId })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      const body = await response.json();

      expect(body.data.totalCount).toBe(48);
      expect(body.data.processedCount).toBe(0);
      expect(body.data.success).toBe(true);
    });

    it('should handle single book enrichment', async () => {
      const books = [
        { title: 'The Great Gatsby', author: 'F. Scott Fitzgerald', isbn: '9780743273565' }
      ];
      const jobId = 'test-single-book';

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books, jobId })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      const body = await response.json();

      expect(body.data.totalCount).toBe(1);
      expect(body.data.processedCount).toBe(0);
      expect(body.data.success).toBe(true);
    });
  });

  describe('Error handling', () => {
    it('should return 400 for missing books array', async () => {
      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ jobId: 'test-job' })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.error).toBeDefined();
      expect(body.error.message).toContain('Invalid books array');
    });

    it('should return 400 for missing jobId', async () => {
      const books = [{ title: 'Test', author: 'Author', isbn: null }];

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.error).toBeDefined();
      expect(body.error.message).toContain('Missing jobId');
    });

    it('should return 400 for empty books array', async () => {
      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books: [], jobId: 'test-job' })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.error).toBeDefined();
      expect(body.error.message).toContain('Empty books array');
    });

    it('should return 400 for non-array books', async () => {
      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books: 'not-an-array', jobId: 'test-job' })
      });

      const response = await handleBatchEnrichment(request, mockEnv, mockCtx);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.error).toBeDefined();
      expect(body.error.message).toContain('Invalid books array');
    });
  });

  describe('Background processing', () => {
    it('should trigger background processing via ctx.waitUntil', async () => {
      const books = [
        { title: 'Test Book', author: 'Test Author', isbn: '1234567890' }
      ];
      const jobId = 'test-job';

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books, jobId })
      });

      await handleBatchEnrichment(request, mockEnv, mockCtx);

      // Verify ctx.waitUntil was called (background processing started)
      expect(mockCtx.waitUntil).toHaveBeenCalledTimes(1);
      expect(mockCtx.waitUntil).toHaveBeenCalledWith(expect.any(Promise));
    });

    it('should get Durable Object stub for the jobId', async () => {
      const books = [{ title: 'Test', author: 'Author', isbn: null }];
      const jobId = 'my-unique-job-id';

      const request = new Request('http://localhost/api/enrichment/batch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ books, jobId })
      });

      await handleBatchEnrichment(request, mockEnv, mockCtx);

      // Verify DO stub was retrieved with correct jobId
      expect(mockEnv.PROGRESS_WEBSOCKET_DO.idFromName).toHaveBeenCalledWith(jobId);
      expect(mockEnv.PROGRESS_WEBSOCKET_DO.get).toHaveBeenCalled();
    });
  });
});
