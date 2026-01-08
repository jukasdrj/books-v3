import SwiftUI
import SwiftData

/// Coordinates diversity filter navigation from Insights to Library
/// Follows the same pattern as TabCoordinator for consistency
@MainActor
@Observable
public final class InsightsFilterCoordinator: @unchecked Sendable {
    /// Currently active diversity filter
    public var activeFilter: DiversityFilter = .none

    /// Pending navigation to Library with filter (consumed after switch)
    private var pendingNavigation: Bool = false

    public init() {}

    /// Apply a diversity filter and prepare for navigation to Library
    /// - Parameter filter: The diversity filter to apply
    public func applyFilter(_ filter: DiversityFilter) {
        activeFilter = filter
        pendingNavigation = true
    }

    /// Clear the active filter and reset to showing all books
    public func clearFilter() {
        activeFilter = .none
        pendingNavigation = false
    }

    /// Check and consume pending navigation state
    /// Returns true if navigation was pending (one-time use)
    public func consumePendingNavigation() -> Bool {
        let pending = pendingNavigation
        pendingNavigation = false
        return pending
    }
}

// MARK: - Environment Key

private struct InsightsFilterCoordinatorKey: EnvironmentKey {
    static let defaultValue: InsightsFilterCoordinator = {
        @MainActor func makeDefault() -> InsightsFilterCoordinator {
            InsightsFilterCoordinator()
        }
        return MainActor.assumeIsolated { makeDefault() }
    }()
}

extension EnvironmentValues {
    public var insightsFilterCoordinator: InsightsFilterCoordinator {
        get { self[InsightsFilterCoordinatorKey.self] }
        set { self[InsightsFilterCoordinatorKey.self] = newValue }
    }
}
