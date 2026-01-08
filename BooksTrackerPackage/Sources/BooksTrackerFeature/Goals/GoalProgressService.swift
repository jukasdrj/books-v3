import Foundation
import SwiftData

/// Service responsible for calculating and updating goal progress
/// Automatically tracks progress based on library activity
@MainActor
public final class GoalProgressService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Progress Calculation

    /// Calculate current progress for all active goals
    public func updateAllGoalProgress() async throws {
        let goals = try fetchActiveGoals()

        for goal in goals {
            try await updateGoalProgress(goal)
        }

        try modelContext.save()
    }

    /// Update progress for a specific goal
    public func updateGoalProgress(_ goal: Goal) async throws {
        let newProgress: Int

        switch goal.goalType {
        case .booksRead:
            newProgress = try calculateBooksRead(for: goal)

        case .pagesRead:
            newProgress = try calculatePagesRead(for: goal)

        case .authorsExplored:
            newProgress = try calculateAuthorsExplored(for: goal)

        case .genresExplored:
            newProgress = try calculateGenresExplored(for: goal)

        case .readingStreak:
            newProgress = try calculateReadingStreak(for: goal)

        case .readingTime:
            newProgress = try calculateReadingTime(for: goal)
        }

        // Only update if progress changed
        if newProgress != goal.currentProgress {
            goal.updateProgress(newProgress)

            // Create a progress snapshot for significant changes
            if shouldCreateSnapshot(goal: goal, oldProgress: goal.currentProgress, newProgress: newProgress) {
                createProgressSnapshot(for: goal, progress: newProgress)
            }
        }
    }

    // MARK: - Calculation Methods

    private func calculateBooksRead(for goal: Goal) throws -> Int {
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { entry in
                entry.readingStatus.rawValue == "Read"
            }
        )

        let allEntries = try modelContext.fetch(descriptor)
        let entries = allEntries.filter { entry in
            guard let dateCompleted = entry.dateCompleted else { return false }
            return dateCompleted >= startDate
        }

        // If goal has specific target works, filter by those
        if !goal.targetWorkUUIDs.isEmpty {
            return entries.filter { entry in
                guard let workUUID = entry.work?.uuid else { return false }
                return goal.targetWorkUUIDs.contains(workUUID)
            }.count
        }

        return entries.count
    }

    private func calculatePagesRead(for goal: Goal) throws -> Int {
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { entry in
                entry.readingStatus.rawValue == "Read"
            }
        )

        let allEntries = try modelContext.fetch(descriptor)
        let entries = allEntries.filter { entry in
            guard let dateCompleted = entry.dateCompleted else { return false }
            return dateCompleted >= startDate
        }

        var totalPages = 0
        for entry in entries {
            // If goal has specific target works, filter by those
            if !goal.targetWorkUUIDs.isEmpty {
                guard let workUUID = entry.work?.uuid,
                      goal.targetWorkUUIDs.contains(workUUID) else {
                    continue
                }
            }

            // Get page count from edition or work
            if let pageCount = entry.edition?.pageCount {
                totalPages += pageCount
            } else if let work = entry.work,
                      let firstEdition = work.editions?.first,
                      let pageCount = firstEdition.pageCount {
                totalPages += pageCount
            }
        }

        return totalPages
    }

    private func calculateAuthorsExplored(for goal: Goal) throws -> Int {
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { entry in
                entry.readingStatus.rawValue == "Read"
            }
        )

        let allEntries = try modelContext.fetch(descriptor)
        let entries = allEntries.filter { entry in
            guard let dateCompleted = entry.dateCompleted else { return false }
            return dateCompleted >= startDate
        }

        var authorUUIDs = Set<UUID>()
        for entry in entries {
            // If goal has specific target authors, only count those
            if !goal.targetAuthorUUIDs.isEmpty {
                if let work = entry.work, let authors = work.authors {
                    for author in authors {
                        if goal.targetAuthorUUIDs.contains(author.uuid) {
                            authorUUIDs.insert(author.uuid)
                        }
                    }
                }
            } else {
                // Count all unique authors
                if let work = entry.work, let authors = work.authors {
                    for author in authors {
                        authorUUIDs.insert(author.uuid)
                    }
                }
            }
        }

        return authorUUIDs.count
    }

    private func calculateGenresExplored(for goal: Goal) throws -> Int {
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { entry in
                entry.readingStatus.rawValue == "Read"
            }
        )

        let allEntries = try modelContext.fetch(descriptor)
        let entries = allEntries.filter { entry in
            guard let dateCompleted = entry.dateCompleted else { return false }
            return dateCompleted >= startDate
        }

        var subjects = Set<String>()
        for entry in entries {
            if let work = entry.work, !work.subjectTags.isEmpty {
                for subject in work.subjectTags {
                    subjects.insert(subject.lowercased())
                }
            }
        }

        return subjects.count
    }

    private func calculateReadingStreak(for goal: Goal) throws -> Int {
        // Get all reading sessions since goal start
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { session in
                session.date >= startDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let sessions = try modelContext.fetch(descriptor)

        guard !sessions.isEmpty else { return 0 }

        let calendar = Calendar.current
        var currentStreak = 0
        var lastSessionDate: Date?

        // Iterate through sessions to find consecutive days
        for session in sessions.reversed() {
            let sessionDay = calendar.startOfDay(for: session.date)

            if let lastDay = lastSessionDate {
                let daysBetween = calendar.dateComponents([.day], from: lastDay, to: sessionDay).day ?? 0

                if daysBetween == 0 {
                    // Same day, continue
                    continue
                } else if daysBetween == 1 {
                    // Consecutive day
                    currentStreak += 1
                    lastSessionDate = sessionDay
                } else {
                    // Gap in streak, break
                    break
                }
            } else {
                // First session
                currentStreak = 1
                lastSessionDate = sessionDay
            }
        }

        // Check if streak is still active (last session within 48 hours)
        if let lastDay = lastSessionDate {
            let today = calendar.startOfDay(for: Date())
            let daysSinceLastSession = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysSinceLastSession > 1 {
                // Streak broken
                return 0
            }
        }

        return currentStreak
    }

    private func calculateReadingTime(for goal: Goal) throws -> Int {
        let startDate = goal.startDate
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { session in
                session.date >= startDate
            }
        )

        let sessions = try modelContext.fetch(descriptor)

        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        let totalHours = Int((Double(totalMinutes) / 60.0).rounded())

        return totalHours
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

    private func shouldCreateSnapshot(goal: Goal, oldProgress: Int, newProgress: Int) -> Bool {
        // Create snapshot for milestone achievements (every 10% or at completion)
        let oldPercentage = goal.targetCount > 0 ? Double(oldProgress) / Double(goal.targetCount) : 0
        let newPercentage = goal.targetCount > 0 ? Double(newProgress) / Double(goal.targetCount) : 0

        let milestones = stride(from: 0.1, through: 1.0, by: 0.1).map { $0 }

        for milestone in milestones {
            if oldPercentage < milestone && newPercentage >= milestone {
                return true
            }
        }

        return false
    }

    private func createProgressSnapshot(for goal: Goal, progress: Int) {
        let snapshot = GoalProgress(
            recordedDate: Date(),
            progressValue: progress,
            milestone: nil
        )

        snapshot.goal = goal
        snapshot.goalUUID = goal.uuid

        modelContext.insert(snapshot)
    }

    // MARK: - Public API for Manual Updates

    /// Manually record progress for a goal (useful for custom goals)
    public func recordProgress(_ progress: Int, for goal: Goal, note: String? = nil) throws {
        goal.updateProgress(progress)

        let snapshot = GoalProgress(
            recordedDate: Date(),
            progressValue: progress,
            note: note
        )

        snapshot.goal = goal
        snapshot.goalUUID = goal.uuid

        modelContext.insert(snapshot)
        try modelContext.save()
    }

    /// Check if any goals are overdue and send notifications
    public func checkOverdueGoals() throws {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.statusRawValue == "Active" &&
                goal.deadline != nil
            }
        )

        let goals = try modelContext.fetch(descriptor)

        for goal in goals where goal.isOverdue {
            // Post notification for overdue goal
            NotificationCenter.default.post(
                name: .goalBecameOverdue,
                object: goal,
                userInfo: ["goalUUID": goal.uuid]
            )
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a goal becomes overdue
    public static let goalBecameOverdue = Notification.Name("GoalBecameOverdue")

    /// Posted when a goal is completed
    public static let goalCompleted = Notification.Name("GoalCompleted")

    /// Posted when goal progress updates
    public static let goalProgressUpdated = Notification.Name("GoalProgressUpdated")
}
