import Foundation
import SwiftData
import SwiftUI

/// Statistics about cultural diversity in the user's library
/// Calculated from Works, Authors, and UserLibraryEntries in SwiftData
@MainActor
public struct DiversityStats: Sendable {

    // MARK: - Cultural Regions

    public struct RegionStat: Identifiable, Sendable {
        public let id = UUID()
        public let region: CulturalRegion
        public let count: Int
        public let percentage: Double
        public let isMarginalized: Bool

        public init(region: CulturalRegion, count: Int, total: Int) {
            self.region = region
            self.count = count
            self.percentage = total > 0 ? (Double(count) / Double(total)) * 100.0 : 0.0
            // Marginalized regions per Author.swift:75
            let marginalizedRegions: [CulturalRegion] = [.africa, .indigenous, .middleEast, .southAmerica, .centralAsia]
            self.isMarginalized = marginalizedRegions.contains(region)
        }
    }

    public let culturalRegionStats: [RegionStat]
    public let totalRegionsRepresented: Int

    // MARK: - Gender

    public struct GenderStat: Identifiable, Sendable {
        public let id = UUID()
        public let gender: AuthorGender
        public let count: Int
        public let percentage: Double

        public init(gender: AuthorGender, count: Int, total: Int) {
            self.gender = gender
            self.count = count
            self.percentage = total > 0 ? (Double(count) / Double(total)) * 100.0 : 0.0
        }
    }

    public let genderStats: [GenderStat]
    public let totalAuthors: Int

    // MARK: - Marginalized Voices

    public let marginalizedVoicesCount: Int
    public let marginalizedVoicesPercentage: Double

    // MARK: - Languages

    public struct LanguageStat: Identifiable, Sendable {
        public let id = UUID()
        public let language: String
        public let count: Int
        public let emoji: String // Flag emoji for visual appeal

        public init(language: String, count: Int) {
            self.language = language
            self.count = count
            self.emoji = Self.languageToEmoji(language)
        }

        private static func languageToEmoji(_ language: String) -> String {
            // Common languages to flag emojis
            switch language.lowercased() {
            case "english": return "🇬🇧"
            case "spanish": return "🇪🇸"
            case "french": return "🇫🇷"
            case "german": return "🇩🇪"
            case "italian": return "🇮🇹"
            case "portuguese": return "🇵🇹"
            case "russian": return "🇷🇺"
            case "chinese", "mandarin": return "🇨🇳"
            case "japanese": return "🇯🇵"
            case "korean": return "🇰🇷"
            case "arabic": return "🇸🇦"
            case "hindi": return "🇮🇳"
            case "swahili": return "🇹🇿"
            case "yoruba": return "🇳🇬"
            default: return "🌐"
            }
        }
    }

    public let languageStats: [LanguageStat]
    public let totalLanguages: Int

    // MARK: - Hero Stats (Top-Level Metrics)

    public var heroStats: [HeroStat] {
        [
            HeroStat(
                title: "Cultural Regions",
                value: "\(totalRegionsRepresented) of 11",
                systemImage: "globe",
                color: .blue
            ),
            HeroStat(
                title: "Gender Representation",
                value: genderBreakdownString,
                systemImage: "person.2",
                color: .purple
            ),
            HeroStat(
                title: "Marginalized Voices",
                value: String(format: "%.0f%% of library", marginalizedVoicesPercentage),
                systemImage: "hands.sparkles",
                color: .orange
            ),
            HeroStat(
                title: "Languages Read",
                value: "\(totalLanguages) languages",
                systemImage: "text.bubble",
                color: .green
            )
        ]
    }

    private var genderBreakdownString: String {
        let topGenders = genderStats.filter { $0.gender != .unknown }
            .sorted { $0.percentage > $1.percentage }
            .prefix(3)

        return topGenders.map { String(format: "%.0f%% %@", $0.percentage, $0.gender.displayName) }
            .joined(separator: ", ")
    }

    public struct HeroStat: Identifiable {
        public let id = UUID()
        public let title: String
        public let value: String
        public let systemImage: String
        public let color: Color
    }

    // MARK: - Caching

    private static var cachedStats: DiversityStats?
    private static var cacheTimestamp: Date?
    private static let cacheValidityDuration: TimeInterval = 60 // 1 minute

    /// Calculate diversity statistics with caching
    /// Cache is valid for 1 minute to avoid redundant calculations
    public static func calculate(from context: ModelContext, ignoreCache: Bool = false) throws -> DiversityStats {
        // Check cache validity
        if !ignoreCache,
           let cached = cachedStats,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            return cached
        }

        // Calculate fresh stats
        let stats = try calculateFresh(from: context)

        // Update cache
        cachedStats = stats
        cacheTimestamp = Date()

        return stats
    }

    /// Invalidate cache when library changes
    public static func invalidateCache() {
        cachedStats = nil
        cacheTimestamp = nil
    }

    // MARK: - Calculation

    /// Calculate diversity statistics from SwiftData context
    private static func calculateFresh(from context: ModelContext) throws -> DiversityStats {
        // Fetch all authors
        let authorDescriptor = FetchDescriptor<Author>()
        let authors = try context.fetch(authorDescriptor)

        // Fetch all works in library (have UserLibraryEntry)
        let workDescriptor = FetchDescriptor<Work>()
        let works = try context.fetch(workDescriptor)
        let worksInLibrary = works.filter { work in
            (work.userLibraryEntries?.isEmpty == false)
        }

        // Calculate cultural region stats
        var regionCounts: [CulturalRegion: Int] = [:]
        for work in worksInLibrary {
            if let primaryAuthor = work.primaryAuthor,
               let region = primaryAuthor.culturalRegion {
                regionCounts[region, default: 0] += 1
            }
        }

        let totalWorksWithRegion = regionCounts.values.reduce(0, +)
        let regionStats = regionCounts.map { region, count in
            RegionStat(region: region, count: count, total: totalWorksWithRegion)
        }.sorted { $0.count > $1.count }

        // Calculate gender stats
        var genderCounts: [AuthorGender: Int] = [:]
        for author in authors where author.bookCount > 0 {
            genderCounts[author.gender, default: 0] += 1
        }

        let totalAuthorsWithGender = genderCounts.values.reduce(0, +)
        let genderStats = AuthorGender.allCases.map { gender in
            GenderStat(gender: gender, count: genderCounts[gender] ?? 0, total: totalAuthorsWithGender)
        }.filter { $0.count > 0 }

        // Calculate marginalized voices
        let authorsWithWorks = authors.filter { $0.bookCount > 0 }
        let marginalizedAuthors = authorsWithWorks.filter { $0.representsMarginalizedVoices() }
        let marginalizedPercentage = authorsWithWorks.isEmpty ? 0.0 :
            (Double(marginalizedAuthors.count) / Double(authorsWithWorks.count)) * 100.0

        // Calculate language stats
        var languageCounts: [String: Int] = [:]
        for work in worksInLibrary {
            if let language = work.originalLanguage, !language.isEmpty {
                languageCounts[language, default: 0] += 1
            }
        }

        let languageStats = languageCounts.map { language, count in
            LanguageStat(language: language, count: count)
        }.sorted { $0.count > $1.count }

        return DiversityStats(
            culturalRegionStats: regionStats,
            totalRegionsRepresented: regionCounts.keys.count,
            genderStats: genderStats,
            totalAuthors: totalAuthorsWithGender,
            marginalizedVoicesCount: marginalizedAuthors.count,
            marginalizedVoicesPercentage: marginalizedPercentage,
            languageStats: languageStats,
            totalLanguages: languageCounts.keys.count
        )
    }
}
