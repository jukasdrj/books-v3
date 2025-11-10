import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("LibraryRepository Reset Tests")
@MainActor
struct LibraryRepositoryResetTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var repository: LibraryRepository!

    init() throws {
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
        let featureFlags = FeatureFlags()
        let dtoMapper = DTOMapper(modelContext: modelContext, featureFlags: featureFlags)
        repository = LibraryRepository(modelContext: modelContext, dtoMapper: dtoMapper, featureFlags: featureFlags)
    }

    @Test("resetLibrary clears all data")
    func testResetLibrary() async throws {
        // GIVEN: A library with works, authors, editions, and user library entries
        let author = Author(name: "Author")
        let work = Work(title: "Work")
        let edition = Edition(title: "Edition")
        let userLibraryEntry = UserLibraryEntry(readingStatus: .read)

        modelContext.insert(author)
        modelContext.insert(work)
        modelContext.insert(edition)
        modelContext.insert(userLibraryEntry)

        try modelContext.save()

        // WHEN: The library is reset
        await repository.resetLibrary()

        // THEN: All data should be deleted
        let works = try modelContext.fetch(FetchDescriptor<Work>())
        let authors = try modelContext.fetch(FetchDescriptor<Author>())
        let editions = try modelContext.fetch(FetchDescriptor<Edition>())
        let userLibraryEntries = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())

        #expect(works.isEmpty, "Works should be empty after reset")
        #expect(authors.isEmpty, "Authors should be empty after reset")
        #expect(editions.isEmpty, "Editions should be empty after reset")
        #expect(userLibraryEntries.isEmpty, "UserLibraryEntries should be empty after reset")
    }
}
