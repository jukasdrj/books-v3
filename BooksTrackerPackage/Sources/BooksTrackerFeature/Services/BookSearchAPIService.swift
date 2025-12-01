import Foundation
import SwiftUI
import SwiftData
import OSLog

// MARK: - API Service

@MainActor
public class BookSearchAPIService {
    private let urlSession: URLSession
    private let modelContext: ModelContext
    private let dtoMapper: DTOMapper
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "BookSearchAPIService")

    public init(modelContext: ModelContext, dtoMapper: DTOMapper) {
        self.modelContext = modelContext
        self.dtoMapper = dtoMapper

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Search Methods

    /// V2 Unified Search - Primary search method
    ///
    /// Routes all search queries through the V2 unified search endpoint (`/api/v2/search`).
    /// Supports query prefixes for different search types:
    /// - `isbn:9780439064873` → ISBN lookup
    /// - `author:rowling` → Author search
    /// - `title:harry potter` → Explicit title search
    /// - `harry potter` → Default title search
    ///
    /// - Parameters:
    ///   - query: Search query (supports prefixes)
    ///   - maxResults: Maximum results to return (default: 20, max: 50)
    ///   - scope: Search scope for query transformation
    ///   - persist: Whether to persist results to SwiftData
    /// - Returns: SearchResponse with results
    func search(query: String, maxResults: Int = 20, scope: SearchScope = .all, persist: Bool = true) async throws -> SearchResponse {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SearchError.invalidQuery
        }

        // Transform query based on scope using V2 prefix format
        let v2Query = transformQueryForV2(query: query, scope: scope)
        let mode = mapScopeToSearchMode(scope)

        // Use V2 unified search endpoint
        return try await searchV2(query: v2Query, mode: mode, limit: min(maxResults, 50), persist: persist)
    }

    /// Transform query for V2 API format based on scope
    private func transformQueryForV2(query: String, scope: SearchScope) -> String {
        switch scope {
        case .all, .title:
            // Default text search - no prefix needed
            return query
        case .author:
            // Add author: prefix if not already present
            if query.lowercased().hasPrefix("author:") {
                return query
            }
            return "author:\(query)"
        case .isbn:
            // Add isbn: prefix if not already present
            if query.lowercased().hasPrefix("isbn:") {
                return query
            }
            return "isbn:\(query)"
        case .semantic:
            // Semantic search uses mode parameter, no prefix needed
            return query
        }
    }

    /// Map SearchScope to V2 SearchMode
    private func mapScopeToSearchMode(_ scope: SearchScope) -> SearchMode {
        switch scope {
        case .semantic:
            return .semantic
        case .all, .title, .author, .isbn:
            return .text
        }
    }

    /// Get trending books based on user activity within a time range
    /// Returns top 10 most popular books (by search + add count) with optional fallback to curated list
    func getTrendingBooks(timeRange: TimeRange = .lastWeek) async throws -> SearchResponse {
        logger.info("📚 Loading trending books (timeRange: \(timeRange.displayName))...")

        let startTime = Date()

        // Fetch trending activity from SwiftData
        let descriptor = FetchDescriptor<TrendingActivity>(
            sortBy: [SortDescriptor(\.lastActivity, order: .reverse)]
        )

        let activities: [TrendingActivity]
        do {
            activities = try modelContext.fetch(descriptor)
        } catch {
            logger.warning("⚠️ Failed to fetch trending activities: \(error). Falling back to curated list.")
            return try await getCuratedTrendingBooks()
        }

        // Filter by time range
        let cutoffDate: Date
        if timeRange == .allTime {
            cutoffDate = Date.distantPast
        } else {
            cutoffDate = Date().addingTimeInterval(-timeRange.seconds)
        }

        let recentActivity = activities.filter { $0.lastActivity >= cutoffDate }

        // If no recent activity, fall back to curated list
        if recentActivity.isEmpty {
            logger.info("📚 No recent activity found. Falling back to curated list.")
            return try await getCuratedTrendingBooks()
        }

        // Sort by popularity (searchCount + addCount)
        let trending = recentActivity.sorted {
            ($0.searchCount + $0.addCount) > ($1.searchCount + $1.addCount)
        }

        // Get top 10
        let top10 = Array(trending.prefix(10))

        // Convert to SearchResults by searching for each ISBN
        var results: [SearchResult] = []
        var cacheHits = 0
        var totalRequests = 0

        await withTaskGroup(of: (SearchResult?, Double)?.self) { group in
            for activity in top10 {
                guard let isbn = activity.isbn else { continue }  // Skip if ISBN is nil
                group.addTask { [logger] in
                    do {
                        let response = try await self.search(query: isbn, maxResults: 1, persist: false)
                        return (response.results.first, response.cacheHitRate)
                    } catch {
                        logger.warning("⚠️ Failed to load trending book (ISBN: \(isbn)): \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (searchResult, cacheHitRate) = result, let searchResult = searchResult {
                    results.append(searchResult)
                    totalRequests += 1
                    if cacheHitRate > 0.5 {
                        cacheHits += 1
                    }
                }
            }
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000
        let averageCacheHitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0

        logger.info("✅ Trending books loaded: \(results.count) results from user activity in \(Int(responseTime))ms")
        return SearchResponse(
            results: results,
            cacheHitRate: averageCacheHitRate,
            provider: "trending:\(timeRange.rawValue.lowercased())",
            responseTime: responseTime,
            totalItems: results.count
        )
    }

    /// Fallback: Curated list of high-quality, culturally diverse books
    /// Used when no user activity exists or as initial seed content
    private func getCuratedTrendingBooks() async throws -> SearchResponse {
        logger.info("📚 Loading curated trending books (fallback)...")

        let startTime = Date()

        let curatedTitles = [
            "The Martian",
            "Beloved",
            "Things Fall Apart",
            "One Hundred Years of Solitude",
            "The Kite Runner",
            "Pachinko",
            "Homegoing",
            "Americanah",
            "The God of Small Things",
            "The Handmaid's Tale",
            "A Thousand Splendid Suns",
            "The Brief Wondrous Life of Oscar Wao"
        ]

        // Fetch all books concurrently for better performance
        var allResults: [SearchResult] = []
        var cacheHits = 0
        var totalRequests = 0

        await withTaskGroup(of: (SearchResult?, Double)?.self) { group in
            for title in curatedTitles {
                group.addTask {
                    do {
                        let response = try await self.search(query: title, maxResults: 1, persist: false)
                        return (response.results.first, response.cacheHitRate)
                    } catch {
                        // Skip books that fail to load - continue with others
                        self.logger.warning("⚠️ Failed to load curated book '\(title)': \(error)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (searchResult, cacheHitRate) = result, let searchResult = searchResult {
                    allResults.append(searchResult)
                    totalRequests += 1
                    if cacheHitRate > 0.5 {
                        cacheHits += 1
                    }
                }
            }
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000
        let averageCacheHitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0

        logger.info("✅ Curated trending books loaded: \(allResults.count) results in \(Int(responseTime))ms")
        return SearchResponse(
            results: allResults,
            cacheHitRate: averageCacheHitRate,
            provider: "curated",
            responseTime: responseTime,
            totalItems: allResults.count
        )
    }

    /// Track user activity (search or add) for trending calculations
    func trackActivity(isbn: String, title: String, type: ActivityType) {
        let descriptor = FetchDescriptor<TrendingActivity>(
            predicate: #Predicate { $0.isbn == isbn }
        )

        do {
            let existing = try modelContext.fetch(descriptor).first

            if let existing = existing {
                // Update existing activity
                switch type {
                case .search: existing.searchCount += 1
                case .add: existing.addCount += 1
                }
                existing.lastActivity = Date()
            } else {
                // Create new activity record
                let activity = TrendingActivity(isbn: isbn, title: title)
                switch type {
                case .search: activity.searchCount = 1
                case .add: activity.addCount = 1
                }
                modelContext.insert(activity)
            }

            try modelContext.save()
        } catch {
            logger.warning("⚠️ Failed to track activity for ISBN \(isbn): \(error)")
        }
    }

    /// Advanced search with multiple criteria (author, title, ISBN)
    ///
    /// Uses V2 unified search endpoint with query prefixes.
    /// Combines criteria into a single query string:
    /// - Title only: `{title}`
    /// - Author only: `author:{author}`
    /// - ISBN only: `isbn:{isbn}`
    /// - Combined: `{title} author:{author}`
    ///
    /// - Parameters:
    ///   - author: Author name filter
    ///   - title: Book title filter
    ///   - isbn: ISBN filter
    /// - Returns: SearchResponse with results
    func advancedSearch(
        author: String?,
        title: String?,
        isbn: String?
    ) async throws -> SearchResponse {
        // Build V2-compatible query string with prefixes
        var queryParts: [String] = []

        // ISBN takes priority (most specific)
        if let isbn = isbn, !isbn.isEmpty {
            return try await search(query: isbn, scope: .isbn)
        }

        // Add title (no prefix - default search)
        if let title = title, !title.isEmpty {
            queryParts.append(title)
        }

        // Add author with prefix
        if let author = author, !author.isEmpty {
            queryParts.append("author:\(author)")
        }

        guard !queryParts.isEmpty else {
            throw SearchError.invalidQuery
        }

        let query = queryParts.joined(separator: " ")
        return try await searchV2(query: query, mode: .text, limit: 20, persist: true)
    }

    // MARK: - Trending Searches API (Issue #20)

    /// Response structure for trending searches endpoint
    struct TrendingSearchesResponse: Codable {
        let trendingSearches: [TrendingSearchItem]
        let generatedAt: String
    }

    struct TrendingSearchItem: Codable {
        let query: String
        let searchCount: Int
    }

    /// Fetch dynamic trending searches from backend API
    /// Falls back to nil if endpoint unavailable (allows client-side fallback)
    ///
    /// Backend endpoint: GET /api/v2/trending-searches?limit=12
    /// Returns top N search queries by frequency (last 7 days)
    func getTrendingSearches(limit: Int = 12) async throws -> [String] {
        let urlString = "\(EnrichmentConfig.baseURL)/api/v2/trending-searches?limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            logger.warning("⚠️ Trending searches API unavailable: \(error.localizedDescription)")
            throw SearchError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        // Handle 404 gracefully - endpoint may not be deployed yet
        if httpResponse.statusCode == 404 {
            logger.info("📊 Trending searches endpoint not available (404) - using fallback")
            throw SearchError.httpError(404)
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        // Decode response
        let decoder = JSONDecoder()
        let trendingResponse = try decoder.decode(TrendingSearchesResponse.self, from: data)

        logger.info("✅ Loaded \(trendingResponse.trendingSearches.count) trending searches from API")
        return trendingResponse.trendingSearches.map { $0.query }
    }

    // MARK: - Helper Methods

    private func calculateCacheHitRate(from cacheStatus: String) -> Double {
        if cacheStatus.contains("HIT") {
            return 1.0
        } else {
            return 0.0
        }
    }

    /// Update cache health metrics from HTTP response headers
    /// - Parameters:
    ///   - headers: HTTP response headers dictionary
    ///   - responseTime: Request duration in milliseconds
    private func updateCacheMetrics(headers: [AnyHashable: Any], responseTime: TimeInterval) async {
        // Extract values from headers dictionary before crossing actor boundary
        // to avoid Swift 6 data race warnings
        let headersCopy: [String: String] = headers.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        await MainActor.run {
            CacheHealthMetrics.shared.update(from: headersCopy, responseTime: responseTime)
        }
    }

    // MARK: - V2 Search

    /// V2 Unified Search API Response DTOs
    /// Matches the ResponseEnvelope<SearchResponse> format from V2 API
    private struct V2SearchEnvelope: Codable {
        let success: Bool
        let data: V2SearchData?
        let metadata: V2ResponseMetadata?
        let error: V2ApiError?
    }

    private struct V2SearchData: Codable {
        let results: [V2SearchResultItem]
        let totalCount: Int
        let query: String
        let mode: String?
    }

    private struct V2ResponseMetadata: Codable {
        let timestamp: String?
        let cached: Bool?
        let provider: String?
    }

    private struct V2ApiError: Codable {
        let code: String?
        let message: String
    }

    private struct V2SearchResultItem: Codable {
        let isbn: String?
        let title: String
        let author: String?  // V2 uses singular "author" field
        let authors: [String]?  // Fallback for array format
        let coverUrl: String?
        let publisher: String?
        let publishedDate: String?
        let pageCount: Int?
        let description: String?
        let subjects: [String]?
        let workKey: String?
        let relevanceScore: Double?

        /// Get authors as array (handles both singular and array formats)
        var authorList: [String] {
            if let authors = authors, !authors.isEmpty {
                return authors
            }
            if let author = author, !author.isEmpty {
                return [author]
            }
            return []
        }
    }

    /// V2 Unified Search implementation
    ///
    /// Uses the `/api/v2/search` endpoint with ResponseEnvelope format.
    /// Cover URLs are served from Alexandria CDN (`https://alexandria.ooheynerds.com/covers/...`).
    ///
    /// - Parameters:
    ///   - query: Search query (supports prefixes: isbn:, author:, title:)
    ///   - mode: Search mode (text, semantic, hybrid)
    ///   - limit: Maximum results (default: 20, max: 50)
    ///   - persist: Whether to persist results to SwiftData (default: true)
    /// - Returns: SearchResponse with results
    public func searchV2(query: String, mode: SearchMode, limit: Int = 20, persist: Bool = true) async throws -> SearchResponse {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SearchError.invalidQuery
        }

        let urlString = "\(EnrichmentConfig.baseURL)/api/v2/search?q=\(encodedQuery)&mode=\(mode.rawValue)&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw SearchError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        // CORS Detection
        if let customError = httpResponse.value(forHTTPHeaderField: "X-Custom-Error"),
           customError == "CORS_BLOCKED" {
            throw SearchError.corsBlocked
        }

        // Rate Limit Detection
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            logger.warning("V2 Search rate limited. Retry after: \(retryAfter ?? 0)s")
            throw SearchError.rateLimitExceeded(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("V2 Search failed with HTTP status code: \(httpResponse.statusCode)")
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000

        // Extract cache status from headers
        let cacheStatus = httpResponse.value(forHTTPHeaderField: "X-Cache") ?? "MISS"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)

        // Update cache health metrics
        await updateCacheMetrics(headers: httpResponse.allHeaderFields, responseTime: responseTime)

        // Decode V2 ResponseEnvelope format
        let v2Response: V2SearchEnvelope
        do {
            v2Response = try JSONDecoder().decode(V2SearchEnvelope.self, from: data)
        } catch {
            logger.error("V2 Search decoding error: \(error)")
            throw SearchError.decodingError(error)
        }

        // Check for API-level errors
        guard v2Response.success, let searchData = v2Response.data else {
            let errorMessage = v2Response.error?.message ?? "Unknown API error"
            throw SearchError.apiError(errorMessage)
        }

        // Extract provider from metadata
        let provider = v2Response.metadata?.provider ?? "v2-unified"

        let results = convertV2ResultsToSearchResults(searchData.results, mode: mode, persist: persist)

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: responseTime,
            totalItems: searchData.totalCount
        )
    }

    /// Converts V2 search results into SwiftData-based SearchResult models
    ///
    /// Cover URLs from Alexandria CDN are preserved in the coverImageURL field.
    /// Format: `https://alexandria.ooheynerds.com/covers/{isbn}/{size}`
    ///
    /// - Parameters:
    ///   - v2Results: Raw V2 API results
    ///   - mode: Search mode used
    ///   - persist: Whether to persist models to SwiftData
    /// - Returns: Array of SearchResult models
    private func convertV2ResultsToSearchResults(_ v2Results: [V2SearchResultItem], mode: SearchMode, persist: Bool = false) -> [SearchResult] {
        return v2Results.map { item in
            // Create Work model
            let work = Work(title: item.title)
            work.coverImageURL = item.coverUrl  // Alexandria CDN URL
            work.subjectTags = item.subjects ?? []

            if persist {
                modelContext.insert(work)
            }

            // Create Author models
            let authors = item.authorList.map { authorName in
                let author = Author(name: authorName)
                if persist {
                    modelContext.insert(author)
                }
                return author
            }
            work.authors = authors

            // Create Edition model if ISBN present
            var editions: [Edition] = []
            if let isbn = item.isbn {
                let edition = Edition(isbn: isbn)
                edition.coverImageURL = item.coverUrl  // Alexandria CDN URL
                edition.publisher = item.publisher
                edition.publicationDate = item.publishedDate
                edition.pageCount = item.pageCount
                edition.editionDescription = item.description
                edition.work = work

                if persist {
                    modelContext.insert(edition)
                }
                editions.append(edition)
            }

            return SearchResult(
                work: work,
                editions: editions,
                authors: authors,
                relevanceScore: item.relevanceScore ?? 1.0,
                provider: "v2-unified-\(mode.rawValue)"
            )
        }
    }

    // MARK: - Similar Books API

    /// Find similar books using V2 semantic search
    ///
    /// Uses the V2 unified search endpoint with `mode=semantic` for AI-powered
    /// similarity matching based on book content and metadata.
    ///
    /// - Parameters:
    ///   - isbn: Source book ISBN to find similar books for
    ///   - limit: Maximum number of similar books to return (default: 10)
    /// - Returns: SearchResponse with similar books
    func findSimilarBooks(isbn: String, limit: Int = 10) async throws -> SearchResponse {
        logger.info("📚 Finding similar books for ISBN \(isbn) using V2 semantic search...")

        // Use V2 semantic search with isbn: prefix
        return try await searchV2(
            query: "isbn:\(isbn)",
            mode: .semantic,
            limit: limit,
            persist: false
        )
    }
}

// MARK: - Response Models

// SAFETY: @unchecked Sendable because it contains [SearchResult] which is @unchecked Sendable.
// SearchResponse is immutable after creation and safely passed between actors for search operations.
public struct SearchResponse: @unchecked Sendable {
    let results: [SearchResult]
    let cacheHitRate: Double
    let provider: String
    let responseTime: TimeInterval
    let totalItems: Int?
}

// MARK: - Error Types

public enum SearchError: LocalizedError {
    case invalidQuery
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)
    case apiError(String)
    case rateLimitExceeded(retryAfter: Int?)
    case corsBlocked

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Try again in \(retryAfter) seconds."
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        case .corsBlocked:
            return "Network security error. Check your connection or contact support."
        }
    }
}

// MARK: - Extensions for Conversion

extension EditionFormat {
    static func from(string: String?) -> EditionFormat {
        guard let string = string?.lowercased() else { return .paperback }

        switch string {
        case "hardcover", "hardback": return .hardcover
        case "paperback", "softcover": return .paperback
        case "ebook", "digital": return .ebook
        case "audiobook", "audio": return .audiobook
        default: return .paperback
        }
    }
}

extension AuthorGender {
    static func from(string: String?) -> AuthorGender {
        guard let string = string?.lowercased() else { return .unknown }

        switch string {
        case "female", "f": return .female
        case "male", "m": return .male
        case "nonbinary", "non-binary", "nb": return .nonBinary
        case "other": return .other
        default: return .unknown
        }
    }
}

extension CulturalRegion {
    static func from(string: String?) -> CulturalRegion {
        guard let string = string?.lowercased() else { return .international }

        switch string {
        case "africa": return .africa
        case "asia": return .asia
        case "europe": return .europe
        case "north america", "northamerica": return .northAmerica
        case "south america", "southamerica": return .southAmerica
        case "oceania": return .oceania
        case "middle east", "middleeast": return .middleEast
        case "caribbean": return .caribbean
        case "central asia", "centralasia": return .centralAsia
        case "indigenous": return .indigenous
        default: return .international
        }
    }
}
