import Testing
@testable import BooksTrackerFeature

/// Unit tests for CSVValidator
///
/// **Test Coverage:**
/// - Valid CSV scenarios (basic, quoted fields, mixed)
/// - Invalid CSV scenarios (malformed, inconsistent columns)
/// - Edge cases (empty files, single column, escaped quotes)
/// - Real-world examples (Goodreads, LibraryThing exports)
@Suite("CSV Validator Tests")
struct CSVValidatorTests {

    // MARK: - Valid CSV Tests

    @Test("Valid basic CSV with header and data")
    func testValidBasicCSV() throws {
        let csv = """
        Title,Author,ISBN
        1984,George Orwell,9780451524935
        The Great Gatsby,F. Scott Fitzgerald,9780743273565
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with quoted fields containing commas")
    func testValidCSVWithQuotedFields() throws {
        let csv = """
        Title,Author,Publisher
        "1984: A Novel",George Orwell,"Penguin Books, LLC"
        The Great Gatsby,F. Scott Fitzgerald,Scribner
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with escaped quotes inside quoted fields")
    func testValidCSVWithEscapedQuotes() throws {
        let csv = """
        Title,Quote
        Hamlet,"To be, or not to be, that is the question"
        Macbeth,"Out, out, brief candle! Life's but a walking shadow"
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with mixed quoted and unquoted fields")
    func testValidCSVWithMixedFields() throws {
        let csv = """
        Title,Author,Year
        "The Catcher in the Rye",J.D. Salinger,1951
        1984,George Orwell,1949
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with trailing newline")
    func testValidCSVWithTrailingNewline() throws {
        let csv = """
        Title,Author
        1984,George Orwell

        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with empty fields")
    func testValidCSVWithEmptyFields() throws {
        let csv = """
        Title,Author,ISBN
        1984,George Orwell,
        The Great Gatsby,,9780743273565
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    // MARK: - Invalid CSV Tests

    @Test("Invalid CSV with empty content")
    func testInvalidEmptyCSV() {
        let csv = ""

        #expect(throws: CSVValidationError.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with only header row")
    func testInvalidCSVOnlyHeader() {
        let csv = "Title,Author,ISBN"

        #expect(throws: CSVValidationError.insufficientRows(count: 1)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with empty header")
    func testInvalidCSVEmptyHeader() {
        let csv = """
        ,,
        1984,George Orwell,9780451524935
        """

        #expect(throws: CSVValidationError.emptyHeader) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with inconsistent column count")
    func testInvalidCSVInconsistentColumns() {
        let csv = """
        Title,Author,ISBN
        1984,George Orwell,9780451524935
        The Great Gatsby,F. Scott Fitzgerald
        """

        #expect(throws: CSVValidationError.mismatchedColumnCount(expected: 3, actual: 2, lineNumber: 3)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with unclosed quote")
    func testInvalidCSVUnclosedQuote() {
        let csv = """
        Title,Author
        "1984,George Orwell
        """

        #expect(throws: CSVValidationError.unclosedQuote(lineNumber: 2)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with stray quote in unquoted field")
    func testInvalidCSVStrayQuote() {
        let csv = """
        Title,Author
        198"4,George Orwell
        """

        #expect(throws: CSVValidationError.strayQuote(lineNumber: 2)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with too many columns in data row")
    func testInvalidCSVTooManyColumns() {
        let csv = """
        Title,Author
        1984,George Orwell,9780451524935,Extra
        """

        #expect(throws: CSVValidationError.mismatchedColumnCount(expected: 2, actual: 4, lineNumber: 2)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    // MARK: - Real-World Export Tests

    @Test("Valid Goodreads export format")
    func testValidGoodreadsExport() throws {
        let csv = """
        Title,Author,ISBN,My Rating,Average Rating,Publisher,Year Published
        "The Hobbit, or There and Back Again",J.R.R. Tolkien,9780547928227,5,4.28,Mariner Books,2012
        1984,George Orwell,9780451524935,4,4.19,Signet Classic,1950
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid LibraryThing export format")
    func testValidLibraryThingExport() throws {
        let csv = """
        TITLE,AUTHOR (LAST FIRST),ISBN,PUBLICATION,RATING
        "Dune",Herbert Frank,9780441172719,"Ace, 1990",5
        "Foundation",Asimov Isaac,9780553293357,"Spectra, 1991",4
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    // MARK: - Edge Cases

    @Test("Valid CSV with single column")
    func testValidCSVSingleColumn() throws {
        let csv = """
        Title
        1984
        The Great Gatsby
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with many columns")
    func testValidCSVManyColumns() throws {
        let csv = """
        A,B,C,D,E,F,G,H,I,J
        1,2,3,4,5,6,7,8,9,10
        11,12,13,14,15,16,17,18,19,20
        """

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Valid CSV with double-escaped quotes")
    func testValidCSVDoubleEscapedQuotes() throws {
        let csv = """
Title,Quote
Book One,"She said ""Hello"" to me"
Book Two,"He replied ""Goodbye""
"""

        #expect(throws: Never.self) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    @Test("Invalid CSV with mismatched quotes")
    func testInvalidCSVMismatchedQuotes() {
        let csv = """
Title,Author
"1984",George Orwell
The Great Gatsby,"F. Scott Fitzgerald
"""

        #expect(throws: CSVValidationError.unclosedQuote(lineNumber: 3)) {
            try CSVValidator.validate(csvText: csv)
        }
    }

    // MARK: - Error Message Tests

    @Test("Error message for insufficient rows is descriptive")
    func testErrorMessageInsufficientRows() {
        let error = CSVValidationError.insufficientRows(count: 1)
        let message = error.errorDescription

        #expect(message?.contains("header and at least one data row") == true)
        #expect(message?.contains("1 line") == true)
    }

    @Test("Error message for mismatched columns includes line number")
    func testErrorMessageMismatchedColumns() {
        let error = CSVValidationError.mismatchedColumnCount(expected: 3, actual: 2, lineNumber: 5)
        let message = error.errorDescription

        #expect(message?.contains("line 5") == true)
        #expect(message?.contains("3 columns") == true)
        #expect(message?.contains("found 2") == true)
    }

    @Test("Error message for unclosed quote includes line number")
    func testErrorMessageUnclosedQuote() {
        let error = CSVValidationError.unclosedQuote(lineNumber: 10)
        let message = error.errorDescription

        #expect(message?.contains("line 10") == true)
        #expect(message?.contains("not properly closed") == true)
    }
}