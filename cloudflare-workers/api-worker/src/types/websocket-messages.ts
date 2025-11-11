/**
 * Unified WebSocket Message Schema (v1.0.0)
 *
 * Provides consistent message structure across all pipelines:
 * - batch_enrichment (background book metadata enrichment)
 * - csv_import (Gemini-powered CSV parsing)
 * - ai_scan (bookshelf image scanning with Gemini)
 *
 * Design Principles:
 * 1. Discriminated unions for type safety
 * 2. Version field for schema evolution
 * 3. Pipeline field for multi-job tracking
 * 4. Timestamp for client-side latency monitoring
 * 5. Backward compatibility via optional fields
 */

// =============================================================================
// Core Types & Enums
// =============================================================================

/**
 * Message type discriminator
 */
export type MessageType =
  | "job_started"
  | "job_progress"
  | "job_complete"
  | "error"
  | "ping"
  | "pong";

/**
 * Pipeline identifier for job source tracking
 */
export type PipelineType =
  | "batch_enrichment"
  | "csv_import"
  | "ai_scan";

// =============================================================================
// Base Message Envelope
// =============================================================================

/**
 * All WebSocket messages follow this structure
 */
export interface WebSocketMessage {
  type: MessageType;
  jobId: string;           // Client correlation ID
  pipeline: PipelineType;  // Source identification
  timestamp: number;       // Server time (ms since epoch)
  version: string;         // Schema version (e.g., "1.0.0")
  payload: MessagePayload; // Type-specific data
}

/**
 * Payload is a discriminated union based on message type
 */
export type MessagePayload =
  | JobStartedPayload
  | JobProgressPayload
  | JobCompletePayload
  | ErrorPayload
  | PingPayload
  | PongPayload;

// =============================================================================
// Job Started Payload
// =============================================================================

export interface JobStartedPayload {
  type: "job_started";
  totalCount?: number;      // Optional: Total items to process
  estimatedDuration?: number; // Optional: Estimated seconds
}

// =============================================================================
// Job Progress Payload
// =============================================================================

export interface JobProgressPayload {
  type: "job_progress";
  progress: number;         // 0.0 - 1.0
  status: string;           // Human-readable status message
  processedCount?: number;  // Optional: Items processed so far
  currentItem?: string;     // Optional: Current item being processed
  keepAlive?: boolean;      // Optional: True for keep-alive pings
}

// =============================================================================
// Job Complete Payload (Pipeline-Specific)
// =============================================================================

export type JobCompletePayload =
  | BatchEnrichmentCompletePayload
  | CSVImportCompletePayload
  | AIScanCompletePayload;

/**
 * Batch Enrichment Completion
 */
export interface BatchEnrichmentCompletePayload {
  type: "job_complete";
  pipeline: "batch_enrichment";
  totalProcessed: number;
  successCount: number;
  failureCount: number;
  duration: number;         // Milliseconds
}

/**
 * CSV Import Completion
 */
export interface CSVImportCompletePayload {
  type: "job_complete";
  pipeline: "csv_import";
  books: ParsedBook[];
  errors: ImportError[];
  successRate: string;      // e.g., "45/50"
}

export interface ParsedBook {
  title: string;
  author: string;
  isbn?: string;
  coverUrl?: string;
  publisher?: string;
  publicationYear?: number;
  enrichmentError?: string;
}

export interface ImportError {
  title: string;
  error: string;
}

/**
 * AI Scan Completion
 */
export interface AIScanCompletePayload {
  type: "job_complete";
  pipeline: "ai_scan";
  totalDetected: number;
  approved: number;
  needsReview: number;
  books: DetectedBook[];
}

export interface DetectedBook {
  title?: string;
  author?: string;
  isbn?: string;
  confidence?: number;
  boundingBox?: BoundingBox;
  enrichmentStatus?: string;
  coverUrl?: string;
  publisher?: string;
  publicationYear?: number;
}

export interface BoundingBox {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

// =============================================================================
// Error Payload
// =============================================================================

export interface ErrorPayload {
  type: "error";
  code: string;             // Machine-readable error code
  message: string;          // Human-readable error message
  details?: any;            // Optional: Additional error context
  retryable?: boolean;      // Optional: Can client retry?
}

// =============================================================================
// Ping/Pong Payloads
// =============================================================================

export interface PingPayload {
  type: "ping";
  timestamp: number;
}

export interface PongPayload {
  type: "pong";
  timestamp: number;
  latency?: number;         // Optional: Server-measured round-trip time
}

// =============================================================================
// WebSocket Message Factory
// =============================================================================

/**
 * Factory for creating type-safe WebSocket messages
 */
export class WebSocketMessageFactory {
  private static readonly VERSION = "1.0.0";

  /**
   * Create a job_started message
   */
  static createJobStarted(
    jobId: string,
    pipeline: PipelineType,
    payload: Omit<JobStartedPayload, "type">
  ): WebSocketMessage {
    return {
      type: "job_started",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload: {
        type: "job_started",
        ...payload
      }
    };
  }

  /**
   * Create a job_progress message
   */
  static createJobProgress(
    jobId: string,
    pipeline: PipelineType,
    payload: Omit<JobProgressPayload, "type">
  ): WebSocketMessage {
    return {
      type: "job_progress",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload: {
        type: "job_progress",
        ...payload
      }
    };
  }

  /**
   * Create a job_complete message
   */
  static createJobComplete(
    jobId: string,
    pipeline: PipelineType,
    payload: Omit<JobCompletePayload, "type">
  ): WebSocketMessage {
    return {
      type: "job_complete",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload: {
        type: "job_complete",
        ...payload
      }
    };
  }

  /**
   * Create an error message
   */
  static createError(
    jobId: string,
    pipeline: PipelineType,
    payload: Omit<ErrorPayload, "type">
  ): WebSocketMessage {
    return {
      type: "error",
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: this.VERSION,
      payload: {
        type: "error",
        ...payload
      }
    };
  }

  /**
   * Create a ping message
   */
  static createPing(
    jobId: string,
    pipeline: PipelineType
  ): WebSocketMessage {
    const timestamp = Date.now();
    return {
      type: "ping",
      jobId,
      pipeline,
      timestamp,
      version: this.VERSION,
      payload: {
        type: "ping",
        timestamp
      }
    };
  }

  /**
   * Create a pong message
   */
  static createPong(
    jobId: string,
    pipeline: PipelineType,
    pingTimestamp: number
  ): WebSocketMessage {
    const timestamp = Date.now();
    return {
      type: "pong",
      jobId,
      pipeline,
      timestamp,
      version: this.VERSION,
      payload: {
        type: "pong",
        timestamp,
        latency: timestamp - pingTimestamp
      }
    };
  }
}
