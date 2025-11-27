import Foundation

struct WeeklyRecommendationsResponse: Codable {
    let weekOf: String
    let books: [WeeklyRecommendation]
    let generatedAt: Date
    let nextRefresh: Date

    enum CodingKeys: String, CodingKey {
        case weekOf = "week_of"
        case books
        case generatedAt = "generated_at"
        case nextRefresh = "next_refresh"
    }
}

struct WeeklyRecommendation: Codable, Identifiable {
    let isbn: String
    let title: String
    let authors: [String]
    let coverURLString: String
    let reason: String

    var id: String { isbn }

    var coverURL: URL? {
        URL(string: coverURLString)
    }

    enum CodingKeys: String, CodingKey {
        case isbn
        case title
        case authors
        case coverURLString = "cover_url"
        case reason
    }
}
