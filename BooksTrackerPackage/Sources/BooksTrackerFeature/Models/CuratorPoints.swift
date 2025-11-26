import Foundation
import SwiftData

/// Tracks curator points earned by the user for contributing diversity metadata
///
/// # Usage
///
/// ```swift
/// let points = CuratorPoints()
/// points.awardPoints(10, for: .authorGender)
/// print("Total: \(points.totalPoints)")
/// ```
@Model
public final class CuratorPoints {
    /// Unique identifier for the user (default user)
    public var userId: String
    
    /// Total curator points accumulated
    public var totalPoints: Int
    
    /// Points breakdown by action type
    public var pointsByAction: [String: Int]
    
    /// Last updated timestamp
    public var lastUpdated: Date
    
    // MARK: - Initializer
    
    public init(userId: String = "default-user") {
        self.userId = userId
        self.totalPoints = 0
        self.pointsByAction = [:]
        self.lastUpdated = Date()
    }
    
    // MARK: - Public Methods
    
    /// Award points for a specific action type
    /// - Parameters:
    ///   - points: Number of points to award
    ///   - actionType: Type of action performed
    public func awardPoints(_ points: Int, for actionType: CuratorActionType) {
        totalPoints += points
        pointsByAction[actionType.rawValue, default: 0] += points
        lastUpdated = Date()
    }
    
    /// Get points earned for a specific action type
    /// - Parameter actionType: Type of action to query
    /// - Returns: Total points earned for this action type
    public func pointsFor(_ actionType: CuratorActionType) -> Int {
        return pointsByAction[actionType.rawValue] ?? 0
    }
}

/// Types of curator actions that earn points
public enum CuratorActionType: String, Codable, Sendable {
    case authorGender = "author_gender"
    case culturalRegion = "cultural_region"
    case originalLanguage = "original_language"
    case ownVoices = "own_voices"
    case accessibility = "accessibility"
    case completeAllFields = "complete_all_fields"
    
    /// Points awarded for this action type
    public var pointValue: Int {
        switch self {
        case .authorGender: return 10
        case .culturalRegion: return 15
        case .originalLanguage: return 10
        case .ownVoices: return 20
        case .accessibility: return 10
        case .completeAllFields: return 50
        }
    }
    
    /// Display name for the action
    public var displayName: String {
        switch self {
        case .authorGender: return "Author Gender"
        case .culturalRegion: return "Cultural Region"
        case .originalLanguage: return "Original Language"
        case .ownVoices: return "Own Voices"
        case .accessibility: return "Accessibility"
        case .completeAllFields: return "Complete Profile"
        }
    }
}
