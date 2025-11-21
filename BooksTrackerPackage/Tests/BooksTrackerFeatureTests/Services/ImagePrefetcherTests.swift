import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("ImagePrefetcher")
@MainActor
struct ImagePrefetcherTests {
    @Test("cancelPrefetching clears task and is idempotent")
    func cancelPrefetching_isIdempotent() {
        let prefetcher = ImagePrefetcher()

        // Starting without URLs should still create/cancel safely
        prefetcher.startPrefetching(urls: [])
        prefetcher.cancelPrefetching()
        // Second cancel should not crash
        prefetcher.cancelPrefetching()

        // Start again with empty URLs to avoid network dependency
        prefetcher.startPrefetching(urls: [])
        prefetcher.cancelPrefetching()
    }
}
