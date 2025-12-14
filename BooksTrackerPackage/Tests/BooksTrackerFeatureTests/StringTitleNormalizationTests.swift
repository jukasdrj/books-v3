import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("String Title Normalization Tests")
struct StringTitleNormalizationTests {

    @Test(
        "Normalize title for search",
        arguments: [
            (input: "The da Vinci Code: The Young Adult Adaptation", expected: "The da Vinci Code"),
            (input: "Devil's Knot: The True Story of the West Memphis Three (Justice Knot, #1)", expected: "Devil's Knot"),
            (input: "1984 [Special Edition]", expected: "1984"),
            (input: "Dept. of Speculation", expected: "Dept of Speculation"),
            (input: "It: A Novel", expected: "It"),  // Subtitles stripped for better search matching
            (input: "The Girl with the Dragon Tattoo - A Thriller", expected: "The Girl with the Dragon Tattoo"),
            (input: "The Hobbit (The Lord of the Rings #0) (Collector's Edition)", expected: "The Hobbit"),
            (input: "  The Great Gatsby  ", expected: "The Great Gatsby"),
            (input: "The    Great    Gatsby", expected: "The Great Gatsby"),
            (input: "", expected: ""),
            (input: "(Book One)", expected: ""),
            (input: "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)", expected: "Harry Potter and the Sorcerer's Stone"),
            (input: "The Fellowship of the Ring (The Lord of the Rings, #1)", expected: "The Fellowship of the Ring"),
            (input: "A Game of Thrones (A Song of Ice and Fire, #1)", expected: "A Game of Thrones"),
            (input: "The Handmaid's Tale: Special Illustrated Edition", expected: "The Handmaid's Tale"),
            (input: "Educated: A Memoir", expected: "Educated")
        ]
    )
    func testTitleNormalization(input: String, expected: String) {
        #expect(input.normalizedTitleForSearch == expected)
    }
}
