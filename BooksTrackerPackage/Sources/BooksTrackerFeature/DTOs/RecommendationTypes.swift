import Foundation

// MARK: - Public Domain Models

/// A book recommendation with similarity score and reasoning
public struct ScoredRecommendation: Sendable, Identifiable {
    /// Unique identifier (uses workKey or ISBN as fallback)
    public var id: String {
        book.workKey ?? book.isbn
    }

    /// The recommended book
    public let book: V3Book

    /// Recommendation score (0-100)
    public let score: Double

    /// Human-readable reasons for the recommendation
    public let reasons: [String]

    /// Optional score breakdown (only in debug mode)
    public let breakdown: ScoreBreakdown?
}

extension ScoredRecommendation: Decodable {
    enum CodingKeys: String, CodingKey {
        case book
        case score
        case reasons
        case breakdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.book = try container.decode(V3Book.self, forKey: .book)
        self.score = try container.decode(Double.self, forKey: .score)
        self.reasons = try container.decode([String].self, forKey: .reasons)
        self.breakdown = try container.decodeIfPresent(ScoreBreakdown.self, forKey: .breakdown)
    }
}

// MARK: - Result Models

/// Result from the recommendations API containing personalized book suggestions
/// Stripped of the `{success: bool}` wrapper for clean domain modeling
public struct RecommendationResult: Sendable, Decodable {
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
public struct ScoreBreakdown: Sendable, Decodable {
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
public enum RecommendationStrategy: String, Sendable, Decodable {
    /// Based on user's 4-5 star ratings (requires rating history)
    case preferenceBased = "preference_based"

    /// Based on user preferences only (no ratings needed)
    case coldStart = "cold_start"

    public var displayName: String {
        switch self {
        case .preferenceBased:
            return "Based on your ratings"
        case .coldStart:
            return "Based on your preferences"
        }
    }

    public var description: String {
        switch self {
        case .preferenceBased:
            return "Recommendations based on books you've rated highly"
        case .coldStart:
            return "Recommendations based on your reading preferences"
        }
    }
}

/// Debug information from the recommendation engine
public struct RecommendationDebug: Sendable, Decodable {
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

// MARK: - Internal DTOs

/// Internal wrapper to handle the API's `{success: bool, data: {...}}` envelope
/// This is stripped away before returning to the caller
/// Updated to support RFC 9457 Problem Details format (bendv3 Issue #261)
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?

    // RFC 9457 Problem Details fields
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
    let instance: String?
    let code: String?
    let retryable: Bool?

    // Legacy field for backward compatibility
    let error: String?

    /// Get error message (RFC 9457 'detail' or legacy 'error')
    var errorMessage: String? {
        return detail ?? error
    }

    private enum CodingKeys: String, CodingKey {
        case success, data
        case type, title, status, detail, instance, code, retryable
        case error
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
