import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("SessionAnalyticsService Tests")
struct SessionAnalyticsServiceTests {

    /// Helper to set up the test environment with a fresh ModelContext and service
    private func setupService() throws -> (ModelContext, SessionAnalyticsService) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ReadingSession.self, StreakData.self,
            configurations: config
        )
        let context = ModelContext(container)
        let service = SessionAnalyticsService(modelContext: context)
        return (context, service)
    }

    @Test("First session starts streak at 1")
    func testFirstSessionStartsStreak() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"
        let sessionDate = Date()
        let session = ReadingSession(
            date: sessionDate,
            durationMinutes: 30,
            startPage: 10,
            endPage: 40
        )
        context.insert(session)
        try context.save()

        // When
        try await service.updateStreakForSession(userId: userId, session: session)

        // Then
        let streakData = try service.fetchStreakData(userId: userId)
        #expect(streakData.currentStreak == 1)
        #expect(streakData.longestStreak == 1)
        #expect(streakData.totalSessions == 1)
        #expect(streakData.totalMinutesRead == 30)
    }

    @Test("Consecutive day sessions increment streak")
    func testConsecutiveDaySessionsIncrementStreak() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"

        let day1 = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let session1 = ReadingSession(date: day1, durationMinutes: 30, startPage: 10, endPage: 40)
        context.insert(session1)
        try await service.updateStreakForSession(userId: userId, session: session1)

        // When
        let day2 = Date()
        let session2 = ReadingSession(date: day2, durationMinutes: 45, startPage: 41, endPage: 86)
        context.insert(session2)
        try await service.updateStreakForSession(userId: userId, session: session2)

        // Then
        let streakData = try service.fetchStreakData(userId: userId)
        #expect(streakData.currentStreak == 2)
        #expect(streakData.longestStreak == 2)
        #expect(streakData.totalSessions == 2)
        #expect(streakData.totalMinutesRead == 75)
    }

    @Test("Non-consecutive day breaks streak")
    func testNonConsecutiveDayBreaksStreak() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"

        let day1 = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session1 = ReadingSession(date: day1, durationMinutes: 30, startPage: 10, endPage: 40)
        context.insert(session1)
        try await service.updateStreakForSession(userId: userId, session: session1)

        // When (skip day2, so day3 is non-consecutive)
        let day3 = Date()
        let session2 = ReadingSession(date: day3, durationMinutes: 20, startPage: 41, endPage: 61)
        context.insert(session2)
        try await service.updateStreakForSession(userId: userId, session: session2)

        // Then
        let streakData = try service.fetchStreakData(userId: userId)
        #expect(streakData.currentStreak == 1) // Streak resets to 1
        #expect(streakData.longestStreak == 1)
        #expect(streakData.streakBrokenCount == 1)
        #expect(streakData.totalSessions == 2)
    }

    @Test("Multiple sessions same day don't increment streak")
    func testMultipleSessionsSameDayNoIncrement() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"

        let day1 = Date()
        let session1 = ReadingSession(date: day1, durationMinutes: 30, startPage: 10, endPage: 40)
        context.insert(session1)
        try await service.updateStreakForSession(userId: userId, session: session1)

        // When (second session same day)
        let session2 = ReadingSession(
            date: day1.addingTimeInterval(3600), // 1 hour later, same day
            durationMinutes: 20,
            startPage: 41,
            endPage: 61
        )
        context.insert(session2)
        try await service.updateStreakForSession(userId: userId, session: session2)

        // Then
        let streakData = try service.fetchStreakData(userId: userId)
        #expect(streakData.currentStreak == 1) // Streak stays at 1
        #expect(streakData.longestStreak == 1)
        #expect(streakData.totalSessions == 2) // But sessions count increases
        #expect(streakData.totalMinutesRead == 50)
    }

    @Test("Longest streak tracked correctly")
    func testLongestStreakTracking() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"

        // Build a 3-day streak
        let day1 = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let session1 = ReadingSession(date: day1, durationMinutes: 10, startPage: 1, endPage: 11)
        context.insert(session1)
        try await service.updateStreakForSession(userId: userId, session: session1)

        let day2 = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let session2 = ReadingSession(date: day2, durationMinutes: 10, startPage: 12, endPage: 22)
        context.insert(session2)
        try await service.updateStreakForSession(userId: userId, session: session2)

        let day3 = Date()
        let session3 = ReadingSession(date: day3, durationMinutes: 10, startPage: 23, endPage: 33)
        context.insert(session3)
        try await service.updateStreakForSession(userId: userId, session: session3)

        // Then
        let streakData = try service.fetchStreakData(userId: userId)
        #expect(streakData.currentStreak == 3)
        #expect(streakData.longestStreak == 3)
    }

    @Test("Average pages per hour calculated correctly")
    func testAveragePagesPerHour() async throws {
        // Given
        let (context, service) = try setupService()
        let userId = "test-user"

        // Session 1: 30 pages in 30 minutes (60 pages/hour)
        let session1 = ReadingSession(date: Date(), durationMinutes: 30, startPage: 10, endPage: 40)
        context.insert(session1)

        // Session 2: 20 pages in 15 minutes (80 pages/hour)
        let session2 = ReadingSession(
            date: Date().addingTimeInterval(-7200),
            durationMinutes: 15,
            startPage: 50,
            endPage: 70
        )
        context.insert(session2)

        // Session 3: 50 pages in 60 minutes (50 pages/hour)
        let session3 = ReadingSession(
            date: Date().addingTimeInterval(-14400),
            durationMinutes: 60,
            startPage: 100,
            endPage: 150
        )
        context.insert(session3)

        try context.save()

        // When
        let average = try await service.calculateAveragePagesPerHour(userId: userId)

        // Then
        // Total pages: 30 + 20 + 50 = 100
        // Total minutes: 30 + 15 + 60 = 105
        // Total hours: 105 / 60 = 1.75
        // Average: 100 / 1.75 = 57.14...
        let expectedAverage = 100.0 / (105.0 / 60.0)
        #expect(abs(average - expectedAverage) < 0.01)
    }

    @Test("Average pages per hour for no sessions returns zero")
    func testAveragePagesPerHourNoSessions() async throws {
        // Given
        let (_, service) = try setupService()
        let userId = "test-user"

        // When
        let average = try await service.calculateAveragePagesPerHour(userId: userId)

        // Then
        #expect(average == 0.0)
    }

    @Test("isOnStreak computed property - today's session")
    func testIsOnStreakToday() throws {
        // Given
        let userId = "test-user"
        let streakData = StreakData(
            userId: userId,
            currentStreak: 5,
            longestStreak: 10,
            lastSessionDate: Date() // Today
        )

        // Then
        #expect(streakData.isOnStreak == true)
    }

    @Test("isOnStreak computed property - yesterday's session")
    func testIsOnStreakYesterday() throws {
        // Given
        let userId = "test-user"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let streakData = StreakData(
            userId: userId,
            currentStreak: 5,
            longestStreak: 10,
            lastSessionDate: yesterday
        )

        // Then
        #expect(streakData.isOnStreak == true)
    }

    @Test("isOnStreak computed property - two days ago (broken)")
    func testIsOnStreakBroken() throws {
        // Given
        let userId = "test-user"
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let streakData = StreakData(
            userId: userId,
            currentStreak: 0,
            longestStreak: 10,
            lastSessionDate: twoDaysAgo
        )

        // Then
        #expect(streakData.isOnStreak == false)
    }
}
