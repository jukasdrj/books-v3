import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("ImageCleanupService Performance")
struct ImageCleanupServiceTests {

    @Test("Cleanup uses predicate filtering")
    func testCleanupUsesPredicateFiltering() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Create 100 works without images (should be filtered out by predicate)
        for i in 0..<100 {
            let work = Work(title: "Book \(i)")
            context.insert(work)
            work.originalImagePath = nil // No image
        }

        // Create 1 work with image
        let workWithImage = Work(title: "Scanned Book")
        context.insert(workWithImage)
        workWithImage.originalImagePath = "/tmp/scan.jpg"
        workWithImage.reviewStatus = .verified

        try context.save()

        let start = CFAbsoluteTimeGetCurrent()
        await ImageCleanupService.shared.cleanupReviewedImages(in: context)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ ImageCleanup (100 works, 1 image): \(Int(elapsed))ms")
        #expect(elapsed < 100) // Should be fast with predicate filtering
    }

    @Test("Cleanup with no images is instant")
    func testCleanupWithNoImages() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        let start = CFAbsoluteTimeGetCurrent()
        await ImageCleanupService.shared.cleanupReviewedImages(in: context)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ ImageCleanup (no images): \(Int(elapsed))ms")
        #expect(elapsed < 10) // Should be instant
    }
}
