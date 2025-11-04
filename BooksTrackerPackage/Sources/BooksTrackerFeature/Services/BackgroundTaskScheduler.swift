import Foundation
import SwiftData

/// Schedules non-critical background tasks to run after app launch completes
@MainActor
public final class BackgroundTaskScheduler {
    public static let shared = BackgroundTaskScheduler()

    private var scheduledTasks: [Task<Void, Never>] = []
    private let deferralDelay: Duration = .seconds(2) // Delay background work by 2s

    private init() {}

    /// Schedule a task to run after app launch completes
    /// - Parameter priority: TaskPriority (default: .background)
    /// - Parameter operation: Async operation to execute
    public func schedule(
        priority: TaskPriority = .background,
        operation: @escaping @MainActor () async -> Void
    ) {
        let task = Task(priority: priority) {
            // Wait for app to be fully interactive before running background tasks
            try? await Task.sleep(for: deferralDelay)

            LaunchMetrics.shared.recordMilestone("Background task started")
            await operation()
            LaunchMetrics.shared.recordMilestone("Background task completed")
        }

        scheduledTasks.append(task)
    }

    /// Cancel all scheduled background tasks (e.g., on library reset)
    public func cancelAll() {
        let count = scheduledTasks.count
        scheduledTasks.forEach { $0.cancel() }
        scheduledTasks.removeAll()
        print("🛑 Cancelled \(count) background tasks")
    }

    /// Wait for all background tasks to complete (for testing)
    public func waitForCompletion() async {
        for task in scheduledTasks {
            await task.value
        }
        scheduledTasks.removeAll()
    }
}
