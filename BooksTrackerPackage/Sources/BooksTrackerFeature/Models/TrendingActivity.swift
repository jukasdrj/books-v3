import Foundation
import SwiftData

/// Tracks user activity (searches, library additions) for generating time-based trending books
@Model
public final class TrendingActivity {
    /// ISBN of the book (primary identifier)
    var isbn: String?

    /// Book title (for display)
    var title: String?

    /// Number of times this book was searched
    var searchCount: Int = 0

    /// Number of times this book was added to library
    var addCount: Int = 0

    /// Last time this book had activity (search or add)
    var lastActivity: Date = Date()

    public init(isbn: String? = nil, title: String? = nil) {
        self.isbn = isbn
        self.title = title
        self.searchCount = 0
        self.addCount = 0
        self.lastActivity = Date()
    }
}

/// Type of activity to track
enum ActivityType {
    case search
    case add
}

/// Time range for trending calculations
enum TimeRange: String, CaseIterable, Identifiable {
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case allTime = "All Time"

    var id: String { rawValue }

    /// Time interval in seconds
    var seconds: TimeInterval {
        switch self {
        case .lastWeek: return 7 * 24 * 60 * 60
        case .lastMonth: return 30 * 24 * 60 * 60
        case .allTime: return .infinity
        }
    }

    /// Display name for UI
    var displayName: String { rawValue }
}
