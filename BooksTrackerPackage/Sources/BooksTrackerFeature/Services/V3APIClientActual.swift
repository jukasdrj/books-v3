import Foundation
import OSLog

// MARK: - V3 API Client (True V3 Implementation)

/// V3 API Client - True V3 implementation using actual V3 DTOs
///
/// This is the production V3 API client that uses the true V3 response format
/// (unified Book model, no Work/Edition/Author separation).
///
/// **Design:**
/// - Uses V3* DTOs matching openapi-v3.json exactly
/// - ETag caching support for conditional requests
/// - RFC 9457 Problem Details error handling
/// - Request ID tracking (X-Request-ID header)
/// - Automatic retry for transient failures
///
/// **Endpoints:**
/// - `GET /v3/books/search` - Search books
/// - `GET /v3/books/{isbn}` - Get book by ISBN
/// - `POST /v3/books/enrich` - Batch enrich ISBNs
///
/// Part of V3 Migration Plan - Phase 1
@MainActor
public class V3APIClientActual {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "V3APIClientActual")

    /// ETag cache for conditional requests
    private var etagCache: [String: String] = [:]

    /// Initialize V3 API client
    ///
    /// - Parameter baseURL: Base URL for V3 API (default: production API)
    public init(baseURL: URL = URL(string: "https://api.oooefam.net")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // 30s for enrich operations
        config.timeoutIntervalForResource = 60.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Search Operations

    /// Search for books using V3 unified search API
    ///
    /// Endpoint: `GET /v3/books/search`
    ///
    /// - Parameters:
    ///   - query: Search query (book title to search for)
    ///   - page: Page number for offset pagination (default: 1)
    ///   - limit: Results per page (default: 20, max: 100)
    /// - Returns: V3SearchResponse with books array and pagination
    /// - Throws: V3APIError for network or API errors
    public func search(
        query: String,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> V3SearchResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v3/books/search"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw V3ActualAPIError.invalidURL
        }

        logger.info("📘 V3 Search: GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0  // 5s for search operations
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequestWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3ActualAPIError.invalidResponse
        }

        logger.debug("📘 V3 Search: Status \(httpResponse.statusCode)")

        // Track request ID from headers
        if let requestId = httpResponse.value(forHTTPHeaderField: "X-Request-ID") {
            logger.debug("📘 V3 Search: Request-ID \(requestId)")
        }

        // Handle error responses
        if httpResponse.statusCode >= 400 {
            return try handleErrorResponse(data: data, statusCode: httpResponse.statusCode)
        }

        // Decode success response
        let decoder = JSONDecoder()

        do {
            let searchResponse = try decoder.decode(V3SearchResponse.self, from: data)

            if searchResponse.success {
                logger.info("📘 V3 Search: Success - \(searchResponse.data.books.count) books, total \(searchResponse.data.total)")
            } else {
                logger.warning("📘 V3 Search: Unexpected success=false in 200 response")
            }

            return searchResponse
        } catch {
            logger.error("📘 V3 Search: Decoding failed - \(error.localizedDescription)")
            throw V3ActualAPIError.decodingFailed(error)
        }
    }

    // MARK: - ISBN Lookup

    /// Get book details by ISBN with ETag caching support
    ///
    /// Endpoint: `GET /v3/books/{isbn}`
    ///
    /// - Parameter isbn: 10 or 13 digit ISBN
    /// - Returns: V3Book with complete metadata
    /// - Throws: V3APIError for network or API errors
    public func getBook(isbn: String) async throws -> V3Book {
        let url = baseURL.appendingPathComponent("/v3/books/\(isbn)")

        logger.info("📘 V3 GetBook: GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0  // 5s for ISBN lookups
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add ETag for conditional request if cached
        if let cachedETag = etagCache[isbn] {
            request.setValue(cachedETag, forHTTPHeaderField: "If-None-Match")
            logger.debug("📘 V3 GetBook: Using cached ETag \(cachedETag)")
        }

        let (data, response) = try await performRequestWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3ActualAPIError.invalidResponse
        }

        logger.debug("📘 V3 GetBook: Status \(httpResponse.statusCode)")

        // Handle 304 Not Modified (ETag match)
        if httpResponse.statusCode == 304 {
            logger.info("📘 V3 GetBook: 304 Not Modified (ETag match)")
            throw V3ActualAPIError.notModified
        }

        // Cache new ETag
        if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
            etagCache[isbn] = newETag
            logger.debug("📘 V3 GetBook: Cached ETag \(newETag)")
        }

        // Handle error responses
        if httpResponse.statusCode >= 400 {
            return try handleErrorResponse(data: data, statusCode: httpResponse.statusCode)
        }

        // Decode success response
        let decoder = JSONDecoder()

        do {
            let bookResponse = try decoder.decode(V3BookResponse.self, from: data)

            if bookResponse.success {
                logger.info("📘 V3 GetBook: Success - \(bookResponse.data.title)")
            } else {
                logger.warning("📘 V3 GetBook: Unexpected success=false in 200 response")
            }

            return bookResponse.data
        } catch {
            logger.error("📘 V3 GetBook: Decoding failed - \(error.localizedDescription)")
            throw V3APIError.decodingFailed(error)
        }
    }

    // MARK: - Batch Enrichment

    /// Enrich books with metadata from Alexandria
    ///
    /// Endpoint: `POST /v3/books/enrich`
    ///
    /// - Parameters:
    ///   - isbns: Array of ISBNs to enrich (1-50)
    ///   - includeEmbedding: Generate semantic embeddings for vector search (default: false)
    /// - Returns: V3EnrichResponse with enriched books
    /// - Throws: V3APIError for network or API errors
    public func enrichBooks(
        isbns: [String],
        includeEmbedding: Bool = false
    ) async throws -> V3EnrichResponse {
        let url = baseURL.appendingPathComponent("/v3/books/enrich")

        logger.info("📘 V3 Enrich: POST \(url.absoluteString) - \(isbns.count) ISBNs")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0  // 30s for batch operations
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Create request payload
        let enrichRequest = V3EnrichRequest(isbns: isbns, includeEmbedding: includeEmbedding)

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(enrichRequest)

        let (data, response) = try await performRequestWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw V3ActualAPIError.invalidResponse
        }

        logger.debug("📘 V3 Enrich: Status \(httpResponse.statusCode)")

        // Handle error responses
        if httpResponse.statusCode >= 400 {
            return try handleErrorResponse(data: data, statusCode: httpResponse.statusCode)
        }

        // Decode success response
        let decoder = JSONDecoder()

        do {
            let enrichResponse = try decoder.decode(V3EnrichResponse.self, from: data)

            if enrichResponse.success {
                logger.info("📘 V3 Enrich: Success - \(enrichResponse.data.found)/\(enrichResponse.data.requested) books found")
            } else {
                logger.warning("📘 V3 Enrich: Unexpected success=false in 200 response")
            }

            return enrichResponse
        } catch {
            logger.error("📘 V3 Enrich: Decoding failed - \(error.localizedDescription)")
            throw V3APIError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    /// Perform HTTP request with automatic retry for transient failures
    private func performRequestWithRetry(
        _ request: URLRequest,
        maxRetries: Int = 2
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await urlSession.data(for: request)
            } catch {
                lastError = error

                // Check if error is retryable
                if let urlError = error as? URLError {
                    let retryable = urlError.code == .timedOut ||
                                    urlError.code == .networkConnectionLost ||
                                    urlError.code == .cannotConnectToHost

                    if retryable && attempt < maxRetries - 1 {
                        let delay = Double(attempt + 1) * 0.5  // 0.5s, 1.0s exponential backoff
                        logger.warning("📘 V3 API: Retry attempt \(attempt + 1) after \(delay)s")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                // Non-retryable error or max retries reached
                throw error
            }
        }

        throw lastError ?? V3ActualAPIError.networkError(URLError(.unknown))
    }

    /// Handle RFC 9457 error responses
    private func handleErrorResponse<T>(data: Data, statusCode: Int) throws -> T {
        let decoder = JSONDecoder()

        do {
            let errorResponse = try decoder.decode(V3ErrorResponse.self, from: data)

            logger.error("📘 V3 API Error: [\(errorResponse.code.rawValue)] \(errorResponse.title)")
            if let detail = errorResponse.detail {
                logger.error("📘 V3 API Error Detail: \(detail)")
            }

            throw V3ActualAPIError.apiError(errorResponse)
        } catch let decodingError as DecodingError {
            logger.error("📘 V3 API: Failed to decode error response - \(decodingError.localizedDescription)")

            // Fallback to generic error
            throw V3ActualAPIError.httpError(statusCode: statusCode)
        } catch {
            // Re-throw V3ActualAPIError.apiError
            throw error
        }
    }
}

// MARK: - Errors

public enum V3ActualAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed(Error)
    case networkError(URLError)
    case apiError(V3ErrorResponse)
    case httpError(statusCode: Int)
    case notModified  // 304 for ETag match

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
        case .apiError(let errorResponse):
            return errorResponse.detail ?? errorResponse.title
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .notModified:
            return "Resource not modified (304)"
        }
    }

    /// Whether this error is retryable
    public var isRetryable: Bool {
        switch self {
        case .networkError(let urlError):
            return urlError.code == .timedOut ||
                   urlError.code == .networkConnectionLost ||
                   urlError.code == .cannotConnectToHost
        case .apiError(let errorResponse):
            return errorResponse.retryable ?? false
        case .httpError(let statusCode):
            return statusCode == 429 || statusCode == 503
        default:
            return false
        }
    }
}

// MARK: - Type Aliases

/// Legacy name compatibility for V3ActualAPIError
public typealias V3APIError = V3ActualAPIError
