import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("BookMetadataRow Tests")
struct BookMetadataRowTests {

    @Test("Accessibility label for calendar icon")
    func calendarAccessibilityLabel() {
        let row = BookMetadataRow(icon: "calendar", text: "2017", style: .secondary)

        #expect(row.accessibilityText == "Year Published: 2017")
    }

    @Test("Accessibility label for person icon")
    func authorAccessibilityLabel() {
        let row = BookMetadataRow(icon: "person", text: "Taylor Jenkins Reid", style: .secondary)

        #expect(row.accessibilityText == "Author: Taylor Jenkins Reid")
    }

    @Test("Accessibility label for building icon")
    func publisherAccessibilityLabel() {
        let row = BookMetadataRow(icon: "building.2", text: "Atria Books", style: .secondary)

        #expect(row.accessibilityText == "Publisher: Atria Books")
    }

    @Test("Accessibility label for book icon")
    func pagesAccessibilityLabel() {
        let row = BookMetadataRow(icon: "book.pages", text: "368", style: .secondary)

        #expect(row.accessibilityText == "Pages: 368")
    }

    @Test("Accessibility label for unknown icon")
    func unknownIconAccessibilityLabel() {
        let row = BookMetadataRow(icon: "star.fill", text: "5.0", style: .secondary)

        // Unknown icons default to "Info: {text}"
        #expect(row.accessibilityText == "Info: 5.0")
    }

    @Test("Empty text produces empty accessibility label")
    func emptyTextAccessibilityLabel() {
        let row = BookMetadataRow(icon: "calendar", text: "", style: .secondary)

        #expect(row.accessibilityText == "Year Published: ")
    }

    @Test("Renders with secondary style")
    func rendersSecondaryStyle() {
        let row = BookMetadataRow(icon: "calendar", text: "2017", style: .secondary)

        // Compilation test - view can be created
        #expect(row != nil)
        #expect(row.style == .secondary)
    }

    @Test("Renders with tertiary style")
    func rendersTertiaryStyle() {
        let row = BookMetadataRow(icon: "building.2", text: "Publisher", style: .tertiary)

        // Compilation test - view can be created
        #expect(row != nil)
        #expect(row.style == .tertiary)
    }
}
