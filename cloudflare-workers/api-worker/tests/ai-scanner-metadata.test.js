/**
 * AI Scanner Metadata Tests
 *
 * Verifies that completion metadata includes the AI model name used.
 * This test reproduces the bug where providerParam is undefined.
 *
 * Run with: npm test -- ai-scanner-metadata.test.js
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { processBookshelfScan } from '../src/services/ai-scanner.js';

describe('AI Scanner Metadata', () => {
  let mockEnv;
  let mockDoStub;
  let progressUpdates;

  beforeEach(() => {
    progressUpdates = [];

    mockEnv = {
      GEMINI_API_KEY: 'test-api-key-123',
      CONFIDENCE_THRESHOLD: '0.6',
      BOOKS_API_PROXY: {
        fetch: async () => new Response(JSON.stringify({
          isbn: '9780743273565',
          title: 'The Great Gatsby',
          authors: [{ key: '/authors/OL123A', name: 'F. Scott Fitzgerald' }],
          covers: [123456],
          metadata: { provider: 'openlibrary' }
        }), { status: 200, headers: { 'Content-Type': 'application/json' } })
      }
    };

    mockDoStub = {
      pushProgress: async (data) => {
        progressUpdates.push(data);
      },
      closeConnection: async (code, reason) => {
        // Track close calls
      }
    };
  });

  it('should include model name in completion metadata', async () => {
    // Mock Gemini API response
    global.fetch = vi.fn(async (url) => {
      if (url.includes('generativelanguage.googleapis.com')) {
        return new Response(JSON.stringify({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify([{
                  title: 'Test Book',
                  author: 'Test Author',
                  isbn: '9780743273565',
                  format: 'hardcover',
                  confidence: 0.85,
                  boundingBox: { x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4 }
                }])
              }]
            }
          }]
        }), { status: 200 });
      }
      // Enrichment API call
      return new Response(JSON.stringify({
        items: [{
          isbn: '9780743273565',
          title: 'Test Book',
          authors: [{ name: 'Test Author' }]
        }],
        provider: 'openlibrary'
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    });

    const imageData = new ArrayBuffer(1024);
    const mockRequest = { headers: new Map() };
    const jobId = 'test-job-123';

    await processBookshelfScan(jobId, imageData, mockRequest, mockEnv, mockDoStub);

    // Find completion update (progress === 1.0)
    const completionUpdate = progressUpdates.find(u => u.progress === 1.0);

    expect(completionUpdate).toBeDefined();
    expect(completionUpdate.result).toBeDefined();
    expect(completionUpdate.result.metadata).toBeDefined();
    expect(completionUpdate.result.metadata.modelUsed).toBe('gemini-2.0-flash-exp');
  });
});
