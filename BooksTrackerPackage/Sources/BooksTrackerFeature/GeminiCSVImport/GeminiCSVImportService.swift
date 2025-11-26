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

// MARK: - V1 Gemini CSV Import Response Models

public struct GeminiCSVImportResponse: Codable, Sendable {
    public let jobId: String
    public let token: String
}

// MARK: - V2 CSV Import Response Models

public struct CSVImportV2Response: Codable, Sendable {
    let jobId: String
    let status: String
    let createdAt: String
    let sseUrl: String
    let statusUrl: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case createdAt = "created_at"
        case sseUrl = "sse_url"
        case statusUrl = "status_url"
    }
}

/// Represents the possible outcomes of the initial CSV upload API call.
public enum CSVUploadResult {
    /// V1 result with a job ID and a WebSocket token.
    case v1(jobId: String, token: String)
    /// V2 result with the full job creation response.
    case v2(response: CSVImportV2Response)
}

// MARK: - Job Models

public struct GeminiCSVImportJob: Codable, Sendable {
    public let books: [ParsedBook]
    public let errors: [ImportError]
    public let successRate: String

    public struct ParsedBook: Codable, Sendable, Equatable {
        public let title: String
        public let author: String
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?
        public let enrichmentError: String?
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

public struct CSVImportV2JobStatus: Codable, Sendable {
    let jobId: String
    let status: String
    let progress: Double
    let totalRows: Int
    let processedRows: Int
    let successfulRows: Int
    let failedRows: Int
    let createdAt: String
    let startedAt: String?
    let completedAt: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, progress
        case totalRows = "total_rows"
        case processedRows = "processed_rows"
        case successfulRows = "successful_rows"
        case failedRows = "failed_rows"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case error
    }
}

// MARK: - V2 SSE Event Data Models & Progress Enum

public struct ResultSummary: Codable, Sendable, Equatable {
    let booksCreated: Int
    let booksUpdated: Int
    let duplicatesSkipped: Int
    let enrichmentSucceeded: Int
    let enrichmentFailed: Int
    let errors: [ImportErrorDetail]

    enum CodingKeys: String, CodingKey {
        case booksCreated = "books_created"
        case booksUpdated = "books_updated"
        case duplicatesSkipped = "duplicates_skipped"
        case enrichmentSucceeded = "enrichment_succeeded"
        case enrichmentFailed = "enrichment_failed"
        case errors
    }
}

public struct ImportErrorDetail: Codable, Sendable, Equatable {
    let row: Int
    let isbn: String?
    let error: String
}


struct SSEStartedEvent: Codable, Sendable {
    let status: String
    let totalRows: Int

    enum CodingKeys: String, CodingKey {
        case status
        case totalRows = "total_rows"
    }
}

struct SSEProgressEvent: Codable, Sendable {
    let progress: Double
    let processedRows: Int

    enum CodingKeys: String, CodingKey {
        case progress
        case processedRows = "processed_rows"
    }
}

struct SSECompleteEvent: Codable, Sendable {
    let status: String
    let resultSummary: ResultSummary

    enum CodingKeys: String, CodingKey {
        case status
        case resultSummary = "result_summary"
    }
}

struct SSEErrorEvent: Codable, Sendable {
    let status: String
    let error: String
    let processedRows: Int

    enum CodingKeys: String, CodingKey {
        case status
        case error
        case processedRows = "processed_rows"
    }
}


/// Represents the progress of a V2 CSV import, combining data from SSE events and polling.
public enum CSVImportProgress: Sendable {
    case started(totalRows: Int)
    case progress(processedRows: Int, totalRows: Int, progress: Double)
    case complete(summary: ResultSummary)
    case failed(error: String)
}


// MARK: - Gemini CSV Import Service

/// Service for Gemini-powered CSV import with WebSocket progress tracking
/// Actor-isolated for thread-safe network operations
actor GeminiCSVImportService {
    // MARK: - Configuration

    private let maxFileSize: Int = 10_000_000 // 10MB max

    // MARK: - Singleton

    static let shared = GeminiCSVImportService()

    private init() {}

    // MARK: - Upload CSV

    /// Upload CSV file and receive job details for progress tracking.
    /// - Parameter csvText: Raw CSV content
    /// - Returns: A `CSVUploadResult` containing either V1 (jobId, token) or V2 (full response) details.
    /// - Throws: GeminiCSVImportError on failure
    func uploadCSV(csvText: String) async throws -> CSVUploadResult {
        if FeatureFlags.shared.useV2CSVImport {
            return try await uploadCSVV2(csvText: csvText)
        } else {
            return try await uploadCSVV1(csvText: csvText)
        }
    }

    private func uploadCSVV1(csvText: String) async throws -> CSVUploadResult {
        let response = try await uploadV1(csvText: csvText)
        return .v1(jobId: response.jobId, token: response.token)
    }

    private func uploadCSVV2(csvText: String) async throws -> CSVUploadResult {
        let response = try await uploadV2(csvText: csvText)
        return .v2(response: response)
    }

    private func uploadV1(csvText: String) async throws -> GeminiCSVImportResponse {
        let endpoint = EnrichmentConfig.csvImportURL
        let request = try createUploadRequest(csvText: csvText, endpoint: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, [200, 202].contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500, errorMessage)
            }
            let envelope = try JSONDecoder().decode(ResponseEnvelope<GeminiCSVImportResponse>.self, from: data)
            guard let importResponse = envelope.data else { throw GeminiCSVImportError.invalidResponse }
            return importResponse
        } catch {
            throw GeminiCSVImportError.networkError(error)
        }
    }

    private func uploadV2(csvText: String) async throws -> CSVImportV2Response {
        let endpoint = EnrichmentConfig.csvImportV2URL
        let request = try createUploadRequest(csvText: csvText, endpoint: endpoint)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 202 else {
                 let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500, errorMessage)
            }
            return try JSONDecoder().decode(CSVImportV2Response.self, from: data)
        } catch {
            throw GeminiCSVImportError.networkError(error)
        }
    }

    private func createUploadRequest(csvText: String, endpoint: URL) throws -> URLRequest {
        do {
            try CSVValidator.validate(csvText: csvText)
        } catch let validationError as CSVValidationError {
            throw GeminiCSVImportError.parsingFailed(validationError.localizedDescription)
        }

        let dataSize = csvText.utf8.count
        guard dataSize <= maxFileSize else {
            throw GeminiCSVImportError.fileTooLarge(dataSize)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvText.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }

    // MARK: - Check Job Status

    /// Check the status of a CSV import job (fallback polling for V1)
    /// - Parameter jobId: The job ID to check
    /// - Returns: Job status including progress and results
    /// - Throws: GeminiCSVImportError on failure
    @available(*, deprecated, message: "Use checkV2JobStatus for V2 jobs")
    func checkJobStatus(jobId: String) async throws -> GeminiCSVImportJobStatus {
        return try await pollV1Status(jobId: jobId)
    }

    /// Checks the status of a V2 CSV import job.
    func checkV2JobStatus(jobId: String) async throws -> CSVImportV2JobStatus {
        return try await pollV2Status(jobId: jobId)
    }

    private func pollV1Status(jobId: String) async throws -> GeminiCSVImportJobStatus {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/csv/status/\(jobId)")!
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GeminiCSVImportError.invalidResponse
            }
            let envelope = try JSONDecoder().decode(ResponseEnvelope<GeminiCSVImportJobStatus>.self, from: data)
            guard let status = envelope.data else { throw GeminiCSVImportError.invalidResponse }
            return status
        } catch {
            throw GeminiCSVImportError.networkError(error)
        }
    }

    private func pollV2Status(jobId: String) async throws -> CSVImportV2JobStatus {
        let url = EnrichmentConfig.csvImportV2StatusURL(jobId: jobId)
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GeminiCSVImportError.invalidResponse
            }
            return try JSONDecoder().decode(CSVImportV2JobStatus.self, from: data)
        } catch {
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

        let cancelURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/csv/cancel/\(jobId)")!
        var request = URLRequest(url: cancelURL)
        request.httpMethod = "POST"
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

    // MARK: - V2 SSE Progress Streaming

    func streamV2JobProgress(jobId: String) -> AsyncThrowingStream<CSVImportProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastEventID: String?
                var totalRows: Int?

                for attempt in 1...3 {
                    do {
                        let stream = try await connectToSSE(jobId: jobId, lastEventID: lastEventID)
                        for try await event in stream {
                            lastEventID = event.id

                            guard let eventName = event.event, let dataString = event.data, let data = dataString.data(using: .utf8) else {
                                continue
                            }

                            let decoder = JSONDecoder()

                            switch eventName {
                            case "started":
                                let startedEvent = try decoder.decode(SSEStartedEvent.self, from: data)
                                totalRows = startedEvent.totalRows
                                continuation.yield(.started(totalRows: startedEvent.totalRows))
                            case "progress":
                                if let total = totalRows {
                                    let progressEvent = try decoder.decode(SSEProgressEvent.self, from: data)
                                    continuation.yield(.progress(processedRows: progressEvent.processedRows, totalRows: total, progress: progressEvent.progress))
                                }
                            case "complete":
                                let completeEvent = try decoder.decode(SSECompleteEvent.self, from: data)
                                continuation.yield(.complete(summary: completeEvent.resultSummary))
                                continuation.finish()
                                return
                            case "error":
                                let errorEvent = try decoder.decode(SSEErrorEvent.self, from: data)
                                continuation.yield(.failed(error: errorEvent.error))
                                continuation.finish()
                                return
                            default:
                                break
                            }
                        }
                    } catch {
                        if attempt == 3 {
                            continuation.finish(throwing: error)
                        } else {
                            try await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000)) // 2 seconds
                        }
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func connectToSSE(jobId: String, lastEventID: String?) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let url = EnrichmentConfig.csvImportV2StreamURL(jobId: jobId)
        let request = URLRequest(url: url)

        let client = SSEClient(urlRequest: request, lastEventID: lastEventID)
        return client.connect()
    }
}