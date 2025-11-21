import Foundation
import SwiftData

/// `BookEnrichment` stores user-added metadata for specific books,
/// including ratings, notes, tags, and cascaded author information.
/// This model is designed to be `Sendable` for use in Swift's concurrency model.
@Model
final class BookEnrichment: Sendable {
    /// A unique identifier for the work (book) this enrichment applies to.
    @Attribute(.unique) var workId: String

    /// The user's rating for the book, from 1 to 5 stars (optional).
    var userRating: Int?

    /// A list of genres assigned to the book by the user.
    var genres: [String]

    /// A list of themes identified in the book by the user.
    var themes: [String]

    /// A list of content warnings for the book, added by the user.
    var contentWarnings: [String]

    /// Personal notes or reflections on the book.
    var personalNotes: String?

    /// The author's cultural background, potentially cascaded from `AuthorMetadata`.
    var authorCulturalBackground: String?

    /// The author's gender identity, potentially cascaded from `AuthorMetadata`.
    var authorGenderIdentity: String?

    /// A flag indicating if the author-related fields (`authorCulturalBackground`, `authorGenderIdentity`)
    /// were automatically filled from `AuthorMetadata`.
    var isCascaded: Bool

    /// The date when this book's enrichment data was last updated.
    var lastEnriched: Date

    /// A computed property representing the percentage of key enrichment fields that have been filled.
    /// This provides a quick overview of how complete the user's enrichment data is for a book.
    var completionPercentage: Double {
        var filledFieldsCount = 0
        // Define which fields contribute to the completion percentage
        let totalFieldsToConsider = 7 // userRating, genres, themes, contentWarnings, personalNotes, authorCulturalBackground, authorGenderIdentity

        if userRating != nil { filledFieldsCount += 1 }
        if !genres.isEmpty { filledFieldsCount += 1 }
        if !themes.isEmpty { filledFieldsCount += 1 }
        if !contentWarnings.isEmpty { filledFieldsCount += 1 }
        if let notes = personalNotes, !notes.isEmpty { filledFieldsCount += 1 }
        if let culturalBackground = authorCulturalBackground, !culturalBackground.isEmpty { filledFieldsCount += 1 }
        if let genderIdentity = authorGenderIdentity, !genderIdentity.isEmpty { filledFieldsCount += 1 }

        guard totalFieldsToConsider > 0 else { return 0.0 } // Avoid division by zero
        return Double(filledFieldsCount) / Double(totalFieldsToConsider)
    }

    /// Initializes a new `BookEnrichment` instance.
    /// - Parameters:
    ///   - workId: The unique ID of the work.
    ///   - userRating: The user's rating (defaults to `nil`).
    ///   - genres: Initial genres (defaults to empty array).
    ///   - themes: Initial themes (defaults to empty array).
    ///   - contentWarnings: Initial content warnings (defaults to empty array).
    ///   - personalNotes: Initial personal notes (defaults to `nil`).
    ///   - authorCulturalBackground: Initial author cultural background (defaults to `nil`).
    ///   - authorGenderIdentity: Initial author gender identity (defaults to `nil`).
    ///   - isCascaded: Flag indicating if author info was cascaded (defaults to `false`).
    ///   - lastEnriched: The date of last enrichment (defaults to the current date).
    init(workId: String,
         userRating: Int? = nil,
         genres: [String] = [],
         themes: [String] = [],
         contentWarnings: [String] = [],
         personalNotes: String? = nil,
         authorCulturalBackground: String? = nil,
         authorGenderIdentity: String? = nil,
         isCascaded: Bool = false,
         lastEnriched: Date = Date()) {
        self.workId = workId
        self.userRating = userRating
        self.genres = genres
        self.themes = themes
        self.contentWarnings = contentWarnings
        self.personalNotes = personalNotes
        self.authorCulturalBackground = authorCulturalBackground
        self.authorGenderIdentity = authorGenderIdentity
        self.isCascaded = isCascaded
        self.lastEnriched = lastEnriched
    }
}
