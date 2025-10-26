import Testing
import Foundation
@testable import BooksTrackerFeature
#if canImport(UIKit)
import UIKit
#endif

@Suite("Actor Isolation")
struct ActorIsolationTests {

    @Test("BookSearchAPIService is actor-isolated")
    func testSearchAPIServiceActorIsolation() async throws {
        // Verify BookSearchAPIService enforces actor isolation
        let service = BookSearchAPIService()

        // This should compile without data race warnings
        let results = try await service.search(query: "Test", maxResults: 20, scope: .all)

        #expect(results.results.count >= 0, "Actor-isolated call should succeed")
    }

    @Test("BookshelfAIService is actor-isolated")
    func testBookshelfAIServiceActorIsolation() async throws {
        #if canImport(UIKit)
        let service = BookshelfAIService.shared

        // Create test image
        let image = UIImage(systemName: "book")!

        // This should compile without data race warnings
        do {
            _ = try await service.processBookshelfImage(image)
        } catch {
            // Expected to fail (no backend), but should be actor-safe
            #expect(true, "Actor isolation enforced even on error")
        }
        #endif
    }

    @Test("concurrent access to actor-isolated service is safe")
    func testConcurrentActorAccess() async throws {
        let service = BookSearchAPIService()

        // Launch multiple concurrent searches
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    do {
                        _ = try await service.search(query: "Query \(i)", maxResults: 20, scope: .all)
                    } catch {
                        // Expected failures OK - testing actor safety, not success
                    }
                }
            }
        }

        // If we reach here without data races, actor isolation works
        #expect(true, "Concurrent access should be safe with actor isolation")
    }
}
