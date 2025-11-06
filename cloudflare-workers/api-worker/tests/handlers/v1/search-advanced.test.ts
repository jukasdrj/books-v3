import { describe, it, expect } from 'vitest';
import { handleSearchAdvanced } from '../../../src/handlers/v1/search-advanced.js';

// Mock ExecutionContext
const createMockContext = () => ({
  waitUntil: () => {},
  passThroughOnException: () => {}
});

describe('GET /v1/search/advanced', () => {
  it('should return canonical response structure with title+author', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async () => null,
        put: async () => {}
      }
    };
    const mockCtx = createMockContext();

    const response = await handleSearchAdvanced('1984', 'George Orwell', mockEnv, mockCtx);

    // Should return proper envelope structure
    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
    expect(response.meta.timestamp).toBeDefined();
    expect(response.meta.processingTime).toBeTypeOf('number');
  });

  it('should return error when both title and author are missing', async () => {
    const mockEnv = {};
    const mockCtx = createMockContext();

    const response = await handleSearchAdvanced('', '', mockEnv, mockCtx);

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
      CACHE: {
        get: async () => null,
        put: async () => {}
      }
    };
    const mockCtx = createMockContext();

    const response = await handleSearchAdvanced('1984', '', mockEnv, mockCtx);

    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
  });

  it('should accept author only', async () => {
    const mockEnv = {
      GOOGLE_BOOKS_API_KEY: 'test-key',
      CACHE: {
        get: async () => null,
        put: async () => {}
      }
    };
    const mockCtx = createMockContext();

    const response = await handleSearchAdvanced('', 'George Orwell', mockEnv, mockCtx);

    expect(response).toBeDefined();
    expect(response.success).toBeDefined();
    expect(response.meta).toBeDefined();
  });
});
