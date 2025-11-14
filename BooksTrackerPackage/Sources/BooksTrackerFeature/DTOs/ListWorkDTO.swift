import Foundation
import SwiftData

/// Lightweight projection DTO for list views (fallback pattern for Phase 4.1).
///
/// **Purpose:** Memory-optimized representation of Work for scrolling lists.
/// Only contains data needed for book cards (title, cover, author preview).
///
/// **When to use:**
/// - LibraryView book cards
/// - Search results lists
/// - Review queue lists
///
/// **Memory savings:** 70-80% reduction vs. full Work objects with relationships.
///
/// **Pattern:** Projection DTO (alternative to SwiftData `propertiesToFetch`).
/// If Phase 4.1 validation fails, this pattern provides guaranteed CloudKit safety.
///
/// - SeeAlso: `docs/plans/2025-11-12-phase-3-4-implementation-plan.md` lines 402-405
public struct ListWorkDTO: Sendable, Identifiable, Hashable {
    public let id: String  // PersistentIdentifier string representation
    public let title: String
    public let authorPreview: String?  // First author name for display
    public let coverImageURL: String?  // Changed from URL? to match Work model
    public let reviewStatus: ReviewStatus

    public init(
        id: String,
        title: String,
        authorPreview: String?,
        coverImageURL: String?,
        reviewStatus: ReviewStatus
    ) {
        self.id = id
        self.title = title
        self.authorPreview = authorPreview
        self.coverImageURL = coverImageURL
        self.reviewStatus = reviewStatus
    }

    /// Creates projection from full Work model.
    /// Use in LibraryRepository methods if propertiesToFetch validation fails.
    public static func from(_ work: Work) -> ListWorkDTO {
        ListWorkDTO(
            id: "\(work.persistentModelID)",
            title: work.title,
            authorPreview: work.authors?.first?.name,
            coverImageURL: work.coverImageURL,
            reviewStatus: work.reviewStatus
        )
    }
}