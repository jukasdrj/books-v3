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
    case jobStarted = "job_started"
    case jobProgress = "job_progress"
    case jobComplete = "job_complete"
    case error = "error"
    case ping = "ping"
    case pong = "pong"
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
    case jobStarted(JobStartedPayload)
    case jobProgress(JobProgressPayload)
    case jobComplete(JobCompletePayload)
    case error(ErrorPayload)
    case ping(PingPayload)
    case pong(PongPayload)

    // Custom Codable implementation for discriminated union
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
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
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

// MARK: - Job Started Payload

public struct JobStartedPayload: Codable, Sendable {
    public let type: String = "job_started"
    public let totalCount: Int?
    public let estimatedDuration: Int?      // Seconds
}

// MARK: - Job Progress Payload

public struct JobProgressPayload: Codable, Sendable {
    public let type: String = "job_progress"
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pipeline = try container.decode(String.self, forKey: .pipeline)

        switch pipeline {
        case "batch_enrichment":
            self = .batchEnrichment(try BatchEnrichmentCompletePayload(from: decoder))
        case "csv_import":
            self = .csvImport(try CSVImportCompletePayload(from: decoder))
        case "ai_scan":
            self = .aiScan(try AIScanCompletePayload(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .pipeline,
                in: container,
                debugDescription: "Unknown pipeline: \(pipeline)"
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

    private enum CodingKeys: String, CodingKey {
        case pipeline
    }
}

// MARK: - Batch Enrichment Complete Payload

public struct BatchEnrichmentCompletePayload: Codable, Sendable {
    public let type: String = "job_complete"
    public let pipeline: String = "batch_enrichment"
    public let totalProcessed: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: Int                // Milliseconds
    public let enrichedBooks: [EnrichedBookPayload]  // The actual enriched data
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
    public let type: String = "job_complete"
    public let pipeline: String = "csv_import"
    public let books: [ParsedBook]
    public let errors: [ImportError]
    public let successRate: String          // e.g., "45/50"
}

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

// MARK: - AI Scan Complete Payload

public struct AIScanCompletePayload: Codable, Sendable {
    public let type: String = "job_complete"
    public let pipeline: String = "ai_scan"
    public let totalDetected: Int
    public let approved: Int
    public let needsReview: Int
    public let books: [DetectedBook]
}

public struct DetectedBook: Codable, Sendable {
    public let title: String?
    public let author: String?
    public let isbn: String?
    public let confidence: Double?
    public let boundingBox: BoundingBox?
    public let enrichmentStatus: String?
    public let coverUrl: String?
    public let publisher: String?
    public let publicationYear: Int?
}

public struct BoundingBox: Codable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

// MARK: - Error Payload

public struct ErrorPayload: Codable, Sendable {
    public let type: String = "error"
    public let code: String
    public let message: String
    public let details: AnyCodable?         // Optional: Additional context
    public let retryable: Bool?
}

// MARK: - Ping/Pong Payloads

public struct PingPayload: Codable, Sendable {
    public let type: String = "ping"
    public let timestamp: Int64
}

public struct PongPayload: Codable, Sendable {
    public let type: String = "pong"
    public let timestamp: Int64
    public let latency: Int?                // Milliseconds
}

// MARK: - AnyCodable Helper

/// Helper for encoding/decoding arbitrary JSON
public struct AnyCodable: Codable, Sendable {
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
