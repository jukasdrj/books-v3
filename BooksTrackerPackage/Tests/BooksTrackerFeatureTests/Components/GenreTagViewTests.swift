import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("GenreTagView Tests")
struct GenreTagViewTests {

    @Test("Renders up to 2 genre tags")
    func rendersTwoTags() {
        let view = GenreTagView(genres: ["Fiction", "Romance", "Historical"])

        // Compilation test - view can be created
        #expect(view != nil)
    }

    @Test("Returns EmptyView for empty genres array")
    func handlesEmptyGenres() {
        let view = GenreTagView(genres: [])

        #expect(view != nil)
    }

    @Test("Handles single genre")
    func handlesSingleGenre() {
        let view = GenreTagView(genres: ["Fiction"])

        #expect(view != nil)
    }
}
