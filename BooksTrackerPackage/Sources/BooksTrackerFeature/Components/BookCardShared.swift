import SwiftUI
import SwiftData

// MARK: - Shared Book Card Components

/// Shared components, actions, and utilities for book card views
/// Refactored from iOS26AdaptiveBookCard, iOS26LiquidListRow, and iOS26FloatingBookCard
/// to eliminate code duplication while maintaining consistent behavior

// MARK: - Cultural Diversity Badge

/// A reusable cultural diversity badge shown on book cards for marginalized voices
@available(iOS 26.0, *)
public struct CulturalDiversityBadge: View {
    let culturalRegion: CulturalRegion?
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    public init(for author: Author?) {
        self.culturalRegion = author?.culturalRegion
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
            
            if let region = culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .glassEffect(.subtle)
    }
}

// MARK: - Status Badge Variants

/// A compact status badge shown as a circular indicator
@available(iOS 26.0, *)
public struct StatusBadgeCircle: View {
    let status: ReadingStatus
    let size: CGFloat
    
    public init(status: ReadingStatus, size: CGFloat = 28) {
        self.status = status
        self.size = size
    }
    
    public var body: some View {
        Circle()
            .fill(status.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
            .glassEffect(.subtle)
            .shadow(color: status.color.opacity(0.4), radius: 5, x: 0, y: 2)
    }
}

/// A compact inline status indicator with text
@available(iOS 26.0, *)
public struct StatusBadgeInline: View {
    let status: ReadingStatus
    
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundColor(status.color)
        }
    }
}

// MARK: - Reading Progress Overlay

/// A reusable progress bar overlay for active reading books
@available(iOS 26.0, *)
public struct ReadingProgressOverlay: View {
    let progress: Double
    
    public init(progress: Double) {
        self.progress = progress
    }
    
    public var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
            .scaleEffect(y: 1.5, anchor: .bottom)
            .padding(10)
            .background(.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Book Cover Placeholder

/// A reusable placeholder for book covers with theme colors
@available(iOS 26.0, *)
public struct BookCoverPlaceholder: View {
    let title: String
    let iconFont: Font
    let showTitle: Bool
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    public init(title: String, iconFont: Font = .title2, showTitle: Bool = true) {
        self.title = title
        self.iconFont = iconFont
        self.showTitle = showTitle
    }
    
    public var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [
                    themeStore.primaryColor.opacity(0.3),
                    themeStore.secondaryColor.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(iconFont)
                        .foregroundColor(.white.opacity(0.8))
                    
                    if showTitle {
                        Text(title)
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
            }
    }
}

// MARK: - Book Card Actions

/// Shared actions for book cards, providing consistent behavior across card types
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
        
        triggerHapticFeedback(.success)
    }
    
    /// Sets the rating for a library entry
    @MainActor
    public static func setRating(_ rating: Double, for userEntry: UserLibraryEntry?) {
        guard let userEntry = userEntry, !userEntry.isWishlistItem else { return }
        
        userEntry.personalRating = rating > 0 ? rating : nil
        userEntry.rating = rating > 0 ? Int(rating) : nil
        userEntry.touch()
        
        triggerHapticFeedback(.success)
    }
    
    /// Triggers haptic feedback for user interactions
    @MainActor
    public static func triggerHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
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

// MARK: - Accessibility Helpers

/// Shared accessibility description builder for book cards
public enum BookCardAccessibility {
    
    /// Builds a comprehensive accessibility description for a book
    public static func buildDescription(
        work: Work,
        userEntry: UserLibraryEntry?,
        includeYear: Bool = false
    ) -> String {
        var description = "Book: \(work.title) by \(work.authorNames)"
        
        if includeYear, let year = work.firstPublicationYear {
            description += ", Published \(year)"
        }
        
        if let userEntry = userEntry {
            description += ", Status: \(userEntry.readingStatus.displayName)"
            if userEntry.readingStatus == .reading && userEntry.readingProgress > 0 {
                description += ", Progress: \(Int(userEntry.readingProgress * 100))%"
            }
        }
        
        return description
    }
}

// MARK: - Quick Actions Menu Builder

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
            
            Button("View Details", systemImage: "info.circle") {
                // Navigate to detail view - handled by parent
            }
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
            
            Button("View Details", systemImage: "info.circle") {
                // Navigate to detail view - handled by parent
            }
        }
    }
}
