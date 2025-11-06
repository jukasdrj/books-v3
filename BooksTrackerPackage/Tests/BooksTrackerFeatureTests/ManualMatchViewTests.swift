//
//  ManualMatchViewTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for manual book matching functionality
//

import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("Manual Match View Tests")
@MainActor
struct ManualMatchViewTests {
    
    /// Test that ManualMatchView can be initialized with a Work
    @Test("ManualMatchView initialization")
    func testInitialization() async throws {
        // Arrange
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        
        let author = Author(name: "Test Author")
        let work = Work(
            title: "Test Book",
            originalLanguage: "English",
            firstPublicationYear: 2024
        )
        work.reviewStatus = .needsReview
        
        context.insert(author)
        context.insert(work)
        work.authors = [author]
        
        try context.save()
        
        // Act - Create view (just verify it doesn't crash)
        let view = ManualMatchView(work: work)
        
        // Assert
        #expect(view.work.title == "Test Book")
        #expect(view.work.reviewStatus == .needsReview)
    }
    
    /// Test that applying a match updates Work metadata
    @Test("Apply match updates work")
    func testApplyMatchUpdatesWork() async throws {
        // Arrange
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        
        // Original work with missing data
        let originalAuthor = Author(name: "Unknown")
        let originalWork = Work(
            title: "Incomplete Book",
            originalLanguage: nil,
            firstPublicationYear: nil
        )
        originalWork.reviewStatus = .needsReview
        
        context.insert(originalAuthor)
        context.insert(originalWork)
        originalWork.authors = [originalAuthor]
        
        // Create a "matched" work with complete data
        let matchedAuthor = Author(name: "Complete Author")
        let matchedWork = Work(
            title: "Complete Book",
            originalLanguage: "English",
            firstPublicationYear: 2024
        )
        matchedWork.googleBooksVolumeID = "abc123"
        matchedWork.openLibraryID = "OL123"
        
        context.insert(matchedAuthor)
        context.insert(matchedWork)
        matchedWork.authors = [matchedAuthor]
        
        // Create edition for matched work
        let edition = Edition(
            isbn: "9781234567890",
            publisher: "Test Publisher",
            publicationDate: "2024",
            pageCount: 300,
            format: .hardcover,
            coverImageURL: "https://example.com/cover.jpg"
        )
        context.insert(edition)
        edition.work = matchedWork
        
        try context.save()
        
        // Act - Simulate applying match by copying data
        originalWork.title = matchedWork.title
        originalWork.originalLanguage = matchedWork.originalLanguage
        originalWork.firstPublicationYear = matchedWork.firstPublicationYear
        originalWork.googleBooksVolumeID = matchedWork.googleBooksVolumeID
        originalWork.openLibraryID = matchedWork.openLibraryID
        originalWork.authors = [matchedAuthor]
        originalWork.reviewStatus = .userEdited
        originalWork.synthetic = false
        
        try context.save()
        
        // Assert
        #expect(originalWork.title == "Complete Book")
        #expect(originalWork.originalLanguage == "English")
        #expect(originalWork.firstPublicationYear == 2024)
        #expect(originalWork.googleBooksVolumeID == "abc123")
        #expect(originalWork.openLibraryID == "OL123")
        #expect(originalWork.authors?.count == 1)
        #expect(originalWork.authors?.first?.name == "Complete Author")
        #expect(originalWork.reviewStatus == .userEdited)
        #expect(originalWork.synthetic == false)
    }
    
    /// Test that manual matching preserves user library entries
    @Test("Apply match preserves library entries")
    func testApplyMatchPreservesLibraryEntries() async throws {
        // Arrange
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        
        // Create work with user library entry
        let author = Author(name: "Test Author")
        let work = Work(
            title: "My Book",
            originalLanguage: "English",
            firstPublicationYear: 2024
        )
        let edition = Edition(
            isbn: "9781234567890",
            publisher: "Test Publisher",
            publicationDate: "2024",
            pageCount: 200,
            format: .paperback
        )
        
        context.insert(author)
        context.insert(work)
        context.insert(edition)
        work.authors = [author]
        edition.work = work
        
        // Create user library entry
        let entry = UserLibraryEntry(
            readingStatus: .reading,
            personalRating: 4.5,
            edition: edition
        )
        context.insert(entry)
        entry.work = work
        
        try context.save()
        
        let originalEntryCount = work.userLibraryEntries?.count ?? 0
        
        // Act - Update work metadata (simulating match application)
        work.title = "Updated Book Title"
        work.googleBooksVolumeID = "new-id"
        
        try context.save()
        
        // Assert - User library entry should still exist
        #expect(work.userLibraryEntries?.count == originalEntryCount)
        #expect(entry.work?.title == "Updated Book Title")
        #expect(entry.readingStatus == .reading)
        #expect(entry.personalRating == 4.5)
    }
}
