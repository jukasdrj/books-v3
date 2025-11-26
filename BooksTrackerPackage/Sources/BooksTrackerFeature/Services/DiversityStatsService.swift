import SwiftData
import Foundation

/// Service for calculating and managing enhanced diversity statistics
/// Aggregates diversity metrics from Work and Author models into EnhancedDiversityStats cache
@MainActor
public final class DiversityStatsService {

    private let modelContext: ModelContext
    private static let defaultUserId = "default-user"

    /// Initializes the service with the required ModelContext
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Calculate diversity statistics for a given period
    /// - Parameter period: Time period for stats aggregation (allTime, year, month)
    /// - Returns: EnhancedDiversityStats with aggregated metrics
    public func calculateStats(period: StatsPeriod = .allTime) async throws -> EnhancedDiversityStats {
        // Fetch all library entries
        let entryDescriptor = FetchDescriptor<UserLibraryEntry>()
        let entries = try modelContext.fetch(entryDescriptor)

        // Initialize aggregation containers
        var culturalOrigins: [String: Int] = [:]
        var genderDistribution: [String: Int] = [:]
        var translationStatus: [String: Int] = [:]
        var ownVoicesTheme: [String: Int] = [:]
        var nicheAccessibility: [String: Int] = [:]

        // Completion tracking
        var totalBooks = 0
        var booksWithCulturalData = 0
        var booksWithGenderData = 0
        var booksWithTranslationData = 0
        var booksWithOwnVoicesData = 0
        var booksWithAccessibilityData = 0

        // Aggregate data from each entry's work
        for entry in entries {
            guard let work = entry.work else { continue }
            totalBooks += 1

            // Cultural origin (from primary author)
            if let primaryAuthor = work.primaryAuthor,
               let region = primaryAuthor.culturalRegion {
                let regionName = region.displayName
                culturalOrigins[regionName, default: 0] += 1
                booksWithCulturalData += 1
            }

            // Gender distribution (from primary author)
            if let primaryAuthor = work.primaryAuthor {
                let genderName = primaryAuthor.gender.displayName
                if primaryAuthor.gender != .unknown {
                    genderDistribution[genderName, default: 0] += 1
                    booksWithGenderData += 1
                }
            }

            // Translation status (from work)
            if let language = work.originalLanguage, !language.isEmpty {
                let isTranslated = language.lowercased() != "english" // TODO: Make this configurable
                let statusKey = isTranslated ? "Translated" : "Original Language"
                translationStatus[statusKey, default: 0] += 1
                booksWithTranslationData += 1
            }
            
            // Own Voices theme
            if let isOwnVoices = work.isOwnVoices {
                let themeKey = isOwnVoices ? "Own Voices" : "Not Own Voices"
                ownVoicesTheme[themeKey, default: 0] += 1
                booksWithOwnVoicesData += 1
            }
            
            // Accessibility features
            if !work.accessibilityTags.isEmpty {
                for tag in work.accessibilityTags {
                    nicheAccessibility[tag, default: 0] += 1
                }
                booksWithAccessibilityData += 1
            }
        }

        // Create or update stats model
        let defaultUserId = Self.defaultUserId
        let statsDescriptor = FetchDescriptor<EnhancedDiversityStats>(
            predicate: #Predicate { stats in
                stats.userId == defaultUserId && stats.period == period
            }
        )

        let existingStats = try modelContext.fetch(statsDescriptor).first

        let stats: EnhancedDiversityStats
        if let existing = existingStats {
            // Update existing
            stats = existing
            stats.culturalOrigins = culturalOrigins
            stats.genderDistribution = genderDistribution
            stats.translationStatus = translationStatus
            stats.ownVoicesTheme = ownVoicesTheme
            stats.nicheAccessibility = nicheAccessibility
            stats.totalBooks = totalBooks
            stats.booksWithCulturalData = booksWithCulturalData
            stats.booksWithGenderData = booksWithGenderData
            stats.booksWithTranslationData = booksWithTranslationData
            stats.booksWithOwnVoicesData = booksWithOwnVoicesData
            stats.booksWithAccessibilityData = booksWithAccessibilityData
            stats.lastCalculated = Date()
        } else {
            // Create new
            stats = EnhancedDiversityStats(userId: Self.defaultUserId, period: period)
            stats.culturalOrigins = culturalOrigins
            stats.genderDistribution = genderDistribution
            stats.translationStatus = translationStatus
            stats.ownVoicesTheme = ownVoicesTheme
            stats.nicheAccessibility = nicheAccessibility
            stats.totalBooks = totalBooks
            stats.booksWithCulturalData = booksWithCulturalData
            stats.booksWithGenderData = booksWithGenderData
            stats.booksWithTranslationData = booksWithTranslationData
            stats.booksWithOwnVoicesData = booksWithOwnVoicesData
            stats.booksWithAccessibilityData = booksWithAccessibilityData
            modelContext.insert(stats)
        }

        try modelContext.save()
        return stats
    }

    /// Fetch overall completion percentage for diversity data
    /// - Returns: Percentage from 0-100
    public func fetchCompletionPercentage() async throws -> Double {
        let defaultUserId = Self.defaultUserId
        let allTimePeriod = StatsPeriod.allTime
        let statsDescriptor = FetchDescriptor<EnhancedDiversityStats>(
            predicate: #Predicate { stats in
                stats.userId == defaultUserId && stats.period == allTimePeriod
            }
        )

        if let stats = try modelContext.fetch(statsDescriptor).first {
            return stats.overallCompletionPercentage
        }

        // If no stats exist, calculate them
        let stats = try await calculateStats(period: .allTime)
        return stats.overallCompletionPercentage
    }

    /// Get list of missing data dimensions for a specific work
    /// - Parameter workId: PersistentIdentifier of the work
    /// - Returns: Array of dimension names that are missing data
    public func getMissingDataDimensions(for workId: PersistentIdentifier) async throws -> [String] {
        guard let work = modelContext.model(for: workId) as? Work else {
            throw DiversityStatsError.workNotFound
        }

        var missing: [String] = []

        // Check cultural origin
        if work.primaryAuthor?.culturalRegion == nil {
            missing.append("culturalOrigins")
        }

        // Check gender
        if work.primaryAuthor == nil || work.primaryAuthor?.gender == .unknown {
            missing.append("genderDistribution")
        }

        // Check translation/language
        if work.originalLanguage == nil || work.originalLanguage?.isEmpty == true {
            missing.append("translationStatus")
        }
        
        // Check own voices
        if work.isOwnVoices == nil {
            missing.append("ownVoicesTheme")
        }
        
        // Check accessibility
        if work.accessibilityTags.isEmpty {
            missing.append("nicheAccessibility")
        }

        return missing
    }

    /// Update diversity data for a work
    /// - Parameters:
    ///   - workId: PersistentIdentifier of the work to update
    ///   - dimension: Dimension name:
    ///     - "culturalOrigins": Updates primary author's cultural region (value should be CulturalRegion.displayName, e.g., "Africa", "Asia")
    ///     - "genderDistribution": Updates primary author's gender (value should be AuthorGender.displayName, e.g., "Female", "Male", "Non-binary")
    ///     - "translationStatus": Updates work's original language (value is language name, e.g., "English", "Spanish")
    ///     - "ownVoicesTheme": Updates work's Own Voices status (value should be "true", "false", "Own Voices", or "Not Own Voices")
    ///     - "nicheAccessibility": Adds accessibility tag to work (value is tag name, e.g., "Large Print", "Audio Available")
    ///   - value: String value for the dimension (see dimension parameter for expected formats)
    public func updateDiversityData(workId: PersistentIdentifier, dimension: String, value: String) async throws {
        guard let work = modelContext.model(for: workId) as? Work else {
            throw DiversityStatsError.workNotFound
        }

        switch dimension {
        case "culturalOrigins":
            // Update primary author's cultural region
            if let primaryAuthor = work.primaryAuthor {
                // Parse CulturalRegion from string value
                if let region = CulturalRegion.allCases.first(where: { $0.displayName == value }) {
                    primaryAuthor.culturalRegion = region
                }
            }

        case "genderDistribution":
            // Update primary author's gender
            if let primaryAuthor = work.primaryAuthor {
                if let gender = AuthorGender.allCases.first(where: { $0.displayName == value }) {
                    primaryAuthor.gender = gender
                }
            }

        case "translationStatus":
            // Update work's original language
            work.originalLanguage = value
        
        case "ownVoicesTheme":
            // Update work's own voices status
            // Accept variations: "true", "false", "Own Voices", "Not Own Voices"
            let normalizedValue = value.lowercased()
            work.isOwnVoices = (normalizedValue == "true" || normalizedValue == "own voices")
        
        case "nicheAccessibility":
            // Add accessibility tag if not already present
            if !work.accessibilityTags.contains(value) {
                work.accessibilityTags.append(value)
            }

        default:
            throw DiversityStatsError.invalidDimension
        }

        try modelContext.save()

        // Recalculate stats after update
        _ = try await calculateStats(period: .allTime)
    }
}

/// Errors specific to diversity stats service
public enum DiversityStatsError: Error, LocalizedError {
    case workNotFound
    case invalidDimension

    public var errorDescription: String? {
        switch self {
        case .workNotFound:
            return "Work not found in database"
        case .invalidDimension:
            return "Invalid diversity dimension specified"
        }
    }
}
