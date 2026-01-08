import Foundation
import SwiftData

/// Filter types for diversity-based library filtering
/// Used for tap-to-filter navigation from Insights charts to Library view
public enum DiversityFilter: Equatable, Sendable, Hashable {
    case region(CulturalRegion)
    case gender(AuthorGender)
    case language(String)
    case marginalizedVoices
    case none

    /// Human-readable name for the filter
    public var displayName: String {
        switch self {
        case .region(let region):
            return region.displayName
        case .gender(let gender):
            return gender.displayName
        case .language(let language):
            return language
        case .marginalizedVoices:
            return "Marginalized Voices"
        case .none:
            return "All Books"
        }
    }

    /// Icon for filter badge
    public var badgeIcon: String {
        switch self {
        case .region:
            return "globe"
        case .gender:
            return "person.2"
        case .language:
            return "character.book.closed"
        case .marginalizedVoices:
            return "hand.raised"
        case .none:
            return "books.vertical"
        }
    }

    /// Descriptive label for accessibility
    public var accessibilityLabel: String {
        switch self {
        case .region(let region):
            return "Filtering by region: \(region.displayName)"
        case .gender(let gender):
            return "Filtering by gender: \(gender.displayName)"
        case .language(let language):
            return "Filtering by language: \(language)"
        case .marginalizedVoices:
            return "Filtering by marginalized voices"
        case .none:
            return "No filter applied"
        }
    }
}
