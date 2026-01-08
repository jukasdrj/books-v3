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
        // #if DEBUG
        // print("📚 [LibraryFilter] Filtering \(works.count) total works")
        // #endif

        let filtered = works.filter { work in
            // CRITICAL: Check if work is still valid in context before accessing relationships
            // During library reset, @Query may not have updated yet and allWorks may contain deleted objects
            // Accessing userLibraryEntries on a deleted object triggers fault resolution and crashes
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                // #if DEBUG
                // print("📚 [LibraryFilter] Skipping deleted work: \(work.title)")
                // #endif
                return false
            }

            // Now safe to access relationship property
            guard let entries = work.userLibraryEntries else {
                // #if DEBUG
                // print("📚 [LibraryFilter] Work '\(work.title)' has nil userLibraryEntries - FILTERED OUT")
                // #endif
                return false
            }

            if entries.isEmpty {
                // #if DEBUG
                // print("📚 [LibraryFilter] Work '\(work.title)' has empty userLibraryEntries array - FILTERED OUT")
                // #endif
                return false
            }

            // #if DEBUG
            // print("📚 [LibraryFilter] ✅ Work '\(work.title)' has \(entries.count) library entries - INCLUDED")
            // #endif
            return true
        }

        // #if DEBUG
        // print("📚 [LibraryFilter] Result: \(filtered.count) works in library (filtered out \(works.count - filtered.count))")
        // #endif

        return filtered
    }

    // MARK: - Diversity Filtering

    /// Filter works by diversity criteria from Insights charts.
    /// - Parameters:
    ///   - works: Works to filter
    ///   - filter: Diversity filter to apply
    ///   - modelContext: SwiftData model context for validating object lifecycle
    /// - Returns: Filtered works matching the diversity criteria
    public func filterByDiversity(
        _ works: [Work],
        filter: DiversityFilter,
        modelContext: ModelContext
    ) -> [Work] {
        guard filter != .none else { return works }

        return works.filter { work in
            // CRITICAL: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return false
            }

            guard let authors = work.authors, !authors.isEmpty else {
                return false
            }

            switch filter {
            case .region(let targetRegion):
                // Check if any author is from the target region
                return authors.contains { author in
                    guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                        return false
                    }
                    return author.culturalRegion == targetRegion
                }

            case .gender(let targetGender):
                // Check if any author matches the target gender
                return authors.contains { author in
                    guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                        return false
                    }
                    return author.gender == targetGender
                }

            case .language(let targetLanguage):
                // Check if original language matches (case-insensitive)
                guard let originalLanguage = work.originalLanguage else {
                    return false
                }
                return originalLanguage.lowercased() == targetLanguage.lowercased()

            case .marginalizedVoices:
                // Check if any author represents marginalized voices
                return authors.contains { author in
                    guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                        return false
                    }
                    return author.representsMarginalizedVoices()
                }

            case .none:
                return true
            }
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

    /// Calculate diversity score asynchronously for a collection of works.
    /// Runs on background thread to avoid blocking main thread during UI updates.
    /// - Parameter works: Works to analyze
    /// - Returns: Diversity score (0-100)
    public func calculateDiversityScoreAsync(for works: [Work]) async -> Double {
        // Extract Sendable data from SwiftData models on main thread
        // Swift 6: SwiftData models are not Sendable, so we extract values first
        let authorData: [(gender: AuthorGender, region: CulturalRegion?)] = works.flatMap { work in
            (work.authors ?? []).map { author in
                (author.gender, author.culturalRegion)
            }
        }

        // Perform calculation on background thread with extracted data
        return await Task.detached(priority: .utility) {
            guard !authorData.isEmpty else { return 0.0 }

            var genderSet: Set<AuthorGender> = []
            var regionSet: Set<CulturalRegion> = []

            for (gender, region) in authorData {
                genderSet.insert(gender)
                if let region = region {
                    regionSet.insert(region)
                }
            }

            // Simple diversity metric: (unique genders + unique regions) / max possible * 100
            let maxGenders = 5.0 // female, male, nonBinary, other, unknown
            let maxRegions = 10.0 // Total cultural regions

            let genderDiversity = Double(genderSet.count) / maxGenders
            let regionDiversity = Double(regionSet.count) / maxRegions

            return ((genderDiversity + regionDiversity) / 2.0) * 100.0
        }.value
    }

    /// Calculate diversity score for a collection of works (synchronous version).
    /// - Parameters:
    ///   - works: Works to analyze
    ///   - modelContext: SwiftData model context for validating object lifecycle
    /// - Returns: Diversity score (0-100)
    /// - Note: Consider using `calculateDiversityScoreAsync` to avoid blocking the main thread
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
