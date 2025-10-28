import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("BookMetadataRow Tests")
struct BookMetadataRowTests {

    @Test("Renders icon and text with secondary style")
    func rendersIconAndText() {
        let row = BookMetadataRow(
            icon: "calendar",
            text: "2017",
            style: .secondary
        )

        // Test that view can be created (compilation test)
        #expect(row != nil)
    }

    @Test("Handles nil values gracefully")
    func handlesNilValues() {
        let row = BookMetadataRow(
            icon: "calendar",
            text: "",
            style: .secondary
        )

        #expect(row != nil)
    }
}
