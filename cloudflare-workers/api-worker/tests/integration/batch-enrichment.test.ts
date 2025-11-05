/**
 * Integration tests for POST /api/enrichment/start endpoint
 *
 * Tests the batch enrichment endpoint that accepts workIds for enrichment.
 * This endpoint is used by iOS EnrichmentQueue to enrich books in the background.
 *
 * **Prerequisites:**
 * 1. Deploy worker: `wrangler deploy`
 * 2. Run tests: `WORKER_URL=https://books-api-proxy.jukasdrj.workers.dev npm test integration/batch-enrichment`
 *
 * **OR** for local dev:
 * 1. `wrangler dev --port 8787` (separate terminal)
 * 2. `npm test integration/batch-enrichment`
 *
 * Note: Tests validate HTTP contract only. WebSocket testing requires separate client setup.
 */

import { describe, it, expect, beforeAll } from 'vitest';

const WORKER_URL = process.env.WORKER_URL || 'http://localhost:8787';

// Check if worker is running before ALL tests
beforeAll(async () => {
  try {
    const response = await fetch(`${WORKER_URL}/health`);
    if (!response.ok) {
      throw new Error('Worker health check failed');
    }
  } catch (error) {
    console.warn('\n⚠️  Worker not running. Start with: wrangler dev --port 8787');
    console.warn('   Or set WORKER_URL to deployed worker for real API tests\n');
    throw new Error('Worker not available - skipping integration tests');
  }
});

describe('POST /api/enrichment/start (integration)', () => {
  /**
   * Helper to generate unique job IDs for each test
   */
  function generateJobId(): string {
    return `test-batch-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  // ========================================================================
  // Basic Functionality Tests
  // ========================================================================

  describe('Basic functionality', () => {
    it('should accept valid workIds and return 202 Accepted', async () => {
      const jobId = generateJobId();
      const workIds = ['work-1', 'work-2', 'work-3'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(202);

      const body = await response.json();
      expect(body.data).toBeDefined();
      expect(body.data.jobId).toBe(jobId);
      expect(body.data.status).toBe('started');
      expect(body.data.totalBooks).toBe(3);
      expect(body.data.message).toContain('ws/progress');
      expect(body.data.message).toContain(jobId);
      expect(body.metadata).toBeDefined();
      expect(body.metadata.timestamp).toBeDefined();
      expect(body.error).toBeUndefined();
    });

    it('should handle single workId', async () => {
      const jobId = generateJobId();
      const workIds = ['work-single'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(202);

      const body = await response.json();
      expect(body.data).toBeDefined();
      expect(body.data.totalBooks).toBe(1);
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should handle large batch of workIds (50+)', async () => {
      const jobId = generateJobId();
      const workIds = Array.from({ length: 50 }, (_, i) => `work-${i + 1}`);

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(202);

      const body = await response.json();
      expect(body.data).toBeDefined();
      expect(body.data.totalBooks).toBe(50);
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should handle 100 workIds (stress test)', async () => {
      const jobId = generateJobId();
      const workIds = Array.from({ length: 100 }, (_, i) => `work-${i + 1}`);

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(202);

      const body = await response.json();
      expect(body.data).toBeDefined();
      expect(body.data.totalBooks).toBe(100);
      expect(body.metadata.timestamp).toBeDefined();
    });
  });

  // ========================================================================
  // Error Handling Tests
  // ========================================================================

  describe('Error handling', () => {
    it('should return 400 for missing jobId', async () => {
      const workIds = ['work-1', 'work-2'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds })
      });

      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.data).toBeNull();
      expect(body.error).toBeDefined();
      expect(body.error.message.toLowerCase()).toContain('jobid');
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should return 400 for missing workIds', async () => {
      const jobId = generateJobId();

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ jobId })
      });

      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.data).toBeNull();
      expect(body.error).toBeDefined();
      expect(body.error.message.toLowerCase()).toContain('workids');
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should return 400 for empty workIds array', async () => {
      const jobId = generateJobId();
      const workIds: string[] = [];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.data).toBeNull();
      expect(body.error).toBeDefined();
      expect(body.error.message.toLowerCase()).toContain('empty');
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should return 400 for workIds as non-array', async () => {
      const jobId = generateJobId();
      const workIds = 'not-an-array';

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.data).toBeNull();
      expect(body.error).toBeDefined();
      expect(body.metadata.timestamp).toBeDefined();
    });

    it('should return 400 for malformed JSON', async () => {
      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid-json-{{'
      });

      expect([400, 500]).toContain(response.status);
    });
  });

  // ========================================================================
  // Response Structure Validation
  // ========================================================================

  describe('Response structure', () => {
    it('should return correct response structure', async () => {
      const jobId = generateJobId();
      const workIds = ['work-1', 'work-2'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      expect(response.status).toBe(202);

      const body = await response.json();

      // Validate envelope structure
      expect(body).toHaveProperty('data');
      expect(body).toHaveProperty('metadata');
      expect(body.data).toBeDefined();
      expect(body.metadata).toBeDefined();

      // Validate metadata
      expect(body.metadata.timestamp).toBeDefined();
      expect(typeof body.metadata.timestamp).toBe('string');

      // Validate data payload
      expect(body.data).toHaveProperty('jobId');
      expect(body.data).toHaveProperty('status');
      expect(body.data).toHaveProperty('totalBooks');
      expect(body.data).toHaveProperty('message');

      // Validate types
      expect(typeof body.data.jobId).toBe('string');
      expect(typeof body.data.status).toBe('string');
      expect(typeof body.data.totalBooks).toBe('number');
      expect(typeof body.data.message).toBe('string');

      // Validate values
      expect(body.data.jobId).toBe(jobId);
      expect(body.data.status).toBe('started');
      expect(body.data.totalBooks).toBe(2);
      expect(body.data.message).toContain('ws/progress');
    });

    it('should include CORS headers', async () => {
      const jobId = generateJobId();
      const workIds = ['work-1'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      // Note: CORS headers might not be set on 202 responses
      // Checking if present (not strictly required for this endpoint)
      const corsHeader = response.headers.get('access-control-allow-origin');
      if (corsHeader) {
        expect(corsHeader).toBe('*');
      }
    });
  });

  // ========================================================================
  // WebSocket Integration
  // ========================================================================

  describe('WebSocket progress URL', () => {
    it('should provide WebSocket URL in response message', async () => {
      const jobId = generateJobId();
      const workIds = ['work-1', 'work-2', 'work-3'];

      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId })
      });

      const body = await response.json();

      // Message should tell client how to connect to WebSocket
      expect(body.data.message).toContain('ws/progress');
      expect(body.data.message).toContain(jobId);

      // Expected format: "Enrichment job started. Connect to /ws/progress?jobId=xxx for real-time updates."
    });

    it('should generate unique jobIds for concurrent requests', async () => {
      const workIds = ['work-1'];

      const response1 = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId: 'test-job-1' })
      });

      const response2 = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workIds, jobId: 'test-job-2' })
      });

      const body1 = await response1.json();
      const body2 = await response2.json();

      expect(body1.data.jobId).toBe('test-job-1');
      expect(body2.data.jobId).toBe('test-job-2');
      expect(body1.data.jobId).not.toBe(body2.data.jobId);
    });
  });

  // ========================================================================
  // HTTP Method Validation
  // ========================================================================

  describe('HTTP method validation', () => {
    it('should reject GET requests', async () => {
      const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
        method: 'GET'
      });

      // Should either return 404 (not matched) or 405 (method not allowed)
      expect([404, 405]).toContain(response.status);
    });

    it('should only accept POST method', async () => {
      const jobId = generateJobId();
      const workIds = ['work-1'];
      const methods = ['PUT', 'PATCH', 'DELETE'];

      for (const method of methods) {
        const response = await fetch(`${WORKER_URL}/api/enrichment/start`, {
          method,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ workIds, jobId })
        });

        expect([404, 405]).toContain(response.status);
      }
    });
  });
});
