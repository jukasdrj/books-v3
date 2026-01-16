import Foundation
import OSLog

/// Client for fetching personalized book recommendations from the bendv3 API
/// Endpoint: /v3/recommendations/personalized (v3.4.3+)
/// Pattern: @MainActor for UI-safety, Sendable for Swift 6 strict concurrency
@MainActor
public final class RecommendationsClient: Sendable {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.bookstrack", category: "RecommendationsClient")

    /// Initialize with base API URL
    /// - Parameter baseURL: Base URL for the bendv3 API (default: https://api.oooefam.net)
    public init(baseURL: URL = URL(string: "https://api.oooefam.net")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch personalized book recommendations
    ///
    /// - Parameters:
    ///   - userId: The ID of the user to fetch recommendations for
    ///   - limit: Maximum number of recommendations (1-50, default 10)
    ///   - excludedISBNs: ISBNs to exclude from results (e.g., books already in library)
    /// - Returns: Recommendations with scores and strategy used
    /// - Throws: `RecommendationError` for various failure cases
    ///
    /// Strategy Selection (v3.4.3):
    /// - `preference_based`: User has 4-5 star ratings in history (requires Alexandria ratings API)
    /// - `cold_start`: User has preferences but no ratings
    /// - `weekly_fallback`: Fallback to weekly recommendations (current until Alexandria ready)
    ///
    /// Example:
    /// ```swift
    /// let result = try await client.getRecommendations(
    ///     userId: "user123",
    ///     limit: 10,
    ///     excludedISBNs: ["9780123456789"]
    /// )
    /// ```
    public func getRecommendations(
        userId: String,
        limit: Int = 10,
        excludedISBNs: [String] = []
    ) async throws -> RecommendationResult {
        return try await fetchRecommendations(
            userId: userId,
            limit: limit,
            excludedISBNs: excludedISBNs,
            debug: false
        )
    }

    /// Fetch recommendations with debug information
    ///
    /// Returns additional information about the recommendation engine's decision process:
    /// - User subjects extracted from reading history
    /// - Preference subjects from user settings
    /// - Number of candidate books evaluated
    /// - Score breakdown (subject match, preference match, diversity bonus)
    ///
    /// - Parameters:
    ///   - userId: The ID of the user to fetch recommendations for
    ///   - limit: Maximum number of recommendations (1-50, default 10)
    ///   - excludedISBNs: ISBNs to exclude from results
    /// - Returns: Recommendations with debug information
    /// - Throws: `RecommendationError` for various failure cases
    public func getRecommendationsDebug(
        userId: String,
        limit: Int = 10,
        excludedISBNs: [String] = []
    ) async throws -> RecommendationResult {
        return try await fetchRecommendations(
            userId: userId,
            limit: limit,
            excludedISBNs: excludedISBNs,
            debug: true
        )
    }

    // MARK: - Private Implementation

    /// Internal method to fetch recommendations with optional debug mode
    private func fetchRecommendations(
        userId: String,
        limit: Int,
        excludedISBNs: [String],
        debug: Bool
    ) async throws -> RecommendationResult {
        // 1. Validate parameters
        let clampedLimit = max(1, min(50, limit))

        // 2. Construct URL
        let endpoint = debug ? "/v3/recommendations/personalized/debug" : "/v3/recommendations/personalized"
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: true
        ) else {
            throw RecommendationError.invalidURL
        }

        var queryItems = [URLQueryItem(name: "limit", value: String(clampedLimit))]

        if !excludedISBNs.isEmpty {
            let joinedISBNs = excludedISBNs.joined(separator: ",")
            queryItems.append(URLQueryItem(name: "exclude", value: joinedISBNs))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw RecommendationError.invalidURL
        }

        // 3. Configure Request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "x-user-id")

        logger.info("📚 Recommendations: GET \(url.absoluteString) for User \(userId)")

        do {
            // 4. Perform Request
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RecommendationError.networkError(URLError(.badServerResponse))
            }

            // 5. Handle HTTP Errors (Non-200)
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("📚 HTTP Error: \(httpResponse.statusCode)")
                throw RecommendationError.serverError(statusCode: httpResponse.statusCode)
            }

            // 6. Decode V3 ResponseEnvelope
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let envelope = try decoder.decode(ResponseEnvelope<RecommendationResult>.self, from: data)

            // 7. Validate Business Logic Success
            guard let result = envelope.data else {
                // Handle error from envelope
                if let error = envelope.error {
                    logger.warning("📚 API returned failure: \(error.detail) (code: \(error.code ?? "none"))")

                    // Map specific error codes to typed enums
                    // Check code first (RFC 9457)
                    if error.code == "INSUFFICIENT_HISTORY" ||
                       error.detail.localizedCaseInsensitiveContains("no preferences") ||
                       error.detail.localizedCaseInsensitiveContains("no ratings") ||
                       error.detail.localizedCaseInsensitiveContains("insufficient history") {
                        throw RecommendationError.insufficientHistory
                    }

                    throw RecommendationError.apiError(message: error.detail)
                }

                // Invalid response (success without data)
                logger.error("📚 Invalid response: success without data")
                throw RecommendationError.apiError(message: "Invalid response from server")
            }

            logger.info("📚 Success: \(result.recommendations.count) books via \(result.strategy.rawValue)")
            return result

        } catch let error as RecommendationError {
            throw error
        } catch {
            logger.error("📚 Network/Decoding failed: \(error.localizedDescription)")
            throw RecommendationError.networkError(error)
        }
    }
}
