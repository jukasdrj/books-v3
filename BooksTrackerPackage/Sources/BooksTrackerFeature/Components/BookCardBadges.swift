import SwiftUI
import SwiftData

// MARK: - Book Card Badge Components

/// Badge components for book cards: status indicators and cultural diversity badges
/// Refactored from iOS26AdaptiveBookCard, iOS26LiquidListRow, and iOS26FloatingBookCard

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
