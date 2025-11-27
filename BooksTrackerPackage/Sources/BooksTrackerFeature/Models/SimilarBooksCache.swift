import Foundation
import SwiftData

@Model
final class SimilarBooksCache {
    /// Cache expiration duration (24 hours)
    static let cacheExpirationSeconds: TimeInterval = 24 * 60 * 60

    @Attribute(.unique)
    var sourceISBN: String
    var similarBookWorkIDs: [String]
    var timestamp: Date

    init(sourceISBN: String, similarBookWorkIDs: [String], timestamp: Date = Date()) {
        self.sourceISBN = sourceISBN
        self.similarBookWorkIDs = similarBookWorkIDs
        self.timestamp = timestamp
    }

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > Self.cacheExpirationSeconds
    }
}
