import Foundation
import SwiftData

/// Service for filtering and searching library works.
/// Extracted from iOS26LiquidLibraryView to separate business logic from UI.
@MainActor
public final class LibraryFilterService {

    // MARK: - Initialization

    public init() {}

    // MARK: - Library Filtering

    /// Filter works to include only those in user's library.
    /// - Parameter works: All works from SwiftData
    /// - Returns: Works with non-empty userLibraryEntries
    public func filterLibraryWorks(from works: [Work]) -> [Work] {
        works.filter { work in
            guard let entries = work.userLibraryEntries else { return false }
            return !entries.isEmpty
        }
    }

    // MARK: - Search

    /// Search works by title or author name.
    /// - Parameters:
    ///   - works: Works to search through
    ///   - searchText: Search query
    /// - Returns: Filtered works matching search query
    public func searchWorks(_ works: [Work], searchText: String) -> [Work] {
        guard !searchText.isEmpty else { return works }

        let lowercased = searchText.lowercased()
        return works.filter { work in
            // Search in title
            if work.title.lowercased().contains(lowercased) {
                return true
            }

            // Search in author names
            if let authors = work.authors {
                for author in authors {
                    if author.name.lowercased().contains(lowercased) {
                        return true
                    }
                }
            }

            return false
        }
    }

    // MARK: - Diversity Metrics

    /// Calculate diversity score for a collection of works.
    /// - Parameter works: Works to analyze
    /// - Returns: Diversity score (0-100)
    public func calculateDiversityScore(for works: [Work]) -> Double {
        guard !works.isEmpty else { return 0.0 }

        var genderSet: Set<AuthorGender> = []
        var regionSet: Set<CulturalRegion> = []

        for work in works {
            guard let authors = work.authors else { continue }
            for author in authors {
                genderSet.insert(author.gender)
                if let region = author.culturalRegion {
                    regionSet.insert(region)
                }
            }
        }

        // Simple diversity metric: (unique genders + unique regions) / max possible * 100
        let maxGenders = 5.0 // female, male, nonBinary, other, unknown
        let maxRegions = 10.0 // Total cultural regions

        let genderDiversity = Double(genderSet.count) / maxGenders
        let regionDiversity = Double(regionSet.count) / maxRegions

        // Weighted average (60% region, 40% gender)
        return (regionDiversity * 60.0 + genderDiversity * 40.0)
    }
}
