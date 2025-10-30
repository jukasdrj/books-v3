// tests/canonical-enrichment.test.js
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { unstable_dev } from 'wrangler';

describe('Canonical Enrichment Format', () => {
  let worker;

  beforeAll(async () => {
    worker = await unstable_dev('src/index.js', {
      experimental: { disableExperimentalWarning: true }
    });
  });

  afterAll(async () => {
    await worker.stop();
  });

  // NOTE: These tests require Google Books API secret which isn't available in test environment
  // Manual validation required with: npm run dev + curl commands
  it.skip('should return canonical WorkDTO/EditionDTO format from v1 search', async () => {
    // Manual test: curl "http://localhost:8787/v1/search/title?q=1984" | jq
    // Expected: { success: true, data: { works: [WorkDTO], authors: [AuthorDTO] }, meta: {...} }
  });

  it.skip('should return canonical format from v1 ISBN search', async () => {
    // Manual test: curl "http://localhost:8787/v1/search/isbn?isbn=9780451524935" | jq
    // Expected: WorkDTO with googleBooksVolumeIDs array
  });

  it.skip('should return canonical format from v1 advanced search', async () => {
    // Manual test: curl "http://localhost:8787/v1/search/advanced?title=1984&author=Orwell" | jq
    // Expected: { works: [WorkDTO], authors: [AuthorDTO] }
  });

  // TODO: Full WebSocket testing requires mocking ProgressWebSocketDO
  // For now, validate structure manually with curl + wscat
  // Manual test: npm run dev, then wscat -c ws://localhost:8787/ws/progress?jobId=test
  it.skip('should return canonical format from enrichment WebSocket', async () => {
    // Start enrichment job
    const jobId = crypto.randomUUID();
    const response = await worker.fetch('http://localhost/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        workIds: ['isbn:9780451524935']  // 1984 by George Orwell
      })
    });

    expect(response.status).toBe(202);

    // WebSocket testing requires manual validation with wscat
    // Expected structure: { works: [WorkDTO], editions: [EditionDTO], authors: [AuthorDTO] }
    // NOT: { enrichedWorks: [GoogleBooksItem] }
  });

  it.skip('should return canonical format from AI bookshelf scanning', async () => {
    // Upload test bookshelf image
    const jobId = crypto.randomUUID();

    // WebSocket testing requires manual validation
    // Expected: { works, editions, authors, detections, metadata }
  });
});
