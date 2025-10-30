/**
 * API Response Envelopes
 *
 * Universal structure for all API responses.
 * Discriminated union enables TypeScript type narrowing.
 */

import type { DataProvider, ApiErrorCode } from './enums.js';
import type { WorkDTO, EditionDTO, AuthorDTO } from './canonical.js';

// ============================================================================
// RESPONSE ENVELOPE
// ============================================================================

/**
 * Response metadata included in every response
 */
export interface ResponseMeta {
  timestamp: string; // ISO 8601
  processingTime?: number; // milliseconds
  provider?: DataProvider;
  cached?: boolean;
  cacheAge?: number; // seconds since cached
  requestId?: string; // for distributed tracing (future)
}

/**
 * Success response envelope
 */
export interface SuccessResponse<T> {
  success: true;
  data: T;
  meta: ResponseMeta;
}

/**
 * Error response envelope
 */
export interface ErrorResponse {
  success: false;
  error: {
    message: string;
    code?: ApiErrorCode;
    details?: any;
  };
  meta: ResponseMeta;
}

/**
 * Discriminated union for all responses
 */
export type ApiResponse<T> = SuccessResponse<T> | ErrorResponse;

// ============================================================================
// DOMAIN-SPECIFIC RESPONSE TYPES
// ============================================================================

/**
 * Book search response
 * Used by: /v1/search/title, /v1/search/isbn, /v1/search/advanced
 */
export interface BookSearchResponse {
  works: WorkDTO[];
  authors: AuthorDTO[];
  totalResults?: number; // for pagination (future)
}

/**
 * Enrichment job response
 * Used by: /v1/api/enrichment/start
 */
export interface EnrichmentJobResponse {
  jobId: string;
  queuedCount: number;
  estimatedDuration?: number; // seconds
  websocketUrl: string;
}

/**
 * Bookshelf scan response
 * Used by: /v1/api/scan-bookshelf, /v1/api/scan-bookshelf/batch
 */
export interface BookshelfScanResponse {
  jobId: string;
  detectedBooks: {
    work: WorkDTO;
    edition: EditionDTO;
    confidence: number; // 0.0-1.0
  }[];
  websocketUrl: string;
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Create success response
 */
export function createSuccessResponse<T>(
  data: T,
  meta: Partial<ResponseMeta> = {}
): SuccessResponse<T> {
  return {
    success: true,
    data,
    meta: {
      timestamp: new Date().toISOString(),
      ...meta,
    },
  };
}

/**
 * Create error response
 */
export function createErrorResponse(
  message: string,
  code?: ApiErrorCode,
  details?: any,
  meta: Partial<ResponseMeta> = {}
): ErrorResponse {
  return {
    success: false,
    error: { message, code, details },
    meta: {
      timestamp: new Date().toISOString(),
      ...meta,
    },
  };
}
