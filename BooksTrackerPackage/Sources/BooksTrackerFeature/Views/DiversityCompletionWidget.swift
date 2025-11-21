import SwiftUI
import SwiftData

/// A SwiftUI widget displaying diversity data completion for the user's library.
///
/// This widget features:
/// - An overall progress ring showing the total diversity data completion percentage.
/// - A breakdown of completion percentages for individual diversity dimensions.
/// - A display for earned Curator Points.
/// - An action button to prompt filling in missing data.
///
/// It integrates with `EnhancedDiversityStats` and `DiversityStatsService` to fetch and
/// manage data, and utilizes `GlassCard` and `AuroraGradient` for the v2 aesthetic.
@available(iOS 26.0, *)
public struct DiversityCompletionWidget: View {
    @Environment(\.modelContext) private var modelContext
    @State private var diversityStats: EnhancedDiversityStats?
    @State private var isLoading: Bool = true
    @State private var error: Error?

    // Service instance, initialized when modelContext is available
    @State private var statsService: DiversityStatsService?

    /// Action closure to be called when a specific dimension row is tapped.
    /// The `String` parameter will be the raw value of the `Dimension` enum (e.g., "culturalOrigins").
    let onDimensionTapped: (String) -> Void

    /// Action closure to be called when the "Fill Missing Data" button is tapped.
    let onFillMissingData: () -> Void

    /// Initializes the DiversityCompletionWidget.
    /// - Parameters:
    ///   - onDimensionTapped: A closure to handle taps on individual dimension rows.
    ///   - onFillMissingData: A closure to handle taps on the "Fill Missing Data" button.
    public init(onDimensionTapped: @escaping (String) -> Void, onFillMissingData: @escaping () -> Void) {
        self.onDimensionTapped = onDimensionTapped
        self.onFillMissingData = onFillMissingData
    }

    public var body: some View {
        GlassCard(title: "Diversity Data", icon: "chart.pie.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    ProgressView("Loading Diversity Stats...")
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40) // Provide some height during loading
                } else if let error {
                    ContentUnavailableView {
                        Label("Error Loading Stats", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Retry") {
                            Task { await loadStats() }
                        }
                    }
                } else if let stats = diversityStats {
                    // Overall Progress Ring
                    overallProgressSection(stats: stats)

                    Divider()

                    // Dimension Breakdown
                    dimensionBreakdownSection(stats: stats)

                    // Curator Points
                    curatorPointsSection(stats: stats)

                    // Fill Missing Data Button
                    fillMissingDataButton()
                } else {
                    ContentUnavailableView {
                        Label("No Diversity Stats", systemImage: "chart.pie.fill")
                    } description: {
                        Text("Start adding books to your library to see diversity data.")
                    } actions: {
                        // Placeholder for navigation to add book
                        Button("Add First Book") {
                            print("Navigate to Add Book flow")
                        }
                    }
                }
            }
        }
        .task {
            // Initialize service here, as modelContext is available
            statsService = DiversityStatsService(modelContext: modelContext)
            await loadStats()
        }
    }

    /// Fetches or recalculates diversity statistics.
    @MainActor
    private func loadStats() async {
        isLoading = true
        error = nil
        do {
            // Always calculate for .allTime for the widget's primary display
            diversityStats = try await statsService?.calculateStats(period: .allTime)
        } catch {
            self.error = error
            print("Error loading diversity stats: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func overallProgressSection(stats: EnhancedDiversityStats) -> some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 10)
                    .frame(width: 80, height: 80)

                // Progress ring, animated
                ProgressRingShape(progress: stats.overallCompletionPercentage / 100)
                    .stroke(LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.39, blue: 1.00),
                            Color(red: 0.00, green: 0.82, blue: 1.00),
                            Color(red: 0.07, green: 0.89, blue: 0.64)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 10)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90)) // Start from top
                    .animation(.easeInOut(duration: 1.0), value: stats.overallCompletionPercentage)

                Text("\(Int(stats.overallCompletionPercentage))%")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity) // Center the ZStack
            Text("Overall Completion")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dimensionBreakdownSection(stats: EnhancedDiversityStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dimension Breakdown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(Dimension.allCases, id: \.self) { dimension in
                DimensionProgressRow(
                    dimension: dimension,
                    percentage: stats.percentage(for: dimension),
                    onTap: { onDimensionTapped(dimension.rawValue) }
                )
            }
        }
    }

    /// Points multiplier for curator points calculation
    /// Formula: overallCompletionPercentage (0.0-1.0) * multiplier = points
    private let curatorPointsMultiplier: Double = 0.5

    @ViewBuilder
    private func curatorPointsSection(stats: EnhancedDiversityStats) -> some View {
        // Calculate curator points based on overall completion percentage
        // This rewards users for enriching their library metadata
        let curatorPoints = Int(stats.overallCompletionPercentage * curatorPointsMultiplier)
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
            Text("+\(curatorPoints) Curator Points")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func fillMissingDataButton() -> some View {
        Button(action: onFillMissingData) {
            Label("Fill Missing Data", systemImage: "square.and.pencil")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.39, blue: 1.00),
                                Color(red: 0.00, green: 0.82, blue: 1.00),
                                Color(red: 0.07, green: 0.89, blue: 0.64)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain) // Prevent default button styling
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fill Missing Data")
        .frame(minHeight: 44) // Ensure minimum tap target
    }
}

// MARK: - Helper Views

/// A view representing a single diversity dimension's progress.
@available(iOS 26.0, *)
struct DimensionProgressRow: View {
    let dimension: DiversityCompletionWidget.Dimension
    let percentage: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dimension.displayName)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(percentage))%")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                // Custom progress bar
                GeometryReader { geometry in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.39, blue: 1.00).opacity(0.6),
                                Color(red: 0.00, green: 0.82, blue: 1.00).opacity(0.6),
                                Color(red: 0.07, green: 0.89, blue: 0.64).opacity(0.6)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(0, CGFloat(percentage / 100) * geometry.size.width), height: 4)
                        .cornerRadius(2)
                        .animation(.easeInOut(duration: 0.5), value: percentage)
                }
                .frame(height: 4) // Fixed height for the progress bar
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain) // Prevent default button styling
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dimension.displayName), \(Int(percentage))% complete")
        .frame(minHeight: 44) // Ensure minimum tap target
    }
}

/// A custom `Shape` for drawing a circular progress ring.
@available(iOS 26.0, *)
struct ProgressRingShape: Shape {
    var progress: Double // Value from 0.0 to 1.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360 * progress),
                    clockwise: false)
        return path
    }

    // Allows for smooth animation of the progress value
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
}

// MARK: - Extensions and Enums

@available(iOS 26.0, *)
extension DiversityCompletionWidget {
    /// Represents the five core diversity dimensions.
    enum Dimension: String, CaseIterable {
        case culturalOrigins
        case genderDistribution
        case translationStatus
        case ownVoicesTheme
        case nicheAccessibility

        /// User-friendly display name for each dimension.
        var displayName: String {
            switch self {
            case .culturalOrigins: return "Cultural Origin"
            case .genderDistribution: return "Gender Identity"
            case .translationStatus: return "Translation"
            case .ownVoicesTheme: return "Own Voices"
            case .nicheAccessibility: return "Accessibility"
            }
        }
    }
}

@available(iOS 26.0, *)
extension EnhancedDiversityStats {
    /// Returns the completion percentage for a given diversity dimension.
    /// - Parameter dimension: The `DiversityCompletionWidget.Dimension` to query.
    /// - Returns: The completion percentage (0-100) for the specified dimension.
    func percentage(for dimension: DiversityCompletionWidget.Dimension) -> Double {
        guard totalBooks > 0 else { return 0 }
        switch dimension {
        case .culturalOrigins: return culturalCompletionPercentage
        case .genderDistribution: return genderCompletionPercentage
        case .translationStatus: return translationCompletionPercentage
        case .ownVoicesTheme: return ownVoicesCompletionPercentage
        case .nicheAccessibility: return accessibilityCompletionPercentage
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    // Mock data for preview
    let previewStats = EnhancedDiversityStats(userId: "preview")
    previewStats.totalBooks = 20
    previewStats.booksWithCulturalData = 20 // 100%
    previewStats.booksWithGenderData = 10   // 50%
    previewStats.booksWithTranslationData = 15 // 75%
    previewStats.booksWithOwnVoicesData = 8    // 40%
    previewStats.booksWithAccessibilityData = 6 // 30%
    previewStats.culturalOrigins = ["African": 10, "European": 10]
    previewStats.genderDistribution = ["Female": 8, "Male": 2]
    previewStats.translationStatus = ["Translated": 5, "Original Language": 10]
    previewStats.ownVoicesTheme = ["Own Voices": 8]
    previewStats.nicheAccessibility = ["Accessible": 6]

    // Create an in-memory ModelContainer for the preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: EnhancedDiversityStats.self, configurations: config)
    container.mainContext.insert(previewStats)

    return DiversityCompletionWidget(
        onDimensionTapped: { dimension in
            print("Tapped dimension: \(dimension)")
            // In a real app, this would navigate to a view to fill data for this dimension
        },
        onFillMissingData: {
            print("Tapped Fill Missing Data button")
            // In a real app, this would navigate to the first incomplete dimension's data entry view
        }
    )
    .modelContainer(container) // Provide model container for the preview
    .padding()
    .background(.regularMaterial)
}
