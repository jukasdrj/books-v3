import Foundation
import OSLog

/// Service for fetching AI-curated weekly book recommendations
///
/// **Architecture:**
/// - Swift 6.2 actor for thread-safe operation
/// - Fetches from GET /api/v2/recommendations/weekly
/// - Local caching with 1-week TTL
/// - Non-personalized global picks
///
/// **API Contract:**
/// - Backend: Cloudflare Workers with Gemini API
/// - Generated: Every Sunday at midnight UTC (cron job)
/// - Cached: KV with 1-week TTL
/// - Auth: No authentication required
///
/// **Error Handling:**
/// - 404: No recommendations yet (show next refresh date)
/// - 429: Rate limit (retry with exponential backoff)
/// - 500: Server error (retry with backoff)
///
/// **Concurrency:**
/// - Actor-isolated to prevent data races
/// - All methods are async and Sendable-safe
/// - Cache access is synchronized
///
/// See: docs/API_CONTRACT.md Section 6.5.4
public actor WeeklyRecommendationsService {
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "WeeklyRecommendationsService")
    private let urlSession: URLSession
    
    // MARK: - Local Cache
    
    private var cachedRecommendations: WeeklyRecommendationsDTO?
    private var cacheTimestamp: Date?
    
    /// Cache TTL: 1 week (matches backend refresh schedule)
    private let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    
    // MARK: - Initialization
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Fetch weekly recommendations with local caching
    ///
    /// **Behavior:**
    /// - Returns cached data if fresh (< 1 week old)
    /// - Fetches from API if cache expired or missing
    /// - Updates cache on successful fetch
    ///
    /// **Error Handling:**
    /// - 404: Returns nil (no recommendations available yet)
    /// - 429: Throws rateLimitExceeded
    /// - 5xx: Throws serverError
    /// - Network: Throws networkError
    ///
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    /// - Returns: Weekly recommendations or nil if none available
    /// - Throws: RecommendationsError on failure
    public func fetchWeeklyRecommendations(forceRefresh: Bool = false) async throws -> WeeklyRecommendationsDTO? {
        // Check cache if not forcing refresh
        if !forceRefresh, let cached = cachedRecommendations, let timestamp = cacheTimestamp {
            let age = Date().timeIntervalSince(timestamp)
            if age < cacheTTL {
                logger.info("📚 Returning cached weekly recommendations (age: \(Int(age))s)")
                return cached
            } else {
                logger.info("📚 Cache expired (age: \(Int(age))s), fetching fresh recommendations")
            }
        }
        
        // Fetch from API
        let endpoint = "\(EnrichmentConfig.baseURL)/api/v2/recommendations/weekly"
        guard let url = URL(string: endpoint) else {
            throw RecommendationsError.invalidURL
        }
        
        logger.info("📚 Fetching weekly recommendations from \(endpoint)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            logger.error("❌ Network error fetching recommendations: \(error.localizedDescription)")
            throw RecommendationsError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecommendationsError.invalidResponse
        }
        
        // Handle status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - parse response
            do {
                let recommendations = try JSONDecoder().decode(WeeklyRecommendationsDTO.self, from: data)
                
                // Update cache
                self.cachedRecommendations = recommendations
                self.cacheTimestamp = Date()
                
                logger.info("✅ Successfully fetched \(recommendations.books.count) weekly recommendations")
                return recommendations
                
            } catch {
                logger.error("❌ Failed to decode recommendations: \(error.localizedDescription)")
                throw RecommendationsError.decodingError(error)
            }
            
        case 404:
            // No recommendations available yet (expected state before first cron run)
            logger.info("ℹ️ No weekly recommendations available yet (404)")
            return nil
            
        case 429:
            // Rate limit exceeded
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            logger.warning("⚠️ Rate limit exceeded fetching recommendations (retry after: \(retryAfter ?? 60)s)")
            throw RecommendationsError.rateLimitExceeded(retryAfter: retryAfter)
            
        default:
            // Server error or unexpected status
            logger.error("❌ HTTP error fetching recommendations: \(httpResponse.statusCode)")
            throw RecommendationsError.httpError(httpResponse.statusCode)
        }
    }
    
    /// Clear local cache (useful for testing or manual refresh)
    public func clearCache() {
        cachedRecommendations = nil
        cacheTimestamp = nil
        logger.info("🗑️ Cleared weekly recommendations cache")
    }
}

// MARK: - Error Types

/// Errors that can occur when fetching weekly recommendations
public enum RecommendationsError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case rateLimitExceeded(retryAfter: Int?)
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid recommendations endpoint URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "Server error (HTTP \(statusCode))"
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please try again in \(seconds) seconds."
            }
            return "Too many requests. Please try again later."
        case .decodingError(let error):
            return "Failed to parse recommendations: \(error.localizedDescription)"
        }
    }
}
