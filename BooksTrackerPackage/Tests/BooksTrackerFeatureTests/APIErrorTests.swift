import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("APIError Tests")
struct APIErrorTests {
    
    // MARK: - Basic Functionality Tests
    
    @Test("APIError initializes with code and message")
    func testAPIErrorInitialization() {
        // Given
        let code = "AUTH_FAILED"
        let message = "Authentication failed"
        
        // When
        let error = APIError(code: code, message: message)
        
        // Then
        #expect(error.code == code)
        #expect(error.message == message)
    }
    
    @Test("APIError provides correct error description")
    func testErrorDescription() {
        // Given
        let code = "NETWORK_ERROR"
        let message = "Unable to connect to server"
        let error = APIError(code: code, message: message)
        
        // When
        let description = error.errorDescription
        
        // Then
        let expectedDescription = "\(message) (Code: \(code))"
        #expect(description == expectedDescription)
    }
    
    // MARK: - Error Protocol Conformance Tests
    
    @Test("APIError conforms to Error protocol")
    func testErrorProtocolConformance() {
        // Given
        let error = APIError(code: "TEST_ERROR", message: "Test message")
        
        // When/Then
        let errorAsError: Error = error
        #expect(errorAsError is APIError)
    }
    
    @Test("APIError conforms to LocalizedError protocol")
    func testLocalizedErrorConformance() {
        // Given
        let error = APIError(code: "LOCALIZED_ERROR", message: "Localized test message")
        
        // When/Then
        let localizedError: LocalizedError = error
        #expect(localizedError.errorDescription != nil)
    }
    
    // MARK: - Edge Cases and Special Characters
    
    @Test("APIError with empty code and message")
    func testEmptyCodeAndMessage() {
        // Given
        let error = APIError(code: "", message: "")
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == "")
        #expect(error.message == "")
        #expect(description == " (Code: )")
    }
    
    @Test("APIError with special characters in code")
    func testSpecialCharactersInCode() {
        // Given
        let code = "ERROR_CODE_WITH_SPECIAL!@#$%^&*()_+-=[]{}|;':\",./<>?"
        let message = "Error with special characters in code"
        let error = APIError(code: code, message: message)
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == code)
        #expect(description == "\(message) (Code: \(code))")
    }
    
    @Test("APIError with special characters in message")
    func testSpecialCharactersInMessage() {
        // Given
        let code = "SPECIAL_CHARS"
        let message = "Error message with special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?"
        let error = APIError(code: code, message: message)
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.message == message)
        #expect(description == "\(message) (Code: \(code))")
    }
    
    @Test("APIError with unicode characters")
    func testUnicodeCharacters() {
        // Given
        let code = "UNICODE_ERROR_🚨"
        let message = "Unicode error message: 测试错误 🔥💥⚠️"
        let error = APIError(code: code, message: message)
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == code)
        #expect(error.message == message)
        #expect(description == "\(message) (Code: \(code))")
    }
    
    @Test("APIError with newlines and tabs")
    func testNewlinesAndTabs() {
        // Given
        let code = "MULTILINE_ERROR"
        let message = "Error message\nwith newlines\tand tabs\r\nand carriage returns"
        let error = APIError(code: code, message: message)
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.message == message)
        #expect(description == "\(message) (Code: \(code))")
    }
    
    // MARK: - Real-world Error Scenarios
    
    @Test("Authentication error scenario")
    func testAuthenticationError() {
        // Given
        let error = APIError(
            code: "AUTH_TOKEN_EXPIRED",
            message: "Your authentication token has expired. Please log in again."
        )
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == "AUTH_TOKEN_EXPIRED")
        #expect(error.message == "Your authentication token has expired. Please log in again.")
        #expect(description == "Your authentication token has expired. Please log in again. (Code: AUTH_TOKEN_EXPIRED)")
    }
    
    @Test("Network error scenario")
    func testNetworkError() {
        // Given
        let error = APIError(
            code: "NETWORK_TIMEOUT",
            message: "The request timed out. Please check your internet connection and try again."
        )
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == "NETWORK_TIMEOUT")
        #expect(description?.contains("timed out") == true)
        #expect(description?.contains("NETWORK_TIMEOUT") == true)
    }
    
    @Test("Validation error scenario")
    func testValidationError() {
        // Given
        let error = APIError(
            code: "VALIDATION_FAILED",
            message: "The provided data is invalid. Please check the required fields."
        )
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == "VALIDATION_FAILED")
        #expect(description?.contains("invalid") == true)
        #expect(description?.contains("VALIDATION_FAILED") == true)
    }
    
    @Test("Server error scenario")
    func testServerError() {
        // Given
        let error = APIError(
            code: "INTERNAL_SERVER_ERROR",
            message: "An unexpected error occurred on the server. Please try again later."
        )
        
        // When
        let description = error.errorDescription
        
        // Then
        #expect(error.code == "INTERNAL_SERVER_ERROR")
        #expect(description?.contains("server") == true)
        #expect(description?.contains("INTERNAL_SERVER_ERROR") == true)
    }
    
    // MARK: - Equality and Comparison Tests
    
    @Test("APIError equality comparison")
    func testAPIErrorEquality() {
        // Given
        let error1 = APIError(code: "SAME_ERROR", message: "Same message")
        let error2 = APIError(code: "SAME_ERROR", message: "Same message")
        let error3 = APIError(code: "DIFFERENT_ERROR", message: "Same message")
        let error4 = APIError(code: "SAME_ERROR", message: "Different message")
        
        // When/Then
        // Note: APIError doesn't implement Equatable, so we test individual properties
        #expect(error1.code == error2.code)
        #expect(error1.message == error2.message)
        #expect(error1.code != error3.code)
        #expect(error1.message != error4.message)
    }
    
    // MARK: - Error Handling Integration Tests
    
    @Test("APIError can be thrown and caught")
    func testThrowAndCatch() throws {
        // Given
        let expectedError = APIError(code: "TEST_THROW", message: "Test throwing error")
        
        // When/Then
        do {
            throw expectedError
        } catch let caughtError as APIError {
            #expect(caughtError.code == expectedError.code)
            #expect(caughtError.message == expectedError.message)
        } catch {
            Issue.record("Expected APIError but caught different error type")
        }
    }
    
    @Test("APIError in Result type")
    func testAPIErrorInResult() {
        // Given
        let error = APIError(code: "RESULT_ERROR", message: "Error in Result type")
        let failureResult: Result<String, APIError> = .failure(error)
        
        // When/Then
        switch failureResult {
        case .success:
            Issue.record("Expected failure but got success")
        case .failure(let apiError):
            #expect(apiError.code == "RESULT_ERROR")
            #expect(apiError.message == "Error in Result type")
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("APIError creation performance")
    func testAPIErrorCreationPerformance() {
        // Given
        let code = "PERFORMANCE_TEST"
        let message = "Performance test message"
        
        // When - Create many APIError instances
        let errors = (0..<1000).map { index in
            APIError(code: "\(code)_\(index)", message: "\(message) \(index)")
        }
        
        // Then
        #expect(errors.count == 1000)
        #expect(errors.first?.code == "PERFORMANCE_TEST_0")
        #expect(errors.last?.code == "PERFORMANCE_TEST_999")
    }
    
    // MARK: - String Interpolation Tests
    
    @Test("APIError in string interpolation")
    func testStringInterpolation() {
        // Given
        let error = APIError(code: "INTERPOLATION_TEST", message: "Test message for interpolation")
        
        // When
        let interpolatedString = "An error occurred: \(error.errorDescription ?? "Unknown error")"
        
        // Then
        #expect(interpolatedString.contains("Test message for interpolation"))
        #expect(interpolatedString.contains("INTERPOLATION_TEST"))
    }
    
    // MARK: - Memory and Resource Tests
    
    @Test("APIError with very long strings")
    func testVeryLongStrings() {
        // Given
        let longCode = String(repeating: "A", count: 10000)
        let longMessage = String(repeating: "B", count: 10000)
        
        // When
        let error = APIError(code: longCode, message: longMessage)
        
        // Then
        #expect(error.code.count == 10000)
        #expect(error.message.count == 10000)
        #expect(error.errorDescription?.count == 20013) // message + " (Code: " + code + ")"
    }
}