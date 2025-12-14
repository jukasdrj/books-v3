import SwiftUI

/// Bento Box Module: DiversityBlock
/// Displays the representation radar chart and diversity badges.
struct DiversityBlock: View {
    let work: Work
    @State private var showDetailedBreakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.green)
                Text("Representation")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Radar Chart (Miniature/Preview)
            // We use the existing RepresentationRadarChart but constrained
            RepresentationRadarChart(
                data: RadarChartData(dimensions: radarDimensions),
                onAddData: { _ in } // Interaction disabled in small view, or opens detail
            )
            .frame(height: 140)
            .disabled(true) // Disable internal interaction for now, make whole card clickable

            // Identity Badges (Horizontal Scroll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if work.isOwnVoices == true {
                        IdentityBadge(text: "Own Voices", color: .purple)
                    }
                    if let cultural = work.culturalRegion?.rawValue { // Fixed: culturalSetting -> culturalRegion
                        IdentityBadge(text: cultural.capitalized, color: .orange)
                    }
                    if work.subjectTags.contains(where: { $0.localizedCaseInsensitiveContains("LGBT") || $0.localizedCaseInsensitiveContains("Queer") }) {
                        IdentityBadge(text: "LGBTQ+", color: .blue)
                    }
                    if work.accessibilityTags.contains(where: { $0.localizedCaseInsensitiveContains("Dyslexia") || $0.localizedCaseInsensitiveContains("Neurodivergent") }) {
                        IdentityBadge(text: "Neurodivergent", color: .teal)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // Computed property for Radar Data (runs on MainActor)
    private var radarDimensions: [RadarDimension] {
        let score = DiversityScore(work: work)
        return score.metrics.map { metric in
            RadarDimension(
                name: metric.axis.rawValue,
                completionPercentage: metric.score * 100,
                isComplete: !metric.isMissing
            )
        }
    }
}

struct IdentityBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
