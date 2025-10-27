import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

@Suite("SwiftData Relationship Cascades")
@MainActor
struct RelationshipCascadeTests {

    @Test("deleting Work cascades to UserLibraryEntries")
    func testDeleteWorkCascades() throws {
        let context = createTestContext()

        // Create Work with UserLibraryEntry
        let work = Work(title: "Test Book", authors: [])
        let entry = UserLibraryEntry(work: work, readingStatus: .toRead)
        work.userLibraryEntries = [entry]

        context.insert(work)
        context.insert(entry)
        try context.save()

        // Verify entry exists
        let entriesBefore = try context.fetch(FetchDescriptor<UserLibraryEntry>())
        #expect(entriesBefore.count == 1)

        // Delete work
        context.delete(work)
        try context.save()

        // Verify entry is also deleted (cascade)
        let entriesAfter = try context.fetch(FetchDescriptor<UserLibraryEntry>())
        #expect(entriesAfter.count == 0, "UserLibraryEntry should cascade delete with Work")
    }

    @Test("deleting Author removes relationship but keeps Work")
    func testDeleteAuthorPreservesWork() throws {
        let context = createTestContext()

        // Create Author and Work
        let author = Author(name: "Test Author", gender: .unknown, culturalRegion: nil)
        let work = Work(title: "Test Book", authors: [author])

        context.insert(author)
        context.insert(work)
        try context.save()

        // Verify relationship
        #expect(work.authors?.count == 1)

        // Delete author
        context.delete(author)
        try context.save()

        // Work should still exist, but with empty authors
        let works = try context.fetch(FetchDescriptor<Work>())
        #expect(works.count == 1, "Work should not cascade delete with Author")
        #expect(works.first?.authors?.count == 0, "Author relationship should be removed")
    }

    @Test("deleting Edition removes relationship but keeps Work")
    func testDeleteEditionPreservesWork() throws {
        let context = createTestContext()

        // Create Work and Edition
        let work = Work(title: "Test Book", authors: [])
        let edition = Edition(isbn: "1234567890", format: .hardcover, work: work)
        work.editions = [edition]

        context.insert(work)
        context.insert(edition)
        try context.save()

        // Delete edition
        context.delete(edition)
        try context.save()

        // Work should still exist
        let works = try context.fetch(FetchDescriptor<Work>())
        #expect(works.count == 1)
        #expect(works.first?.editions?.count == 0)
    }

    @Test("library reset clears all relationships correctly")
    func testLibraryResetClearsRelationships() throws {
        let context = createTestContext()

        // Create complex relationship graph
        let author = Author(name: "Author", gender: .unknown, culturalRegion: nil)
        let work = Work(title: "Book", authors: [author])
        let edition = Edition(isbn: "123", format: .paperback, work: work)
        let entry = UserLibraryEntry(work: work, readingStatus: .read)

        entry.edition = edition
        work.editions = [edition]
        work.userLibraryEntries = [entry]

        context.insert(author)
        context.insert(work)
        context.insert(edition)
        context.insert(entry)
        try context.save()

        // Simulate library reset
        let allWorks = try context.fetch(FetchDescriptor<Work>())
        let allEntries = try context.fetch(FetchDescriptor<UserLibraryEntry>())
        let allAuthors = try context.fetch(FetchDescriptor<Author>())
        let allEditions = try context.fetch(FetchDescriptor<Edition>())

        for work in allWorks { context.delete(work) }
        for entry in allEntries { context.delete(entry) }
        for author in allAuthors { context.delete(author) }
        for edition in allEditions { context.delete(edition) }

        try context.save()

        // Verify everything is deleted
        #expect(try context.fetch(FetchDescriptor<Work>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<UserLibraryEntry>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Author>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Edition>()).count == 0)
    }

    // MARK: - Helpers

    private func createTestContext() -> ModelContext {
        let schema = Schema([Work.self, Author.self, Edition.self, UserLibraryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
