import Testing
@testable import BooksTrackerFeature
import Foundation

@Suite("DiversityScore Tests")
struct DiversityScoreTests {

    @Test("Test DiversityScore with complete data")
    func testCompleteDataScoring() throws {
        let author = Author(name: "Author", gender: .female, culturalRegion: .africa)
        let work = Work(title: "Title", isOwnVoices: true, accessibilityTags: ["Dyslexia Friendly"])
        let edition = Edition(originalLanguage: "French")
        work.authors = [author]
        work.editions = [edition]

        let score = DiversityScore(work: work)

        #expect(score.metrics.count == 5)
        #expect(score.overallScore > 0.8) // Should be high
    }

    @Test("Test DiversityScore with missing data")
    func testMissingDataScoring() throws {
        let author = Author(name: "Author")
        let work = Work(title: "Title")
        work.authors = [author]

        let score = DiversityScore(work: work)

        #expect(score.metrics.allSatisfy { $0.value == nil })
        #expect(score.overallScore == 0.0)
    }

    @Test("Test DiversityScore with partial data")
    func testPartialDataScoring() throws {
        let author = Author(name: "Author", gender: .male)
        let work = Work(title: "Title")
        work.authors = [author]

        let score = DiversityScore(work: work)

        #expect(score.metrics.first(where: { $0.id == "gender" })?.value != nil)
        #expect(score.overallScore > 0.0 && score.overallScore < 0.3)
    }

    @Test("Test non-English original language score")
    func testTranslationScore() throws {
        let work = Work(title: "Title")
        let edition = Edition(originalLanguage: "Spanish")
        work.editions = [edition]

        let score = DiversityScore(work: work)

        #expect(score.metrics.first(where: { $0.id == "translation" })?.value == 1.0)
    }

    @Test("Test English original language score")
    func testEnglishTranslationScore() throws {
        let work = Work(title: "Title")
        let edition = Edition(originalLanguage: "English")
        work.editions = [edition]

        let score = DiversityScore(work: work)

        #expect(score.metrics.first(where: { $0.id == "translation" })?.value == 0.1)
    }
}
