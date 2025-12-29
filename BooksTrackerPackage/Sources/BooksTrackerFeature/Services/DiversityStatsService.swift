import SwiftData
import Foundation
import os.log

/// Service for calculating and managing enhanced diversity statistics
/// Aggregates diversity metrics from Work and Author models into EnhancedDiversityStats cache
@MainActor
public final class DiversityStatsService {

    private let modelContext: ModelContext
    private static let defaultUserId = "default-user"
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "DiversityStatsService")

    /// Initializes the service with the required ModelContext
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Supporting Types

    /// Intermediate container for aggregated diversity data during calculation
    private struct AggregatedDiversityData {
        var culturalOrigins: [String: Int] = [:]
        var genderDistribution: [String: Int] = [:]
        var translationStatus: [String: Int] = [:]
        var ownVoicesCount: Int = 0
        var accessibilityTags: [String: Int] = [:]
        var totalBooks: Int = 0
        var booksWithCulturalData: Int = 0
        var booksWithGenderData: Int = 0
        var booksWithTranslationData: Int = 0
        var booksWithOwnVoicesData: Int = 0
        var booksWithAccessibilityData: Int = 0
    }

    // MARK: - Private Helpers

    /// Fetch or create UserSettings for the default user
    private func fetchOrCreateUserSettings() async throws -> UserSettings {
        let settingsDescriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.userId == "default-user" }
        )
        if let existingSettings = try modelContext.fetch(settingsDescriptor).first {
            return existingSettings
        } else {
            let newSettings = UserSettings(
                userId: Self.defaultUserId,
                primaryReadingLanguage: UserSettings.defaultPrimaryReadingLanguage()
            )
            modelContext.insert(newSettings)
            try modelContext.save()
            return newSettings
        }
    }

    /// Aggregate diversity data from all library entries
    private func aggregateDiversityData(
        entries: [UserLibraryEntry],
        primaryReadingLanguage: String
    ) -> AggregatedDiversityData {
        var data = AggregatedDiversityData()

        for entry in entries {
            guard let work = entry.work else { continue }
            data.totalBooks += 1

            aggregateCulturalData(from: work, into: &data)
            aggregateGenderData(from: work, into: &data)
            aggregateTranslationData(from: entry, primaryReadingLanguage: primaryReadingLanguage, into: &data)
            aggregateOwnVoicesData(from: work, into: &data)
            aggregateAccessibilityData(from: work, into: &data)
        }

        return data
    }

    private func aggregateCulturalData(from work: Work, into data: inout AggregatedDiversityData) {
        if let primaryAuthor = work.primaryAuthor,
           let region = primaryAuthor.culturalRegion {
            let regionName = region.displayName
            data.culturalOrigins[regionName, default: 0] += 1
            data.booksWithCulturalData += 1
        }
    }

    private func aggregateGenderData(from work: Work, into data: inout AggregatedDiversityData) {
        if let primaryAuthor = work.primaryAuthor {
            let genderName = primaryAuthor.gender.displayName
            if primaryAuthor.gender != .unknown {
                data.genderDistribution[genderName, default: 0] += 1
                data.booksWithGenderData += 1
            }
        }
    }

    private func aggregateTranslationData(
        from entry: UserLibraryEntry,
        primaryReadingLanguage: String,
        into data: inout AggregatedDiversityData
    ) {
        if let edition = entry.edition, let language = edition.originalLanguage, !language.isEmpty {
            let isTranslated = language.lowercased() != primaryReadingLanguage
            let statusKey = isTranslated ? "Translated" : "Original Language"
            data.translationStatus[statusKey, default: 0] += 1
            data.booksWithTranslationData += 1
        }
    }

    private func aggregateOwnVoicesData(from work: Work, into data: inout AggregatedDiversityData) {
        if let isOwnVoices = work.isOwnVoices {
            if isOwnVoices {
                data.ownVoicesCount += 1
            }
            data.booksWithOwnVoicesData += 1
        }
    }

    private func aggregateAccessibilityData(from work: Work, into data: inout AggregatedDiversityData) {
        if !work.accessibilityTags.isEmpty {
            for tag in work.accessibilityTags {
                data.accessibilityTags[tag, default: 0] += 1
            }
            data.booksWithAccessibilityData += 1
        }
    }

    /// Apply aggregated data to an EnhancedDiversityStats instance
    private func applyAggregatedData(_ data: AggregatedDiversityData, to stats: EnhancedDiversityStats) {
        stats.culturalOrigins = data.culturalOrigins
        stats.genderDistribution = data.genderDistribution
        stats.translationStatus = data.translationStatus
        stats.ownVoicesCount = data.ownVoicesCount
        stats.accessibilityTags = data.accessibilityTags
        stats.totalBooks = data.totalBooks
        stats.booksWithCulturalData = data.booksWithCulturalData
        stats.booksWithGenderData = data.booksWithGenderData
        stats.booksWithTranslationData = data.booksWithTranslationData
        stats.booksWithOwnVoicesData = data.booksWithOwnVoicesData
        stats.booksWithAccessibilityData = data.booksWithAccessibilityData
        stats.lastCalculated = Date()
    }

    /// Fetch existing stats or create new instance for the given period
    private func fetchOrCreateStats(for period: StatsPeriod) throws -> (stats: EnhancedDiversityStats, isNew: Bool) {
        let defaultUserId = Self.defaultUserId
        let statsDescriptor = FetchDescriptor<EnhancedDiversityStats>(
            predicate: #Predicate { stats in
                stats.userId == defaultUserId && stats.period == period
            }
        )

        if let existingStats = try modelContext.fetch(statsDescriptor).first {
            return (existingStats, false)
        } else {
            let newStats = EnhancedDiversityStats(userId: Self.defaultUserId, period: period)
            return (newStats, true)
        }
    }

    // MARK: - Public API

    /// Calculate diversity statistics for a given period
    /// - Parameter period: Time period for stats aggregation (allTime, year, month)
    /// - Returns: EnhancedDiversityStats with aggregated metrics
    public func calculateStats(period: StatsPeriod = .allTime) async throws -> EnhancedDiversityStats {
        let userSettings = try await fetchOrCreateUserSettings()
        let primaryReadingLanguage = userSettings.primaryReadingLanguage.lowercased()

        let entryDescriptor = FetchDescriptor<UserLibraryEntry>()
        let entries = try modelContext.fetch(entryDescriptor)

        let aggregatedData = aggregateDiversityData(entries: entries, primaryReadingLanguage: primaryReadingLanguage)

        let (stats, isNew) = try fetchOrCreateStats(for: period)
        applyAggregatedData(aggregatedData, to: stats)

        if isNew {
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
        if work.accessibilityTags.isEmpty {
            missing.append("accessibilityTags")
        }

        return missing
    }

    /// Update diversity data for a work
    /// - Parameters:
    ///   - entryId: PersistentIdentifier of the UserLibraryEntry to update
    ///   - dimension: Dimension name ("culturalOrigins", "genderDistribution", "translationStatus", "ownVoicesCount", "accessibilityTags")
    ///   - value: The value to set for the dimension
    /// Finds a work in the library that is missing diversity metadata
    /// Used for Progressive Profiling flow
    /// - Returns: A Work object that needs profiling, or nil if all works are complete
    /// - Throws: DiversityStatsError.databaseFetchFailed if database access fails
    public func findNextWorkForProfiling() throws -> Work? {
        logger.debug("Finding next work for profiling")

        let descriptor = FetchDescriptor<UserLibraryEntry>()

        let entries: [UserLibraryEntry]
        do {
            entries = try modelContext.fetch(descriptor)
            logger.debug("Successfully fetched \(entries.count) library entries for profiling analysis")
        } catch {
            logger.error("Failed to fetch library entries for profiling: \(error.localizedDescription)")
            throw DiversityStatsError.databaseFetchFailed(error)
        }

        for entry in entries {
            guard let work = entry.work else { continue }

            // Check for missing data supported by ProgressiveProfilingSheet

            // 1. Cultural Region
            if work.primaryAuthor?.culturalRegion == nil {
                logger.debug("Found work needing cultural region data: \(work.title)")
                return work
            }

            // 2. Gender
            if work.primaryAuthor?.gender == nil || work.primaryAuthor?.gender == .unknown {
                logger.debug("Found work needing gender data: \(work.title)")
                return work
            }

            // 3. Original Language
            if work.originalLanguage == nil || work.originalLanguage?.isEmpty == true {
                logger.debug("Found work needing original language data: \(work.title)")
                return work
            }
        }

        logger.debug("No works found requiring profiling - all diversity data complete")
        return nil
    }

    public func updateDiversityData(entryId: PersistentIdentifier, dimension: String, value: Any) async throws {
        logger.debug("Updating diversity data - dimension: \(dimension), entryId: \(String(describing: entryId))")

        guard let entry = modelContext.model(for: entryId) as? UserLibraryEntry, let work = entry.work else {
            logger.error("Work not found for entry ID: \(String(describing: entryId))")
            throw DiversityStatsError.workNotFound
        }

        switch dimension {
        case "culturalOrigins":
            guard let stringValue = value as? String else {
                logger.error("Type validation failed for culturalOrigins - expected String, got \(type(of: value))")
                throw DiversityStatsError.typeValidationFailed(
                    dimension: dimension,
                    expectedType: "String",
                    receivedType: String(describing: type(of: value))
                )
            }

            guard let primaryAuthor = work.primaryAuthor else {
                logger.error("Primary author not found for work: \(work.title)")
                throw DiversityStatsError.primaryAuthorNotFound
            }

            guard let region = CulturalRegion.allCases.first(where: { $0.displayName == stringValue }) else {
                logger.error("Invalid cultural region: \(stringValue)")
                throw DiversityStatsError.invalidCulturalRegion(stringValue)
            }

            primaryAuthor.culturalRegion = region
            logger.debug("Updated cultural region to \(stringValue) for work: \(work.title)")

        case "genderDistribution":
            guard let stringValue = value as? String else {
                logger.error("Type validation failed for genderDistribution - expected String, got \(type(of: value))")
                throw DiversityStatsError.typeValidationFailed(
                    dimension: dimension,
                    expectedType: "String",
                    receivedType: String(describing: type(of: value))
                )
            }

            guard let primaryAuthor = work.primaryAuthor else {
                logger.error("Primary author not found for work: \(work.title)")
                throw DiversityStatsError.primaryAuthorNotFound
            }

            guard let gender = AuthorGender.allCases.first(where: { $0.displayName == stringValue }) else {
                logger.error("Invalid gender: \(stringValue)")
                throw DiversityStatsError.invalidGender(stringValue)
            }

            primaryAuthor.gender = gender
            logger.debug("Updated gender to \(stringValue) for work: \(work.title)")

        case "translationStatus":
            guard let stringValue = value as? String else {
                logger.error("Type validation failed for translationStatus - expected String, got \(type(of: value))")
                throw DiversityStatsError.typeValidationFailed(
                    dimension: dimension,
                    expectedType: "String",
                    receivedType: String(describing: type(of: value))
                )
            }

            guard let edition = entry.edition else {
                logger.error("Edition not found for entry: \(String(describing: entryId))")
                throw DiversityStatsError.editionNotFound
            }

            edition.originalLanguage = stringValue
            logger.debug("Updated original language to \(stringValue) for work: \(work.title)")

        case "ownVoicesCount":
            guard let boolValue = value as? Bool else {
                logger.error("Type validation failed for ownVoicesCount - expected Bool, got \(type(of: value))")
                throw DiversityStatsError.typeValidationFailed(
                    dimension: dimension,
                    expectedType: "Bool",
                    receivedType: String(describing: type(of: value))
                )
            }

            work.isOwnVoices = boolValue
            logger.debug("Updated own voices status to \(boolValue) for work: \(work.title)")

        case "accessibilityTags":
            guard let stringValue = value as? String else {
                logger.error("Type validation failed for accessibilityTags - expected String, got \(type(of: value))")
                throw DiversityStatsError.typeValidationFailed(
                    dimension: dimension,
                    expectedType: "String",
                    receivedType: String(describing: type(of: value))
                )
            }

            work.accessibilityTags.append(stringValue)
            logger.debug("Added accessibility tag \(stringValue) for work: \(work.title)")

        default:
            logger.error("Invalid diversity dimension: \(dimension)")
            throw DiversityStatsError.invalidDimension
        }

        do {
            try modelContext.save()
            logger.debug("Successfully saved diversity data update for work: \(work.title)")
        } catch {
            logger.error("Failed to save diversity data update: \(error.localizedDescription)")
            throw DiversityStatsError.databaseFetchFailed(error)
        }

        // Recalculate stats after update
        logger.debug("Recalculating stats after diversity data update")
        do {
            _ = try await calculateStats(period: .allTime)
            logger.debug("Successfully recalculated diversity stats")
        } catch {
            logger.error("Failed to recalculate stats after update: \(error.localizedDescription)")
            // Note: We don't re-throw this error as the primary update succeeded
        }
    }
}

/// Errors specific to diversity stats service
public enum DiversityStatsError: Error, LocalizedError {
    case workNotFound
    case invalidDimension
    case databaseFetchFailed(Error)
    case typeValidationFailed(dimension: String, expectedType: String, receivedType: String)
    case primaryAuthorNotFound
    case editionNotFound
    case invalidCulturalRegion(String)
    case invalidGender(String)

    public var errorDescription: String? {
        switch self {
        case .workNotFound:
            return "The requested book was not found in your library. Please try refreshing your library or contact support if the issue persists."
        case .invalidDimension:
            return "Invalid diversity category specified. Please use one of: cultural region, gender, translation status, own voices, or accessibility tags."
        case .databaseFetchFailed(let underlyingError):
            return "Failed to access your book library. Error: \(underlyingError.localizedDescription). Please try again or contact support."
        case .typeValidationFailed(let dimension, let expectedType, let receivedType):
            return "Invalid data type for \(dimension). Expected \(expectedType) but received \(receivedType). Please check your input and try again."
        case .primaryAuthorNotFound:
            return "Primary author information is missing for this book. Please add author details before updating diversity data."
        case .editionNotFound:
            return "Book edition information is missing. Please ensure the book has edition details before updating translation status."
        case .invalidCulturalRegion(let region):
            return "'\(region)' is not a recognized cultural region. Please select from the available options."
        case .invalidGender(let gender):
            return "'\(gender)' is not a recognized gender option. Please select from the available options."
        }
    }
}
