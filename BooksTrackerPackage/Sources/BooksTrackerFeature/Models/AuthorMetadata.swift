import Foundation
import SwiftData

/// `AuthorMetadata` stores author-level information that can cascade to multiple works.
/// This model is designed to be `Sendable` for use in Swift's concurrency model.
@Model
final class AuthorMetadata: Sendable {
    /// A unique identifier for the author.
    @Attribute(.unique) var authorId: String

    /// A list of cultural backgrounds associated with the author.
    var culturalBackground: [String]

    /// The author's gender identity (optional).
    var genderIdentity: String?

    /// A list of nationalities associated with the author.
    var nationality: [String]

    /// A list of languages the author writes in or is associated with.
    var languages: [String]

    /// A list of marginalized identities the author may hold.
    var marginalizedIdentities: [String]

    /// A list of `workId`s to which this author's metadata has been cascaded.
    /// This helps track which works have received the default author data.
    var cascadedToWorkIds: [String]

    /// The date when this author's metadata was last updated.
    var lastUpdated: Date

    /// The ID of the user who contributed or last updated this metadata.
    var contributedBy: String

    /// One-to-many relationship with `WorkOverride`.
    /// If an `AuthorMetadata` instance is deleted, all associated `WorkOverride` instances will also be deleted.
    @Relationship(deleteRule: .cascade, inverse: \WorkOverride.authorMetadata)
    var workOverrides: [WorkOverride] = []

    /// Initializes a new `AuthorMetadata` instance.
    /// - Parameters:
    ///   - authorId: A unique identifier for the author.
    ///   - culturalBackground: Initial cultural backgrounds (defaults to empty array).
    ///   - genderIdentity: Initial gender identity (defaults to `nil`).
    ///   - nationality: Initial nationalities (defaults to empty array).
    ///   - languages: Initial languages (defaults to empty array).
    ///   - marginalizedIdentities: Initial marginalized identities (defaults to empty array).
    ///   - cascadedToWorkIds: Initial list of work IDs that have received cascaded data (defaults to empty array).
    ///   - lastUpdated: The date of the last update (defaults to the current date).
    ///   - contributedBy: The user ID who contributed this metadata.
    init(authorId: String,
         culturalBackground: [String] = [],
         genderIdentity: String? = nil,
         nationality: [String] = [],
         languages: [String] = [],
         marginalizedIdentities: [String] = [],
         cascadedToWorkIds: [String] = [],
         lastUpdated: Date = Date(),
         contributedBy: String) {
        self.authorId = authorId
        self.culturalBackground = culturalBackground
        self.genderIdentity = genderIdentity
        self.nationality = nationality
        self.languages = languages
        self.marginalizedIdentities = marginalizedIdentities
        self.cascadedToWorkIds = cascadedToWorkIds
        self.lastUpdated = lastUpdated
        self.contributedBy = contributedBy
    }
}
