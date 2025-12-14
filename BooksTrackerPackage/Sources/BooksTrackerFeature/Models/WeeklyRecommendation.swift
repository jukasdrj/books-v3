import Foundation

/// Wrapper for V3 API response
struct WeeklyRecommendationsAPIResponse: Codable {
    let success: Bool
    let data: WeeklyRecommendationsData
}

struct WeeklyRecommendationsData: Codable {
    let weekOf: String
    let recommendations: [WeeklyRecommendationDTO]
    let count: Int
    let totalAvailable: Int
}

struct WeeklyRecommendationDTO: Codable {
    let isbn: String
    let title: String
    let author: String
    let coverUrl: String
    let reason: String
    let score: Double
}

// MARK: - App Models (used by views)

struct WeeklyRecommendationsResponse: Codable {
    let weekOf: String
    let books: [WeeklyRecommendation]
    let nextRefresh: Date

    /// Create from V3 API response
    init(from apiResponse: WeeklyRecommendationsAPIResponse) {
        self.weekOf = apiResponse.data.weekOf
        self.books = apiResponse.data.recommendations.map { WeeklyRecommendation(from: $0) }
        // Next refresh is next Monday
        self.nextRefresh = Self.nextMonday()
    }

    /// For cache decoding
    init(weekOf: String, books: [WeeklyRecommendation], nextRefresh: Date) {
        self.weekOf = weekOf
        self.books = books
        self.nextRefresh = nextRefresh
    }

    private static func nextMonday() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // Sunday = 1, Monday = 2, etc.
        let daysUntilMonday = weekday == 1 ? 1 : (9 - weekday)
        return calendar.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today.addingTimeInterval(7 * 24 * 60 * 60)
    }
}

struct WeeklyRecommendation: Codable, Identifiable, Hashable {
    let isbn: String
    let title: String
    let authors: [String]
    let coverURLString: String
    let reason: String

    var id: String { isbn }

    var coverURL: URL? {
        URL(string: coverURLString)
    }

    /// Create from V3 API DTO
    init(from dto: WeeklyRecommendationDTO) {
        self.isbn = dto.isbn
        self.title = dto.title
        self.authors = [dto.author]
        self.coverURLString = dto.coverUrl
        self.reason = dto.reason
    }

    /// For cache decoding
    init(isbn: String, title: String, authors: [String], coverURLString: String, reason: String) {
        self.isbn = isbn
        self.title = title
        self.authors = authors
        self.coverURLString = coverURLString
        self.reason = reason
    }
}
