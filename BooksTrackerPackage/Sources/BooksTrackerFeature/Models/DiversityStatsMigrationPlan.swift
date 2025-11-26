import SwiftData

enum DiversityStatsMigrationPlan: SchemaMigrationPlan {
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
                let statV2 = DiversityStatsSchemaV2.EnhancedDiversityStats(
                    userId: statV1.userId,
                    period: statV1.period,
                    culturalOrigins: statV1.culturalOrigins,
                    genderDistribution: statV1.genderDistribution,
                    translationStatus: statV1.translationStatus,
                    ownVoicesCount: statV1.ownVoicesTheme["Own Voices"] ?? 0,
                    accessibilityTags: statV1.nicheAccessibility,
                    totalBooks: statV1.totalBooks,
                    booksWithCulturalData: statV1.booksWithCulturalData,
                    booksWithGenderData: statV1.booksWithGenderData,
                    booksWithTranslationData: statV1.booksWithTranslationData,
                    booksWithOwnVoicesData: statV1.booksWithOwnVoicesData,
                    booksWithAccessibilityData: statV1.booksWithAccessibilityData,
                    lastCalculated: statV1.lastCalculated
                )
                context.insert(statV2)
                context.delete(statV1)
            }
        }
    )
}

enum DiversityStatsSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [EnhancedDiversityStats.self]
    }

    @Model
    final class EnhancedDiversityStats {
        var userId: String
        var period: StatsPeriod
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
    }
}

enum DiversityStatsSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [EnhancedDiversityStats.self]
    }

    @Model
    final class EnhancedDiversityStats {
        var userId: String
        var period: StatsPeriod
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
    }
}
