import Foundation
import SwiftData

@Model
final class SimilarBooksCache {
    @Attribute(.unique)
    var sourceISBN: String
    var similarBookWorkIDs: [String]
    var timestamp: Date

    init(sourceISBN: String, similarBookWorkIDs: [String], timestamp: Date) {
        self.sourceISBN = sourceISBN
        self.similarBookWorkIDs = similarBookWorkIDs
        self.timestamp = timestamp
    }

    var isExpired: Bool {
        return Date().timeIntervalSince(timestamp) > 24 * 60 * 60 // 24 hours
    }
}
