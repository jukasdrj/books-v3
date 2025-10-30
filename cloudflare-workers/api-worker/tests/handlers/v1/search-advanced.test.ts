import { describe, it, expect } from 'vitest';
import { handleSearchAdvanced } from '../../../src/handlers/v1/search-advanced.js';

describe('GET /v1/search/advanced', () => {
  it('should return canonical response structure with title+author', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
    };

    const response = await handleSearchAdvanced('1984', 'George Orwell', mockEnv);

    // Should return proper envelope structure
    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
    expect(response.meta.timestamp).toBeDefined();
    expect(response.meta.processingTime).toBeTypeOf('number');
  });

  it('should return error when both title and author are missing', async () => {
    const mockEnv = {};

    const response = await handleSearchAdvanced('', '', mockEnv);

    expect(response.success).toBe(false);
    if (!response.success) {
      expect(response.error.code).toBe('INVALID_QUERY');
      expect(response.error.message).toContain('title or author');
      expect(response.meta.timestamp).toBeDefined();
    }
  });

  it('should accept title only', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
    };

    const response = await handleSearchAdvanced('1984', '', mockEnv);

    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
  });

  it('should accept author only', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
    };

    const response = await handleSearchAdvanced('', 'George Orwell', mockEnv);

    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
  });
});
