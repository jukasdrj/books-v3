import Testing
@testable import BooksTrackerFeature

@Suite("SearchCoordinator Tests")
@MainActor
struct SearchCoordinatorTests {

    @Test("Setting pending search stores author name")
    func setPendingSearch() {
        let coordinator = SearchCoordinator()

        coordinator.setPendingAuthorSearch("Kazuo Ishiguro")

        #expect(coordinator.pendingAuthorSearch == "Kazuo Ishiguro")
    }

    @Test("Consuming pending search clears it")
    func consumePendingSearch() {
        let coordinator = SearchCoordinator()
        coordinator.setPendingAuthorSearch("Taylor Jenkins Reid")

        let author = coordinator.consumePendingAuthorSearch()

        #expect(author == "Taylor Jenkins Reid")
        #expect(coordinator.pendingAuthorSearch == nil)
    }

    @Test("Consuming nil search returns nil")
    func consumeNilSearch() {
        let coordinator = SearchCoordinator()

        let author = coordinator.consumePendingAuthorSearch()

        #expect(author == nil)
    }
}
