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

/// Error detail structure for SSE failed/error events (V2 API)
public struct ErrorDetail: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let retryable: Bool?
    public let details: AnyCodable?

    public init(code: String, message: String, retryable: Bool? = nil, details: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case retryable
        case details
    }

    // Custom Equatable to handle AnyCodable
    public static func == (lhs: ErrorDetail, rhs: ErrorDetail) -> Bool {
        lhs.code == rhs.code &&
        lhs.message == rhs.message &&
        lhs.retryable == rhs.retryable
        // Ignoring details for equality since AnyCodable holds Any
    }
}

// Note: AnyCodable is defined in DTOs/WebSocketMessages.swift and reused here

/// Failed/Error event from SSE stream (V2 API)
/// ⚠️ Updated to match backend spec: error is now a structured ErrorDetail object
public struct SSEErrorEvent: Codable, Sendable {
    public let jobId: String?
    public let status: String?
    public let progress: Double?
    public let processedCount: Int?
    public let totalCount: Int?
    public let error: ErrorDetail  // ⚠️ Changed from String to ErrorDetail

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case progress
        case processedCount
        case totalCount
        case error
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
    public let books: [ParsedBook]?  // Optional for backwards compatibility

    enum CodingKeys: String, CodingKey {
        case booksCreated
        case booksUpdated
        case duplicatesSkipped
        case enrichmentSucceeded
        case enrichmentFailed
        case errors
        case books
    }

    public struct ImportError: Codable, Sendable {
        public let row: Int
        public let isbn: String
        public let error: String
    }

    /// Parsed book from backend CSV import
    /// Backend returns simple format, not full canonical book object
    public struct ParsedBook: Codable, Sendable {
        public let title: String
        public let author: String
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?
        public let enrichmentError: String?
    }
}
