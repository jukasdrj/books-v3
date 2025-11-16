//
//  CoverImageServiceTests.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test suite for CoverImageService fallback logic
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for CoverImageService cover URL resolution with Edition → Work fallback.
///
/// **Test Coverage:**
/// - Primary edition cover URL resolution
/// - Work-level fallback when edition lacks cover
/// - Specific edition with work fallback
/// - Edge cases (nil URLs, empty strings, missing editions)
/// - Diagnostic helpers (coverSource, hasCover)
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `CoverImageService.swift`
/// - SeeAlso: `docs/architecture/2025-11-09-cover-image-display-bug-analysis.md`
@Suite("CoverImageService Tests")
@MainActor
struct CoverImageServiceTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        // Create in-memory container for testing
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
    }

    // MARK: - Primary Edition Cover Tests

    @Test("Returns primary edition cover URL when available")
    func primaryEditionCoverURL() throws {
        // Create work and edition with cover
        let work = Work(title: "Test Book")
        let edition = Edition(
            isbn: "1234567890123",
            coverImageURL: "https://example.com/cover.jpg"
        )

        modelContext.insert(work)
        modelContext.insert(edition)

        // Set up relationship (insert-before-relate pattern)
        edition.work = work
        try modelContext.save()

        // Manually set primary edition (AutoStrategy would normally do this)
        work.manuallySelectedEdition = edition

        // Test
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL != nil, "Should return edition cover URL")
        #expect(coverURL?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test("Falls back to Work cover when primary edition has no cover")
    func workLevelFallback() throws {
        // Create work with cover at work-level
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        // Create edition WITHOUT cover
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test - should fall back to work-level cover
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL != nil, "Should return work-level fallback cover")
        #expect(coverURL?.absoluteString == "https://example.com/work-cover.jpg")
    }

    @Test("Returns nil when no cover available at any level")
    func noCoverAvailable() throws {
        // Create work and edition without covers
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL == nil, "Should return nil when no cover exists")
    }

    @Test("Returns nil when work has no editions")
    func noEditions() {
        // Create work without any editions
        let work = Work(title: "Test Book")
        modelContext.insert(work)

        // Test
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL == nil, "Should return nil when work has no editions")
    }

    @Test("Handles empty cover URL string gracefully")
    func emptyCoverURLString() throws {
        // Create work with empty cover URL string
        let work = Work(title: "Test Book")
        work.coverImageURL = ""  // Empty string (not nil)

        let edition = Edition(isbn: "1234567890123")
        edition.coverImageURL = ""  // Empty string

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL == nil, "Should return nil for empty cover URL strings")
    }

    @Test("Handles malformed URL strings gracefully")
    func malformedURLString() throws {
        // Create work with invalid URL
        let work = Work(title: "Test Book")
        work.coverImageURL = "not a valid url!!!"

        modelContext.insert(work)

        // Test - should handle gracefully (URL initializer returns nil)
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL == nil, "Should return nil for malformed URLs")
    }

    // MARK: - Specific Edition Cover Tests

    @Test("Returns specific edition cover when provided")
    func specificEditionCover() throws {
        // Create work and multiple editions
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        let edition1 = Edition(
            isbn: "1111111111111",
            coverImageURL: "https://example.com/edition1-cover.jpg"
        )
        let edition2 = Edition(
            isbn: "2222222222222",
            coverImageURL: "https://example.com/edition2-cover.jpg"
        )

        modelContext.insert(work)
        modelContext.insert(edition1)
        modelContext.insert(edition2)

        edition1.work = work
        edition2.work = work
        try modelContext.save()

        // Test - should use specific edition (edition2)
        let coverURL = CoverImageService.coverURL(for: edition2, work: work)

        #expect(coverURL != nil)
        #expect(coverURL?.absoluteString == "https://example.com/edition2-cover.jpg")
    }

    @Test("Falls back to work when specific edition has no cover")
    func specificEditionFallbackToWork() throws {
        // Create work with cover
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        // Create edition WITHOUT cover
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        // Test - should fall back to work-level cover
        let coverURL = CoverImageService.coverURL(for: edition, work: work)

        #expect(coverURL != nil)
        #expect(coverURL?.absoluteString == "https://example.com/work-cover.jpg")
    }

    @Test("Handles nil specific edition gracefully")
    func nilSpecificEdition() throws {
        // Create work with cover
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        modelContext.insert(work)

        // Test with nil edition - should fall back to work logic
        let coverURL = CoverImageService.coverURL(for: nil, work: work)

        #expect(coverURL != nil)
        #expect(coverURL?.absoluteString == "https://example.com/work-cover.jpg")
    }

    // MARK: - Diagnostic Helper Tests

    @Test("coverSource returns 'primaryEdition' when cover from edition")
    func coverSourcePrimaryEdition() throws {
        // Create work and edition with cover
        let work = Work(title: "Test Book")
        let edition = Edition(
            isbn: "1234567890123",
            coverImageURL: "https://example.com/cover.jpg"
        )

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let source = CoverImageService.coverSource(for: work)

        #expect(source == "primaryEdition", "Source should be primaryEdition")
    }

    @Test("coverSource returns 'work' when cover from work-level")
    func coverSourceWork() throws {
        // Create work with work-level cover only
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let source = CoverImageService.coverSource(for: work)

        #expect(source == "work", "Source should be work")
    }

    @Test("coverSource returns 'none' when no cover available")
    func coverSourceNone() throws {
        // Create work without cover
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let source = CoverImageService.coverSource(for: work)

        #expect(source == "none", "Source should be none")
    }

    @Test("hasCover returns true when cover available")
    func hasCoverTrue() throws {
        // Create work with cover
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/cover.jpg"

        modelContext.insert(work)

        // Test
        let result = CoverImageService.hasCover(work)

        #expect(result == true, "Should return true when cover exists")
    }

    @Test("hasCover returns false when no cover available")
    func hasCoverFalse() throws {
        // Create work without cover
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test
        let result = CoverImageService.hasCover(work)

        #expect(result == false, "Should return false when no cover exists")
    }

    // MARK: - Integration Tests

    @Test("Prioritizes edition cover over work cover when both exist")
    func editionCoverPriority() throws {
        // Create work with both edition and work-level covers
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        let edition = Edition(
            isbn: "1234567890123",
            coverImageURL: "https://example.com/edition-cover.jpg"
        )

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        work.manuallySelectedEdition = edition

        // Test - should prioritize edition cover
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL != nil)
        #expect(coverURL?.absoluteString == "https://example.com/edition-cover.jpg",
               "Should prioritize edition cover over work cover")
    }

    @Test("Works with AutoStrategy edition selection")
    func autoStrategyIntegration() throws {
        // Create work with multiple editions
        let work = Work(title: "Test Book")
        work.coverImageURL = "https://example.com/work-cover.jpg"

        // Edition without cover
        let editionNoCover = Edition(isbn: "1111111111111")

        // Edition with cover (AutoStrategy gives +10 bonus for covers)
        let editionWithCover = Edition(
            isbn: "2222222222222",
            coverImageURL: "https://example.com/edition-cover.jpg"
        )

        modelContext.insert(work)
        modelContext.insert(editionNoCover)
        modelContext.insert(editionWithCover)

        editionNoCover.work = work
        editionWithCover.work = work
        try modelContext.save()

        // AutoStrategy should select edition with cover
        // (primaryEdition uses AutoStrategy by default)
        let selectedEdition = work.primaryEdition

        // Test - should use auto-selected edition with cover
        let coverURL = CoverImageService.coverURL(for: work)

        #expect(coverURL != nil)
        #expect(selectedEdition?.coverImageURL != nil,
               "AutoStrategy should select edition with cover")
    }
}
