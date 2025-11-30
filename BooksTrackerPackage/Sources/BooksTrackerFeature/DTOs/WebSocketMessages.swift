import Foundation

// MARK: - Unified WebSocket Message Schema (v1.0.0)

/**
 * Swift implementation of the unified WebSocket message schema
 *
 * Mirrors the TypeScript schema in:
 * cloudflare-workers/api-worker/src/types/websocket-messages.ts
 *
 * Design Principles:
 * 1. Codable for JSON serialization/deserialization
 * 2. Sendable for Swift 6 concurrency
 * 3. Discriminated unions via enums with associated values
 * 4. Type-safe message construction
 */

// MARK: - Message Type Enum

public enum MessageType: String, Codable, Sendable {
    // Client-to-Server
    case ready = "ready"              // Client ready signal
    
    // Server-to-Client
    case readyAck = "ready_ack"       // Backend acknowledgment of client ready signal
    case reconnected = "reconnected"  // State sync after reconnect
    case jobStarted = "job_started"
    case jobProgress = "job_progress"
    case jobComplete = "job_complete"
    case error = "error"
    case ping = "ping"
    case pong = "pong"

    // Batch scanning
    case batchInit = "batch-init"
    case batchProgress = "batch-progress"
    case batchComplete = "batch-complete"
    case batchCanceling = "batch-canceling"
}

// MARK: - Pipeline Type Enum

public enum PipelineType: String, Codable, Sendable {
    case batchEnrichment = "batch_enrichment"
    case csvImport = "csv_import"
    case aiScan = "ai_scan"
}

// MARK: - Base WebSocket Message

public struct TypedWebSocketMessage: Codable, Sendable {
    public let type: MessageType
    public let jobId: String
    public let pipeline: PipelineType
    public let timestamp: Int64           // Milliseconds since epoch
    public let version: String
    public let payload: MessagePayload

    /// Initialize from JSON data
    public init(from data: Data) throws {
        self = try JSONDecoder().decode(TypedWebSocketMessage.self, from: data)
    }
}

// MARK: - Message Payload (Discriminated Union)

public enum MessagePayload: Codable, Sendable {
    case readyAck(ReadyAckPayload)
    case reconnected(ReconnectedPayload)
    case jobStarted(JobStartedPayload)
    case jobProgress(JobProgressPayload)
    case jobComplete(JobCompletePayload)
    case error(ErrorPayload)
    case ping(PingPayload)
    case pong(PongPayload)

    // Batch scanning messages (Section 7.6)
    case batchInit(BatchInitPayload)
    case batchProgress(BatchProgressPayload)
    case batchComplete(BatchCompletePayload)
    case batchCanceling(BatchCancelingPayload)

    // Custom Codable implementation for discriminated union
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "ready_ack":
            self = .readyAck(try ReadyAckPayload(from: decoder))
        case "reconnected":
            self = .reconnected(try ReconnectedPayload(from: decoder))
        case "job_started":
            self = .jobStarted(try JobStartedPayload(from: decoder))
        case "job_progress":
            self = .jobProgress(try JobProgressPayload(from: decoder))
        case "job_complete":
            self = .jobComplete(try JobCompletePayload(from: decoder))
        case "error":
            self = .error(try ErrorPayload(from: decoder))
        case "ping":
            self = .ping(try PingPayload(from: decoder))
        case "pong":
            self = .pong(try PongPayload(from: decoder))
        case "batch-init":
            self = .batchInit(try BatchInitPayload(from: decoder))
        case "batch-progress":
            self = .batchProgress(try BatchProgressPayload(from: decoder))
        case "batch-complete":
            self = .batchComplete(try BatchCompletePayload(from: decoder))
        case "batch-canceling":
            self = .batchCanceling(try BatchCancelingPayload(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .readyAck(let payload):
            try payload.encode(to: encoder)
        case .reconnected(let payload):
            try payload.encode(to: encoder)
        case .jobStarted(let payload):
            try payload.encode(to: encoder)
        case .jobProgress(let payload):
            try payload.encode(to: encoder)
        case .jobComplete(let payload):
            try payload.encode(to: encoder)
        case .error(let payload):
            try payload.encode(to: encoder)
        case .ping(let payload):
            try payload.encode(to: encoder)
        case .pong(let payload):
            try payload.encode(to: encoder)
        case .batchInit(let payload):
            try payload.encode(to: encoder)
        case .batchProgress(let payload):
            try payload.encode(to: encoder)
        case .batchComplete(let payload):
            try payload.encode(to: encoder)
        case .batchCanceling(let payload):
            try payload.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

// MARK: - Ready Acknowledgment Payload

public struct ReadyAckPayload: Codable, Sendable {
    public let type: String
    public let timestamp: Int64             // Milliseconds since epoch
}

// MARK: - Reconnected Payload

public struct ReconnectedPayload: Codable, Sendable {
    public let type: String
    public let progress: Double
    public let status: String
    public let processedCount: Int
    public let totalCount: Int
    public let lastUpdate: Int64?
    public let message: String
    
    enum CodingKeys: String, CodingKey {
        case type, progress, status, message
        case processedCount = "processed_count"
        case totalCount = "total_count"
        case lastUpdate = "last_update"
    }
}


// MARK: - Job Started Payload

public struct JobStartedPayload: Codable, Sendable {
    public let type: String
    public let totalCount: Int?
    public let estimatedDuration: Int?      // Seconds
}

// MARK: - Job Progress Payload

public struct JobProgressPayload: Codable, Sendable {
    public let type: String
    public let progress: Double             // 0.0 - 1.0
    public let status: String
    public let processedCount: Int?
    public let currentItem: String?
    public let keepAlive: Bool?
}

// MARK: - Job Complete Payload (Pipeline-Specific)

public enum JobCompletePayload: Codable, Sendable {
    case batchEnrichment(BatchEnrichmentCompletePayload)
    case csvImport(CSVImportCompletePayload)
    case aiScan(AIScanCompletePayload)

    public init(from decoder: Decoder) throws {
        // Try decoding each pipeline-specific payload type
        // The payload discriminator (pipeline) is at the MESSAGE level, not in the payload itself
        // So we use the payload structure to determine which type it is

        if let aiPayload = try? AIScanCompletePayload(from: decoder) {
            self = .aiScan(aiPayload)
        } else if let batchPayload = try? BatchEnrichmentCompletePayload(from: decoder) {
            self = .batchEnrichment(batchPayload)
        } else if let csvPayload = try? CSVImportCompletePayload(from: decoder) {
            self = .csvImport(csvPayload)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not decode any known JobCompletePayload type"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .batchEnrichment(let payload):
            try payload.encode(to: encoder)
        case .csvImport(let payload):
            try payload.encode(to: encoder)
        case .aiScan(let payload):
            try payload.encode(to: encoder)
        }
    }
}

// MARK: - Job Completion Summary (v2.0 - Mobile Optimized)

/// Lightweight completion summary (<1 KB) for mobile optimization.
/// Full results are stored in KV cache and retrieved via HTTP GET using `resourceId`.
/// BREAKING CHANGE (v2.0 - Nov 15, 2025): Migrated from full payload to summary-only format.
public struct JobCompletionSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int                // Milliseconds
    public let resourceId: String?          // KV cache key: "job-results:{jobId}"
}

// MARK: - Batch Enrichment Complete Payload

public struct BatchEnrichmentCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: JobCompletionSummary

    /// ISO 8601 timestamp when results expire from KV cache
    /// 24 hours after job completion (v2.4 - Issue #169)
    public let expiresAt: String
}

// MARK: - Enriched Book Data (Batch Enrichment)

/// Single book enrichment result from backend
/// Matches the structure returned by batch-enrichment.js
public struct EnrichedBookPayload: Codable, Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let success: Bool
    public let error: String?
    public let enriched: EnrichedDataPayload?
}

/// The enriched data containing work, edition, and authors
/// Matches SingleEnrichmentResult from enrichment.ts
public struct EnrichedDataPayload: Codable, Sendable {
    public let work: WorkDTO
    public let edition: EditionDTO?
    public let authors: [AuthorDTO]
}

// MARK: - CSV Import Complete Payload

public struct CSVImportCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: JobCompletionSummary

    /// ISO 8601 timestamp when results expire from KV cache
    /// 24 hours after job completion (v2.4 - Issue #169)
    public let expiresAt: String
}

// MARK: - Legacy CSV Import Models (Deprecated - v2.0)

/// Legacy models for full CSV import results (now fetched via HTTP GET)
/// These are kept for backward compatibility when fetching from KV cache
/// DEPRECATED: Use GET /v1/jobs/{jobId}/results to fetch full results

public struct ParsedBook: Codable, Sendable {
    public let title: String
    public let author: String
    public let isbn: String?
    public let coverUrl: String?
    public let publisher: String?
    public let publicationYear: Int?
    public let enrichmentError: String?
}

public struct ImportError: Codable, Sendable {
    public let title: String
    public let error: String
}

// MARK: - AI Scan Summary (v2.0 - Extends Base Summary)

/// AI scan summary extending base summary with AI-specific statistics
public struct AIScanSummary: Codable, Sendable {
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int                // Milliseconds
    public let resourceId: String?          // KV cache key: "job-results:{jobId}"
    public let totalDetected: Int?          // Books detected by Gemini Vision
    public let approved: Int?               // Auto-approved books (high confidence)
    public let needsReview: Int?            // Books requiring manual review (low confidence)
}

// MARK: - AI Scan Complete Payload

public struct AIScanCompletePayload: Codable, Sendable {
    public let type: String
    public let pipeline: String
    public let summary: AIScanSummary

    /// ISO 8601 timestamp when results expire from KV cache
    /// 24 hours after job completion (v2.4 - Issue #169)
    public let expiresAt: String
}

// MARK: - Legacy AI Scan Models (Deprecated - v2.0)

/// Legacy models for full AI scan results (now fetched via HTTP GET)
/// These are kept for backward compatibility when fetching from KV cache
/// DEPRECATED: Use GET /v1/jobs/{jobId}/results to fetch full results

public struct JobMetadata: Codable, Sendable {
    public let modelUsed: String?
    public let processingTime: Int?

    enum CodingKeys: String, CodingKey {
        case modelUsed = "model_used"
        case processingTime = "processing_time"
    }
}

// MARK: - Detected Book Payload

public struct DetectedBookPayload: Codable, Sendable {
    public let title: String?
    public let author: String?
    public let isbn: String?
    public let confidence: Double?
    public let boundingBox: BoundingBox?
    public let enrichmentStatus: String?  // Keep as String for backward compatibility
    // Deprecated flat fields (use enrichment below)
    public let coverUrl: String?
    public let publisher: String?
    public let publicationYear: Int?
    // Nested enrichment data (canonical DTOs) - Added Nov 2025
    public let enrichment: EnrichmentData?

    /// Check if enrichment can be retried based on status string
    /// Retryable statuses: pending, error, circuit_open
    public var canRetryEnrichment: Bool {
        let status = enrichmentStatus ?? enrichment?.status
        switch status {
        case "pending", "error", "circuit_open":
            return true
        default:
            return false
        }
    }

    /// Get retry delay if circuit is open (milliseconds)
    public var circuitOpenRetryDelay: Int? {
        let status = enrichmentStatus ?? enrichment?.status
        guard status == "circuit_open" else { return nil }
        return enrichment?.retryAfterMs
    }
}

public struct EnrichmentData: Codable, Sendable {
    public let status: String  // Keep as String for backward compatibility
    public let work: WorkDTO?
    public let editions: [EditionDTO]?
    public let authors: [AuthorDTO]?
    public let provider: String?
    public let cachedResult: Bool?
    public let error: String?
    public let retryAfterMs: Int?  // Circuit breaker cooldown (API Contract v3.1)

    /// Convenience: Is this a circuit_open status?
    public var isCircuitOpen: Bool {
        status == "circuit_open"
    }
}

public struct BoundingBox: Codable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

// MARK: - Error Payload

public struct ErrorPayload: Codable, Sendable {
    public let type: String
    public let code: String
    public let message: String
    public let details: AnyCodable?         // Optional: Additional context
    public let retryable: Bool?

    public init(type: String = "error", code: String, message: String, details: AnyCodable? = nil, retryable: Bool? = nil) {
        self.type = type
        self.code = code
        self.message = message
        self.details = details
        self.retryable = retryable
    }
}

// MARK: - Ping/Pong Payloads

public struct PingPayload: Codable, Sendable {
    public let type: String
    public let timestamp: Int64
}

public struct PongPayload: Codable, Sendable {
    public let type: String
    public let timestamp: Int64
    public let latency: Int?                // Milliseconds
}

// MARK: - Batch Scanning Payloads (Section 7.6)

/// Batch init payload - sent when batch job is initialized
public struct BatchInitPayload: Codable, Sendable {
    public let type: String
    public let totalPhotos: Int
    public let status: String

    public init(type: String = "batch-init", totalPhotos: Int, status: String) {
        self.type = type
        self.totalPhotos = totalPhotos
        self.status = status
    }
}

/// Batch progress payload - sent during batch processing
public struct BatchProgressPayload: Codable, Sendable {
    public let type: String
    public let currentPhoto: Int
    public let totalPhotos: Int
    public let photoStatus: String
    public let booksFound: Int
    public let totalBooksFound: Int
    public let photos: [PhotoProgressData]

    public struct PhotoProgressData: Codable, Sendable {
        public let index: Int
        public let status: String
        public let booksFound: Int?
        public let error: String?

        public init(index: Int, status: String, booksFound: Int? = nil, error: String? = nil) {
            self.index = index
            self.status = status
            self.booksFound = booksFound
            self.error = error
        }
    }

    public init(
        type: String = "batch-progress",
        currentPhoto: Int,
        totalPhotos: Int,
        photoStatus: String,
        booksFound: Int,
        totalBooksFound: Int,
        photos: [PhotoProgressData]
    ) {
        self.type = type
        self.currentPhoto = currentPhoto
        self.totalPhotos = totalPhotos
        self.photoStatus = photoStatus
        self.booksFound = booksFound
        self.totalBooksFound = totalBooksFound
        self.photos = photos
    }
}

/// Batch complete payload - sent when batch job finishes
public struct BatchCompletePayload: Codable, Sendable {
    public let type: String
    public let totalBooks: Int
    public let photoResults: [PhotoResult]
    public let books: [DetectedBookPayload]

    public struct PhotoResult: Codable, Sendable {
        public let index: Int
        public let status: String
        public let booksFound: Int?
        public let error: String?

        public init(index: Int, status: String, booksFound: Int? = nil, error: String? = nil) {
            self.index = index
            self.status = status
            self.booksFound = booksFound
            self.error = error
        }
    }

    public init(
        type: String = "batch-complete",
        totalBooks: Int,
        photoResults: [PhotoResult],
        books: [DetectedBookPayload]
    ) {
        self.type = type
        self.totalBooks = totalBooks
        self.photoResults = photoResults
        self.books = books
    }
}

/// Batch canceling payload - sent when batch job is being canceled
public struct BatchCancelingPayload: Codable, Sendable {
    public let type: String
    public let reason: String?

    public init(type: String = "batch-canceling", reason: String? = nil) {
        self.type = type
        self.reason = reason
    }
}

// MARK: - AnyCodable Helper

/// Helper for encoding/decoding arbitrary JSON
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}

// MARK: - ReconnectedPayload Extension

extension ReconnectedPayload {
    /// Converts a ReconnectedPayload to a synthetic JobProgressPayload
    /// Used for updating progress handlers after WebSocket reconnection
    public func toJobProgressPayload() -> JobProgressPayload {
        JobProgressPayload(
            type: self.type,
            progress: self.progress,
            status: self.status,
            processedCount: self.processedCount,
            currentItem: nil,
            keepAlive: true
        )
    }
}