import Foundation

actor BooksTrackAPI {
    let baseURL: URL  // Internal for extensions
    let session: URLSession  // Internal for extensions
    let decoder: JSONDecoder  // Internal for extensions
    private let clientVersion: String

    init(baseURL: URL = URL(string: "https://api.oooefam.net")!, session: URLSession? = nil) {
        self.baseURL = baseURL

        // Configure URLSession with 10s request and 30s resource timeouts as default for GET requests
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0 // Default for GET
        config.timeoutIntervalForResource = 30.0
        self.session = session ?? URLSession(configuration: config)

        self.decoder = JSONDecoder()
        // Backend uses camelCase (retryAfterMs, traceId, statusCode) per API_CONTRACT.md
        // No key decoding strategy needed

        // Extract client version from Info.plist
        self.clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Decodes canonical `ResponseEnvelope` and extracts data or throws `APIError`.
    /// - Parameters:
    ///   - type: The `Decodable` type expected in the `data` field.
    ///   - data: The raw `Data` received from the network request.
    /// - Returns: An instance of `T` decoded from the `data` field.
    /// - Throws: `APIError` if envelope contains error or data is missing.
    func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T where T: Codable {
        let envelope: ResponseEnvelope<T>
        do {
            envelope = try decoder.decode(ResponseEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decodingError(message: "Failed to decode ResponseEnvelope: \(error.localizedDescription)")
        }

        // Use success discriminator (backend contract from FRONTEND_HANDOFF.md)
        guard envelope.success else {
            // Error case: envelope.success == false
            guard let error = envelope.error else {
                throw APIError.decodingError(message: "Response has success=false but no error field")
            }

            // Map canonical ApiErrorInfo to our APIError enum
            if let code = error.code {
                // Try to map known error codes with safe casting
                if code == "CIRCUIT_OPEN" {
                    // Safe parsing of circuit breaker details
                    if let details = error.details?.value as? [String: Any],
                       let provider = details["provider"] as? String,
                       let retryAfterMs = details["retryAfterMs"] as? Int {
                        throw APIError.circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
                    }
                    // If details parsing fails, fall through to generic server error
                }

                if code == "RATE_LIMIT_EXCEEDED" {
                    throw APIError.rateLimitExceeded(retryAfter: nil) // Will get from headers
                }

                if code == "NOT_FOUND" {
                    throw APIError.notFound(message: error.message)
                }
            }
            throw APIError.serverError(message: error.message)
        }

        // Success case: envelope.success == true
        // Extract data or throw
        guard let result = envelope.data else {
            throw APIError.decodingError(message: "Response has success=true but missing data field")
        }

        return result
    }

    /// Constructs a `URLRequest` with common headers.
    /// - Parameters:
    ///   - url: The full `URL` for the request.
    ///   - method: The HTTP method (e.g., "GET", "POST"). Defaults to "GET".
    ///   - body: Optional `Data` for the HTTP body.
    ///   - contentType: The `Content-Type` header value. Defaults to "application/json".
    /// - Returns: A configured `URLRequest`.
    func makeRequest(url: URL, method: String = "GET", body: Data? = nil, contentType: String? = "application/json") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("ios-v\(clientVersion)", forHTTPHeaderField: "X-Client-Version")

        if let body = body {
            request.httpBody = body
        }
        return request
    }

    /// Validates the `URLResponse` for common HTTP errors, rate limits, and CORS.
    /// - Parameter response: The `URLResponse` to validate.
    /// - Throws: An `APIError` if validation fails.
    func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // CORS detection (X-Custom-Error header)
        if let corsError = httpResponse.allHeaderFields["X-Custom-Error"] as? String, corsError == "CORS Blocked" {
            throw APIError.corsBlocked
        }

        // Rate limit detection (429 Too Many Requests)
        if httpResponse.statusCode == 429 {
            let retryAfterSeconds = (httpResponse.allHeaderFields["Retry-After"] as? String).flatMap(Double.init)
            throw APIError.rateLimitExceeded(retryAfter: retryAfterSeconds)
        }

        // Circuit Breaker detection (503 Service Unavailable)
        // If 503, the actual circuit breaker details (provider, retryAfterMs) are in the body,
        // so we just throw a generic 503 here, and decodeEnvelope will pick up the specifics.
        if httpResponse.statusCode == 503 {
            throw APIError.httpError(503) // Await decodeEnvelope for specific circuitOpen error
        }

        // Other HTTP status validation
        switch httpResponse.statusCode {
        case 200..<300:
            return // Success
        case 401:
            throw APIError.unauthorized(message: "Authentication required.")
        case 404:
            throw APIError.notFound(message: "The requested resource was not found.")
        case 400..<500:
            throw APIError.httpError(httpResponse.statusCode) // Client error
        case 500..<600:
            throw APIError.serverError(message: "Server encountered an error.")
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    /// Performs the network request and handles common error flows.
    /// - Parameter request: The `URLRequest` to execute.
    /// - Returns: A tuple containing the `Data` and `URLResponse`.
    /// - Throws: An `APIError` if the request fails or response is invalid.
    func performRequest(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            return (data, response)
        } catch let urlError as URLError {
            throw APIError.networkError(urlError)
        } catch {
            throw APIError(error) // Wrap any other error into APIError if not already one
        }
    }
}
