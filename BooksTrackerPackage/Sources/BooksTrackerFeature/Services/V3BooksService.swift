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

    // V3 API client (manual implementation, replaces OpenAPI-generated code)
    private let v3Client: V3APIClient

    public init(modelContext: ModelContext, dtoMapper: DTOMapper) {
        self.modelContext = modelContext
        self.dtoMapper = dtoMapper

        // Initialize V2 service as primary implementation
        self.v2Service = BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)

        // Initialize V3 API client
        self.v3Client = V3APIClient()
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
    /// - Check `enableV3Search` feature flag (default: false)
    /// - Check API capabilities (does backend support V3?)
    /// - Fallback to V2 if V3 unavailable
    private func shouldUseV3API() -> Bool {
        // Feature flag check
        guard let enableV3 = UserDefaults.standard.object(forKey: "feature.enableV3Search") as? Bool,
              enableV3 else {
            return false
        }

        // API capabilities check (future)
        // guard let capabilities = FeatureFlags.shared.apiCapabilities,
        //       capabilities.supportsV3 else {
        //     logger.warning("V3 API requested but backend doesn't support it. Falling back to V2.")
        //     return false
        // }

        // V3 client is always available (initialized in init)
        return true
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

    // MARK: - V3 Implementation (Manual V3APIClient)
    // TODO: Fully implement V3 API integration when backend is ready

    private func searchV3(query: String, mode: SearchMode, limit: Int) async throws -> SearchResponse {
        // V3 API client is available, but backend V3 may not be deployed yet
        // For now, log and fall back to V2
        logger.info("📘 V3 API requested but backend not deployed. Falling back to V2.")
        return try await searchV2(query: query, mode: mode, limit: limit)

        // TODO: When V3 backend is ready, implement this:
        // let envelope = try await v3Client.search(query: query, mode: mode.rawValue, limit: limit)
        // guard envelope.success, let searchData = envelope.data else {
        //     if let error = envelope.error {
        //         let genericError = ResponseEnvelope<AnyCodable>.ApiErrorInfo(
        //             message: error.message,
        //             code: error.code,
        //             details: error.details,
        //             statusCode: error.statusCode,
        //             retryable: error.retryable
        //         )
        //         throw V3APIError.apiError(genericError)
        //     }
        //     throw BooksServiceError.invalidResponse
        // }
        // // Use DTOMapper to convert DTOs to SwiftData models
        // // Return SearchResponse with proper conversion
    }

    private func getBookByISBNV3(_ isbn: String) async throws -> (work: WorkDTO, edition: EditionDTO)? {
        // V3 backend not deployed yet, fall back to V2
        logger.info("📘 V3 API requested but backend not deployed. Falling back to V2.")
        return try await getBookByISBNV2(isbn)

        // TODO: When V3 backend is ready, implement this:
        // let envelope = try await v3Client.getBookByISBN(isbn)
        // guard envelope.success, let bookData = envelope.data else {
        //     if let error = envelope.error {
        //         if error.code == "NOT_FOUND" { return nil }
        //         let genericError = ResponseEnvelope<AnyCodable>.ApiErrorInfo(
        //             message: error.message, code: error.code, details: error.details,
        //             statusCode: error.statusCode, retryable: error.retryable
        //         )
        //         throw V3APIError.apiError(genericError)
        //     }
        //     throw BooksServiceError.invalidResponse
        // }
        // return (work: bookData.work, edition: bookData.edition)
    }

    private func getWorkDetailsV3(_ workId: String) async throws -> WorkDTO {
        // V3 backend not deployed yet, fall back to V2
        logger.info("📘 V3 API requested but backend not deployed. Falling back to V2.")
        return try await getWorkDetailsV2(workId)

        // TODO: When V3 backend is ready, implement this:
        // let envelope = try await v3Client.getWork(workId)
        // guard envelope.success, let work = envelope.data else {
        //     if let error = envelope.error {
        //         let genericError = ResponseEnvelope<AnyCodable>.ApiErrorInfo(
        //             message: error.message, code: error.code, details: error.details,
        //             statusCode: error.statusCode, retryable: error.retryable
        //         )
        //         throw V3APIError.apiError(genericError)
        //     }
        //     throw BooksServiceError.invalidResponse
        // }
        // return work
    }
}

// MARK: - Errors

public enum BooksServiceError: LocalizedError {
    case notImplemented(String)
    case v3ClientUnavailable
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .v3ClientUnavailable:
            return "V3 API client is not available"
        case .invalidResponse:
            return "Invalid response from API"
        }
    }
}

// MARK: - Feature Flag Extension

extension FeatureFlags {
    /// Enable V3 API for book search operations
    ///
    /// When enabled, all book search requests will use the V3 OpenAPI client
    /// instead of the legacy V2 API. Falls back to V2 if V3 is unavailable.
    ///
    /// Default: `false` (disabled, uses V2 API)
    ///
    /// Note: This is part of the V3 Migration Plan (Phase 2).
    /// V3 will become the default in Phase 3 (Q2 2026).
    public var enableV3Search: Bool {
        get {
            UserDefaults.standard.bool(forKey: "feature.enableV3Search")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.enableV3Search")
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
