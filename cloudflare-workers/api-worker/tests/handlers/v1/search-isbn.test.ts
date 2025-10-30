import { describe, it, expect } from 'vitest';
import { handleSearchISBN } from '../../../src/handlers/v1/search-isbn.js';

describe('GET /v1/search/isbn', () => {
  it('should return canonical response structure', async () => {
    // Note: Using fake API key, so we expect error response
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
    };

    const response = await handleSearchISBN('9780451524935', mockEnv);

    // Should return proper envelope structure even on error
    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
    expect(response.meta.timestamp).toBeDefined();
    expect(response.meta.processingTime).toBeTypeOf('number');

    // With fake key, we expect error
    if (!response.success) {
      expect(response.error).toBeDefined();
      expect(response.error.message).toBeDefined();
      expect(response.error.code).toBe('PROVIDER_ERROR');
    }
  });

  it('should return error for invalid ISBN', async () => {
    const mockEnv = {};

    const response = await handleSearchISBN('invalid-isbn', mockEnv);

    expect(response.success).toBe(false);
    if (!response.success) {
      expect(response.error.code).toBe('INVALID_ISBN');
      expect(response.error.message).toContain('valid ISBN');
      expect(response.meta.timestamp).toBeDefined();
    }
  });

  it('should return error for empty ISBN', async () => {
    const mockEnv = {};

    const response = await handleSearchISBN('', mockEnv);

    expect(response.success).toBe(false);
    if (!response.success) {
      expect(response.error.code).toBe('INVALID_ISBN');
      expect(response.error.message).toContain('required');
      expect(response.meta.timestamp).toBeDefined();
    }
  });
});
