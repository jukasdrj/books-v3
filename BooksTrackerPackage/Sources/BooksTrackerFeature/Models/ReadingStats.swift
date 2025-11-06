import Foundation
import SwiftData
import SwiftUI

/// Time period for filtering reading statistics
public enum TimePeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTime = "All Time"
    case thisYear = "This Year"
    case last30Days = "Last 30 Days"
    case custom = "Custom Range"

    public var id: String { rawValue }

    /// Calculate date range for this period
    public func dateRange(customStart: Date? = nil, customEnd: Date? = nil) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .allTime:
            return (Date.distantPast, now)
        case .thisYear:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return (startOfYear, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (start, now)
        case .custom:
            return (customStart ?? Date.distantPast, customEnd ?? now)
        }
    }
}

/// Statistics about user's reading habits and progress
@MainActor
public struct ReadingStats: Sendable {

    // MARK: - Basic Stats

    public let pagesRead: Int
    public let booksCompleted: Int
    public let booksInProgress: Int
    public let averageReadingPace: Double // pages per day
    public let fastestReadingPace: Double // pages per day

    // MARK: - Diversity Metrics

    public let diversityScore: Double // 0-10 scale
    public let regionsRepresented: Int
    public let marginalizedVoicesPercentage: Double

    // MARK: - Time-Based Trends

    public let period: TimePeriod
    public let comparisonToPreviousPeriod: Double? // percentage change

    // MARK: - Stat Cards

    public var statCards: [StatCard] {
        [
            StatCard(
                title: "Pages Read",
                value: "\(pagesRead.formatted()) pages",
                subtitle: comparisonString(comparisonToPreviousPeriod),
                detail: "Avg: \(Int(averageReadingPace)) pages/day",
                systemImage: "book.pages",
                color: .blue
            ),
            StatCard(
                title: "Books Finished",
                value: "\(booksCompleted) books",
                subtitle: goalProgressString(),
                detail: "Avg: \(String(format: "%.1f", Double(booksCompleted) / monthsInPeriod())) books/month",
                systemImage: "checkmark.circle.fill",
                color: .green
            ),
            StatCard(
                title: "Reading Speed",
                value: "\(Int(averageReadingPace)) pages/day",
                subtitle: trendString(averageReadingPace),
                detail: "Fastest: \(Int(fastestReadingPace)) pg/day",
                systemImage: "bolt.fill",
                color: .orange
            ),
            StatCard(
                title: "Diversity Index",
                value: String(format: "%.1f / 10", diversityScore),
                subtitle: "\(regionsRepresented) regions",
                detail: "\(Int(marginalizedVoicesPercentage))% marginalized voices",
                systemImage: "globe",
                color: .purple
            )
        ]
    }

    public struct StatCard: Identifiable {
        public let id = UUID()
        public let title: String
        public let value: String
        public let subtitle: String
        public let detail: String
        public let systemImage: String
        public let color: Color
    }

    // MARK: - Helper Methods

    private func comparisonString(_ change: Double?) -> String {
        guard let change = change else { return "" }
        let arrow = change > 0 ? "↑" : "↓"
        return "\(arrow) \(abs(Int(change)))% vs last period"
    }

    private func goalProgressString() -> String {
        guard period == .thisYear else { return "" }
        let goalFor52Books = 52
        let progress = (Double(booksCompleted) / Double(goalFor52Books)) * 100.0
        return progress >= 100 ? "🎯 Goal achieved!" : "🎯 \(Int(progress))% to 52/year"
    }

    private func trendString(_ pace: Double) -> String {
        pace > 30 ? "📈 Trending up" : pace > 15 ? "→ Steady" : "📉 Slow pace"
    }

    private func monthsInPeriod() -> Double {
        switch period {
        case .allTime: return 12.0 // Arbitrary for display
        case .thisYear:
            let now = Date()
            let startOfYear = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: now))!
            let monthsElapsed = Calendar.current.dateComponents([.month], from: startOfYear, to: now).month ?? 1
            return Double(max(monthsElapsed, 1))
        case .last30Days: return 1.0
        case .custom: return 1.0 // User-defined
        }
    }

    // MARK: - Caching

    /// Thread-safe cache key that includes all parameters affecting calculation
    /// FIXED: Copilot Issue #3 - Include customStart/customEnd in cache key
    private struct CacheKey: Hashable, Sendable {
        let period: TimePeriod
        let customStart: Date?
        let customEnd: Date?
    }

    /// Actor to provide thread-safe access to the cache
    /// FIXED: Copilot Issue #1 - Add thread safety to static cache
    private actor ReadingStatsCache {
        private var cachedStats: [CacheKey: ReadingStats] = [:]
        private var cacheTimestamp: Date?
        private let cacheValidityDuration: TimeInterval = 60 // 1 minute

        func get(for key: CacheKey) -> ReadingStats? {
            // Check if cache is expired
            if let timestamp = cacheTimestamp, Date().timeIntervalSince(timestamp) >= cacheValidityDuration {
                cachedStats = [:]
                cacheTimestamp = nil
                return nil
            }

            return cachedStats[key]
        }

        func set(_ stats: ReadingStats, for key: CacheKey) {
            cachedStats[key] = stats
            // FIXED: Copilot Issue #2 - Always update timestamp when setting new value
            cacheTimestamp = Date()
        }

        func invalidate() {
            cachedStats = [:]
            cacheTimestamp = nil
        }
    }

    private static let cache = ReadingStatsCache()

    /// Invalidate cache when library changes
    public static func invalidateCache() async {
        await cache.invalidate()
        print("ℹ️ ReadingStats cache invalidated")
    }

    // MARK: - Calculation

    /// Calculate reading statistics for a given time period, with caching.
    /// Cache is valid for 1 minute to avoid redundant calculations.
    public static func calculate(
        from context: ModelContext,
        period: TimePeriod,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) async throws -> ReadingStats {
        // Create cache key including all parameters
        let cacheKey = CacheKey(
            period: period,
            customStart: customStart,
            customEnd: customEnd
        )

        // Check for cached result (thread-safe via actor)
        if let cached = await cache.get(for: cacheKey) {
            return cached
        }

        // Calculate fresh stats
        let stats = try calculateFresh(
            from: context,
            period: period,
            customStart: customStart,
            customEnd: customEnd
        )

        // Update cache (thread-safe via actor)
        await cache.set(stats, for: cacheKey)

        return stats
    }

    /// Performs the actual calculation of reading statistics.
    private static func calculateFresh(
        from context: ModelContext,
        period: TimePeriod,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) throws -> ReadingStats {
        let (startDate, endDate) = period.dateRange(customStart: customStart, customEnd: customEnd)

        // Fetch all library entries
        let entryDescriptor = FetchDescriptor<UserLibraryEntry>()
        let allEntries = try context.fetch(entryDescriptor)

        // Filter by time period
        let entriesInPeriod = allEntries.filter { entry in
            if let completed = entry.dateCompleted {
                return completed >= startDate && completed <= endDate
            }
            return false
        }

        // Calculate pages read
        let pagesRead = entriesInPeriod.reduce(0) { sum, entry in
            // DEFENSIVE: Validate entry is still in context before accessing properties
            guard context.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return sum
            }
            return sum + (entry.edition?.pageCount ?? 0)
        }

        // Count completed books
        let booksCompleted = entriesInPeriod.filter { entry in
            // DEFENSIVE: Validate entry is still in context before accessing properties
            guard context.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return false
            }
            return entry.readingStatus == .read
        }.count

        // Count in-progress books
        let booksInProgress = allEntries.filter { entry in
            // DEFENSIVE: Validate entry is still in context before accessing properties
            guard context.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return false
            }
            return entry.readingStatus == .reading
        }.count

        // Calculate reading pace
        let currentlyReading = allEntries.filter { entry in
            // DEFENSIVE: Validate entry is still in context before accessing properties
            guard context.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return false
            }
            return entry.readingStatus == .reading
        }
        let paces: [Double] = currentlyReading.compactMap { entry in
            // Entry already validated in filter above, but still defensive
            guard context.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return nil
            }
            return entry.readingPace
        }
        let averagePace = paces.isEmpty ? 0.0 : paces.reduce(0, +) / Double(paces.count)
        let fastestPace = paces.max() ?? 0.0

        // Calculate diversity metrics
        let diversityStats = try DiversityStats.calculate(from: context)

        // Calculate diversity score (0-10 scale)
        // Formula: 30% regions + 30% gender + 20% languages + 20% marginalized
        let regionScore = (Double(diversityStats.totalRegionsRepresented) / 11.0) * 3.0

        let genderDiversity = calculateGenderDiversity(diversityStats.genderStats)
        let genderScore = genderDiversity * 3.0

        let languageScore = min(Double(diversityStats.totalLanguages) / 5.0, 1.0) * 2.0

        let marginalizedScore = (diversityStats.marginalizedVoicesPercentage / 100.0) * 2.0

        let diversityScore = regionScore + genderScore + languageScore + marginalizedScore

        // Calculate comparison to previous period (TODO: implement in future iteration)
        let comparisonToPrevious: Double? = nil

        return ReadingStats(
            pagesRead: pagesRead,
            booksCompleted: booksCompleted,
            booksInProgress: booksInProgress,
            averageReadingPace: averagePace,
            fastestReadingPace: fastestPace,
            diversityScore: diversityScore,
            regionsRepresented: diversityStats.totalRegionsRepresented,
            marginalizedVoicesPercentage: diversityStats.marginalizedVoicesPercentage,
            period: period,
            comparisonToPreviousPeriod: comparisonToPrevious
        )
    }

    /// Calculate gender diversity score (0-1 scale)
    /// Higher score = more balanced distribution
    private static func calculateGenderDiversity(_ genderStats: [DiversityStats.GenderStat]) -> Double {
        guard !genderStats.isEmpty else { return 0.0 }

        // Use Shannon Diversity Index (entropy)
        // Higher entropy = more diversity
        let total = Double(genderStats.reduce(0) { $0 + $1.count })
        guard total > 0 else { return 0.0 }

        let entropy = genderStats.reduce(0.0) { sum, stat in
            let p = Double(stat.count) / total
            guard p > 0 else { return sum }
            return sum - (p * log2(p))
        }

        // Normalize to 0-1 scale (max entropy for 5 genders = log2(5) ≈ 2.32)
        let maxEntropy = log2(Double(AuthorGender.allCases.count))
        return entropy / maxEntropy
    }
}
