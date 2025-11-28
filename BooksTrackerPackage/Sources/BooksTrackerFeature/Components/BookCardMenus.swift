import SwiftUI
import SwiftData

// MARK: - Quick Actions Menu Builders

/// Reusable quick actions context menus for book cards
/// Refactored from iOS26AdaptiveBookCard, iOS26LiquidListRow, and iOS26FloatingBookCard

// MARK: - Full Quick Actions Menu

/// A reusable quick actions context menu for book cards
@available(iOS 26.0, *)
public struct BookCardQuickActionsMenu: View {
    let work: Work
    let userEntry: UserLibraryEntry?
    let onStatusChange: (ReadingStatus) -> Void
    let onRatingChange: ((Double) -> Void)?
    let onRemove: (() -> Void)?

    public init(
        work: Work,
        userEntry: UserLibraryEntry?,
        onStatusChange: @escaping (ReadingStatus) -> Void,
        onRatingChange: ((Double) -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.work = work
        self.userEntry = userEntry
        self.onStatusChange = onStatusChange
        self.onRatingChange = onRatingChange
        self.onRemove = onRemove
    }

    public var body: some View {
        Group {
            if let userEntry = userEntry {
                // Status change submenu
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(ReadingStatus.allCases.filter { $0 != userEntry.readingStatus }, id: \.self) { status in
                        Button(status.displayName, systemImage: status.systemImage) {
                            onStatusChange(status)
                        }
                    }
                }

                Divider()

                // Quick rating (if owned and callback provided)
                if !userEntry.isWishlistItem, let onRatingChange = onRatingChange {
                    Menu("Rate Book", systemImage: "star") {
                        ForEach(1...5, id: \.self) { rating in
                            Button("\(rating) Stars") {
                                onRatingChange(Double(rating))
                            }
                        }
                        Button("Remove Rating") {
                            onRatingChange(0)
                        }
                    }
                }

                if onRemove != nil {
                    Divider()

                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        onRemove?()
                    }
                }
            }

            // Note: "View Details" navigation should be handled by parent view's NavigationLink
            // Not included here to avoid confusion with no-op buttons
        }
    }
}

// MARK: - Simple Quick Actions (for simpler card types)

/// Simplified quick actions for cards that only need basic status changes
@available(iOS 26.0, *)
public struct SimpleBookCardQuickActions: View {
    let userEntry: UserLibraryEntry?
    let onMarkReading: () -> Void
    let onMarkRead: () -> Void
    let onRemove: (() -> Void)?

    public init(
        userEntry: UserLibraryEntry?,
        onMarkReading: @escaping () -> Void,
        onMarkRead: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.userEntry = userEntry
        self.onMarkReading = onMarkReading
        self.onMarkRead = onMarkRead
        self.onRemove = onRemove
    }

    public var body: some View {
        Group {
            if userEntry != nil {
                Button("Mark as Reading", systemImage: "book.pages") {
                    onMarkReading()
                }

                Button("Mark as Read", systemImage: "checkmark.circle") {
                    onMarkRead()
                }

                if let onRemove = onRemove {
                    Button("Remove from Library", systemImage: "trash", role: .destructive) {
                        onRemove()
                    }
                }
            }

            // Note: "View Details" navigation should be handled by parent view's NavigationLink
            // Not included here to avoid confusion with no-op buttons
        }
    }
}
