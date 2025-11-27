import Foundation
import SwiftData

enum DiversityStatsMigrationPlan: SchemaMigrationPlan {
    /// Time period for statistics aggregation (used in migration schemas)
    public enum MigrationStatsPeriod: String, Codable {
        case allTime
        case year
        case month
    }

    static var schemas: [any VersionedSchema.Type] {
        [DiversityStatsSchemaV1.self, DiversityStatsSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: DiversityStatsSchemaV1.self,
        toVersion: DiversityStatsSchemaV2.self,
        willMigrate: { context in
            // No action needed before migration
        },
        didMigrate: { context in
            let statsV1 = try context.fetch(FetchDescriptor<DiversityStatsSchemaV1.EnhancedDiversityStats>())
            for statV1 in statsV1 {
                let statV2 = DiversityStatsSchemaV2.EnhancedDiversityStats()
                statV2.userId = statV1.userId
                statV2.period = statV1.period
                statV2.culturalOrigins = statV1.culturalOrigins
                statV2.genderDistribution = statV1.genderDistribution
                statV2.translationStatus = statV1.translationStatus
                statV2.ownVoicesCount = statV1.ownVoicesTheme["Own Voices"] ?? 0
                statV2.accessibilityTags = statV1.nicheAccessibility
                statV2.totalBooks = statV1.totalBooks
                statV2.booksWithCulturalData = statV1.booksWithCulturalData
                statV2.booksWithGenderData = statV1.booksWithGenderData
                statV2.booksWithTranslationData = statV1.booksWithTranslationData
                statV2.booksWithOwnVoicesData = statV1.booksWithOwnVoicesData
                statV2.booksWithAccessibilityData = statV1.booksWithAccessibilityData
                statV2.lastCalculated = statV1.lastCalculated
                context.insert(statV2)
                context.delete(statV1)
            }
        }
    )
}

enum DiversityStatsSchemaV1: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [EnhancedDiversityStats.self]
    }

    @Model
    final class EnhancedDiversityStats {
        var userId: String
        var period: DiversityStatsMigrationPlan.MigrationStatsPeriod
        var culturalOrigins: [String: Int]
        var genderDistribution: [String: Int]
        var translationStatus: [String: Int]
        var ownVoicesTheme: [String: Int]
        var nicheAccessibility: [String: Int]
        var totalBooks: Int
        var booksWithCulturalData: Int
        var booksWithGenderData: Int
        var booksWithTranslationData: Int
        var booksWithOwnVoicesData: Int
        var booksWithAccessibilityData: Int
        var lastCalculated: Date

        init(
            userId: String = "",
            period: DiversityStatsMigrationPlan.MigrationStatsPeriod = .allTime,
            culturalOrigins: [String: Int] = [:],
            genderDistribution: [String: Int] = [:],
            translationStatus: [String: Int] = [:],
            ownVoicesTheme: [String: Int] = [:],
            nicheAccessibility: [String: Int] = [:],
            totalBooks: Int = 0,
            booksWithCulturalData: Int = 0,
            booksWithGenderData: Int = 0,
            booksWithTranslationData: Int = 0,
            booksWithOwnVoicesData: Int = 0,
            booksWithAccessibilityData: Int = 0,
            lastCalculated: Date = Date()
        ) {
            self.userId = userId
            self.period = period
            self.culturalOrigins = culturalOrigins
            self.genderDistribution = genderDistribution
            self.translationStatus = translationStatus
            self.ownVoicesTheme = ownVoicesTheme
            self.nicheAccessibility = nicheAccessibility
            self.totalBooks = totalBooks
            self.booksWithCulturalData = booksWithCulturalData
            self.booksWithGenderData = booksWithGenderData
            self.booksWithTranslationData = booksWithTranslationData
            self.booksWithOwnVoicesData = booksWithOwnVoicesData
            self.booksWithAccessibilityData = booksWithAccessibilityData
            self.lastCalculated = lastCalculated
        }
    }
}

enum DiversityStatsSchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [EnhancedDiversityStats.self]
    }

    @Model
    final class EnhancedDiversityStats {
        var userId: String
        var period: DiversityStatsMigrationPlan.MigrationStatsPeriod
        var culturalOrigins: [String: Int]
        var genderDistribution: [String: Int]
        var translationStatus: [String: Int]
        var ownVoicesCount: Int
        var accessibilityTags: [String: Int]
        var totalBooks: Int
        var booksWithCulturalData: Int
        var booksWithGenderData: Int
        var booksWithTranslationData: Int
        var booksWithOwnVoicesData: Int
        var booksWithAccessibilityData: Int
        var lastCalculated: Date

        init(
            userId: String = "",
            period: DiversityStatsMigrationPlan.MigrationStatsPeriod = .allTime,
            culturalOrigins: [String: Int] = [:],
            genderDistribution: [String: Int] = [:],
            translationStatus: [String: Int] = [:],
            ownVoicesCount: Int = 0,
            accessibilityTags: [String: Int] = [:],
            totalBooks: Int = 0,
            booksWithCulturalData: Int = 0,
            booksWithGenderData: Int = 0,
            booksWithTranslationData: Int = 0,
            booksWithOwnVoicesData: Int = 0,
            booksWithAccessibilityData: Int = 0,
            lastCalculated: Date = Date()
        ) {
            self.userId = userId
            self.period = period
            self.culturalOrigins = culturalOrigins
            self.genderDistribution = genderDistribution
            self.translationStatus = translationStatus
            self.ownVoicesCount = ownVoicesCount
            self.accessibilityTags = accessibilityTags
            self.totalBooks = totalBooks
            self.booksWithCulturalData = booksWithCulturalData
            self.booksWithGenderData = booksWithGenderData
            self.booksWithTranslationData = booksWithTranslationData
            self.booksWithOwnVoicesData = booksWithOwnVoicesData
            self.booksWithAccessibilityData = booksWithAccessibilityData
            self.lastCalculated = lastCalculated
        }
    }
}
