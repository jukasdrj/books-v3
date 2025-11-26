import Foundation

class WeeklyRecommendationsCache {
    private let cacheKey = "weeklyRecommendationsCache"
    private let userDefaults = UserDefaults.standard

    func save(_ response: WeeklyRecommendationsResponse) {
        do {
            let data = try JSONEncoder().encode(response)
            userDefaults.set(data, forKey: cacheKey)
        } catch {
            print("Error caching weekly recommendations: \(error)")
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
            print("Error loading cached weekly recommendations: \(error)")
            return nil
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: cacheKey)
    }
}
