import Foundation

// MARK: - Empty Response Type
public struct EmptyResponse: Codable, Sendable {}

// NOTE: ResponseEnvelope is defined in DTOs/ResponseEnvelope.swift (canonical backend contract)

// MARK: - Book DTO (Simple version for Search/Import responses)
public struct BookDTO: Codable, Sendable, Hashable {
    public let isbn: String?
    public let title: String
    public let authors: [String]?
    public let publisher: String?
    public let description: String?
    public let pageCount: Int?
    public let categories: [String]?
    public let language: String?
    public let coverUrl: URL?
    public let averageRating: Double?
}

// NOTE: EnrichedBookDTO is defined in DTOs/EnrichedBookDTO.swift (canonical contract)

// MARK: - Import DTOs

/// Response from initiating a CSV import or enrichment batch job
public struct JobInitiationResponse: Codable, Sendable {
    public let jobId: String
    public let authToken: String
}

public struct ImportResults: Codable, Sendable {
    public let booksCreated: Int
    public let booksUpdated: Int
    public let duplicatesSkipped: Int
    public let enrichmentSucceeded: Int
    public let enrichmentFailed: Int
    public let errors: [String]
    public let books: [BookDTO]? // Array of simple BookDTO for CSV import results
}

/// Backend import job status (v2 /api/v2/imports/:jobId endpoint)
/// NOTE: This is distinct from the client-side JobStatus enum in Common/JobModels.swift
public struct ImportJobStatus: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending = "PENDING"
        case processing = "PROCESSING"
        case completed = "COMPLETED"
        case failed = "FAILED"
        case cancelled = "CANCELLED"
    }
    public let jobId: String
    public let status: Status
    public let progress: Double?
    public let totalCount: Int?
    public let processedCount: Int?
    public let pipeline: String?
}

public struct JobCancellationResponse: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let message: String
}
