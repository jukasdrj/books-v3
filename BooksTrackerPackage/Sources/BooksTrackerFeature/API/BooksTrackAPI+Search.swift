import Foundation

extension BooksTrackAPI {
    // MARK: - V3 Unified Search API

    /// Unified V3 search endpoint - replaces all V1 and V2 search endpoints
    /// Uses: GET /v3/books/search
    /// - Parameters:
    ///   - query: Search query string (supports prefixes: "isbn:", "similar:")
    ///   - mode: Search mode (text/semantic/hybrid)
    ///   - limit: Maximum number of results to return (default: 20)
    ///   - offset: Number of results to skip for pagination (default: 0)
    /// - Returns: SearchResults with results, total count, mode, and query
    func search(
        query: String,
        mode: SearchMode = .text,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SearchResults {
        guard var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("/v3/books/search"),
            resolvingAgainstBaseURL: true
        ) else {
            throw APIError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(SearchResults.self, from: data)
    }

    // MARK: - Convenience Methods for Migration

    /// Searches for a single book by ISBN using V2 unified search
    /// Convenience method to maintain compatibility with V1 API callers
    /// - Parameter isbn: The ISBN to search for
    /// - Returns: First matching BookDTO, or nil if not found
    func searchByISBN(_ isbn: String) async throws -> BookDTO? {
        let encodedISBN = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let results = try await self.search(query: "isbn:\(encodedISBN)", mode: .text, limit: 1)
        return results.results.first
    }

    /// Searches for books by title using V2 unified search
    /// Convenience method to maintain compatibility with V1 API callers
    /// - Parameters:
    ///   - title: The title to search for
    ///   - limit: Maximum number of results (default: 20)
    /// - Returns: Array of matching BookDTOs
    func searchByTitle(_ title: String, limit: Int = 20) async throws -> [BookDTO] {
        let results = try await self.search(query: title, mode: .text, limit: limit)
        return results.results
    }

    /// Finds similar books based on an ISBN using semantic search
    /// Convenience method to maintain compatibility with V1 API callers
    /// - Parameters:
    ///   - isbn: The ISBN to find similar books for
    ///   - limit: Maximum number of results (default: 10)
    /// - Returns: Array of similar BookDTOs
    func findSimilarBooks(to isbn: String, limit: Int = 10) async throws -> [BookDTO] {
        let encodedISBN = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
        let results = try await self.search(
            query: "similar:\(encodedISBN)",
            mode: .semantic,
            limit: limit
        )
        return results.results
    }

    /// Performs an advanced search with multiple criteria using V2 unified search
    /// Convenience method to maintain compatibility with V1 API callers
    /// - Parameters:
    ///   - author: Optional author name
    ///   - title: Optional title
    ///   - isbn: Optional ISBN
    /// - Returns: Array of matching BookDTOs
    func advancedSearch(author: String?, title: String?, isbn: String?) async throws -> [BookDTO] {
        var queryParts: [String] = []

        if let author = author {
            let encodedAuthor = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
            queryParts.append("author:\(encodedAuthor)")
        }
        if let title = title {
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
            queryParts.append("title:\(encodedTitle)")
        }
        if let isbn = isbn {
            let encodedISBN = isbn.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? isbn
            queryParts.append("isbn:\(encodedISBN)")
        }

        guard !queryParts.isEmpty else {
            throw APIError.httpError(400) // Bad Request if no search parameters
        }

        let query = queryParts.joined(separator: " ")
        let results = try await self.search(query: query, mode: .text, limit: 20)
        return results.results
    }

    // MARK: - Legacy V1 Methods (DEPRECATED - Remove after caller migration)

    /// Searches for a book by ISBN.
    /// ⚠️ DEPRECATED: Use searchByISBN(_:) instead. Will be removed in v4.0
    @available(*, deprecated, message: "Use searchByISBN(_:) instead. V1 endpoint sunset: March 1, 2026")
    func search(isbn: String) async throws -> BookDTO {
        guard let result = try await searchByISBN(isbn) else {
            throw APIError.notFound(message: "Book with ISBN \(isbn) not found")
        }
        return result
    }

    /// Searches for books by title.
    /// ⚠️ DEPRECATED: Use searchByTitle(_:limit:) instead. Will be removed in v4.0
    @available(*, deprecated, message: "Use searchByTitle(_:limit:) instead. V1 endpoint sunset: March 1, 2026")
    func search(title: String, limit: Int = 20) async throws -> [BookDTO] {
        return try await searchByTitle(title, limit: limit)
    }

    /// Finds similar books based on an ISBN.
    /// ⚠️ DEPRECATED: Use findSimilarBooks(to:limit:) instead. Will be removed in v4.0
    @available(*, deprecated, message: "Use findSimilarBooks(to:limit:) instead. V1 endpoint sunset: March 1, 2026")
    func findSimilarBooks(isbn: String, limit: Int = 10) async throws -> [BookDTO] {
        return try await findSimilarBooks(to: isbn, limit: limit)
    }

    /// Performs a semantic search for books.
    /// ⚠️ DEPRECATED: Use search(query:mode:limit:offset:) with mode: .semantic instead. Will be removed in v4.0
    @available(*, deprecated, message: "Use search(query:mode:limit:offset:) with mode: .semantic instead. V1 endpoint sunset: March 1, 2026")
    func searchSemantic(query: String, limit: Int = 20) async throws -> [BookDTO] {
        let results = try await self.search(query: query, mode: .semantic, limit: limit)
        return results.results
    }
}
