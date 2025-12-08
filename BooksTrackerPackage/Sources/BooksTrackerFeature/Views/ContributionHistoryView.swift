import SwiftUI

/// Displays the user's contribution history for diversity metadata.
/// Shows recent contributions with points awarded and curator progress.
@available(iOS 26.0, *)
public struct ContributionHistoryView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.curatorPointsService) private var curatorPointsService

    /// Initialize the contribution history view
    public init() {}

    /// Curator status threshold
    private let curatorThreshold = CuratorPointsService.curatorThreshold

    /// Whether the user has achieved curator status
    private var isCurator: Bool {
        (curatorPointsService?.totalPoints ?? 0) >= curatorThreshold
    }

    /// Progress percentage towards curator status
    private var progressPercentage: Double {
        let points = Double(curatorPointsService?.totalPoints ?? 0)
        return min(points / Double(curatorThreshold), 1.0)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with progress
                progressSection

                // Curator badge (if earned)
                if isCurator {
                    curatorBadgeSection
                }

                // How to earn points
                earnPointsSection

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Curator Progress")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            // Total points
            VStack(spacing: 8) {
                Text("\(curatorPointsService?.totalPoints ?? 0)")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(themeStore.primaryColor)

                Text("Curator Points")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            if !isCurator {
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            // Progress fill
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            themeStore.primaryColor,
                                            themeStore.primaryColor.opacity(0.7)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progressPercentage, height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Progress text
                    HStack {
                        Text("\(Int(progressPercentage * 100))% to Curator")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(curatorThreshold - (curatorPointsService?.totalPoints ?? 0)) points needed")
                            .font(.caption.bold())
                            .foregroundStyle(themeStore.primaryColor)
                    }
                }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Curator Badge Section

    private var curatorBadgeSection: some View {
        VStack(spacing: 16) {
            // Celebration header
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(themeStore.primaryColor)
                    .symbolEffect(.pulse, options: .repeating)

                Text("You're a Curator!")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Spacer()
            }

            // Badge display
            CuratorBadge(totalPoints: curatorPointsService?.totalPoints ?? 0, compact: false)

            // Explanation
            Text("You've contributed diversity metadata to help the community track representation in their reading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
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
    }

    // MARK: - Earn Points Section

    private var earnPointsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to Earn Points")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                // Cultural origins
                contributionTypeRow(
                    icon: "globe.americas.fill",
                    title: "Cultural Origins",
                    points: 15,
                    description: "Add an author's cultural background"
                )

                // Gender distribution
                contributionTypeRow(
                    icon: "person.2.fill",
                    title: "Gender Identity",
                    points: 10,
                    description: "Add an author's gender identity"
                )

                // Translation status
                contributionTypeRow(
                    icon: "text.book.closed.fill",
                    title: "Original Language",
                    points: 5,
                    description: "Add a book's original language"
                )

                // Cascade multiplier
                contributionTypeRow(
                    icon: "arrow.down.circle.fill",
                    title: "Cascade to All Books",
                    points: 25,  // 5x multiplier example (5 books × 5 points)
                    description: "Apply metadata to all books by an author",
                    isSpecial: true
                )
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func contributionTypeRow(
        icon: String,
        title: String,
        points: Int,
        description: String,
        isSpecial: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isSpecial ? themeStore.primaryColor : .secondary)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(isSpecial ? themeStore.primaryColor.opacity(0.1) : Color.secondary.opacity(0.1))
                }

            // Title and description
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Points badge
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(isSpecial ? themeStore.primaryColor : .yellow)

                Text("+\(points)")
                    .font(.caption.bold())
                    .foregroundStyle(isSpecial ? themeStore.primaryColor : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSpecial ? themeStore.primaryColor.opacity(0.15) : Color.secondary.opacity(0.1))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    let curatorPointsService = CuratorPointsService()

    // Simulate some points awarded
    curatorPointsService.awardPoints(45, for: "Preview")

    return NavigationStack {
        ContributionHistoryView()
            .environment(\.iOS26ThemeStore, themeStore)
            .environment(\.curatorPointsService, curatorPointsService)
    }
}

#Preview("Curator Status") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    let curatorPointsService = CuratorPointsService()

    // Simulate curator status achieved
    curatorPointsService.awardPoints(150, for: "Preview")

    return NavigationStack {
        ContributionHistoryView()
            .environment(\.iOS26ThemeStore, themeStore)
            .environment(\.curatorPointsService, curatorPointsService)
    }
}
