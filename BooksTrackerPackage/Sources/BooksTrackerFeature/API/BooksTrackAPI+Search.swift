import Foundation

extension BooksTrackAPI {
    /// Searches for a book by ISBN.
    func search(isbn: String) async throws -> BookDTO {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/v1/search/isbn"), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        urlComponents.queryItems = [URLQueryItem(name: "isbn", value: isbn)]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(BookDTO.self, from: data)
    }

    /// Searches for books by title.
    func search(title: String, limit: Int = 20) async throws -> [BookDTO] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/v1/search/title"), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope([BookDTO].self, from: data)
    }

    /// Performs a semantic search for books.
    func searchSemantic(query: String, limit: Int = 20) async throws -> [BookDTO] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/api/v2/search"), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "mode", value: "semantic"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope([BookDTO].self, from: data)
    }

    /// Finds similar books based on an ISBN.
    func findSimilarBooks(isbn: String, limit: Int = 10) async throws -> [BookDTO] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/v1/search/similar"), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope([BookDTO].self, from: data)
    }

    /// Performs an advanced search for books.
    func advancedSearch(author: String?, title: String?, isbn: String?) async throws -> [BookDTO] {
        guard var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/v1/search/advanced"), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        var queryItems: [URLQueryItem] = []
        if let author = author { queryItems.append(URLQueryItem(name: "author", value: author)) }
        if let title = title { queryItems.append(URLQueryItem(name: "title", value: title)) }
        if let isbn = isbn { queryItems.append(URLQueryItem(name: "isbn", value: isbn)) }

        guard !queryItems.isEmpty else {
            throw APIError.httpError(400) // Bad Request if no search parameters
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope([BookDTO].self, from: data)
    }
}
