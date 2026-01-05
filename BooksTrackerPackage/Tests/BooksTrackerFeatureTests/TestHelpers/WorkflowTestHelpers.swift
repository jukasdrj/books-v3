//
//  WorkflowTestHelpers.swift
//  BooksTrackerFeatureTests
//
//  Workflow test builder pattern for constructing complex test scenarios
//  Used by CloudKit, Reading, and Scanning workflow tests
//

import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - Work Builder Pattern

/// Builder for constructing Work instances with all required relationships
@MainActor
struct WorkBuilder {
    private var work: Work
    private var modelContext: ModelContext
    private var authors: [Author] = []
    private var editions: [Edition] = []

    init(title: String, modelContext: ModelContext) {
        self.work = Work(title: title)
        self.modelContext = modelContext
    }

    /// Add author to work
    mutating func withAuthor(_ author: Author) -> Self {
        authors.append(author)
        return self
    }

    /// Create and add a new author by name
    mutating func withAuthor(name: String, gender: AuthorGender = .unknown) -> Self {
        let author = Author(name: name, gender: gender)
        modelContext.insert(author)
        authors.append(author)
        return self
    }

    /// Add edition to work
    mutating func withEdition(_ edition: Edition) -> Self {
        editions.append(edition)
        return self
    }

    /// Create and add a new edition
    mutating func withEdition(isbn: String, pageCount: Int = 300) -> Self {
        let edition = Edition(isbn: isbn, pageCount: pageCount)
        modelContext.insert(edition)
        editions.append(edition)
        return self
    }

    /// Set CloudKit metadata
    mutating func withCloudKitMetadata(
        openLibraryID: String? = nil,
        isbndbID: String? = nil
    ) -> Self {
        work.openLibraryID = openLibraryID
        work.isbndbID = isbndbID
        return self
    }

    /// Set diversity metadata
    mutating func withDiversityMetadata(
        isOwnVoices: Bool? = nil,
        accessibilityTags: [String] = [],
        subjectTags: [String] = []
    ) -> Self {
        work.isOwnVoices = isOwnVoices
        work.accessibilityTags = accessibilityTags
        work.subjectTags = subjectTags
        return self
    }

    /// Set review status
    mutating func withReviewStatus(_ status: ReviewStatus) -> Self {
        work.reviewStatus = status
        return self
    }

    /// Build the complete Work with all relationships
    func build() throws -> Work {
        modelContext.insert(work)
        try modelContext.save()

        // Add authors after insert (insert-before-relate pattern)
        if !authors.isEmpty {
            work.authors = authors
        }

        // Add editions after insert
        if !editions.isEmpty {
            for edition in editions {
                edition.work = work
            }
            work.editions = editions
        }

        try modelContext.save()
        return work
    }
}

// MARK: - UserLibraryEntry Builder Pattern

/// Builder for constructing UserLibraryEntry instances with reading sessions
@MainActor
struct UserLibraryEntryBuilder {
    private var entry: UserLibraryEntry
    private var modelContext: ModelContext
    private var readingSessions: [ReadingSession] = []

    init(work: Work?, edition: Edition? = nil, modelContext: ModelContext) {
        self.entry = UserLibraryEntry()
        self.modelContext = modelContext
        self.entry.work = work
        self.entry.edition = edition
    }

    /// Set reading status
    mutating func withReadingStatus(_ status: ReadingStatus) -> Self {
        entry.readingStatus = status
        return self
    }

    /// Set reading progress
    mutating func withReadingProgress(currentPage: Int, progress: Double) -> Self {
        entry.currentPage = currentPage
        entry.readingProgress = min(progress, 1.0)
        return self
    }

    /// Set reading dates
    mutating func withReadingDates(
        dateStarted: Date? = nil,
        dateCompleted: Date? = nil
    ) -> Self {
        entry.dateStarted = dateStarted
        entry.dateCompleted = dateCompleted
        return self
    }

    /// Set rating
    mutating func withRating(_ rating: Int?) -> Self {
        entry.rating = rating
        return self
    }

    /// Add a reading session
    mutating func addReadingSession(
        date: Date = Date(),
        durationMinutes: Int,
        startPage: Int,
        endPage: Int
    ) -> Self {
        let session = ReadingSession(
            date: date,
            durationMinutes: durationMinutes,
            startPage: startPage,
            endPage: endPage
        )
        readingSessions.append(session)
        return self
    }

    /// Build the complete UserLibraryEntry with reading sessions
    func build() throws -> UserLibraryEntry {
        modelContext.insert(entry)

        // Add reading sessions
        if !readingSessions.isEmpty {
            for session in readingSessions {
                session.entry = entry
                modelContext.insert(session)
            }
            entry.readingSessions = readingSessions
        }

        try modelContext.save()
        return entry
    }
}

// MARK: - Library Scenario Builder

/// Builder for constructing complex library scenarios (multiple works, entries, sessions)
@MainActor
struct LibraryScenarioBuilder {
    private var modelContext: ModelContext
    private var works: [Work] = []
    private var entries: [UserLibraryEntry] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Add a pre-built work
    mutating func addWork(_ work: Work) -> Self {
        works.append(work)
        return self
    }

    /// Create and add a work with default settings
    mutating func addWork(title: String) throws -> Self {
        var builder = WorkBuilder(title: title, modelContext: modelContext)
        builder = builder.withAuthor(name: "Test Author")
        builder = builder.withEdition(isbn: "978\(UUID().uuidString.prefix(10))")
        let work = try builder.build()
        works.append(work)
        return self
    }

    /// Add a pre-built entry
    mutating func addEntry(_ entry: UserLibraryEntry) -> Self {
        entries.append(entry)
        return self
    }

    /// Create and add a reading scenario (work + entry with sessions)
    mutating func addReadingScenario(
        title: String,
        status: ReadingStatus,
        sessionsCount: Int = 1
    ) throws -> Self {
        var workBuilder = WorkBuilder(title: title, modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "978\(UUID().uuidString.prefix(10))")
        let work = try workBuilder.build()
        works.append(work)

        var entryBuilder = UserLibraryEntryBuilder(work: work, edition: work.editions?.first, modelContext: modelContext)
        entryBuilder = entryBuilder.withReadingStatus(status)

        // Add reading sessions
        for i in 0..<sessionsCount {
            let date = Date().addingTimeInterval(TimeInterval(-86400 * i))
            entryBuilder = entryBuilder.addReadingSession(
                date: date,
                durationMinutes: 30 + i * 10,
                startPage: i * 50,
                endPage: (i + 1) * 50
            )
        }

        let entry = try entryBuilder.build()
        entries.append(entry)
        return self
    }

    /// Build and return all created items
    func build() throws -> (works: [Work], entries: [UserLibraryEntry]) {
        try modelContext.save()
        return (works, entries)
    }
}

// MARK: - ModelContext Helpers

/// Helper extension for creating in-memory test containers
extension ModelContainer {
    /// Create an in-memory container configured for workflow tests
    @MainActor
    static func createWorkflowTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Work.self,
                Author.self,
                Edition.self,
                UserLibraryEntry.self,
                ReadingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

// MARK: - Date Helpers for Testing

extension Date {
    /// Create a date for a specific day count from now
    static func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-86400 * days))
    }

    /// Create a date that's a specific number of hours from now
    static func hoursAgo(_ hours: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-3600 * hours))
    }

    /// Create a date at start of today
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Create a date at start of a specific day
    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

// MARK: - Edition Builder Pattern

/// Builder for constructing Edition instances
@MainActor
struct EditionBuilder {
    private var edition: Edition
    private var modelContext: ModelContext

    init(isbn: String, modelContext: ModelContext) {
        self.edition = Edition(isbn: isbn)
        self.modelContext = modelContext
    }

    /// Set page count
    mutating func withPageCount(_ pageCount: Int) -> Self {
        edition.pageCount = pageCount
        return self
    }

    /// Set publication date
    mutating func withPublicationDate(_ date: String) -> Self {
        edition.publicationDate = date
        return self
    }

    /// Set language
    mutating func withLanguage(_ language: String) -> Self {
        edition.originalLanguage = language
        return self
    }

    /// Set format
    mutating func withFormat(_ format: EditionFormat) -> Self {
        edition.format = format
        return self
    }

    /// Build the edition
    func build() throws -> Edition {
        modelContext.insert(edition)
        try modelContext.save()
        return edition
    }
}
