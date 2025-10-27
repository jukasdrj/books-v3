import Foundation
import SwiftData

// MARK: - Enrichment Service
/// Service for enriching imported books with metadata from Cloudflare Worker
/// Fetches cover images, ISBNs, publication details, and other metadata
/// MainActor-isolated for SwiftData compatibility
@MainActor
public final class EnrichmentService {
    public static let shared = EnrichmentService()

    // MARK: - Properties

    private let baseURL = "https://api-worker.jukasdrj.workers.dev"
    private let urlSession: URLSession
    private let batchSize = 5 // Process 5 books at a time
    private let throttleDelay: TimeInterval = 0.5 // 500ms between requests

    // Statistics
    private var totalEnriched: Int = 0
    private var totalFailed: Int = 0

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Enrich a single work with metadata from the API
    public func enrichWork(
        _ work: Work,
        in modelContext: ModelContext
    ) async -> EnrichmentResult {
        // Use the original title for logging, but extract the normalized title for searching
        let rawTitle = work.title

        // IMPORTANT: Normalize the title before searching to improve match rates
        // This strips series markers, subtitles, and edition details that cause zero-result searches
        let searchTitle = rawTitle.normalizedTitleForSearch

        let authorName = work.primaryAuthorName

        guard !searchTitle.isEmpty else {
            return .failure(.missingTitle)
        }

        do {
            // Use advanced search with separated title + author for backend filtering
            let author = authorName != "Unknown Author" ? authorName : nil

            // Pass the CLEANED searchTitle to the API (not the raw title!)
            let response = try await searchAPI(title: searchTitle, author: author)

            // Find best match from results
            guard let bestMatch = findBestMatch(
                for: work,
                in: response.items
            ) else {
                return .failure(.noMatchFound)
            }

            // Update work with enriched data
            updateWork(work, with: bestMatch, in: modelContext)

            totalEnriched += 1
            return .success

        } catch {
            totalFailed += 1

            // DIAGNOSTIC: Log actual error type and HTTP status code if available
            if let enrichmentError = error as? EnrichmentError {
                switch enrichmentError {
                case .httpError(let statusCode):
                    print("🚨 HTTP Error \(statusCode) enriching '\(searchTitle)'")
                default:
                    print("🚨 Enrichment error: \(enrichmentError)")
                }
                return .failure(enrichmentError)
            }

            // Fallback for unknown errors
            print("🚨 Unexpected error enriching '\(searchTitle)': \(error)")
            return .failure(.apiError(error.localizedDescription))
        }
    }

    /// Get enrichment statistics
    public func getStatistics() -> EnrichmentStatistics {
        return EnrichmentStatistics(
            totalEnriched: totalEnriched,
            totalFailed: totalFailed
        )
    }

    // MARK: - Private Methods

    private func searchAPI(title: String, author: String?) async throws -> EnrichmentSearchResponseFlat {
        // Use advanced search endpoint for CSV enrichment (precise backend filtering)
        // This leverages the /search/advanced endpoint's multi-field filtering capability
        var urlComponents = URLComponents(string: "\(baseURL)/search/advanced")!
        var queryItems: [URLQueryItem] = []

        queryItems.append(URLQueryItem(name: "title", value: title))
        if let author = author, !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        queryItems.append(URLQueryItem(name: "maxResults", value: "5"))

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw EnrichmentError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw EnrichmentError.httpError(httpResponse.statusCode)
        }

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📡 Enrichment API Response: \(jsonString.prefix(500))")
        }
        #endif

        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(EnrichmentSearchResponse.self, from: data)

        // Transform VolumeItems to flat EnrichmentSearchResults
        let transformedResults = apiResponse.items.map { volumeItem in
            EnrichmentSearchResult(from: volumeItem.volumeInfo, volumeId: volumeItem.id)
        }

        // Create a response with transformed results for compatibility
        return EnrichmentSearchResponseFlat(
            items: transformedResults,
            totalItems: apiResponse.totalItems ?? transformedResults.count  // Fallback to actual count if missing
        )
    }

    private func findBestMatch(
        for work: Work,
        in results: [EnrichmentSearchResult]
    ) -> EnrichmentSearchResult? {
        guard !results.isEmpty else { return nil }

        let workTitleLower = work.title.lowercased()
        let workAuthorLower = work.primaryAuthorName.lowercased()

        // Get the normalized title for better matching (strips series markers, subtitles, etc.)
        let normalizedWorkTitleLower = work.title.normalizedTitleForSearch.lowercased()

        // Score each result
        let scoredResults = results.map { result -> (EnrichmentSearchResult, Int) in
            var score = 0

            // Title match (highest priority)
            // Prioritize normalized title matches first, then fall back to raw title
            if result.title.lowercased() == normalizedWorkTitleLower {
                score += 100
            } else if result.title.lowercased().contains(normalizedWorkTitleLower) ||
                      normalizedWorkTitleLower.contains(result.title.lowercased()) {
                score += 50
            } else if result.title.lowercased() == workTitleLower {
                // Fallback to raw title match (lower score since it's less reliable)
                score += 30
            } else if result.title.lowercased().contains(workTitleLower) ||
                      workTitleLower.contains(result.title.lowercased()) {
                score += 15
            }

            // Author match
            if result.author.lowercased() == workAuthorLower {
                score += 50
            } else if result.author.lowercased().contains(workAuthorLower) ||
                      workAuthorLower.contains(result.author.lowercased()) {
                score += 25
            }

            // Prefer results with ISBNs
            if result.isbn != nil {
                score += 10
            }

            // Prefer results with cover images
            if result.coverImage != nil {
                score += 5
            }

            return (result, score)
        }

        // Return highest scoring result if score > 50 (reasonable match)
        let best = scoredResults.max(by: { $0.1 < $1.1 })
        return (best?.1 ?? 0) > 50 ? best?.0 : nil
    }

    private func updateWork(
        _ work: Work,
        with searchResult: EnrichmentSearchResult,
        in modelContext: ModelContext
    ) {
        // Update work metadata
        if work.firstPublicationYear == nil, let year = searchResult.publicationYear {
            work.firstPublicationYear = year
        }

        // Update external IDs
        if let olWorkId = searchResult.openLibraryWorkID, work.openLibraryWorkID == nil {
            work.openLibraryWorkID = olWorkId
        }

        if let gbVolumeId = searchResult.googleBooksVolumeID, work.googleBooksVolumeID == nil {
            work.googleBooksVolumeID = gbVolumeId
        }

        // Find or create edition
        var edition: Edition?

        // Check if work already has an edition
        if let existingEditions = work.editions, !existingEditions.isEmpty {
            edition = existingEditions.first
        }

        // Create new edition if needed and we have ISBN
        if edition == nil, let isbn = searchResult.isbn {
            let newEdition = Edition(
                isbn: isbn,
                publisher: searchResult.publisher,
                publicationDate: searchResult.publicationDate,
                pageCount: searchResult.pageCount,
                format: .paperback,
                coverImageURL: searchResult.coverImage,
                work: nil  // ✅ Don't set in constructor
            )
            modelContext.insert(newEdition)  // ✅ Get permanent ID FIRST

            // NOW set bidirectional relationship (both have permanent IDs)
            newEdition.work = work
            // Note: work.editions is computed or automatically managed by SwiftData

            edition = newEdition
        }

        // Update existing edition with missing data
        if let edition = edition {
            if edition.coverImageURL == nil, let coverURL = searchResult.coverImage {
                edition.coverImageURL = coverURL
            }

            if edition.pageCount == nil, let pageCount = searchResult.pageCount {
                edition.pageCount = pageCount
            }

            if edition.publisher == nil, let publisher = searchResult.publisher {
                edition.publisher = publisher
            }

            if let isbn = searchResult.isbn {
                edition.addISBN(isbn)
            }

            edition.touch()
        }

        work.touch()

        // CRITICAL: Save model context immediately to convert temporary IDs to permanent IDs
        // This prevents crash if UI accesses the model before next save cycle
        // Fatal error occurs when: Edition created → temporary ID → UI accesses → context invalidated → crash
        try? modelContext.save()
    }
}

// MARK: - Supporting Types

public enum EnrichmentResult {
    case success
    case failure(EnrichmentError)
}

public enum EnrichmentError: Error, Sendable {
    case missingTitle
    case noMatchFound
    case apiError(String)
    case invalidQuery
    case invalidURL
    case invalidResponse
    case httpError(Int)
}

public struct BatchEnrichmentResult: Sendable {
    public let successCount: Int
    public let failureCount: Int
    public let errors: [EnrichmentError]
}

public struct EnrichmentStatistics: Sendable {
    public let totalEnriched: Int
    public let totalFailed: Int

    public var successRate: Double {
        let total = totalEnriched + totalFailed
        guard total > 0 else { return 0 }
        return Double(totalEnriched) / Double(total)
    }
}

// MARK: - EnrichmentSearchResponse (Google Books Format)
// Matches the nested volumeInfo structure from books-api-proxy worker

private struct EnrichmentSearchResponse: Codable {
    let items: [VolumeItem]
    let totalItems: Int?  // Optional: Backend doesn't always include this field
    let query: String?
    let provider: String?
    let cached: Bool?
    let success: Bool?  // Backend includes success flag
}

private struct VolumeItem: Codable {
    let kind: String?
    let id: String?
    let volumeInfo: VolumeInfo
}

private struct VolumeInfo: Codable {
    let title: String
    let subtitle: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let industryIdentifiers: [IndustryIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let imageLinks: ImageLinks?
    let crossReferenceIds: CrossReferenceIds?
}

private struct ImageLinks: Codable {
    let thumbnail: String?
    let smallThumbnail: String?
}

private struct CrossReferenceIds: Codable {
    let openLibraryWorkId: String?
    let openLibraryEditionId: String?
    let googleBooksVolumeId: String?
}

private struct IndustryIdentifier: Codable {
    let type: String
    let identifier: String
}

// MARK: - Transformation to Flat Model

private struct EnrichmentSearchResult {
    let title: String
    let author: String
    let isbn: String?
    let coverImage: String?
    let publicationYear: Int?
    let publicationDate: String?
    let publisher: String?
    let pageCount: Int?
    let openLibraryWorkID: String?
    let googleBooksVolumeID: String?

    init(from volumeInfo: VolumeInfo, volumeId: String?) {
        self.title = volumeInfo.title
        self.author = volumeInfo.authors?.first ?? "Unknown Author"

        // Extract ISBN from industryIdentifiers
        if let identifiers = volumeInfo.industryIdentifiers {
            self.isbn = identifiers.first(where: { $0.type.contains("ISBN") })?.identifier
        } else {
            self.isbn = nil
        }

        self.coverImage = volumeInfo.imageLinks?.thumbnail

        // Parse year from publishedDate string (e.g., "2022" or "2022-01-15")
        if let dateString = volumeInfo.publishedDate {
            self.publicationYear = Int(dateString.prefix(4))
        } else {
            self.publicationYear = nil
        }

        self.publicationDate = volumeInfo.publishedDate
        self.publisher = volumeInfo.publisher
        self.pageCount = volumeInfo.pageCount
        self.openLibraryWorkID = volumeInfo.crossReferenceIds?.openLibraryWorkId
        self.googleBooksVolumeID = volumeInfo.crossReferenceIds?.googleBooksVolumeId ?? volumeId
    }
}

// MARK: - Flat Response (for internal use)

private struct EnrichmentSearchResponseFlat {
    let items: [EnrichmentSearchResult]
    let totalItems: Int
}
