import Foundation
import SwiftUI
import SwiftData
import OSLog

// MARK: - Protocol Abstraction

/// Protocol for book search operations
///
/// Abstracts the underlying API implementation (V2 vs V3) to enable
/// seamless migration with feature flag control.
@MainActor
public protocol BooksServiceProtocol {
    /// Search for books using text or ISBN query
    ///
    /// - Parameters:
    ///   - query: Search query (title, author, ISBN, or prefixed query)
    ///   - mode: Search mode (text, semantic, hybrid)
    ///   - limit: Maximum number of results (default: 20, max: 50)
    /// - Returns: Search response with works, editions, and authors
    func search(query: String, mode: SearchMode, limit: Int) async throws -> SearchResponse

    /// Get book details by ISBN
    ///
    /// - Parameter isbn: 10 or 13 digit ISBN
    /// - Returns: Work and edition for the specified ISBN
    func getBookByISBN(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)?

    /// Get book details by OpenLibrary work ID
    ///
    /// - Parameter workId: OpenLibrary work ID (e.g., "OL45804W")
    /// - Returns: Work details with editions
    func getWorkDetails(_ workId: String) async throws -> WorkDTO
}

// MARK: - V3 Service Implementation

/// V3 Books Service - Protocol-based abstraction over V2/V3 APIs
///
/// This service provides a unified interface for book search operations,
/// abstracting the underlying API version (V2 or V3) based on feature flags.
///
/// Migration Strategy:
/// - Phase 1: All requests route to V2 API (BookSearchAPIService)
/// - Phase 2: Feature flag enables gradual V3 migration
/// - Phase 3: V3 becomes default, V2 is fallback
///
/// Part of V3 Migration Plan - Phase 2, Task 1
@MainActor
public class V3BooksService: BooksServiceProtocol {
    private let modelContext: ModelContext
    private let dtoMapper: DTOMapper
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "V3BooksService")

    // V2 API service (current implementation)
    private let v2Service: BookSearchAPIService

    // V3 API client (production V3 implementation)
    private let v3Client: V3APIClientActual

    public init(modelContext: ModelContext, dtoMapper: DTOMapper) {
        self.modelContext = modelContext
        self.dtoMapper = dtoMapper

        // Initialize V2 service as primary implementation
        self.v2Service = BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)

        // Initialize V3 API client (production V3 implementation)
        self.v3Client = V3APIClientActual()
    }

    // MARK: - Search Operations

    public func search(query: String, mode: SearchMode = .text, limit: Int = 20) async throws -> SearchResponse {
        // Check V3 feature flag
        if shouldUseV3API() {
            logger.info("📘 V3BooksService: Using V3 API for search (query: \(query))")
            return try await searchV3(query: query, mode: mode, limit: limit)
        } else {
            logger.debug("📗 V3BooksService: Using V2 API for search (query: \(query))")
            return try await searchV2(query: query, mode: mode, limit: limit)
        }
    }

    public func getBookByISBN(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)? {
        if shouldUseV3API() {
            logger.info("📘 V3BooksService: Using V3 API for ISBN lookup (\(isbn))")
            return try await getBookByISBNV3(isbn)
        } else {
            logger.debug("📗 V3BooksService: Using V2 API for ISBN lookup (\(isbn))")
            return try await getBookByISBNV2(isbn)
        }
    }

    public func getWorkDetails(_ workId: String) async throws -> WorkDTO {
        if shouldUseV3API() {
            logger.info("📘 V3BooksService: Using V3 API for work details (\(workId))")
            return try await getWorkDetailsV3(workId)
        } else {
            logger.debug("📗 V3BooksService: Using V2 API for work details (\(workId))")
            return try await getWorkDetailsV2(workId)
        }
    }

    // MARK: - Feature Flag Control

    /// Determines whether to use V3 API based on feature flags
    ///
    /// Strategy:
    /// - Check `enableV3Search` feature flag (default: true)
    /// - V3 backend is now deployed and production-ready
    private func shouldUseV3API() -> Bool {
        return FeatureFlags.shared.enableV3Search
    }

    // MARK: - V2 Implementation (Current)

    private func searchV2(query: String, mode: SearchMode, limit: Int) async throws -> SearchResponse {
        // Delegate to existing V2 service
        return try await v2Service.searchV2(query: query, mode: mode, limit: limit, persist: true)
    }

    private func getBookByISBNV2(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)? {
        // V2 API doesn't have a dedicated ISBN lookup endpoint that returns DTOs
        // This method is not used by current V2 flow (search handles ISBN via "isbn:" prefix)
        // V3 will provide proper ISBN endpoint
        throw BooksServiceError.notImplemented("Use search() with isbn: prefix instead")
    }

    private func getWorkDetailsV2(_ workId: String) async throws -> WorkDTO {
        // V2 API doesn't have a dedicated work details endpoint
        // We'd need to fetch from OpenLibrary directly or use search
        throw BooksServiceError.notImplemented("V2 API doesn't support work details lookup")
    }

    // MARK: - V3 Implementation (Production V3APIClientActual)

    /// Generic retry helper for V3 API requests
    ///
    /// Handles retryable errors with exponential backoff and proper error mapping.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts (default: 2)
    ///   - operation: Async operation to execute and retry
    /// - Returns: Result from successful operation
    private func performV3Request<T>(
        maxRetries: Int = 2,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch let error as V3ActualAPIError {
                lastError = error
                if error.isRetryable && attempt < maxRetries {
                    logger.warning("📘 V3BooksService: Retrying V3 request due to retryable error: \(error.localizedDescription) (Attempt \(attempt + 1)/\(maxRetries + 1))")
                    try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                    continue
                } else {
                    throw mapV3ActualAPIErrorToBooksServiceError(error)
                }
            } catch {
                lastError = error
                logger.error("📘 V3BooksService: V3 request failed with unexpected error: \(error.localizedDescription)")
                throw BooksServiceError.apiError(error)
            }
        }
        throw lastError ?? BooksServiceError.unknownError("Unknown error after retries for V3 request")
    }

    private func searchV3(query: String, mode: SearchMode, limit: Int) async throws -> SearchResponse {
        return try await performV3Request {
            let page = 1  // For now, always first page (pagination TODO)
            let v3Response = try await self.v3Client.search(query: query, page: page, limit: limit)

            // Use V3ToV2Mapper to convert V3 response to V2 DTOs
            let v2Response = V3ToV2Mapper.mapSearchResponse(v3Response)

            // Convert V2 DTOs to SearchResult models
            let searchResults = try self.convertBookSearchResponseToSearchResults(v2Response, provider: "v3-alexandria", persist: true)

            return SearchResponse(
                results: searchResults,
                cacheHitRate: 0.0,  // V3 doesn't provide cache metrics yet
                provider: "v3-alexandria",
                responseTime: 0.0,  // TODO: Track response time
                totalItems: v3Response.data.total
            )
        }
    }

    private func getBookByISBNV3(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)? {
        do {
            return try await performV3Request {
                let v3Book = try await self.v3Client.getBook(isbn: isbn)
                let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)
                return (work: work, edition: edition)
            }
        } catch let error as BooksServiceError {
            // Handle 404 specially - book not found is not an error, return nil
            if case .apiError(let underlyingError) = error,
               let v3Error = underlyingError as? V3ActualAPIError,
               case .httpError(let statusCode) = v3Error,
               statusCode == 404 {
                logger.info("📘 V3BooksService: Book with ISBN \(isbn) not found (404) via V3 API.")
                return nil
            }
            throw error
        }
    }

    private func getWorkDetailsV3(_ workId: String) async throws -> WorkDTO {
        logger.info("📘 V3BooksService: getWorkDetailsV3 not implemented for workId: \(workId)")
        throw BooksServiceError.notImplemented("V3 API doesn't support work details lookup yet")
    }
}

// MARK: - Errors

public enum BooksServiceError: LocalizedError {
    case notImplemented(String)
    case v3ClientUnavailable
    case invalidResponse
    case apiError(Error)
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .v3ClientUnavailable:
            return "V3 API client is not available"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let error):
            if let v3Error = error as? V3ActualAPIError {
                return v3Error.localizedDescription
            }
            return "API Error: \(error.localizedDescription)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - DTO Conversion Helpers

extension V3BooksService {
    /// Converts BookSearchResponse (separate works/editions/authors arrays) to SearchResult models
    ///
    /// BookSearchResponse from V2 DTOs contains:
    /// - works: Array of WorkDTO
    /// - editions: Array of EditionDTO
    /// - authors: Array of AuthorDTO
    ///
    /// This method uses DTOMapper to convert each DTO to SwiftData models and groups them into SearchResults.
    ///
    /// - Parameters:
    ///   - response: BookSearchResponse with separated DTOs
    ///   - provider: Provider string for metadata
    ///   - persist: Whether to persist models to SwiftData
    /// - Returns: Array of SearchResult models
    private func convertBookSearchResponseToSearchResults(_ response: BookSearchResponse, provider: String, persist: Bool) throws -> [SearchResult] {
        // Convert all DTOs to SwiftData models using DTOMapper
        let works = try response.works.map { try self.dtoMapper.mapToWork($0, persist: persist) }
        let editions = try response.editions.map { try self.dtoMapper.mapToEdition($0, persist: persist) }
        let authors = try response.authors.map { try self.dtoMapper.mapToAuthor($0, persist: persist) }

        // Group editions by work (using openLibraryID as the linking key)
        // Note: This is a simplified grouping - in production, we'd need more sophisticated relationship mapping
        var results: [SearchResult] = []

        for work in works {
            // Find editions that belong to this work
            let workEditions = editions.filter { edition in
                // Match editions to works via openLibraryID
                edition.openLibraryID == work.openLibraryID
            }

            // Find authors for this work (simplified - assumes first author)
            // In production, we'd need proper relationship mapping
            let workAuthors = authors.isEmpty ? [] : [authors[0]]

            let searchResult = SearchResult(
                work: work,
                editions: workEditions.isEmpty ? [] : workEditions,
                authors: workAuthors,
                relevanceScore: 1.0, // V3 doesn't provide relevance scores yet
                provider: provider
            )
            results.append(searchResult)
        }

        return results
    }
}

// MARK: - V3 Error Mapping

extension V3BooksService {
    /// Maps a V3ActualAPIError to a BooksServiceError for consistent error handling.
    private func mapV3ActualAPIErrorToBooksServiceError(_ error: V3ActualAPIError) -> BooksServiceError {
        switch error {
        case .invalidURL, .networkError, .apiError, .httpError, .notModified:
            return .apiError(error)
        case .invalidResponse:
            return .invalidResponse
        case .decodingFailed(let underlyingError):
            return .apiError(underlyingError)
        }
    }
}

// MARK: - Environment Key

/// Environment key for V3BooksService dependency injection
struct V3BooksServiceKey: EnvironmentKey {
    static let defaultValue: V3BooksService? = nil
}

extension EnvironmentValues {
    public var v3BooksService: V3BooksService? {
        get { self[V3BooksServiceKey.self] }
        set { self[V3BooksServiceKey.self] = newValue }
    }
}
