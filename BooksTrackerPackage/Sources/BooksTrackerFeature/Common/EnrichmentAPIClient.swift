import Foundation

// MARK: - Retry Configuration

/// Configuration for retry behavior with exponential backoff
struct RetryConfiguration: Sendable {
    /// Maximum number of retry attempts (including the initial attempt)
    let maxAttempts: Int
    /// Initial delay before first retry (seconds)
    let initialDelay: TimeInterval
    /// Maximum delay between retries (seconds)
    let maxDelay: TimeInterval
    /// Multiplier for exponential backoff
    let backoffMultiplier: Double

    /// Default configuration: 3 attempts, 1s initial delay, 60s max, 2x backoff
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0
    )

    /// Aggressive configuration: 5 attempts, 0.5s initial delay, 30s max, 1.5x backoff
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 30.0,
        backoffMultiplier: 1.5
    )

    /// No retry configuration: single attempt only
    static let none = RetryConfiguration(
        maxAttempts: 1,
        initialDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0
    )
}

/// API client for triggering backend enrichment jobs
actor EnrichmentAPIClient {

    private let baseURL = EnrichmentConfig.baseURL

    struct EnrichmentResult: Codable, Sendable {
        let success: Bool
        let processedCount: Int
        let totalCount: Int
        let authToken: String  // Auth token for WebSocket connection (canonical)

        /// **DEPRECATED:** Use `authToken` instead. Removal: March 1, 2026
        /// Kept for API backward compatibility only - always nil in new code
        let token: String?

        /// Server-assigned job ID for async enrichment (V3 API)
        /// CRITICAL: Use this for WebSocket/SSE connections, NOT the client-generated UUID
        let serverJobId: String?

        /// V3 SSE stream URL for real-time progress (preferred over WebSocket)
        /// Format: https://api.oooefam.net/v3/jobs/enrichment/{jobId}/stream
        let streamUrl: String?

        /// Embedded enriched books for sync mode (batch ≤50 ISBNs)
        /// When present, bypass WebSocket and use these results directly
        let embeddedBooks: [SyncEnrichedBook]?

        /// True if this result contains embedded books (sync mode)
        var hasSyncResults: Bool {
            embeddedBooks != nil && !embeddedBooks!.isEmpty
        }

        /// Memberwise initializer for programmatic construction (e.g., title-based search results)
        init(
            success: Bool,
            processedCount: Int,
            totalCount: Int,
            authToken: String,
            serverJobId: String? = nil,
            streamUrl: String? = nil,
            embeddedBooks: [SyncEnrichedBook]? = nil
        ) {
            self.success = success
            self.processedCount = processedCount
            self.totalCount = totalCount
            self.authToken = authToken
            self.token = nil  // Deprecated property
            self.serverJobId = serverJobId
            self.streamUrl = streamUrl
            self.embeddedBooks = embeddedBooks
        }

        // Custom decoding to handle both authToken and token fields
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            success = try container.decode(Bool.self, forKey: .success)
            processedCount = try container.decode(Int.self, forKey: .processedCount)
            totalCount = try container.decode(Int.self, forKey: .totalCount)

            // Prefer authToken, fallback to token for legacy responses
            if let authTokenValue = try? container.decode(String.self, forKey: .authToken) {
                authToken = authTokenValue
            } else if let tokenValue = try? container.decode(String.self, forKey: .token) {
                // Legacy response - only has token field
                authToken = tokenValue
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.authToken,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected authToken or token field"
                    )
                )
            }

            // token property is deprecated - no longer populated
            token = nil

            // These fields are only present in programmatic construction (async mode), not from JSON
            serverJobId = nil
            streamUrl = nil
            embeddedBooks = nil
        }

        private enum CodingKeys: String, CodingKey {
            case success, processedCount, totalCount, authToken, token
        }
    }

    /// V3 Async Enrichment Response (for batches >50 ISBNs)
    /// Returns jobId + token for SSE progress tracking instead of immediate results
    struct AsyncEnrichmentResult: Codable, Sendable {
        let jobId: String
        let status: String  // "queued"
        let streamUrl: String?
        let token: String  // Auth token for SSE/WebSocket connection

        /// Convert to standard EnrichmentResult for API compatibility
        /// CRITICAL: Passes serverJobId and streamUrl for SSE/WebSocket connection
        func toEnrichmentResult(totalCount: Int) -> EnrichmentResult {
            EnrichmentResult(
                success: true,
                processedCount: 0,  // Job queued, not processed yet
                totalCount: totalCount,
                authToken: token,
                serverJobId: jobId,      // Server-assigned job ID for SSE/WS
                streamUrl: streamUrl,    // V3 SSE stream URL (preferred)
                embeddedBooks: nil
            )
        }
    }

    // MARK: - V3 Sync Enrichment Response (for batches ≤50 ISBNs)

    /// Response structure for sync enrichment (HTTP 200, immediate results)
    /// V3 API returns enriched books directly when batch ≤50 ISBNs
    struct SyncEnrichmentResponse: Codable, Sendable {
        let books: [SyncEnrichedBook]
        let requested: Int
        let found: Int
        let notFound: [String]

        /// Convert to standard EnrichmentResult with embedded books
        func toEnrichmentResult() -> EnrichmentResult {
            EnrichmentResult(
                success: true,
                processedCount: found,
                totalCount: requested,
                authToken: "",  // No WebSocket needed for sync mode
                embeddedBooks: books
            )
        }
    }

    /// Enriched book from V3 sync response
    /// Flattened structure matching backend's Book schema
    struct SyncEnrichedBook: Codable, Sendable {
        let isbn: String
        let isbn10: String?
        let title: String
        let subtitle: String?
        let authors: [String]
        let publisher: PublisherValue?  // Can be string or array
        let publishedDate: String?
        let description: String?
        let pageCount: Int?
        let categories: [String]?
        let language: String?
        let coverUrl: String?
        let thumbnailUrl: String?
        let workKey: String?
        let editionKey: String?
        let provider: String
        let quality: Double
        let vectorized: Bool?

        /// Publisher can be returned as either a String or [String] from backend
        enum PublisherValue: Codable, Sendable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let stringValue = try? container.decode(String.self) {
                    self = .string(stringValue)
                } else if let arrayValue = try? container.decode([String].self) {
                    self = .array(arrayValue)
                } else {
                    self = .string("")  // Default to empty string if null
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let value):
                    try container.encode(value)
                case .array(let value):
                    try container.encode(value)
                }
            }

            /// Get first publisher value as String
            var firstPublisher: String? {
                switch self {
                case .string(let value):
                    return value.isEmpty ? nil : value
                case .array(let values):
                    return values.first
                }
            }
        }

        /// Convert to EnrichedBookPayload for downstream processing
        func toEnrichedBookPayload() -> EnrichedBookPayload {
            // Create EnrichedDataPayload from flat fields
            let workDTO = WorkDTO(
                title: title,
                subjectTags: categories ?? [],
                originalLanguage: language,
                firstPublicationYear: nil,
                description: description,
                coverImageURL: coverUrl,
                searchLinks: nil,
                synthetic: nil,
                primaryProvider: provider,
                contributors: nil,
                openLibraryID: nil,
                openLibraryWorkID: workKey?.hasPrefix("OL") == true ? workKey : nil,
                isbndbID: workKey?.hasPrefix("isbndb-") == true ? workKey?.replacingOccurrences(of: "isbndb-", with: "") : nil,
                googleBooksVolumeID: nil,
                goodreadsID: nil,
                goodreadsWorkIDs: [],
                amazonASINs: [],
                librarythingIDs: [],
                googleBooksVolumeIDs: [],
                isbndbQuality: Int(quality),
                reviewStatus: .verified
            )

            // Build ISBN array for EditionDTO
            var isbnsArray: [String] = [isbn]
            if let isbn10Value = isbn10 {
                isbnsArray.append(isbn10Value)
            }

            let editionDTO = EditionDTO(
                isbn: isbn,
                isbns: isbnsArray,
                title: title,
                publisher: publisher?.firstPublisher,
                publicationDate: publishedDate,
                pageCount: pageCount,
                format: .paperback,  // Default format
                coverImageURL: coverUrl ?? thumbnailUrl,
                editionTitle: subtitle,
                language: language,
                primaryProvider: provider,
                openLibraryID: nil,
                openLibraryEditionID: editionKey?.hasPrefix("OL") == true ? editionKey : nil,
                isbndbID: editionKey?.hasPrefix("isbndb-") == true ? editionKey : nil,
                googleBooksVolumeID: nil,
                amazonASINs: [],
                googleBooksVolumeIDs: [],
                librarythingIDs: [],
                isbndbQuality: Int(quality)
            )

            // Create author DTOs from string array
            let authorDTOs = authors.map { authorName in
                AuthorDTO(
                    name: authorName,
                    gender: .unknown
                )
            }

            let enrichedData = EnrichedDataPayload(
                work: workDTO,
                edition: editionDTO,
                authors: authorDTOs
            )

            return EnrichedBookPayload(
                title: title,
                author: authors.first,
                isbn: isbn,
                success: true,
                error: nil,
                enriched: enrichedData
            )
        }
    }

    /// Start enrichment job on backend with automatic retry for retryable errors
    /// Backend will push progress updates via WebSocket
    /// - Parameters:
    ///   - jobId: Unique job identifier for WebSocket tracking
    ///   - books: Books to enrich
    ///   - retryConfig: Retry configuration (default: .default)
    /// - Returns: Enrichment result with final counts
    /// - Note: Books with ISBNs use POST /v3/books/enrich; books without ISBNs use title-based search
    func startEnrichment(jobId: String, books: [Book], retryConfig: RetryConfiguration = .default) async throws -> EnrichmentResult {
        // Split books into those with and without ISBNs
        let booksWithISBN = books.filter { $0.isbn != nil && !$0.isbn!.isEmpty }
        let booksWithoutISBN = books.filter { $0.isbn == nil || $0.isbn!.isEmpty }

        #if DEBUG
        print("[EnrichmentAPIClient] 📊 Books split: \(booksWithISBN.count) with ISBN, \(booksWithoutISBN.count) without ISBN")
        #endif

        // If we have books with ISBNs, use the batch endpoint
        if !booksWithISBN.isEmpty {
            return try await retryWithBackoff(config: retryConfig) { [self] in
                try await self.performEnrichment(endpoint: "/v3/books/enrich", jobId: jobId, books: booksWithISBN)
            }
        }

        // If we only have books without ISBNs, use title-based search enrichment
        if !booksWithoutISBN.isEmpty {
            return try await enrichByTitleSearch(jobId: jobId, books: booksWithoutISBN, retryConfig: retryConfig)
        }

        // No books to enrich
        throw NSError(
            domain: "com.bookstrack.api",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "No books provided for enrichment"]
        )
    }

    /// Enrich books without ISBNs using title-based search via V3 search endpoint
    /// - Parameters:
    ///   - jobId: Unique job identifier for tracking
    ///   - books: Books without ISBNs to enrich via title search
    ///   - retryConfig: Retry configuration
    /// - Returns: Enrichment result with counts and embedded enrichment data
    private func enrichByTitleSearch(jobId: String, books: [Book], retryConfig: RetryConfiguration) async throws -> EnrichmentResult {
        #if DEBUG
        print("[EnrichmentAPIClient] 📖 Starting title-based enrichment for \(books.count) books without ISBNs")
        #endif

        var enrichedBooks: [EnrichedBookPayload] = []

        for book in books {
            do {
                // Build search query: "title author:authorname"
                var queryParts: [String] = [book.title]
                if !book.author.isEmpty && book.author != "Unknown Author" {
                    queryParts.append("author:\(book.author)")
                }
                let query = queryParts.joined(separator: " ")

                guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "\(baseURL)/v3/books/search?q=\(encodedQuery)&mode=text&limit=1") else {
                    #if DEBUG
                    print("[EnrichmentAPIClient] ⚠️ Invalid URL for title search: \(book.title)")
                    #endif
                    enrichedBooks.append(EnrichedBookPayload(
                        title: book.title, author: book.author, isbn: nil,
                        success: false, error: "Invalid search URL", enriched: nil
                    ))
                    continue
                }

                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
                request.setValue("v3.3", forHTTPHeaderField: "X-API-Contract-Version")
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    #if DEBUG
                    print("[EnrichmentAPIClient] ⚠️ Search failed for '\(book.title)': HTTP \(statusCode)")
                    #endif
                    enrichedBooks.append(EnrichedBookPayload(
                        title: book.title, author: book.author, isbn: nil,
                        success: false, error: "HTTP \(statusCode)", enriched: nil
                    ))
                    continue
                }

                // V3 Search Response is already the full envelope (not wrapped)
                let searchResponse = try JSONDecoder().decode(V3SearchResponse.self, from: data)

                // Check for API error in V3 response
                guard searchResponse.success else {
                    #if DEBUG
                    print("[EnrichmentAPIClient] ⚠️ V3 search failed for '\(book.title)'")
                    #endif
                    enrichedBooks.append(EnrichedBookPayload(
                        title: book.title, author: book.author, isbn: nil,
                        success: false, error: "Search returned failure", enriched: nil
                    ))
                    continue
                }

                if let v3Book = searchResponse.data.books.first {
                    // Found a match - convert V3Book to canonical DTOs for EnrichedDataPayload
                    // This maintains compatibility with existing enrichment pipeline
                    let workDTO = WorkDTO(
                        title: v3Book.title,
                        subjectTags: v3Book.categories ?? [],
                        originalLanguage: v3Book.language,
                        firstPublicationYear: Self.extractYear(from: v3Book.publishedDate),
                        description: v3Book.description,
                        coverImageURL: v3Book.coverUrl,
                        openLibraryWorkID: v3Book.workKey,
                        goodreadsWorkIDs: [],
                        amazonASINs: [],
                        librarythingIDs: [],
                        googleBooksVolumeIDs: [],
                        isbndbQuality: Int(v3Book.quality),
                        reviewStatus: .verified
                    )

                    let editionDTO = EditionDTO(
                        isbn: v3Book.isbn,
                        isbns: [v3Book.isbn],
                        title: v3Book.title,
                        publisher: v3Book.publisher,
                        publicationDate: v3Book.publishedDate,
                        pageCount: v3Book.pageCount,
                        format: .paperback,  // Default - V3 doesn't expose format
                        coverImageURL: v3Book.coverUrl,
                        editionDescription: v3Book.description,
                        language: v3Book.language,
                        openLibraryEditionID: v3Book.editionKey,
                        amazonASINs: [],
                        googleBooksVolumeIDs: [],
                        librarythingIDs: [],
                        isbndbQuality: Int(v3Book.quality)
                    )

                    let authorDTOs = v3Book.authors.map { name in
                        AuthorDTO(name: name, gender: .unknown)
                    }

                    let enrichedData = EnrichedDataPayload(
                        work: workDTO,
                        edition: editionDTO,
                        authors: authorDTOs
                    )

                    enrichedBooks.append(EnrichedBookPayload(
                        title: book.title,
                        author: book.author,
                        isbn: v3Book.isbn,
                        success: true,
                        error: nil,
                        enriched: enrichedData
                    ))

                    #if DEBUG
                    print("[EnrichmentAPIClient] ✅ Found match for '\(book.title)': \(v3Book.title)")
                    #endif
                } else {
                    #if DEBUG
                    print("[EnrichmentAPIClient] ⚠️ No match found for '\(book.title)'")
                    #endif
                    enrichedBooks.append(EnrichedBookPayload(
                        title: book.title, author: book.author, isbn: nil,
                        success: false, error: "No match found", enriched: nil
                    ))
                }

                // Small delay between requests to avoid rate limiting
                if enrichedBooks.count < books.count {
                    try await Task.sleep(for: .milliseconds(100))
                }

            } catch {
                #if DEBUG
                print("[EnrichmentAPIClient] ⚠️ Error searching for '\(book.title)': \(error.localizedDescription)")
                #endif
                enrichedBooks.append(EnrichedBookPayload(
                    title: book.title, author: book.author, isbn: nil,
                    success: false, error: error.localizedDescription, enriched: nil
                ))
            }
        }

        let successCount = enrichedBooks.filter { $0.success }.count

        #if DEBUG
        print("[EnrichmentAPIClient] 📊 Title-based enrichment complete: \(successCount)/\(books.count) matched")
        #endif

        // Store enriched data in TitleSearchResultsCache for retrieval by EnrichmentQueue
        await TitleSearchResultsCache.shared.store(jobId: jobId, results: enrichedBooks)

        // Return result with marker token indicating title-based search was used
        // EnrichmentQueue will detect this and retrieve data from TitleSearchResultsCache
        return EnrichmentResult(
            success: successCount > 0,
            processedCount: enrichedBooks.count,
            totalCount: books.count,
            authToken: "title-search:\(jobId)"  // Marker token with job ID for cache retrieval
        )
    }

    /// Log fallback event for observability (sends to console in DEBUG, ready for analytics integration)
    private static func logFallbackMetric(fromEndpoint: String, toEndpoint: String, reason: String) {
        #if DEBUG
        print("📊 [EnrichmentAPIClient] Fallback: \(fromEndpoint) → \(toEndpoint) (reason: \(reason))")
        #endif
        // TODO: Send to analytics/observability system (Firebase, Sentry, etc.)
        // Example: Analytics.log("enrichment_endpoint_fallback", parameters: ["from": fromEndpoint, "to": toEndpoint, "reason": reason])
    }

    /// Performs enrichment request to specified endpoint
    /// - Parameters:
    ///   - endpoint: API endpoint path (e.g., "/v3/books/enrich")
    ///   - jobId: Unique job identifier for WebSocket tracking
    ///   - books: Books to enrich
    /// - Returns: Enrichment result with job details
    private func performEnrichment(endpoint: String, jobId: String, books: [Book]) async throws -> EnrichmentResult {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.setValue("v3.3", forHTTPHeaderField: "X-API-Contract-Version")
        request.timeoutInterval = 30  // 30 second timeout for POST request

        // Track async mode for response decoding
        var useAsyncMode = false
        var isbnCount = 0

        // V3 API requires isbns array format; legacy API uses books array format
        if endpoint.hasPrefix("/v3/") {
            // V3 format: extract and clean ISBNs from books
            // - Removes hyphens/spaces
            // - Converts ISBN-10 with 'X' suffix to ISBN-13
            // - Filters out invalid formats (must be 10 or 13 digits)
            // Backend regex: /^\d{10}(\d{3})?$/ - only accepts digits
            let allIsbns = books.compactMap { $0.isbn }.filter { !$0.isEmpty }
            let cleanedIsbns = allIsbns.compactMap { ISBNValidator.cleanForAPI($0) }

            #if DEBUG
            let skippedCount = allIsbns.count - cleanedIsbns.count
            if skippedCount > 0 {
                let invalidIsbns = allIsbns.filter { ISBNValidator.cleanForAPI($0) == nil }
                print("[EnrichmentAPIClient] ⚠️ Skipping \(skippedCount) invalid ISBNs: \(invalidIsbns)")
            }
            // Log any ISBN-10→13 conversions
            let convertedIsbns = zip(allIsbns, cleanedIsbns).filter { original, cleaned in
                let originalClean = original.filter { $0.isNumber || $0.uppercased() == "X" }
                return originalClean.count == 10 && cleaned.count == 13
            }
            if !convertedIsbns.isEmpty {
                print("[EnrichmentAPIClient] 🔄 Converted \(convertedIsbns.count) ISBN-10 to ISBN-13")
            }
            #endif

            let validIsbns = cleanedIsbns
            isbnCount = validIsbns.count

            guard !validIsbns.isEmpty else {
                // No valid ISBNs - cannot use V3 enrichment
                // Fall back to title-based search instead
                throw NSError(
                    domain: "com.bookstrack.api",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "No valid ISBNs available for V3 enrichment. Books without ISBNs require title-based search."]
                )
            }

            // V3 format: isbns array + jobId in header
            // Use async mode for batches >50 ISBNs (V3 API limit for sync mode)
            useAsyncMode = validIsbns.count > 50
            let v3Payload = V3EnrichRequest(isbns: validIsbns, includeEmbedding: false, async: useAsyncMode ? true : nil)
            request.httpBody = try JSONEncoder().encode(v3Payload)
            request.setValue(jobId, forHTTPHeaderField: "X-Job-ID")

            #if DEBUG
            print("[EnrichmentAPIClient] 📤 Sending V3 POST to \(endpoint) (jobId: \(jobId), isbns: \(validIsbns.count), async: \(useAsyncMode))")
            #endif
        } else {
            // Legacy format: books array with title/author/isbn
            let payload = BatchEnrichmentPayload(books: books, jobId: jobId)
            request.httpBody = try JSONEncoder().encode(payload)

            #if DEBUG
            print("[EnrichmentAPIClient] 📤 Sending legacy POST to \(endpoint) (jobId: \(jobId), books: \(books.count))")
            #endif
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[EnrichmentAPIClient] ✅ Received HTTP \(statusCode) response from \(endpoint)")
        #endif

        // CORS Detection (Issue #428)
        // NOTE: This detects backend-signaled CORS errors via X-Custom-Error header.
        // Real CORS errors (browser/OS blocks) result in status 0 or network errors
        // and cannot be reliably detected client-side. This is primarily for web builds
        // where backends can explicitly signal CORS policy violations.
        if let httpResponse = response as? HTTPURLResponse {
            if let customError = httpResponse.value(forHTTPHeaderField: "X-Custom-Error"),
               customError == "CORS_BLOCKED" {
                throw ApiErrorCode.corsBlocked.toNSError()
            }
        }

        // V3 API returns:
        // - HTTP 200: Sync mode success (batch ≤50 ISBNs, async: false/nil)
        // - HTTP 202: Async mode accepted (batch >50 ISBNs, async: true)
        let expectedStatus = useAsyncMode ? 202 : 200
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == expectedStatus else {
            // Enhanced error logging for debugging enrichment failures
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            #if DEBUG
            print("🚨 Enrichment API error: HTTP \(statusCode) from \(endpoint)")
            #endif

            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif

            // Try to decode error response to extract error code
            // Backend returns ResponseEnvelope for both success and error cases
            do {
                _ = try data.decodeEnvelope(EnrichmentResult.self)
                // If decoding succeeds, we shouldn't be here (should have gotten 202)
                throw NSError(domain: "com.bookstrack.api", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Unexpected success response with non-202 status"])
            } catch let error as ResponseEnvelopeError {
                if case .apiError(let code, let message, let details) = error {
                    #if DEBUG
                    print("🚨 API Error: \(message), Code: \(code ?? "UNKNOWN")")
                    #endif

                    // Use ApiErrorCode for structured error handling (Issue #429)
                    if let errorCode = ApiErrorCode.from(code: code) {
                        throw errorCode.toNSError(details: details)
                    } else {
                        // Fallback for unknown error codes (preserve backend message)
                        let userInfo: [String: Any] = [
                            NSLocalizedDescriptionKey: message,
                            "errorCode": code ?? "UNKNOWN",
                            "details": details ?? NSNull()
                        ]
                        throw NSError(domain: "com.bookstrack.api", code: statusCode, userInfo: userInfo)
                    }
                }
                // For other ResponseEnvelopeError cases, fall through
            }
            throw NSError(domain: "com.bookstrack.api", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Enrichment request failed"])
        }

        // Decode ResponseEnvelope and unwrap data
        // Async mode: { jobId, status, streamUrl, token } - requires WebSocket for results
        // Sync mode: { books, requested, found, notFound } - results are embedded
        let result: EnrichmentResult
        do {
            if useAsyncMode {
                // V3 Async: { jobId, status: "queued", streamUrl, token }
                let asyncResult = try data.decodeEnvelope(AsyncEnrichmentResult.self)
                result = asyncResult.toEnrichmentResult(totalCount: isbnCount)

                #if DEBUG
                print("✅ Async enrichment job queued: jobId=\(asyncResult.jobId), token=\(asyncResult.token.prefix(8))..., streamUrl=\(asyncResult.streamUrl ?? "none")")
                #endif
            } else {
                // V3 Sync: { books, requested, found, notFound } - results embedded directly
                let syncResult = try data.decodeEnvelope(SyncEnrichmentResponse.self)
                result = syncResult.toEnrichmentResult()

                #if DEBUG
                print("✅ Sync enrichment completed: \(syncResult.found)/\(syncResult.requested) books found, \(syncResult.notFound.count) not found")
                if !syncResult.notFound.isEmpty {
                    print("⚠️ ISBNs not found: \(syncResult.notFound.joined(separator: ", "))")
                }
                #endif
            }
        } catch let error as ResponseEnvelopeError {
            if case .apiError(let code, let message, let details) = error {
                #if DEBUG
                print("🚨 Enrichment envelope error: \(message), Code: \(code ?? "UNKNOWN")")
                #endif

                // Use ApiErrorCode for structured error handling (Issue #429)
                if let errorCode = ApiErrorCode.from(code: code) {
                    throw errorCode.toNSError(details: details)
                } else {
                    // Fallback for unknown error codes
                    throw NSError(domain: "com.bookstrack.api", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
                }
            } else if case .missingData = error {
                #if DEBUG
                print("🚨 Enrichment response missing data field from \(endpoint)")
                #endif
                throw URLError(.badServerResponse)
            } else {
                // .decodingFailed case
                throw error
            }
        }

        return result
    }

    // MARK: - Job Cancellation (API v3.1)

    struct JobCancellationResponse: Codable, Sendable {
        let jobId: String
        let status: String
        let message: String
        let cleanup: CleanupDetails

        struct CleanupDetails: Codable, Sendable {
            let r2ObjectsDeleted: Int
            let kvCacheCleared: Bool
        }
    }

    /// Cancel an enrichment job and cleanup R2 images/KV cache (V3 API)
    /// - Parameters:
    ///   - jobId: The unique job identifier to cancel
    ///   - authToken: Bearer token from job creation (required for authentication)
    /// - Returns: Job cancellation response with cleanup details
    /// - Note: Idempotent - calling DELETE on completed jobs returns success
    func cancelJob(jobId: String, authToken: String) async throws -> JobCancellationResponse {
        guard let url = URL(string: "\(baseURL)/v3/jobs/enrichment/\(jobId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.setValue("v3.3", forHTTPHeaderField: "X-API-Contract-Version")
        request.timeoutInterval = 15  // 15 second timeout for DELETE request

        #if DEBUG
        print("[EnrichmentAPIClient] 🗑️ Sending DELETE to /v3/jobs/enrichment/\(jobId)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Handle authentication errors
        if httpResponse.statusCode == 401 {
            #if DEBUG
            print("🚨 Job cancellation unauthorized: Invalid or expired token")
            #endif
            throw NSError(domain: "com.bookstrack.api", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed: Invalid or expired token"])
        }

        guard httpResponse.statusCode == 200 else {
            #if DEBUG
            print("🚨 Job cancellation failed: HTTP \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif
            throw NSError(domain: "com.bookstrack.api", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Job cancellation failed"])
        }

        // Decode ResponseEnvelope and unwrap data
        let result = try data.decodeEnvelope(JobCancellationResponse.self)

        #if DEBUG
        print("✅ Job \(jobId) canceled successfully: \(result.cleanup.r2ObjectsDeleted) R2 objects deleted")
        #endif

        return result
    }

    // MARK: - Helper Methods

    /// Extract year from V3 publishedDate string (e.g., "2023-05-15" → 2023)
    private static func extractYear(from publishedDate: String?) -> Int? {
        guard let dateStr = publishedDate else { return nil }
        // Try to extract year from various formats: "2023", "2023-05-15", "May 2023"
        let yearRegex = try? NSRegularExpression(pattern: #"(19|20)\d{2}"#)
        if let match = yearRegex?.firstMatch(in: dateStr, range: NSRange(dateStr.startIndex..., in: dateStr)),
           let range = Range(match.range, in: dateStr) {
            return Int(dateStr[range])
        }
        return nil
    }

    // MARK: - Retry Logic with Exponential Backoff

    /// Retry wrapper with exponential backoff for retryable errors
    /// - Parameters:
    ///   - config: Retry configuration
    ///   - operation: Async operation to retry
    /// - Returns: Result of successful operation
    /// - Throws: Error if all retries exhausted or non-retryable error
    private func retryWithBackoff<T: Sendable>(
        config: RetryConfiguration,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < config.maxAttempts {
            do {
                return try await operation()
            } catch let error as EnrichmentError {
                lastError = error

                // Determine if error is retryable and get delay
                let (retryable, delay) = getRetryInfo(for: error, config: config, attempt: attempt)

                if !retryable {
                    throw error
                }

                attempt += 1
                if attempt >= config.maxAttempts {
                    throw error
                }

                #if DEBUG
                print("⚠️ Retryable error (attempt \(attempt)/\(config.maxAttempts)), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                #endif

                try await Task.sleep(for: .seconds(delay))
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost || error.code == .notConnectedToInternet {
                // Network errors are retryable with exponential backoff
                lastError = error

                // Calculate delay BEFORE incrementing attempt (consistent with EnrichmentError handling)
                let delay = min(
                    config.initialDelay * pow(config.backoffMultiplier, Double(attempt)),
                    config.maxDelay
                )

                attempt += 1
                if attempt >= config.maxAttempts {
                    throw error
                }

                #if DEBUG
                print("⚠️ Network error (attempt \(attempt)/\(config.maxAttempts)), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                #endif

                try await Task.sleep(for: .seconds(delay))
            } catch {
                // Non-retryable error - fail immediately
                throw error
            }
        }

        throw lastError ?? EnrichmentError.apiError("Max retries exceeded")
    }

    /// Determines if an error is retryable and calculates delay
    /// - Parameters:
    ///   - error: The EnrichmentError to evaluate
    ///   - config: Retry configuration for backoff calculation
    ///   - attempt: Current attempt number (0-indexed)
    /// - Returns: Tuple of (isRetryable, delayInSeconds)
    private func getRetryInfo(
        for error: EnrichmentError,
        config: RetryConfiguration,
        attempt: Int
    ) -> (retryable: Bool, delay: TimeInterval) {
        switch error {
        case .rateLimitExceeded(let retryAfter):
            // Use server-provided retry-after, capped at maxDelay
            let delay = min(TimeInterval(retryAfter), config.maxDelay)
            return (true, delay)

        case .circuitOpen(_, let retryAfterMs):
            // Use circuit breaker cooldown from server, capped at maxDelay
            let delay = min(TimeInterval(retryAfterMs) / 1000.0, config.maxDelay)
            return (true, delay)

        case .httpError(let statusCode) where statusCode >= 500:
            // Server errors are retryable with exponential backoff
            let delay = min(
                config.initialDelay * pow(config.backoffMultiplier, Double(attempt)),
                config.maxDelay
            )
            return (true, delay)

        default:
            // Not retryable - noMatchFound, apiError, invalidQuery, etc.
            return (false, 0)
        }
    }

    // MARK: - V2 Sync Enrichment API

    /// Enriches a book using the V2 sync API with automatic retry for retryable errors.
    /// - Parameters:
    ///   - barcode: The ISBN or barcode to enrich
    ///   - idempotencyKey: Optional stable key for retry safety. If nil, generates one based on barcode.
    ///   - preferProvider: Provider preference hint (default: "auto")
    ///   - retryConfig: Retry configuration (default: .default)
    /// - Returns: Enriched book data from the API
    /// - Throws: EnrichmentError for API-specific errors, URLError for network issues
    func enrichBookV2(
        barcode: String,
        idempotencyKey: String? = nil,
        preferProvider: String = "auto",
        retryConfig: RetryConfiguration = .default
    ) async throws -> EnrichedBookDTO {
        // Use provided idempotency key or generate a stable one based on barcode
        // This ensures retries use the same key, preserving idempotency semantics
        let key = idempotencyKey ?? "scan_\(barcode)"

        return try await retryWithBackoff(config: retryConfig) { [self] in
            try await self.performEnrichBookV2(
                barcode: barcode,
                idempotencyKey: key,
                preferProvider: preferProvider
            )
        }
    }

    /// Internal implementation of enrichBookV2 without retry wrapper
    /// - Parameters:
    ///   - barcode: The ISBN or barcode to enrich
    ///   - idempotencyKey: Stable key for retry safety
    ///   - preferProvider: Provider preference hint
    /// - Returns: Enriched book data from the API
    private func performEnrichBookV2(
        barcode: String,
        idempotencyKey: String,
        preferProvider: String
    ) async throws -> EnrichedBookDTO {
        let url = EnrichmentConfig.enrichBookURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.setValue("v3.3", forHTTPHeaderField: "X-API-Contract-Version")

        let payload = EnrichBookV2Request(barcode: barcode, preferProvider: preferProvider, idempotencyKey: idempotencyKey)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200:
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("📡 V2 Enrich Response: \(responseString.prefix(200))")
            }
            #endif

            // Decode ResponseEnvelope wrapper and extract book
            do {
                let book = try data.decodeEnvelope(EnrichedBookDTO.self)

                #if DEBUG
                print("✅ V2 Enriched '\(book.title)' from provider: \(book.provider ?? "unknown")")
                if let categories = book.categories, !categories.isEmpty {
                    print("  📚 Categories: \(categories.joined(separator: ", "))")
                }
                #endif

                return book

            } catch let error as ResponseEnvelopeError {
                // Map ResponseEnvelopeError to EnrichmentError
                switch error {
                case .apiError(_, let message, _):
                    #if DEBUG
                    print("🚨 V2 Enrich envelope error: \(message)")
                    #endif
                    throw EnrichmentError.apiError(message)
                case .missingData:
                    #if DEBUG
                    print("🚨 V2 Enrich response missing data field")
                    #endif
                    throw EnrichmentError.invalidResponse
                case .decodingFailed:
                    throw EnrichmentError.invalidResponse
                }
            }

        case 404:
            throw EnrichmentError.noMatchFound
        case 429:
            // Use conservative default of 5 seconds to prevent busy-wait loops
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfterSeconds = Int(retryAfter ?? "5") ?? 5
            throw EnrichmentError.rateLimitExceeded(retryAfter: retryAfterSeconds)
        case 503:
            // Service unavailable - parse structured error response
            do {
                // Try to decode ResponseEnvelope (should have error field)
                _ = try data.decodeEnvelope(EnrichedBookDTO.self)

                // Fallback if no error in envelope (unexpected for 503!)
                #if DEBUG
                print("⚠️ 503 response decoded successfully - unexpected backend response")
                #endif
                throw URLError(.badServerResponse)

            } catch let error as ResponseEnvelopeError {
                if case .apiError(let code, let message, let details) = error {
                    // Check for circuit breaker
                    if code == "CIRCUIT_OPEN" {
                        // Type-safe decoding of circuit breaker details
                        let (provider, retryAfterMs): (String, Int)
                        if let detailsDict = details,
                           let providerValue = detailsDict["provider"] as? String,
                           let retryValue = detailsDict["retryAfterMs"] as? Int {
                            provider = providerValue
                            retryAfterMs = retryValue
                        } else {
                            provider = "unknown"
                            retryAfterMs = 60000
                        }

                        #if DEBUG
                        print("⚠️ Circuit breaker open for provider '\(provider)', retry in \(retryAfterMs)ms: \(message)")
                        #endif

                        throw EnrichmentError.circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
                    }

                    // Handle other 503 errors with structured message
                    throw EnrichmentError.apiError(message)
                }

                // For other ResponseEnvelopeError types
                #if DEBUG
                print("⚠️ Failed to decode 503 error response: \(error)")
                #endif
                throw URLError(.badServerResponse)
            } catch {
                // Handle other errors (like EnrichmentError re-throws)
                if let enrichmentError = error as? EnrichmentError {
                    throw enrichmentError
                }
                #if DEBUG
                print("⚠️ Unexpected error during 503 handling: \(error)")
                #endif
                throw URLError(.badServerResponse)
            }
        default:
            #if DEBUG
            print("🚨 V2 Enrich unexpected HTTP \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif
            throw URLError(.badServerResponse)
        }
    }
}
