import { describe, test, expect } from 'vitest';
import {
  createUnifiedSuccessResponse,
  createUnifiedErrorResponse,
  adaptToUnifiedEnvelope
} from '../../src/utils/envelope-helpers.js';
import type { SuccessResponse, ErrorResponse } from '../../src/types/responses.js';

describe('Envelope Helpers', () => {
  describe('createUnifiedSuccessResponse', () => {
    test('includes all metadata fields', () => {
      const data = { works: [], editions: [], authors: [] };
      const meta = {
        timestamp: '2025-11-12T00:00:00Z',
        processingTime: 150,
        provider: 'google',
        cached: true
      };

      const result = createUnifiedSuccessResponse(data, meta);

      expect(result.data).toBe(data);
      expect(result.metadata.timestamp).toBe(meta.timestamp);
      expect(result.metadata.processingTime).toBe(150);
      expect(result.metadata.provider).toBe('google');
      expect(result.metadata.cached).toBe(true);
      expect(result.error).toBeUndefined();
    });

    test('handles partial metadata', () => {
      const data = { works: [] };
      const meta = { timestamp: '2025-11-12T00:00:00Z' };

      const result = createUnifiedSuccessResponse(data, meta);

      expect(result.data).toBe(data);
      expect(result.metadata.timestamp).toBe(meta.timestamp);
      expect(result.metadata.processingTime).toBeUndefined();
      expect(result.metadata.provider).toBeUndefined();
      expect(result.metadata.cached).toBeUndefined();
    });
  });

  describe('createUnifiedErrorResponse', () => {
    test('includes error details', () => {
      const result = createUnifiedErrorResponse(
        'Not found',
        'E_NOT_FOUND',
        { suggestion: 'Try different query' }
      );

      expect(result.data).toBeNull();
      expect(result.metadata.timestamp).toBeDefined();
      expect(result.error?.message).toBe('Not found');
      expect(result.error?.code).toBe('E_NOT_FOUND');
      expect(result.error?.details).toEqual({ suggestion: 'Try different query' });
    });

    test('handles minimal error', () => {
      const result = createUnifiedErrorResponse('Internal error');

      expect(result.data).toBeNull();
      expect(result.error?.message).toBe('Internal error');
      expect(result.error?.code).toBeUndefined();
      expect(result.error?.details).toBeUndefined();
    });
  });

  describe('adaptToUnifiedEnvelope', () => {
    test('preserves legacy format when flag OFF', async () => {
      const legacyResponse: SuccessResponse<any> = {
        success: true,
        data: { works: [], editions: [], authors: [] },
        meta: {
          timestamp: '2025-11-12T00:00:00Z',
          provider: 'google',
          cached: false
        }
      };

      const response = adaptToUnifiedEnvelope(legacyResponse, false);
      const body = await response.json();

      expect(body).toHaveProperty('success');
      expect(body.success).toBe(true);
      expect(body).toHaveProperty('data');
      expect(body).toHaveProperty('meta');
      expect(body.data.works).toBeDefined();
    });

    test('returns unified format when flag ON', async () => {
      const legacyResponse: SuccessResponse<any> = {
        success: true,
        data: { works: [], editions: [], authors: [] },
        meta: {
          timestamp: '2025-11-12T00:00:00Z',
          provider: 'google',
          cached: false
        }
      };

      const response = adaptToUnifiedEnvelope(legacyResponse, true);
      const body = await response.json();

      // Verify unified envelope structure (error field may be omitted for success)
      expect(body).toHaveProperty('data');
      expect(body).toHaveProperty('metadata');
      expect(body.data.works).toBeDefined();
      expect(body.metadata.timestamp).toBe('2025-11-12T00:00:00Z');
      expect(body.metadata.provider).toBe('google');

      // Error field is undefined/omitted for success responses (optional field)
      expect(body.error).toBeUndefined();
    });

    test('handles legacy error response', async () => {
      const legacyResponse: ErrorResponse = {
        success: false,
        error: {
          message: 'Invalid query',
          code: 'E_INVALID_QUERY',
          details: { field: 'title' }
        },
        meta: {
          timestamp: '2025-11-12T00:00:00Z'
        }
      };

      const response = adaptToUnifiedEnvelope(legacyResponse, true);
      const body = await response.json();

      expect(body).toHaveProperty('data');
      expect(body.data).toBeNull();
      expect(body).toHaveProperty('error');
      expect(body.error.message).toBe('Invalid query');
      expect(body.error.code).toBe('E_INVALID_QUERY');
    });

    test('maps error codes to correct HTTP status (Issue #398)', async () => {
      // Test INVALID_QUERY → 400
      const invalidQuery: ErrorResponse = {
        success: false,
        error: {
          message: 'Invalid query',
          code: 'INVALID_QUERY'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };
      expect(adaptToUnifiedEnvelope(invalidQuery, true).status).toBe(400);

      // Test NOT_FOUND → 404
      const notFound: ErrorResponse = {
        success: false,
        error: {
          message: 'Not found',
          code: 'NOT_FOUND'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };
      expect(adaptToUnifiedEnvelope(notFound, true).status).toBe(404);

      // Test INTERNAL_ERROR → 500
      const internalError: ErrorResponse = {
        success: false,
        error: {
          message: 'Internal error',
          code: 'INTERNAL_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };
      expect(adaptToUnifiedEnvelope(internalError, true).status).toBe(500);

      // Test PROVIDER_ERROR (timeout) → 503
      const providerTimeout: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider timeout',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };
      expect(adaptToUnifiedEnvelope(providerTimeout, true).status).toBe(503);
    });
  });
});
