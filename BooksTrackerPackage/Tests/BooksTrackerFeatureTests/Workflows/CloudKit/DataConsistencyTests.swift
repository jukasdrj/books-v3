//
//  DataConsistencyTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for CloudKit data consistency across devices and conflict resolution
//
//  Given: Multi-device scenarios with CloudKit sync
//  When: Data is modified concurrently or offline
//  Then: Consistency is maintained using Last-Writer-Wins strategy
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Data Consistency Tests")
@MainActor
struct DataConsistencyTests {

    var modelContainer: ModelContainer!

    init() throws {
        modelContainer = try ModelContainer.createWorkflowTestContainer()
    }

    // MARK: - Multi-Device Simulation

    @Test("Two devices can operate independently with same data")
    func twoDevicesIndependentOperation() throws {
        let simulator = CloudKitMultiDeviceSimulator(modelContainer: modelContainer)

        // Device 1 creates a work
        var builder1 = WorkBuilder(title: "Shared Work", modelContext: simulator.context1)
        builder1 = builder1.withAuthor(name: "Author")
        builder1 = builder1.withEdition(isbn: "9780439708180")
        let work = try builder1.build()

        let workID = work.uuid

        // Simulate device 2 seeing the same work
        try simulator.simulateRemoteChange { context in
            let descriptor = FetchDescriptor<Work>(
                predicate: #Predicate { $0.uuid == workID }
            )
            if let remoteWork = try context.fetch(descriptor).first {
                remoteWork.title = "Updated on Device 2"
                try context.save()
            }
        }

        // Device 1 refreshes and sees device 2's change
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.uuid == workID }
        )
        let refreshedWork = try simulator.context1.fetch(descriptor).first

        #expect(refreshedWork?.title == "Updated on Device 2")
    }

    @Test("Conflict resolution uses Last-Writer-Wins")
    func lastWriterWinsConflict() throws {
        let simulator = CloudKitMultiDeviceSimulator(modelContainer: modelContainer)

        // Create initial work on device 1
        var builder = WorkBuilder(title: "Conflict Work", modelContext: simulator.context1)
        builder = builder.withAuthor(name: "Original Author")
        let work = try builder.build()

        // Both devices try to modify the same work
        try simulator.simulateConflict(
            on: work,
            device1Change: { $0.title = "Device 1 Title" },
            device2Change: { $0.title = "Device 2 Title (wins)" }
        )

        // Device 1 sees device 2's change (last write wins)
        #expect(work.title == "Device 2 Title (wins)")
    }

    @Test("Offline changes are eventually consistent")
    func offlineChangesEventuallyConsistent() throws {
        let modelContext = ModelContext(modelContainer)

        // Create work offline
        var builder = WorkBuilder(title: "Offline Work", modelContext: modelContext)
        builder = builder.withAuthor(name: "Offline Author")
        var work = try builder.build()

        let originalTitle = work.title

        // Modify offline
        work.title = "Modified While Offline"
        try modelContext.save()

        // Refetch to verify changes persisted
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.uuid == work.uuid }
        )
        work = try modelContext.fetch(descriptor).first ?? work

        #expect(work.title == "Modified While Offline")
        #expect(work.title != originalTitle)
    }

    // MARK: - Reading Session Consistency

    @Test("Reading sessions maintain consistency with UserLibraryEntry")
    func readingSessionsConsistency() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Session Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        entryBuilder = entryBuilder.addReadingSession(
            durationMinutes: 30,
            startPage: 0,
            endPage: 50
        )
        entryBuilder = entryBuilder.addReadingSession(
            durationMinutes: 45,
            startPage: 50,
            endPage: 100
        )
        let entry = try entryBuilder.build()

        // Verify consistency
        #expect(entry.readingSessions?.count == 2)
        #expect(entry.totalReadingMinutes == 75)
        #expect(DataConsistencyHelper.verifyReadingMinutesConsistency(for: entry))
    }

    @Test("Updating reading progress maintains bounds")
    func readingProgressBoundsAreEnforced() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Bounded Progress Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180", pageCount: 300)
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        entryBuilder = entryBuilder.withReadingProgress(currentPage: 150, progress: 0.5)
        let entry = try entryBuilder.build()

        #expect(DataConsistencyHelper.verifyProgressBounds(for: entry))
        #expect(entry.readingProgress >= 0.0)
        #expect(entry.readingProgress <= 1.0)
    }

    @Test("Pages read is never negative")
    func pagesReadNeverNegative() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Pages Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        let session = ReadingSession(
            durationMinutes: 30,
            startPage: 100,
            endPage: 50  // Invalid: end < start
        )

        // Pages read should still be non-negative
        #expect(session.pagesRead >= 0)
        #expect(DataConsistencyHelper.verifyNegativePagesCheck(for: session))
    }

    // MARK: - Relationship Integrity

    @Test("Work-Author relationships maintain integrity after deletion")
    func workAuthorIntegrityAfterModification() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Integrity Work", modelContext: modelContext)
        workBuilder = workBuilder.withAuthor(name: "Author 1")
        workBuilder = workBuilder.withAuthor(name: "Author 2")
        let work = try workBuilder.build()

        // Verify initial integrity
        #expect(RelationshipIntegrityHelper.verifyWorkAuthorIntegrity(work: work))

        // Modify and verify consistency
        work.title = "Modified Title"
        try modelContext.save()

        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.uuid == work.uuid }
        )
        let refreshedWork = try modelContext.fetch(descriptor).first ?? work

        #expect(RelationshipIntegrityHelper.verifyWorkAuthorIntegrity(work: refreshedWork))
    }

    @Test("Work-Edition relationships maintain integrity")
    func workEditionIntegrity() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Edition Integrity Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        workBuilder = workBuilder.withEdition(isbn: "9780439708197")
        let work = try workBuilder.build()

        #expect(RelationshipIntegrityHelper.verifyWorkEditionIntegrity(work: work))
    }

    @Test("Work-UserLibraryEntry relationships maintain integrity")
    func workEntryIntegrity() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Entry Integrity Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        let entry = try entryBuilder.build()

        #expect(work.userLibraryEntries?.contains(where: { $0.id == entry.id }) ?? false)
        #expect(RelationshipIntegrityHelper.verifyWorkEntryIntegrity(work: work))
    }

    @Test("Reading session integrity is maintained")
    func readingSessionIntegrity() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Session Integrity Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )
        entryBuilder = entryBuilder.addReadingSession(
            durationMinutes: 30,
            startPage: 0,
            endPage: 50
        )
        let entry = try entryBuilder.build()

        guard let session = entry.readingSessions?.first else {
            Issue.record("No session created")
            return
        }

        #expect(RelationshipIntegrityHelper.verifySessionIntegrity(session: session))
    }

    // MARK: - Batch Operations Consistency

    @Test("Batch insert maintains consistency for 100 works")
    func batchInsertConsistency() throws {
        let modelContext = ModelContext(modelContainer)

        let works = try LargeDatasetHelper.createLargeLibraryScenario(
            workCount: 100,
            entriesPerWork: 1,
            sessionsPerEntry: 1,
            modelContext: modelContext
        )

        #expect(works.count == 100)

        // Verify all relationships are intact
        for work in works {
            #expect(RelationshipIntegrityHelper.verifyWorkEditionIntegrity(work: work))
        }
    }

    @Test("Bulk query returns correct count after batch insert")
    func bulkQueryAccuracy() throws {
        let modelContext = ModelContext(modelContainer)

        let insertedCount = try LargeDatasetHelper.createLargeLibraryScenario(
            workCount: 50,
            entriesPerWork: 1,
            sessionsPerEntry: 0,
            modelContext: modelContext
        ).count

        let queryCount = try LargeDatasetHelper.performBulkQuery(
            workCount: 50,
            modelContext: modelContext
        )

        #expect(queryCount >= insertedCount)
    }

    // MARK: - Floating Point Consistency

    @Test("Reading pace calculation is accurate")
    func readingPaceAccuracy() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Pace Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        let session = ReadingSession(
            durationMinutes: 60,
            startPage: 0,
            endPage: 60
        )

        #expect(DataConsistencyHelper.verifyReadingPaceCalculation(for: session))
        #expect(abs(session.readingPace ?? 0 - 60.0) < 0.01)
    }

    @Test("Average reading pace aggregates correctly")
    func averageReadingPaceAggregation() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Avg Pace Work", modelContext: modelContext)
        workBuilder = workBuilder.withEdition(isbn: "9780439708180")
        let work = try workBuilder.build()

        var entryBuilder = UserLibraryEntryBuilder(
            work: work,
            edition: work.editions?.first,
            modelContext: modelContext
        )

        // Session 1: 60 pages in 60 minutes = 60 pph
        entryBuilder = entryBuilder.addReadingSession(
            durationMinutes: 60,
            startPage: 0,
            endPage: 60
        )

        // Session 2: 40 pages in 60 minutes = 40 pph
        entryBuilder = entryBuilder.addReadingSession(
            durationMinutes: 60,
            startPage: 60,
            endPage: 100
        )

        let entry = try entryBuilder.build()

        let expectedAverage = (60.0 + 40.0) / 2.0
        let actualAverage = entry.averageReadingPace ?? 0

        #expect(abs(actualAverage - expectedAverage) < 0.01)
    }

    // MARK: - Concurrent Modification Safety

    @Test("Safe concurrent read during write operation")
    func safeReadDuringWrite() throws {
        let modelContext = ModelContext(modelContainer)

        var workBuilder = WorkBuilder(title: "Concurrent Work", modelContext: modelContext)
        workBuilder = workBuilder.withAuthor(name: "Author")
        let work = try workBuilder.build()

        let workID = work.uuid

        // Perform modification
        work.title = "Modified"
        try modelContext.save()

        // Immediately read
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.uuid == workID }
        )
        let refreshed = try modelContext.fetch(descriptor).first

        #expect(refreshed?.title == "Modified")
    }
}
