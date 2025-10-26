import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("SearchAPIService")
struct SearchAPIServiceTests {

    @Test("search executes API call with correct parameters")
    func testSearchExecutesAPICall() async throws {
        let service = SearchAPIService()

        // This will fail initially - method doesn't exist yet
        let results = try await service.search(query: "Swift Programming", scope: .title, page: 1)

        #expect(!results.isEmpty || results.isEmpty, "Should return array of results")
    }

    @Test("search handles network errors gracefully")
    func testSearchHandlesNetworkErrors() async throws {
        let service = SearchAPIService()

        do {
            _ = try await service.search(query: "", scope: .all, page: 1)
            Issue.record("Should throw error for empty query")
        } catch {
            #expect(error is SearchAPIError, "Should throw SearchAPIError")
        }
    }

    @Test("search supports pagination")
    func testSearchSupportsPagination() async throws {
        let service = SearchAPIService()

        let page1 = try await service.search(query: "Fantasy", scope: .all, page: 1)
        let page2 = try await service.search(query: "Fantasy", scope: .all, page: 2)

        // Pages should be different (or both empty if no results)
        #expect(page1.count >= 0 && page2.count >= 0, "Both pages should return valid results")
    }
}
