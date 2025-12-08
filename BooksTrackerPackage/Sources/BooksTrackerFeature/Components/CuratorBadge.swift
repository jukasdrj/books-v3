import SwiftUI

/// A badge component that displays when a user has reached "Curator" status (5+ contributions).
/// Shows a sparkle icon with the user's total contribution points.
@available(iOS 26.0, *)
public struct CuratorBadge: View {
    let totalPoints: Int
    let compact: Bool

    @Environment(\.iOS26ThemeStore) private var themeStore

    /// Initialize the curator badge
    /// - Parameters:
    ///   - totalPoints: The user's total curator points
    ///   - compact: Whether to show a compact version (for inline display next to username)
    public init(totalPoints: Int, compact: Bool = false) {
        self.totalPoints = totalPoints
        self.compact = compact
    }

    /// Whether the user has achieved curator status
    private var isCurator: Bool {
        totalPoints >= CuratorPointsService.curatorThreshold
    }

    public var body: some View {
        if isCurator {
            if compact {
                compactBadge
            } else {
                fullBadge
            }
        }
    }

    // MARK: - Compact Badge (Inline)

    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(themeStore.primaryColor)
                .symbolEffect(.pulse, options: .repeating)

            Text("Curator")
                .font(.caption2.bold())
                .foregroundStyle(themeStore.primaryColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(themeStore.primaryColor.opacity(0.1))
        }
        .accessibilityLabel("Curator badge - \(totalPoints) contribution points")
    }

    // MARK: - Full Badge (Profile Display)

    private var fullBadge: some View {
        VStack(spacing: 12) {
            // Badge icon with flair
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                themeStore.primaryColor.opacity(0.2),
                                themeStore.primaryColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                // Star icon
                Image(systemName: "star.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeStore.primaryColor,
                                themeStore.primaryColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
                    .shadow(color: themeStore.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            // Badge title and points
            VStack(spacing: 4) {
                Text("Curator")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text("\(totalPoints) Points")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    themeStore.primaryColor.opacity(0.3),
                                    themeStore.primaryColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Curator badge earned")
        .accessibilityValue("\(totalPoints) contribution points")
    }
}

// MARK: - Preview

#Preview("Full Badge") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    VStack(spacing: 32) {
        CuratorBadge(totalPoints: 150, compact: false)
        CuratorBadge(totalPoints: 75, compact: false)
    }
    .padding()
    .environment(\.iOS26ThemeStore, themeStore)
}

#Preview("Compact Badge") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    VStack(spacing: 16) {
        HStack {
            Text("Username")
                .font(.headline)
            CuratorBadge(totalPoints: 150, compact: true)
        }

        HStack {
            Text("Another User")
                .font(.headline)
            CuratorBadge(totalPoints: 75, compact: true)
        }
    }
    .padding()
    .environment(\.iOS26ThemeStore, themeStore)
}

#Preview("Below Threshold") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    VStack {
        Text("User with 50 points (below curator threshold):")
            .font(.caption)

        CuratorBadge(totalPoints: 50, compact: false)

        Text("Nothing should render above")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .environment(\.iOS26ThemeStore, themeStore)
}
