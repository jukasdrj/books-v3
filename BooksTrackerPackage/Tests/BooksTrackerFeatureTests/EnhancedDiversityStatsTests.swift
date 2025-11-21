import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("EnhancedDiversityStats Tests")
struct EnhancedDiversityStatsTests {

    @Test("Test individual completion percentages with full data")
    func testIndividualCompletionPercentagesFullData() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 10
        stats.booksWithCulturalData = 10
        stats.booksWithGenderData = 10
        stats.booksWithTranslationData = 10
        stats.booksWithOwnVoicesData = 10
        stats.booksWithAccessibilityData = 10

        #expect(stats.culturalCompletionPercentage == 100.0)
        #expect(stats.genderCompletionPercentage == 100.0)
        #expect(stats.translationCompletionPercentage == 100.0)
        #expect(stats.ownVoicesCompletionPercentage == 100.0)
        #expect(stats.accessibilityCompletionPercentage == 100.0)
    }

    @Test("Test individual completion percentages with partial data")
    func testIndividualCompletionPercentagesPartialData() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 10
        stats.booksWithCulturalData = 5
        stats.booksWithGenderData = 7
        stats.booksWithTranslationData = 0
        stats.booksWithOwnVoicesData = 10
        stats.booksWithAccessibilityData = 2

        #expect(stats.culturalCompletionPercentage == 50.0)
        #expect(stats.genderCompletionPercentage == 70.0)
        #expect(stats.translationCompletionPercentage == 0.0)
        #expect(stats.ownVoicesCompletionPercentage == 100.0)
        #expect(stats.accessibilityCompletionPercentage == 20.0)
    }

    @Test("Test individual completion percentages with zero total books")
    func testIndividualCompletionPercentagesZeroBooks() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 0
        stats.booksWithCulturalData = 0
        stats.booksWithGenderData = 0
        stats.booksWithTranslationData = 0
        stats.booksWithOwnVoicesData = 0
        stats.booksWithAccessibilityData = 0

        #expect(stats.culturalCompletionPercentage == 0.0)
        #expect(stats.genderCompletionPercentage == 0.0)
        #expect(stats.translationCompletionPercentage == 0.0)
        #expect(stats.ownVoicesCompletionPercentage == 0.0)
        #expect(stats.accessibilityCompletionPercentage == 0.0)
    }

    @Test("Test overall completion percentage with full data")
    func testOverallCompletionPercentageFullData() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 10
        stats.booksWithCulturalData = 10
        stats.booksWithGenderData = 10
        stats.booksWithTranslationData = 10
        stats.booksWithOwnVoicesData = 10
        stats.booksWithAccessibilityData = 10

        #expect(stats.overallCompletionPercentage == 100.0)
    }

    @Test("Test overall completion percentage with partial data")
    func testOverallCompletionPercentagePartialData() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 10 // 5 dimensions * 10 books = 50 total fields
        stats.booksWithCulturalData = 5
        stats.booksWithGenderData = 7
        stats.booksWithTranslationData = 0
        stats.booksWithOwnVoicesData = 10
        stats.booksWithAccessibilityData = 2

        // (5 + 7 + 0 + 10 + 2) / (10 * 5) * 100 = 24 / 50 * 100 = 48.0
        #expect(stats.overallCompletionPercentage == 48.0)
    }

    @Test("Test overall completion percentage with zero total books")
    func testOverallCompletionPercentageZeroBooks() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 0
        stats.booksWithCulturalData = 0
        stats.booksWithGenderData = 0
        stats.booksWithTranslationData = 0
        stats.booksWithOwnVoicesData = 0
        stats.booksWithAccessibilityData = 0

        #expect(stats.overallCompletionPercentage == 0.0)
    }

    @Test("Test overall completion percentage with some total books but no data filled")
    func testOverallCompletionPercentageNoDataFilled() throws {
        let stats = EnhancedDiversityStats(userId: "user1")
        stats.totalBooks = 5 // 5 dimensions * 5 books = 25 total fields
        stats.booksWithCulturalData = 0
        stats.booksWithGenderData = 0
        stats.booksWithTranslationData = 0
        stats.booksWithOwnVoicesData = 0
        stats.booksWithAccessibilityData = 0

        // 0 / (5 * 5) * 100 = 0.0
        #expect(stats.overallCompletionPercentage == 0.0)
    }
}
