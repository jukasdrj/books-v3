import Foundation
import SwiftData
import SwiftUI
import Observation

/// Coordinates automatic goal tracking and progress updates
/// Listens to library changes and updates goal progress accordingly
@MainActor
@Observable
public final class GoalTrackingCoordinator {
    private let modelContext: ModelContext
    private let progressService: GoalProgressService
    private var isTracking = false

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.progressService = GoalProgressService(modelContext: modelContext)
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNotificationObservers() {
        // Listen for library changes that affect goals
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryChange),
            name: .libraryWasUpdated,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookCompleted),
            name: .bookMarkedAsRead,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReadingSessionEnded),
            name: .readingSessionEnded,
            object: nil
        )
    }

    // MARK: - Event Handlers

    @objc private func handleLibraryChange(_ notification: Notification) {
        Task {
            await updateAllGoals()
        }
    }

    @objc private func handleBookCompleted(_ notification: Notification) {
        Task {
            await updateAllGoals()

            // Check if any goals were completed
            try? await checkForCompletedGoals()
        }
    }

    @objc private func handleReadingSessionEnded(_ notification: Notification) {
        Task {
            // Update streak and time-based goals
            await updateTimeBasedGoals()
        }
    }

    // MARK: - Update Methods

    /// Update all active goal progress
    public func updateAllGoals() async {
        guard !isTracking else { return }

        isTracking = true
        defer { isTracking = false }

        do {
            try await progressService.updateAllGoalProgress()
        } catch {
            print("⚠️ Failed to update goals: \(error.localizedDescription)")
        }
    }

    /// Update only time-based goals (streaks, reading time)
    private func updateTimeBasedGoals() async {
        do {
            let goals = try fetchActiveGoals()

            for goal in goals {
                if goal.goalType == .readingStreak || goal.goalType == .readingTime {
                    try await progressService.updateGoalProgress(goal)
                }
            }

            try modelContext.save()
        } catch {
            print("⚠️ Failed to update time-based goals: \(error.localizedDescription)")
        }
    }

    /// Check if any goals were just completed
    private func checkForCompletedGoals() async throws {
        let goals = try fetchActiveGoals()

        for goal in goals where goal.isCompleted && goal.status == .active {
            // Mark as completed
            goal.status = .completed
            goal.completionDate = Date()
            goal.touch()

            // Post completion notification
            NotificationCenter.default.post(
                name: .goalCompleted,
                object: goal,
                userInfo: ["goalUUID": goal.uuid]
            )
        }

        try modelContext.save()
    }

    // MARK: - Public API

    /// Manually trigger progress update for all goals
    public func refreshGoalProgress() async {
        await updateAllGoals()
    }

    /// Check for overdue goals and send notifications
    public func checkOverdueGoals() {
        do {
            try progressService.checkOverdueGoals()
        } catch {
            print("⚠️ Failed to check overdue goals: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    private func fetchActiveGoals() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.statusRawValue == "Active"
            }
        )

        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the library is updated (books added/removed/changed)
    public static let libraryWasUpdated = Notification.Name("LibraryWasUpdated")

    /// Posted when a book is marked as read
    public static let bookMarkedAsRead = Notification.Name("BookMarkedAsRead")

    /// Posted when a reading session ends
    public static let readingSessionEnded = Notification.Name("ReadingSessionEnded")
}

// MARK: - Environment Key

private struct GoalTrackingCoordinatorKey: EnvironmentKey {
    nonisolated static let defaultValue: GoalTrackingCoordinator? = nil
}

extension EnvironmentValues {
    public var goalTrackingCoordinator: GoalTrackingCoordinator? {
        get { self[GoalTrackingCoordinatorKey.self] }
        set { self[GoalTrackingCoordinatorKey.self] = newValue }
    }
}
