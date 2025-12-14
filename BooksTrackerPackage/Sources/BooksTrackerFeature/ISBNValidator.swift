import Foundation

public struct ISBNValidator {

    public struct ISBN: Equatable, Hashable, Sendable {
        public let normalizedValue: String
        public let displayValue: String
        public let type: ISBNType

        public enum ISBNType: String, Sendable {
            case isbn10 = "ISBN-10"
            case isbn13 = "ISBN-13"
        }
    }

    public enum ValidationResult: Equatable {
        case valid(ISBN)
        case invalid(String)
    }

    /// Quick format check for ISBN (10 or 13 digits only, no checksum validation).
    /// Use this for filtering before API calls to avoid batch failures.
    /// Backend regex: /^\d{10}(\d{3})?$/
    /// - Note: ISBN-10 can end with 'X' (represents 10), which is handled by cleanForAPI()
    public static func isValidFormat(_ rawValue: String) -> Bool {
        let cleanValue = rawValue.uppercased().filter { $0.isNumber || $0 == "X" }
        // ISBN-10: 10 chars (last can be X), ISBN-13: 13 digits
        if cleanValue.count == 10 {
            // ISBN-10: first 9 must be digits, last can be digit or X
            let first9 = cleanValue.prefix(9)
            return first9.allSatisfy { $0.isNumber }
        } else if cleanValue.count == 13 {
            // ISBN-13: all 13 must be digits
            return cleanValue.allSatisfy { $0.isNumber }
        }
        return false
    }

    /// Cleans ISBN for API submission (removes hyphens/spaces, converts ISBN-10 with X to ISBN-13).
    /// Backend only accepts digits: /^\d{10}(\d{3})?$/
    /// - Returns: Cleaned ISBN string ready for API, or nil if invalid format
    public static func cleanForAPI(_ rawValue: String) -> String? {
        let cleanValue = rawValue.uppercased().filter { $0.isNumber || $0 == "X" }

        if cleanValue.count == 13 && cleanValue.allSatisfy({ $0.isNumber }) {
            // Valid ISBN-13: return as-is
            return cleanValue
        } else if cleanValue.count == 10 {
            let first9 = cleanValue.prefix(9)
            guard first9.allSatisfy({ $0.isNumber }) else { return nil }

            let lastChar = cleanValue.last!
            if lastChar == "X" {
                // ISBN-10 ending in X: convert to ISBN-13
                // Formula: prepend 978, recalculate check digit
                return convertISBN10ToISBN13(String(cleanValue))
            } else if lastChar.isNumber {
                // Valid ISBN-10 with digit ending: return as-is
                return cleanValue
            }
        }
        return nil
    }

    /// Converts ISBN-10 to ISBN-13 format.
    /// Prepends "978" and recalculates the check digit.
    private static func convertISBN10ToISBN13(_ isbn10: String) -> String? {
        guard isbn10.count == 10 else { return nil }

        // Take first 9 digits of ISBN-10, prepend 978
        let first9 = isbn10.prefix(9)
        guard first9.allSatisfy({ $0.isNumber }) else { return nil }

        let isbn13Base = "978" + first9

        // Calculate ISBN-13 check digit
        let digits = isbn13Base.compactMap { Int(String($0)) }
        guard digits.count == 12 else { return nil }

        var sum = 0
        for i in 0..<12 {
            sum += digits[i] * (i % 2 == 0 ? 1 : 3)
        }
        let checkDigit = (10 - (sum % 10)) % 10

        return isbn13Base + String(checkDigit)
    }

    /// Cleans and validates an ISBN-10 or ISBN-13 string.
    public static func validate(_ rawValue: String) -> ValidationResult {
        // 1. Clean the input and normalize X to uppercase
        let cleanValue = rawValue.filter { $0.isNumber || $0.uppercased() == "X" }.uppercased()

        switch cleanValue.count {
        case 10:
            return validateISBN10(cleanValue)
        case 13:
            return validateISBN13(cleanValue)
        default:
            return .invalid("Invalid length: \(cleanValue.count)")
        }
    }

    private static func validateISBN10(_ isbn: String) -> ValidationResult {
        guard isbn.count == 10 else { return .invalid("Length not 10") }

        let chars = Array(isbn.uppercased())
        var sum = 0

        for i in 0..<9 {
            guard let digit = Int(String(chars[i])) else { return .invalid("Invalid character in ISBN-10") }
            sum += (i + 1) * digit
        }

        let lastChar = chars[9]
        let lastDigit: Int
        if lastChar == "X" {
            lastDigit = 10
        } else if let digit = Int(String(lastChar)) {
            lastDigit = digit
        } else {
            return .invalid("Invalid check digit in ISBN-10")
        }

        sum += 10 * lastDigit

        if sum % 11 == 0 {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN10(isbn),
                type: .isbn10
            ))
        } else {
            return .invalid("Checksum failed for ISBN-10")
        }
    }

    private static func validateISBN13(_ isbn: String) -> ValidationResult {
        guard isbn.count == 13 else { return .invalid("Length not 13") }
        guard isbn.prefix(3) == "978" || isbn.prefix(3) == "979" else { return .invalid("Not a recognized prefix") }

        let digits = isbn.compactMap { Int(String($0)) }
        guard digits.count == 13 else { return .invalid("Invalid character in ISBN-13") }

        var sum = 0
        for i in 0..<12 {
            sum += digits[i] * (i % 2 == 0 ? 1 : 3)
        }

        let checksum = (10 - (sum % 10)) % 10

        if checksum == digits[12] {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN13(isbn),
                type: .isbn13
            ))
        } else {
            return .invalid("Checksum failed for ISBN-13")
        }
    }

    private static func formatISBN10(_ isbn: String) -> String {
        return "\(isbn.prefix(1))-\(isbn.prefix(5).suffix(4))-\(isbn.prefix(9).suffix(4))-\(isbn.suffix(1))"
    }

    private static func formatISBN13(_ isbn: String) -> String {
        return "\(isbn.prefix(3))-\(isbn.prefix(4).suffix(1))-\(isbn.prefix(9).suffix(5))-\(isbn.prefix(12).suffix(3))-\(isbn.suffix(1))"
    }
}