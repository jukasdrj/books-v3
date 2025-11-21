import Foundation
import SwiftData

/// Enhanced diversity statistics model for v2 Representation Radar Chart
/// Aggregates diversity metrics across user's library with completion tracking
@Model
public final class EnhancedDiversityStats {
    public var userId: String
    public var period: StatsPeriod

    // MARK: - Diversity Dimensions (5 core axes for Radar Chart)

    /// Cultural origins distribution (e.g., {"African": 12, "European": 8})
    public var culturalOrigins: [String: Int]

    /// Gender distribution (e.g., {"Female": 15, "Male": 5, "Non-binary": 2})
    public var genderDistribution: [String: Int]

    /// Translation status (e.g., {"Translated": 8, "Original Language": 12})
    public var translationStatus: [String: Int]

    /// Own Voices theme (e.g., {"Own Voices": 10, "Not Own Voices": 8})
    public var ownVoicesTheme: [String: Int]

    /// Niche/Accessibility features (e.g., {"Accessible": 5, "Standard": 13})
    public var nicheAccessibility: [String: Int]

    // MARK: - Completion Tracking (for Gamification)

    /// Total books in library for this period
    public var totalBooks: Int

    /// Number of books with cultural origin data filled
    public var booksWithCulturalData: Int

    /// Number of books with gender data filled
    public var booksWithGenderData: Int

    /// Number of books with translation data filled
    public var booksWithTranslationData: Int

    /// Number of books with own voices data filled
    public var booksWithOwnVoicesData: Int

    /// Number of books with accessibility data filled
    public var booksWithAccessibilityData: Int

    // MARK: - Metadata

    public var lastCalculated: Date

    // MARK: - Computed Properties

    /// Completion percentage for cultural origin dimension (0-100)
    public var culturalCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithCulturalData) / Double(totalBooks) * 100
    }

    /// Completion percentage for gender dimension (0-100)
    public var genderCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithGenderData) / Double(totalBooks) * 100
    }

    /// Completion percentage for translation dimension (0-100)
    public var translationCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithTranslationData) / Double(totalBooks) * 100
    }

    /// Completion percentage for own voices dimension (0-100)
    public var ownVoicesCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithOwnVoicesData) / Double(totalBooks) * 100
    }

    /// Completion percentage for accessibility dimension (0-100)
    public var accessibilityCompletionPercentage: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(booksWithAccessibilityData) / Double(totalBooks) * 100
    }

    /// Overall completion percentage across all 5 dimensions (0-100)
    /// Formula: (sum of all booksWithXData) / (totalBooks × 5) × 100
    public var overallCompletionPercentage: Double {
        let totalFields = totalBooks * 5 // 5 dimensions
        guard totalFields > 0 else { return 0 }

        let completedFields = booksWithCulturalData + booksWithGenderData +
                              booksWithTranslationData + booksWithOwnVoicesData +
                              booksWithAccessibilityData

        return Double(completedFields) / Double(totalFields) * 100
    }

    // MARK: - Initializer

    public init(userId: String, period: StatsPeriod = .allTime) {
        self.userId = userId
        self.period = period
        self.culturalOrigins = [:]
        self.genderDistribution = [:]
        self.translationStatus = [:]
        self.ownVoicesTheme = [:]
        self.nicheAccessibility = [:]
        self.totalBooks = 0
        self.booksWithCulturalData = 0
        self.booksWithGenderData = 0
        self.booksWithTranslationData = 0
        self.booksWithOwnVoicesData = 0
        self.booksWithAccessibilityData = 0
        self.lastCalculated = Date()
    }
}

/// Time period for statistics aggregation
public enum StatsPeriod: String, Codable {
    case allTime
    case year
    case month
}
