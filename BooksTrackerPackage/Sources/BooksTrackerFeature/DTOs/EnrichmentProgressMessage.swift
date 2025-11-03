import Foundation

/// Discriminated union for enrichment WebSocket messages
enum EnrichmentProgressMessage: Decodable {
    case progress(processedCount: Int, totalCount: Int, currentTitle: String)
    case complete(message: String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
        case processedCount
        case totalCount
        case currentTitle
        case message
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
            let message = try container.decode(String.self, forKey: .message)
            self = .complete(message: message)

        default:
            self = .unknown
        }
    }
}
