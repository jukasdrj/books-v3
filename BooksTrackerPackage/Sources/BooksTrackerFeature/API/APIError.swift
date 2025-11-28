import Foundation

public enum APIError: Error, LocalizedError, Decodable, Sendable {
    case circuitOpen(provider: String, retryAfterMs: Int)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case notFound(message: String)
    case serverError(message: String)
    case decodingError(message: String)
    case networkError(Error)
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case corsBlocked
    case unauthorized(message: String)
    case unknownError(message: String)

    // Helper struct for decoding backend error payload
    private struct BackendError: Decodable {
        let code: String
        let message: String?
        let provider: String?
        let retryAfterMs: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let backendError = try container.decode(BackendError.self)

        switch backendError.code {
        case "CIRCUIT_OPEN":
            guard let provider = backendError.provider, let retryAfterMs = backendError.retryAfterMs else {
                self = .decodingError(message: "Missing provider or retryAfterMs for CIRCUIT_OPEN error.")
                return
            }
            self = .circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
        case "RATE_LIMIT_EXCEEDED":
            // Backend might send retryAfterMs, or we might get Retry-After header
            // Prioritizing retryAfterMs from body if present, else nil for header parsing
            self = .rateLimitExceeded(retryAfter: backendError.retryAfterMs.map { TimeInterval($0 / 1000) })
        case "NOT_FOUND":
            self = .notFound(message: backendError.message ?? "Resource not found.")
        case "UNAUTHORIZED":
            self = .unauthorized(message: backendError.message ?? "Unauthorized access.")
        case "SERVER_ERROR":
            self = .serverError(message: backendError.message ?? "Server error occurred.")
        case "DECODING_ERROR": // This might be used by backend to signal decoding failure
            self = .decodingError(message: backendError.message ?? "Backend reported a decoding error.")
        default:
            self = .unknownError(message: backendError.message ?? "An unknown backend error occurred with code: \(backendError.code)")
        }
    }

    public var errorDescription: String? {
        switch self {
        case .circuitOpen(let provider, let retryAfterMs):
            return "Circuit for \(provider) is open. Please retry after \(retryAfterMs / 1000) seconds."
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Please retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .notFound(let message):
            return "Not Found: \(message)"
        case .serverError(let message):
            return "Server Error: \(message)"
        case .decodingError(let message):
            return "Decoding Error: \(message)"
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid Response"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .corsBlocked:
            return "CORS Blocked: Request was blocked by the server's CORS policy."
        case .unauthorized(let message):
            return "Unauthorized: \(message)"
        case .unknownError(let message):
            return "An unknown error occurred: \(message)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .circuitOpen, .rateLimitExceeded, .networkError:
            return true
        case .httpError(let statusCode):
            return (500..<600).contains(statusCode) // Generic server errors might be retryable
        default:
            return false
        }
    }

    public var retryDelay: TimeInterval? {
        switch self {
        case .circuitOpen(_, let retryAfterMs):
            return TimeInterval(retryAfterMs) / 1000.0
        case .rateLimitExceeded(let retryAfter):
            return retryAfter
        case .networkError:
            // A common strategy for network errors is exponential backoff,
            // but for a simple property, returning a small default or nil is okay.
            return 5.0 // Example default retry delay for transient network issues
        default:
            return nil
        }
    }

    // Custom initializer for non-decodable errors to conform to Error protocol
    public init(_ error: Error) {
        if let apiError = error as? APIError {
            self = apiError
        } else {
            self = .networkError(error) // Wrap any other error as a network error
        }
    }
}
