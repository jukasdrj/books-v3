import Foundation
@testable import BooksTrackerFeature

// MARK: - ResponseMetadata Test Factory

extension ResponseMetadata {
    /// Creates a mock ResponseMetadata for testing
    static func mock(
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        traceId: String? = UUID().uuidString,
        processingTime: Int? = 42,
        provider: String? = "test-provider",
        cached: Bool? = false
    ) -> ResponseMetadata {
        // Use JSONDecoder since ResponseMetadata has no public init
        let json: [String: Any?] = [
            "timestamp": timestamp,
            "traceId": traceId,
            "processingTime": processingTime,
            "provider": provider,
            "cached": cached
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(ResponseMetadata.self, from: data)
    }
}

// MARK: - ResponseEnvelope Test Factories

extension ResponseEnvelope {
    /// Creates a successful ResponseEnvelope for testing
    static func mockSuccess(
        data: T,
        metadata: ResponseMetadata = .mock()
    ) -> ResponseEnvelope<T> {
        ResponseEnvelope(
            success: true,
            data: data,
            metadata: metadata,
            error: nil
        )
    }

    /// Creates a failed ResponseEnvelope for testing (RFC 9457 format)
    static func mockFailure(
        detail: String,
        type: String? = nil,
        title: String? = nil,
        status: Int? = nil,
        instance: String? = nil,
        code: String? = nil,
        statusCode: Int? = nil,
        retryable: Bool? = nil,
        metadata: ResponseMetadata = .mock()
    ) -> ResponseEnvelope<T> {
        ResponseEnvelope(
            success: false,
            data: nil,
            metadata: metadata,
            error: ApiErrorInfo(
                type: type,
                title: title,
                status: status,
                detail: detail,
                instance: instance,
                message: nil,  // RFC 9457 format doesn't use message
                code: code,
                details: nil,
                statusCode: statusCode,
                retryable: retryable,
                retryAfterMs: nil
            )
        )
    }

    /// Creates a failed ResponseEnvelope for testing (Legacy format - backward compatibility)
    /// This version uses the old `message` field for testing legacy backend responses
    static func mockFailureLegacy(
        message: String,
        code: String? = nil,
        statusCode: Int? = nil,
        retryable: Bool? = nil,
        metadata: ResponseMetadata = .mock()
    ) -> ResponseEnvelope<T> {
        ResponseEnvelope(
            success: false,
            data: nil,
            metadata: metadata,
            error: ApiErrorInfo(
                type: nil,
                title: nil,
                status: nil,
                detail: message,  // Custom decoder will use this
                instance: nil,
                message: message,  // Legacy field
                code: code,
                details: nil,
                statusCode: statusCode,
                retryable: retryable,
                retryAfterMs: nil
            )
        )
    }
}

// MARK: - ApiResponse Test Factories

extension ApiResponse {
    /// Creates a successful ApiResponse for testing
    static func mockSuccess(
        data: T,
        metadata: ResponseMetadata = .mock()
    ) -> ApiResponse<T> {
        .success(data, metadata)
    }

    /// Creates a failed ApiResponse for testing (RFC 9457 format)
    static func mockFailure(
        detail: String,
        type: String? = nil,
        title: String? = nil,
        status: Int? = nil,
        instance: String? = nil,
        code: String? = nil,
        statusCode: Int? = nil,
        retryable: Bool? = nil,
        metadata: ResponseMetadata = .mock()
    ) -> ApiResponse<T> {
        .failure(
            ApiErrorInfo(
                type: type,
                title: title,
                status: status,
                detail: detail,
                instance: instance,
                message: nil,
                code: code,
                details: nil,
                statusCode: statusCode,
                retryable: retryable,
                retryAfterMs: nil
            ),
            metadata
        )
    }

    /// Creates a failed ApiResponse for testing (Legacy format - backward compatibility)
    static func mockFailureLegacy(
        message: String,
        code: String? = nil,
        statusCode: Int? = nil,
        retryable: Bool? = nil,
        metadata: ResponseMetadata = .mock()
    ) -> ApiResponse<T> {
        .failure(
            ApiErrorInfo(
                type: nil,
                title: nil,
                status: nil,
                detail: message,
                instance: nil,
                message: message,
                code: code,
                details: nil,
                statusCode: statusCode,
                retryable: retryable,
                retryAfterMs: nil
            ),
            metadata
        )
    }
}

// MARK: - CSVParsedBook Test Factory

extension CSVParsedBook {
    /// Creates a CSVParsedBook for testing (uses JSON decode since no public init)
    static func mock(
        title: String,
        authors: [String] = [],
        isbn: String? = nil,
        coverUrl: String? = nil,
        publisher: String? = nil,
        year: Int? = nil,
        pageCount: Int? = nil,
        language: String? = nil,
        enrichmentError: String? = nil
    ) -> CSVParsedBook {
        var json: [String: Any] = ["title": title]
        if !authors.isEmpty { json["authors"] = authors }
        if let isbn { json["isbn"] = isbn }
        if let coverUrl { json["coverUrl"] = coverUrl }
        if let publisher { json["publisher"] = publisher }
        if let year { json["year"] = year }
        if let pageCount { json["pageCount"] = pageCount }
        if let language { json["language"] = language }
        if let enrichmentError { json["enrichmentError"] = enrichmentError }

        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(CSVParsedBook.self, from: data)
    }
}
