import SwiftUI

/// Bento Box Module: DiversityBlock
/// Displays the representation radar chart and diversity badges.
@available(iOS 26.0, *)
struct DiversityBlock: View {
    let work: Work
    var onAddData: ((String) -> Void)?
    @State private var showDetailedBreakdown = false

    var body: some View {
        GlassCard(title: "Representation", icon: "globe") {
            VStack(spacing: 16) {
                // Radar Chart - centered and editable
                RepresentationRadarChart(
                    data: RadarChartData(dimensions: radarDimensions),
                    onAddData: { dimension in
                        onAddData?(dimension)
                    }
                )
                .frame(height: 240)
                .frame(maxWidth: .infinity, alignment: .center)

                // Identity Badges (Horizontal Scroll) - centered
                if hasIdentityBadges {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if work.isOwnVoices == true {
                                IdentityBadge(text: "Own Voices", color: .purple)
                            }
                            if let cultural = work.culturalRegion?.rawValue {
                                IdentityBadge(text: cultural.capitalized, color: .orange)
                            }
                            if work.subjectTags.contains(where: { $0.localizedCaseInsensitiveContains("LGBT") || $0.localizedCaseInsensitiveContains("Queer") }) {
                                IdentityBadge(text: "LGBTQ+", color: .blue)
                            }
                            if work.accessibilityTags.contains(where: { $0.localizedCaseInsensitiveContains("Dyslexia") || $0.localizedCaseInsensitiveContains("Neurodivergent") }) {
                                IdentityBadge(text: "Neurodivergent", color: .teal)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var hasIdentityBadges: Bool {
        work.isOwnVoices == true ||
        work.culturalRegion != nil ||
        work.subjectTags.contains(where: { $0.localizedCaseInsensitiveContains("LGBT") || $0.localizedCaseInsensitiveContains("Queer") }) ||
        work.accessibilityTags.contains(where: { $0.localizedCaseInsensitiveContains("Dyslexia") || $0.localizedCaseInsensitiveContains("Neurodivergent") })
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
