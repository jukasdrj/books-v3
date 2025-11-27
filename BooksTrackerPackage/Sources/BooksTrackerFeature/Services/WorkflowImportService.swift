import Foundation
import OSLog

/// Service for managing Cloudflare Workflow-based book imports
///
/// This service provides durable, step-by-step book import with automatic retries
/// and state persistence via the Cloudflare Workflows API.
///
/// Benefits over traditional import:
/// - Automatic retries (3x with backoff)
/// - State persistence across failures
/// - Step-by-step observability
/// - No timeout for long-running imports
public actor WorkflowImportService {
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "WorkflowImportService")

    /// Polling interval for workflow status checks
    private let pollingInterval: Duration = .milliseconds(500)

    /// Maximum time to wait for workflow completion
    private let timeout: Duration = .seconds(30)

    /// Initialize with configurable URLSession for testing
    /// - Parameter urlSession: URLSession to use for requests (default: configured session)
    public init(urlSession: URLSession? = nil) {
        if let session = urlSession {
            self.urlSession = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            self.urlSession = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// Create a new import workflow for the given ISBN
    /// - Parameters:
    ///   - isbn: The ISBN to import
    ///   - source: The source to use for metadata (default: google_books)
    /// - Returns: The workflow creation response
    /// - Throws: WorkflowError if creation fails
    public func createWorkflow(isbn: String, source: String = "google_books") async throws -> WorkflowCreateResponse {
        let url = EnrichmentConfig.workflowCreateURL
        logger.info("Creating workflow for ISBN: \(isbn)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = WorkflowCreateRequest(isbn: isbn, source: source)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowError.invalidResponse
        }

        guard httpResponse.statusCode == 202 else {
            logger.error("Workflow creation failed with status: \(httpResponse.statusCode)")
            throw WorkflowError.creationFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let createResponse = try JSONDecoder().decode(WorkflowCreateResponse.self, from: data)
            logger.info("Workflow created: \(createResponse.workflowId)")
            return createResponse
        } catch {
            logger.error("Failed to decode workflow response: \(error.localizedDescription)")
            throw WorkflowError.decodingError(error)
        }
    }

    /// Get the current status of a workflow
    /// - Parameter workflowId: The workflow ID to check
    /// - Returns: The workflow status response
    /// - Throws: WorkflowError if status check fails
    public func getWorkflowStatus(workflowId: String) async throws -> WorkflowStatusResponse {
        let url = EnrichmentConfig.workflowStatusURL(workflowId: workflowId)

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("Workflow status check failed with status: \(httpResponse.statusCode)")
            throw WorkflowError.statusCheckFailed(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(WorkflowStatusResponse.self, from: data)
        } catch {
            logger.error("Failed to decode status response: \(error.localizedDescription)")
            throw WorkflowError.decodingError(error)
        }
    }

    /// Poll workflow until completion or timeout
    /// - Parameters:
    ///   - workflowId: The workflow ID to monitor
    ///   - onProgress: Callback for progress updates (currentStep)
    /// - Returns: The final workflow result
    /// - Throws: WorkflowError if workflow fails or times out
    public func pollUntilComplete(
        workflowId: String,
        onProgress: @escaping @Sendable (WorkflowStep?) async -> Void
    ) async throws -> WorkflowResult {
        let startTime = ContinuousClock.now
        var lastStep: String?

        while true {
            // Check timeout
            if ContinuousClock.now - startTime > timeout {
                logger.error("Workflow timed out after \(self.timeout)")
                throw WorkflowError.timeout
            }

            let statusResponse = try await getWorkflowStatus(workflowId: workflowId)

            // Report progress if step changed
            if statusResponse.currentStep != lastStep {
                lastStep = statusResponse.currentStep
                let step = statusResponse.currentStep.flatMap { WorkflowStep(rawValue: $0) }
                await onProgress(step)
            }

            switch statusResponse.status {
            case .complete:
                guard let result = statusResponse.result else {
                    throw WorkflowError.missingResult
                }
                logger.info("Workflow completed successfully: \(result.title)")
                return result

            case .failed:
                let failedStep = statusResponse.currentStep ?? "unknown"
                logger.error("Workflow failed at step: \(failedStep)")
                throw WorkflowError.workflowFailed(step: failedStep)

            case .running:
                // Continue polling
                try await Task.sleep(for: pollingInterval)
            }
        }
    }
}

// MARK: - Workflow Error

public enum WorkflowError: LocalizedError {
    case invalidResponse
    case creationFailed(statusCode: Int)
    case statusCheckFailed(statusCode: Int)
    case decodingError(Error)
    case timeout
    case workflowFailed(step: String)
    case missingResult

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .creationFailed(let statusCode):
            return "Failed to create import workflow. Server returned status \(statusCode)."
        case .statusCheckFailed(let statusCode):
            return "Failed to check workflow status. Server returned status \(statusCode)."
        case .decodingError:
            return "Failed to decode the workflow response from the server."
        case .timeout:
            return "The import timed out. Please try again."
        case .workflowFailed(let step):
            return "Import failed at step: \(step). Please try again."
        case .missingResult:
            return "The workflow completed but no result was returned."
        }
    }
}
