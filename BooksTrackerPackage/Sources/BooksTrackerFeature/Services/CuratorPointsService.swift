import SwiftData
import Foundation

/// Service for managing curator points awarded for contributing diversity metadata
/// All operations run on @MainActor since ModelContext requires it
@MainActor
public final class CuratorPointsService {
    
    private let modelContext: ModelContext
    private static let defaultUserId = "default-user"
    
    /// Initializes the service with the required ModelContext for persistence
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Award points for a diversity contribution
    /// - Parameters:
    ///   - actionType: Type of action performed
    ///   - cascadeCount: Number of works affected (for cascade bonuses)
    /// - Returns: Total points awarded (base + cascade bonus)
    @discardableResult
    public func awardPoints(for actionType: CuratorActionType, cascadeCount: Int = 1) async throws -> Int {
        let curatorPoints = try fetchOrCreatePoints()
        
        // Base points for the action
        let basePoints = actionType.pointValue
        
        // Cascade bonus: additional points for each affected work beyond the first
        let cascadeBonus = cascadeCount > 1 ? (cascadeCount - 1) * 5 : 0
        
        let totalAwarded = basePoints + cascadeBonus
        
        curatorPoints.awardPoints(totalAwarded, for: actionType)
        
        try modelContext.save()
        
        return totalAwarded
    }
    
    /// Get total curator points for the user
    /// - Returns: Total points accumulated
    public func getTotalPoints() async throws -> Int {
        let curatorPoints = try fetchOrCreatePoints()
        return curatorPoints.totalPoints
    }
    
    /// Get points breakdown by action type
    /// - Returns: Dictionary mapping action types to points earned
    public func getPointsBreakdown() async throws -> [CuratorActionType: Int] {
        let curatorPoints = try fetchOrCreatePoints()
        var breakdown: [CuratorActionType: Int] = [:]
        
        for (key, value) in curatorPoints.pointsByAction {
            if let actionType = CuratorActionType(rawValue: key) {
                breakdown[actionType] = value
            }
        }
        
        return breakdown
    }
    
    // MARK: - Helper Methods
    
    /// Fetches existing CuratorPoints or creates new one if not found
    private func fetchOrCreatePoints() throws -> CuratorPoints {
        let userId = Self.defaultUserId
        let descriptor = FetchDescriptor<CuratorPoints>(
            predicate: #Predicate { $0.userId == userId }
        )
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        } else {
            let newPoints = CuratorPoints(userId: userId)
            modelContext.insert(newPoints)
            return newPoints
        }
    }
}
