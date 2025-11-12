/**
 * Response Envelope Helpers (Phase 3)
 *
 * Utilities for unified response envelope format migration.
 * Supports dual-format responses via feature flag.
 */

import type {
  ResponseEnvelope,
  SuccessResponse,
  ErrorResponse,
  ResponseMeta
} from '../types/responses.js';
import { statusFromError } from './error-status.js';

/**
 * Create unified success response envelope
 *
 * Transforms legacy ResponseMeta into ResponseMetadata structure.
 */
export function createUnifiedSuccessResponse<T>(
  data: T,
  meta: { timestamp: string; processingTime?: number; provider?: string; cached?: boolean }
): ResponseEnvelope<T> {
  return {
    data,
    metadata: {
      timestamp: meta.timestamp,
      processingTime: meta.processingTime,
      provider: meta.provider,
      cached: meta.cached
    },
    error: undefined as any  // Will be serialized as missing key in JSON
  };
}

/**
 * Create unified error response envelope
 *
 * Returns envelope with null data and populated error field.
 */
export function createUnifiedErrorResponse(
  message: string,
  code?: string,
  details?: any
): ResponseEnvelope<null> {
  return {
    data: null,
    metadata: {
      timestamp: new Date().toISOString()
    },
    error: {
      message,
      code,
      details
    }
  };
}

/**
 * Adapt legacy response to unified envelope based on feature flag
 *
 * @param legacyResponse - Discriminated union response (SuccessResponse | ErrorResponse)
 * @param useUnifiedEnvelope - Feature flag value (ENABLE_UNIFIED_ENVELOPE)
 * @returns Response object with appropriate format
 */
export function adaptToUnifiedEnvelope<T>(
  legacyResponse: SuccessResponse<T> | ErrorResponse,
  useUnifiedEnvelope: boolean
): Response {
  // Feature flag OFF: Return legacy format unchanged
  if (!useUnifiedEnvelope) {
    return Response.json(legacyResponse);
  }

  // Feature flag ON: Transform to unified envelope
  if (legacyResponse.success) {
    // Success response: Transform data + meta
    return Response.json(createUnifiedSuccessResponse(
      legacyResponse.data,
      legacyResponse.meta
    ));
  } else {
    // Error response: Transform error + meta
    return Response.json(
      createUnifiedErrorResponse(
        legacyResponse.error.message,
        legacyResponse.error.code,
        legacyResponse.error.details
      ),
      { status: statusFromError(legacyResponse) }
    );
  }
}
