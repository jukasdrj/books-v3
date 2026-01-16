import SwiftUI

/// Premium star rating with gradient fill, glow effects, and half-star support
@available(iOS 26.0, *)
struct StarRatingView: View {
    @Binding var rating: Double
    let allowsHalfStars: Bool
    let size: StarSize
    let accessibilityLabel: String

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var dragLocation: CGFloat = 0
    @State private var isDragging = false

    enum StarSize {
        case compact   // For cards and lists
        case standard  // Default size
        case large     // For detail views

        var font: Font {
            switch self {
            case .compact: return .body
            case .standard: return .title3
            case .large: return .title2
            }
        }

        var spacing: CGFloat {
            switch self {
            case .compact: return 4
            case .standard: return 6
            case .large: return 8
            }
        }
    }

    init(rating: Binding<Double>, allowsHalfStars: Bool = true, size: StarSize = .standard, accessibilityLabel: String = "Rating") {
        self._rating = rating
        self.allowsHalfStars = allowsHalfStars
        self.size = size
        self.accessibilityLabel = accessibilityLabel
    }

    // Premium gradient for filled stars
    private var starGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.85, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            GeometryReader { geometry in
                HStack(spacing: size.spacing) {
                    ForEach(1...5, id: \.self) { index in
                        starView(for: index)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    rating = Double(index)
                                }
                                triggerHaptic(.light)
                            }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let starWidth = geometry.size.width / 5
                            let newRating = min(5.0, max(0.0, value.location.x / starWidth))
                            let snappedRating = allowsHalfStars
                                ? (newRating * 2).rounded() / 2  // Snap to 0.5
                                : newRating.rounded()             // Snap to 1.0
                            if snappedRating != rating {
                                rating = snappedRating
                                triggerHaptic(.selection)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            triggerHaptic(.light)
                        }
                )
            }
            .frame(width: starFrameWidth, height: starFrameHeight)

            // Rating label
            if rating > 0 {
                ratingLabel
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(formattedRating) out of 5 stars")
        .accessibilityAdjustableAction { direction in
            let step = allowsHalfStars ? 0.5 : 1.0
            switch direction {
            case .increment:
                rating = min(5.0, rating + step)
            case .decrement:
                rating = max(0.0, rating - step)
            @unknown default:
                break
            }
        }
    }

    // MARK: - Star View

    @ViewBuilder
    private func starView(for index: Int) -> some View {
        let fillLevel = fillLevel(for: index)

        Image(systemName: symbolName(for: fillLevel))
            .font(size.font)
            .foregroundStyle(fillLevel > 0 ? AnyShapeStyle(starGradient) : AnyShapeStyle(Color.secondary.opacity(0.3)))
            .scaleEffect(fillLevel > 0 ? 1.0 : 0.92)
            .shadow(color: fillLevel > 0 ? .yellow.opacity(0.5) : .clear, radius: 4, x: 0, y: 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: fillLevel)
    }

    private func fillLevel(for index: Int) -> Double {
        let diff = rating - Double(index - 1)
        if diff >= 1 {
            return 1.0  // Full star
        } else if diff >= 0.5 {
            return 0.5  // Half star
        } else {
            return 0.0  // Empty star
        }
    }

    private func symbolName(for fillLevel: Double) -> String {
        if fillLevel >= 1.0 {
            return "star.fill"
        } else if fillLevel >= 0.5 && allowsHalfStars {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }

    // MARK: - Rating Label

    private var ratingLabel: some View {
        Text(formattedRating)
            .font(size == .large ? .callout.weight(.semibold) : .caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .contentTransition(.numericText())
    }

    private var formattedRating: String {
        if rating.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rating))"
        } else {
            return String(format: "%.1f", rating)
        }
    }

    // MARK: - Layout

    private var starFrameWidth: CGFloat {
        switch size {
        case .compact: return 100
        case .standard: return 130
        case .large: return 160
        }
    }

    private var starFrameHeight: CGFloat {
        switch size {
        case .compact: return 20
        case .standard: return 24
        case .large: return 32
        }
    }

    // MARK: - Haptics

    private enum HapticType {
        case light
        case selection
    }

    private func triggerHaptic(_ type: HapticType) {
        switch type {
        case .light:
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        case .selection:
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Star Rating - Interactive") {
    struct PreviewWrapper: View {
        @State private var rating1: Double = 3.5
        @State private var rating2: Double = 4.0
        @State private var rating3: Double = 2.5

        var body: some View {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Large (Detail View)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StarRatingView(rating: $rating1, size: .large)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Standard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StarRatingView(rating: $rating2, size: .standard)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Compact (Cards)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StarRatingView(rating: $rating3, size: .compact)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Integer Only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StarRatingView(rating: $rating2, allowsHalfStars: false, size: .standard)
                }
            }
            .padding()
        }
    }

    return PreviewWrapper()
        .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}
