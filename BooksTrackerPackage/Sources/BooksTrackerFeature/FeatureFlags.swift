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

    public static let shared = FeatureFlags()

    private init() {}

    /// Reset all feature flags to default values
    /// Called during library reset to restore clean state
    public func resetToDefaults() {
        enableTabBarMinimize = true  // Default enabled
        coverSelectionStrategy = .auto  // Default auto
        #if DEBUG
        print("✅ FeatureFlags reset to defaults (tabBarMinimize: true, coverSelection: auto)")
        #endif
    }
}
