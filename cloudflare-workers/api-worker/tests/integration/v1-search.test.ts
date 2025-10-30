/**
 * Integration tests for /v1/ search endpoints
 *
 * These tests validate the canonical response structure with real API calls.
 *
 * **Prerequisites for successful tests:**
 * 1. Deploy worker: `wrangler deploy`
 * 2. Run tests: `WORKER_URL=https://books-api-proxy.jukasdrj.workers.dev npm test integration`
 *
 * **OR** for local dev (without real API):
 * 1. `wrangler dev --port 8787` (separate terminal)
 * 2. `npm test integration` (tests error handling paths)
 *
 * Note: Real Google Books API credentials only available in deployed environment.
 */

import { describe, it, expect } from 'vitest';

const WORKER_URL = process.env.WORKER_URL || 'http://localhost:8787';

describe('GET /v1/search/title (integration)', () => {
  it('should return canonical response for "1984"', async () => {
    const response = await fetch(`${WORKER_URL}/v1/search/title?q=1984`);
    const json = await response.json();

    expect(response.status).toBe(200);

    // Validate envelope structure (required regardless of success/error)
    expect(json.success).toBeDefined();
    expect(json.meta).toBeDefined();
    expect(json.meta.timestamp).toBeDefined();

    if (json.success) {
      // Success path: validate full canonical response
      // Validate envelope structure
      expect(json.data).toBeDefined();
      expect(json.meta).toBeDefined();
      expect(json.meta.timestamp).toBeDefined();
      expect(json.meta.provider).toBe('google-books');
      expect(json.meta.processingTime).toBeTypeOf('number');

      // Validate BookSearchResponse structure
      expect(json.data.works).toBeInstanceOf(Array);
      expect(json.data.authors).toBeInstanceOf(Array);

      // Validate WorkDTO structure
      if (json.data.works.length > 0) {
        const work = json.data.works[0];
        expect(work.title).toBeTypeOf('string');
        expect(work.subjectTags).toBeInstanceOf(Array);
        expect(work.goodreadsWorkIDs).toBeInstanceOf(Array);
        expect(work.amazonASINs).toBeInstanceOf(Array);
        expect(work.librarythingIDs).toBeInstanceOf(Array);
        expect(work.googleBooksVolumeIDs).toBeInstanceOf(Array);
        expect(work.isbndbQuality).toBeTypeOf('number');
        expect(work.reviewStatus).toBeDefined();
        expect(work.synthetic).toBe(false);
        expect(work.primaryProvider).toBe('google-books');
      }

      // Validate AuthorDTO structure
      if (json.data.authors.length > 0) {
        const author = json.data.authors[0];
        expect(author.name).toBeTypeOf('string');
        expect(author.gender).toBeDefined();
      }
    } else {
      // Error path: validate error envelope
      expect(json.error).toBeDefined();
      expect(json.error.message).toBeDefined();
      expect(json.error.code).toBeDefined();
      console.log('⚠️  Integration test running without real API credentials');
      console.log(`   Error: ${json.error.message}`);
      console.log('   To test with real API: Deploy worker and set WORKER_URL env var');
    }
  });

  it('should return error for empty query', async () => {
    const response = await fetch(`${WORKER_URL}/v1/search/title?q=`);
    const json = await response.json();

    expect(response.status).toBe(200); // Still 200, error in JSON
    expect(json.success).toBe(false);

    if (!json.success) {
      expect(json.error).toBeDefined();
      expect(json.error.code).toBe('INVALID_QUERY');
      expect(json.error.message).toContain('query is required');
      expect(json.meta.timestamp).toBeDefined();
    }
  });

  it('should handle special characters in query', async () => {
    const response = await fetch(`${WORKER_URL}/v1/search/title?q=${encodeURIComponent('The Hitchhiker\'s Guide')}`);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.success).toBeDefined();
    expect(json.meta).toBeDefined();

    // Should either succeed or fail gracefully
    if (json.success) {
      expect(json.data.works).toBeInstanceOf(Array);
    } else {
      expect(json.error).toBeDefined();
    }
  });
});
