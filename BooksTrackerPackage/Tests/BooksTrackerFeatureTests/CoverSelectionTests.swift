import Testing
@testable import BooksTrackerFeature

@Suite("Cover Selection Quality Scoring")
struct CoverSelectionTests {

    @Test("Edition with cover scores higher than edition without cover")
    func coverAvailabilityScoring() async throws {
        let work = Work(title: "Test Book")

        let noCover = Edition(
            publicationDate: "2023",
            format: .hardcover,
            coverImageURL: nil
        )

        let hasCover = Edition(
            publicationDate: "2020",
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/b/id/12345-L.jpg"
        )

        work.editions = [noCover, hasCover]

        // hasCover should win despite being older (cover = +10 points)
        #expect(work.primaryEdition?.id == hasCover.id)
    }

    @Test("Hardcover preferred over paperback when both have covers")
    func formatPreferenceScoring() async throws {
        let work = Work(title: "Test Book")

        let paperback = Edition(
            publicationDate: "2023",
            format: .paperback,
            coverImageURL: "https://covers.openlibrary.org/a.jpg"
        )

        let hardcover = Edition(
            publicationDate: "2023",
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/b.jpg"
        )

        work.editions = [paperback, hardcover]

        // Hardcover wins (+3 vs +2 format bonus)
        #expect(work.primaryEdition?.format == .hardcover)
    }

    @Test("Recent publication preferred when other factors equal")
    func recencyScoring() async throws {
        let work = Work(title: "Test Book")

        let vintage = Edition(
            publicationDate: "1960",
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/a.jpg"
        )

        let modern = Edition(
            publicationDate: "2023",
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/b.jpg"
        )

        work.editions = [vintage, modern]

        // Modern wins due to recency scoring (+23 vs +0)
        #expect(work.primaryEdition?.publicationDate == "2023")
    }

    @Test("User's owned edition always takes priority")
    func userEditionPriority() async throws {
        let work = Work(title: "Test Book")

        let poorEdition = Edition(
            publicationDate: "1960",
            format: .paperback,
            coverImageURL: nil  // No cover
        )

        let betterEdition = Edition(
            publicationDate: "2023",
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/b.jpg"
        )

        work.editions = [poorEdition, betterEdition]

        // Create user entry with poor edition
        let userEntry = UserLibraryEntry(readingStatus: .read)
        userEntry.work = work
        userEntry.edition = poorEdition
        work.userLibraryEntries = [userEntry]

        // User's edition wins despite terrible score
        #expect(work.primaryEdition?.id == poorEdition.id)
    }
}

@Suite("Cover Selection Strategies")
struct CoverSelectionStrategyTests {

    @Test("Auto strategy uses quality scoring")
    func autoStrategy() async throws {
        let work = Work(title: "Test Book")
        work.editions = [
            Edition(publicationDate: "2020", format: .paperback, coverImageURL: "url1"),
            Edition(publicationDate: "2024", format: .hardcover, coverImageURL: "url2")
        ]

        // Auto strategy uses quality-based algorithm (recency + format + provider)
        // 2024 hardcover should win due to recency and format
        #expect(work.primaryEdition(using: .auto)?.publicationDate == "2024")
    }

    @Test("Recent strategy selects most recent publication")
    func recentStrategy() async throws {
        let work = Work(title: "Test Book")
        work.editions = [
            Edition(publicationDate: "2020", format: .hardcover),
            Edition(publicationDate: "2024", format: .paperback),
            Edition(publicationDate: "1990", format: .hardcover)
        ]

        #expect(work.primaryEdition(using: .recent)?.publicationDate == "2024")
    }

    @Test("Hardcover strategy prioritizes hardcover editions")
    func hardcoverStrategy() async throws {
        let work = Work(title: "Test Book")
        work.editions = [
            Edition(publicationDate: "2024", format: .paperback),
            Edition(publicationDate: "2020", format: .hardcover)
        ]

        #expect(work.primaryEdition(using: .hardcover)?.format == .hardcover)
    }

    @Test("Manual strategy falls back to quality scoring")
    func manualStrategy() async throws {
        let work = Work(title: "Test Book")
        let oldEdition = Edition(publicationDate: "1990")
        let recentEdition = Edition(publicationDate: "2023")
        work.editions = [
            oldEdition,
            recentEdition
        ]

        // Without a preferred edition, manual strategy falls back to quality scoring
        // 2023 edition will have higher score due to recency
        #expect(work.primaryEdition(using: .manual)?.id == recentEdition.id)
    }
}

@Suite("Cover Selection Persistence")
struct CoverSelectionPersistenceTests {

    @Test("Strategy persists across FeatureFlags instances")
    func strategyPersistence() async throws {
        let flags1 = FeatureFlags.shared
        flags1.coverSelectionStrategy = .recent

        // Simulate app restart
        let flags2 = FeatureFlags.shared

        #expect(flags2.coverSelectionStrategy == .recent)

        // Cleanup
        flags1.resetToDefaults()
    }

    @Test("Reset to defaults restores auto strategy")
    func resetToDefaults() async throws {
        let flags = FeatureFlags.shared
        flags.coverSelectionStrategy = .hardcover

        flags.resetToDefaults()

        #expect(flags.coverSelectionStrategy == .auto)
    }
}

@Suite("Cover Selection Edge Cases")
struct CoverSelectionEdgeCaseTests {

    @Test("Work with no editions returns nil")
    func noEditions() async throws {
        let work = Work(title: "Test Book")
        work.editions = []

        #expect(work.primaryEdition == nil)
    }

    @Test("Work with single edition returns that edition")
    func singleEdition() async throws {
        let work = Work(title: "Test Book")
        let edition = Edition(publicationDate: "2023")
        work.editions = [edition]

        #expect(work.primaryEdition?.id == edition.id)
    }

    @Test("All editions lack covers, selects best by other factors")
    func allEditionsNoCover() async throws {
        let work = Work(title: "Test Book")
        work.editions = [
            Edition(publicationDate: "2020", format: .paperback),
            Edition(publicationDate: "2023", format: .hardcover)
        ]

        // Should select hardcover despite no covers
        #expect(work.primaryEdition?.format == .hardcover)
    }

    @Test("Unparseable publication dates handle gracefully")
    func invalidPublicationDates() async throws {
        let work = Work(title: "Test Book")
        work.editions = [
            Edition(publicationDate: "invalid", format: .hardcover),
            Edition(publicationDate: "", format: .paperback),
            Edition(publicationDate: nil, format: .ebook)
        ]

        // Should not crash, return some edition
        #expect(work.primaryEdition != nil)
    }
}
