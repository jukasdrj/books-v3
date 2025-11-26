import Foundation

/// Service for managing Curator Points, the gamification system for data contributions.
/// Points are stored in UserDefaults for persistence across app launches.
@MainActor
public class CuratorPointsService {

    /// UserDefaults key for storing points.
    private let pointsKey = "com.bookstracker.curatorPoints"
    private let userDefaults: UserDefaults

    /// Total points accumulated by the user.
    @Published public private(set) var totalPoints: Int

    /// Initializes the service, loading initial points from UserDefaults.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.totalPoints = userDefaults.integer(forKey: pointsKey)
    }

    /// Awards points for a specific contribution action.
    /// - Parameters:
    ///   - points: The number of points to award.
    ///   - action: A description of the action for logging.
    public func awardPoints(_ points: Int, for action: String) {
        guard points > 0 else { return }

        totalPoints += points
        userDefaults.set(totalPoints, forKey: pointsKey)

        #if DEBUG
        print("✅ Awarded \(points) points for \(action). Total: \(totalPoints)")
        #endif
    }

    /// Resets the user's points to zero.
    public func resetPoints() {
        totalPoints = 0
        userDefaults.removeObject(forKey: pointsKey)
    }
}
