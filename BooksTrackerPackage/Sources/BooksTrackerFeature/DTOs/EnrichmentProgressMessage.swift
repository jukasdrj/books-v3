import Foundation

// MARK: - Payload Structs

/// Single book enrichment result from backend
/// Matches the structure returned by batch-enrichment.js
public struct EnrichedBookPayload: Decodable, Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let success: Bool
    public let error: String?
    public let enriched: EnrichedDataPayload?
}

/// The enriched data containing work, edition, and authors
/// Matches SingleEnrichmentResult from enrichment.ts
public struct EnrichedDataPayload: Decodable, Sendable {
    public let work: WorkDTO
    public let edition: EditionDTO?
    public let authors: [AuthorDTO]
}

// MARK: - WebSocket Message

/// Discriminated union for enrichment WebSocket messages
enum EnrichmentProgressMessage: Decodable {
    case progress(processedCount: Int, totalCount: Int, currentTitle: String)
    case complete(books: [EnrichedBookPayload])
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
        // Progress keys
        case processedCount
        case totalCount
        case currentTitle
        // Completion keys
        case data // The backend wraps the 'books' array in a 'data' object
    }

    private enum DataKeys: String, CodingKey {
        case books
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "progress":
            let processedCount = try container.decode(Int.self, forKey: .processedCount)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let currentTitle = try container.decode(String.self, forKey: .currentTitle)
            self = .progress(processedCount: processedCount, totalCount: totalCount, currentTitle: currentTitle)

        case "complete":
            // 1. Decode the nested 'data' object
            let dataContainer = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            // 2. Decode the 'books' array from within 'data'
            let books = try dataContainer.decode([EnrichedBookPayload].self, forKey: .books)
            self = .complete(books: books)

        default:
            self = .unknown
        }
    }
}
