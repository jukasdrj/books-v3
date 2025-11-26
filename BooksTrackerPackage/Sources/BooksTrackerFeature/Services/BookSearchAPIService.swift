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

    func search(query: String, maxResults: Int = 20, scope: SearchScope = .all, persist: Bool = true) async throws -> SearchResponse {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SearchError.invalidQuery
        }

        // iOS 26 HIG: Intelligent routing based on query context
        let endpoint: String
        let urlString: String

        switch scope {
        case .all:
            // Smart detection: ISBN → Title search, otherwise use title search
            // Title search handles ISBNs intelligently + provides best coverage
            endpoint = "/v1/search/title"
            urlString = "\(EnrichmentConfig.baseURL)\(endpoint)?q=\(encodedQuery)"
        case .title:
            endpoint = "/v1/search/title"
            urlString = "\(EnrichmentConfig.baseURL)\(endpoint)?q=\(encodedQuery)"
        case .author:
            // Use advanced search with author-only parameter (canonical format)
            endpoint = "/v1/search/advanced"
            urlString = "\(EnrichmentConfig.baseURL)\(endpoint)?author=\(encodedQuery)"
        case .isbn:
            // Dedicated ISBN endpoint for ISBNdb lookups (7-day cache, most accurate)
            endpoint = "/v1/search/isbn"
            urlString = "\(EnrichmentConfig.baseURL)\(endpoint)?isbn=\(encodedQuery)"
        }
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

        // CORS Detection (Issue #428, Issue #10)
        // NOTE: This detects backend-signaled CORS errors via X-Custom-Error header.
        // Real CORS errors (browser/OS blocks) result in status 0 or network errors
        // and cannot be reliably detected client-side. This is primarily for web builds
        // where backends can explicitly signal CORS policy violations.
        if let customError = httpResponse.value(forHTTPHeaderField: "X-Custom-Error"),
           customError == "CORS_BLOCKED" {
            throw SearchError.corsBlocked
        }

        // Rate Limit Detection (Issue #9)
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw SearchError.rateLimitExceeded(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds

        // Extract performance headers
        let cacheStatus = httpResponse.value(forHTTPHeaderField: "X-Cache") ?? "MISS"
        let provider = httpResponse.value(forHTTPHeaderField: "X-Provider") ?? "unknown"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)

        // Update cache health metrics (actor-isolated call)
        await updateCacheMetrics(headers: httpResponse.allHeaderFields, responseTime: responseTime)

        // Parse response using DTOMapper (supports both unified envelope and legacy formats)
        let searchResponse: BookSearchResponse
        do {
            searchResponse = try dtoMapper.parseSearchResponse(data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Convert parsed DTO response to SearchResult array
        let results = try convertToSearchResults(searchResponse, persist: persist)

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0, // Will be calculated by caller
            totalItems: results.count
        )
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
                let isbn = activity.isbn  // Capture value to avoid sendability issues
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
    /// Backend performs filtering to return clean results
    /// Optimization: When only author is provided, uses dedicated /search/author endpoint
    func advancedSearch(
        author: String?,
        title: String?,
        isbn: String?
    ) async throws -> SearchResponse {
        // Detect author-only search for optimization
        let isAuthorOnlySearch = !(author?.isEmpty ?? true) && (title?.isEmpty ?? true) && (isbn?.isEmpty ?? true)

        var urlComponents: URLComponents
        var queryItems: [URLQueryItem] = []

        if isAuthorOnlySearch, let authorName = author {
            // Use v1 advanced search with author-only parameter
            urlComponents = URLComponents(string: "\(EnrichmentConfig.baseURL)/v1/search/advanced")!
            queryItems.append(URLQueryItem(name: "author", value: authorName))
        } else {
            // Use v1 advanced search endpoint for multi-criteria queries
            urlComponents = URLComponents(string: "\(EnrichmentConfig.baseURL)/v1/search/advanced")!

            if let author = author, !author.isEmpty {
                queryItems.append(URLQueryItem(name: "author", value: author))
            }
            if let title = title, !title.isEmpty {
                queryItems.append(URLQueryItem(name: "title", value: title))
            }
            if let isbn = isbn, !isbn.isEmpty {
                queryItems.append(URLQueryItem(name: "isbn", value: isbn))
            }
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
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

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds

        // Extract performance headers
        let cacheStatus = httpResponse.allHeaderFields["X-Cache"] as? String ?? "MISS"
        let provider = httpResponse.allHeaderFields["X-Provider"] as? String ?? "advanced-search"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)

        // Update cache health metrics (actor-isolated call)
        await updateCacheMetrics(headers: httpResponse.allHeaderFields, responseTime: responseTime)

        // Parse response using DTOMapper (supports both unified envelope and legacy formats)
        let searchResponse: BookSearchResponse
        do {
            searchResponse = try dtoMapper.parseSearchResponse(data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Convert parsed DTO response to SearchResult array
        let results = try convertToSearchResults(searchResponse, persist: true)

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0,
            totalItems: results.count
        )
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

    // MARK: - Similar Books API (Vector Embeddings)

    /// Find books similar to a given book using vector embeddings
    /// Uses BGE-M3 embeddings (1024 dimensions) for semantic similarity
    ///
    /// Backend endpoint: GET /v1/search/similar?isbn={isbn}&limit={limit}
    /// Rate limit: Part of semantic search budget (5 req/min)
    /// Cache: 24h TTL (SwiftData cache)
    ///
    /// - Parameters:
    ///   - isbn: ISBN of the source book to find similar books for
    ///   - limit: Maximum number of results (default: 10, max: 50)
    /// - Returns: Array of similar books with similarity scores
    /// - Throws: SearchError on network or API errors
    func findSimilarBooks(isbn: String, limit: Int = 10) async throws -> SimilarBooksResponse {
        // Check cache first
        let cacheDescriptor = FetchDescriptor<SimilarBooksCache>(
            predicate: #Predicate { $0.sourceIsbn == isbn }
        )
        
        if let cached = try? modelContext.fetch(cacheDescriptor).first, cached.isValid {
            logger.info("✅ Similar books cache hit for ISBN \(isbn)")
            return cached.toResponse()
        }
        
        // Cache miss - fetch from API
        let urlString = "\(EnrichmentConfig.baseURL)/v1/search/similar?isbn=\(isbn)&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            logger.warning("⚠️ Similar books API error for ISBN \(isbn): \(error.localizedDescription)")
            throw SearchError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        // Handle 404 - source book not found in vector index
        if httpResponse.statusCode == 404 {
            logger.info("📊 Source book not found in vector index (ISBN: \(isbn))")
            throw SearchError.httpError(404)
        }

        // Rate limit detection (semantic search has stricter limits)
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw SearchError.rateLimitExceeded(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000

        // Decode response
        let decoder = JSONDecoder()
        let similarBooksResponse: SimilarBooksResponse
        do {
            similarBooksResponse = try decoder.decode(SimilarBooksResponse.self, from: data)
        } catch {
            logger.error("❌ Failed to decode similar books response: \(error)")
            throw SearchError.decodingError(error)
        }

        // Cache the response
        do {
            // Remove old cache entry if exists
            if let oldCache = try? modelContext.fetch(cacheDescriptor).first {
                modelContext.delete(oldCache)
            }
            
            let newCache = SimilarBooksCache(sourceIsbn: isbn, response: similarBooksResponse)
            modelContext.insert(newCache)
            try modelContext.save()
        } catch {
            logger.warning("⚠️ Failed to cache similar books response: \(error)")
            // Non-fatal - continue with response
        }

        logger.info("✅ Found \(similarBooksResponse.results.count) similar books for ISBN \(isbn) in \(Int(responseTime))ms")
        return similarBooksResponse
    }

    // MARK: - Helper Methods

    /// Convert BookSearchResponse to SearchResult array
    /// Extracts common logic for mapping authors and works from API DTOs
    private func convertToSearchResults(_ searchData: BookSearchResponse, persist: Bool) throws -> [SearchResult] {
        logger.debug("📦 Processing search response: \(searchData.works.count) works, \(searchData.editions.count) editions, \(searchData.authors.count) authors")

        // Map authors from API response
        let mappedAuthors = searchData.authors.compactMap { authorDTO in
            do {
                return try dtoMapper.mapToAuthor(authorDTO, persist: persist)
            } catch {
                logger.warning("⚠️ Failed to map Author DTO '\(authorDTO.name)': \(String(describing: error))")
                return nil
            }
        }

        logger.debug("✅ Mapped \(mappedAuthors.count) authors successfully")

        // Map editions with DTOMapper
        let mappedEditions = searchData.editions.compactMap { editionDTO in
            do {
                return try dtoMapper.mapToEdition(editionDTO, persist: persist)
            } catch {
                logger.warning("⚠️ Failed to map Edition DTO: \(String(describing: error))")
                return nil
            }
        }

        logger.debug("✅ Mapped \(mappedEditions.count) editions successfully")

        // Use DTOMapper to convert DTOs → SwiftData models with deduplication
        return searchData.works.enumerated().compactMap { (index, workDTO) in
            do {
                let work = try dtoMapper.mapToWork(workDTO, persist: persist)

                // Get corresponding edition (1:1 mapping by index)
                let edition = index < mappedEditions.count ? mappedEditions[index] : nil

                // Link edition to work if available
                if let edition = edition {
                    edition.work = work
                }

                // Link authors to work
                if !mappedAuthors.isEmpty {
                    work.authors = mappedAuthors
                }

                return SearchResult(
                    work: work,
                    editions: edition.map { [$0] } ?? [],
                    authors: mappedAuthors,
                    relevanceScore: 1.0,
                    provider: "canonical-api" // Provider tracking moved to meta envelope level
                )
            } catch {
                logger.warning("⚠️ Failed to map Work DTO '\(workDTO.title)': \(String(describing: error))")
                return nil
            }
        }
    }

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
