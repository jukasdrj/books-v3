import Foundation
import SwiftUI

/// Centralized service for resolving book cover image URLs with intelligent fallback logic.
///
/// **Problem:** Cover images can be stored at multiple levels (Edition, Work) due to enrichment
/// from different data sources. Display views need a single, reliable method to get the best
/// available cover URL without duplicating fallback logic.
///
/// **Solution:** This service implements a prioritized fallback chain:
/// 1. Primary Edition cover (selected by AutoStrategy which prioritizes editions with covers)
/// 2. Work-level cover (populated by enrichment as fallback)
/// 3. nil (triggers placeholder in UI)
///
/// **Usage:**
/// ```swift
/// struct BookCard: View {
///     let work: Work
///
///     var body: some View {
///         CachedAsyncImage(url: CoverImageService.coverURL(for: work)) {
///             image in image.resizable()
///         } placeholder: {
///             PlaceholderView()
///         }
///     }
/// }
/// ```
///
/// **Architecture Decision:**
/// - Static methods (no instance needed)
/// - Works with existing Work/Edition models
/// - Delegates edition selection to Work.primaryEdition (uses EditionSelectionStrategy)
/// - Zero side effects (pure function)
///
/// **Testing:** See `CoverImageServiceTests` for fallback logic verification.
///
/// **Related:**
/// - `EditionSelectionStrategy` - Selects best edition (AutoStrategy prioritizes covers +10 points)
/// - `EnrichmentQueue.applyEnrichedData()` - Populates Work.coverImageURL as fallback
/// - `Edition.coverURL` - Converts string to URL
///
/// **History:**
/// - Created: 2025-11-09 (Issue #[TBD])
/// - Fix for missing covers due to missing fallback logic in display views
@MainActor
public final class CoverImageService {

    // MARK: - Public API

    /// Get cover URL for display with intelligent fallback logic.
    ///
    /// **Fallback Chain:**
    /// 1. `work.primaryEdition.coverURL` - Uses AutoStrategy to pick edition with best cover
    /// 2. `work.coverImageURL` - Fallback populated by enrichment when no edition has cover
    /// 3. `nil` - No cover available at any level (triggers placeholder)
    ///
    /// **Example:**
    /// ```swift
    /// let coverURL = CoverImageService.coverURL(for: work)
    /// ```
    ///
    /// - Parameter work: The work to get cover URL for
    /// - Returns: URL for best available cover image, or nil if none exists
    public static func coverURL(for work: Work) -> URL? {
        // 1. Try primary edition (delegates to EditionSelectionStrategy)
        //    AutoStrategy gives +10 bonus for editions with covers
        if let primaryEdition = work.primaryEdition,
           let coverURL = primaryEdition.coverURL {
            return coverURL
        }

        // 2. Fall back to Work-level cover
        //    Populated by EnrichmentQueue.applyEnrichedData() when edition lacks cover
        if let coverImageURL = work.coverImageURL,
           !coverImageURL.isEmpty,
           let url = URL(string: coverImageURL) {
            return url
        }

        // 3. No cover available
        return nil
    }

    /// Get cover URL for a specific edition with Work fallback.
    ///
    /// **Use Case:** When you already have a specific edition selected (e.g., user's owned edition)
    /// but still want Work-level fallback if that edition lacks a cover.
    ///
    /// **Example:**
    /// ```swift
    /// let userEdition = work.userEntry?.edition
    /// let coverURL = CoverImageService.coverURL(for: userEdition, work: work)
    /// ```
    ///
    /// - Parameters:
    ///   - edition: The specific edition to check first (can be nil)
    ///   - work: The work to fall back to if edition has no cover
    /// - Returns: URL for best available cover image, or nil if none exists
    public static func coverURL(for edition: Edition?, work: Work) -> URL? {
        // Try specific edition first
        if let edition = edition, let coverURL = edition.coverURL {
            return coverURL
        }

        // Fall back to work-level logic (includes primary edition fallback)
        return coverURL(for: work)
    }

    // MARK: - Diagnostic Helpers

    /// Check where the cover URL is coming from (for debugging/logging).
    ///
    /// **Use Case:** Debugging why covers aren't appearing, understanding data quality.
    ///
    /// **Example:**
    /// ```swift
    /// let source = CoverImageService.coverSource(for: work)
    /// print("Cover from: \(source)") // "primaryEdition", "work", or "none"
    /// ```
    ///
    /// - Parameter work: The work to check
    /// - Returns: Source of cover URL ("primaryEdition", "work", or "none")
    public static func coverSource(for work: Work) -> String {
        if work.primaryEdition?.coverURL != nil {
            return "primaryEdition"
        }
        if let coverImageURL = work.coverImageURL, !coverImageURL.isEmpty {
            return "work"
        }
        return "none"
    }

    /// Check if work has any cover available at any level.
    ///
    /// **Use Case:** Filter books by cover availability, show "missing cover" indicators.
    ///
    /// **Example:**
    /// ```swift
    /// if !CoverImageService.hasCover(work) {
    ///     showMissingCoverBadge = true
    /// }
    /// ```
    ///
    /// - Parameter work: The work to check
    /// - Returns: True if cover exists at any level (edition or work)
    public static func hasCover(_ work: Work) -> Bool {
        return coverURL(for: work) != nil
    }
}
