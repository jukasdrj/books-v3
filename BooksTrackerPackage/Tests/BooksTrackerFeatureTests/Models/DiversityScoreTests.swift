//
//  DiversityScoreTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for DiversityScore model including all metric calculations
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("DiversityScore Tests")
@MainActor
struct DiversityScoreTests {

    // MARK: - Helper

    private func makeTestContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - Complete Data Scoring

    @Test func completeDataScoring() throws {
        let context = try makeTestContext()

        // Create author with complete diversity data
        let author = Author(
            name: "Chimamanda Ngozi Adichie",
            nationality: "Nigerian",
            gender: .female,
            culturalRegion: .africa
        )
        context.insert(author)

        // Create edition with non-English language
        let edition = Edition()
        edition.originalLanguage = "Igbo"
        context.insert(edition)

        // Create work with complete diversity metadata
        let work = Work(title: "Americanah")
        work.authors = [author]
        work.editions = [edition]
        work.isOwnVoices = true
        work.accessibilityTags = ["dyslexia-friendly", "audiobook"]
        context.insert(work)

        try context.save()

        // Calculate diversity score
        let score = DiversityScore(work: work)

        // Verify all metrics are present
        #expect(score.metrics.count == 5)
        #expect(score.hasAnyData == true)

        // Verify individual metrics
        let culturalMetric = score.metrics.first { $0.axis == .cultural }
        #expect(culturalMetric?.isMissing == false)
        #expect(culturalMetric?.score == 1.0) // Africa is marginalized region

        let genderMetric = score.metrics.first { $0.axis == .gender }
        #expect(genderMetric?.isMissing == false)
        #expect(genderMetric?.score == 1.0) // Female author

        let translationMetric = score.metrics.first { $0.axis == .translation }
        #expect(translationMetric?.isMissing == false)
        #expect(translationMetric?.score == 1.0) // Non-English language

        let ownVoicesMetric = score.metrics.first { $0.axis == .ownVoices }
        #expect(ownVoicesMetric?.isMissing == false)
        #expect(ownVoicesMetric?.score == 1.0) // Own voices true

        let accessibilityMetric = score.metrics.first { $0.axis == .accessibility }
        #expect(accessibilityMetric?.isMissing == false)
        #expect(accessibilityMetric?.score == 1.0) // Has dyslexia-friendly tag

        // Verify overall score is high
        #expect(score.overallScore > 0.8)
    }

    // MARK: - Missing Data Handling

    @Test func missingDataHandling() throws {
        let context = try makeTestContext()

        // Create work with no diversity data
        let work = Work(title: "Anonymous Book")
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)

        // Verify all metrics show missing data
        #expect(score.metrics.count == 5)
        #expect(score.hasAnyData == false)

        for metric in score.metrics {
            #expect(metric.isMissing == true)
            #expect(metric.score == 0.0)
        }

        // Verify overall score is 0.0 when all data missing
        #expect(score.overallScore == 0.0)
    }

    // MARK: - Partial Data Scoring

    @Test func partialDataScoring() throws {
        let context = try makeTestContext()

        // Create author with only gender data
        let author = Author(
            name: "Virginia Woolf",
            gender: .female
        )
        context.insert(author)

        let work = Work(title: "Mrs Dalloway")
        work.authors = [author]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)

        // Only gender metric should have data
        let genderMetric = score.metrics.first { $0.axis == .gender }
        #expect(genderMetric?.isMissing == false)
        #expect(genderMetric?.score == 1.0)

        // Other metrics should be missing
        let culturalMetric = score.metrics.first { $0.axis == .cultural }
        #expect(culturalMetric?.isMissing == true)

        let translationMetric = score.metrics.first { $0.axis == .translation }
        #expect(translationMetric?.isMissing == true)

        let ownVoicesMetric = score.metrics.first { $0.axis == .ownVoices }
        #expect(ownVoicesMetric?.isMissing == true)

        let accessibilityMetric = score.metrics.first { $0.axis == .accessibility }
        #expect(accessibilityMetric?.isMissing == true)

        // Overall score should only count gender metric
        #expect(score.overallScore == 1.0)
        #expect(score.hasAnyData == true)
    }

    // MARK: - Translation Scoring

    @Test func translationScoringNonEnglish() throws {
        let context = try makeTestContext()

        let edition = Edition()
        edition.originalLanguage = "French"
        context.insert(edition)

        let work = Work(title: "L'Étranger")
        work.editions = [edition]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let translationMetric = score.metrics.first { $0.axis == .translation }

        #expect(translationMetric?.isMissing == false)
        #expect(translationMetric?.score == 1.0) // Non-English scores 1.0
    }

    @Test func translationScoringEnglish() throws {
        let context = try makeTestContext()

        let edition = Edition()
        edition.originalLanguage = "English"
        context.insert(edition)

        let work = Work(title: "The Great Gatsby")
        work.editions = [edition]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let translationMetric = score.metrics.first { $0.axis == .translation }

        #expect(translationMetric?.isMissing == false)
        #expect(translationMetric?.score == 0.1) // English scores 0.1
    }

    @Test func translationScoringCaseInsensitive() throws {
        let context = try makeTestContext()

        let edition = Edition()
        edition.originalLanguage = "ENGLISH" // Uppercase
        context.insert(edition)

        let work = Work(title: "Test Book")
        work.editions = [edition]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let translationMetric = score.metrics.first { $0.axis == .translation }

        #expect(translationMetric?.score == 0.1) // Should handle case-insensitive comparison
    }

    // MARK: - Cultural Region Scoring

    @Test func culturalRegionMarginalizedScore() throws {
        let context = try makeTestContext()

        let marginalizedRegions: [CulturalRegion] = [
            .africa, .asia, .southAmerica, .middleEast,
            .caribbean, .centralAsia, .indigenous
        ]

        for region in marginalizedRegions {
            let author = Author(name: "Test Author", culturalRegion: region)
            context.insert(author)

            let work = Work(title: "Test Book \(region.rawValue)")
            work.authors = [author]
            context.insert(work)

            let score = DiversityScore(work: work)
            let culturalMetric = score.metrics.first { $0.axis == .cultural }

            #expect(culturalMetric?.isMissing == false)
            #expect(culturalMetric?.score == 1.0, "Region \(region.rawValue) should score 1.0")
        }
    }

    @Test func culturalRegionWesternScore() throws {
        let context = try makeTestContext()

        let westernRegions: [CulturalRegion] = [
            .europe, .northAmerica, .oceania, .international
        ]

        for region in westernRegions {
            let author = Author(name: "Test Author", culturalRegion: region)
            context.insert(author)

            let work = Work(title: "Test Book \(region.rawValue)")
            work.authors = [author]
            context.insert(work)

            let score = DiversityScore(work: work)
            let culturalMetric = score.metrics.first { $0.axis == .cultural }

            #expect(culturalMetric?.isMissing == false)
            #expect(culturalMetric?.score == 0.2, "Region \(region.rawValue) should score 0.2")
        }
    }

    // MARK: - Gender Scoring

    @Test func genderScoringNonMale() throws {
        let context = try makeTestContext()

        let nonMaleGenders: [AuthorGender] = [.female, .nonBinary, .other]

        for gender in nonMaleGenders {
            let author = Author(name: "Test Author", gender: gender)
            context.insert(author)

            let work = Work(title: "Test Book \(gender.rawValue)")
            work.authors = [author]
            context.insert(work)

            let score = DiversityScore(work: work)
            let genderMetric = score.metrics.first { $0.axis == .gender }

            #expect(genderMetric?.isMissing == false)
            #expect(genderMetric?.score == 1.0, "Gender \(gender.rawValue) should score 1.0")
        }
    }

    @Test func genderScoringMale() throws {
        let context = try makeTestContext()

        let author = Author(name: "Test Author", gender: .male)
        context.insert(author)

        let work = Work(title: "Test Book")
        work.authors = [author]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let genderMetric = score.metrics.first { $0.axis == .gender }

        #expect(genderMetric?.isMissing == false)
        #expect(genderMetric?.score == 0.2) // Male scores 0.2
    }

    @Test func genderScoringUnknown() throws {
        let context = try makeTestContext()

        let author = Author(name: "Test Author", gender: .unknown)
        context.insert(author)

        let work = Work(title: "Test Book")
        work.authors = [author]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let genderMetric = score.metrics.first { $0.axis == .gender }

        #expect(genderMetric?.isMissing == true) // Unknown is treated as missing data
        #expect(genderMetric?.score == 0.0)
    }

    // MARK: - Accessibility Scoring

    @Test func accessibilityScoringDyslexiaFriendly() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.accessibilityTags = ["dyslexia-friendly font", "audiobook"]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let accessibilityMetric = score.metrics.first { $0.axis == .accessibility }

        #expect(accessibilityMetric?.isMissing == false)
        #expect(accessibilityMetric?.score == 1.0) // Dyslexia tag scores 1.0
    }

    @Test func accessibilityScoringOtherFeatures() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.accessibilityTags = ["large-print", "audiobook"]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let accessibilityMetric = score.metrics.first { $0.axis == .accessibility }

        #expect(accessibilityMetric?.isMissing == false)
        #expect(accessibilityMetric?.score == 0.5) // Non-dyslexia tags score 0.5
    }

    @Test func accessibilityScoringEmptyTags() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.accessibilityTags = [] // Empty tags
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let accessibilityMetric = score.metrics.first { $0.axis == .accessibility }

        #expect(accessibilityMetric?.isMissing == true) // Empty tags treated as missing
        #expect(accessibilityMetric?.score == 0.0)
    }

    // MARK: - Own Voices Scoring

    @Test func ownVoicesScoringTrue() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.isOwnVoices = true
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let ownVoicesMetric = score.metrics.first { $0.axis == .ownVoices }

        #expect(ownVoicesMetric?.isMissing == false)
        #expect(ownVoicesMetric?.score == 1.0)
    }

    @Test func ownVoicesScoringFalse() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.isOwnVoices = false
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let ownVoicesMetric = score.metrics.first { $0.axis == .ownVoices }

        #expect(ownVoicesMetric?.isMissing == false)
        #expect(ownVoicesMetric?.score == 0.0)
    }

    @Test func ownVoicesScoringNil() throws {
        let context = try makeTestContext()

        let work = Work(title: "Test Book")
        work.isOwnVoices = nil
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)
        let ownVoicesMetric = score.metrics.first { $0.axis == .ownVoices }

        #expect(ownVoicesMetric?.isMissing == true)
        #expect(ownVoicesMetric?.score == 0.0)
    }

    // MARK: - Overall Score Calculation

    @Test func overallScoreAveragesNonMissingMetrics() throws {
        let context = try makeTestContext()

        let author = Author(name: "Test Author", gender: .female)
        context.insert(author)

        let edition = Edition()
        edition.originalLanguage = "French"
        context.insert(edition)

        let work = Work(title: "Test Book")
        work.authors = [author]
        work.editions = [edition]
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)

        // Only gender (1.0) and translation (1.0) have data
        // Overall should be (1.0 + 1.0) / 2 = 1.0
        #expect(score.overallScore == 1.0)
    }

    @Test func overallScoreWithMixedValues() throws {
        let context = try makeTestContext()

        let author = Author(name: "Test Author", gender: .male, culturalRegion: .europe)
        context.insert(author)

        let edition = Edition()
        edition.originalLanguage = "English"
        context.insert(edition)

        let work = Work(title: "Test Book")
        work.authors = [author]
        work.editions = [edition]
        work.isOwnVoices = false
        context.insert(work)
        try context.save()

        let score = DiversityScore(work: work)

        // Gender: 0.2, Cultural: 0.2, Translation: 0.1, Own Voices: 0.0
        // Overall: (0.2 + 0.2 + 0.1 + 0.0) / 4 = 0.125
        #expect(score.overallScore == 0.125)
    }
}
