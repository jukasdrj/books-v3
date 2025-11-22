import Testing
import SwiftUI
import SwiftData
@testable import BooksTrackerFeature

// MARK: - Sprint 3 Components Tests

@Suite("Sprint 3 UI Components Tests")
struct Sprint3ComponentsTests {

    // MARK: - Test Helpers

    /// Creates an in-memory ModelContainer for testing purposes.
    static func createTestModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: BookEnrichment.self, Work.self, Author.self, AuthorMetadata.self, WorkOverride.self,
            configurations: config
        )
    }

    // MARK: - BookEnrichment Model Tests

    @Suite("BookEnrichment.completionPercentage Tests")
    struct BookEnrichmentCompletionPercentageTests {
        @Test("0% completion when all fields are empty/nil")
        func testZeroCompletion() throws {
            let enrichment = BookEnrichment(workId: "test-work-0")
            #expect(enrichment.completionPercentage == 0.0)
        }

        @Test("Partial completion with one field filled")
        func testPartialCompletionOneField() throws {
            let enrichment = BookEnrichment(workId: "test-work-1", userRating: 3) // 1/7 fields
            #expect(enrichment.completionPercentage == 1.0 / 7.0)
        }

        @Test("Partial completion with multiple fields filled")
        func testPartialCompletionMultipleFields() throws {
            let enrichment = BookEnrichment(
                workId: "test-work-3",
                userRating: 4,
                genres: ["Fantasy"],
                personalNotes: "Great read."
            ) // 3/7 fields
            #expect(enrichment.completionPercentage == 3.0 / 7.0)
        }

        @Test("100% completion when all fields are filled")
        func testFullCompletion() throws {
            let enrichment = BookEnrichment(
                workId: "test-work-full",
                userRating: 5,
                genres: ["Sci-Fi"],
                themes: ["Dystopian"],
                contentWarnings: ["Violence"],
                personalNotes: "A masterpiece.",
                authorCulturalBackground: "Japanese",
                authorGenderIdentity: "Female"
            ) // 7/7 fields
            #expect(enrichment.completionPercentage == 1.0)
        }

        @Test("String fields with empty string are not considered filled")
        func testEmptyStringFields() throws {
            let enrichment = BookEnrichment(
                workId: "test-work-empty-strings",
                personalNotes: "", // Should not count
                authorCulturalBackground: "", // Should not count
                authorGenderIdentity: "" // Should not count
            ) // 0/7 fields
            #expect(enrichment.completionPercentage == 0.0)
        }

        @Test("Empty arrays are not considered filled")
        func testEmptyArrayFields() throws {
            let enrichment = BookEnrichment(
                workId: "test-work-empty-arrays",
                genres: [], // Should not count
                themes: [], // Should not count
                contentWarnings: [] // Should not count
            ) // 0/7 fields
            #expect(enrichment.completionPercentage == 0.0)
        }
    }

    // MARK: - RatingsCard Tests

    @Suite("RatingsCard Tests")
    struct RatingsCardTests {
        @Test("RatingsCard can be initialized with BookEnrichment")
        func testInitialization() throws {
            let enrichment = BookEnrichment(workId: "book1", userRating: 4)
            let card = RatingsCard(enrichment: enrichment)

            // Verify initialization doesn't throw
            #expect(card.enrichment.workId == "book1")
            #expect(card.enrichment.userRating == 4)
        }

        @Test("RatingsCard renders with nil user rating")
        func testRenderingWithNilUserRating() throws {
            let enrichment = BookEnrichment(workId: "book2", userRating: nil)
            let card = RatingsCard(enrichment: enrichment)

            #expect(card.enrichment.userRating == nil)
        }

        @Test("RatingsCard renders with user rating of 1")
        func testRenderingWithMinUserRating() throws {
            let enrichment = BookEnrichment(workId: "book3", userRating: 1)
            let card = RatingsCard(enrichment: enrichment)

            #expect(card.enrichment.userRating == 1)
        }

        @Test("RatingsCard renders with user rating of 5")
        func testRenderingWithMaxUserRating() throws {
            let enrichment = BookEnrichment(workId: "book4", userRating: 5)
            let card = RatingsCard(enrichment: enrichment)

            #expect(card.enrichment.userRating == 5)
        }
    }

    // MARK: - EnrichmentCompletionWidget Tests

    @Suite("EnrichmentCompletionWidget Tests")
    struct EnrichmentCompletionWidgetTests {

        @Test("EnrichmentCompletionWidget can be initialized")
        func testInitialization() throws {
            let enrichment = BookEnrichment(workId: "w0")
            let widget = EnrichmentCompletionWidget(enrichment: enrichment)

            #expect(widget.enrichment.workId == "w0")
        }

        @Test("Widget shows 0% completion for empty enrichment")
        func testZeroCompletion() throws {
            let enrichment = BookEnrichment(workId: "zero")
            let widget = EnrichmentCompletionWidget(enrichment: enrichment)

            #expect(widget.enrichment.completionPercentage == 0.0)
        }

        @Test("Widget shows partial completion")
        func testPartialCompletion() throws {
            let enrichment = BookEnrichment(
                workId: "partial",
                userRating: 3,
                genres: ["Fiction"],
                themes: ["Adventure"]
            ) // 3/7 fields
            let widget = EnrichmentCompletionWidget(enrichment: enrichment)

            #expect(widget.enrichment.completionPercentage == 3.0 / 7.0)
        }

        @Test("Widget shows 100% completion")
        func testFullCompletion() throws {
            let enrichment = BookEnrichment(
                workId: "full",
                userRating: 5,
                genres: ["Sci-Fi"],
                themes: ["Dystopian"],
                contentWarnings: ["Violence"],
                personalNotes: "Great!",
                authorCulturalBackground: "Japanese",
                authorGenderIdentity: "Female"
            ) // 7/7 fields
            let widget = EnrichmentCompletionWidget(enrichment: enrichment)

            #expect(widget.enrichment.completionPercentage == 1.0)
        }
    }

    // MARK: - OverrideSheet Tests

    @Suite("OverrideSheet Tests")
    struct OverrideSheetTests {
        @Test("OverrideSheet can be initialized")
        func testInitialization() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext

            let author = Author(name: "Test Author")
            let work = Work(title: "Test Work")
            context.insert(author)
            context.insert(work)
            work.authors = [author]

            let metadata = AuthorMetadata(
                authorId: author.persistentModelID.hashValue.description,
                contributedBy: "test-user"
            )
            metadata.culturalBackground = ["Japanese"]
            metadata.genderIdentity = "Female"
            context.insert(metadata)

            let sheet = OverrideSheet(
                work: work,
                authorMetadata: metadata,
                onSave: {}
            )

            #expect(sheet.work.title == "Test Work")
            #expect(sheet.authorMetadata.culturalBackground == ["Japanese"])
        }

        @Test("OverrideSheet initializes with empty metadata")
        func testInitializationWithEmptyMetadata() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext

            let author = Author(name: "Empty Author")
            let work = Work(title: "Empty Work")
            context.insert(author)
            context.insert(work)

            let metadata = AuthorMetadata(
                authorId: author.persistentModelID.hashValue.description,
                contributedBy: "test-user"
            )
            // Leave metadata empty
            context.insert(metadata)

            let sheet = OverrideSheet(
                work: work,
                authorMetadata: metadata,
                onSave: {}
            )

            #expect(sheet.authorMetadata.culturalBackground.isEmpty)
            #expect(sheet.authorMetadata.genderIdentity == nil)
            #expect(sheet.authorMetadata.nationality.isEmpty)
        }
    }

    // MARK: - AuthorProfileView Tests

    @Suite("AuthorProfileView Tests")
    struct AuthorProfileViewTests {
        @Test("AuthorProfileView can be initialized with authorId")
        func testInitialization() throws {
            let view = AuthorProfileView(authorId: "test-author-123")

            #expect(view.authorId == "test-author-123")
        }

        @Test("AuthorProfileView handles empty authorId")
        func testEmptyAuthorId() throws {
            let view = AuthorProfileView(authorId: "")

            #expect(view.authorId == "")
        }

        @Test("AuthorProfileView handles valid UUID string")
        func testValidUUIDAuthorId() throws {
            let uuid = UUID().uuidString
            let view = AuthorProfileView(authorId: uuid)

            #expect(view.authorId == uuid)
        }
    }

    // MARK: - Integration Tests

    @Suite("Sprint 3 Component Integration Tests")
    struct IntegrationTests {
        @Test("BookEnrichment can be created and persisted")
        func testBookEnrichmentPersistence() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext

            let enrichment = BookEnrichment(
                workId: "integration-test-1",
                userRating: 4,
                genres: ["Fantasy", "Adventure"]
            )
            context.insert(enrichment)

            try context.save()

            // Fetch back
            let descriptor = FetchDescriptor<BookEnrichment>(
                predicate: #Predicate<BookEnrichment> { e in
                    e.workId == "integration-test-1"
                }
            )
            let fetched = try context.fetch(descriptor)

            #expect(fetched.count == 1)
            #expect(fetched.first?.userRating == 4)
            #expect(fetched.first?.genres.count == 2)
        }

        @Test("AuthorMetadata can be created and persisted")
        func testAuthorMetadataPersistence() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext

            let metadata = AuthorMetadata(
                authorId: "author-123",
                contributedBy: "test-user"
            )
            metadata.culturalBackground = ["Japanese", "American"]
            metadata.genderIdentity = "Female"
            metadata.nationality = ["Japanese"]
            context.insert(metadata)

            try context.save()

            // Fetch back
            let descriptor = FetchDescriptor<AuthorMetadata>(
                predicate: #Predicate<AuthorMetadata> { m in
                    m.authorId == "author-123"
                }
            )
            let fetched = try context.fetch(descriptor)

            #expect(fetched.count == 1)
            #expect(fetched.first?.culturalBackground.count == 2)
            #expect(fetched.first?.genderIdentity == "Female")
        }

        @Test("WorkOverride can be created with relationship to AuthorMetadata")
        func testWorkOverrideWithAuthorMetadata() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext

            let metadata = AuthorMetadata(
                authorId: "author-456",
                contributedBy: "test-user"
            )
            context.insert(metadata)

            let override = WorkOverride(
                workId: "work-789",
                field: "culturalBackground",
                customValue: "Custom Value",
                reason: "User preference"
            )
            override.authorMetadata = metadata
            context.insert(override)

            try context.save()

            // Fetch back
            let descriptor = FetchDescriptor<WorkOverride>(
                predicate: #Predicate<WorkOverride> { o in
                    o.workId == "work-789"
                }
            )
            let fetched = try context.fetch(descriptor)

            #expect(fetched.count == 1)
            #expect(fetched.first?.field == "culturalBackground")
            #expect(fetched.first?.customValue == "Custom Value")
            #expect(fetched.first?.authorMetadata?.authorId == "author-456")
        }
    }
}
