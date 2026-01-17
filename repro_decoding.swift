import Foundation

struct ScoredRecommendation: Codable {
    let coverUrl: String?
}

struct WeeklyRecommendationDTO: Codable {
    let coverUrl: String
}

let json = """
{
    "isbn": "123",
    "title": "Test",
    "author": "Test",
    "coverUrl": "https://example.com/image.jpg",
    "score": 10.0,
    "reason": "Test"
}
""".data(using: .utf8)!

print("--- Testing WeeklyRecommendationDTO (Default Strategy) ---")
let weeklyDecoder = JSONDecoder()
do {
    let result = try weeklyDecoder.decode(WeeklyRecommendationDTO.self, from: json)
    print("Success! coverUrl: \(result.coverUrl)")
} catch {
    print("Failed: \(error)")
}

print("\n--- Testing ScoredRecommendation (Snake Case Strategy) ---")
let recDecoder = JSONDecoder()
recDecoder.keyDecodingStrategy = .convertFromSnakeCase
do {
    let result = try recDecoder.decode(ScoredRecommendation.self, from: json)
    if let url = result.coverUrl {
        print("Success! coverUrl: \(url)")
    } else {
        print("Success, but coverUrl is NIL")
    }
} catch {
    print("Failed: \(error)")
}

