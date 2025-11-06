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
    /// - Parameters:
    ///   - works: All works from SwiftData
    ///   - modelContext: SwiftData model context for validating object lifecycle
    /// - Returns: Works with non-empty userLibraryEntries, excluding deleted objects
    public func filterLibraryWorks(from works: [Work], modelContext: ModelContext) -> [Work] {
        works.filter { work in
            // CRITICAL: Check if work is still valid in context before accessing relationships
            // During library reset, @Query may not have updated yet and allWorks may contain deleted objects
            // Accessing userLibraryEntries on a deleted object triggers fault resolution and crashes
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return false
            }
            
            // Now safe to access relationship property
            guard let entries = work.userLibraryEntries else { return false }
            return !entries.isEmpty
        }
    }

    // MARK: - Search

    /// Search works by title or author name.
    /// - Parameters:
    ///   - works: Works to search through
    ///   - searchText: Search query
    ///   - modelContext: SwiftData model context for validating object lifecycle
    /// - Returns: Filtered works matching search query
    public func searchWorks(_ works: [Work], searchText: String, modelContext: ModelContext) -> [Work] {
        guard !searchText.isEmpty else { return works }

        let lowercased = searchText.lowercased()
        return works.filter { work in
            // CRITICAL: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return false
            }
            
            // Search in title
            if work.title.lowercased().contains(lowercased) {
                return true
            }

            // Search in author names
            if let authors = work.authors {
                for author in authors {
                    // DEFENSIVE: Validate author is still in context before accessing properties
                    // During library reset, authors may be deleted while search is running
                    guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                        continue
                    }
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
    /// - Parameters:
    ///   - works: Works to analyze
    ///   - modelContext: SwiftData model context for validating object lifecycle
    /// - Returns: Diversity score (0-100)
    public func calculateDiversityScore(for works: [Work], modelContext: ModelContext) -> Double {
        guard !works.isEmpty else { return 0.0 }

        var genderSet: Set<AuthorGender> = []
        var regionSet: Set<CulturalRegion> = []

        for work in works {
            // CRITICAL: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                continue
            }
            
            guard let authors = work.authors else { continue }
            for author in authors {
                // DEFENSIVE: Validate author is still in context before accessing properties
                // During library reset, authors may be deleted while calculations are running
                guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                    continue
                }
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
