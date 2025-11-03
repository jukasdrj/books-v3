import Foundation

/// A book with minimal metadata for batch enrichment.
struct Book: Codable, Sendable {
    let title: String
    let author: String
    let isbn: String?
}

/// The payload for the batch enrichment API endpoint.
struct BatchEnrichmentPayload: Codable, Sendable {
    let books: [Book]
    let jobId: String
}
