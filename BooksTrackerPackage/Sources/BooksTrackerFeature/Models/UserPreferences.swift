import SwiftData
import Foundation

/// User reading preferences for personalized book recommendations
/// Maps to backend UserPreferences interface for recommendation API
@Model
public final class UserPreferences {
    /// Unique identifier (typically matches userId)
    @Attribute(.unique) public var userId: String

    // MARK: - Subject Preferences

    /// Preferred book subjects/genres (e.g., ["fantasy", "mystery"])
    /// Used for content-based filtering in recommendation scoring
    public var preferredSubjects: [String]

    /// Subjects to exclude from recommendations (e.g., ["horror"])
    public var excludedSubjects: [String]

    // MARK: - Author Preferences

    /// Preferred authors (Open Library keys, e.g., ["/authors/OL23919A"])
    public var preferredAuthors: [String]

    /// Authors to exclude from recommendations
    public var excludedAuthors: [String]

    // MARK: - Reading Mood & Constraints

    /// Current reading mood preference
    /// Options: light, dark, epic, cozy, thrilling
    public var mood: ReadingMood?

    /// Minimum page count filter for recommendations
    public var pageCountMin: Int?

    /// Maximum page count filter for recommendations
    public var pageCountMax: Int?

    /// Minimum publication year filter
    public var publicationYearMin: Int?

    /// Maximum publication year filter
    public var publicationYearMax: Int?

    // MARK: - Metadata

    /// Timestamp of last preferences update
    public var lastUpdated: Date

    /// Whether onboarding has been completed
    public var onboardingCompleted: Bool

    // MARK: - Initialization

    public init(
        userId: String,
        preferredSubjects: [String] = [],
        excludedSubjects: [String] = [],
        preferredAuthors: [String] = [],
        excludedAuthors: [String] = [],
        mood: ReadingMood? = nil,
        pageCountMin: Int? = nil,
        pageCountMax: Int? = nil,
        publicationYearMin: Int? = nil,
        publicationYearMax: Int? = nil,
        onboardingCompleted: Bool = false
    ) {
        self.userId = userId
        self.preferredSubjects = preferredSubjects
        self.excludedSubjects = excludedSubjects
        self.preferredAuthors = preferredAuthors
        self.excludedAuthors = excludedAuthors
        self.mood = mood
        self.pageCountMin = pageCountMin
        self.pageCountMax = pageCountMax
        self.publicationYearMin = publicationYearMin
        self.publicationYearMax = publicationYearMax
        self.lastUpdated = Date()
        self.onboardingCompleted = onboardingCompleted
    }

    // MARK: - Validation

    /// Validates that page count constraints are logical
    public var isPageCountValid: Bool {
        guard let min = pageCountMin, let max = pageCountMax else {
            return true // If either is nil, constraint is valid
        }
        return min <= max
    }

    /// Validates that publication year constraints are logical
    public var isPublicationYearValid: Bool {
        guard let min = publicationYearMin, let max = publicationYearMax else {
            return true
        }
        return min <= max
    }

    /// Returns true if user has set any preferences (not a cold start)
    public var hasPreferences: Bool {
        return !preferredSubjects.isEmpty
            || !excludedSubjects.isEmpty
            || !preferredAuthors.isEmpty
            || mood != nil
            || pageCountMin != nil
            || pageCountMax != nil
    }

    // MARK: - API Conversion

    /// Converts to backend-compatible dictionary for API requests
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "preferred_subjects": preferredSubjects,
            "excluded_subjects": excludedSubjects,
            "preferred_authors": preferredAuthors,
            "excluded_authors": excludedAuthors
        ]

        if let mood = mood {
            dict["mood"] = mood.rawValue
        }
        if let pageCountMin = pageCountMin {
            dict["page_count_min"] = pageCountMin
        }
        if let pageCountMax = pageCountMax {
            dict["page_count_max"] = pageCountMax
        }
        if let publicationYearMin = publicationYearMin {
            dict["publication_year_min"] = publicationYearMin
        }
        if let publicationYearMax = publicationYearMax {
            dict["publication_year_max"] = publicationYearMax
        }

        return dict
    }
}

// MARK: - Reading Mood Enum

/// User's current reading mood preference
/// Matches backend mood options: 'light' | 'dark' | 'epic' | 'cozy' | 'thrilling'
public enum ReadingMood: String, Codable, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case epic = "epic"
    case cozy = "cozy"
    case thrilling = "thrilling"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .light: return "Light & Fun"
        case .dark: return "Dark & Intense"
        case .epic: return "Epic & Grand"
        case .cozy: return "Cozy & Comforting"
        case .thrilling: return "Thrilling & Fast-Paced"
        }
    }

    public var description: String {
        switch self {
        case .light:
            return "Uplifting stories with happy endings and lighthearted themes"
        case .dark:
            return "Complex, mature themes with emotional depth"
        case .epic:
            return "Grand adventures with world-building and scope"
        case .cozy:
            return "Warm, comforting reads perfect for relaxation"
        case .thrilling:
            return "Fast-paced, suspenseful stories that keep you guessing"
        }
    }

    public var systemImage: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .epic: return "mountain.2.fill"
        case .cozy: return "fireplace.fill"
        case .thrilling: return "bolt.fill"
        }
    }

    public var color: (light: String, dark: String) {
        switch self {
        case .light: return ("#FFD700", "#FFA500")  // Gold gradient
        case .dark: return ("#4A148C", "#6A1B9A")   // Deep purple gradient
        case .epic: return ("#1565C0", "#1976D2")   // Blue gradient
        case .cozy: return ("#D84315", "#E64A19")   // Warm orange gradient
        case .thrilling: return ("#C62828", "#D32F2F") // Red gradient
        }
    }
}
