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
    // CSV import event types
    case csvImportProgress(CSVImportProgress)
    case csvImportCompleted(CSVImportCompleted)
    case csvImportFailed(CSVImportFailed)
    // V3 scan event types (unprefixed events from backend)
    case v3ScanInitialized(V3ScanInitialized)
    case v3ScanProgress(V3ScanProgress)
    case v3ScanCompleted(V3ScanCompleted)
    case v3ScanFailed(V3ScanFailed)
    case v3Ping(V3Ping)
}

// MARK: - CSV Import Progress (SSE Payloads)

/// Progress update during CSV import (SSE event payload)
/// Matches API Contract v3.3 for CSV import SSE events
public struct CSVImportProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double         // 0.0 - 1.0 (matches backend)
    public let processedCount: Int      // Renamed from processedRecords
    public let totalCount: Int          // Renamed from totalRecords
    public let startedAt: String?       // ISO timestamp when job started

    public init(
        jobId: String,
        status: String,
        progress: Double,
        processedCount: Int,
        totalCount: Int,
        startedAt: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.startedAt = startedAt
    }
}

/// Completed CSV import (SSE event: "completed")
/// Matches API Contract v3.3 for CSV import completion event
public struct CSVImportCompleted: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double         // Should be 1.0 on completion
    public let processedCount: Int
    public let totalCount: Int

    public init(
        jobId: String,
        status: String,
        progress: Double,
        processedCount: Int,
        totalCount: Int
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.processedCount = processedCount
        self.totalCount = totalCount
    }
}

/// CSV import failed event
public struct CSVImportFailed: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let error: ErrorDetail
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

// MARK: - Photo Scan SSE Events (API Contract v3.2)

/// PhotoScan progress event (SSE event: "photoscan.progress")
public struct PhotoScanSSEProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double  // 0.0 - 1.0
    public let processedPhotos: Int
    public let totalPhotos: Int
    public let recognizedBooks: Int
    public let message: String?

    public init(
        jobId: String,
        status: String,
        progress: Double,
        processedPhotos: Int,
        totalPhotos: Int,
        recognizedBooks: Int,
        message: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.processedPhotos = processedPhotos
        self.totalPhotos = totalPhotos
        self.recognizedBooks = recognizedBooks
        self.message = message
    }
}

/// PhotoScan completed event (SSE event: "photoscan.completed")
public struct PhotoScanSSECompleted: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let resultsUrl: String  // URL to fetch full results
    public let summary: PhotoScanSummary

    public struct PhotoScanSummary: Codable, Equatable, Sendable {
        public let totalDetected: Int
        public let approved: Int
        public let needsReview: Int
        public let enrichedCount: Int
        public let duration: Int  // milliseconds

        public init(
            totalDetected: Int,
            approved: Int,
            needsReview: Int,
            enrichedCount: Int,
            duration: Int
        ) {
            self.totalDetected = totalDetected
            self.approved = approved
            self.needsReview = needsReview
            self.enrichedCount = enrichedCount
            self.duration = duration
        }
    }

    public init(
        jobId: String,
        status: String,
        resultsUrl: String,
        summary: PhotoScanSummary
    ) {
        self.jobId = jobId
        self.status = status
        self.resultsUrl = resultsUrl
        self.summary = summary
    }
}

/// PhotoScan failed event (SSE event: "photoscan.failed")
public struct PhotoScanSSEFailed: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String
    public let error: String
    public let retryable: Bool?

    public init(
        jobId: String,
        status: String,
        error: String,
        retryable: Bool? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.error = error
        self.retryable = retryable
    }
}

/// Union type for all PhotoScan SSE events
public enum PhotoScanSSEEvent: Equatable, Sendable {
    case progress(PhotoScanSSEProgress)
    case completed(PhotoScanSSECompleted)
    case failed(PhotoScanSSEFailed)
}

// MARK: - V3 Scan SSE Events (Actual Backend Format)

/// V3 scan initialized event (event: "initialized")
/// Sent immediately when SSE connection is established
public struct V3ScanInitialized: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String           // "initialized"
    public let progress: Double         // 0
    public let processedCount: Int      // 0
    public let totalCount: Int          // Number of photos
    public let timestamp: String

    public init(
        jobId: String,
        status: String,
        progress: Double,
        processedCount: Int,
        totalCount: Int,
        timestamp: String
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.timestamp = timestamp
    }
}

/// V3 scan progress event (event: "progress")
/// Sent during photo processing (10-50%) and enrichment (50-95%)
/// Note: Backend may send varying fields - all numeric fields made optional for resilience
public struct V3ScanProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String           // "processing"
    public let progress: Double?        // 0.0 - 1.0 (optional - backend may omit)
    public let processedCount: Int?     // Optional - backend may omit
    public let totalCount: Int?         // Optional - backend may omit
    public let timestamp: String?       // Optional - backend may omit
    public let message: String?         // Human-readable progress message from backend

    public init(
        jobId: String,
        status: String,
        progress: Double? = nil,
        processedCount: Int? = nil,
        totalCount: Int? = nil,
        timestamp: String? = nil,
        message: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.timestamp = timestamp
        self.message = message
    }
}

/// V3 scan completed event (event: "completed")
/// Sent when job finishes with inline results
public struct V3ScanCompleted: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String           // "completed"
    public let results: [V3ScanBookResult]
    public let timestamp: String

    public init(
        jobId: String,
        status: String,
        results: [V3ScanBookResult],
        timestamp: String
    ) {
        self.jobId = jobId
        self.status = status
        self.results = results
        self.timestamp = timestamp
    }
}

/// Individual book result from V3 scan
public struct V3ScanBookResult: Codable, Equatable, Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let confidence: Double       // 0.0 - 1.0
    public let enrichmentStatus: String // "success", "partial", "failed"
    public let coverUrl: String?
    public let publisher: String?
    public let publicationYear: Int?

    public init(
        title: String,
        author: String? = nil,
        isbn: String? = nil,
        confidence: Double,
        enrichmentStatus: String,
        coverUrl: String? = nil,
        publisher: String? = nil,
        publicationYear: Int? = nil
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.confidence = confidence
        self.enrichmentStatus = enrichmentStatus
        self.coverUrl = coverUrl
        self.publisher = publisher
        self.publicationYear = publicationYear
    }
}

/// V3 scan failed event (event: "failed")
/// Note: Backend may omit timestamp field - made optional for resilience
public struct V3ScanFailed: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: String?          // "failed" - optional for backward compat
    public let error: V3ScanError
    public let timestamp: String?       // Optional - backend may omit

    public init(jobId: String, status: String? = "failed", error: V3ScanError, timestamp: String? = nil) {
        self.jobId = jobId
        self.status = status
        self.error = error
        self.timestamp = timestamp
    }
}

/// V3 scan error details
public struct V3ScanError: Codable, Equatable, Sendable {
    public let code: String             // "E_ALARM_PROCESSING_FAILED"
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// V3 ping event (event: "ping")
/// Heartbeat sent every 30s to keep connection alive
public struct V3Ping: Codable, Equatable, Sendable {
    public let timestamp: String

    public init(timestamp: String) {
        self.timestamp = timestamp
    }
}

// MARK: - Legacy Support for GeminiCSVImport

/// Results response from SSE stream (legacy support)
/// Updated to match API Contract v3.3 (CSV import results endpoint)
public struct SSEResultsResponse: Codable, Sendable {
    public let books: [ParsedBook]?         // Parsed books (with enrichment data)
    public let errors: [ImportError]        // Import errors
    public let booksCreated: Int            // Count of new books created
    public let booksUpdated: Int            // Count of existing books updated
    public let error: String?               // Legacy error field
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
