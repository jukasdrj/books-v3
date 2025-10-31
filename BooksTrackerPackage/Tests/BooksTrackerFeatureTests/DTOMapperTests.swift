import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

/// Tests for DTOMapper - converts canonical DTOs to SwiftData models
/// Critical: Respects insert-before-relate pattern for SwiftData
@Suite("DTO Mapper Tests")
struct DTOMapperTests {

    // MARK: - Helper: Create In-Memory ModelContainer

    @MainActor
    func createTestContainer() throws -> ModelContainer {
        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - AuthorDTO Mapping Tests

    @Test("mapToAuthor converts AuthorDTO to Author model")
    @MainActor
    func mapToAuthorBasic() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        let authorDTO = AuthorDTO(
            name: "George Orwell",
            gender: .male,
            culturalRegion: .europe,
            nationality: "British",
            birthYear: 1903,
            deathYear: 1950,
            openLibraryID: "OL123A",
            isbndbID: nil,
            googleBooksID: nil,
            goodreadsID: nil,
            bookCount: 15
        )

        let author = try mapper.mapToAuthor(authorDTO)

        #expect(author.name == "George Orwell")
        #expect(author.gender == .male)
        #expect(author.culturalRegion == .europe)
        #expect(author.nationality == "British")
        #expect(author.birthYear == 1903)
        #expect(author.deathYear == 1950)
        #expect(author.openLibraryID == "OL123A")
        #expect(author.bookCount == 15)
    }

    @Test("mapToAuthor handles minimal AuthorDTO")
    @MainActor
    func mapToAuthorMinimal() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        let authorDTO = AuthorDTO(
            name: "Unknown Author",
            gender: .unknown,
            culturalRegion: nil,
            nationality: nil,
            birthYear: nil,
            deathYear: nil,
            openLibraryID: nil,
            isbndbID: nil,
            googleBooksID: nil,
            goodreadsID: nil,
            bookCount: nil
        )

        let author = try mapper.mapToAuthor(authorDTO)

        #expect(author.name == "Unknown Author")
        #expect(author.gender == .unknown)
        #expect(author.culturalRegion == nil)
        #expect(author.bookCount == 0)
    }

    // MARK: - EditionDTO Mapping Tests

    @Test("mapToEdition converts EditionDTO to Edition model")
    @MainActor
    func mapToEditionBasic() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        let editionDTO = EditionDTO(
            isbn: "9780451524935",
            isbns: ["9780451524935", "0451524934"],
            title: "1984",
            publisher: "Signet Classic",
            publicationDate: "1950-06-01",
            pageCount: 328,
            format: .paperback,
            coverImageURL: "https://example.com/cover.jpg",
            editionTitle: "First Edition",
            editionDescription: "Classic dystopian novel",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryEditionID: "OL123E",
            isbndbID: nil,
            googleBooksVolumeID: "vol789",
            goodreadsID: nil,
            amazonASINs: ["B001ABC123"],
            googleBooksVolumeIDs: ["vol789"],
            librarythingIDs: ["thing456"],
            lastISBNDBSync: nil,
            isbndbQuality: 90
        )

        let edition = try mapper.mapToEdition(editionDTO)

        #expect(edition.isbn == "9780451524935")
        #expect(edition.isbns == ["9780451524935", "0451524934"])
        #expect(edition.publisher == "Signet Classic")
        #expect(edition.pageCount == 328)
        #expect(edition.format == .paperback)
        #expect(edition.editionDescription == "Classic dystopian novel")
        #expect(edition.primaryProvider == "google-books")
        #expect(edition.contributors == ["google-books"])
        #expect(edition.isbndbQuality == 90)
    }

    // MARK: - WorkDTO Mapping Tests

    @Test("mapToWork converts WorkDTO to Work model")
    @MainActor
    func mapToWorkBasic() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        let workDTO = WorkDTO(
            title: "1984",
            subjectTags: ["Fiction", "Dystopian"],
            originalLanguage: "English",
            firstPublicationYear: 1949,
            description: "A dystopian novel",
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: "OL123W",
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: ["work123"],
            amazonASINs: ["B001ABC123"],
            librarythingIDs: ["thing456"],
            googleBooksVolumeIDs: ["vol789"],
            lastISBNDBSync: nil,
            isbndbQuality: 95,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let work = try mapper.mapToWork(workDTO)

        #expect(work.title == "1984")
        #expect(work.subjectTags == ["Fiction", "Dystopian"])
        #expect(work.originalLanguage == "English")
        #expect(work.firstPublicationYear == 1949)
        #expect(work.synthetic == false)
        #expect(work.primaryProvider == "google-books")
        #expect(work.contributors == ["google-books"])
        #expect(work.isbndbQuality == 95)
        #expect(work.reviewStatus == .verified)
    }

    @Test("mapToWork deduplicates by googleBooksVolumeIDs")
    @MainActor
    func mapToWorkDeduplication() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create first work with googleBooksVolumeID
        let work1DTO = WorkDTO(
            title: "1984",
            subjectTags: ["Fiction"],
            originalLanguage: nil,
            firstPublicationYear: 1949,
            description: nil,
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["vol123"],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let work1 = try mapper.mapToWork(work1DTO)
        try context.save()

        // Try to create duplicate with same googleBooksVolumeID
        let work2DTO = WorkDTO(
            title: "1984 (Reissue)",
            subjectTags: ["Fiction", "Classic"],
            originalLanguage: "English",
            firstPublicationYear: 1949,
            description: "Updated description",
            synthetic: false,
            primaryProvider: "openlibrary",
            contributors: ["openlibrary"],
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["vol123"],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let work2 = try mapper.mapToWork(work2DTO)

        // Should return same Work instance (deduplicated)
        #expect(work1 === work2)

        // Should have merged data
        #expect(work2.contributors.contains("google-books"))
        #expect(work2.contributors.contains("openlibrary"))
    }

    @Test("mapToWork merges synthetic Work with real Work")
    @MainActor
    func mapToWorkSyntheticMerging() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create synthetic work first (inferred from Edition)
        let syntheticWorkDTO = WorkDTO(
            title: "Unknown Book",
            subjectTags: [],
            originalLanguage: nil,
            firstPublicationYear: nil,
            description: nil,
            synthetic: true,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["vol456"],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .needsReview,
            originalImagePath: nil,
            boundingBox: nil
        )

        let syntheticWork = try mapper.mapToWork(syntheticWorkDTO)
        try context.save()

        #expect(syntheticWork.synthetic == true)

        // Now map real Work data with same googleBooksVolumeID
        let realWorkDTO = WorkDTO(
            title: "1984",
            subjectTags: ["Fiction", "Dystopian"],
            originalLanguage: "English",
            firstPublicationYear: 1949,
            description: "A dystopian novel by George Orwell",
            synthetic: false,
            primaryProvider: "openlibrary",
            contributors: ["openlibrary"],
            openLibraryID: nil,
            openLibraryWorkID: "OL123W",
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: ["work123"],
            amazonASINs: ["B001ABC123"],
            librarythingIDs: ["thing456"],
            googleBooksVolumeIDs: ["vol456"],
            lastISBNDBSync: nil,
            isbndbQuality: 95,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        let realWork = try mapper.mapToWork(realWorkDTO)

        // Should return same Work instance
        #expect(syntheticWork === realWork)

        // Should have replaced synthetic with real data
        #expect(realWork.synthetic == false)
        #expect(realWork.title == "1984")
        // Note: Work model doesn't have description field
        #expect(realWork.reviewStatus == .verified)
    }

    @Test("mapToWork handles existing Works with empty googleBooksVolumeIDs")
    @MainActor
    func mapToWorkWithEmptyVolumeIDs() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let mapper = DTOMapper(modelContext: context)

        // Create an existing Work with empty googleBooksVolumeIDs (common in CSV imports)
        let existingWork = Work(
            title: "The Great Gatsby",
            originalLanguage: "English",
            firstPublicationYear: 1925,
            subjectTags: ["Fiction"],
            synthetic: false,
            primaryProvider: "csv"
        )
        // Empty googleBooksVolumeIDs array (default state)
        #expect(existingWork.googleBooksVolumeIDs.isEmpty)

        // Insert into context
        context.insert(existingWork)
        try context.save()

        // Now try to map a new Work with valid googleBooksVolumeIDs
        // This should NOT crash when comparing against existing Work with empty array
        let newWorkDTO = WorkDTO(
            title: "1984",
            subjectTags: ["Dystopian", "Fiction"],
            originalLanguage: "English",
            firstPublicationYear: 1949,
            description: nil,
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: ["vol123", "vol456"],
            lastISBNDBSync: nil,
            isbndbQuality: 85,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        // This is where the crash happens in production:
        // findExistingWork() iterates over all Works and calls:
        // Set(existingWork.googleBooksVolumeIDs).isDisjoint(with: volumeIDs)
        // When existingWork.googleBooksVolumeIDs is empty, this crashes
        let newWork = try mapper.mapToWork(newWorkDTO)

        // Should create a new Work (not merge with existing)
        #expect(newWork !== existingWork)
        #expect(newWork.title == "1984")
        #expect(newWork.googleBooksVolumeIDs.count == 2)

        // Existing work should be unchanged
        #expect(existingWork.title == "The Great Gatsby")
        #expect(existingWork.googleBooksVolumeIDs.isEmpty)
    }
}
