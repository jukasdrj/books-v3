import Foundation

struct APIConfig {
    static let baseURL: URL = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: urlString) else {
            fatalError("API_BASE_URL not set in Info.plist")
        }
        return url
    }()
}

enum APIEndpoint {
    case weeklyRecommendations

    var path: String {
        switch self {
        case .weeklyRecommendations:
            return "/recommendations/weekly"
        }
    }

    var url: URL {
        return APIConfig.baseURL.appendingPathComponent(path)
    }
}
