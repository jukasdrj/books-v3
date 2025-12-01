import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("ReadingHabitsViewModel Tests")
struct ReadingHabitsViewModelTests {

    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Work.self, UserLibraryEntry.self, ReadingSession.self, Edition.self, Author.self, configurations: config)
        context = container.mainContext
    }

    @Test("Reading streak counts consecutive days correctly")
    func testStreakConsecutiveDays() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work

        // Create sessions: Today, Yesterday, Day before yesterday (Streak = 3)
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let s1 = ReadingSession(date: twoDaysAgo, durationMinutes: 10, startPage: 0, endPage: 10)
        let s2 = ReadingSession(date: yesterday, durationMinutes: 10, startPage: 10, endPage: 20)
        let s3 = ReadingSession(date: today, durationMinutes: 10, startPage: 20, endPage: 30)

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        entry.readingSessions = [s1, s2, s3]

        let viewModel = ReadingHabitsViewModel(work: work)

        #expect(viewModel.readingStreak == 3)
    }

    @Test("Reading streak counts midnight crossover as consecutive days")
    func testStreakMidnightCrossover() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work

        // Create sessions: Yesterday 23:30 and Today 00:30
        // These are consecutive days, but < 24 hours apart
        let calendar = Calendar.current
        let today = Date()

        // Ensure "Yesterday" is late
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.hour = 0
        components.minute = 30
        let todayEarly = calendar.date(from: components)! // Today 00:30

        let yesterdayLate = calendar.date(byAdding: .minute, value: -60, to: todayEarly)! // Yesterday 23:30

        let s1 = ReadingSession(date: yesterdayLate)
        let s2 = ReadingSession(date: todayEarly)

        context.insert(s1)
        context.insert(s2)
        entry.readingSessions = [s1, s2]

        let viewModel = ReadingHabitsViewModel(work: work)

        #expect(viewModel.readingStreak == 2)
    }

    @Test("Reading streak breaks on missing day")
    func testStreakBreak() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work

        // Create sessions: Today, Yesterday, GAP, 4 days ago
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today)!

        let s1 = ReadingSession(date: fourDaysAgo)
        let s2 = ReadingSession(date: yesterday)
        let s3 = ReadingSession(date: today)

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        entry.readingSessions = [s1, s2, s3]

        let viewModel = ReadingHabitsViewModel(work: work)

        // Today + Yesterday = 2. Break. 4 days ago ignored for streak.
        #expect(viewModel.readingStreak == 2)
    }

    @Test("Reading streak handles multiple sessions on same day")
    func testStreakSameDay() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work

        // Create sessions: Today (morning), Today (evening), Yesterday
        let calendar = Calendar.current
        let today = Date()

        // Construct dates to be sure they are same day
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.hour = 9
        let todayMorning = calendar.date(from: components)!

        components.hour = 20
        let todayEvening = calendar.date(from: components)!

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let s1 = ReadingSession(date: yesterday)
        let s2 = ReadingSession(date: todayMorning)
        let s3 = ReadingSession(date: todayEvening)

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        entry.readingSessions = [s1, s2, s3]

        let viewModel = ReadingHabitsViewModel(work: work)

        // Today (count as 1 day) + Yesterday = 2
        #expect(viewModel.readingStreak == 2)
    }

    @Test("Average pace calculation ignores zero duration sessions")
    func testAveragePace() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work

        // Session 1: 10 pages in 30 min (20 pages/hour)
        let s1 = ReadingSession(durationMinutes: 30, startPage: 0, endPage: 10)
        // Session 2: 20 pages in 30 min (40 pages/hour)
        let s2 = ReadingSession(durationMinutes: 30, startPage: 10, endPage: 30)
        // Session 3: 0 duration (ignored)
        let s3 = ReadingSession(durationMinutes: 0, startPage: 30, endPage: 40)
        // Session 4: 0 pages read (ignored)
        let s4 = ReadingSession(durationMinutes: 30, startPage: 40, endPage: 40)


        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        context.insert(s4)
        entry.readingSessions = [s1, s2, s3, s4]

        let viewModel = ReadingHabitsViewModel(work: work)

        // Total pages (valid): 10 + 20 = 30
        // Total minutes (valid): 30 + 30 = 60
        // Pace: 30 pages / 60 min * 60 = 30 pages/hour
        #expect(viewModel.averagePace == 30.0)
    }

    @Test("ViewModel handles empty sessions gracefully")
    func testEmptySessions() throws {
        let work = Work(title: "Test Book")
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work
        entry.readingSessions = []

        let viewModel = ReadingHabitsViewModel(work: work)

        #expect(viewModel.readingStreak == 0)
        #expect(viewModel.averagePace == nil)
    }
}
