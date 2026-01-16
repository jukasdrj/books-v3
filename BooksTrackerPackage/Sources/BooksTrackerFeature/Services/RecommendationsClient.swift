import Foundation
import OSLog

/// Client for fetching personalized book recommendations from the bendv3 API
/// Architecture: Separate from V3APIClientActual due to different error schema
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
    /// Strategy Selection:
    /// - `preference_based`: User has 4-5 star ratings in history
    /// - `cold_start`: User has preferences but no ratings
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
        let endpoint = debug ? "/api/recommendations/debug" : "/api/recommendations"
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

            // 6. Decode Envelope
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let envelope = try decoder.decode(APIEnvelope<RecommendationResult>.self, from: data)

            // 7. Validate Business Logic Success
            guard envelope.success, let result = envelope.data else {
                let errorMessage = envelope.error ?? "Unknown error"
                logger.warning("📚 API returned failure: \(errorMessage)")

                // Map specific string errors to typed enums
                if errorMessage.localizedCaseInsensitiveContains("no preferences") ||
                   errorMessage.localizedCaseInsensitiveContains("no ratings") ||
                   errorMessage.localizedCaseInsensitiveContains("insufficient history") {
                    throw RecommendationError.insufficientHistory
                }

                throw RecommendationError.apiError(message: errorMessage)
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
