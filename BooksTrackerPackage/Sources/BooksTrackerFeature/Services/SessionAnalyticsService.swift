import SwiftData
import Foundation
import OSLog

/// Errors specific to the SessionAnalyticsService.
public enum SessionAnalyticsServiceError: Error, LocalizedError {
    case streakDataNotFound
    case noSessionsFoundForAverageCalculation

    public var errorDescription: String? {
        switch self {
        case .streakDataNotFound:
            return "Streak data not found for the specified user."
        case .noSessionsFoundForAverageCalculation:
            return "No reading sessions found to calculate average pages per hour."
        }
    }
}

/// Service responsible for tracking reading streaks and session-based analytics.
@MainActor
public final class SessionAnalyticsService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "SessionAnalytics")

    /// In-memory cache for StreakData to reduce database fetches for frequent access.
    private var streakDataCache: [String: StreakData] = [:]

    /// Initializes the service with the required ModelContext for persistence.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Streak Tracking

    /// Updates the user's reading streak and other session analytics based on a completed session.
    /// This is the primary entry point for recording session data.
    /// - Parameters:
    ///   - userId: The ID of the user.
    ///   - session: The completed ReadingSession.
    /// - Throws: `SessionAnalyticsServiceError` if data cannot be fetched or saved.
    public func updateStreakForSession(userId: String, session: ReadingSession) async throws {
        logger.info("Updating streak and analytics for user ID: \(userId) with session on \(session.date.formatted()).")

        let streakData = try fetchOrCreateStreakData(userId: userId)

        // Update total session counts and minutes
        streakData.totalSessions += 1
        streakData.totalMinutesRead += session.durationMinutes

        // Streak logic
        let sessionDate = Calendar.current.startOfDay(for: session.date)
        let lastSessionStartOfDay = Calendar.current.startOfDay(for: streakData.lastSessionDate)

        if streakData.lastSessionDate == .distantPast {
            // First ever session
            streakData.currentStreak = 1
            logger.debug("First session recorded for user \(userId). Streak started at 1.")
        } else if sessionDate == lastSessionStartOfDay {
            // Session on the same day, do not increment streak, just update other stats
            logger.debug("Multiple sessions on the same day for user \(userId). Streak not incremented.")
        } else if isConsecutiveDay(lastSession: streakData.lastSessionDate, newSession: session.date) {
            // Consecutive day
            streakData.currentStreak += 1
            logger.debug("Consecutive day session for user \(userId). Streak incremented to \(streakData.currentStreak).")
        } else {
            // Streak broken
            streakData.streakBrokenCount += 1
            streakData.currentStreak = 1 // Start new streak
            logger.info("Streak broken for user \(userId). New streak started at 1. Total breaks: \(streakData.streakBrokenCount).")
        }

        streakData.longestStreak = max(streakData.longestStreak, streakData.currentStreak)
        streakData.lastSessionDate = session.date
        streakData.lastCalculated = Date()

        // Update session counts for week/month
        try await updateSessionCounts(userId: userId)

        // Calculate average pages per hour
        streakData.averagePagesPerHour = try await calculateAveragePagesPerHour(userId: userId)

        try modelContext.save()
        streakDataCache[userId] = streakData // Update cache
        logger.info("Streak and analytics updated successfully for user ID: \(userId). Current streak: \(streakData.currentStreak).")
    }

    /// Checks if the current streak is broken (e.g., if called at the start of a new day
    /// and no session was recorded yesterday) and resets it if necessary.
    /// This method might be called periodically (e.g., on app launch or daily background task).
    /// - Parameter userId: The ID of the user.
    /// - Throws: `SessionAnalyticsServiceError` if streak data cannot be fetched or saved.
    public func checkAndResetStreakIfBroken(userId: String) async throws {
        logger.info("Checking streak status for user ID: \(userId).")
        let streakData = try fetchOrCreateStreakData(userId: userId)

        guard streakData.lastSessionDate != .distantPast else {
            logger.debug("No previous sessions for user \(userId), streak cannot be broken.")
            return // No sessions, no streak to break
        }

        let today = Calendar.current.startOfDay(for: Date())
        let lastSessionStartOfDay = Calendar.current.startOfDay(for: streakData.lastSessionDate)

        // If the last session was not today, and not yesterday, the streak is broken
        if today != lastSessionStartOfDay && !isConsecutiveDay(lastSession: streakData.lastSessionDate, newSession: Date()) {
            if streakData.currentStreak > 0 { // Only reset if there was an active streak
                streakData.streakBrokenCount += 1
                streakData.currentStreak = 0 // Streak is broken
                streakData.lastCalculated = Date()
                try modelContext.save()
                streakDataCache[userId] = streakData // Update cache
                logger.info("Streak for user \(userId) was broken. Resetting current streak to 0. Total breaks: \(streakData.streakBrokenCount).")
            } else {
                logger.debug("Streak for user \(userId) was already 0 or inactive.")
            }
        } else {
            logger.debug("Streak for user \(userId) is still active or was already checked today.")
        }
    }

    /// Returns the current reading streak for the specified user.
    /// - Parameter userId: The ID of the user.
    /// - Returns: The current streak count.
    /// - Throws: `SessionAnalyticsServiceError.streakDataNotFound` if data is missing.
    public func calculateCurrentStreak(userId: String) async throws -> Int {
        let streakData = try fetchStreakData(userId: userId)
        return streakData.currentStreak
    }

    /// Returns the longest reading streak achieved by the specified user.
    /// - Parameter userId: The ID of the user.
    /// - Returns: The longest streak count.
    /// - Throws: `SessionAnalyticsServiceError.streakDataNotFound` if data is missing.
    public func calculateLongestStreak(userId: String) async throws -> Int {
        let streakData = try fetchStreakData(userId: userId)
        return streakData.longestStreak
    }

    // MARK: - Session Analytics

    /// Recalculates and updates session counts for the current week and month.
    /// This method fetches all relevant sessions and re-aggregates.
    /// - Parameter userId: The ID of the user.
    /// - Throws: `Error` if fetching sessions fails.
    public func updateSessionCounts(userId: String) async throws {
        logger.info("Recalculating session counts for user ID: \(userId).")
        let streakData = try fetchOrCreateStreakData(userId: userId)

        // Fetch all reading sessions (single-user app, so fetch all)
        let descriptor = FetchDescriptor<ReadingSession>()
        let allSessions = try modelContext.fetch(descriptor)

        let calendar = Calendar.current
        let now = Date()

        var sessionsThisWeek = 0
        var sessionsThisMonth = 0

        for session in allSessions {
            // Check for current week
            if calendar.isDate(session.date, equalTo: now, toGranularity: .weekOfYear) {
                sessionsThisWeek += 1
            }
            // Check for current month
            if calendar.isDate(session.date, equalTo: now, toGranularity: .month) {
                sessionsThisMonth += 1
            }
        }

        streakData.sessionsThisWeek = sessionsThisWeek
        streakData.sessionsThisMonth = sessionsThisMonth
        streakData.lastCalculated = Date()

        try modelContext.save()
        streakDataCache[userId] = streakData // Update cache
        logger.debug("Session counts updated for user \(userId): \(sessionsThisWeek) this week, \(sessionsThisMonth) this month.")
    }

    /// Calculates the average pages read per hour across all sessions for a user.
    /// - Parameter userId: The ID of the user.
    /// - Returns: The average pages per hour.
    /// - Throws: `SessionAnalyticsServiceError.noSessionsFoundForAverageCalculation` if no sessions exist.
    public func calculateAveragePagesPerHour(userId: String) async throws -> Double {
        logger.info("Calculating average pages per hour for user ID: \(userId).")

        // Fetch all reading sessions (single-user app)
        let descriptor = FetchDescriptor<ReadingSession>()
        let sessions = try modelContext.fetch(descriptor)

        guard !sessions.isEmpty else {
            logger.debug("No sessions found for user \(userId) to calculate average pages per hour.")
            return 0.0
        }

        var totalPagesRead = 0
        var totalDurationHours: Double = 0

        for session in sessions {
            let pages = session.pagesRead
            if pages > 0 { // Only count positive page progress
                totalPagesRead += pages
            }
            totalDurationHours += Double(session.durationMinutes) / 60.0
        }

        guard totalDurationHours > 0 else {
            logger.debug("Total reading duration is zero for user \(userId). Cannot calculate average pages per hour.")
            return 0.0
        }

        let average = Double(totalPagesRead) / totalDurationHours
        logger.debug("Average pages per hour for user \(userId): \(average).")
        return average
    }

    /// Fetches the StreakData object for a given user.
    /// - Parameter userId: The ID of the user.
    /// - Returns: The StreakData object.
    /// - Throws: `SessionAnalyticsServiceError.streakDataNotFound` if no data exists.
    public func fetchStreakData(userId: String) throws -> StreakData {
        if let cached = streakDataCache[userId] {
            return cached
        }

        let descriptor = FetchDescriptor<StreakData>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let streakData = try modelContext.fetch(descriptor).first else {
            logger.error("StreakData not found for user ID: \(userId).")
            throw SessionAnalyticsServiceError.streakDataNotFound
        }
        streakDataCache[userId] = streakData
        return streakData
    }

    // MARK: - Helper Methods (Private)

    /// Fetches an existing StreakData object or creates a new one if not found.
    /// - Parameter userId: The ID of the user.
    /// - Returns: The existing or newly created StreakData object.
    /// - Throws: `Error` if fetching or saving fails.
    private func fetchOrCreateStreakData(userId: String) throws -> StreakData {
        if let cached = streakDataCache[userId] {
            return cached
        }

        let descriptor = FetchDescriptor<StreakData>(
            predicate: #Predicate { $0.userId == userId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            streakDataCache[userId] = existing
            return existing
        } else {
            logger.info("Creating new StreakData for user ID: \(userId).")
            let newStreakData = StreakData(userId: userId)
            modelContext.insert(newStreakData)
            streakDataCache[userId] = newStreakData
            return newStreakData
        }
    }

    /// Determines if `newSession` date is the day immediately following `lastSession` date, ignoring time.
    /// - Parameters:
    ///   - lastSession: The date of the previous session.
    ///   - newSession: The date of the current session.
    /// - Returns: `true` if `newSession` is the consecutive day after `lastSession`, `false` otherwise.
    private func isConsecutiveDay(lastSession: Date, newSession: Date) -> Bool {
        let calendar = Calendar.current
        guard let dayAfterLastSession = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastSession)) else {
            return false
        }
        return calendar.isDate(newSession, inSameDayAs: dayAfterLastSession)
    }
}
