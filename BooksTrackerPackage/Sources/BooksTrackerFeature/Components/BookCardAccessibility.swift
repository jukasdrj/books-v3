import SwiftUI
import SwiftData

// MARK: - Accessibility Helpers

/// Shared accessibility description builder for book cards
/// Refactored from iOS26AdaptiveBookCard, iOS26LiquidListRow, and iOS26FloatingBookCard
public enum BookCardAccessibility {

    /// Builds a comprehensive accessibility description for a book
    public static func buildDescription(
        work: Work,
        userEntry: UserLibraryEntry?,
        includeYear: Bool = false
    ) -> String {
        var description = "Book: \(work.title) by \(work.authorNames)"

        if includeYear, let year = work.firstPublicationYear {
            description += ", Published \(year)"
        }

        if let userEntry = userEntry {
            description += ", Status: \(userEntry.readingStatus.displayName)"
            if userEntry.readingStatus == .reading && userEntry.readingProgress > 0 {
                description += ", Progress: \(Int(userEntry.readingProgress * 100))%"
            }
        }

        return description
    }
}
