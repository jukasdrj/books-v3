import Foundation

// MARK: - SSE Event Models

/// SSE event types for CSV import progress tracking (V2 API)
public enum SSEEventType: String, Sendable {
    case initialized
    case processing
    case completed
    case failed
    case error
    case timeout
}

/// Processing event from SSE stream (V2 API)
public struct SSEProgressEvent: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double
    public let processedCount: Int
    public let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case progress
        case processedCount
        case totalCount
    }
}

/// Initialized event from SSE stream (V2 API)
public struct SSEInitializedEvent: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double
    public let processedCount: Int
    public let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case progress
        case processedCount
        case totalCount
    }
}

/// Completed event from SSE stream (V2 API)
/// Note: resultSummary NOT included - fetch from /api/v2/imports/{jobId}/results
public struct SSECompleteEvent: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double
    public let processedCount: Int
    public let totalCount: Int
    public let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case progress
        case processedCount
        case totalCount
        case completedAt
    }
}

/// Failed/Error event from SSE stream (V2 API)
public struct SSEErrorEvent: Codable, Sendable {
    public let jobId: String?
    public let status: String?
    public let error: String
    public let message: String
    public let details: String?

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case error
        case message
        case details
    }
}

/// Timeout event from SSE stream (V2 API)
public struct SSETimeoutEvent: Codable, Sendable {
    public let error: String
    public let message: String
    public let jobId: String
    public let lastStatus: String
    public let lastProgress: Double

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case jobId
        case lastStatus
        case lastProgress
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

/// Wrapper for all SSE events with type information (V2 API)
public enum SSEEvent: Sendable {
    case initialized(SSEInitializedEvent)
    case processing(SSEProgressEvent)
    case completed(SSECompleteEvent)
    case failed(SSEErrorEvent)
    case error(SSEErrorEvent)
    case timeout(SSETimeoutEvent)
}

// MARK: - Results Response Models

/// Results response from /api/v2/imports/{jobId}/results
public struct SSEResultsResponse: Codable, Sendable {
    public let booksCreated: Int
    public let booksUpdated: Int
    public let duplicatesSkipped: Int
    public let enrichmentSucceeded: Int
    public let enrichmentFailed: Int
    public let errors: [ImportError]

    enum CodingKeys: String, CodingKey {
        case booksCreated
        case booksUpdated
        case duplicatesSkipped
        case enrichmentSucceeded
        case enrichmentFailed
        case errors
    }

    public struct ImportError: Codable, Sendable {
        public let row: Int
        public let isbn: String
        public let error: String
    }
}
