/**
 * Batch Scan Endpoint Tests
 *
 * Tests the batch bookshelf scanning endpoint that accepts multiple photos
 * and processes them sequentially with WebSocket progress updates.
 *
 * SETUP: Start dev server first
 *   cd cloudflare-workers/api-worker
 *   npm run dev
 *
 * Then run tests in separate terminal:
 *   npm test -- batch-scan.test.js
 */

import { describe, it, expect, beforeAll } from 'vitest';

describe('Batch Scan Endpoint', () => {
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

  it('accepts batch scan request with multiple images', async () => {
    const jobId = crypto.randomUUID();
    const request = {
      jobId,
      images: [
        { index: 0, data: 'base64image1...' },
        { index: 1, data: 'base64image2...' }
      ]
    };

    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request)
    });

    expect(response.status).toBe(202); // Accepted
    const body = await response.json();
    expect(body.data).toBeDefined();
    expect(body.data.jobId).toBe(jobId);
    expect(body.data.totalPhotos).toBe(2);
    expect(body.data.status).toBe('processing');
    expect(body.metadata).toBeDefined();
    expect(body.metadata.timestamp).toBeDefined();
    expect(body.error).toBeUndefined();
  });

  it('rejects batches exceeding 5 photos', async () => {
    const jobId = crypto.randomUUID();
    const images = Array.from({ length: 6 }, (_, i) => ({
      index: i,
      data: 'base64image...'
    }));

    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId, images })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('maximum 5 photos');
    expect(body.error.code).toBe('E_INVALID_IMAGES');
    expect(body.metadata.timestamp).toBeDefined();
  });

  it('rejects request without jobId', async () => {
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        images: [{ index: 0, data: 'base64image...' }]
      })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('jobId');
    expect(body.error.code).toBe('E_INVALID_REQUEST');
    expect(body.metadata.timestamp).toBeDefined();
  });

  it('rejects request without images array', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('images array required');
    expect(body.error.code).toBe('E_INVALID_REQUEST');
    expect(body.metadata.timestamp).toBeDefined();
  });

  it('rejects empty images array', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId, images: [] })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('At least one image required');
    expect(body.error.code).toBe('E_INVALID_IMAGES');
    expect(body.metadata.timestamp).toBeDefined();
  });

  it('validates image structure (index and data fields)', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        images: [{ index: 0 }] // Missing data field
      })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error.message).toContain('index and data fields');
    expect(body.error.code).toBe('E_INVALID_IMAGES');
    expect(body.metadata.timestamp).toBeDefined();
  });

  it('includes CORS headers', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        images: [{ index: 0, data: 'base64image...' }]
      })
    });

    expect(response.headers.get('access-control-allow-origin')).toBe('*');
  });
});

describe('Batch State Management (Durable Object)', () => {
  const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:8787';

  it('initializes batch job with photo array', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Create Durable Object stub
    const response = await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 3,
        status: 'uploading'
      })
    });

    expect(response.status).toBe(200);
    const initResult = await response.json();
    expect(initResult.success).toBe(true);

    // Fetch state to verify initialization
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    expect(stateResponse.status).toBe(200);

    const state = await stateResponse.json();
    expect(state.type).toBe('batch');
    expect(state.totalPhotos).toBe(3);
    expect(state.photos).toHaveLength(3);
    expect(state.photos[0].status).toBe('queued');
    expect(state.photos[0].index).toBe(0);
    expect(state.photos[1].status).toBe('queued');
    expect(state.photos[2].status).toBe('queued');
    expect(state.overallStatus).toBe('uploading');
    expect(state.currentPhoto).toBeNull();
    expect(state.totalBooksFound).toBe(0);
    expect(state.cancelRequested).toBe(false);
  });

  it('updates individual photo progress', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 2,
        status: 'processing'
      })
    });

    // Update photo 0 to processing
    const updateResponse = await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 0,
        status: 'processing'
      })
    });

    expect(updateResponse.status).toBe(200);

    // Verify state
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    const state = await stateResponse.json();

    expect(state.photos[0].status).toBe('processing');
    expect(state.photos[1].status).toBe('queued');
    expect(state.currentPhoto).toBe(0);
  });

  it('tracks books found per photo', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 2,
        status: 'processing'
      })
    });

    // Update photo 0 with books found
    await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 0,
        status: 'complete',
        booksFound: 5
      })
    });

    // Verify state
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    const state = await stateResponse.json();

    expect(state.photos[0].booksFound).toBe(5);
    expect(state.totalBooksFound).toBe(5);
  });

  it('accumulates total books across photos', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 3,
        status: 'processing'
      })
    });

    // Complete photos with different book counts
    await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 0,
        status: 'complete',
        booksFound: 5
      })
    });

    await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 1,
        status: 'complete',
        booksFound: 8
      })
    });

    await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 2,
        status: 'complete',
        booksFound: 3
      })
    });

    // Verify state
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    const state = await stateResponse.json();

    expect(state.totalBooksFound).toBe(16); // 5 + 8 + 3
  });

  it('handles photo errors', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 2,
        status: 'processing'
      })
    });

    // Update photo 0 with error
    await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 0,
        status: 'error',
        error: 'AI processing failed'
      })
    });

    // Verify state
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    const state = await stateResponse.json();

    expect(state.photos[0].status).toBe('error');
    expect(state.photos[0].error).toBe('AI processing failed');
  });

  it('completes batch with final results', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 2,
        status: 'processing'
      })
    });

    // Complete batch
    const completeResponse = await fetch(`${BASE_URL}/test/do/complete-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        status: 'complete',
        totalBooks: 12,
        photoResults: [
          { index: 0, status: 'complete', booksFound: 7 },
          { index: 1, status: 'complete', booksFound: 5 }
        ],
        books: [] // Would contain actual book data
      })
    });

    expect(completeResponse.status).toBe(200);

    // Verify state
    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    const state = await stateResponse.json();

    expect(state.overallStatus).toBe('complete');
    expect(state.totalBooksFound).toBe(12);
    expect(state.finalResults).toBeDefined();
  });

  it('checks cancellation status', async () => {
    const jobId = `test-batch-${crypto.randomUUID()}`;

    // Initialize batch
    await fetch(`${BASE_URL}/test/do/init-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        totalPhotos: 2,
        status: 'processing'
      })
    });

    // Check initial cancellation status
    const checkResponse1 = await fetch(`${BASE_URL}/test/do/is-canceled?jobId=${jobId}`);
    const result1 = await checkResponse1.json();
    expect(result1.canceled).toBe(false);

    // Request cancellation (will be tested in Task 6, just verify endpoint exists)
    const cancelResponse = await fetch(`${BASE_URL}/test/do/cancel-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId })
    });

    expect(cancelResponse.status).toBe(200);

    // Check cancellation status after cancel
    const checkResponse2 = await fetch(`${BASE_URL}/test/do/is-canceled?jobId=${jobId}`);
    const result2 = await checkResponse2.json();
    expect(result2.canceled).toBe(true);
  });

  it('returns 404 for non-existent job state', async () => {
    const jobId = `nonexistent-${crypto.randomUUID()}`;

    const stateResponse = await fetch(`${BASE_URL}/test/do/get-state?jobId=${jobId}`);
    expect(stateResponse.status).toBe(404);
  });

  it('returns 404 when updating photo for non-existent batch', async () => {
    const jobId = `nonexistent-${crypto.randomUUID()}`;

    const updateResponse = await fetch(`${BASE_URL}/test/do/update-photo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        photoIndex: 0,
        status: 'processing'
      })
    });

    expect(updateResponse.status).toBe(404);
  });
});
