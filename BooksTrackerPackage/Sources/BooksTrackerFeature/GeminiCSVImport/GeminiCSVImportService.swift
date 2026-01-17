import Foundation
import OSLog

// ✅ V3 Migration Complete - CSV Import Service
// Backend V3 CSV endpoint: POST /v3/jobs/imports
// Request: multipart/form-data with CSV file
// Response: V3 JobResponse format with jobId and authToken
// Migrated from V2: POST /api/v2/imports → V3: POST /v3/jobs/imports
// See: V3_MIGRATION_SUMMARY.md for complete migration details

// MARK: - Gemini CSV Import Errors

enum GeminiCSVImportError: Error, LocalizedError {
    case fileTooLarge(Int)
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingFailed(Error)
    case parsingFailed(String)
    case missingToken

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            return "CSV file too large (\(size / 1024 / 1024)MB). Maximum size is 10MB."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .parsingFailed(let reason):
            return "CSV parsing failed: \(reason)"
        case .missingToken:
            return "Authentication token missing from server response"
        }
    }
}

// MARK: - Gemini CSV Import Response Models

public struct GeminiCSVImportResponse: Codable, Sendable {
    public let jobId: String
    public let authToken: String // Job-specific auth token for SSE stream

    private enum CodingKeys: String, CodingKey {
        case jobId
        case authToken = "token" // V3 API returns "token", not "authToken"
    }
}

/// V3 API response for GET /v3/jobs/imports/{jobId}/results
/// Structure: { success, data: { jobId, status, results: [...] } }
/// OpenAPI: results is array of objects (structure varies by job type)
public struct GeminiCSVImportResultsResponse: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let results: [CSVParsedBook]  // ✅ Direct array per OpenAPI spec
}

/// Legacy wrapper for backward compatibility with existing code
public struct GeminiCSVImportJob: Codable, Sendable {
    public let books: [CSVParsedBook]
    public let errors: [CSVImportError]
    public let successRate: String

    /// Initialize from V3 results response
    public init(from resultsResponse: GeminiCSVImportResultsResponse) {
        // With new OpenAPI-compliant structure, results is direct array
        self.books = resultsResponse.results

        // Extract errors from books that have enrichmentError
        self.errors = resultsResponse.results.compactMap { book in
            guard let errorMsg = book.enrichmentError else { return nil }
            return CSVImportError(title: book.title, error: errorMsg)
        }

        // Calculate success rate
        let totalBooks = resultsResponse.results.count
        let successfulBooks = resultsResponse.results.filter { $0.enrichmentError == nil }.count
        let success = totalBooks > 0 ? Double(successfulBooks) / Double(totalBooks) * 100 : 100
        self.successRate = "\(Int(success))%"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        books = try container.decodeIfPresent([CSVParsedBook].self, forKey: .books) ?? []
        errors = try container.decodeIfPresent([CSVImportError].self, forKey: .errors) ?? []
        successRate = try container.decodeIfPresent(String.self, forKey: .successRate) ?? "100%"
    }

    private enum CodingKeys: String, CodingKey {
        case books, errors, successRate
    }
}

/// Parsed book from V3 CSV import (distinct from legacy WebSocket ParsedBook)
public struct CSVParsedBook: Codable, Sendable, Equatable {
    public let title: String
    public let authors: [String]
    public let isbn: String?
    public let coverUrl: String?
    public let publisher: String?
    public let year: Int?
    public let pageCount: Int?
    public let language: String?
    public let enrichmentError: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)

        // Handle both "author" (singular string) and "authors" (array) from backend
        // Backend CSV processor sometimes sends "author: string" but iOS expects "authors: [String]"
        if let authorsArray = try? container.decode([String].self, forKey: .authors) {
            authors = authorsArray
        } else if let authorString = try? container.decode(String.self, forKey: .author) {
            authors = [authorString]
        } else {
            authors = []  // Default to empty if neither present
        }

        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        enrichmentError = try container.decodeIfPresent(String.self, forKey: .enrichmentError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(authors, forKey: .authors)  // Always encode as "authors" array
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(enrichmentError, forKey: .enrichmentError)
    }

    private enum CodingKeys: String, CodingKey {
        case title, authors, author, isbn, coverUrl, publisher, year, pageCount, language, enrichmentError
    }
}

/// Import error from V3 CSV import (distinct from legacy WebSocket ImportError)
public struct CSVImportError: Codable, Sendable, Equatable {
    public let title: String
    public let error: String
}

// MARK: - Job Status Response

public struct GeminiCSVImportJobStatus: Codable, Sendable {
    public let status: String  // "processing", "completed", "failed"
    public let progress: Double?
    public let message: String?
    public let books: [CSVParsedBook]?
    public let errors: [CSVImportError]?
    public let error: String?
}

// MARK: - Gemini CSV Import Service

/// Service for Gemini-powered CSV import with SSE progress tracking
/// Actor-isolated for thread-safe network operations
actor GeminiCSVImportService {
    // MARK: - Configuration

    private let maxFileSize: Int = 10_000_000 // 10MB max
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "Import")

    // MARK: - Singleton

    static let shared = GeminiCSVImportService()

    private init() {}

    // MARK: - Upload CSV

    /// Upload CSV file to V2 API and receive jobId + authToken for SSE tracking
    /// - Parameter csvText: Raw CSV content
    /// - Returns: Tuple of (jobId, authToken) for SSE stream connection
    /// - Throws: GeminiCSVImportError on failure
    func uploadCSV(csvText: String) async throws -> (jobId: String, authToken: String) {
        logger.info("CSV upload starting, size: \(csvText.utf8.count) bytes")

        // NOTE: CSV validation is handled by the backend (Gemini).
        // Client-side validation was removed to avoid false positives on valid CSVs
        // that the backend can handle (e.g., different quoting styles, BOM markers, etc.)

        // Validate file size
        let dataSize = csvText.utf8.count
        guard dataSize <= maxFileSize else {
            logger.error("CSV file too large: \(dataSize) bytes")
            throw GeminiCSVImportError.fileTooLarge(dataSize)
        }

        // V3 API: Use multipart/form-data (backend expects 'file' field)
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/imports")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minute timeout for large CSV files

        // Create multipart/form-data boundary
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        logger.debug("CSV upload request configured, endpoint: \(url, privacy: .private)")

        // Build multipart/form-data body
        var body = Data()

        // Add CSV file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvText.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Close multipart boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        #if DEBUG
        print("[CSV Upload] 📦 Multipart body size: \(body.count) bytes (CSV: \(csvText.utf8.count) bytes + headers)")
        print("[CSV Upload] 📦 CSV text first 100 bytes: \(String(csvText.prefix(100)))")
        #endif

        logger.debug("CSV multipart/form-data constructed, size: \(body.count) bytes")
        logger.debug("Sending CSV upload request to V3 API...")

        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            logger.info("CSV upload response received, status code: \(httpResponse.statusCode)")
            logger.debug("CSV response body size: \(data.count) bytes")
            if let bodyString = String(data: data, encoding: .utf8) {
                logger.debug("CSV response body preview: \(bodyString.prefix(500))")
            }

            // Accept both 200 (OK) and 202 (Accepted) for async job start
            if ![200, 202].contains(httpResponse.statusCode) {
                // Try to decode error response using new ResponseEnvelope format
                do {
                    _ = try data.decodeEnvelope(GeminiCSVImportResponse.self)
                    // If successful, we shouldn't be here (should have been 200/202)
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "Unexpected success response")
                } catch let error as ResponseEnvelopeError {
                    if case .apiError(let code, let message, _) = error {
                        let errorMessageWithCode = code != nil
                            ? "\(message) (Code: \(code!))"
                            : message
                        throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                    }
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode ResponseEnvelope and extract data
            do {
                let importResponse = try data.decodeEnvelope(GeminiCSVImportResponse.self)

                logger.info("CSV upload successful, jobId: \(importResponse.jobId, privacy: .private)")
                return (jobId: importResponse.jobId, authToken: importResponse.authToken)

            } catch let error as ResponseEnvelopeError {
                // Map ResponseEnvelopeError to GeminiCSVImportError
                switch error {
                case .apiError(let code, let message, _):
                    let errorMessageWithCode = code != nil
                        ? "\(message) (Code: \(code!))"
                        : message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                case .missingData:
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
                case .decodingFailed(let decodingError):
                    throw GeminiCSVImportError.decodingFailed(decodingError)
                }
            }

        } catch let error as GeminiCSVImportError {
            logger.error("CSV import error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("CSV upload network error: \(error.localizedDescription)")
            throw GeminiCSVImportError.networkError(error)
        }
    }

    /// Streams CSV import progress via SSE
    /// - Parameters:
    ///   - jobId: Import job ID from uploadCSV
    ///   - authToken: Auth token from uploadCSV
    /// - Returns: Tuple of (SSEClient, AsyncStream<EnrichmentEvent>) for progress events and cancellation
    func streamImportProgress(jobId: String, authToken: String) async -> (client: SSEClient, stream: AsyncStream<EnrichmentEvent>) {
        guard let sseURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/imports/\(jobId)/stream") else {
            // Return empty stream that finishes immediately if URL is malformed (unlikely but safe)
            return (client: SSEClient(url: URL(string: "https://invalid")!, authToken: ""), stream: AsyncStream { $0.finish() })
        }
        let sseClient = SSEClient(url: sseURL, authToken: authToken)
        let stream = await sseClient.connect()
        return (client: sseClient, stream: stream)
    }

    // MARK: - Fetch Results

    /// Fetch results from completed import job (V3 API)
    /// - Parameter jobId: The import job ID
    /// - Returns: Results summary with counts and errors
    /// - Throws: GeminiCSVImportError on failure
    func fetchResults(jobId: String) async throws -> GeminiCSVImportJob {
        logger.info("Fetching CSV import results for job: \(jobId, privacy: .private)")

        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/imports/\(jobId)/results")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            logger.debug("CSV results response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                // Try to decode error response
                do {
                    _ = try data.decodeEnvelope(GeminiCSVImportJob.self)
                    // If successful, shouldn't be here with non-200 status
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "Unexpected success response")
                } catch let error as ResponseEnvelopeError {
                    if case .apiError(let code, let message, _) = error {
                        let errorMessageWithCode = code != nil
                            ? "\(message) (Code: \(code!))"
                            : message
                        throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                    }
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // DEBUG: Log raw backend response for troubleshooting
            if let rawResponse = String(data: data, encoding: .utf8) {
                logger.debug("CSV backend response (first 1000 chars): \(rawResponse.prefix(1000))")
            }

            // Decode ResponseEnvelope with V3 results structure
            // V3 API: { success, data: { jobId, status, results: { books, ... } } }
            let results: GeminiCSVImportJob
            do {
                let resultsResponse = try data.decodeEnvelope(GeminiCSVImportResultsResponse.self)
                results = GeminiCSVImportJob(from: resultsResponse)
            } catch let error as ResponseEnvelopeError {
                // Map ResponseEnvelopeError to GeminiCSVImportError
                switch error {
                case .apiError(let code, let message, _):
                    let errorMessageWithCode = code != nil
                        ? "\(message) (Code: \(code!))"
                        : message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                case .missingData:
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
                case .decodingFailed(let decodingError):
                    throw GeminiCSVImportError.decodingFailed(decodingError)
                }
            }

            logger.info("CSV import results fetched: \(results.books.count) books, \(results.errors.count) errors")
            logger.debug("CSV detailed book data (first 10):")
            for (index, book) in results.books.prefix(10).enumerated() {
                logger.debug("  Book \(index + 1): \(book.title, privacy: .private), authors: \(book.authors), isbn: \(book.isbn ?? "none", privacy: .private), publisher: \(book.publisher ?? "none", privacy: .private), year: \(book.year?.description ?? "none"), enrichmentError: \(book.enrichmentError ?? "none")")
            }
            if results.books.count > 10 {
                logger.debug("CSV import: ... and \(results.books.count - 10) more books")
            }
            return results

        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            logger.error("CSV results network error: \(error.localizedDescription)")
            throw GeminiCSVImportError.networkError(error)
        }
    }

    // MARK: - Check Job Status

    /// Check the status of a CSV import job (fallback polling)
    /// - Parameter jobId: The job ID to check
    /// - Returns: Job status including progress and results
    /// - Throws: GeminiCSVImportError on failure
    func checkJobStatus(jobId: String) async throws -> GeminiCSVImportJobStatus {
        logger.info("Checking CSV import job status: \(jobId, privacy: .private)")

        let statusURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/imports/\(jobId)")!
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            logger.debug("CSV job status response code: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                // Try to decode error response
                do {
                    _ = try data.decodeEnvelope(GeminiCSVImportJobStatus.self)
                    // If successful, shouldn't be here with non-200 status
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "Unexpected success response")
                } catch let error as ResponseEnvelopeError {
                    if case .apiError(let code, let message, _) = error {
                        let errorMessageWithCode = code != nil
                            ? "\(message) (Code: \(code!))"
                            : message
                        throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                    }
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode ResponseEnvelope and extract data
            let jobStatus: GeminiCSVImportJobStatus
            do {
                jobStatus = try data.decodeEnvelope(GeminiCSVImportJobStatus.self)
            } catch let error as ResponseEnvelopeError {
                // Map ResponseEnvelopeError to GeminiCSVImportError
                switch error {
                case .apiError(let code, let message, _):
                    let errorMessageWithCode = code != nil
                        ? "\(message) (Code: \(code!))"
                        : message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                case .missingData:
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
                case .decodingFailed(let decodingError):
                    throw GeminiCSVImportError.decodingFailed(decodingError)
                }
            }

            logger.info("CSV import job status: \(jobStatus.status)")
            return jobStatus

        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            logger.error("CSV job status network error: \(error.localizedDescription)")
            throw GeminiCSVImportError.networkError(error)
        }
    }

    // MARK: - Cancel Job

    /// Cancel a running CSV import job
    /// - Parameter jobId: The job ID to cancel
    /// - Throws: GeminiCSVImportError on failure
    func cancelJob(jobId: String) async throws {
        logger.info("Canceling CSV import job: \(jobId, privacy: .private)")

        let cancelURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/imports/\(jobId)")!
        var request = URLRequest(url: cancelURL)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            // Accept 200 (OK), 202 (Accepted), or 404 (already completed/not found)
            if ![200, 202, 404].contains(httpResponse.statusCode) {
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, "Failed to cancel job")
            }

            logger.info("CSV import job canceled successfully")
        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            logger.error("CSV cancel job network error: \(error.localizedDescription)")
            throw GeminiCSVImportError.networkError(error)
        }
    }
}