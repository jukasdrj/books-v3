import Foundation

public struct EnrichedBookDTO: Codable, Sendable {
    public let isbn: String
    public let title: String
    public let authors: [String]
    public let publisher: String?
    public let publishedDate: String?
    public let pageCount: Int?
    public let coverUrl: String?
    public let description: String?
    public let provider: String?
    public let enrichedAt: String?
}

public struct EnrichmentErrorDTO: Codable, Sendable {
    public let error: ErrorDetails
}

public struct ErrorDetails: Codable, Sendable {
    public let code: String
    public let message: String
    public let providersChecked: [String]
}

struct EnrichBookV2Request: Codable, Sendable {
    let barcode: String
    let preferProvider: String
    let idempotencyKey: String
}
