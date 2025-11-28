import SwiftUI
import SwiftData

// MARK: - Book Card Actions

/// Shared actions for book cards, providing consistent behavior across card types
/// Refactored from iOS26AdaptiveBookCard, iOS26LiquidListRow, and iOS26FloatingBookCard
@available(iOS 26.0, *)
public enum BookCardActions {

    /// Updates the reading status of a library entry with proper date tracking
    @MainActor
    public static func updateReadingStatus(_ status: ReadingStatus, for userEntry: UserLibraryEntry?) {
        guard let userEntry = userEntry else { return }

        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()

        triggerNotificationFeedback(.success)
    }

    /// Sets the rating for a library entry
    @MainActor
    public static func setRating(_ rating: Double, for userEntry: UserLibraryEntry?) {
        guard let userEntry = userEntry, !userEntry.isWishlistItem else { return }

        userEntry.personalRating = rating > 0 ? rating : nil
        userEntry.rating = rating > 0 ? Int(rating) : nil
        userEntry.touch()

        triggerNotificationFeedback(.success)
    }

    /// Triggers notification-style haptic feedback (success, warning, error)
    @MainActor
    public static func triggerNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(type)
    }

    /// Triggers impact haptic feedback for press gestures
    @MainActor
    public static func triggerImpactFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}
