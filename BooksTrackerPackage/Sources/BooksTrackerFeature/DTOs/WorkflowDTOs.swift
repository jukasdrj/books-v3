import Foundation

public enum WorkflowStatus: String, Codable, Sendable {
    case running
    case complete
    case failed
}

public struct WorkflowCreateResponse: Codable, Sendable {
    public let workflowId: String
    public let status: WorkflowStatus
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case workflowId
        case status
        case createdAt = "created_at"
    }
}

public struct WorkflowStatusResponse: Codable, Sendable {
    public let workflowId: String
    public let status: WorkflowStatus
    public let currentStep: String?
    public let result: WorkflowResult?
}

public struct WorkflowResult: Codable, Sendable {
    public let isbn: String
    public let title: String
    public let success: Bool
}
