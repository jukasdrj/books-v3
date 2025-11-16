//
//  ApiResponseHelpers.swift
//  BooksTrackerFeatureTests
//
//  Test utilities for creating mock ApiResponse objects
//

import Foundation
@testable import BooksTrackerFeature

// MARK: - ApiResponse Mock Helpers

extension ApiResponse {
    /// Create a mock success response for testing
    /// - Parameters:
    ///   - data: The data payload to wrap
    ///   - processingTime: Optional processing time in milliseconds
    ///   - provider: Optional provider name
    ///   - cached: Whether the response was cached
    /// - Returns: A mock success ApiResponse
    static func mockSuccess(
        data: T,
        processingTime: Int? = nil,
        provider: String? = nil,
        cached: Bool? = nil
    ) -> ApiResponse<T> {
        let meta = ResponseMeta(
            timestamp: "2025-11-04T12:00:00Z",
            processingTime: processingTime,
            provider: provider,
            cached: cached,
            cacheAge: nil,
            requestId: nil
        )
        return .success(data, meta)
    }

    /// Create a mock error response for testing
    /// - Parameters:
    ///   - message: Error message
    ///   - code: Optional error code
    ///   - details: Optional error details
    ///   - processingTime: Optional processing time in milliseconds
    /// - Returns: A mock failure ApiResponse
    static func mockFailure(
        message: String,
        code: DTOApiErrorCode? = nil,
        details: Any? = nil,
        processingTime: Int? = nil
    ) -> ApiResponse<T> {
        let apiError = ApiResponse<T>.ApiError(
            message: message,
            code: code,
            details: details != nil ? AnyCodable(details!) : nil
        )
        let meta = ResponseMeta(
            timestamp: "2025-11-04T12:00:00Z",
            processingTime: processingTime,
            provider: nil,
            cached: nil,
            cacheAge: nil,
            requestId: nil
        )
        return .failure(apiError, meta)
    }
}

// MARK: - BookSearchResponse Mock Helpers

extension BookSearchResponse {
    /// Create a mock empty search response
    static func mockEmpty() -> BookSearchResponse {
        BookSearchResponse(works: [], editions: [], authors: [], totalResults: 0)
    }

    /// Create a mock search response with sample data
    static func mockWithWork(title: String = "Test Book", authorName: String = "Test Author") -> BookSearchResponse {
        let work = WorkDTO(
            title: title,
            subjectTags: ["Fiction"],
            originalLanguage: "en",
            firstPublicationYear: 2020,
            description: "A test book",
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: "OL12345W",
            isbndbID: nil,
            googleBooksVolumeID: "test123",
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["test123"],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let author = AuthorDTO(
            name: authorName,
            gender: .unknown,
            culturalRegion: nil,
            nationality: nil,
            birthYear: nil,
            deathYear: nil,
            openLibraryID: nil,
            isbndbID: nil,
            googleBooksID: nil,
            goodreadsID: nil,
            bookCount: nil
        )

        return BookSearchResponse(works: [work], editions: [], authors: [author], totalResults: 1)
    }
}

// MARK: - EnrichmentJobResponse Mock Helpers

extension EnrichmentJobResponse {
    /// Create a mock enrichment job response
    static func mock(
        jobId: String = "test-job-123",
        queuedCount: Int = 5,
        estimatedDuration: Int? = 60,
        websocketUrl: String = "wss://example.com/ws"
    ) -> EnrichmentJobResponse {
        EnrichmentJobResponse(
            jobId: jobId,
            queuedCount: queuedCount,
            estimatedDuration: estimatedDuration,
            websocketUrl: websocketUrl
        )
    }
}
