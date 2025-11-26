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
        var ownVoicesCount = 0
        var accessibilityTags: [String: Int] = [:]

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

            // Translation status (from edition)
            if let edition = entry.edition, let language = edition.originalLanguage, !language.isEmpty {
                let isTranslated = language.lowercased() != "english" // TODO: Make this configurable
                let statusKey = isTranslated ? "Translated" : "Original Language"
                translationStatus[statusKey, default: 0] += 1
                booksWithTranslationData += 1
            }

            // Own Voices
            if let isOwnVoices = work.isOwnVoices {
                if isOwnVoices {
                    ownVoicesCount += 1
                }
                booksWithOwnVoicesData += 1
            }

            // Accessibility
            if let tags = work.accessibilityTags, !tags.isEmpty {
                for tag in tags {
                    accessibilityTags[tag, default: 0] += 1
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
            stats.ownVoicesCount = ownVoicesCount
            stats.accessibilityTags = accessibilityTags
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
            stats.ownVoicesCount = ownVoicesCount
            stats.accessibilityTags = accessibilityTags
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

    /// Get list of missing data dimensions for a specific entry
    /// - Parameter entryId: PersistentIdentifier of the UserLibraryEntry
    /// - Returns: Array of dimension names that are missing data
    public func getMissingDataDimensions(for entryId: PersistentIdentifier) async throws -> [String] {
        guard let entry = modelContext.model(for: entryId) as? UserLibraryEntry, let work = entry.work else {
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
        if entry.edition?.originalLanguage == nil || entry.edition?.originalLanguage?.isEmpty == true {
            missing.append("translationStatus")
        }

        // Check Own Voices
        if work.isOwnVoices == nil {
            missing.append("ownVoicesCount")
        }

        // Check Accessibility
        if work.accessibilityTags == nil || work.accessibilityTags?.isEmpty == true {
            missing.append("accessibilityTags")
        }

        return missing
    }

    /// Update diversity data for a work
    /// - Parameters:
    ///   - entryId: PersistentIdentifier of the UserLibraryEntry to update
    ///   - dimension: Dimension name ("culturalOrigins", "genderDistribution", "translationStatus", "ownVoicesCount", "accessibilityTags")
    ///   - value: The value to set for the dimension
    public func updateDiversityData(entryId: PersistentIdentifier, dimension: String, value: Any) async throws {
        guard let entry = modelContext.model(for: entryId) as? UserLibraryEntry, let work = entry.work else {
            throw DiversityStatsError.workNotFound
        }

        switch dimension {
        case "culturalOrigins":
            // Update primary author's cultural region
            if let primaryAuthor = work.primaryAuthor, let value = value as? String {
                // Parse CulturalRegion from string value
                if let region = CulturalRegion.allCases.first(where: { $0.displayName == value }) {
                    primaryAuthor.culturalRegion = region
                }
            }

        case "genderDistribution":
            // Update primary author's gender
            if let primaryAuthor = work.primaryAuthor, let value = value as? String {
                if let gender = AuthorGender.allCases.first(where: { $0.displayName == value }) {
                    primaryAuthor.gender = gender
                }
            }

        case "translationStatus":
            // Update edition's original language
            if let edition = entry.edition, let value = value as? String {
                edition.originalLanguage = value
            }

        case "ownVoicesCount":
            if let value = value as? Bool {
                work.isOwnVoices = value
            }

        case "accessibilityTags":
            if let value = value as? String {
                if work.accessibilityTags == nil {
                    work.accessibilityTags = []
                }
                work.accessibilityTags?.append(value)
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
