/**
 * Error Status Mapping Tests
 *
 * Validates correct HTTP status code mapping for API error codes.
 * Related: GitHub Issue #398
 */

import { describe, test, expect } from 'vitest';
import { statusFromError, type HttpStatus } from '../../src/utils/error-status.js';
import type { ErrorResponse } from '../../src/types/responses.js';

describe('Error Status Mapping', () => {
  describe('statusFromError - Standard Error Codes', () => {
    test('maps INVALID_QUERY to 400 Bad Request', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Query parameter is empty',
          code: 'INVALID_QUERY'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(400);
    });

    test('maps INVALID_ISBN to 400 Bad Request', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Malformed ISBN format',
          code: 'INVALID_ISBN'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(400);
    });

    test('maps NOT_FOUND to 404 Not Found', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Book not found in any provider',
          code: 'NOT_FOUND'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(404);
    });

    test('maps INTERNAL_ERROR to 500 Internal Server Error', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Unexpected server error',
          code: 'INTERNAL_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(500);
    });
  });

  describe('statusFromError - Provider Errors (Nuanced)', () => {
    test('maps timeout PROVIDER_ERROR to 503 Service Unavailable', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider timeout after 30 seconds',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(503);
    });

    test('maps unavailable PROVIDER_ERROR to 503', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider service unavailable',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(503);
    });

    test('maps rate limit PROVIDER_ERROR to 503', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Rate limit exceeded',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(503);
    });

    test('maps "too many requests" PROVIDER_ERROR to 503', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Too many requests to provider',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(503);
    });

    test('maps generic PROVIDER_ERROR to 502 Bad Gateway', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider returned invalid data',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(502);
    });

    test('checks details field for timeout keywords', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider error',
          code: 'PROVIDER_ERROR',
          details: { error: 'Connection timeout' }
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(503);
    });
  });

  describe('statusFromError - Edge Cases', () => {
    test('returns 500 for error without code', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Unexpected error'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(500);
    });

    test('returns 500 for unknown error code', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Some error',
          code: 'UNKNOWN_CODE' as any
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status = statusFromError(error);
      expect(status).toBe(500);
    });

    test('returns 500 for non-ErrorResponse object', () => {
      const status = statusFromError({ random: 'object' });
      expect(status).toBe(500);
    });

    test('returns 500 for null/undefined', () => {
      expect(statusFromError(null)).toBe(500);
      expect(statusFromError(undefined)).toBe(500);
    });

    test('uses explicit status field if present', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Custom error',
          code: 'INVALID_QUERY'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' },
        status: 418 // I'm a teapot (explicit override)
      };

      const status = statusFromError(error);
      expect(status).toBe(418);
    });
  });

  describe('Type Safety - HttpStatus Union', () => {
    test('statusFromError returns valid HttpStatus type', () => {
      const error: ErrorResponse = {
        success: false,
        error: {
          message: 'Test',
          code: 'NOT_FOUND'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      const status: HttpStatus = statusFromError(error);

      // Verify status is one of the valid values
      const validStatuses: HttpStatus[] = [400, 404, 500, 502, 503];
      expect(validStatuses).toContain(status);
    });
  });

  describe('Case Insensitivity', () => {
    test('matches keywords case-insensitively in message', () => {
      const errorCaps: ErrorResponse = {
        success: false,
        error: {
          message: 'PROVIDER TIMEOUT OCCURRED',
          code: 'PROVIDER_ERROR'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      expect(statusFromError(errorCaps)).toBe(503);
    });

    test('matches keywords case-insensitively in details', () => {
      const errorMixed: ErrorResponse = {
        success: false,
        error: {
          message: 'Provider error',
          code: 'PROVIDER_ERROR',
          details: 'Rate Limit Exceeded'
        },
        meta: { timestamp: '2025-11-12T00:00:00Z' }
      };

      expect(statusFromError(errorMixed)).toBe(503);
    });
  });
});
