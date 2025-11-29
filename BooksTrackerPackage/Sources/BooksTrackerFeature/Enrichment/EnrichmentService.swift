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
    private let apiClient = EnrichmentAPIClient()
    private let baseURL = EnrichmentConfig.baseURL
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
                    #if DEBUG
                    print("🚨 HTTP Error \(statusCode) enriching '\(searchTitle)'")
                    #endif
                default:
                    #if DEBUG
                    print("🚨 Enrichment error: \(enrichmentError)")
                    #endif
                }
                return .failure(enrichmentError)
            }

            // Fallback for unknown errors
            #if DEBUG
            print("🚨 Unexpected error enriching '\(searchTitle)': \(error)")
            #endif
            return .failure(.apiError(String(describing: error)))
        }
    }

    /// Enrich a batch of works with metadata from the API
    public func batchEnrichWorks(
        _ works: [Work],
        jobId: String,
        in modelContext: ModelContext
    ) async -> BatchEnrichmentResult {
        let books = works.map { work in
            Book(
                title: work.title.normalizedTitleForSearch,
                author: work.primaryAuthorName,
                isbn: work.editions?.first?.isbn
            )
        }

        do {
            let result = try await apiClient.startEnrichment(jobId: jobId, books: books)
            
            #if DEBUG
            print("✅ Batch enrichment job accepted: \(result.totalCount) books queued for background processing")
            #endif
            
            // HTTP 202 response indicates job acceptance, not completion
            // Actual enrichment happens asynchronously via WebSocket
            // Return 0/0 to avoid confusing "Success: 0, Failed: 48" logs
            return BatchEnrichmentResult(
                successCount: 0,  // Job accepted, enrichment pending (not complete)
                failureCount: 0,  // No failures yet (enrichment in progress)
                errors: [],
                token: result.authToken  // WebSocket authentication token
            )
        } catch {
            // Enhanced error logging for debugging enrichment failures
            #if DEBUG
            print("🚨 Batch enrichment failed: \(error)")
            #endif
            #if DEBUG
            print("🚨 Error type: \(type(of: error))")
            #endif

            if let urlError = error as? URLError {
                #if DEBUG
                print("🚨 URLError code: \(urlError.code.rawValue), localized: \(urlError.localizedDescription)")
                #endif
            } else {
                // Bridge to NSError for detailed diagnostics
                let nsError = error as NSError
                #if DEBUG
                print("🚨 NSError domain: \(nsError.domain), code: \(nsError.code)")
                #endif
                #if DEBUG
                print("🚨 NSError userInfo: \(nsError.userInfo)")
                #endif
            }
            
            return BatchEnrichmentResult(
                successCount: 0,
                failureCount: works.count,
                errors: [EnrichmentError.apiError(String(describing: error))],
                token: nil  // No token on error
            )
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
        // Use v1 canonical advanced search endpoint for CSV enrichment
        // Returns canonical ResponseEnvelope<BookSearchResponse> with WorkDTO, EditionDTO, AuthorDTO
        var urlComponents = URLComponents(string: "\(baseURL)/v1/search/advanced")!
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
        let envelope = try decoder.decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        // Parse canonical ResponseEnvelope
        let transformedResults: [EnrichmentSearchResult]
        let totalItems: Int

        if let searchData = envelope.data {
            // Create a map of work index to editions for correlation (1:1 mapping)
            let editionsByIndex = Dictionary(uniqueKeysWithValues:
                searchData.editions.enumerated().map { ($0, $1) }
            )

            // Transform canonical DTOs to EnrichmentSearchResults
            transformedResults = searchData.works.enumerated().map { (index, workDTO) in
                let edition = editionsByIndex[index]
                return EnrichmentSearchResult(from: workDTO, edition: edition, authors: searchData.authors)
            }
            totalItems = searchData.totalResults ?? transformedResults.count
        } else if let error = envelope.error {
            throw EnrichmentError.apiError(error.message)
        } else {
            throw EnrichmentError.apiError("Invalid response: missing both data and error")
        }

        return EnrichmentSearchResponseFlat(
            items: transformedResults,
            totalItems: totalItems
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

            // Prefer results with cover images (increased from 5 to 30)
            // This ensures we prioritize results with covers when title/author match is close
            if result.coverImage != nil {
                score += 30
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
                coverImageURL: searchResult.coverImage
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

    public func enrichBookV2(barcode: String, in modelContext: ModelContext) async -> Result<Work, EnrichmentError> {
        do {
            let dto = try await apiClient.enrichBookV2(barcode: barcode)
            let work = createOrUpdateWork(from: dto, in: modelContext)
            totalEnriched += 1
            return .success(work)
        } catch {
            totalFailed += 1
            if let enrichmentError = error as? EnrichmentError {
                return .failure(enrichmentError)
            }
            return .failure(.apiError(String(describing: error)))
        }
    }

    private func createOrUpdateWork(from dto: EnrichedBookDTO, in modelContext: ModelContext) -> Work {
        let isbn = dto.isbn
        // Check primary isbn field OR isbns array for matching ISBN
        let predicate = #Predicate<Edition> { edition in
            edition.isbn == isbn || edition.isbns.contains(isbn)
        }
        var descriptor = FetchDescriptor<Edition>(predicate: predicate)
        descriptor.fetchLimit = 1

        let work: Work
        if let existingEdition = (try? modelContext.fetch(descriptor))?.first,
           let existingWork = existingEdition.work {
            // Update existing edition and work
            work = existingWork

            existingEdition.publisher = dto.publisher ?? existingEdition.publisher
            existingEdition.publicationDate = dto.publishedDate ?? existingEdition.publicationDate
            existingEdition.pageCount = dto.pageCount ?? existingEdition.pageCount
            existingEdition.coverImageURL = dto.coverUrl ?? existingEdition.coverImageURL
            existingEdition.touch()

            // Only update title if it's empty or has the placeholder value
            if (work.title.isEmpty || work.title == "Unknown Title"), !dto.title.isEmpty {
                work.title = dto.title
            }

            work.authors = findOrCreateAuthors(named: dto.authors, in: modelContext)
            work.touch()

        } else {
            work = Work(title: dto.title)
            modelContext.insert(work)

            // Create and insert authors FIRST, then set relationship
            // Per SwiftData lifecycle: both objects must be inserted before setting relationships
            let authors = findOrCreateAuthors(named: dto.authors, in: modelContext)
            work.authors = authors

            let newEdition = Edition(
                isbn: dto.isbn,
                publisher: dto.publisher,
                publicationDate: dto.publishedDate,
                pageCount: dto.pageCount,
                format: .paperback,
                coverImageURL: dto.coverUrl
            )
            modelContext.insert(newEdition)

            newEdition.work = work
        }

        try? modelContext.save()
        return work
    }

    private func findOrCreateAuthors(named authorNames: [String], in modelContext: ModelContext) -> [Author] {
        // Deduplicate input names to prevent creating duplicate authors
        let uniqueAuthorNames = Set(authorNames)
        guard !uniqueAuthorNames.isEmpty else { return [] }

        let predicate = #Predicate<Author> { author in
            uniqueAuthorNames.contains(author.name)
        }
        let existingAuthors = (try? modelContext.fetch(FetchDescriptor<Author>(predicate: predicate))) ?? []
        let existingAuthorNames = Set(existingAuthors.map { $0.name })

        var finalAuthors = existingAuthors

        for name in uniqueAuthorNames where !existingAuthorNames.contains(name) {
            let newAuthor = Author(name: name)
            modelContext.insert(newAuthor)
            finalAuthors.append(newAuthor)
        }

        return finalAuthors
    }
}

// MARK: - Supporting Types

public enum EnrichmentResult {
    case success
    case failure(EnrichmentError)
}

public enum EnrichmentError: Error, Sendable, LocalizedError {
    case missingTitle
    case noMatchFound
    case apiError(String)
    case invalidQuery
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case rateLimitExceeded(retryAfter: Int)
    case circuitOpen(provider: String, retryAfterMs: Int)

    public var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Book title is required"
        case .noMatchFound:
            return "No matching book found"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded. Try again in \(retryAfter) seconds."
        case .circuitOpen(let provider, let retryAfterMs):
            let seconds = retryAfterMs / 1000
            return "Provider '\(provider)' temporarily unavailable. Retry in \(seconds) seconds."
        }
    }
}

public struct BatchEnrichmentResult: Sendable {
    public let successCount: Int
    public let failureCount: Int
    public let errors: [EnrichmentError]
    public let token: String?  // WebSocket authentication token (nil on error)
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

    /// Create from canonical WorkDTO + EditionDTO (v1 API response)
    init(from workDTO: WorkDTO, edition: EditionDTO?, authors: [AuthorDTO]) {
        self.title = workDTO.title
        self.author = authors.first?.name ?? "Unknown Author"
        self.isbn = edition?.isbn
        self.coverImage = edition?.coverImageURL
        self.publicationYear = workDTO.firstPublicationYear
        self.publicationDate = edition?.publicationDate
        self.publisher = edition?.publisher
        self.pageCount = edition?.pageCount
        self.openLibraryWorkID = workDTO.openLibraryWorkID
        self.googleBooksVolumeID = workDTO.googleBooksVolumeIDs.first ?? workDTO.googleBooksVolumeID
    }
}

// MARK: - Flat Response (for internal use)

private struct EnrichmentSearchResponseFlat {
    let items: [EnrichmentSearchResult]
    let totalItems: Int
}
