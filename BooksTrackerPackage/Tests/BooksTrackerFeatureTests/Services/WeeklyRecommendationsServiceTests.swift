import XCTest
@testable import BooksTrackerFeature

final class WeeklyRecommendationsServiceTests: XCTestCase {

    var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    func testFetchWeeklyRecommendations_success() async throws {
        // Given
        let json = """
        {
          "week_of": "2025-11-25",
          "books": [],
          "generated_at": "2025-11-24T00:00:00Z",
          "next_refresh": "2025-12-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)
        let response = try await service.fetchWeeklyRecommendations()

        // Then
        XCTAssertEqual(response.weekOf, "2025-11-25")
    }

    func testFetchWeeklyRecommendations_noRecommendations() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)

        // Then
        do {
            _ = try await service.fetchWeeklyRecommendations()
            XCTFail("Expected to throw noRecommendations error")
        } catch let error as WeeklyRecommendationsService.APIError {
            XCTAssertEqual(error, .noRecommendations)
        } catch {
            XCTFail("Unexpected error thrown")
        }
    }

    func testFetchWeeklyRecommendations_serverError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)

        // Then
        do {
            _ = try await service.fetchWeeklyRecommendations()
            XCTFail("Expected to throw serverError")
        } catch let error as WeeklyRecommendationsService.APIError {
            if case .serverError(let statusCode) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Incorrect error type")
            }
        } catch {
            XCTFail("Unexpected error thrown")
        }
    }
}

extension WeeklyRecommendationsService.APIError: Equatable {
    public static func == (lhs: WeeklyRecommendationsService.APIError, rhs: WeeklyRecommendationsService.APIError) -> Bool {
        switch (lhs, rhs) {
        case (.noRecommendations, .noRecommendations):
            return true
        case (let .serverError(lhsCode), let .serverError(rhsCode)):
            return lhsCode == rhsCode
        default:
            return false
        }
    }
}
