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

    /// IDs of books to highlight after enrichment
    public var highlightedBookIDs: Set<PersistentIdentifier> = []


    public init() {}

    /// Request switch to Library tab
    /// Used after successful operations (e.g., shelf scan add to library)
    public func switchToLibrary() {
        selectedTab = .library
        pendingSwitchToLibrary = true
        highlightedBookIDs = [] // Clear highlights on generic switch
    }

    /// Switch to library and highlight specific books
    public func showEnrichedBooksInLibrary(bookIDs: [PersistentIdentifier]) {
        highlightedBookIDs = Set(bookIDs)
        selectedTab = .library
    }

    /// Check and consume pending Library tab switch
    /// Returns true if switch was pending (one-time use)
    public func consumePendingLibrarySwitch() -> Bool {
        let pending = pendingSwitchToLibrary
        pendingSwitchToLibrary = false
        return pending
    }
}
