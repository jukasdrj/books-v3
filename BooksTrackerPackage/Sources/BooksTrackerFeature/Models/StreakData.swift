import Foundation
import SwiftData

/// `StreakData` tracks reading streaks and other session analytics for a user.
@Model
public final class StreakData {
    /// A unique identifier for the user.
    public var userId: String?

    /// The current number of consecutive days with reading sessions.
    public var currentStreak: Int = 0

    /// The longest streak achieved by the user.
    public var longestStreak: Int = 0

    /// The date of the last recorded reading session.
    public var lastSessionDate: Date = Date()

    /// The total number of reading sessions recorded for the user.
    public var totalSessions: Int = 0

    /// The total number of minutes the user has read across all sessions.
    public var totalMinutesRead: Int = 0

    /// The average number of pages read per hour across all sessions.
    public var averagePagesPerHour: Double = 0.0

    /// The number of reading sessions completed this calendar week.
    public var sessionsThisWeek: Int = 0

    /// The number of reading sessions completed this calendar month.
    public var sessionsThisMonth: Int = 0

    /// The count of how many times the user's streak has been broken.
    public var streakBrokenCount: Int = 0

    /// The date when the streak data was last calculated or updated.
    public var lastCalculated: Date = Date()

    /// A computed property indicating whether the user is currently on an active streak.
    /// A streak is considered active if the last session was either today or yesterday.
    public var isOnStreak: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastSessionDay = calendar.startOfDay(for: lastSessionDate)

        // Check if the last session was today
        if lastSessionDay == today {
            return true
        }

        // Check if the last session was yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           lastSessionDay == yesterday {
            return true
        }

        return false
    }

    /// Initializes a new `StreakData` instance.
    /// - Parameters:
    ///   - userId: The unique ID of the user.
    ///   - currentStreak: Initial current streak (defaults to 0).
    ///   - longestStreak: Initial longest streak (defaults to 0).
    ///   - lastSessionDate: The date of the last session (defaults to `Date.distantPast` for no prior sessions).
    ///   - totalSessions: Initial total sessions (defaults to 0).
    ///   - totalMinutesRead: Initial total minutes read (defaults to 0).
    ///   - averagePagesPerHour: Initial average pages per hour (defaults to 0.0).
    ///   - sessionsThisWeek: Initial sessions this week (defaults to 0).
    ///   - sessionsThisMonth: Initial sessions this month (defaults to 0).
    ///   - streakBrokenCount: Initial streak broken count (defaults to 0).
    ///   - lastCalculated: The date of last calculation (defaults to the current date).
    public init(userId: String? = nil,
         currentStreak: Int = 0,
         longestStreak: Int = 0,
         lastSessionDate: Date = Date(),
         totalSessions: Int = 0,
         totalMinutesRead: Int = 0,
         averagePagesPerHour: Double = 0.0,
         sessionsThisWeek: Int = 0,
         sessionsThisMonth: Int = 0,
         streakBrokenCount: Int = 0,
         lastCalculated: Date = Date()) {
        self.userId = userId
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastSessionDate = lastSessionDate
        self.totalSessions = totalSessions
        self.totalMinutesRead = totalMinutesRead
        self.averagePagesPerHour = averagePagesPerHour
        self.sessionsThisWeek = sessionsThisWeek
        self.sessionsThisMonth = sessionsThisMonth
        self.streakBrokenCount = streakBrokenCount
        self.lastCalculated = lastCalculated
    }
}
