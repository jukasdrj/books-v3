import Foundation
import OSLog

class WeeklyRecommendationsCache {
    private let cacheKey = "weeklyRecommendationsCache"
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "WeeklyRecommendationsCache")

    func save(_ response: WeeklyRecommendationsResponse) {
        do {
            let data = try JSONEncoder().encode(response)
            userDefaults.set(data, forKey: cacheKey)
        } catch {
            logger.error("Error caching weekly recommendations: \(error.localizedDescription)")
        }
    }

    func load() -> WeeklyRecommendationsResponse? {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return nil
        }

        do {
            let response = try JSONDecoder().decode(WeeklyRecommendationsResponse.self, from: data)
            if response.nextRefresh > Date() {
                return response
            } else {
                // Cache is expired
                return nil
            }
        } catch {
            logger.error("Error loading cached weekly recommendations: \(error.localizedDescription)")
            return nil
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: cacheKey)
    }
}
