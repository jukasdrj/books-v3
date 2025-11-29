import Foundation

// MARK: - SSE Event Models

/// Represents a parsed Server-Sent Events (SSE) event
/// Conforms to the W3C SSE specification
public struct SSEEvent: Equatable, Sendable {
    /// Event ID for resuming streams with Last-Event-ID
    public let id: String?

    /// Event type (e.g., "enrichment.progress", "enrichment.completed")
    public let event: String?

    /// Event data payload (JSON string to be decoded)
    public let data: String?

    /// Retry interval in milliseconds (server-suggested reconnection delay)
    public let retry: TimeInterval?

    public init(id: String? = nil, event: String? = nil, data: String? = nil, retry: TimeInterval? = nil) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

// MARK: - SSE Error Types

/// Errors specific to SSE stream handling
public enum SSEError: Error, LocalizedError, Equatable, Sendable {
    case invalidContentType
    case httpError(statusCode: Int)
    case connectionFailed(String) // Using String instead of Error for Equatable/Sendable
    case decodingError(String)
    case streamCancelled
    case malformedEvent(String)

    public var errorDescription: String? {
        switch self {
        case .invalidContentType:
            return "Server sent an invalid Content-Type header. Expected 'text/event-stream'."
        case .httpError(let statusCode):
            return "HTTP error occurred: Status Code \(statusCode)."
        case .connectionFailed(let message):
            return "SSE connection failed: \(message)"
        case .decodingError(let message):
            return "Failed to decode SSE event data: \(message)"
        case .streamCancelled:
            return "SSE stream was cancelled."
        case .malformedEvent(let line):
            return "Malformed SSE event line: \(line)"
        }
    }

    public static func == (lhs: SSEError, rhs: SSEError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidContentType, .invalidContentType),
             (.streamCancelled, .streamCancelled):
            return true
        case (.httpError(let lStatus), .httpError(let rStatus)):
            return lStatus == rStatus
        case (.connectionFailed(let lMsg), .connectionFailed(let rMsg)),
             (.decodingError(let lMsg), .decodingError(let rMsg)),
             (.malformedEvent(let lMsg), .malformedEvent(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

// MARK: - Enrichment Event Models (SSE Payloads)

/// Progress update during enrichment (SSE event: "enrichment.progress")
public struct EnrichmentProgress: Codable, Equatable, Sendable {
    public let isbn: String
    public let status: String
    public let progress: Int
    public let provider: String
}

/// Completed enrichment (SSE event: "enrichment.completed")
public struct EnrichmentCompleted: Codable, Sendable {
    public let isbn: String
    public let status: String
    public let data: AnyCodable // Flexible data field from backend

    public static func == (lhs: EnrichmentCompleted, rhs: EnrichmentCompleted) -> Bool {
        lhs.isbn == rhs.isbn && lhs.status == rhs.status
    }
}

extension EnrichmentCompleted: Equatable {}

/// Failed enrichment (SSE event: "enrichment.failed")
public struct EnrichmentFailed: Codable, Equatable, Sendable {
    public let isbn: String
    public let status: String
    public let error: String
}

/// Union type for all enrichment events
public enum EnrichmentEvent: Equatable, Sendable {
    case progress(EnrichmentProgress)
    case completed(EnrichmentCompleted)
    case failed(EnrichmentFailed)
}

// MARK: - CSV Import Progress (SSE Payloads)

/// Progress update during CSV import (SSE event payload)
public struct CSVImportProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String // "PENDING", "PROCESSING", "COMPLETED", "FAILED"
    public let processedRecords: Int
    public let totalRecords: Int
    public let progressPercentage: Int
    public let message: String?
    public let errors: [String]?
    public let finalResult: String? // URL string for download
}

// MARK: - Photo Scan Progress (SSE Payloads)

/// Progress update during photo scanning (SSE event payload)
public struct PhotoScanProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let processedPhotos: Int
    public let totalPhotos: Int
    public let recognizedBooks: Int
    public let message: String?
}

// MARK: - Legacy Support for GeminiCSVImport

/// Results response from SSE stream (legacy support)
public struct SSEResultsResponse: Codable, Sendable {
    public let results: [BookDTO]?
    public let error: String?
}

/// Error detail structure (legacy support)
public struct ErrorDetail: Codable, Equatable, Sendable {
    public let message: String
    public let code: String?
    public let retryable: Bool?

    public init(message: String, code: String? = nil, retryable: Bool? = nil) {
        self.message = message
        self.code = code
        self.retryable = retryable
    }
}
