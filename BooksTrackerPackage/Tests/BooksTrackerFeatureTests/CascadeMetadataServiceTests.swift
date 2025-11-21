import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("CascadeMetadataService Tests")
struct CascadeMetadataServiceTests {

    /// Helper to set up the test environment with a fresh ModelContext and service
    private func setupService() throws -> (ModelContext, CascadeMetadataService) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AuthorMetadata.self, WorkOverride.self, BookEnrichment.self,
            configurations: config
        )
        let context = ModelContext(container)
        let service = CascadeMetadataService(modelContext: context)
        return (context, service)
    }

    @Test("Fetch or create author metadata - creates new")
    func testFetchOrCreateAuthorMetadataCreatesNew() throws {
        // Given
        let (context, service) = try setupService()
        let authorId = "author-1"
        let userId = "user-1"

        // When
        let metadata = try service.fetchOrCreateAuthorMetadata(authorId: authorId, userId: userId)
        try context.save()

        // Then
        #expect(metadata.authorId == authorId)
        #expect(metadata.contributedBy == userId)
        #expect(metadata.culturalBackground.isEmpty)
        #expect(metadata.cascadedToWorkIds.isEmpty)
    }

    @Test("Fetch or create author metadata - fetches existing")
    func testFetchOrCreateAuthorMetadataFetchesExisting() throws {
        // Given
        let (context, service) = try setupService()
        let authorId = "author-2"
        let userId = "user-1"

        // Create initial metadata
        let initialMetadata = AuthorMetadata(
            authorId: authorId,
            culturalBackground: ["Japanese"],
            genderIdentity: "Female",
            contributedBy: userId
        )
        context.insert(initialMetadata)
        try context.save()

        // When
        let fetchedMetadata = try service.fetchOrCreateAuthorMetadata(authorId: authorId, userId: userId)

        // Then
        #expect(fetchedMetadata.persistentModelID == initialMetadata.persistentModelID)
        #expect(fetchedMetadata.culturalBackground == ["Japanese"])
        #expect(fetchedMetadata.genderIdentity == "Female")
    }

    @Test("Fetch or create enrichment - creates new")
    func testFetchOrCreateEnrichmentCreatesNew() throws {
        // Given
        let (context, service) = try setupService()
        let workId = "work-1"

        // When
        let enrichment = try service.fetchOrCreateEnrichment(workId: workId)
        try context.save()

        // Then
        #expect(enrichment.workId == workId)
        #expect(enrichment.genres.isEmpty)
        #expect(enrichment.themes.isEmpty)
        #expect(enrichment.isCascaded == false)
    }

    @Test("Fetch or create enrichment - fetches existing")
    func testFetchOrCreateEnrichmentFetchesExisting() throws {
        // Given
        let (context, service) = try setupService()
        let workId = "work-2"

        // Create initial enrichment
        let initialEnrichment = BookEnrichment(
            workId: workId,
            userRating: 5,
            genres: ["Fiction"],
            authorCulturalBackground: "Japanese"
        )
        context.insert(initialEnrichment)
        try context.save()

        // When
        let fetchedEnrichment = try service.fetchOrCreateEnrichment(workId: workId)

        // Then
        #expect(fetchedEnrichment.persistentModelID == initialEnrichment.persistentModelID)
        #expect(fetchedEnrichment.userRating == 5)
        #expect(fetchedEnrichment.genres == ["Fiction"])
        #expect(fetchedEnrichment.authorCulturalBackground == "Japanese")
    }

    @Test("Create work override for valid field")
    func testCreateWorkOverrideValidField() throws {
        // Given
        let (context, service) = try setupService()
        let authorId = "author-3"
        let workId = "work-3"
        let userId = "user-1"

        // Create author metadata first
        let metadata = AuthorMetadata(
            authorId: authorId,
            culturalBackground: ["Default Culture"],
            contributedBy: userId
        )
        context.insert(metadata)
        try context.save()

        // When
        try service.createOverride(
            authorId: authorId,
            workId: workId,
            field: "culturalBackground",
            customValue: "Override Culture",
            reason: "Test reason"
        )

        // Then
        let descriptor = FetchDescriptor<WorkOverride>(
            predicate: #Predicate {
                $0.authorMetadata?.authorId == authorId &&
                $0.workId == workId &&
                $0.field == "culturalBackground"
            }
        )
        let overrides = try context.fetch(descriptor)
        #expect(overrides.count == 1)
        #expect(overrides.first?.customValue == "Override Culture")
        #expect(overrides.first?.reason == "Test reason")
    }

    @Test("Create work override for invalid field throws error")
    func testCreateWorkOverrideInvalidField() throws {
        // Given
        let (context, service) = try setupService()
        let authorId = "author-4"
        let workId = "work-4"
        let userId = "user-1"

        // Create author metadata first
        let metadata = AuthorMetadata(authorId: authorId, contributedBy: userId)
        context.insert(metadata)
        try context.save()

        // When/Then
        #expect(throws: CascadeMetadataServiceError.invalidFieldForOverride("invalidField")) {
            try service.createOverride(
                authorId: authorId,
                workId: workId,
                field: "invalidField",
                customValue: "Test",
                reason: nil
            )
        }
    }

    @Test("BookEnrichment completion percentage calculated correctly")
    func testCompletionPercentageCalculation() throws {
        // Given: All fields filled (7/7)
        let fullEnrichment = BookEnrichment(
            workId: "work-full",
            userRating: 5,
            genres: ["Fiction"],
            themes: ["Adventure"],
            contentWarnings: ["Violence"],
            personalNotes: "Great book!",
            authorCulturalBackground: "Japanese",
            authorGenderIdentity: "Female"
        )

        // Then
        #expect(fullEnrichment.completionPercentage == 1.0)

        // Given: Partial fields filled (3/7)
        let partialEnrichment = BookEnrichment(
            workId: "work-partial",
            userRating: 4,
            genres: ["Mystery"],
            authorCulturalBackground: "British"
        )

        // Then
        let expectedPartial = 3.0 / 7.0
        #expect(abs(partialEnrichment.completionPercentage - expectedPartial) < 0.01)

        // Given: No fields filled (0/7)
        let emptyEnrichment = BookEnrichment(workId: "work-empty")

        // Then
        #expect(emptyEnrichment.completionPercentage == 0.0)
    }

    @Test("AuthorMetadata stores multiple cultural backgrounds")
    func testMultipleCulturalBackgrounds() throws {
        // Given
        let metadata = AuthorMetadata(
            authorId: "author-multi",
            culturalBackground: ["Japanese", "American"],
            contributedBy: "user-1"
        )

        // Then
        #expect(metadata.culturalBackground.count == 2)
        #expect(metadata.culturalBackground.contains("Japanese"))
        #expect(metadata.culturalBackground.contains("American"))
    }

    @Test("WorkOverride tracks creation date")
    func testWorkOverrideCreationDate() throws {
        // Given
        let beforeCreate = Date()
        let override = WorkOverride(
            workId: "work-test",
            field: "culturalBackground",
            customValue: "Test"
        )
        let afterCreate = Date()

        // Then
        #expect(override.createdAt >= beforeCreate)
        #expect(override.createdAt <= afterCreate)
    }

    @Test("AuthorMetadata cascadedToWorkIds tracks work IDs")
    func testCascadedToWorkIdsTracking() throws {
        // Given
        let metadata = AuthorMetadata(
            authorId: "author-track",
            cascadedToWorkIds: ["work-1", "work-2", "work-3"],
            contributedBy: "user-1"
        )

        // Then
        #expect(metadata.cascadedToWorkIds.count == 3)
        #expect(metadata.cascadedToWorkIds.contains("work-1"))
        #expect(metadata.cascadedToWorkIds.contains("work-2"))
        #expect(metadata.cascadedToWorkIds.contains("work-3"))
    }

    @Test("BookEnrichment isCascaded flag defaults to false")
    func testIsCascadedDefaultsFalse() throws {
        // Given
        let enrichment = BookEnrichment(workId: "work-default")

        // Then
        #expect(enrichment.isCascaded == false)
    }
}
