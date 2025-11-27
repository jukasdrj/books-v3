import SwiftUI
import SwiftData

/// Diversity Insights Tab - Representation Radar Chart
/// Displays diversity metrics for a book including cultural background,
/// gender identity, translation status, own voices, and accessibility features.
@available(iOS 26.0, *)
@MainActor
struct DiversityInsightsTab: View {
    let work: Work
    let diversityScore: DiversityScore

    @Environment(\.iOS26ThemeStore) private var themeStore

    init(work: Work, diversityScore: DiversityScore? = nil) {
        self.work = work
        self.diversityScore = diversityScore ?? DiversityScore(work: work)
    }

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Header
                header

                // MARK: - Content
                if diversityScore.hasAnyData {
                    VStack(spacing: 24) {
                        // Radar Chart
                        RadarChartView(metrics: diversityScore.metrics)
                            .frame(height: 280)
                            .padding(.vertical, 8)

                        // Metric Details
                        metricDetailsGrid

                        // Explanatory Footer
                        explanatoryFooter
                    }
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .glassEffect(.regular, tint: themeStore.primaryColor.opacity(0.1))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(themeStore.primaryColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Representation Radar")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text("Diversity metrics for this book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Metric Details Grid

    private var metricDetailsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(diversityScore.metrics) { metric in
                if !metric.isMissing {
                    metricRow(for: metric)
                }
            }
        }
    }

    private func metricRow(for metric: DiversityMetric) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: metric.axis.systemImage)
                .font(.body)
                .foregroundStyle(themeStore.primaryColor)
                .frame(width: 24)

            // Axis Name
            Text(metric.axis.rawValue)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            // Score
            Text(String(format: "%.0f%%", metric.score * 100))
                .font(.subheadline.bold())
                .foregroundStyle(scoreColor(for: metric.score))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(scoreColor(for: metric.score).opacity(0.15))
                }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(for score: Double) -> Color {
        switch score {
        case 0.8...:
            return .green
        case 0.5..<0.8:
            return .orange
        default:
            return .secondary
        }
    }

    // MARK: - Explanatory Footer

    private var explanatoryFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color.secondary.opacity(0.3))

            Text("About This Chart")
                .font(.footnote.bold())
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                let metricsByAxis = Dictionary(uniqueKeysWithValues: diversityScore.metrics.map { ($0.axis, $0) })
                ForEach(Array(DiversityScore.metricDescriptions.sorted(by: { $0.key.rawValue < $1.key.rawValue })), id: \.key) { axis, description in
                    if let metric = metricsByAxis[axis], !metric.isMissing {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.secondary)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(axis.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)

                                Text(description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No Diversity Data Available")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("We don't have diversity information for this book yet. You can help by contributing data through progressive profiling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // TODO: Link to Progressive Profiling Sheet (Issue #70)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Preview Helpers

@available(iOS 26.0, *)
@MainActor
private func makePreviewContainer(configure: (ModelContext) -> Void) -> ModelContainer {
    let container = try! ModelContainer(for: Work.self, Edition.self, Author.self)
    let context = container.mainContext
    configure(context)
    return container
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("With Complete Data") {
    @Previewable @State var container = makePreviewContainer { context in
        let author = Author(
            name: "Chimamanda Ngozi Adichie",
            nationality: "Nigerian",
            gender: .female,
            culturalRegion: .africa
        )
        let edition = Edition()
        edition.originalLanguage = "Igbo"

        let work = Work(title: "Americanah")
        work.authors = [author]
        work.editions = [edition]
        work.isOwnVoices = true
        work.accessibilityTags = ["dyslexia-friendly", "audiobook"]

        context.insert(author)
        context.insert(edition)
        context.insert(work)
    }

    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    DiversityInsightsTab(work: work)
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.iOS26ThemeStore, themeStore)
}

@available(iOS 26.0, *)
#Preview("With Partial Data") {
    @Previewable @State var container = makePreviewContainer { context in
        let author = Author(name: "Virginia Woolf", gender: .female)
        let work = Work(title: "Mrs Dalloway")
        work.authors = [author]

        context.insert(author)
        context.insert(work)
    }

    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    DiversityInsightsTab(work: work)
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.iOS26ThemeStore, themeStore)
}

@available(iOS 26.0, *)
#Preview("Empty State") {
    @Previewable @State var container = makePreviewContainer { context in
        let work = Work(title: "Anonymous Book")
        context.insert(work)
    }

    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    DiversityInsightsTab(work: work)
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.iOS26ThemeStore, themeStore)
}
