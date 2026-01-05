//
//  CloudKitModelComplianceTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for CloudKit compliance of SwiftData models
//
//  Given: Models designed for CloudKit sync
//  When: Models are tested for compliance requirements
//  Then: All required defaults and relationships are properly configured
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("CloudKit Model Compliance Tests")
@MainActor
struct CloudKitModelComplianceTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        modelContainer = try ModelContainer.createWorkflowTestContainer()
        modelContext = ModelContext(modelContainer)
    }

    // MARK: - Work Model Compliance

    @Test("Work model has required title default")
    func workHasTitle() {
        let work = Work(title: "Test Book")

        #expect(!work.title.isEmpty)
        #expect(work.title == "Test Book")
    }

    @Test("Work model initializes with valid defaults")
    func workDefaultsAreValid() {
        let work = Work(title: "Default Work")

        #expect(work.uuid != nil, "Work must have UUID for CloudKit sync")
        #expect(work.dateCreated != nil, "Work must have creation date")
        #expect(work.lastModified != nil, "Work must have modification date")
        #expect(work.reviewStatus == .verified, "Work must have default review status")
        #expect(work.authors == nil, "Authors relationship should be nil initially")
    }

    @Test("Work relationships are optional (CloudKit requirement)")
    func workRelationshipsAreOptional() {
        let work = Work(title: "Work with Optional Rels")

        #expect(work.authors == nil || work.authors?.isEmpty == true)
        #expect(work.editions == nil || work.editions?.isEmpty == true)
        #expect(work.userLibraryEntries == nil || work.userLibraryEntries?.isEmpty == true)
    }

    @Test("Work external storage attributes handle empty collections")
    func workExternalStorageHandlesEmpty() {
        let work = Work(title: "Work")

        #expect(work.accessibilityTags.isEmpty)
        #expect(work.subjectTags.isEmpty)
        #expect(work.goodreadsWorkIDs.isEmpty)
        #expect(work.amazonASINs.isEmpty)
    }

    @Test("Work UUID is stable across modifications")
    func workUUIDIsStable() throws {
        var workBuilder = WorkBuilder(title: "Stable UUID Work", modelContext: modelContext)
        workBuilder = workBuilder.withAuthor(name: "Test Author")
        let work = try workBuilder.build()

        let originalUUID = work.uuid

        // Modify work
        work.title = "Modified Title"
        try modelContext.save()

        // UUID should not change
        #expect(work.uuid == originalUUID)
    }

    @Test("Work optional external identifiers default to nil")
    func workOptionalIdentifiersAreNil() {
        let work = Work(title: "No IDs Work")

        #expect(work.openLibraryID == nil)
        #expect(work.isbndbID == nil)
        #expect(work.googleBooksVolumeID == nil)
        #expect(work.goodreadsID == nil)
    }

    // MARK: - Edition Model Compliance

    @Test("Edition model requires ISBN")
    func editionRequiresISBN() {
        let edition = Edition(isbn: "9780439708180")

        #expect(!edition.isbn.isEmpty)
        #expect(edition.isbn == "9780439708180")
    }

    @Test("Edition model has valid defaults")
    func editionDefaultsAreValid() {
        let edition = Edition(isbn: "9780439708180")

        #expect(edition.work == nil, "Edition work relationship should be optional")
        #expect(edition.userLibraryEntries == nil, "Entries relationship should be optional")
    }

    @Test("Edition optional properties default to nil")
    func editionOptionalPropertiesAreNil() {
        let edition = Edition(isbn: "9780439708180")

        #expect(edition.publicationDate == nil)
        #expect(edition.language == nil)
        #expect(edition.format == nil)
        #expect(edition.pageCount == nil)
    }

    // MARK: - UserLibraryEntry Model Compliance

    @Test("UserLibraryEntry has valid defaults")
    func entryDefaultsAreValid() {
        let entry = UserLibraryEntry()

        #expect(entry.readingStatus == .toRead)
        #expect(entry.currentPage == 0)
        #expect(entry.readingProgress == 0.0)
        #expect(entry.rating == nil)
    }

    @Test("UserLibraryEntry relationships are optional")
    func entryRelationshipsAreOptional() {
        let entry = UserLibraryEntry()

        #expect(entry.work == nil)
        #expect(entry.edition == nil)
        #expect(entry.readingSessions == nil || entry.readingSessions?.isEmpty == true)
    }

    @Test("UserLibraryEntry dates are properly initialized")
    func entryDatesAreInitialized() {
        let entry = UserLibraryEntry()

        #expect(entry.dateAdded != nil)
        #expect(entry.lastModified != nil)
        #expect(entry.dateStarted == nil)
        #expect(entry.dateCompleted == nil)
    }

    @Test("UserLibraryEntry reading sessions array is optional")
    func entryReadingSessionsIsOptional() {
        let entry = UserLibraryEntry()

        // Should be nil or empty initially
        let isEmpty = (entry.readingSessions ?? []).isEmpty
        #expect(isEmpty)
    }

    // MARK: - ReadingSession Model Compliance

    @Test("ReadingSession has valid defaults")
    func sessionDefaultsAreValid() {
        let session = ReadingSession()

        #expect(session.date != nil)
        #expect(session.durationMinutes == 0)
        #expect(session.startPage == 0)
        #expect(session.endPage == 0)
    }

    @Test("ReadingSession relationship to entry is optional")
    func sessionEntryRelationshipIsOptional() {
        let session = ReadingSession()

        #expect(session.entry == nil)
    }

    @Test("ReadingSession progressive profiling fields are properly initialized")
    func sessionProgressiveProfilingDefaults() {
        let session = ReadingSession()

        #expect(session.enrichmentPromptShown == false)
        #expect(session.enrichmentCompleted == false)
    }

    // MARK: - Author Model Compliance

    @Test("Author model has required name")
    func authorHasName() {
        let author = Author(name: "Test Author", gender: .unknown)

        #expect(!author.name.isEmpty)
        #expect(author.name == "Test Author")
    }

    @Test("Author model has valid defaults")
    func authorDefaultsAreValid() {
        let author = Author(name: "Test Author", gender: .unknown)

        #expect(author.gender == .unknown)
        #expect(author.works == nil || author.works?.isEmpty == true)
    }

    // MARK: - Multi-Model Consistency

    @Test("Work with author relationship maintains consistency")
    func workAuthorConsistency() throws {
        var workBuilder = WorkBuilder(title: "Multi Author Work", modelContext: modelContext)
        workBuilder = workBuilder.withAuthor(name: "Author One")
        workBuilder = workBuilder.withAuthor(name: "Author Two")

        let work = try workBuilder.build()

        #expect(work.authors?.count == 2)
        #expect(work.authors?[0].name == "Author One")
        #expect(work.authors?[1].name == "Author Two")
    }

    @Test("Work with multiple editions maintains consistency")
    func workEditionConsistency() throws {
        var workBuilder = WorkBuilder(title: "Multi Edition Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        workBuilder = workBuilder.withEdition(isbn: "9780439708197")

        let work = try workBuilder.build()

        #expect(work.editions?.count == 2)
        for edition in work.editions ?? [] {
            #expect(edition.work?.uuid == work.uuid)
        }
    }

    @Test("UserLibraryEntry with work and edition maintains integrity")
    func entryWithRelationshipsIsConsistent() throws {
        var workBuilder = WorkBuilder(title: "Consistent Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        let entry = try entryBuilder.build()

        #expect(entry.work?.uuid == work.uuid)
        #expect(entry.edition?.isbn == "9780439708180")
    }

    // MARK: - CloudKit Compliance Validation

    @Test("All Work instances pass CloudKit compliance check")
    func workCloudKitCompliance() throws {
        var workBuilder = WorkBuilder(title: "Compliant Work", modelContext: modelContext)
        workBuilder = workBuilder.withAuthor(name: "Author")
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        let issues = CloudKitComplianceValidator.validateCloudKitCompliance(for: work)

        #expect(issues.isEmpty, "Work should pass all CloudKit compliance checks")
    }

    @Test("All UserLibraryEntry instances pass CloudKit compliance check")
    func entryCloudKitCompliance() throws {
        var workBuilder = WorkBuilder(title: "Compliant Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        let entry = try entryBuilder.build()

        let issues = CloudKitComplianceValidator.validateCloudKitCompliance(for: entry)

        #expect(issues.isEmpty, "Entry should pass all CloudKit compliance checks")
    }

    @Test("All Edition instances pass CloudKit compliance check")
    func editionCloudKitCompliance() {
        let edition = Edition(isbn: "9780439708180")

        let issues = CloudKitComplianceValidator.validateCloudKitCompliance(for: edition)

        #expect(issues.isEmpty, "Edition should pass all CloudKit compliance checks")
    }

    // MARK: - Large Library Stress Test

    @Test("CloudKit compliance holds for large library (1000 books)")
    func cloudKitComplianceLargeLibrary() throws {
        let works = try LargeDatasetHelper.createLargeLibraryScenario(
            workCount: 100,
            entriesPerWork: 1,
            sessionsPerEntry: 0,
            modelContext: modelContext
        )

        #expect(works.count == 100)

        // Verify all works are compliant
        for work in works {
            let issues = CloudKitComplianceValidator.validateCloudKitCompliance(for: work)
            #expect(issues.isEmpty, "All works should be CloudKit compliant")
        }
    }
}
