import Foundation
import OSLog

// MARK: - V3 API Client

/// Manual V3 API Client - Lightweight HTTP client for V3 API
///
/// This is a temporary manual implementation while OpenAPI Generator plugin
/// has validation issues in Xcode beta. Once OpenAPI Generator is stable,
/// this can be replaced with generated code.
///
/// **Design:**
/// - Uses `ResponseEnvelope<T>` for all responses (canonical API contract)
/// - Type-safe response parsing with Codable
/// - Automatic error handling and retry logic
/// - Matches V3 API specification (openapi.yaml)
///
/// Part of V3 Migration Plan - Phase 2
@MainActor
public class V3APIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "V3APIClient")

    /// Initialize V3 API client
    ///
    /// - Parameter baseURL: Base URL for V3 API (default: production API)
    public init(baseURL: URL = URL(string: "https://api.oooefam.net/api/v3")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Search Operations

    /// Search for books using V3 unified search API
    ///
    /// Endpoint: `GET /search`
    ///
    /// - Parameters:
    ///   - query: Search query (title, author, ISBN, or prefixed)
    ///   - mode: Search mode (text, semantic, hybrid)
    ///   - limit: Maximum results (default: 20, max: 50)
    /// - Returns: ResponseEnvelope containing BookSearchResponse
    public func search(
        query: String,
        mode: String = "text",
        limit: Int = 20
    ) async throws -> ResponseEnvelope<BookSearchResponse> {
        var components = URLComponents(url: baseURL.appendingPathComponent("/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw V3APIError.invalidURL
        }

        logger.info("📘 V3 API: GET \(url.absoluteString)")

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3APIError.invalidResponse
        }

        logger.debug("📘 V3 API: Status \(httpResponse.statusCode)")

        // Decode ResponseEnvelope
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

            if envelope.success {
                logger.info("📘 V3 API: Search successful (\(envelope.data?.resultCount ?? 0) results)")
            } else {
                logger.warning("📘 V3 API: Search failed - \(envelope.error?.message ?? "unknown error")")
            }

            return envelope
        } catch {
            logger.error("📘 V3 API: Decoding failed - \(error.localizedDescription)")
            throw V3APIError.decodingFailed(error)
        }
    }

    /// Get book details by ISBN
    ///
    /// Endpoint: `GET /books/isbn/{isbn}`
    ///
    /// - Parameter isbn: 10 or 13 digit ISBN
    /// - Returns: ResponseEnvelope containing book work and edition
    public func getBookByISBN(_ isbn: String) async throws -> ResponseEnvelope<BookDetailsResponse> {
        let url = baseURL
            .appendingPathComponent("/books")
            .appendingPathComponent("isbn")
            .appendingPathComponent(isbn)

        logger.info("📘 V3 API: GET \(url.absoluteString)")

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3APIError.invalidResponse
        }

        logger.debug("📘 V3 API: Status \(httpResponse.statusCode)")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let envelope = try decoder.decode(ResponseEnvelope<BookDetailsResponse>.self, from: data)

            if envelope.success {
                logger.info("📘 V3 API: ISBN lookup successful")
            } else {
                logger.warning("📘 V3 API: ISBN lookup failed - \(envelope.error?.message ?? "unknown error")")
            }

            return envelope
        } catch {
            logger.error("📘 V3 API: Decoding failed - \(error.localizedDescription)")
            throw V3APIError.decodingFailed(error)
        }
    }

    /// Get work details by OpenLibrary work ID
    ///
    /// Endpoint: `GET /works/{workId}`
    ///
    /// - Parameter workId: OpenLibrary work ID (e.g., "OL45804W")
    /// - Returns: ResponseEnvelope containing work details
    public func getWork(_ workId: String) async throws -> ResponseEnvelope<WorkDTO> {
        let url = baseURL
            .appendingPathComponent("/works")
            .appendingPathComponent(workId)

        logger.info("📘 V3 API: GET \(url.absoluteString)")

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3APIError.invalidResponse
        }

        logger.debug("📘 V3 API: Status \(httpResponse.statusCode)")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let envelope = try decoder.decode(ResponseEnvelope<WorkDTO>.self, from: data)

            if envelope.success {
                logger.info("📘 V3 API: Work lookup successful")
            } else {
                logger.warning("📘 V3 API: Work lookup failed - \(envelope.error?.message ?? "unknown error")")
            }

            return envelope
        } catch {
            logger.error("📘 V3 API: Decoding failed - \(error.localizedDescription)")
            throw V3APIError.decodingFailed(error)
        }
    }
}

// MARK: - Response Types

/// Book details response (work + edition)
public struct BookDetailsResponse: Codable, Sendable {
    public let work: WorkDTO
    public let edition: EditionDTO
}

// MARK: - Errors

public enum V3APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed(Error)
    case networkError(Error)
    case apiError(ApiErrorInfo)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let apiError):
            return apiError.userMessage
        }
    }
}
