import Foundation

// MARK: - Workflow Status

/// Status of a Cloudflare Workflow import job
public enum WorkflowStatus: String, Codable, Sendable {
    case running
    case complete
    case failed
}

// MARK: - Workflow Steps

/// Individual steps in the import workflow
public enum WorkflowStep: String, Codable, Sendable, CaseIterable {
    case validateISBN = "validate-isbn"
    case fetchMetadata = "fetch-metadata"
    case uploadCover = "upload-cover"
    case saveDatabase = "save-database"

    public var displayName: String {
        switch self {
        case .validateISBN: return "Validating ISBN"
        case .fetchMetadata: return "Fetching metadata"
        case .uploadCover: return "Uploading cover"
        case .saveDatabase: return "Saving to database"
        }
    }

    public var icon: String {
        switch self {
        case .validateISBN: return "barcode.viewfinder"
        case .fetchMetadata: return "magnifyingglass"
        case .uploadCover: return "photo"
        case .saveDatabase: return "externaldrive"
        }
    }
}

// MARK: - Create Workflow Request/Response

/// Request body for creating a new import workflow
public struct WorkflowCreateRequest: Codable, Sendable {
    public let isbn: String
    public let source: String

    public init(isbn: String, source: String = "google_books") {
        self.isbn = isbn
        self.source = source
    }
}

/// Response from creating a new import workflow
public struct WorkflowCreateResponse: Codable, Sendable {
    public let workflowId: String
    public let status: WorkflowStatus
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case workflowId
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Workflow Status Response

/// Response from checking workflow status
public struct WorkflowStatusResponse: Codable, Sendable {
    public let workflowId: String
    public let status: WorkflowStatus
    public let currentStep: String?
    public let result: WorkflowResult?
}

/// Result data when workflow completes successfully
public struct WorkflowResult: Codable, Sendable {
    public let isbn: String
    public let title: String
    public let success: Bool
}
