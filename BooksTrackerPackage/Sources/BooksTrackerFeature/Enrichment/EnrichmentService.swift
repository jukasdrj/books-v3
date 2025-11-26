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

    /// Enrich a single book using ISBN barcode (V2 synchronous endpoint)
    /// - Parameters:
    ///   - isbn: ISBN-10 or ISBN-13 barcode
    ///   - modelContext: SwiftData model context for saving enriched data
    /// - Returns: EnrichmentResult indicating success or failure
    /// - Note: Uses V2 /api/v2/books/enrich endpoint for fast, synchronous enrichment
    public func enrichWorkByISBN(
        _ isbn: String,
        in modelContext: ModelContext
    ) async -> EnrichmentResult {
        do {
            let response = try await apiClient.enrichBookV2(barcode: isbn)

            #if DEBUG
            print("✅ V2 Enrichment successful: \(response.title) by \(response.authors.joined(separator: ", "))")
            #endif

            // Find or create work with enriched data
            let work = await findOrCreateWork(from: response, in: modelContext)

            totalEnriched += 1
            return .success

        } catch let error as EnrichmentV2Error {
            totalFailed += 1

            #if DEBUG
            print("🚨 V2 Enrichment failed: \(error.localizedDescription)")
            #endif

            // Map V2 errors to existing EnrichmentError
            switch error {
            case .bookNotFound:
                return .failure(.noMatchFound)
            case .invalidBarcode:
                return .failure(.invalidQuery)
            case .rateLimitExceeded, .serviceUnavailable, .invalidResponse:
                return .failure(.apiError(error.localizedDescription))
            case .httpError(let statusCode):
                return .failure(.httpError(statusCode))
            }

        } catch {
            totalFailed += 1

            #if DEBUG
            print("🚨 Unexpected V2 enrichment error: \(error)")
            #endif

            return .failure(.apiError(String(describing: error)))
        }
    }

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
                token: result.token  // WebSocket authentication token
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

    /// Find existing work by ISBN or create new work from V2 enrichment response
    private func findOrCreateWork(
        from response: V2EnrichmentResponse,
        in modelContext: ModelContext
    ) async -> Work {
        // Try to find existing work by ISBN
        if let existingWork = findWorkByISBN(response.isbn, in: modelContext) {
            // Update existing work with new data if missing
            updateWorkFromV2Response(existingWork, with: response, in: modelContext)
            return existingWork
        }

        // Create new work
        let work = Work(
            title: response.title,
            authors: []  // Will be set after insertion
        )

        // Insert work first to get permanent ID
        modelContext.insert(work)

        // Set publication year from date if available
        if let publishedDate = response.publishedDate {
            work.firstPublicationYear = extractYear(from: publishedDate)
        }

        // Create author if we have author names
        if !response.authors.isEmpty {
            let authorName = response.authors.first ?? "Unknown Author"
            let author = Author(name: authorName)
            modelContext.insert(author)

            // Set bidirectional relationship
            work.authors = [author]
        }

        // Create edition with enriched data
        let edition = Edition(
            isbn: response.isbn,
            publisher: response.publisher,
            publicationDate: response.publishedDate,
            pageCount: response.pageCount,
            format: .paperback,
            coverImageURL: response.coverUrl
        )
        modelContext.insert(edition)

        // Set bidirectional relationship
        edition.work = work

        work.touch()

        try? modelContext.save()

        return work
    }

    /// Find work by ISBN in model context
    private func findWorkByISBN(_ isbn: String, in modelContext: ModelContext) -> Work? {
        let descriptor = FetchDescriptor<Edition>(
            predicate: #Predicate<Edition> { edition in
                edition.isbn == isbn
            }
        )

        if let edition = try? modelContext.fetch(descriptor).first {
            return edition.work
        }

        return nil
    }

    /// Update existing work with V2 enrichment data
    private func updateWorkFromV2Response(
        _ work: Work,
        with response: V2EnrichmentResponse,
        in modelContext: ModelContext
    ) {
        // Update publication year if missing
        if work.firstPublicationYear == nil, let publishedDate = response.publishedDate {
            work.firstPublicationYear = extractYear(from: publishedDate)
        }

        // Find or create edition
        var edition: Edition?

        if let existingEditions = work.editions, !existingEditions.isEmpty {
            edition = existingEditions.first
        } else {
            let newEdition = Edition(
                isbn: response.isbn,
                publisher: response.publisher,
                publicationDate: response.publishedDate,
                pageCount: response.pageCount,
                format: .paperback,
                coverImageURL: response.coverUrl
            )
            modelContext.insert(newEdition)
            newEdition.work = work
            edition = newEdition
        }

        // Update edition with missing data
        if let edition = edition {
            if edition.coverImageURL == nil, let coverURL = response.coverUrl {
                edition.coverImageURL = coverURL
            }

            if edition.pageCount == nil {
                edition.pageCount = response.pageCount
            }

            if edition.publisher == nil {
                edition.publisher = response.publisher
            }

            edition.touch()
        }

        work.touch()

        try? modelContext.save()
    }

    /// Extract year from date string (formats: YYYY, YYYY-MM-DD)
    private func extractYear(from dateString: String) -> Int? {
        // Try full ISO date format first
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"

        if let date = isoFormatter.date(from: dateString) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }

        // Try just year
        if let year = Int(dateString.prefix(4)) {
            return year
        }

        return nil
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
