//
//  ResponseEnvelopeHelpers.swift
//  BooksTrackerFeatureTests
//
//  Test utilities for creating mock ResponseEnvelope objects
//

import Foundation
@testable import BooksTrackerFeature

// MARK: - ResponseEnvelope Mock Helpers

extension ResponseEnvelope {
    /// Create a mock success response for testing
    /// - Parameters:
    ///   - data: The data payload to wrap
    ///   - processingTime: Optional processing time in milliseconds
    ///   - provider: Optional provider name
    ///   - cached: Whether the response was cached
    ///   - traceId: Optional trace ID for distributed tracing
    /// - Returns: A mock success ResponseEnvelope
    static func mockSuccess(
        data: T,
        processingTime: Int? = nil,
        provider: String? = nil,
        cached: Bool? = nil,
        traceId: String? = nil
    ) -> ResponseEnvelope<T> {
        let metadata = ResponseMetadata(
            timestamp: "2025-11-18T12:00:00Z",
            traceId: traceId,
            processingTime: processingTime,
            provider: provider,
            cached: cached
        )
        return ResponseEnvelope(data: data, metadata: metadata, error: nil)
    }

    /// Create a mock error response for testing
    /// - Parameters:
    ///   - message: Error message
    ///   - code: Optional error code
    ///   - details: Optional error details
    ///   - processingTime: Optional processing time in milliseconds
    /// - Returns: A mock failure ResponseEnvelope
    static func mockFailure(
        message: String,
        code: String? = nil,
        details: Any? = nil,
        processingTime: Int? = nil
    ) -> ResponseEnvelope<T> {
        let apiError = ResponseEnvelope<T>.ApiErrorInfo(
            message: message,
            code: code,
            details: details != nil ? AnyCodable(details!) : nil
        )
        let metadata = ResponseMetadata(
            timestamp: "2025-11-18T12:00:00Z",
            traceId: nil,
            processingTime: processingTime,
            provider: nil,
            cached: nil
        )
        return ResponseEnvelope(data: nil, metadata: metadata, error: apiError)
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

// MARK: - SimilarBooksResponse Mock Helpers

extension SimilarBooksResponse {
    /// Create a mock similar books response for testing
    static func mock(
        sourceIsbn: String = "9780747532743",
        results: [SimilarBookItem] = [],
        total: Int = 0,
        latencyMs: Int? = 85
    ) -> SimilarBooksResponse {
        SimilarBooksResponse(
            results: results,
            sourceIsbn: sourceIsbn,
            total: total,
            latencyMs: latencyMs
        )
    }
    
    /// Create a mock similar book item
    static func mockItem(
        isbn: String = "9780439064866",
        title: String = "Harry Potter and the Chamber of Secrets",
        authors: [String] = ["J.K. Rowling"],
        similarityScore: Double = 0.94,
        coverUrl: String? = "https://example.com/cover.jpg"
    ) -> SimilarBookItem {
        SimilarBookItem(
            isbn: isbn,
            title: title,
            authors: authors,
            similarityScore: similarityScore,
            coverUrl: coverUrl
        )
    }
}
