import Foundation
import SwiftUI
import OSLog

/// View model for the Recommendations feature
/// Manages fetching, state, and user interactions with recommendations
///
/// **State Management:**
/// - Observable for reactive SwiftUI updates
/// - @MainActor for UI-safe updates
/// - Async/await for API calls
///
/// **Features:**
/// - Fetch recommendations with loading states
/// - Handle "no preferences" error → trigger onboarding
/// - Exclude books already in user's library
/// - Pull-to-refresh support
/// - Error handling with user-friendly messages
@MainActor
@Observable
public final class RecommendationsViewModel {
    // MARK: - Published State

    /// Current view state
    public private(set) var state: ViewState = .initial

    /// List of recommendations (empty until loaded)
    public private(set) var recommendations: [ScoredRecommendation] = []

    /// Strategy used to generate recommendations
    public private(set) var strategy: RecommendationStrategy?

    /// Total number of recommendations available
    public private(set) var total: Int = 0

    /// Whether to show debug information
    public var showDebugInfo: Bool = false

    /// Debug information (only populated if showDebugInfo = true)
    public private(set) var debugInfo: RecommendationDebug?

    // MARK: - Dependencies

    private let client: RecommendationsClient
    private let userId: String
    private let logger = Logger(subsystem: "com.oooefam.bookstrack", category: "RecommendationsViewModel")

    // MARK: - Initialization

    public init(
        userId: String,
        client: RecommendationsClient = RecommendationsClient()
    ) {
        self.userId = userId
        self.client = client
    }

    // MARK: - View State

    public enum ViewState: Equatable {
        /// Initial state before first load
        case initial

        /// Loading recommendations
        case loading

        /// Successfully loaded with data
        case loaded

        /// Error occurred
        case error(RecommendationError)

        /// User needs to complete onboarding (no preferences/ratings)
        case needsOnboarding
    }

    // MARK: - Public API

    /// Fetch recommendations for the current user
    /// - Parameter limit: Maximum number of recommendations (1-50, default 10)
    public func fetchRecommendations(limit: Int = 10) async {
        state = .loading
        logger.info("📚 Fetching \(limit) recommendations for user: \(self.userId)")

        do {
            let result: RecommendationResult

            if showDebugInfo {
                result = try await client.getRecommendationsDebug(
                    userId: userId,
                    limit: limit,
                    excludedISBNs: [] // TODO: Get from user's library
                )
                debugInfo = result.debug
            } else {
                result = try await client.getRecommendations(
                    userId: userId,
                    limit: limit,
                    excludedISBNs: [] // TODO: Get from user's library
                )
            }

            // Update state with smooth animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self.recommendations = result.recommendations
                self.strategy = result.strategy
                self.total = result.total
                self.state = .loaded
            }

            logger.info("📚 Loaded \(result.recommendations.count) recommendations via \(result.strategy.rawValue)")

        } catch let error as RecommendationError {
            logger.error("📚 Failed to fetch recommendations: \(error.localizedDescription)")

            // Handle specific error cases
            if error.shouldShowOnboarding {
                state = .needsOnboarding
            } else {
                state = .error(error)
            }

        } catch {
            logger.error("📚 Unexpected error: \(error.localizedDescription)")
            state = .error(.networkError(error))
        }
    }

    /// Refresh recommendations (for pull-to-refresh)
    public func refresh() async {
        await fetchRecommendations()
    }

    /// Retry after error
    public func retry() async {
        await fetchRecommendations()
    }

    /// Mark a recommendation as added to library (optimistic update)
    /// - Parameter isbn: ISBN of the book added to library
    public func markAsAddedToLibrary(isbn: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            recommendations.removeAll { $0.book.isbn == isbn }
            total = max(0, total - 1)
        }
        logger.info("📚 Removed \(isbn) from recommendations (added to library)")
    }

    // MARK: - Computed Properties

    /// Whether the view is currently loading
    public var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    /// Whether recommendations are empty (after successful load)
    public var isEmpty: Bool {
        if case .loaded = state {
            return recommendations.isEmpty
        }
        return false
    }

    /// User-friendly error message
    public var errorMessage: String? {
        if case .error(let error) = state {
            return error.localizedDescription
        }
        return nil
    }

    /// Whether to show onboarding flow
    public var shouldShowOnboarding: Bool {
        if case .needsOnboarding = state {
            return true
        }
        return false
    }

    /// Strategy display text for UI
    public var strategyDisplayText: String? {
        strategy?.displayName
    }
}
