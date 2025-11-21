import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("ReadingSession Tests")
struct ReadingSessionTests {

    @Test("Test pagesRead computed property - positive pages")
    func testPagesReadPositive() throws {
        let session = ReadingSession(startPage: 10, endPage: 20)
        #expect(session.pagesRead == 10)
    }

    @Test("Test pagesRead computed property - zero pages")
    func testPagesReadZero() throws {
        let session = ReadingSession(startPage: 10, endPage: 10)
        #expect(session.pagesRead == 0)
    }

    @Test("Test pagesRead computed property - negative pages (end < start)")
    func testPagesReadNegative() throws {
        let session = ReadingSession(startPage: 20, endPage: 10)
        // Should return 0 due to max(0, ...)
        #expect(session.pagesRead == 0)
    }

    @Test("Test readingPace computed property - valid pace")
    func testReadingPaceValid() throws {
        // 10 pages in 30 minutes = 20 pages/hour
        let session = ReadingSession(durationMinutes: 30, startPage: 10, endPage: 20)
        #expect(session.readingPace == 20.0)
    }

    @Test("Test readingPace computed property - zero duration")
    func testReadingPaceZeroDuration() throws {
        let session = ReadingSession(durationMinutes: 0, startPage: 10, endPage: 20)
        // Should return nil if duration is 0
        #expect(session.readingPace == nil)
    }

    @Test("Test readingPace computed property - zero pages read, positive duration")
    func testReadingPaceZeroPages() throws {
        // 0 pages in 60 minutes = 0 pages/hour
        let session = ReadingSession(durationMinutes: 60, startPage: 10, endPage: 10)
        #expect(session.readingPace == 0.0)
    }

    @Test("Test readingPace computed property - negative duration (should not happen, but defensive)")
    func testReadingPaceNegativeDuration() throws {
        let session = ReadingSession(durationMinutes: -10, startPage: 10, endPage: 20)
        // Guard statement handles durationMinutes <= 0, so it should be nil
        #expect(session.readingPace == nil)
    }

    @Test("Test initializer defaults")
    func testInitializerDefaults() throws {
        let session = ReadingSession()
        #expect(session.durationMinutes == 0)
        #expect(session.startPage == 0)
        #expect(session.endPage == 0)
        #expect(session.enrichmentPromptShown == false)
        #expect(session.enrichmentCompleted == false)
        // Date is initialized to Date(), so we can't assert an exact value, but it should be close to now.
        #expect(abs(session.date.timeIntervalSinceNow) < 5) // Within 5 seconds of now
    }
}
