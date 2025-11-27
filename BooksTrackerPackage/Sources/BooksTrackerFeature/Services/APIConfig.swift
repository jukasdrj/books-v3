import Foundation

struct APIConfig {
    static let baseURL: URL = {
        // Hardcoded since Swift compiler flags don't support string values
        // xcconfig API_BASE_URL is for documentation only
        let urlString = "https://api.oooefam.net/api/v2"

        guard let url = URL(string: urlString) else {
            fatalError("Invalid API_BASE_URL: \(urlString)")
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
