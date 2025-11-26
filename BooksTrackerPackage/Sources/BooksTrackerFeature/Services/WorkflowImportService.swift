import Foundation

// MARK: - Workflow Import Models

/// Request payload for creating a workflow import
public struct WorkflowImportRequest: Codable, Sendable {
    public let isbn: String
    public let source: WorkflowSource
    
    public init(isbn: String, source: WorkflowSource = .googleBooks) {
        self.isbn = isbn
        self.source = source
    }
}

/// Data source for workflow import
public enum WorkflowSource: String, Codable, Sendable {
    case googleBooks = "google_books"
    case isbndb = "isbndb"
    case openLibrary = "openlibrary"
}

/// Response from workflow creation endpoint
public struct WorkflowCreateResponse: Codable, Sendable {
    public let workflowId: String
    public let status: String
    public let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case workflowId = "workflowId"
        case status
        case createdAt = "created_at"
    }
}

/// Response from workflow status endpoint
public struct WorkflowStatusResponse: Codable, Sendable {
    public let workflowId: String
    public let status: WorkflowStatus
    public let currentStep: String?
    public let result: WorkflowResult?
    
    enum CodingKeys: String, CodingKey {
        case workflowId = "workflowId"
        case status
        case currentStep
        case result
    }
}

/// Workflow execution status
public enum WorkflowStatus: String, Codable, Sendable {
    case running
    case complete
    case failed
}

/// Result data from completed workflow
public struct WorkflowResult: Codable, Sendable {
    public let isbn: String
    public let title: String
    public let success: Bool
}

// MARK: - Workflow Import Errors

public enum WorkflowImportError: Error, LocalizedError {
    case invalidISBN
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case timeout
    case workflowFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidISBN:
            return "Invalid ISBN format (use 10 or 13 digits)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .timeout:
            return "Workflow timed out after 30 seconds"
        case .workflowFailed(let reason):
            return "Workflow failed: \(reason)"
        }
    }
}

// MARK: - Workflow Import Service

/// Service for importing books using Cloudflare Workflows API
///
/// The workflow API provides:
/// - Automatic retries with exponential backoff
/// - State persistence across worker restarts
/// - Step-by-step execution tracing
/// - No timeout limitations
///
/// ## Usage
///
/// ```swift
/// let service = WorkflowImportService()
/// let workflowId = try await service.createWorkflow(isbn: "9780747532743")
///
/// // Poll for status
/// while true {
///     let status = try await service.getWorkflowStatus(workflowId: workflowId)
///     if status.status == .complete {
///         break
///     }
///     try await Task.sleep(for: .milliseconds(500))
/// }
/// ```
public actor WorkflowImportService {
    
    // MARK: - Configuration
    
    private let baseURL = EnrichmentConfig.baseURL
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Create a new workflow import job
    ///
    /// - Parameters:
    ///   - isbn: ISBN-10 or ISBN-13 (digits only)
    ///   - source: Data source (defaults to Google Books)
    /// - Returns: Workflow ID for status polling
    /// - Throws: WorkflowImportError on failure
    public func createWorkflow(
        isbn: String,
        source: WorkflowSource = .googleBooks
    ) async throws -> String {
        // Validate ISBN format
        guard isbn.range(of: "^\\d{10,13}$", options: .regularExpression) != nil else {
            throw WorkflowImportError.invalidISBN
        }
        
        guard let url = URL(string: "\(baseURL)/v2/import/workflow") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.timeoutInterval = 10.0
        
        let payload = WorkflowImportRequest(isbn: isbn, source: source)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WorkflowImportError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowImportError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            let message = "Rate limit exceeded"
            throw WorkflowImportError.serverError(429, message)
        }
        
        // Success response should be 202 Accepted
        guard httpResponse.statusCode == 202 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WorkflowImportError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Try to decode with ResponseEnvelope wrapper first (canonical format)
        let decoder = JSONDecoder()
        
        if let envelope = try? decoder.decode(ResponseEnvelope<WorkflowCreateResponse>.self, from: data) {
            // Canonical ResponseEnvelope format
            if let error = envelope.error {
                throw WorkflowImportError.serverError(httpResponse.statusCode, error.message)
            }
            
            guard let result = envelope.data else {
                throw WorkflowImportError.invalidResponse
            }
            
            return result.workflowId
        } else {
            // Fallback: Try direct unwrapped response (backward compatibility)
            let result = try decoder.decode(WorkflowCreateResponse.self, from: data)
            return result.workflowId
        }
    }
    
    /// Get current status of a workflow
    ///
    /// - Parameter workflowId: Workflow ID from createWorkflow
    /// - Returns: Current workflow status and result (if complete)
    /// - Throws: WorkflowImportError on failure
    public func getWorkflowStatus(workflowId: String) async throws -> WorkflowStatusResponse {
        guard let url = URL(string: "\(baseURL)/v2/import/workflow/\(workflowId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WorkflowImportError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowImportError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WorkflowImportError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Try to decode with ResponseEnvelope wrapper first (canonical format)
        let decoder = JSONDecoder()
        
        if let envelope = try? decoder.decode(ResponseEnvelope<WorkflowStatusResponse>.self, from: data) {
            // Canonical ResponseEnvelope format
            if let error = envelope.error {
                throw WorkflowImportError.serverError(httpResponse.statusCode, error.message)
            }
            
            guard let status = envelope.data else {
                throw WorkflowImportError.invalidResponse
            }
            
            return status
        } else {
            // Fallback: Try direct unwrapped response (backward compatibility)
            let status = try decoder.decode(WorkflowStatusResponse.self, from: data)
            return status
        }
    }
    
    /// Poll workflow status until completion or timeout
    ///
    /// - Parameters:
    ///   - workflowId: Workflow ID from createWorkflow
    ///   - pollingInterval: Time between status checks (default: 500ms)
    ///   - timeout: Maximum time to wait (default: 30s)
    ///   - progressHandler: Optional callback for status updates
    /// - Returns: Final workflow status response
    /// - Throws: WorkflowImportError on failure or timeout
    public func pollUntilComplete(
        workflowId: String,
        pollingInterval: Duration = .milliseconds(500),
        timeout: Duration = .seconds(30),
        progressHandler: (@Sendable (WorkflowStatusResponse) async -> Void)? = nil
    ) async throws -> WorkflowStatusResponse {
        let startTime = ContinuousClock.now
        
        while true {
            // Check timeout
            let elapsed = startTime.duration(to: ContinuousClock.now)
            if elapsed >= timeout {
                throw WorkflowImportError.timeout
            }
            
            // Get current status
            let status = try await getWorkflowStatus(workflowId: workflowId)
            
            // Call progress handler if provided
            if let progressHandler = progressHandler {
                await progressHandler(status)
            }
            
            // Check if complete or failed
            switch status.status {
            case .complete:
                return status
            case .failed:
                let reason = status.currentStep ?? "Unknown step"
                throw WorkflowImportError.workflowFailed(reason)
            case .running:
                // Continue polling
                break
            }
            
            // Wait before next poll
            try await Task.sleep(for: pollingInterval)
        }
    }
}
