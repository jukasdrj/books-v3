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
    // V2 Migration: No auth token needed - SSE is public streaming endpoint
}

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

// MARK: - Gemini CSV Import Service

/// Service for Gemini-powered CSV import with SSE progress tracking
/// Actor-isolated for thread-safe network operations
actor GeminiCSVImportService {
    // MARK: - Configuration

    private let endpoint = EnrichmentConfig.csvImportURL
    private let maxFileSize: Int = 10_000_000 // 10MB max

    // MARK: - Singleton

    static let shared = GeminiCSVImportService()

    private init() {}

    // MARK: - Upload CSV

    /// Upload CSV file to V2 API and receive jobId for SSE tracking
    /// - Parameter csvText: Raw CSV content
    /// - Returns: jobId for SSE stream connection
    /// - Throws: GeminiCSVImportError on failure
    func uploadCSV(csvText: String) async throws -> String {
        #if DEBUG
        print("[CSV Upload] Starting upload, size: \(csvText.utf8.count) bytes")
        #endif

        // Validate CSV format (fail fast before network call)
        do {
            try await MainActor.run {
                try CSVValidator.validate(csvText: csvText, featureFlags: FeatureFlags.shared)
            }
            #if DEBUG
            print("[CSV Upload] ✅ CSV validation passed")
            #endif
        } catch let validationError as CSVValidationError {
            #if DEBUG
            print("[CSV Upload] ❌ CSV validation failed: \(validationError.localizedDescription)")
            #endif
            throw GeminiCSVImportError.parsingFailed(validationError.localizedDescription)
        }

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
                if let errorResponse = try? JSONDecoder().decode(ResponseEnvelope<GeminiCSVImportResponse>.self, from: data),
                   let error = errorResponse.error {
                    let errorMessageWithCode = error.code != nil
                        ? "\(error.message) (Code: \(error.code!))"
                        : error.message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode new ResponseEnvelope<GeminiCSVImportResponse> format
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(ResponseEnvelope<GeminiCSVImportResponse>.self, from: data)

            // Check for errors in response
            if let error = envelope.error {
                let errorMessageWithCode = error.code != nil
                    ? "\(error.message) (Code: \(error.code!))"
                    : error.message
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
            }
            
            // Extract data
            guard let importResponse = envelope.data else {
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
            }
            
            #if DEBUG
            print("[CSV Upload] ✅ Got jobId: \(importResponse.jobId)")
            #endif
            return importResponse.jobId

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

    // MARK: - Fetch Results

    /// Fetch results from completed import job (V2 API)
    /// - Parameter jobId: The import job ID
    /// - Returns: Results summary with counts and errors
    /// - Throws: GeminiCSVImportError on failure
    func fetchResults(jobId: String) async throws -> SSEResultsResponse {
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
                if let errorResponse = try? JSONDecoder().decode(ResponseEnvelope<SSEResultsResponse>.self, from: data),
                   let error = errorResponse.error {
                    let errorMessageWithCode = error.code != nil
                        ? "\(error.message) (Code: \(error.code!))"
                        : error.message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode response
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(ResponseEnvelope<SSEResultsResponse>.self, from: data)

            // Check for errors in response
            if let error = envelope.error {
                let errorMessageWithCode = error.code != nil
                    ? "\(error.message) (Code: \(error.code!))"
                    : error.message
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
            }

            // Extract data
            guard let results = envelope.data else {
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
            }

            #if DEBUG
            print("[CSV Results] ✅ Results fetched: \(results.results?.count ?? 0) books")
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

        let statusURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/csv/status/\(jobId)")!
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
                if let errorResponse = try? JSONDecoder().decode(ResponseEnvelope<GeminiCSVImportJobStatus>.self, from: data),
                   let error = errorResponse.error {
                    let errorMessageWithCode = error.code != nil
                        ? "\(error.message) (Code: \(error.code!))"
                        : error.message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode response
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(ResponseEnvelope<GeminiCSVImportJobStatus>.self, from: data)

            // Check for errors in response
            if let error = envelope.error {
                let errorMessageWithCode = error.code != nil
                    ? "\(error.message) (Code: \(error.code!))"
                    : error.message
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
            }

            // Extract data
            guard let jobStatus = envelope.data else {
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, "No data in response")
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
}