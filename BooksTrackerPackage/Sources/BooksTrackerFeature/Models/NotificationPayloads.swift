import Foundation

/// Type-safe payload for enrichment start notifications
public struct EnrichmentStartedPayload: Sendable {
    public let totalBooks: Int

    public init(totalBooks: Int) {
        self.totalBooks = totalBooks
    }
}

/// Type-safe payload for enrichment progress notifications
public struct EnrichmentProgressPayload: Sendable {
    public let completed: Int
    public let total: Int
    public let currentTitle: String

    public init(completed: Int, total: Int, currentTitle: String) {
        self.completed = completed
        self.total = total
        self.currentTitle = currentTitle
    }
}

/// Type-safe payload for enrichment failed notifications
public struct EnrichmentFailedPayload: Sendable {
    public let errorMessage: String

    public init(errorMessage: String) {
        self.errorMessage = errorMessage
    }
}

/// Type-safe payload for author search notifications
public struct SearchForAuthorPayload: Sendable {
    public let authorName: String

    public init(authorName: String) {
        self.authorName = authorName
    }
}
