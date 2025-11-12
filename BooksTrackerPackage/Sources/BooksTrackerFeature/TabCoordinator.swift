import SwiftUI

/// Coordinates navigation actions between tabs
/// Used for cross-tab navigation (e.g., Shelf scan → Library after adding books)
@MainActor
@Observable
public final class TabCoordinator {
    /// The currently selected tab
    public var selectedTab: MainTab = .library

    /// Pending action to switch to Library tab (consumed after switch)
    private var pendingSwitchToLibrary: Bool = false

    public init() {}

    /// Request switch to Library tab
    /// Used after successful operations (e.g., shelf scan add to library)
    public func switchToLibrary() {
        selectedTab = .library
        pendingSwitchToLibrary = true
    }

    /// Check and consume pending Library tab switch
    /// Returns true if switch was pending (one-time use)
    public func consumePendingLibrarySwitch() -> Bool {
        let pending = pendingSwitchToLibrary
        pendingSwitchToLibrary = false
        return pending
    }
}
