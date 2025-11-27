import Foundation

// MARK: - SSE Event Models

/// SSE event types for CSV import progress tracking
public enum SSEEventType: String, Sendable {
    case queued
    case started
    case progress
    case complete
    case error
}

/// Progress event from SSE stream
public struct SSEProgressEvent: Codable, Sendable {
    public let progress: Double
    public let processedRows: Int
    public let successfulRows: Int
    public let failedRows: Int

    enum CodingKeys: String, CodingKey {
        case progress
        case processedRows = "processed_rows"
        case successfulRows = "successful_rows"
        case failedRows = "failed_rows"
    }
}

/// Started event from SSE stream
public struct SSEStartedEvent: Codable, Sendable {
    public let status: String
    public let totalRows: Int
    public let startedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case totalRows = "total_rows"
        case startedAt = "started_at"
    }
}

/// Complete event from SSE stream
public struct SSECompleteEvent: Codable, Sendable {
    public let status: String
    public let progress: Double
    public let resultSummary: ResultSummary

    enum CodingKeys: String, CodingKey {
        case status
        case progress
        case resultSummary = "result_summary"
    }

    public struct ResultSummary: Codable, Sendable {
        public let booksCreated: Int
        public let booksUpdated: Int
        public let duplicatesSkipped: Int
        public let enrichmentSucceeded: Int
        public let enrichmentFailed: Int
        public let errors: [ImportError]?

        enum CodingKeys: String, CodingKey {
            case booksCreated = "books_created"
            case booksUpdated = "books_updated"
            case duplicatesSkipped = "duplicates_skipped"
            case enrichmentSucceeded = "enrichment_succeeded"
            case enrichmentFailed = "enrichment_failed"
            case errors
        }
    }

    public struct ImportError: Codable, Sendable {
        public let row: Int
        public let isbn: String
        public let error: String
    }
}

/// Error event from SSE stream
public struct SSEErrorEvent: Codable, Sendable {
    public let status: String
    public let error: String
    public let processedRows: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case error
        case processedRows = "processed_rows"
    }
}

/// Queued event from SSE stream
public struct SSEQueuedEvent: Codable, Sendable {
    public let status: String
    public let jobId: String

    enum CodingKeys: String, CodingKey {
        case status
        case jobId = "job_id"
    }
}

// MARK: - SSE Client Errors

public enum SSEClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case connectionFailed(Error)
    case eventParsingFailed
    case serverError(String)
    case reconnectionLimitExceeded
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid SSE stream URL"
        case .connectionFailed(let error):
            return "SSE connection failed: \(error.localizedDescription)"
        case .eventParsingFailed:
            return "Failed to parse SSE event data"
        case .serverError(let message):
            return "Server error: \(message)"
        case .reconnectionLimitExceeded:
            return "Maximum reconnection attempts exceeded"
        case .cancelled:
            return "SSE connection cancelled"
        }
    }
}

// MARK: - SSE Event Wrapper

/// Wrapper for all SSE events with type information
public enum SSEEvent: Sendable {
    case queued(SSEQueuedEvent)
    case started(SSEStartedEvent)
    case progress(SSEProgressEvent)
    case complete(SSECompleteEvent)
    case error(SSEErrorEvent)
}
