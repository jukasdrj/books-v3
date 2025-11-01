//
//  PrimaryEditionTests.swift
//  BooksTrackerFeatureTests
//
//  Created by Jules on 10/31/25.
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Work PrimaryEdition Tests")
@MainActor
struct PrimaryEditionTests {

    var container: ModelContainer!
    var context: ModelContext!

    init() {
        do {
            container = try ModelContainer(
                for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    @Test("Test Manual Selection")
    func testManualSelection() {
        let work = Work(title: "Test Book")
        let edition1 = Edition(publicationDate: "2021")
        let edition2 = Edition(publicationDate: "2022")
        let userEntry = UserLibraryEntry()

        context.insert(work)
        context.insert(edition1)
        context.insert(edition2)
        context.insert(userEntry)

        // Link relationships (insert-before-relate)
        edition1.work = work
        edition2.work = work
        work.editions = [edition1, edition2]
        work.userLibraryEntries = [userEntry]
        userEntry.work = work
        userEntry.preferredEdition = edition2

        FeatureFlags.shared.coverSelectionStrategy = .manual

        #expect(work.primaryEdition == edition2, "Primary edition should be the preferred edition")
    }

    @Test("Test Manual Selection Fallback")
    func testManualSelectionFallback() {
        let work = Work(title: "Test Book")
        let edition1 = Edition(publicationDate: "2021")
        let edition2 = Edition(publicationDate: "2022")
        let userEntry = UserLibraryEntry()

        context.insert(work)
        context.insert(edition1)
        context.insert(edition2)
        context.insert(userEntry)

        // Set quality scores
        edition1.isbndbQuality = 80
        edition2.isbndbQuality = 90

        // Link relationships (insert-before-relate)
        edition1.work = work
        edition2.work = work
        work.editions = [edition1, edition2]
        work.userLibraryEntries = [userEntry]
        userEntry.work = work

        FeatureFlags.shared.coverSelectionStrategy = .manual

        #expect(work.primaryEdition == edition2, "Primary edition should fallback to the highest quality edition")
    }
}
