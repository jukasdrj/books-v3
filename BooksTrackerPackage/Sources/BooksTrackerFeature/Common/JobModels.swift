import Foundation

// MARK: - Job Identifier
/// Unique identifier for tracking long-running operations
public struct JobIdentifier: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let jobType: String
    public let createdDate: Date

    public init(jobType: String) {
        self.id = UUID()
        self.jobType = jobType
        self.createdDate = Date()
    }
}

// MARK: - Job Status
/// Current state of a job with associated data
public enum JobStatus: Codable, Sendable, Equatable {
    case queued
    case active(progress: JobProgress)
    case completed(log: [String])
    case failed(error: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .active:
            return false
        }
    }
}

// MARK: - Job Progress
/// Progress information for active jobs
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var estimatedTimeRemaining: TimeInterval?
    public var keepAlive: Bool?  // Optional: true for server keep-alive pings, nil for normal updates
    public var scanResult: ScanResultPayload?  // Optional: present in final completion message for scan jobs

    public var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
    }

    public init(
        totalItems: Int,
        processedItems: Int,
        currentStatus: String,
        estimatedTimeRemaining: TimeInterval? = nil,
        keepAlive: Bool? = nil,
        scanResult: ScanResultPayload? = nil
    ) {
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.currentStatus = currentStatus
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.keepAlive = keepAlive
        self.scanResult = scanResult
    }

    public static var zero: JobProgress {
        JobProgress(
            totalItems: 0,
            processedItems: 0,
            currentStatus: "Starting..."
        )
    }
}

// MARK: - Scan Result Payload
/// Scan result data embedded in WebSocket completion message
public struct ScanResultPayload: Codable, Sendable, Equatable {
    public let totalDetected: Int
    public let approved: Int
    public let needsReview: Int
    public let books: [BookPayload]
    public let metadata: ScanMetadataPayload

    /// ISO 8601 timestamp when results expire from KV cache (24-hour TTL per v2.4 API contract)
    public let expiresAt: String?

    public struct BookPayload: Codable, Sendable, Equatable {
        public let title: String
        public let author: String
        public let isbn: String?
        public let format: String?  // Format from Gemini: "hardcover", "paperback", "mass-market", "unknown"
        public let confidence: Double
        public let boundingBox: BoundingBoxPayload
        public let enrichment: EnrichmentPayload?

        public struct BoundingBoxPayload: Codable, Sendable, Equatable {
            public let x1: Double
            public let y1: Double
            public let x2: Double
            public let y2: Double
        }

        public struct EnrichmentPayload: Codable, Sendable, Equatable {
            public let status: String
            public let work: WorkDTO?
            public let editions: [EditionDTO]?
            public let authors: [AuthorDTO]?
            public let provider: String?
            public let cachedResult: Bool?
        }
    }

    public struct ScanMetadataPayload: Codable, Sendable, Equatable {
        public let processingTime: Int
        public let enrichedCount: Int
        public let timestamp: String
        public let modelUsed: String
    }
}
