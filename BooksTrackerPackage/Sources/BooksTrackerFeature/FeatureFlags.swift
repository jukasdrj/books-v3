import SwiftUI

/// Strategy for selecting which edition cover to display
public enum CoverSelectionStrategy: String, CaseIterable, Sendable {
    /// Automatic quality-based selection (default)
    /// Uses quality scoring algorithm: cover availability > format > recency > data quality
    case auto = "auto"

    /// Prefer most recent publication
    case recent = "recent"

    /// Prefer hardcover editions
    case hardcover = "hardcover"

    /// Manual user selection required
    case manual = "manual"

    public var displayName: String {
        switch self {
        case .auto: return "Auto (Best Quality)"
        case .recent: return "Most Recent"
        case .hardcover: return "Prefer Hardcover"
        case .manual: return "Manual Selection"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Automatically selects the best edition based on cover quality, format, and data completeness"
        case .recent: return "Shows the most recently published edition"
        case .hardcover: return "Prioritizes hardcover editions when available"
        case .manual: return "You manually choose which edition to display for each book"
        }
    }
}

/// Feature flags for experimental iOS 26 features
///
/// This observable class manages feature toggles that can be enabled/disabled
/// via Settings. Flags are persisted using UserDefaults for user preference retention.
@Observable
public final class FeatureFlags: Sendable {
    /// Enable tab bar minimize behavior on scroll
    ///
    /// When enabled, the tab bar automatically hides when scrolling down
    /// and reappears when scrolling up. This provides more screen space
    /// for content while maintaining easy access to navigation.
    ///
    /// Default: `true` (enabled)
    ///
    /// Note: This behavior is automatically disabled for VoiceOver and
    /// Reduce Motion accessibility settings, regardless of this flag.
    public var enableTabBarMinimize: Bool {
        get {
            UserDefaults.standard.object(forKey: "enableTabBarMinimize") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableTabBarMinimize")
        }
    }

    /// Cover selection strategy for edition display
    ///
    /// Controls which edition's cover image is displayed when a work has multiple editions.
    /// - `.auto`: Quality-based scoring (default) - considers cover availability, format preference, recency, and data quality
    /// - `.recent`: Most recently published edition
    /// - `.hardcover`: Prioritizes hardcover editions
    /// - `.manual`: User must manually select preferred edition
    ///
    /// Default: `.auto`
    public var coverSelectionStrategy: CoverSelectionStrategy {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "coverSelectionStrategy"),
               let strategy = CoverSelectionStrategy(rawValue: rawValue) {
                return strategy
            }
            return .auto  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "coverSelectionStrategy")
        }
    }

    /// Disable canonical /v1/enrichment/batch endpoint (opt-out flag)
    ///
    /// When enabled, forces use of legacy /api/enrichment/batch endpoint.
    /// Useful for debugging or if canonical endpoint has issues.
    ///
    /// Default: `false` (canonical endpoint enabled)
    ///
    /// Note: Legacy endpoint will be removed in backend v2.0 (January 2026).
    /// This flag provides emergency fallback only.
    public var disableCanonicalEnrichment: Bool {
        get {
            UserDefaults.standard.bool(forKey: "feature.disableCanonicalEnrichment")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.disableCanonicalEnrichment")
        }
    }

    // MARK: - API Capabilities Integration

    /// Cached API capabilities from backend
    /// Updated on app launch by CapabilitiesService
    /// Used to conditionally enable/disable features based on backend support
    private var _cachedCapabilities: APICapabilities?

    /// Update capabilities cache (called by app initialization)
    /// - Parameter capabilities: Fresh capabilities from backend
    public func updateCapabilities(_ capabilities: APICapabilities) {
        _cachedCapabilities = capabilities
        #if DEBUG
        print("✅ FeatureFlags: Capabilities updated (v\(capabilities.version))")
        #endif
    }

    /// Check if a feature is available based on backend capabilities
    /// Falls back to optimistic defaults if capabilities not yet fetched
    /// - Parameter feature: Feature to check
    /// - Returns: Whether feature is available
    public func isFeatureAvailable(_ feature: APICapabilities.Feature) -> Bool {
        // If capabilities not yet fetched, return optimistic defaults
        guard let capabilities = _cachedCapabilities else {
            // Default: Assume V1 capabilities only
            switch feature {
            case .semanticSearch, .similarBooks, .weeklyRecommendations, .sseStreaming:
                return false // V2 features
            case .batchEnrichment, .csvImport:
                return true // V1 features
            }
        }

        return capabilities.isFeatureAvailable(feature)
    }

    /// Get rate limit for a specific operation
    /// - Parameter operation: Operation type
    /// - Returns: Rate limit in requests per minute
    public func getRateLimit(for operation: RateLimitOperation) -> Int {
        guard let capabilities = _cachedCapabilities else {
            // Default limits
            switch operation {
            case .semanticSearch: return 5
            case .textSearch: return 100
            }
        }

        switch operation {
        case .semanticSearch:
            return capabilities.limits.semanticSearchRpm
        case .textSearch:
            return capabilities.limits.textSearchRpm
        }
    }

    /// Get resource limit for a specific constraint
    /// - Parameter constraint: Resource constraint type
    /// - Returns: Maximum allowed value
    public func getResourceLimit(for constraint: ResourceConstraint) -> Int {
        guard let capabilities = _cachedCapabilities else {
            // Default limits
            switch constraint {
            case .csvMaxRows: return 500
            case .batchMaxPhotos: return 5
            }
        }

        switch constraint {
        case .csvMaxRows:
            return capabilities.limits.csvMaxRows
        case .batchMaxPhotos:
            return capabilities.limits.batchMaxPhotos
        }
    }

    /// Get current API version from backend
    /// - Returns: Backend API version or "unknown" if not fetched
    public func getAPIVersion() -> String {
        return _cachedCapabilities?.version ?? "unknown"
    }

    /// Rate limit operations
    public enum RateLimitOperation {
        case semanticSearch
        case textSearch
    }

    /// Resource constraints
    public enum ResourceConstraint {
        case csvMaxRows
        case batchMaxPhotos
    }

    public static let shared = FeatureFlags()

    private init() {}

    /// Reset all feature flags to default values
    /// Called during library reset to restore clean state
    public func resetToDefaults() {
        enableTabBarMinimize = true  // Default enabled
        coverSelectionStrategy = .auto  // Default auto
        disableCanonicalEnrichment = false  // Default canonical endpoint
        #if DEBUG
        print("✅ FeatureFlags reset to defaults (tabBarMinimize: true, coverSelection: auto, canonicalEnrichment: true)")
        #endif
    }
}
