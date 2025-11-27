import Foundation

public struct APICapabilities: Codable, Sendable {
    public let features: Features
    public let limits: Limits
    public let version: String

    public struct Features: Codable, Sendable {
        public let semanticSearch: Bool
        public let similarBooks: Bool
        public let weeklyRecommendations: Bool
        public let sseStreaming: Bool
        public let batchEnrichment: Bool
        public let csvImport: Bool

        enum CodingKeys: String, CodingKey {
            case semanticSearch = "semantic_search"
            case similarBooks = "similar_books"
            case weeklyRecommendations = "weekly_recommendations"
            case sseStreaming = "sse_streaming"
            case batchEnrichment = "batch_enrichment"
            case csvImport = "csv_import"
        }
    }

    public struct Limits: Codable, Sendable {
        public let semanticSearchRpm: Int
        public let textSearchRpm: Int
        public let csvMaxRows: Int
        public let batchMaxPhotos: Int

        enum CodingKeys: String, CodingKey {
            case semanticSearchRpm = "semantic_search_rpm"
            case textSearchRpm = "text_search_rpm"
            case csvMaxRows = "csv_max_rows"
            case batchMaxPhotos = "batch_max_photos"
        }
    }
}
