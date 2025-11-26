import Foundation

actor WeeklyRecommendationsService {

    private let cache = WeeklyRecommendationsCache()
    private let urlSession: URLSession

    enum APIError: Error {
        case networkError(Error)
        case decodingError(Error)
        case serverError(statusCode: Int)
        case noRecommendations
    }

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchWeeklyRecommendations() async throws -> WeeklyRecommendationsResponse {
        if let cachedResponse = cache.load() {
            return cachedResponse
        }

        let url = APIEndpoint.weeklyRecommendations.url
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError(statusCode: 0)
        }

        if httpResponse.statusCode == 404 {
            throw APIError.noRecommendations
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let recommendationsResponse = try decoder.decode(WeeklyRecommendationsResponse.self, from: data)
            cache.save(recommendationsResponse)
            return recommendationsResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
