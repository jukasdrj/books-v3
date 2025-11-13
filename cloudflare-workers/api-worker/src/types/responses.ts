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
 * Response metadata included in every response (legacy)
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
 * Response metadata for new envelope format
 */
export interface ResponseMetadata {
  timestamp: string; // ISO 8601
  traceId?: string; // for distributed tracing
  processingTime?: number; // milliseconds
  provider?: DataProvider;
  cached?: boolean;
}

/**
 * API Error structure
 */
export interface ApiError {
  message: string;
  code?: string;
  details?: any;
}

/**
 * Universal response envelope (new format)
 * Used for all /v1/* endpoints requiring standardized responses
 */
export interface ResponseEnvelope<T> {
  data: T | null;
  metadata: ResponseMetadata;
  error?: ApiError;
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
  status?: number; // Optional HTTP status code (Issue #398)
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
  editions: EditionDTO[];
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
// AI PIPELINE RESPONSE TYPES (Phase 2 - Canonical API Contract)
// ============================================================================

/**
 * Bookshelf Scan Initialization Response
 * Used by: POST /api/scan-bookshelf/batch
 */
export interface BookshelfScanInitResponse {
  jobId: string;
  token: string; // WebSocket authentication token
  totalPhotos: number;
  status: 'started' | 'processing';
}

/**
 * BoundingBox - Rectangle coordinates for book spine in image
 */
export interface BoundingBox {
  x: number;      // X coordinate (0.0-1.0, normalized)
  y: number;      // Y coordinate (0.0-1.0, normalized)
  width: number;  // Width (0.0-1.0, normalized)
  height: number; // Height (0.0-1.0, normalized)
}

/**
 * DetectedBookDTO - Book detected by AI bookshelf scan
 *
 * Hybrid structure: flat fields for simple data, nested enrichment for canonical DTOs.
 * Used in WebSocket completion messages (AIScanCompletePayload).
 */
export interface DetectedBookDTO {
  title?: string;
  author?: string;
  isbn?: string;
  confidence?: number;  // 0.0-1.0 (AI confidence score)
  boundingBox?: BoundingBox;
  enrichmentStatus?: 'pending' | 'success' | 'not_found' | 'error';

  // Flattened edition fields (not nested) - DEPRECATED, use enrichment below
  coverUrl?: string;
  publisher?: string;
  publicationYear?: number;

  // Nested enrichment data (canonical DTOs) - Added Nov 2025 to fix enrichment loss
  enrichment?: {
    status: 'success' | 'not_found' | 'error';
    work?: WorkDTO;
    editions?: EditionDTO[];
    authors?: AuthorDTO[];
    provider?: string;
    cachedResult?: boolean;
    error?: string;
  };
}

/**
 * CSV Import Initialization Response
 * Used by: POST /api/import/csv-gemini
 */
export interface CSVImportInitResponse {
  jobId: string;
  token: string; // WebSocket authentication token
}

/**
 * ParsedBookDTO - Book parsed from CSV file
 */
export interface ParsedBookDTO {
  title: string;
  author: string;
  isbn?: string;
}

/**
 * Enrichment Job Initialization Response
 * Used by: POST /api/enrichment/start
 */
export interface EnrichmentJobInitResponse {
  success: boolean;
  processedCount: number;
  totalCount: number;
  token: string; // WebSocket authentication token
}

/**
 * EnrichedBookDTO - Book with enrichment data from external providers
 *
 * Flattened structure (no nested objects) for iOS Codable parsing.
 * Used in WebSocket completion messages (EnrichmentCompletePayload).
 */
export interface EnrichedBookDTO {
  title: string;
  author?: string;
  isbn?: string;
  success: boolean; // true if enrichment found data, false otherwise
  error?: string;

  // Nested enrichment data (matches iOS EnrichedBookPayload)
  enriched?: {
    work: WorkDTO;
    edition?: EditionDTO;
    authors: AuthorDTO[];
  };
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Create success response object (legacy format)
 * Returns SuccessResponse<T> object, not Response
 */
export function createSuccessResponseObject<T>(
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
 * Create error response object (legacy format)
 * Returns ErrorResponse object, not Response
 */
export function createErrorResponseObject(
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
