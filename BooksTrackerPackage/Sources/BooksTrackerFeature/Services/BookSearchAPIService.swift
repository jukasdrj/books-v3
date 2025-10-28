import Foundation
import SwiftUI
import SwiftData

// MARK: - API Service

public actor BookSearchAPIService {
    private let baseURL = "https://api-worker.jukasdrj.workers.dev"
    private let urlSession: URLSession

    public init() {
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
        switch scope {
        case .all:
            // Smart detection: ISBN → Title search, otherwise use title search
            // Title search handles ISBNs intelligently + provides best coverage
            endpoint = "/search/title"
        case .title:
            endpoint = "/search/title"
        case .author:
            endpoint = "/search/author"
        case .isbn:
            // Dedicated ISBN endpoint for ISBNdb lookups (7-day cache, most accurate)
            endpoint = "/search/isbn"
        }

        let urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)&maxResults=\(maxResults)"
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

        // Parse response based on format
        let apiResponse: APISearchResponse
        do {
            apiResponse = try JSONDecoder().decode(APISearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Check if this is an enhanced format response or legacy format
        let isEnhancedFormat = apiResponse.format == "enhanced_work_edition_v1"

        let results: [SearchResult]

        if isEnhancedFormat {
            // Handle enhanced Work/Edition format
            results = apiResponse.items.compactMap { bookItem in
                return convertEnhancedItemToSearchResult(bookItem, provider: provider)
            }
        } else {
            // Handle legacy Google Books format for backward compatibility
            results = apiResponse.items.map { bookItem in
                // Create authors first
                let authors = (bookItem.volumeInfo.authors ?? []).map { authorName in
                    Author(name: authorName, gender: .unknown, culturalRegion: .international)
                }

                // Create work with authors properly set
                let work = Work(
                    title: bookItem.volumeInfo.title,
                    authors: authors.isEmpty ? [] : authors, // Pass authors in constructor
                    originalLanguage: bookItem.volumeInfo.language,
                    firstPublicationYear: extractYear(from: bookItem.volumeInfo.publishedDate),
                    subjectTags: bookItem.volumeInfo.categories ?? []
                )

                // Set external identifiers
                work.googleBooksVolumeID = bookItem.id
                work.isbndbQuality = 75 // Default quality for Google Books data

                let edition = convertToEdition(from: bookItem, work: work)

                return SearchResult(
                    work: work,
                    editions: [edition],
                    authors: authors,
                    relevanceScore: 1.0,
                    provider: provider
                )
            }
        }

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0, // Will be calculated by caller
            totalItems: apiResponse.totalItems
        )
    }

    func getTrendingBooks() async throws -> SearchResponse {
        // For now, return a curated list of trending books
        // In the future, this could be a separate API endpoint
        return try await search(query: "bestseller 2024", maxResults: 12)
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
            // Use dedicated author endpoint (better caching, optimized for author bibliography)
            urlComponents = URLComponents(string: "\(baseURL)/search/author")!
            queryItems.append(URLQueryItem(name: "q", value: authorName))
            queryItems.append(URLQueryItem(name: "maxResults", value: "20"))
        } else {
            // Use advanced search endpoint for multi-criteria queries
            urlComponents = URLComponents(string: "\(baseURL)/search/advanced")!

            if let author = author, !author.isEmpty {
                queryItems.append(URLQueryItem(name: "author", value: author))
            }
            if let title = title, !title.isEmpty {
                queryItems.append(URLQueryItem(name: "title", value: title))
            }
            if let isbn = isbn, !isbn.isEmpty {
                queryItems.append(URLQueryItem(name: "isbn", value: isbn))
            }

            queryItems.append(URLQueryItem(name: "maxResults", value: "20"))
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

        // Parse response
        let apiResponse: APISearchResponse
        do {
            apiResponse = try JSONDecoder().decode(APISearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Check format and convert
        let isEnhancedFormat = apiResponse.format == "enhanced_work_edition_v1"

        let results: [SearchResult]
        if isEnhancedFormat {
            results = apiResponse.items.compactMap { bookItem in
                return convertEnhancedItemToSearchResult(bookItem, provider: provider)
            }
        } else {
            // Legacy format conversion
            results = apiResponse.items.map { bookItem in
                let authors = (bookItem.volumeInfo.authors ?? []).map { authorName in
                    Author(name: authorName, gender: .unknown, culturalRegion: .international)
                }

                let work = Work(
                    title: bookItem.volumeInfo.title,
                    authors: authors.isEmpty ? [] : authors,
                    originalLanguage: bookItem.volumeInfo.language,
                    firstPublicationYear: extractYear(from: bookItem.volumeInfo.publishedDate),
                    subjectTags: bookItem.volumeInfo.categories ?? []
                )

                work.googleBooksVolumeID = bookItem.id
                work.isbndbQuality = 75

                let edition = convertToEdition(from: bookItem, work: work)

                return SearchResult(
                    work: work,
                    editions: [edition],
                    authors: authors,
                    relevanceScore: 1.0,
                    provider: provider
                )
            }
        }

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0,
            totalItems: apiResponse.totalItems
        )
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

    private func convertToWork(from bookItem: APIBookItem) -> Work {
        let volumeInfo = bookItem.volumeInfo
        let work = Work(
            title: volumeInfo.title,
            originalLanguage: volumeInfo.language,
            firstPublicationYear: extractYear(from: volumeInfo.publishedDate),
            subjectTags: volumeInfo.categories ?? []
        )

        // Set external identifiers
        work.googleBooksVolumeID = bookItem.id
        work.isbndbQuality = 75 // Default quality for Google Books data

        return work
    }

    private func convertToEdition(from bookItem: APIBookItem, work: Work) -> Edition {
        let volumeInfo = bookItem.volumeInfo
        let isbn = volumeInfo.industryIdentifiers?.first { $0.type.contains("ISBN") }?.identifier

        return Edition(
            isbn: isbn,
            publisher: volumeInfo.publisher,
            publicationDate: volumeInfo.publishedDate,
            pageCount: volumeInfo.pageCount,
            format: .paperback, // Default format since not specified in Google Books API
            coverImageURL: volumeInfo.imageLinks?.thumbnail,
            work: work
        )
    }

    private func extractYear(from dateString: String?) -> Int? {
        guard let dateString = dateString else { return nil }
        let yearString = String(dateString.prefix(4))
        return Int(yearString)
    }

    // MARK: - Enhanced Format Conversion

    private func convertEnhancedItemToSearchResult(_ bookItem: APIBookItem, provider: String) -> SearchResult? {
        let volumeInfo = bookItem.volumeInfo

        // Create Author objects first
        let authors = (volumeInfo.authors ?? []).map { authorName in
            Author(name: authorName, gender: .unknown, culturalRegion: .international)
        }

        // Create Work object with authors properly set
        let work = Work(
            title: volumeInfo.title,
            authors: authors.isEmpty ? [] : authors, // Pass authors in constructor
            originalLanguage: volumeInfo.language,
            firstPublicationYear: extractYear(from: volumeInfo.publishedDate),
            subjectTags: volumeInfo.categories ?? []
        )

        // Set external identifiers from enhanced API response
        work.isbndbID = volumeInfo.isbndbID
        work.openLibraryID = volumeInfo.openLibraryID
        work.googleBooksVolumeID = volumeInfo.googleBooksVolumeID
        work.isbndbQuality = 85 // Higher quality for enhanced format

        // Create Edition object
        let isbn = volumeInfo.industryIdentifiers?.first { $0.type.contains("ISBN") }?.identifier
        let edition = Edition(
            isbn: isbn,
            publisher: volumeInfo.publisher,
            publicationDate: volumeInfo.publishedDate,
            pageCount: volumeInfo.pageCount,
            format: EditionFormat.from(string: nil), // Default format
            coverImageURL: volumeInfo.imageLinks?.thumbnail,
            work: work
        )

        // Set external identifiers for edition
        edition.isbndbID = volumeInfo.isbndbID
        edition.openLibraryID = volumeInfo.openLibraryID
        edition.googleBooksVolumeID = volumeInfo.googleBooksVolumeID
        edition.isbndbQuality = 85

        // Add edition to work (handle optional editions array)
        if work.editions == nil {
            work.editions = []
        }
        work.editions?.append(edition)

        return SearchResult(
            work: work,
            editions: [edition],
            authors: authors,
            relevanceScore: 1.0,
            provider: provider
        )
    }

}

// MARK: - API Response Models

private struct APISearchResponse: Codable {
    let kind: String?
    let totalItems: Int?
    let items: [APIBookItem]
    let format: String?        // New field for enhanced format detection
    let provider: String?      // Provider information
    let cached: Bool?          // Cache status
}

private struct APIBookItem: Codable {
    let kind: String?
    let id: String?
    let volumeInfo: APIVolumeInfo
}

private struct APIVolumeInfo: Codable {
    let title: String
    let authors: [String]?
    let publishedDate: String?
    let publisher: String?
    let description: String?
    let industryIdentifiers: [APIIndustryIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let imageLinks: APIImageLinks?
    let language: String?

    // Enhanced format fields for external identifiers
    let isbndbID: String?
    let openLibraryID: String?
    let googleBooksVolumeID: String?
}

private struct APIIndustryIdentifier: Codable {
    let type: String
    let identifier: String
}

private struct APIImageLinks: Codable {
    let thumbnail: String?
    let smallThumbnail: String?
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
