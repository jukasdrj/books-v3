import Foundation
import SwiftData

@Observable
class ReadingHabitsViewModel {
    private var readingSessions: [ReadingSession]

    init(work: Work) {
        // Sort sessions by date for accurate streak calculation
        self.readingSessions = work.userLibraryEntries?.first?.readingSessions.sorted { $0.date < $1.date } ?? []
    }

    /// Calculates the average reading pace in pages per hour.
    var averagePace: Double? {
        let validSessions = readingSessions.filter { $0.durationMinutes > 0 && $0.pagesRead > 0 }
        guard !validSessions.isEmpty else { return nil }

        let totalPagesRead = validSessions.reduce(0) { $0 + $1.pagesRead }
        let totalMinutesRead = validSessions.reduce(0) { $0 + $1.durationMinutes }

        guard totalMinutesRead > 0 else { return nil }

        return (Double(totalPagesRead) / Double(totalMinutesRead)) * 60.0
    }

    /// Calculates the current reading streak in days.
    var readingStreak: Int {
        guard !readingSessions.isEmpty else { return 0 }

        var streak = 1
        var lastDate = readingSessions.last!.date

        for session in readingSessions.reversed().dropFirst() {
            if let days = Calendar.current.dateComponents([.day], from: session.date, to: lastDate).day, days == 1 {
                streak += 1
                lastDate = session.date
            } else if !Calendar.current.isDate(session.date, inSameDayAs: lastDate) {
                break
            }
        }

        return streak
    }
}
