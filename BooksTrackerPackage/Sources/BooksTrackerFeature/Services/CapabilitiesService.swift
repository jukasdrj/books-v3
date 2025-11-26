import Foundation
import OSLog

public actor CapabilitiesService {
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "CapabilitiesService")

    // Cache properties
    private var cachedCapabilities: APICapabilities?
    private var lastFetchTimestamp: Date?
    private let cacheTTL: TimeInterval = 3600 // 1 hour in seconds

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    public func fetchCapabilities() async throws -> APICapabilities {
        if let cached = cachedCapabilities, let lastFetch = lastFetchTimestamp, Date().timeIntervalSince(lastFetch) < cacheTTL {
            logger.info("✅ Returning cached capabilities.")
            return cached
        }

        logger.info("🚀 Fetching capabilities from network...")
        let urlString = "https://api.oooefam.net/api/v2/capabilities"
        guard let url = URL(string: urlString) else {
            throw CapabilitiesError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            logger.error("🚨 Network request failed: \(error.localizedDescription)")
            throw CapabilitiesError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CapabilitiesError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("🚨 Received HTTP status code: \(httpResponse.statusCode)")
            throw CapabilitiesError.httpError(httpResponse.statusCode)
        }

        do {
            let capabilities = try JSONDecoder().decode(APICapabilities.self, from: data)
            self.cachedCapabilities = capabilities
            self.lastFetchTimestamp = Date()
            logger.info("✅ Successfully fetched and cached new capabilities. Version: \(capabilities.version)")
            return capabilities
        } catch {
            logger.error("🚨 Failed to decode capabilities response: \(error.localizedDescription)")
            throw CapabilitiesError.decodingError(error)
        }
    }
}

public enum CapabilitiesError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL for the capabilities endpoint was invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let code):
            return "The server returned an HTTP error: \(code)."
        case .decodingError:
            return "Failed to decode the capabilities response from the server."
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)."
        }
    }
}
