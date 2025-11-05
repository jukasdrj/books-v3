import Foundation
import SwiftUI
import SwiftData
import OSLog

// MARK: - API Service

@MainActor
public class BookSearchAPIService {
    private let baseURL = "https://api-worker.jukasdrj.workers.dev"
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

    func search(query: String, maxResults: Int = 20, scope: SearchScope = .all) async throws -> SearchResponse {
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
            urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)"
        case .title:
            endpoint = "/v1/search/title"
            urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)"
        case .author:
            // Use advanced search with author-only parameter (canonical format)
            endpoint = "/v1/search/advanced"
            urlString = "\(baseURL)\(endpoint)?author=\(encodedQuery)"
        case .isbn:
            // Dedicated ISBN endpoint for ISBNdb lookups (7-day cache, most accurate)
            endpoint = "/v1/search/isbn"
            urlString = "\(baseURL)\(endpoint)?isbn=\(encodedQuery)"
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

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds

        // Extract performance headers
        let cacheStatus = httpResponse.allHeaderFields["X-Cache"] as? String ?? "MISS"
        let provider = httpResponse.allHeaderFields["X-Provider"] as? String ?? "unknown"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)

        // Update cache health metrics (actor-isolated call)
        await updateCacheMetrics(headers: httpResponse.allHeaderFields, responseTime: responseTime)

        // Parse canonical ApiResponse<BookSearchResponse> envelope
        let envelope: ApiResponse<BookSearchResponse>
        do {
            envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Process response using shared helper (eliminates duplication with advancedSearch)
        let results = try processSearchResponse(envelope)

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0, // Will be calculated by caller
            totalItems: results.count
        )
    }

    func getTrendingBooks() async throws -> SearchResponse {
        // For now, return a curated list of trending books
        // In the future, this could be a separate API endpoint
        logger.info("📚 Loading trending books with query: 'bestseller 2024'")
        let response = try await search(query: "bestseller 2024", maxResults: 12)
        logger.info("✅ Trending books loaded: \(response.results.count) results")
        return response
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
            urlComponents = URLComponents(string: "\(baseURL)/v1/search/advanced")!
            queryItems.append(URLQueryItem(name: "author", value: authorName))
        } else {
            // Use v1 advanced search endpoint for multi-criteria queries
            urlComponents = URLComponents(string: "\(baseURL)/v1/search/advanced")!

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

        // Parse canonical ApiResponse<BookSearchResponse> envelope
        let envelope: ApiResponse<BookSearchResponse>
        do {
            envelope = try JSONDecoder().decode(ApiResponse<BookSearchResponse>.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Process response using shared helper (eliminates duplication with search)
        let results = try processSearchResponse(envelope)

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0,
            totalItems: results.count
        )
    }

    // MARK: - Helper Methods

    /// Process BookSearchResponse envelope and convert to SearchResult array
    /// Extracts common logic for mapping authors and works from API DTOs
    private func processSearchResponse(_ envelope: ApiResponse<BookSearchResponse>) throws -> [SearchResult] {
        switch envelope {
        case .success(let searchData, let meta):
            logger.debug("📦 Processing search response: \(searchData.works.count) works, \(searchData.editions.count) editions, \(searchData.authors.count) authors")

            // Map authors from API response
            let mappedAuthors = searchData.authors.compactMap { authorDTO in
                do {
                    return try dtoMapper.mapToAuthor(authorDTO)
                } catch {
                    logger.warning("⚠️ Failed to map Author DTO '\(authorDTO.name)': \(String(describing: error))")
                    return nil
                }
            }

            logger.debug("✅ Mapped \(mappedAuthors.count) authors successfully")

            // Map editions with DTOMapper
            let mappedEditions = searchData.editions.compactMap { editionDTO in
                do {
                    return try dtoMapper.mapToEdition(editionDTO)
                } catch {
                    logger.warning("⚠️ Failed to map Edition DTO: \(String(describing: error))")
                    return nil
                }
            }

            logger.debug("✅ Mapped \(mappedEditions.count) editions successfully")

            // Use DTOMapper to convert DTOs → SwiftData models with deduplication
            return searchData.works.enumerated().compactMap { (index, workDTO) in
                do {
                    let work = try dtoMapper.mapToWork(workDTO)

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
                        provider: meta.provider ?? "unknown"
                    )
                } catch {
                    logger.warning("⚠️ Failed to map Work DTO '\(workDTO.title)': \(String(describing: error))")
                    return nil
                }
            }

        case .failure(let error, _):
            throw SearchError.apiError(error.message)
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
