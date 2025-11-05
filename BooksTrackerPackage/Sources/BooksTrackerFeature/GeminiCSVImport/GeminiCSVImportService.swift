import Foundation

// MARK: - Gemini CSV Import Errors

enum GeminiCSVImportError: Error, LocalizedError {
    case fileTooLarge(Int)
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingFailed(Error)
    case parsingFailed(String)

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
        }
    }
}

// MARK: - Gemini CSV Import Response Models

public struct GeminiCSVImportResponse: Codable, Sendable {
    public let jobId: String
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

// MARK: - Gemini CSV Import Service

/// Service for Gemini-powered CSV import with WebSocket progress tracking
/// Actor-isolated for thread-safe network operations
actor GeminiCSVImportService {
    // MARK: - Configuration

    private let endpoint = URL(string: "https://api-worker.jukasdrj.workers.dev/api/import/csv-gemini")!
    private let maxFileSize: Int = 10_000_000 // 10MB max

    // MARK: - Singleton

    static let shared = GeminiCSVImportService()

    private init() {}

    // MARK: - Upload CSV

    /// Upload CSV file and receive jobId for WebSocket tracking
    /// - Parameter csvText: Raw CSV content
    /// - Returns: JobId for progress tracking
    /// - Throws: GeminiCSVImportError on failure
    func uploadCSV(csvText: String) async throws -> String {
        // Validate file size
        let dataSize = csvText.utf8.count
        guard dataSize <= maxFileSize else {
            throw GeminiCSVImportError.fileTooLarge(dataSize)
        }

        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add CSV file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvText.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiCSVImportError.invalidResponse
            }

            // Accept both 200 (OK) and 202 (Accepted) for async job start
            if ![200, 202].contains(httpResponse.statusCode) {
                // Try to decode error response to extract error code
                if let errorResponse = try? JSONDecoder().decode(ApiResponse<GeminiCSVImportResponse>.self, from: data),
                   case .failure(let apiError, _) = errorResponse {
                    let errorMessageWithCode = apiError.code != nil
                        ? "\(apiError.message) (Code: \(apiError.code!.rawValue))"
                        : apiError.message
                    throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessageWithCode)
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode ResponseEnvelope<GeminiCSVImportResponse>
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(ResponseEnvelope<GeminiCSVImportResponse>.self, from: data)

            // Check for errors
            if let error = envelope.error {
                throw GeminiCSVImportError.serverError(httpResponse.statusCode, error.message)
            }

            // Unwrap data
            guard let importResponse = envelope.data else {
                throw GeminiCSVImportError.invalidResponse
            }

            return importResponse.jobId

        } catch let error as GeminiCSVImportError {
            throw error
        } catch {
            throw GeminiCSVImportError.networkError(error)
        }
    }
}
