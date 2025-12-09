import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("APIError Tests")
struct APIErrorTests {

    // MARK: - Enum Cases Tests

    @Test("APIError circuitOpen case")
    func testCircuitOpenCase() {
        // Given
        let error = APIError.circuitOpen(provider: "google", retryAfterMs: 5000)

        // Then
        #expect(error.isRetryable == true)
        #expect(error.retryDelay == 5.0)
        #expect(error.errorDescription?.contains("google") == true)
        #expect(error.errorDescription?.contains("5 seconds") == true)
    }

    @Test("APIError rateLimitExceeded case with retry")
    func testRateLimitExceededWithRetry() {
        // Given
        let error = APIError.rateLimitExceeded(retryAfter: 30.0)

        // Then
        #expect(error.isRetryable == true)
        #expect(error.retryDelay == 30.0)
        #expect(error.errorDescription?.contains("30 seconds") == true)
    }

    @Test("APIError rateLimitExceeded case without retry")
    func testRateLimitExceededWithoutRetry() {
        // Given
        let error = APIError.rateLimitExceeded(retryAfter: nil)

        // Then
        #expect(error.isRetryable == true)
        #expect(error.retryDelay == nil)
        #expect(error.errorDescription?.contains("try again later") == true)
    }

    @Test("APIError notFound case")
    func testNotFoundCase() {
        // Given
        let message = "Book not found"
        let error = APIError.notFound(message: message)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("APIError serverError case")
    func testServerErrorCase() {
        // Given
        let message = "Internal server error"
        let error = APIError.serverError(message: message)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("APIError decodingError case")
    func testDecodingErrorCase() {
        // Given
        let message = "Failed to decode response"
        let error = APIError.decodingError(message: message)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("APIError networkError case")
    func testNetworkErrorCase() {
        // Given
        struct TestError: Error {}
        let error = APIError.networkError(TestError())

        // Then
        #expect(error.isRetryable == true)
        #expect(error.retryDelay == 5.0)
        #expect(error.errorDescription?.contains("Network Error") == true)
    }

    @Test("APIError invalidURL case")
    func testInvalidURLCase() {
        // Given
        let error = APIError.invalidURL

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription == "Invalid URL")
    }

    @Test("APIError invalidResponse case")
    func testInvalidResponseCase() {
        // Given
        let error = APIError.invalidResponse

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription == "Invalid Response")
    }

    @Test("APIError httpError case with retryable status")
    func testHTTPErrorRetryable() {
        // Given
        let error = APIError.httpError(503)

        // Then
        #expect(error.isRetryable == true)
        #expect(error.errorDescription?.contains("503") == true)
    }

    @Test("APIError httpError case with non-retryable status")
    func testHTTPErrorNonRetryable() {
        // Given
        let error = APIError.httpError(404)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains("404") == true)
    }

    @Test("APIError corsBlocked case")
    func testCORSBlockedCase() {
        // Given
        let error = APIError.corsBlocked

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains("CORS") == true)
    }

    @Test("APIError unauthorized case")
    func testUnauthorizedCase() {
        // Given
        let message = "API key is invalid"
        let error = APIError.unauthorized(message: message)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("APIError unknownError case")
    func testUnknownErrorCase() {
        // Given
        let message = "Something went wrong"
        let error = APIError.unknownError(message: message)

        // Then
        #expect(error.isRetryable == false)
        #expect(error.errorDescription?.contains(message) == true)
    }

    // MARK: - Error Protocol Conformance Tests

    @Test("APIError conforms to Error protocol")
    func testErrorProtocolConformance() {
        // Given
        let error = APIError.invalidURL

        // When/Then
        let errorAsError: Error = error
        #expect(errorAsError is APIError)
    }

    @Test("APIError conforms to LocalizedError protocol")
    func testLocalizedErrorConformance() {
        // Given
        let error = APIError.notFound(message: "Resource not found")

        // When/Then
        let localizedError: LocalizedError = error
        #expect(localizedError.errorDescription != nil)
    }

    // MARK: - Decoding Tests

    @Test("Decode CIRCUIT_OPEN error")
    func testDecodeCircuitOpen() throws {
        // Given
        let json = """
        {
            "code": "CIRCUIT_OPEN",
            "provider": "google",
            "retryAfterMs": 5000
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .circuitOpen(let provider, let retryAfterMs) = error {
            #expect(provider == "google")
            #expect(retryAfterMs == 5000)
        } else {
            Issue.record("Expected circuitOpen case")
        }
    }

    @Test("Decode RATE_LIMIT_EXCEEDED error")
    func testDecodeRateLimitExceeded() throws {
        // Given
        let json = """
        {
            "code": "RATE_LIMIT_EXCEEDED",
            "retryAfterMs": 60000
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .rateLimitExceeded(let retryAfter) = error {
            #expect(retryAfter == 60.0)
        } else {
            Issue.record("Expected rateLimitExceeded case")
        }
    }

    @Test("Decode NOT_FOUND error")
    func testDecodeNotFound() throws {
        // Given
        let json = """
        {
            "code": "NOT_FOUND",
            "message": "Book with ISBN 1234567890 not found"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .notFound(let message) = error {
            #expect(message.contains("1234567890"))
        } else {
            Issue.record("Expected notFound case")
        }
    }

    @Test("Decode UNAUTHORIZED error")
    func testDecodeUnauthorized() throws {
        // Given
        let json = """
        {
            "code": "UNAUTHORIZED",
            "message": "Invalid API key"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .unauthorized(let message) = error {
            #expect(message == "Invalid API key")
        } else {
            Issue.record("Expected unauthorized case")
        }
    }

    @Test("Decode SERVER_ERROR error")
    func testDecodeServerError() throws {
        // Given
        let json = """
        {
            "code": "SERVER_ERROR",
            "message": "Database connection failed"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .serverError(let message) = error {
            #expect(message == "Database connection failed")
        } else {
            Issue.record("Expected serverError case")
        }
    }

    @Test("Decode unknown error code")
    func testDecodeUnknownErrorCode() throws {
        // Given
        let json = """
        {
            "code": "UNKNOWN_CODE",
            "message": "Something unexpected happened"
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let error = try JSONDecoder().decode(APIError.self, from: data)

        // Then
        if case .unknownError(let message) = error {
            #expect(message.contains("UNKNOWN_CODE"))
        } else {
            Issue.record("Expected unknownError case")
        }
    }

    // MARK: - Custom Initializer Tests

    @Test("Init with APIError wraps correctly")
    func testInitWithAPIError() {
        // Given
        let originalError = APIError.notFound(message: "Test")

        // When
        let wrappedError = APIError(originalError)

        // Then
        if case .notFound = wrappedError {
            // Success
        } else {
            Issue.record("Expected notFound case to be preserved")
        }
    }

    @Test("Init with other Error wraps as networkError")
    func testInitWithOtherError() {
        // Given
        struct CustomError: Error {}
        let customError = CustomError()

        // When
        let wrappedError = APIError(customError)

        // Then
        if case .networkError = wrappedError {
            // Success
        } else {
            Issue.record("Expected networkError case for custom error")
        }
    }

    // MARK: - Error Handling Integration Tests

    @Test("APIError can be thrown and caught")
    func testThrowAndCatch() throws {
        // Given
        let expectedError = APIError.notFound(message: "Test resource")

        // When/Then
        do {
            throw expectedError
        } catch let error as APIError {
            if case .notFound(let message) = error {
                #expect(message == "Test resource")
            } else {
                Issue.record("Expected notFound case")
            }
        } catch {
            Issue.record("Expected APIError but caught different error type")
        }
    }

    @Test("APIError in Result type")
    func testAPIErrorInResult() {
        // Given
        let error = APIError.invalidURL
        let failureResult: Result<String, APIError> = .failure(error)

        // When/Then
        switch failureResult {
        case .success:
            Issue.record("Expected failure but got success")
        case .failure(let apiError):
            if case .invalidURL = apiError {
                // Success
            } else {
                Issue.record("Expected invalidURL case")
            }
        }
    }

    // MARK: - Retry Logic Tests

    @Test("Retry delay for circuit open")
    func testRetryDelayCircuitOpen() {
        // Given
        let error = APIError.circuitOpen(provider: "google", retryAfterMs: 10000)

        // Then
        #expect(error.retryDelay == 10.0)
    }

    @Test("Retry delay for rate limit")
    func testRetryDelayRateLimit() {
        // Given
        let error = APIError.rateLimitExceeded(retryAfter: 15.5)

        // Then
        #expect(error.retryDelay == 15.5)
    }

    @Test("Retry delay for network error")
    func testRetryDelayNetworkError() {
        // Given
        struct TestError: Error {}
        let error = APIError.networkError(TestError())

        // Then
        #expect(error.retryDelay == 5.0)
    }

    @Test("No retry delay for non-retryable errors")
    func testNoRetryDelayForNonRetryable() {
        // Given
        let errors: [APIError] = [
            .invalidURL,
            .notFound(message: "Test"),
            .unauthorized(message: "Test"),
            .corsBlocked
        ]

        // Then
        for error in errors {
            #expect(error.retryDelay == nil)
        }
    }
}
