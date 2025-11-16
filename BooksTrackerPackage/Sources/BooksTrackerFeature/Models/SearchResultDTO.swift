import Foundation

// MARK: - Sendable SearchResult DTO

/// A Sendable representation of SearchResult for cross-actor communication
/// This structure extracts only the necessary data from SwiftData models
/// and provides Sendable conformance without using @unchecked Sendable.
public struct SearchResultDTO: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let workId: PersistentIdentifier
    public let title: String
    public let authors: [AuthorDTO]
    public let primaryEdition: EditionDTO?
    public let allEditions: [EditionDTO]
    public let relevanceScore: Double
    public let provider: String
    public let isInLibrary: Bool
    
    public init(
        from searchResult: SearchResult,
        isInLibrary: Bool = false
    ) {
        self.workId = searchResult.work.persistentModelID
        self.title = searchResult.work.title
        self.authors = searchResult.authors.map { AuthorDTO(from: $0) }
        self.primaryEdition = searchResult.primaryEdition.map { EditionDTO(from: $0) }
        self.allEditions = searchResult.editions.map { EditionDTO(from: $0) }
        self.relevanceScore = searchResult.relevanceScore
        self.provider = searchResult.provider
        self.isInLibrary = isInLibrary
    }
    
    // Computed properties for display
    public var displayTitle: String {
        title
    }
    
    public var displayAuthors: String {
        let names = authors.map { $0.name }
        switch names.count {
        case 0: return "Unknown Author"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }
}

// MARK: - Author DTO

public struct AuthorDTO: Sendable, Hashable {
    public let id: PersistentIdentifier
    public let name: String
    
    public init(from author: Author) {
        self.id = author.persistentModelID
        self.name = author.name
    }
}

// MARK: - Edition DTO

public struct EditionDTO: Sendable, Hashable {
    public let id: PersistentIdentifier
    public let isbn: String?
    public let format: String
    public let publisher: String?
    public let publicationDate: String?
    public let coverImageURL: String?
    
    public init(from edition: Edition) {
        self.id = edition.persistentModelID
        self.isbn = edition.primaryISBN
        self.format = edition.format.displayName
        self.publisher = edition.publisher
        self.publicationDate = edition.publicationDate
        self.coverImageURL = edition.coverImageURL
    }
}
