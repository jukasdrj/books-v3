//
//  AuthorTests.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test suite for Author model and cultural diversity logic
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for Author model including cultural diversity analytics.
///
/// **Test Coverage:**
/// - Author initialization and properties
/// - Cultural diversity detection (representsMarginalizedVoices)
/// - Indigenous voices detection
/// - Gender and cultural region mapping
/// - Display name formatting (with birth/death years)
/// - Author statistics (book count, updateStatistics)
/// - Relationships with Works
/// - External ID management
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `Author.swift`
@Suite("Author Model Tests")
@MainActor
struct AuthorTests {

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

    // MARK: - Initialization Tests

    @Test("Author initializes with default values")
    func authorInitialization() {
        let author = Author(name: "Test Author")

        #expect(author.name == "Test Author")
        #expect(author.gender == .unknown)
        #expect(author.culturalRegion == nil)
        #expect(author.nationality == nil)
        #expect(author.birthYear == nil)
        #expect(author.deathYear == nil)
        #expect(author.bookCount == 0)
    }

    @Test("Author initializes with all parameters")
    func authorFullInitialization() {
        let author = Author(
            name: "Chimamanda Ngozi Adichie",
            nationality: "Nigeria",
            gender: .female,
            culturalRegion: .africa,
            birthYear: 1977,
            deathYear: nil
        )

        #expect(author.name == "Chimamanda Ngozi Adichie")
        #expect(author.nationality == "Nigeria")
        #expect(author.gender == .female)
        #expect(author.culturalRegion == .africa)
        #expect(author.birthYear == 1977)
        #expect(author.deathYear == nil)
    }

    // MARK: - Display Name Tests

    @Test("Display name without birth/death years")
    func displayNameBasic() {
        let author = Author(name: "Jane Austen")

        #expect(author.displayName == "Jane Austen")
    }

    @Test("Display name with birth year only")
    func displayNameWithBirthYear() {
        let author = Author(
            name: "Chimamanda Ngozi Adichie",
            birthYear: 1977
        )

        #expect(author.displayName == "Chimamanda Ngozi Adichie (b. 1977)")
    }

    @Test("Display name with birth and death years")
    func displayNameWithBirthDeath() {
        let author = Author(
            name: "Jane Austen",
            birthYear: 1775,
            deathYear: 1817
        )

        #expect(author.displayName == "Jane Austen (1775–1817)")
    }

    @Test("Display name with death year only (edge case)")
    func displayNameWithDeathYearOnly() {
        let author = Author(
            name: "Mystery Author",
            deathYear: 1900
        )

        // Should not show death year if birth year is unknown
        #expect(author.displayName == "Mystery Author")
    }

    // MARK: - Marginalized Voices Detection Tests

    @Test("Female authors represent marginalized voices")
    func femaleAuthorsMarginalized() {
        let author = Author(
            name: "Toni Morrison",
            gender: .female
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Female authors should be recognized as marginalized voices")
    }

    @Test("Non-binary authors represent marginalized voices")
    func nonBinaryAuthorsMarginalized() {
        let author = Author(
            name: "Test Author",
            gender: .nonBinary
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Non-binary authors should be recognized as marginalized voices")
    }

    @Test("Other gender authors represent marginalized voices")
    func otherGenderAuthorsMarginalized() {
        let author = Author(
            name: "Test Author",
            gender: .other
        )

        #expect(author.representsMarginalizedVoices() == true,
               "'Other' gender authors should be recognized as marginalized voices")
    }

    @Test("Male authors from Europe do not represent marginalized voices")
    func maleEuropeanAuthorsNotMarginalized() {
        let author = Author(
            name: "Test Author",
            nationality: "United Kingdom",
            gender: .male,
            culturalRegion: .europe
        )

        #expect(author.representsMarginalizedVoices() == false,
               "Male European authors should not be counted as marginalized")
    }

    @Test("Male authors from Africa represent marginalized voices")
    func maleAfricanAuthorsMarginalized() {
        let author = Author(
            name: "Chinua Achebe",
            nationality: "Nigeria",
            gender: .male,
            culturalRegion: .africa
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Authors from Africa should be recognized as marginalized voices")
    }

    @Test("Authors from Middle East represent marginalized voices")
    func middleEastAuthorsMarginalized() {
        let author = Author(
            name: "Test Author",
            gender: .male,
            culturalRegion: .middleEast
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Authors from Middle East should be recognized as marginalized voices")
    }

    @Test("Authors from South America represent marginalized voices")
    func southAmericanAuthorsMarginalized() {
        let author = Author(
            name: "Gabriel García Márquez",
            gender: .male,
            culturalRegion: .southAmerica
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Authors from South America should be recognized as marginalized voices")
    }

    @Test("Authors from Central Asia represent marginalized voices")
    func centralAsianAuthorsMarginalized() {
        let author = Author(
            name: "Test Author",
            gender: .male,
            culturalRegion: .centralAsia
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Authors from Central Asia should be recognized as marginalized voices")
    }

    @Test("Indigenous authors represent marginalized voices")
    func indigenousAuthorsMarginalized() {
        let author = Author(
            name: "Test Author",
            gender: .male,
            culturalRegion: .indigenous
        )

        #expect(author.representsMarginalizedVoices() == true,
               "Indigenous authors should be recognized as marginalized voices")
    }

    @Test("Unknown gender from non-marginalized region returns false")
    func unknownGenderNonMarginalizedRegion() {
        let author = Author(
            name: "Test Author",
            gender: .unknown,
            culturalRegion: .europe
        )

        #expect(author.representsMarginalizedVoices() == false,
               "Unknown gender + non-marginalized region should return false")
    }

    @Test("Unknown gender with no region returns false")
    func unknownGenderNoRegion() {
        let author = Author(
            name: "Test Author",
            gender: .unknown
        )

        #expect(author.representsMarginalizedVoices() == false,
               "Unknown gender with no region should return false")
    }

    // MARK: - Indigenous Voices Detection Tests

    @Test("Indigenous cultural region is detected")
    func indigenousVoicesDetected() {
        let author = Author(
            name: "Test Author",
            culturalRegion: .indigenous
        )

        #expect(author.representsIndigenousVoices() == true,
               "Should detect indigenous cultural region")
    }

    @Test("Non-indigenous region returns false")
    func nonIndigenousRegion() {
        let author = Author(
            name: "Test Author",
            culturalRegion: .europe
        )

        #expect(author.representsIndigenousVoices() == false,
               "Non-indigenous regions should return false")
    }

    @Test("No cultural region returns false for indigenous check")
    func noCulturalRegionIndigenousCheck() {
        let author = Author(name: "Test Author")

        #expect(author.representsIndigenousVoices() == false,
               "No cultural region should return false")
    }

    // MARK: - Statistics Tests

    @Test("Book count starts at zero")
    func initialBookCount() {
        let author = Author(name: "Test Author")

        #expect(author.bookCount == 0)
    }

    @Test("updateStatistics calculates book count from works relationship")
    func updateStatisticsCalculatesBookCount() throws {
        // Create author and works
        let author = Author(name: "Test Author")
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        let work3 = Work(title: "Book 3")

        modelContext.insert(author)
        modelContext.insert(work1)
        modelContext.insert(work2)
        modelContext.insert(work3)

        // Set up relationships (insert-before-relate pattern)
        work1.authors = [author]
        work2.authors = [author]
        work3.authors = [author]
        try modelContext.save()

        // Update statistics
        author.updateStatistics()

        #expect(author.bookCount == 3, "Book count should match works count")
    }

    @Test("updateStatistics handles empty works array")
    func updateStatisticsEmptyWorks() throws {
        let author = Author(name: "Test Author")
        author.bookCount = 5  // Set non-zero count

        modelContext.insert(author)
        try modelContext.save()

        // Update statistics with no works
        author.updateStatistics()

        #expect(author.bookCount == 0, "Book count should be 0 for no works")
    }

    @Test("updateStatistics updates lastModified timestamp")
    func updateStatisticsUpdatesTimestamp() throws {
        let author = Author(name: "Test Author")
        modelContext.insert(author)
        try modelContext.save()

        let originalTimestamp = author.lastModified

        // Wait briefly to ensure timestamp difference
        try await Task.sleep(for: .milliseconds(10))

        // Update statistics
        author.updateStatistics()

        #expect(author.lastModified > originalTimestamp,
               "lastModified should be updated")
    }

    // MARK: - Touch Method Tests

    @Test("touch method updates lastModified timestamp")
    func touchUpdatesTimestamp() async throws {
        let author = Author(name: "Test Author")
        modelContext.insert(author)
        try modelContext.save()

        let originalTimestamp = author.lastModified

        // Wait briefly to ensure timestamp difference
        try await Task.sleep(for: .milliseconds(10))

        // Touch author
        author.touch()

        #expect(author.lastModified > originalTimestamp,
               "touch() should update lastModified")
    }

    // MARK: - External ID Tests

    @Test("External IDs can be set and retrieved")
    func externalIDsSetAndGet() {
        let author = Author(name: "Test Author")
        author.openLibraryID = "OL23919A"
        author.isbndbID = "test_isbndb_id"
        author.googleBooksID = "test_google_id"
        author.goodreadsID = "12345"

        #expect(author.openLibraryID == "OL23919A")
        #expect(author.isbndbID == "test_isbndb_id")
        #expect(author.googleBooksID == "test_google_id")
        #expect(author.goodreadsID == "12345")
    }

    // MARK: - Relationship Tests

    @Test("Author can have multiple works")
    func authorCanHaveMultipleWorks() throws {
        let author = Author(name: "Test Author")
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")

        modelContext.insert(author)
        modelContext.insert(work1)
        modelContext.insert(work2)

        // Set up many-to-many relationships
        work1.authors = [author]
        work2.authors = [author]
        try modelContext.save()

        #expect(author.works?.count == 2)
        #expect(author.works?.contains(work1) == true)
        #expect(author.works?.contains(work2) == true)
    }

    @Test("Work can have multiple authors (co-authored)")
    func workCanHaveMultipleAuthors() throws {
        let author1 = Author(name: "Author 1")
        let author2 = Author(name: "Author 2")
        let work = Work(title: "Co-Authored Book")

        modelContext.insert(author1)
        modelContext.insert(author2)
        modelContext.insert(work)

        // Set up many-to-many relationship
        work.authors = [author1, author2]
        try modelContext.save()

        #expect(work.authors?.count == 2)
        #expect(work.authors?.contains(author1) == true)
        #expect(work.authors?.contains(author2) == true)
    }

    @Test("Nullify delete rule preserves works when author deleted")
    func deleteRuleNullify() throws {
        let author = Author(name: "Test Author")
        let work = Work(title: "Test Book")

        modelContext.insert(author)
        modelContext.insert(work)

        work.authors = [author]
        try modelContext.save()

        // Delete author
        modelContext.delete(author)
        try modelContext.save()

        // Work should still exist (nullify rule)
        let descriptor = FetchDescriptor<Work>()
        let works = try modelContext.fetch(descriptor)

        #expect(works.count == 1, "Work should still exist after author deletion")
        #expect(works.first?.authors?.isEmpty == true,
               "Work's authors array should be empty")
    }

    // MARK: - Metadata Tests

    @Test("dateCreated is set on initialization")
    func dateCreatedSet() {
        let beforeCreate = Date()
        let author = Author(name: "Test Author")
        let afterCreate = Date()

        #expect(author.dateCreated >= beforeCreate)
        #expect(author.dateCreated <= afterCreate)
    }

    @Test("lastModified is set on initialization")
    func lastModifiedSet() {
        let beforeCreate = Date()
        let author = Author(name: "Test Author")
        let afterCreate = Date()

        #expect(author.lastModified >= beforeCreate)
        #expect(author.lastModified <= afterCreate)
    }
}

// MARK: - AuthorGender Enum Tests

@Suite("AuthorGender Enum Tests")
struct AuthorGenderTests {

    @Test("All gender cases have correct raw values")
    func genderRawValues() {
        #expect(AuthorGender.female.rawValue == "Female")
        #expect(AuthorGender.male.rawValue == "Male")
        #expect(AuthorGender.nonBinary.rawValue == "Non-binary")
        #expect(AuthorGender.other.rawValue == "Other")
        #expect(AuthorGender.unknown.rawValue == "Unknown")
    }

    @Test("All gender cases have icons")
    func genderIcons() {
        #expect(AuthorGender.female.icon == "person.crop.circle.fill")
        #expect(AuthorGender.male.icon == "person.crop.circle")
        #expect(AuthorGender.nonBinary.icon == "person.crop.circle.badge.questionmark")
        #expect(AuthorGender.other.icon == "person.crop.circle.badge.plus")
        #expect(AuthorGender.unknown.icon == "questionmark.circle")
    }

    @Test("All gender cases have display names")
    func genderDisplayNames() {
        #expect(AuthorGender.female.displayName == "Female")
        #expect(AuthorGender.male.displayName == "Male")
        #expect(AuthorGender.nonBinary.displayName == "Non-binary")
        #expect(AuthorGender.other.displayName == "Other")
        #expect(AuthorGender.unknown.displayName == "Unknown")
    }

    @Test("Gender conforms to Identifiable")
    func genderIdentifiable() {
        #expect(AuthorGender.female.id == AuthorGender.female)
        #expect(AuthorGender.male.id == AuthorGender.male)
    }
}

// MARK: - CulturalRegion Enum Tests

@Suite("CulturalRegion Enum Tests")
struct CulturalRegionTests {

    @Test("All regions have correct raw values")
    func regionRawValues() {
        #expect(CulturalRegion.africa.rawValue == "Africa")
        #expect(CulturalRegion.asia.rawValue == "Asia")
        #expect(CulturalRegion.europe.rawValue == "Europe")
        #expect(CulturalRegion.northAmerica.rawValue == "North America")
        #expect(CulturalRegion.southAmerica.rawValue == "South America")
        #expect(CulturalRegion.oceania.rawValue == "Oceania")
        #expect(CulturalRegion.middleEast.rawValue == "Middle East")
        #expect(CulturalRegion.caribbean.rawValue == "Caribbean")
        #expect(CulturalRegion.centralAsia.rawValue == "Central Asia")
        #expect(CulturalRegion.indigenous.rawValue == "Indigenous")
        #expect(CulturalRegion.international.rawValue == "International")
    }

    @Test("All regions have display names")
    func regionDisplayNames() {
        #expect(CulturalRegion.africa.displayName == "Africa")
        #expect(CulturalRegion.northAmerica.displayName == "North America")
        #expect(CulturalRegion.indigenous.displayName == "Indigenous")
    }

    @Test("All regions have short names")
    func regionShortNames() {
        #expect(CulturalRegion.northAmerica.shortName == "N. America")
        #expect(CulturalRegion.southAmerica.shortName == "S. America")
        #expect(CulturalRegion.centralAsia.shortName == "C. Asia")
        #expect(CulturalRegion.international.shortName == "Global")
    }

    @Test("All regions have emojis")
    func regionEmojis() {
        #expect(CulturalRegion.africa.emoji == "🌍")
        #expect(CulturalRegion.asia.emoji == "🌏")
        #expect(CulturalRegion.indigenous.emoji == "🪶")
        #expect(CulturalRegion.international.emoji == "🌐")
    }

    @Test("All regions have SF Symbol icons")
    func regionIcons() {
        #expect(CulturalRegion.africa.icon == "globe.africa.fill")
        #expect(CulturalRegion.asia.icon == "globe.asia.australia.fill")
        #expect(CulturalRegion.indigenous.icon == "leaf.fill")
        #expect(CulturalRegion.international.icon == "globe")
    }

    @Test("Region conforms to Identifiable")
    func regionIdentifiable() {
        #expect(CulturalRegion.africa.id == CulturalRegion.africa)
        #expect(CulturalRegion.indigenous.id == CulturalRegion.indigenous)
    }
}
