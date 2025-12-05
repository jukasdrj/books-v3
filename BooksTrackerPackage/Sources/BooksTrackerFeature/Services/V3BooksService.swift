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

    private func searchV3(query: String, mode: SearchMode, limit: Int) async throws -> SearchResponse {
        let maxRetries = 2 // Including the initial attempt, so 2 retries = 3 attempts total
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let page = 1  // For now, always first page (pagination TODO)
                let v3Response = try await v3Client.search(query: query, page: page, limit: limit)

                // Convert V3Books to SwiftData models and SearchResults
                let searchResults = convertV3BooksToSearchResults(v3Response.data.books, persist: true)

                return SearchResponse(
                    results: searchResults,
                    cacheHitRate: 0.0,  // V3 doesn't provide cache metrics yet
                    provider: "v3-alexandria",
                    responseTime: 0.0,  // TODO: Track response time
                    totalItems: v3Response.data.total
                )
            } catch let error as V3ActualAPIError {
                lastError = error
                if error.isRetryable && attempt < maxRetries {
                    logger.warning("📘 V3BooksService: Retrying searchV3 due to retryable V3ActualAPIError: \(error.localizedDescription) (Attempt \(attempt + 1)/\(maxRetries + 1))")
                    // Add a small delay before retrying
                    try await Task.sleep(nanoseconds: UInt64(0.5 * Double(attempt + 1) * 1_000_000_000))
                    continue
                } else {
                    throw mapV3ActualAPIErrorToBooksServiceError(error)
                }
            } catch {
                lastError = error
                logger.error("📘 V3BooksService: Search V3 failed with unexpected error: \(error.localizedDescription)")
                throw BooksServiceError.apiError(error)
            }
        }
        throw lastError ?? BooksServiceError.unknownError("Unknown error after retries for searchV3")
    }

    /// Converts V3 books into SwiftData-based SearchResult models
    ///
    /// Similar to BookSearchAPIService.convertV2ResultsToSearchResults but for V3 API.
    /// Creates Work, Edition, and Author SwiftData models from V3Book DTOs.
    ///
    /// - Parameters:
    ///   - v3Books: Array of V3Book from Alexandria API
    ///   - persist: Whether to persist models to SwiftData
    /// - Returns: Array of SearchResult models
    private func convertV3BooksToSearchResults(_ v3Books: [V3Book], persist: Bool) -> [SearchResult] {
        return v3Books.map { v3Book in
            // Create Work model
            let work = Work(title: v3Book.title)
            work.coverImageURL = v3Book.coverUrl ?? v3Book.thumbnailUrl
            work.subjectTags = v3Book.categories ?? []
            work.primaryProvider = v3Book.provider
            work.originalLanguage = v3Book.language

            if persist {
                modelContext.insert(work)
            }

            // Create Author models
            let authors = v3Book.authors.map { authorName in
                let author = Author(name: authorName)
                if persist {
                    modelContext.insert(author)
                }
                return author
            }
            work.authors = authors

            // Create Edition model
            let edition = Edition(isbn: v3Book.isbn)
            edition.coverImageURL = v3Book.coverUrl ?? v3Book.thumbnailUrl
            edition.publisher = v3Book.publisher
            edition.publicationDate = v3Book.publishedDate
            edition.pageCount = v3Book.pageCount
            edition.editionDescription = v3Book.description
            edition.work = work
            edition.primaryProvider = v3Book.provider

            if persist {
                modelContext.insert(edition)
            }

            // Create SearchResult
            return SearchResult(
                work: work,
                editions: [edition],
                authors: authors,
                relevanceScore: 1.0,  // V3 doesn't provide relevance scores yet
                provider: v3Book.provider
            )
        }
    }

    private func getBookByISBNV3(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)? {
        let maxRetries = 2
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let v3Book = try await v3Client.getBook(isbn: isbn)
                let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)
                return (work: work, edition: edition)
            } catch let error as V3ActualAPIError {
                lastError = error
                if case .httpError(let statusCode) = error, statusCode == 404 {
                    logger.info("📘 V3BooksService: Book with ISBN \(isbn) not found (404) via V3 API.")
                    return nil
                }

                if error.isRetryable && attempt < maxRetries {
                    logger.warning("📘 V3BooksService: Retrying getBookByISBNV3 due to retryable V3ActualAPIError: \(error.localizedDescription) (Attempt \(attempt + 1)/\(maxRetries + 1))")
                    try await Task.sleep(nanoseconds: UInt64(0.5 * Double(attempt + 1) * 1_000_000_000))
                    continue
                } else {
                    throw mapV3ActualAPIErrorToBooksServiceError(error)
                }
            } catch {
                lastError = error
                logger.error("📘 V3BooksService: Get Book by ISBN V3 failed with unexpected error: \(error.localizedDescription)")
                throw BooksServiceError.apiError(error)
            }
        }
        throw lastError ?? BooksServiceError.unknownError("Unknown error after retries for getBookByISBNV3")
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
