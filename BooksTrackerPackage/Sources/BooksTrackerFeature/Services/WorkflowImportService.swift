import Foundation
import OSLog

public actor WorkflowImportService {
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "WorkflowImportService")

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    public func createWorkflow(isbn: String, source: String = "google_books") async throws -> WorkflowCreateResponse {
        guard let url = URL(string: "\(EnrichmentConfig.baseURL)/v2/import/workflow") else {
            throw WorkflowError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["isbn": isbn, "source": source]
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 202 else {
            throw WorkflowError.creationFailed
        }

        do {
            return try JSONDecoder().decode(WorkflowCreateResponse.self, from: data)
        } catch {
            throw WorkflowError.decodingFailed
        }
    }

    public func getWorkflowStatus(workflowId: String) async throws -> WorkflowStatusResponse {
        guard let url = URL(string: "\(EnrichmentConfig.baseURL)/v2/import/workflow/\(workflowId)") else {
            throw WorkflowError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WorkflowError.statusCheckFailed
        }

        do {
            return try JSONDecoder().decode(WorkflowStatusResponse.self, from: data)
        } catch {
            throw WorkflowError.decodingFailed
        }
    }
}

public enum WorkflowError: Error {
    case invalidURL
    case creationFailed
    case statusCheckFailed
    case decodingFailed
}
