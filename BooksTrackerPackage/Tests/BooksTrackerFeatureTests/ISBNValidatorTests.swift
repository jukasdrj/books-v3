import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("ISBN Validator Tests")
struct ISBNValidatorTests {
    
    // MARK: - Valid ISBN-10 Tests
    
    @Test("Valid ISBN-10 with check digit X")
    func testValidISBN10WithCheckDigitX() {
        let result = ISBNValidator.validate("043942089X")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-10 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "043942089X")
        #expect(isbn.displayValue == "0-4394-2089-X")
        #expect(isbn.type == .isbn10)
    }
    
    @Test("Valid ISBN-10 with numeric check digit")
    func testValidISBN10WithNumericCheckDigit() {
        let result = ISBNValidator.validate("0486284735")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-10 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "0486284735")
        #expect(isbn.displayValue == "0-4862-8473-5")
        #expect(isbn.type == .isbn10)
    }
    
    @Test("Valid ISBN-10 with hyphens and spaces (should be cleaned)")
    func testValidISBN10WithFormatting() {
        let result = ISBNValidator.validate("0-439-42089-X")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-10 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "043942089X")
        #expect(isbn.displayValue == "0-4394-2089-X")
        #expect(isbn.type == .isbn10)
    }
    
    @Test("Valid ISBN-10 with mixed formatting")
    func testValidISBN10WithMixedFormatting() {
        let result = ISBNValidator.validate(" 0 486 28473 5 ")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-10 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "0486284735")
        #expect(isbn.displayValue == "0-4862-8473-5")
        #expect(isbn.type == .isbn10)
    }
    
    // MARK: - Valid ISBN-13 Tests
    
    @Test("Valid ISBN-13 with 978 prefix")
    func testValidISBN13With978Prefix() {
        let result = ISBNValidator.validate("9780439420891")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-13 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "9780439420891")
        #expect(isbn.displayValue == "978-0-43942-089-1")
        #expect(isbn.type == .isbn13)
    }
    
    @Test("Valid ISBN-13 with 979 prefix")
    func testValidISBN13With979Prefix() {
        let result = ISBNValidator.validate("9791234567896")

        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-13 but got invalid result")
            return
        }

        #expect(isbn.normalizedValue == "9791234567896")
        #expect(isbn.displayValue == "979-1-23456-789-6")
        #expect(isbn.type == .isbn13)
    }
    
    @Test("Valid ISBN-13 with formatting")
    func testValidISBN13WithFormatting() {
        let result = ISBNValidator.validate("978-0-439-42089-1")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-13 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "9780439420891")
        #expect(isbn.displayValue == "978-0-43942-089-1")
        #expect(isbn.type == .isbn13)
    }
    
    // MARK: - Invalid ISBN-10 Tests
    
    @Test("Invalid ISBN-10 with wrong checksum")
    func testInvalidISBN10WrongChecksum() {
        let result = ISBNValidator.validate("0439420890")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-10 but got valid result")
            return
        }
        
        #expect(message == "Checksum failed for ISBN-10")
    }
    
    @Test("Invalid ISBN-10 with invalid character")
    func testInvalidISBN10InvalidCharacter() {
        let result = ISBNValidator.validate("043942089Y")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-10 but got valid result")
            return
        }
        
        #expect(message == "Invalid check digit in ISBN-10")
    }
    
    @Test("Invalid ISBN-10 with non-numeric character in middle")
    func testInvalidISBN10NonNumericInMiddle() {
        let result = ISBNValidator.validate("043A42089X")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-10 but got valid result")
            return
        }
        
        #expect(message == "Invalid character in ISBN-10")
    }
    
    // MARK: - Invalid ISBN-13 Tests
    
    @Test("Invalid ISBN-13 with wrong checksum")
    func testInvalidISBN13WrongChecksum() {
        let result = ISBNValidator.validate("9780439420890")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-13 but got valid result")
            return
        }
        
        #expect(message == "Checksum failed for ISBN-13")
    }
    
    @Test("Invalid ISBN-13 with wrong prefix")
    func testInvalidISBN13WrongPrefix() {
        let result = ISBNValidator.validate("9770439420891")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-13 but got valid result")
            return
        }
        
        #expect(message == "Not a recognized prefix")
    }
    
    @Test("Invalid ISBN-13 with non-numeric character")
    func testInvalidISBN13NonNumericCharacter() {
        let result = ISBNValidator.validate("978043942089A")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN-13 but got valid result")
            return
        }
        
        #expect(message == "Invalid character in ISBN-13")
    }
    
    // MARK: - Invalid Length Tests
    
    @Test("Invalid ISBN with too short length")
    func testInvalidISBNTooShort() {
        let result = ISBNValidator.validate("123456789")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 9")
    }
    
    @Test("Invalid ISBN with too long length")
    func testInvalidISBNTooLong() {
        let result = ISBNValidator.validate("12345678901234")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 14")
    }
    
    @Test("Invalid ISBN with 11 digits")
    func testInvalidISBN11Digits() {
        let result = ISBNValidator.validate("12345678901")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 11")
    }
    
    @Test("Invalid ISBN with 12 digits")
    func testInvalidISBN12Digits() {
        let result = ISBNValidator.validate("123456789012")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 12")
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty string")
    func testEmptyString() {
        let result = ISBNValidator.validate("")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 0")
    }
    
    @Test("Only whitespace and hyphens")
    func testOnlyWhitespaceAndHyphens() {
        let result = ISBNValidator.validate("  - - -  ")
        
        guard case .invalid(let message) = result else {
            Issue.record("Expected invalid ISBN but got valid result")
            return
        }
        
        #expect(message == "Invalid length: 0")
    }
    
    @Test("ISBN-10 with lowercase x")
    func testISBN10WithLowercaseX() {
        let result = ISBNValidator.validate("043942089x")
        
        guard case .valid(let isbn) = result else {
            Issue.record("Expected valid ISBN-10 but got invalid result")
            return
        }
        
        #expect(isbn.normalizedValue == "043942089X")
        #expect(isbn.displayValue == "0-4394-2089-X")
        #expect(isbn.type == .isbn10)
    }
    
    // MARK: - ISBN Struct Tests
    
    @Test("ISBN struct equality")
    func testISBNEquality() {
        let isbn1 = ISBNValidator.ISBN(
            normalizedValue: "043942089X",
            displayValue: "0-4394-2089-X",
            type: .isbn10
        )
        
        let isbn2 = ISBNValidator.ISBN(
            normalizedValue: "043942089X",
            displayValue: "0-4394-2089-X",
            type: .isbn10
        )
        
        let isbn3 = ISBNValidator.ISBN(
            normalizedValue: "9780439420891",
            displayValue: "978-0-43942-089-1",
            type: .isbn13
        )
        
        #expect(isbn1 == isbn2)
        #expect(isbn1 != isbn3)
    }
    
    @Test("ISBN struct hashability")
    func testISBNHashability() {
        let isbn1 = ISBNValidator.ISBN(
            normalizedValue: "043942089X",
            displayValue: "0-4394-2089-X",
            type: .isbn10
        )
        
        let isbn2 = ISBNValidator.ISBN(
            normalizedValue: "043942089X",
            displayValue: "0-4394-2089-X",
            type: .isbn10
        )
        
        let set = Set([isbn1, isbn2])
        #expect(set.count == 1)
    }
    
    // MARK: - ValidationResult Tests
    
    @Test("ValidationResult equality")
    func testValidationResultEquality() {
        let isbn = ISBNValidator.ISBN(
            normalizedValue: "043942089X",
            displayValue: "0-4394-2089-X",
            type: .isbn10
        )
        
        let result1 = ISBNValidator.ValidationResult.valid(isbn)
        let result2 = ISBNValidator.ValidationResult.valid(isbn)
        let result3 = ISBNValidator.ValidationResult.invalid("Test error")
        let result4 = ISBNValidator.ValidationResult.invalid("Test error")
        let result5 = ISBNValidator.ValidationResult.invalid("Different error")
        
        #expect(result1 == result2)
        #expect(result3 == result4)
        #expect(result3 != result5)
        #expect(result1 != result3)
    }
    
    // MARK: - Real World ISBN Tests
    
    @Test(
        "Real world valid ISBNs",
        arguments: [
            // Famous books with their actual ISBNs
            ("0061120081", "0-0611-2008-1", ISBNValidator.ISBN.ISBNType.isbn10), // To Kill a Mockingbird
            ("9780061120084", "978-0-06112-008-4", ISBNValidator.ISBN.ISBNType.isbn13), // To Kill a Mockingbird
            ("0451524934", "0-4515-2493-4", ISBNValidator.ISBN.ISBNType.isbn10), // 1984
            ("9780451524935", "978-0-45152-493-5", ISBNValidator.ISBN.ISBNType.isbn13), // 1984
            ("0743273567", "0-7432-7356-7", ISBNValidator.ISBN.ISBNType.isbn10), // The Great Gatsby
            ("9780743273565", "978-0-74327-356-5", ISBNValidator.ISBN.ISBNType.isbn13) // The Great Gatsby
        ]
    )
    func testRealWorldValidISBNs(isbn: String, expectedDisplay: String, expectedType: ISBNValidator.ISBN.ISBNType) {
        let result = ISBNValidator.validate(isbn)
        
        guard case .valid(let validISBN) = result else {
            Issue.record("Expected valid ISBN but got invalid result for \(isbn)")
            return
        }
        
        #expect(validISBN.displayValue == expectedDisplay)
        #expect(validISBN.type == expectedType)
    }
}