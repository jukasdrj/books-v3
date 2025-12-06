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
@MainActor
@Observable
public final class FeatureFlags {
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

    /// Disable V3 API enrichment endpoint (opt-out flag)
    ///
    /// When enabled, forces use of legacy /api/enrichment/batch endpoint.
    /// Useful for debugging or if V3 endpoint has issues.
    ///
    /// Default: `false` (V3 /v3/books/enrich endpoint enabled)
    ///
    /// Note: V1 endpoints sunset March 1, 2026. Legacy /api endpoint will be removed in backend v2.0 (January 2026).
    /// This flag provides emergency fallback only.
    public var disableCanonicalEnrichment: Bool {
        get {
            UserDefaults.standard.bool(forKey: "feature.disableCanonicalEnrichment")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.disableCanonicalEnrichment")
        }
    }

    /// Enable V2 Unified Search API (/api/v2/search)
    ///
    /// All search queries now use the V2 unified search endpoint.
    /// This supports text, semantic, and hybrid search modes.
    ///
    /// Default: `true` (V2 is now the primary search API)
    ///
    /// Note: V1 search endpoints are deprecated and will be removed
    /// after March 1, 2026. This flag is kept for emergency rollback only.
    public var enableV2Search: Bool {
        get {
            // Default to true - V2 is now the primary search API
            UserDefaults.standard.object(forKey: "feature.enableV2Search") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.enableV2Search")
        }
    }

    /// Enable Cloudflare Workflows for ISBN import
    ///
    /// When enabled, ISBN scans will use the Cloudflare Workflows API
    /// for durable, step-by-step import with automatic retries and
    /// state persistence.
    ///
    /// Benefits:
    /// - Automatic retries (3x with backoff)
    /// - State persistence across failures
    /// - Step-by-step observability
    ///
    /// Default: `false` (disabled, uses standard search flow)
    ///
    /// Note: This is a P2 enhancement. Standard ISBN search still works.
    public var enableWorkflowImport: Bool {
        get {
            UserDefaults.standard.bool(forKey: "feature.enableWorkflowImport")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.enableWorkflowImport")
        }
    }

    /// Enable SSE for Photo Scan progress updates (API Contract v3.2)
    ///
    /// When enabled, photo scan operations will use Server-Sent Events (SSE)
    /// for real-time progress updates instead of WebSocket.
    ///
    /// Benefits:
    /// - Simpler protocol (HTTP-based)
    /// - Better firewall/proxy compatibility
    /// - Automatic reconnection handling
    /// - Lower server resource usage
    ///
    /// Default: `true` (enabled, SSE is now the primary transport)
    ///
    /// Note: Phase 1 of WebSocket to SSE migration (Issue #142).
    /// WebSocket fallback remains available if SSE fails.
    public var enablePhotoScanSSE: Bool {
        get {
            UserDefaults.standard.object(forKey: "feature.enablePhotoScanSSE") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.enablePhotoScanSSE")
        }
    }

    /// Enable V3 API for book search operations
    ///
    /// When enabled, all book search requests will use the V3 API client
    /// instead of the legacy V2 API. Falls back to V2 if V3 is disabled.
    ///
    /// Default: `true` (enabled, uses V3 API)
    ///
    /// Note: This is part of the V3 Migration Plan (Phase 3).
    /// V3 is now production-ready and default.
    public var enableV3Search: Bool {
        get {
            UserDefaults.standard.object(forKey: "feature.enableV3Search") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.enableV3Search")
        }
    }

    /// Stores the API capabilities fetched from the backend.
    /// This property is populated on app launch and is used to conditionally
    /// enable or disable features based on backend support.
    public var apiCapabilities: APICapabilities?

    public static let shared = FeatureFlags()

    private init() {}

    /// Reset all feature flags to default values
    /// Called during library reset to restore clean state
    public func resetToDefaults() {
        enableTabBarMinimize = true  // Default enabled
        coverSelectionStrategy = .auto  // Default auto
        disableCanonicalEnrichment = false  // Default canonical endpoint
        enableV2Search = true // V2 search is now the default
        enableWorkflowImport = false // Default workflow import disabled
        enablePhotoScanSSE = true // Default SSE enabled (Phase 1 migration, Issue #142)
        enableV3Search = true // V3 search is now the default
        #if DEBUG
        print("FeatureFlags reset to defaults (tabBarMinimize: true, coverSelection: auto, canonicalEnrichment: true, v2Search: true, v3Search: true, workflowImport: false, photoScanSSE: true)")
        #endif
    }
}
