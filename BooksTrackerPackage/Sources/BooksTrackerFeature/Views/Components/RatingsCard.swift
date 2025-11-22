import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - RatingsCard
/// A SwiftUI component to display and edit multi-source book ratings.
/// It supports user ratings (editable), critics ratings (read-only), and community ratings (read-only).
@available(iOS 26.0, *)
@MainActor
public struct RatingsCard: View {
    @Bindable public var enrichment: BookEnrichment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    // Hardcoded for now as per requirements. In future, these would come from an API.
    private let criticsRating: Double? = nil // Example: 4.5 (NYT)
    private let communityRating: Double? = nil // Example: 4.2 (Goodreads)

    public init(enrichment: BookEnrichment) {
        self.enrichment = enrichment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ratings")
                .font(.headline)
                .foregroundStyle(.primary)

            // MARK: - User Rating (Editable)
            HStack {
                Text("Your Rating:")
                    .foregroundStyle(.primary)
                Spacer()
                StarRatingView(
                    rating: $enrichment.userRating,
                    maxRating: 5,
                    fillColor: .orange,
                    emptyColor: Color(.systemGray3),
                    accessibilityLabelPrefix: "Your rating"
                ) { newRating in
                    // Save logic
                    enrichment.userRating = newRating
                    enrichment.lastEnriched = Date()
                    triggerHapticFeedback()
                    do {
                        try modelContext.save()
                    } catch {
                        print("Failed to save user rating: \(error.localizedDescription)")
                        // Potentially show an error to the user
                    }
                }
            }

            // MARK: - Critics Rating (Read-Only)
            if let criticsRating = criticsRating {
                HStack {
                    Text("Critics (NYT):")
                        .foregroundStyle(.primary)
                    Spacer()
                    StarRatingView(
                        readOnlyRating: criticsRating,
                        maxRating: 5,
                        fillColor: .blue,
                        emptyColor: Color(.systemGray3),
                        accessibilityLabelPrefix: "Critics rating"
                    )
                }
            }

            // MARK: - Community Rating (Read-Only)
            if let communityRating = communityRating {
                HStack {
                    Text("Community:")
                        .foregroundStyle(.primary)
                    Spacer()
                    StarRatingView(
                        readOnlyRating: communityRating,
                        maxRating: 5,
                        fillColor: .green,
                        emptyColor: Color(.systemGray3),
                        accessibilityLabelPrefix: "Community rating"
                    )
                    Text("(\(communityRating, specifier: "%.1f")/5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    /// Triggers haptic feedback for selection style.
    private func triggerHapticFeedback() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    // MARK: - StarRatingView (Nested Helper)
    /// A helper view to display a row of stars, supporting both editable and read-only modes,
    /// and fractional star display for read-only ratings.
    private struct StarRatingView: View {
        @Binding var rating: Int? // For editable user rating
        let readOnlyRating: Double? // For read-only critics/community ratings
        let maxRating: Int
        let fillColor: Color
        let emptyColor: Color
        let accessibilityLabelPrefix: String
        let onStarTap: ((Int) -> Void)? // Closure for editable stars

        private var isEditable: Bool {
            onStarTap != nil
        }

        // Initializer for editable ratings
        init(rating: Binding<Int?>, maxRating: Int, fillColor: Color, emptyColor: Color, accessibilityLabelPrefix: String, onStarTap: @escaping (Int) -> Void) {
            self._rating = rating
            self.readOnlyRating = nil
            self.maxRating = maxRating
            self.fillColor = fillColor
            self.emptyColor = emptyColor
            self.accessibilityLabelPrefix = accessibilityLabelPrefix
            self.onStarTap = onStarTap
        }

        // Initializer for read-only ratings
        init(readOnlyRating: Double?, maxRating: Int, fillColor: Color, emptyColor: Color, accessibilityLabelPrefix: String) {
            self._rating = .constant(nil) // Provide a constant nil binding for read-only
            self.readOnlyRating = readOnlyRating
            self.maxRating = maxRating
            self.fillColor = fillColor
            self.emptyColor = emptyColor
            self.accessibilityLabelPrefix = accessibilityLabelPrefix
            self.onStarTap = nil
        }

        var body: some View {
            HStack(spacing: 2) {
                ForEach(1...maxRating, id: \.self) { index in
                    starImage(for: index)
                        .foregroundStyle(starColor(for: index))
                        .font(.caption) // Smaller stars for a compact look
                        .contentShape(Rectangle()) // Make the whole star tappable area
                        .onTapGesture {
                            if isEditable {
                                onStarTap?(index)
                            }
                        }
                        .accessibilityHidden(true) // Hide individual star images from VoiceOver
                }
            }
            .accessibilityElement(children: .ignore) // Treat the whole HStack as one accessibility element
            .accessibilityLabel(accessibilityLabelPrefix)
            .accessibilityValue(currentAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                if isEditable {
                    switch direction {
                    case .increment:
                        let newRating = (rating ?? 0) + 1
                        onStarTap?(min(newRating, maxRating))
                    case .decrement:
                        let newRating = (rating ?? 1) - 1
                        onStarTap?(max(newRating, 1))
                    @unknown default:
                        break
                    }
                }
            }
        }

        /// Determines the appropriate star image (filled, half, empty) for a given index.
        private func starImage(for index: Int) -> Image {
            if isEditable {
                // For editable, only full or empty stars based on integer rating
                return Image(systemName: index <= (rating ?? 0) ? "star.fill" : "star")
            } else {
                // For read-only, handle fractional ratings
                guard let actualRating = readOnlyRating else { return Image(systemName: "star") }
                if Double(index) <= actualRating {
                    return Image(systemName: "star.fill")
                } else if Double(index) - 0.5 <= actualRating {
                    return Image(systemName: "star.leadinghalf.fill")
                } else {
                    return Image(systemName: "star")
                }
            }
        }

        /// Determines the color of the star based on its state.
        private func starColor(for index: Int) -> Color {
            if isEditable {
                return index <= (rating ?? 0) ? fillColor : emptyColor
            } else {
                guard let actualRating = readOnlyRating else { return emptyColor }
                // For read-only, half stars and full stars use the fill color
                return Double(index) <= actualRating + 0.5 ? fillColor : emptyColor
            }
        }

        /// Provides the accessibility value string for VoiceOver.
        private var currentAccessibilityValue: String {
            if isEditable {
                if let currentRating = rating {
                    return "\(currentRating) stars"
                } else {
                    return "No rating set"
                }
            } else {
                if let currentRating = readOnlyRating {
                    return String(format: "%.1f stars", currentRating)
                } else {
                    return "No rating available"
                }
            }
        }
    }
}

// MARK: - Preview
@available(iOS 26.0, *)
#Preview("Ratings Card") {
    // Create a shared ModelContainer for the preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookEnrichment.self, configurations: config)

    // Insert mock BookEnrichment data
    let mockEnrichment1 = BookEnrichment(workId: "work1", userRating: 3)
    let mockEnrichment2 = BookEnrichment(workId: "work2", userRating: nil)

    container.mainContext.insert(mockEnrichment1)
    container.mainContext.insert(mockEnrichment2)

    // Use actual iOS26ThemeStore
    let themeStore = iOS26ThemeStore()

    return VStack(spacing: 20) {
        RatingsCard(enrichment: mockEnrichment1)
            .environment(\.iOS26ThemeStore, themeStore)
            .modelContainer(container)

        RatingsCard(enrichment: mockEnrichment2)
            .environment(\.iOS26ThemeStore, themeStore)
            .modelContainer(container)
    }
    .padding()
    .background(Color.gray.opacity(0.1)) // To show the glass effect better
}
