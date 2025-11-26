import Foundation
import SwiftData
import SwiftUI

/// Represents an author with cultural diversity analytics.
///
/// # SwiftUI Reactive Updates
///
/// Use `@Bindable` when observing author works relationship or statistics:
///
/// ```swift
/// struct AuthorDetailView: View {
///     @Bindable var author: Author
///
///     var body: some View {
///         Text("\(author.name) has written \(author.bookCount) books")  // ← Updates reactively
///         ForEach(author.works ?? []) { work in  // ← Observes works relationship
///             Text(work.title)
///         }
///     }
/// }
/// ```
///
/// **Why:** `@Bindable` enables reactive updates when author's works relationship
/// changes or statistics are recalculated via `updateStatistics()`.
@Model
public final class Author {
    var name: String = "" // CloudKit: default value required
    var nationality: String?
    var gender: Gender?
    var customGender: String?
    var culturalRegion: CulturalRegion?
    var birthYear: Int?
    var deathYear: Int?

    // External API identifiers for syncing and deduplication
    var openLibraryID: String?      // e.g., "OL23919A"
    var isbndbID: String?          // ISBNDB author identifier
    var googleBooksID: String?     // Google Books author identifier
    var goodreadsID: String?       // Goodreads author ID (future)

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Statistics
    var bookCount: Int = 0

    // Many-to-many relationship with Works
    // CloudKit: relationships must be optional
    @Relationship(deleteRule: .nullify)
    var works: [Work]?

    public init(
        name: String,
        nationality: String? = nil,
        gender: Gender? = nil,
        customGender: String? = nil,
        culturalRegion: CulturalRegion? = nil,
        birthYear: Int? = nil,
        deathYear: Int? = nil
    ) {
        self.name = name
        self.nationality = nationality
        self.gender = gender
        self.customGender = customGender
        self.culturalRegion = culturalRegion
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Display name with birth/death years if available
    var displayName: String {
        var components = [name]

        if let birth = birthYear {
            if let death = deathYear {
                components.append("(\(birth)–\(death))")
            } else {
                components.append("(b. \(birth))")
            }
        }

        return components.joined(separator: " ")
    }

    /// Check if author represents marginalized voices
    func representsMarginalizedVoices() -> Bool {
        // Non-male gender identities
        if let gender = gender, gender != .male && gender != .preferNotToSay {
            return true
        }

        // Underrepresented cultural regions
        let marginalizedRegions: [CulturalRegion] = [.africa, .indigenous, .middleEast, .southAmerica, .centralAsia]
        if let region = culturalRegion, marginalizedRegions.contains(region) {
            return true
        }

        return false
    }

    /// Check if author represents indigenous voices
    func representsIndigenousVoices() -> Bool {
        return culturalRegion == .indigenous
    }

    /// Update book count and last modified date
    func updateStatistics() {
        bookCount = works?.count ?? 0
        touch()
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }
}

// MARK: - Gender Enum
public enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case female = "Female"
    case male = "Male"
    case nonBinary = "Non-binary"
    case other = "Other"
    case preferNotToSay = "Prefer not to say"

    public var id: Self { self }

    var icon: String {
        switch self {
        case .female: return "person.crop.circle.fill"
        case .male: return "person.crop.circle"
        case .nonBinary: return "person.crop.circle.badge.questionmark"
        case .other: return "person.crop.circle.badge.plus"
        case .preferNotToSay: return "person.crop.circle.badge.xmark"
        }
    }

    var displayName: String {
        return rawValue
    }
}

// MARK: - Cultural Region Enum
public enum CulturalRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    case northAmerica = "North America"
    case southAmerica = "South America"
    case oceania = "Oceania"
    case middleEast = "Middle East"
    case caribbean = "Caribbean"
    case centralAsia = "Central Asia"
    case indigenous = "Indigenous"
    case international = "International"

    public var id: Self { self }

    var displayName: String {
        return rawValue
    }

    var shortName: String {
        switch self {
        case .africa: return "Africa"
        case .asia: return "Asia"
        case .europe: return "Europe"
        case .northAmerica: return "N. America"
        case .southAmerica: return "S. America"
        case .oceania: return "Oceania"
        case .middleEast: return "Middle East"
        case .caribbean: return "Caribbean"
        case .centralAsia: return "C. Asia"
        case .indigenous: return "Indigenous"
        case .international: return "Global"
        }
    }

    var emoji: String {
        switch self {
        case .africa: return "🌍"
        case .asia: return "🌏"
        case .europe: return "🌍"
        case .northAmerica: return "🌎"
        case .southAmerica: return "🌎"
        case .oceania: return "🏝️"
        case .middleEast: return "🕌"
        case .caribbean: return "🏖️"
        case .centralAsia: return "🏔️"
        case .indigenous: return "🪶"
        case .international: return "🌐"
        }
    }

    var icon: String {
        switch self {
        case .africa: return "globe.africa.fill"
        case .asia: return "globe.asia.australia.fill"
        case .europe: return "globe.europe.africa.fill"
        case .northAmerica, .southAmerica: return "globe.americas.fill"
        case .oceania: return "globe.asia.australia.fill"
        case .middleEast, .centralAsia: return "globe.europe.africa.fill"
        case .caribbean: return "globe.americas.fill"
        case .indigenous: return "leaf.fill"
        case .international: return "globe"
        }
    }
}
