import Foundation

// MARK: - Search API Errors

public enum SearchAPIError: Error, LocalizedError {
    case emptyQuery
    case networkError(Error)
    case invalidResponse
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Search query cannot be empty"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Search Result Model

public struct SearchResultItem: Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let coverUrl: String?
    public let publicationYear: Int?

    public init(title: String, author: String?, isbn: String?, coverUrl: String?, publicationYear: Int?) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.coverUrl = coverUrl
        self.publicationYear = publicationYear
    }
}

// MARK: - Search API Service

/// Actor-isolated service for book search API communication.
/// Extracted from SearchModel to separate concerns.
public actor SearchAPIService {
    // MARK: - Configuration

    private let baseURL = URL(string: "https://api-worker.jukasdrj.workers.dev")!
    private let timeout: TimeInterval = 30.0

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Execute search query against backend API.
    /// - Parameters:
    ///   - query: Search query string
    ///   - scope: Search scope (title, author, ISBN, all)
    ///   - page: Page number for pagination (default: 1)
    /// - Returns: Array of search results
    /// - Throws: SearchAPIError for failures
    public func search(
        query: String,
        scope: SearchScope,
        page: Int = 1
    ) async throws -> [SearchResultItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SearchAPIError.emptyQuery
        }

        // Build endpoint based on scope
        let endpoint = buildEndpoint(query: query, scope: scope, page: page)

        // Execute network request
        let (data, response) = try await URLSession.shared.data(from: endpoint)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SearchAPIError.invalidResponse
        }

        // Decode response
        do {
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(APISearchResponse.self, from: data)
            return apiResponse.results.map { $0.toSearchResultItem() }
        } catch {
            throw SearchAPIError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func buildEndpoint(query: String, scope: SearchScope, page: Int) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("/search/title"), resolvingAgainstBaseURL: false)!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page))
        ]

        // Add scope parameter
        switch scope {
        case .title:
            queryItems.append(URLQueryItem(name: "scope", value: "title"))
        case .author:
            queryItems.append(URLQueryItem(name: "scope", value: "author"))
        case .isbn:
            queryItems.append(URLQueryItem(name: "scope", value: "isbn"))
        case .all:
            // Default scope
            break
        }

        components.queryItems = queryItems
        return components.url!
    }
}

// MARK: - API Response Models (Internal)

private struct APISearchResponse: Codable {
    let results: [APIBook]
}

private struct APIBook: Codable {
    let title: String
    let author: String?
    let isbn: String?
    let coverUrl: String?
    let publicationYear: Int?

    func toSearchResultItem() -> SearchResultItem {
        SearchResultItem(
            title: title,
            author: author,
            isbn: isbn,
            coverUrl: coverUrl,
            publicationYear: publicationYear
        )
    }
}
