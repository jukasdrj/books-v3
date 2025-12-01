//
//  Data+ResponseEnvelope.swift
//  BooksTrackerFeature
//
//  Created by Claude on 2025-12-01.
//
//  Unified decoder for ResponseEnvelope<T> across all API clients.
//  Eliminates ~105 lines of duplication while preserving flexible error handling.
//

import Foundation

// MARK: - Data Extension

public extension Data {
    /// Decodes a ResponseEnvelope<T> and extracts the wrapped data.
    ///
    /// - Parameter type: The type to decode from the envelope's data field
    /// - Returns: The decoded data of type T
    /// - Throws: ResponseEnvelopeError if envelope contains error or missing data
    ///
    /// Example:
    /// ```swift
    /// let book = try data.decodeEnvelope(EnrichedBookDTO.self)
    /// ```
    func decodeEnvelope<T: Codable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()

        do {
            let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: self)

            // Check for API error in envelope
            if let error = envelope.error {
                // Convert AnyCodable? to [String: Any]?
                let detailsDict = error.details?.value as? [String: Any]

                throw ResponseEnvelopeError.apiError(
                    code: error.code,
                    message: error.message,
                    details: detailsDict
                )
            }

            // Ensure data exists
            guard let result = envelope.data else {
                throw ResponseEnvelopeError.missingData
            }

            return result

        } catch let error as ResponseEnvelopeError {
            // Already a ResponseEnvelopeError, rethrow as-is
            throw error
        } catch {
            // Decoding failed - wrap in ResponseEnvelopeError
            throw ResponseEnvelopeError.decodingFailed(error)
        }
    }
}

// MARK: - ResponseEnvelopeError

/// Errors that can occur when decoding ResponseEnvelope<T>
/// @unchecked Sendable: Details dictionary contains error metadata from backend,
/// which is safe to pass across actor boundaries for error reporting.
public enum ResponseEnvelopeError: Error, LocalizedError, @unchecked Sendable {
    /// API returned an error in the envelope's error field
    case apiError(code: String?, message: String, details: [String: Any]?)

    /// Envelope decoded successfully but data field was null
    case missingData

    /// Failed to decode the envelope structure itself
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let message, _):
            if let code = code {
                return "API Error [\(code)]: \(message)"
            }
            return "API Error: \(message)"

        case .missingData:
            return "Response envelope contained no data"

        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }

    /// Extracts a typed detail value from API error details dictionary
    ///
    /// Example:
    /// ```swift
    /// if case .apiError = error {
    ///     let retryAfter: Int? = error.detail("retryAfter")
    /// }
    /// ```
    public func detail<T>(_ key: String) -> T? {
        if case .apiError(_, _, let details) = self {
            return details?[key] as? T
        }
        return nil
    }
}
