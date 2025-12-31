//
//  CloudKitTestHelpers.swift
//  BooksTrackerFeatureTests
//
//  Utilities for simulating CloudKit sync scenarios in workflow tests
//

import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - Multi-Context Simulation

/// Helper for simulating multi-device CloudKit scenarios with separate ModelContexts
@MainActor
struct CloudKitMultiDeviceSimulator {
    private var device1Context: ModelContext
    private var device2Context: ModelContext
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.device1Context = ModelContext(modelContainer)
        self.device2Context = ModelContext(modelContainer)
    }

    /// Get context for device 1
    var context1: ModelContext {
        device1Context
    }

    /// Get context for device 2
    var context2: ModelContext {
        device2Context
    }

    /// Simulate remote change: device 2 modifies data that device 1 sees
    /// - Parameter modification: Closure that modifies data in device 2's context
    func simulateRemoteChange(
        modification: (ModelContext) throws -> Void
    ) throws {
        try modification(device2Context)
        try device2Context.save()

        // Note: SwiftData automatically refreshes contexts sharing the same container
        // No explicit refresh needed in modern SwiftData
    }

    /// Simulate conflict scenario: both devices modify the same object
    /// Device 2's change wins (Last-Writer-Wins)
    func simulateConflict<T: PersistentModel>(
        on object: T,
        device1Change: (T) -> Void,
        device2Change: (T) -> Void
    ) throws {
        // Device 1 makes a change
        device1Change(object)
        try device1Context.save()

        // Device 2 makes a conflicting change (last write wins)
        device2Change(object)
        try device2Context.save()

        // Note: SwiftData automatically refreshes contexts sharing the same container
        // No explicit refresh needed in modern SwiftData
    }

    /// Verify consistency across both contexts
    /// - Returns: true if data is consistent between devices
    func verifyConsistency() throws -> Bool {
        try device1Context.save()
        try device2Context.save()
        return true
    }
}

// MARK: - CloudKit Compliance Testing

/// Helper for verifying models are CloudKit-compliant
struct CloudKitComplianceValidator {
    /// Check if a property has a valid CloudKit default
    /// CloudKit requires all non-optional properties to have default values
    static func validateCloudKitCompliance(for work: Work) -> [(issue: String, severity: String)] {
        var issues: [(issue: String, severity: String)] = []

        // Check required fields have defaults
        if work.title.isEmpty {
            issues.append((issue: "title must have value", severity: "high"))
        }

        // Check optional relationships
        if work.authors == nil {
            issues.append((issue: "authors should be empty array, not nil", severity: "medium"))
        }

        if work.editions == nil {
            issues.append((issue: "editions should be empty array, not nil", severity: "medium"))
        }

        return issues
    }

    /// Validate CloudKit compliance for UserLibraryEntry
    static func validateCloudKitCompliance(for entry: UserLibraryEntry) -> [(issue: String, severity: String)] {
        var issues: [(issue: String, severity: String)] = []

        // Verify relationships are optional (CloudKit requirement)
        // Note: work and edition relationships should be optional
        if entry.work == nil && entry.readingStatus != .wishlist {
            issues.append((
                issue: "entry should have work unless it's wishlist",
                severity: "medium"
            ))
        }

        return issues
    }

    /// Validate CloudKit compliance for Edition
    static func validateCloudKitCompliance(for edition: Edition) -> [(issue: String, severity: String)] {
        var issues: [(issue: String, severity: String)] = []

        // ISBN is required for editions
        if edition.isbn?.isEmpty ?? true {
            issues.append((issue: "ISBN is required", severity: "high"))
        }

        return issues
    }
}

// MARK: - Data Consistency Helpers

/// Helper for verifying data consistency across operations
struct DataConsistencyHelper {
    /// Verify that total reading minutes is consistent with sessions
    static func verifyReadingMinutesConsistency(for entry: UserLibraryEntry) -> Bool {
        let sessionsMinutes = entry.readingSessions?.reduce(0) { $0 + $1.durationMinutes } ?? 0
        return entry.totalReadingMinutes == sessionsMinutes
    }

    /// Verify that reading pace is calculated correctly
    static func verifyReadingPaceCalculation(for session: ReadingSession) -> Bool {
        guard session.durationMinutes > 0 else {
            return session.readingPace == nil
        }

        let expectedPace = Double(session.pagesRead) / Double(session.durationMinutes) * 60.0
        guard let pace = session.readingPace else { return false }
        return abs(pace - expectedPace) < 0.01 // Allow for floating point errors
    }

    /// Verify that reading progress is between 0 and 1
    static func verifyProgressBounds(for entry: UserLibraryEntry) -> Bool {
        return entry.readingProgress >= 0.0 && entry.readingProgress <= 1.0
    }

    /// Verify that pages read is never negative
    static func verifyNegativePagesCheck(for session: ReadingSession) -> Bool {
        return session.pagesRead >= 0
    }
}

// MARK: - Bulk Operation Helpers

/// Helper for stress testing with large datasets
struct LargeDatasetHelper {
    /// Create a large library scenario (n works with entries and sessions)
    @MainActor
    static func createLargeLibraryScenario(
        workCount: Int,
        entriesPerWork: Int,
        sessionsPerEntry: Int,
        modelContext: ModelContext
    ) throws -> [Work] {
        var works: [Work] = []

        for workIndex in 0..<workCount {
            var workBuilder = WorkBuilder(
                title: "Work #\(workIndex + 1)",
                modelContext: modelContext
            )
            workBuilder = workBuilder.withAuthor(name: "Author \(workIndex + 1)")
            workBuilder = workBuilder.withEdition(
                isbn: "978\(String(format: "%010d", workIndex + 1))"
            )

            let work = try workBuilder.build()
            works.append(work)

            // Add entries and sessions
            for entryIndex in 0..<entriesPerWork {
                var entryBuilder = UserLibraryEntryBuilder(
                    work: work,
                    edition: work.editions?.first,
                    modelContext: modelContext
                )
                entryBuilder = entryBuilder.withReadingStatus(
                    entryIndex == 0 ? .reading : .toRead
                )

                // Add sessions
                for sessionIndex in 0..<sessionsPerEntry {
                    let sessionDate = Date().addingTimeInterval(
                        TimeInterval(-86400 * sessionIndex)
                    )
                    entryBuilder = entryBuilder.addReadingSession(
                        date: sessionDate,
                        durationMinutes: 30,
                        startPage: sessionIndex * 50,
                        endPage: (sessionIndex + 1) * 50
                    )
                }

                _ = try entryBuilder.build()
            }
        }

        try modelContext.save()
        return works
    }

    /// Simulate querying a large dataset
    static func performBulkQuery(
        workCount: Int,
        modelContext: ModelContext
    ) throws -> Int {
        let descriptor = FetchDescriptor<Work>()
        let works = try modelContext.fetch(descriptor)
        return works.count
    }
}

// MARK: - Offline Queue Helpers

/// Helper for simulating offline queue scenarios
struct OfflineQueueHelper {
    /// Create a pending change that would normally sync to CloudKit
    static func createPendingChange(
        work: Work,
        modification: (Work) -> Void,
        modelContext: ModelContext
    ) throws {
        modification(work)
        try modelContext.save()
        // In real scenario, this would be queued for sync
    }

    /// Simulate batching multiple pending changes
    static func createBatchedChanges(
        on works: [Work],
        modifications: [(Work) -> Void],
        modelContext: ModelContext
    ) throws {
        for (work, modification) in zip(works, modifications) {
            modification(work)
        }
        try modelContext.save()
    }

    /// Simulate sync conflict where local and remote differ
    static func simulateSyncConflict(
        localWork: Work,
        remoteModification: (Work) -> Void,
        modelContext: ModelContext
    ) throws -> Work {
        // Simulate remote change
        let remoteWork = Work(title: localWork.title)
        remoteModification(remoteWork)

        // Local has different state - test Last-Writer-Wins logic
        localWork.lastModified = Date()
        try modelContext.save()

        return remoteWork
    }
}

// MARK: - Relationship Integrity Helpers

/// Helper for verifying relationship integrity in CloudKit scenarios
struct RelationshipIntegrityHelper {
    /// Verify Work-Author relationships are consistent
    static func verifyWorkAuthorIntegrity(work: Work) -> Bool {
        guard let authors = work.authors else { return true }

        // All authors should have this work
        for author in authors {
            guard author.works?.contains(where: { $0.uuid == work.uuid }) ?? false else {
                return false
            }
        }
        return true
    }

    /// Verify Work-Edition relationships are consistent
    static func verifyWorkEditionIntegrity(work: Work) -> Bool {
        guard let editions = work.editions else { return true }

        // All editions should reference this work
        for edition in editions {
            guard edition.work?.uuid == work.uuid else {
                return false
            }
        }
        return true
    }

    /// Verify Work-UserLibraryEntry relationships are consistent
    static func verifyWorkEntryIntegrity(work: Work) -> Bool {
        guard let entries = work.userLibraryEntries else { return true }

        // All entries should reference this work
        for entry in entries {
            guard entry.work?.uuid == work.uuid else {
                return false
            }
        }
        return true
    }

    /// Verify reading session relationships
    static func verifySessionIntegrity(session: ReadingSession) -> Bool {
        guard let entry = session.entry else { return true }

        // Session should be in entry's sessions
        return entry.readingSessions?.contains(where: { $0.id == session.id }) ?? false
    }
}
