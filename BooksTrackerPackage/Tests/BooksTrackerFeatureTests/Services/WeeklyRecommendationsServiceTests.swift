import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("Weekly Recommendations Service Tests")
struct WeeklyRecommendationsServiceTests {

    private let cacheKey = "weeklyRecommendationsCache"

    init() {
        // Clear cache to ensure test isolation
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // Note: Structs cannot have deinit - cache cleanup handled in init for next test run

    @Test("Fetch weekly recommendations success")
    func fetchWeeklyRecommendationsSuccess() async throws {
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

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)
        let response = try await service.fetchWeeklyRecommendations()

        // Then
        #expect(response.weekOf == "2025-11-25")
        #expect(response.books.count == 1)
        #expect(response.books.first?.title == "Effective Java")
        #expect(response.books.first?.authors == ["Joshua Bloch"])
    }

    @Test("Fetch weekly recommendations when no recommendations available")
    func fetchWeeklyRecommendationsNoRecommendations() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)

        // Then
        do {
            _ = try await service.fetchWeeklyRecommendations()
            Issue.record("Expected to throw noRecommendations error")
        } catch let error as WeeklyRecommendationsService.APIError {
            #expect(error == .noRecommendations)
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    @Test("Fetch weekly recommendations handles server error")
    func fetchWeeklyRecommendationsServerError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        // When
        let service = WeeklyRecommendationsService(urlSession: urlSession)

        // Then
        do {
            _ = try await service.fetchWeeklyRecommendations()
            Issue.record("Expected to throw serverError")
        } catch let error as WeeklyRecommendationsService.APIError {
            if case .serverError(let statusCode) = error {
                #expect(statusCode == 500)
            } else {
                Issue.record("Incorrect error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
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
