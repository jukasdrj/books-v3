import Foundation

// MARK: - Public Domain Models

/// A book recommendation with similarity score and reasoning
public struct ScoredRecommendation: Sendable, Identifiable, Codable {
    /// Unique identifier (uses ISBN)
    public var id: String {
        isbn
    }

    /// ISBN of the recommended book
    public let isbn: String

    /// Book title
    public let title: String

    /// Author name (single string from backend)
    public let author: String

    /// Cover image URL
    public let coverUrl: String?

    /// Recommendation score (0-100, optional - not in weekly_fallback)
    public let score: Double?

    /// Human-readable reason for the recommendation
    public let reason: String

    /// Optional score breakdown (only in debug mode)
    public let breakdown: ScoreBreakdown?

    /// Computed property for backward compatibility with multi-reason format
    public var reasons: [String] {
        [reason]
    }
}

// MARK: - Result Models

/// Result from the recommendations API containing personalized book suggestions
/// Stripped of the `{success: bool}` wrapper for clean domain modeling
public struct RecommendationResult: Sendable, Codable {
    /// List of recommended books with scores and reasoning
    public let recommendations: [ScoredRecommendation]

    /// Total number of recommendations returned
    public let total: Int

    /// Strategy used to generate recommendations
    public let strategy: RecommendationStrategy

    /// Optional debug information (only returned from /debug endpoint)
    public let debug: RecommendationDebug?

    enum CodingKeys: String, CodingKey {
        case recommendations
        case total
        case strategy
        case debug
    }
}

/// Breakdown of how the recommendation score was calculated
public struct ScoreBreakdown: Sendable, Codable {
    /// Points from subject/genre similarity (0-60)
    public let subjectMatch: Double

    /// Points from user preference alignment (0-20)
    public let preferenceMatch: Double

    /// Points from diversity bonus (0-20)
    public let diversityBonus: Double

    enum CodingKeys: String, CodingKey {
        case subjectMatch = "subject_match"
        case preferenceMatch = "preference_match"
        case diversityBonus = "diversity_bonus"
    }
}

/// Strategy used to generate recommendations
public enum RecommendationStrategy: String, Sendable, Codable {
    /// Based on user's 4-5 star ratings (requires rating history)
    case preferenceBased = "preference_based"

    /// Based on user preferences only (no ratings needed)
    case coldStart = "cold_start"

    /// Fallback to weekly recommendations (when personalized data unavailable)
    case weeklyFallback = "weekly_fallback"

    public var displayName: String {
        switch self {
        case .preferenceBased:
            return "Based on your ratings"
        case .coldStart:
            return "Based on your preferences"
        case .weeklyFallback:
            return "Weekly picks"
        }
    }

    public var description: String {
        switch self {
        case .preferenceBased:
            return "Recommendations based on books you've rated highly"
        case .coldStart:
            return "Recommendations based on your reading preferences"
        case .weeklyFallback:
            return "Curated weekly recommendations for you"
        }
    }
}

/// Debug information from the recommendation engine
public struct RecommendationDebug: Sendable, Codable {
    /// Subjects extracted from user's reading history
    public let userSubjects: [String]

    /// Subjects from user preferences
    public let preferenceSubjects: [String]

    /// Number of candidate books evaluated
    public let candidateCount: Int

    enum CodingKeys: String, CodingKey {
        case userSubjects = "user_subjects"
        case preferenceSubjects = "preference_subjects"
        case candidateCount = "candidate_count"
    }
}

// MARK: - Errors

/// Errors specific to the Recommendations API
public enum RecommendationError: LocalizedError, Sendable {
    /// Invalid URL construction
    case invalidURL

    /// Network or connectivity error
    case networkError(Error)

    /// HTTP error (non-200 status code)
    case serverError(statusCode: Int)

    /// API returned success=false with error message
    case apiError(message: String)

    /// User has insufficient reading history for personalized recommendations
    /// UI should show onboarding or prompt to rate books
    case insufficientHistory

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration."
        case .networkError(let error):
            return error.localizedDescription
        case .serverError(let code):
            return "Server returned error code: \(code)"
        case .apiError(let msg):
            return msg
        case .insufficientHistory:
            return "Not enough reading history for personalized recommendations. Rate some books to get started!"
        }
    }

    /// Whether this error should trigger the onboarding flow
    public var shouldShowOnboarding: Bool {
        if case .insufficientHistory = self {
            return true
        }
        return false
    }
}

// Custom Equatable implementation for RecommendationError
extension RecommendationError: Equatable {
    public static func == (lhs: RecommendationError, rhs: RecommendationError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case (.networkError, .networkError):
            return true  // Compare by case only, not the error instance
        case (.serverError(let lCode), .serverError(let rCode)):
            return lCode == rCode
        case (.apiError(let lMsg), .apiError(let rMsg)):
            return lMsg == rMsg
        case (.insufficientHistory, .insufficientHistory):
            return true
        default:
            return false
        }
    }
}
