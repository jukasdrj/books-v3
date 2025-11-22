import SwiftUI
import SwiftData

/// A SwiftUI component that displays the enrichment completion progress for a book.
/// It includes a circular progress indicator, curator points, a detailed breakdown
/// of completed fields, and a call to action to complete the profile.
@available(iOS 26.0, *)
@MainActor
public struct EnrichmentCompletionWidget: View {
    @Bindable public var enrichment: BookEnrichment
    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(enrichment: BookEnrichment) {
        self.enrichment = enrichment
    }

    // MARK: - Computed Properties

    /// Calculates the curator points based on the completion percentage.
    /// Each percentage point corresponds to one curator point.
    private var curatorPoints: Int {
        Int(enrichment.completionPercentage * 100)
    }

    /// Determines the color of the progress indicator based on the completion percentage.
    /// - Green: 100% complete
    /// - Orange: 50-99% complete
    /// - Gray: Less than 50% complete
    private var progressColor: Color {
        if enrichment.completionPercentage >= 1.0 {
            return .green
        } else if enrichment.completionPercentage >= 0.5 {
            return .orange
        } else {
            return .gray
        }
    }

    /// Provides a list of enrichment fields with their completion status and optional details.
    private var fieldStatuses: [(name: String, isComplete: Bool, detail: String?)] {
        [
            ("User Rating", enrichment.userRating != nil, nil),
            ("Genres", !enrichment.genres.isEmpty, "(\(enrichment.genres.count))"),
            ("Themes", !enrichment.themes.isEmpty, nil),
            ("Content Warnings", !enrichment.contentWarnings.isEmpty, nil),
            ("Personal Notes", enrichment.personalNotes != nil && !(enrichment.personalNotes?.isEmpty ?? true), nil),
            ("Author Cultural Background", enrichment.authorCulturalBackground != nil && !(enrichment.authorCulturalBackground?.isEmpty ?? true), nil),
            ("Author Gender Identity", enrichment.authorGenderIdentity != nil && !(enrichment.authorGenderIdentity?.isEmpty ?? true), nil)
        ]
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header: Progress and Curator Points
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    ProgressView(value: enrichment.completionPercentage)
                        .progressViewStyle(.circular)
                        .tint(progressColor)
                        .scaleEffect(1.8) // Make it visually larger
                        .frame(width: 44, height: 44) // Ensure consistent size
                        .accessibilityLabel("Enrichment completion progress")

                    Text("\(Int(enrichment.completionPercentage * 100))%")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true) // Percentage is conveyed by the ProgressView's label
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Complete")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("+\(curatorPoints) Curator Points")
                        .font(.subheadline)
                        .foregroundStyle(themeStore.primaryColor)
                        .animation(.easeInOut, value: curatorPoints) // Animate points change
                }
            }
            .padding(.bottom, 8)

            // Field Breakdown List
            VStack(alignment: .leading, spacing: 12) {
                ForEach(fieldStatuses, id: \.name) { status in
                    HStack {
                        Image(systemName: status.isComplete ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(status.isComplete ? .green : .gray)
                            .font(.body)

                        Text(status.name)
                            .foregroundStyle(.primary)
                            .font(.body)

                        if let detail = status.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(status.name), \(status.isComplete ? "completed" : "not completed")")
                }
            }

            // "Complete Profile" Button
            if enrichment.completionPercentage < 1.0 {
                Button(action: {
                    // Placeholder action: Navigate to enrichment editing view
                    print("Open enrichment editing view for workId: \(enrichment.workId)")
                }) {
                    HStack {
                        Text("Complete Profile")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(themeStore.primaryColor.opacity(0.8))
                    .cornerRadius(12)
                    .foregroundStyle(.white)
                }
                .padding(.top, 10)
                .accessibilityLabel("Complete profile to earn more curator points")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Enrichment Completion Widget") {
    // Create in-memory container
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookEnrichment.self, configurations: config)

    // Mock data for different completion states
    let incompleteEnrichment = BookEnrichment(
        workId: "work1",
        userRating: nil,
        genres: [],
        themes: [],
        contentWarnings: ["Violence"],
        personalNotes: nil,
        authorCulturalBackground: nil,
        authorGenderIdentity: nil
    ) // 1/7 fields = ~14%

    let partialEnrichment = BookEnrichment(
        workId: "work2",
        userRating: 4,
        genres: ["Fantasy", "Adventure"],
        themes: [],
        contentWarnings: [],
        personalNotes: "Enjoyed the world-building.",
        authorCulturalBackground: nil,
        authorGenderIdentity: nil
    ) // 3/7 fields = ~43%

    let goodProgressEnrichment = BookEnrichment(
        workId: "work3",
        userRating: 5,
        genres: ["Sci-Fi"],
        themes: ["Dystopian"],
        contentWarnings: [],
        personalNotes: "A thought-provoking read.",
        authorCulturalBackground: "African-American",
        authorGenderIdentity: nil
    ) // 5/7 fields = ~71%

    let completeEnrichment = BookEnrichment(
        workId: "work4",
        userRating: 5,
        genres: ["Classic"],
        themes: ["Love", "Tragedy"],
        contentWarnings: ["Death"],
        personalNotes: "A timeless masterpiece.",
        authorCulturalBackground: "British",
        authorGenderIdentity: "Male"
    ) // 7/7 fields = 100%

    // Insert into container
    container.mainContext.insert(incompleteEnrichment)
    container.mainContext.insert(partialEnrichment)
    container.mainContext.insert(goodProgressEnrichment)
    container.mainContext.insert(completeEnrichment)

    let themeStore = iOS26ThemeStore()

    return NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                Text("Enrichment Progress")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .padding(.bottom, 20)

                EnrichmentCompletionWidget(enrichment: incompleteEnrichment)
                    .frame(maxWidth: 400)

                EnrichmentCompletionWidget(enrichment: partialEnrichment)
                    .frame(maxWidth: 400)

                EnrichmentCompletionWidget(enrichment: goodProgressEnrichment)
                    .frame(maxWidth: 400)

                EnrichmentCompletionWidget(enrichment: completeEnrichment)
                    .frame(maxWidth: 400)
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}
