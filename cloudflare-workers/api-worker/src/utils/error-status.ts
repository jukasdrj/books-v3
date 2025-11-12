/**
 * Error Status Mapping Utilities
 *
 * Centralized mapping of API error codes to HTTP status codes.
 * Ensures consistent error responses across all endpoints.
 *
 * Related: GitHub Issue #398
 */

import type { ApiErrorCode } from '../types/enums.js';
import type { ErrorResponse } from '../types/responses.js';

/**
 * Type-safe HTTP status codes
 * Union of literal types enforces compile-time safety
 */
export type HttpStatus = 400 | 404 | 500 | 502 | 503;

/**
 * Centralized error code to HTTP status mapping
 *
 * Mapping rationale:
 * - INVALID_QUERY, INVALID_ISBN: 400 (Bad Request) - client input errors
 * - NOT_FOUND: 404 (Not Found) - requested resource doesn't exist
 * - INTERNAL_ERROR: 500 (Internal Server Error) - unexpected server failures
 * - PROVIDER_ERROR: Handled by providerErrorStatus() for nuanced cases
 */
const ERROR_STATUS_MAP = {
  INVALID_QUERY: 400,
  INVALID_ISBN: 400,
  NOT_FOUND: 404,
  INTERNAL_ERROR: 500,
} as const satisfies Record<Exclude<ApiErrorCode, 'PROVIDER_ERROR'>, HttpStatus>;

/**
 * Determine HTTP status for provider errors with nuanced logic
 *
 * @param error - Error response object
 * @returns 503 for timeout/unavailable/rate-limit, 502 for upstream errors
 */
function providerErrorStatus(error: ErrorResponse): HttpStatus {
  const message = error.error.message.toLowerCase();

  // Convert details to string (handles objects, primitives, etc.)
  let detailsStr = '';
  if (error.error.details) {
    detailsStr = typeof error.error.details === 'object'
      ? JSON.stringify(error.error.details).toLowerCase()
      : String(error.error.details).toLowerCase();
  }

  // 503 Service Unavailable: Temporary conditions
  if (
    message.includes('timeout') ||
    message.includes('unavailable') ||
    message.includes('rate limit') ||
    message.includes('too many requests') ||
    detailsStr.includes('timeout') ||
    detailsStr.includes('rate limit')
  ) {
    return 503;
  }

  // 502 Bad Gateway: Upstream responded but with error
  return 502;
}

/**
 * Map error response to appropriate HTTP status code
 *
 * Priority:
 * 1. Explicit status field on error (if present)
 * 2. Error code mapping (ERROR_STATUS_MAP)
 * 3. Provider error logic (for PROVIDER_ERROR)
 * 4. Default 500 (unknown errors)
 *
 * @param error - Error response or unknown error object
 * @returns HTTP status code
 */
export function statusFromError(error: ErrorResponse | unknown): HttpStatus {
  // Type guard: ensure we have an ErrorResponse
  if (!error || typeof error !== 'object' || !('error' in error)) {
    return 500; // Unknown error format
  }

  const errorResponse = error as ErrorResponse;

  // 1. Explicit status (if already set)
  if (errorResponse.status) {
    return errorResponse.status;
  }

  // 2. Map via error code
  const errorCode = errorResponse.error.code;
  if (!errorCode) {
    return 500; // No error code = internal error
  }

  // 3. Provider error (nuanced logic)
  if (errorCode === 'PROVIDER_ERROR') {
    return providerErrorStatus(errorResponse);
  }

  // 4. Standard mapping
  const mappedStatus = ERROR_STATUS_MAP[errorCode as keyof typeof ERROR_STATUS_MAP];
  return mappedStatus ?? 500; // Default to 500 for unmapped codes
}
