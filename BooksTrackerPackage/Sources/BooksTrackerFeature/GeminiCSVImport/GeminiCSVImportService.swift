import Foundation

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
}

public struct GeminiCSVImportJob: Codable, Sendable {
    public let books: [ParsedBook]
    public let errors: [ImportError]
    public let successRate: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        books = try container.decodeIfPresent([ParsedBook].self, forKey: .books) ?? []
        errors = try container.decodeIfPresent([ImportError].self, forKey: .errors) ?? []
        successRate = try container.decodeIfPresent(String.self, forKey: .successRate) ?? "100%"
    }

    private enum CodingKeys: String, CodingKey {
        case books, errors, successRate
    }

    public struct ParsedBook: Codable, Sendable, Equatable {
        public let title: String
        public let authors: [String]
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let year: Int?
        public let pageCount: Int?
        public let enrichmentError: String?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
            isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
            coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
            publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
            year = try container.decodeIfPresent(Int.self, forKey: .year)
            pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
            enrichmentError = try container.decodeIfPresent(String.self, forKey: .enrichmentError)
        }

        private enum CodingKeys: String, CodingKey {
            case title, authors, isbn, coverUrl, publisher, year, pageCount, enrichmentError
        }
    }

    public struct ImportError: Codable, Sendable, Equatable {
        public let title: String
        public let error: String
    }
}

// MARK: - Job Status Response

public struct GeminiCSVImportJobStatus: Codable, Sendable {
    public let status: String  // "processing", "completed", "failed"
    public let progress: Double?
    public let message: String?
    public let books: [GeminiCSVImportJob.ParsedBook]?
    public let errors: [GeminiCSVImportJob.ImportError]?
    public let error: String?
}

// MARK: - Gemini CSV Import Service

/// Service for Gemini-powered CSV import with SSE progress tracking
/// Actor-isolated for thread-safe network operations
actor GeminiCSVImportService {
    // MARK: - Configuration

    private let maxFileSize: Int = 10_000_000 // 10MB max

    // MARK: - Singleton

    static let shared = GeminiCSVImportService()

    private init() {}

    // MARK: - Upload CSV

    /// Upload CSV file to V2 API and receive jobId + authToken for SSE tracking
    /// - Parameter csvText: Raw CSV content
    /// - Returns: Tuple of (jobId, authToken) for SSE stream connection
    /// - Throws: GeminiCSVImportError on failure
    func uploadCSV(csvText: String) async throws -> (jobId: String, authToken: String) {
        #if DEBUG
        print("[CSV Upload] Starting upload, size: \(csvText.utf8.count) bytes")
        #endif

        // NOTE: CSV validation is handled by the backend (Gemini).
        // Client-side validation was removed to avoid false positives on valid CSVs
        // that the backend can handle (e.g., different quoting styles, BOM markers, etc.)

        // Validate file size
        let dataSize = csvText.utf8.count
        guard dataSize <= maxFileSize else {
            #if DEBUG
            print("[CSV Upload] ❌ File too large: \(dataSize) bytes")
            #endif
            throw GeminiCSVImportError.fileTooLarge(dataSize)
        }

        // V2 API: Use multipart/form-data (backend expects 'file' field)
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/imports")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minute timeout for large CSV files

        // Create multipart/form-data boundary
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        #if DEBUG
        print("[CSV Upload] Request configured, endpoint: \(url)")
        #endif

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
        print("[CSV Upload] Multipart/form-data constructed, size: \(body.count) bytes")
        print("[CSV Upload] Sending request to V2 API...")
        #endif

        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }
            
            #if DEBUG
            print("[CSV Upload] ✅ Received response from backend")
            print("[CSV Upload] Status code: \(httpResponse.statusCode)")
            print("[CSV Upload] Response headers: \(httpResponse.allHeaderFields)")
            print("[CSV Upload] Response body size: \(data.count) bytes")
            if let bodyString = String(data: data, encoding: .utf8) {
                print("[CSV Upload] Response body preview: \(bodyString.prefix(500))")
            }
            #endif

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

                #if DEBUG
                print("[CSV Upload] ✅ Got jobId: \(importResponse.jobId), authToken: <redacted>")
                #endif
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
            #if DEBUG
            print("[CSV Upload] ❌ CSV Import Error: \(error.localizedDescription)")
            #endif
            throw error
        } catch {
            #if DEBUG
            print("[CSV Upload] ❌ Network Error: \(error.localizedDescription)")
            #endif
            throw GeminiCSVImportError.networkError(error)
        }
    }

    /// Streams CSV import progress via SSE
    /// - Parameters:
    ///   - jobId: Import job ID from uploadCSV
    ///   - authToken: Auth token from uploadCSV
    /// - Returns: Tuple of (SSEClient, AsyncStream<EnrichmentEvent>) for progress events and cancellation
    func streamImportProgress(jobId: String, authToken: String) async -> (client: SSEClient, stream: AsyncStream<EnrichmentEvent>) {
        guard let sseURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/imports/\(jobId)/stream") else {
            // Return empty stream that finishes immediately if URL is malformed (unlikely but safe)
            return (client: SSEClient(url: URL(string: "https://invalid")!, authToken: ""), stream: AsyncStream { $0.finish() })
        }
        let sseClient = SSEClient(url: sseURL, authToken: authToken)
        let stream = await sseClient.connect()
        return (client: sseClient, stream: stream)
    }

    // MARK: - Fetch Results

    /// Fetch results from completed import job (V2 API)
    /// - Parameter jobId: The import job ID
    /// - Returns: Results summary with counts and errors
    /// - Throws: GeminiCSVImportError on failure
    func fetchResults(jobId: String) async throws -> GeminiCSVImportJob {
        #if DEBUG
        print("[CSV Results] Fetching results for job: \(jobId)")
        #endif

        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/imports/\(jobId)/results")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            #if DEBUG
            print("[CSV Results] Status code: \(httpResponse.statusCode)")
            #endif

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

            #if DEBUG
            // 🔍 DEBUG: Print raw backend response to see what's actually being returned
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("[CSV Results] 📡 RAW BACKEND RESPONSE (first 1000 chars):")
                print(rawResponse.prefix(1000))
            }
            #endif

            // Decode ResponseEnvelope and extract data
            let results: GeminiCSVImportJob
            do {
                results = try data.decodeEnvelope(GeminiCSVImportJob.self)
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

            #if DEBUG
            print("[CSV Results] ✅ Results fetched: \(results.books.count) books, \(results.errors.count) errors")
            print("[CSV Results] ===== DETAILED BOOK DATA (showing first 10) =====")
            for (index, book) in results.books.prefix(10).enumerated() {
                print("[CSV Results] Book \(index + 1):")
                print("  Title: \(book.title)")
                print("  Authors: \(book.authors)")  // 🔑 KEY CHECK
                print("  ISBN: \(book.isbn ?? "none")")
                print("  Publisher: \(book.publisher ?? "none")")
                print("  Year: \(book.year?.description ?? "none")")
                print("  Cover: \(book.coverUrl ?? "none")")
                print("  Enrichment Error: \(book.enrichmentError ?? "none")")
            }
            if results.books.count > 10 {
                print("[CSV Results] ... and \(results.books.count - 10) more books")
            }
            print("[CSV Results] ===============================")
            #endif
            return results

        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            #if DEBUG
            print("[CSV Results] ❌ Network Error: \(error.localizedDescription)")
            #endif
            throw GeminiCSVImportError.networkError(error)
        }
    }

    // MARK: - Check Job Status

    /// Check the status of a CSV import job (fallback polling)
    /// - Parameter jobId: The job ID to check
    /// - Returns: Job status including progress and results
    /// - Throws: GeminiCSVImportError on failure
    func checkJobStatus(jobId: String) async throws -> GeminiCSVImportJobStatus {
        #if DEBUG
        print("[CSV Status] Checking status for job: \(jobId)")
        #endif

        let statusURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/imports/\(jobId)")!
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            #if DEBUG
            print("[CSV Status] Status code: \(httpResponse.statusCode)")
            #endif

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

            #if DEBUG
            print("[CSV Status] ✅ Status: \(jobStatus.status)")
            #endif
            return jobStatus

        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            #if DEBUG
            print("[CSV Status] ❌ Network Error: \(error.localizedDescription)")
            #endif
            throw GeminiCSVImportError.networkError(error)
        }
    }

    // MARK: - Cancel Job

    /// Cancel a running CSV import job
    /// - Parameter jobId: The job ID to cancel
    /// - Throws: GeminiCSVImportError on failure
    func cancelJob(jobId: String) async throws {
        #if DEBUG
        print("[CSV Cancel] Canceling job: \(jobId)")
        #endif

        let cancelURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/jobs/\(jobId)/cancel")!
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
            
            #if DEBUG
            print("[CSV Cancel] ✅ Job canceled successfully")
            #endif
        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            #if DEBUG
            print("[CSV Cancel] ❌ Network Error: \(error.localizedDescription)")
            #endif
            throw GeminiCSVImportError.networkError(error)
        }
    }
}