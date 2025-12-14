import XCTest
@testable import BooksTrackerFeature

final class WeeklyRecommendationsServiceTests: XCTestCase {

    var urlSession: URLSession!
    private let cacheKey = "weeklyRecommendationsCache"

    override func setUp() {
        super.setUp()
        // Clear cache to ensure test isolation
        UserDefaults.standard.removeObject(forKey: cacheKey)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        // Clean up cache after each test
        UserDefaults.standard.removeObject(forKey: cacheKey)
        super.tearDown()
    }

    func testFetchWeeklyRecommendations_success() async throws {
        // Given - V3 API response format
        let json = """
        {
          "success": true,
          "data": {
            "weekOf": "2025-11-25",
            "recommendations": [
              {
                "isbn": "9780134685991",
                "title": "Effective Java",
                "author": "Joshua Bloch",
                "coverUrl": "https://example.com/cover.jpg",
                "reason": "A great read",
                "score": 0.8
              }
            ],
            "count": 1,
            "totalAvailable": 1
          }
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
        XCTAssertEqual(response.books.count, 1)
        XCTAssertEqual(response.books.first?.title, "Effective Java")
        XCTAssertEqual(response.books.first?.authors, ["Joshua Bloch"])
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
