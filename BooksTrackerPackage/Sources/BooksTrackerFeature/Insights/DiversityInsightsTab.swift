import SwiftUI

struct DiversityInsightsTab: View {
    let work: Work

    @State private var showingProfilingSheet = false
    @State private var selectedMetric: DiversityMetric?

    private var diversityScore: DiversityScore {
        DiversityScore(work: work)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Representation Radar")
                .font(.title2.bold())

            RadarChartView(metrics: diversityScore.metrics, overallScore: diversityScore.overallScore) { metric in
                selectedMetric = metric
                showingProfilingSheet = true
            }
            .accessibilityRepresentation {
                DiversityMetricsTableView(metrics: diversityScore.metrics)
            }

            Text("This chart visualizes the diversity of representation in this book. Tap on a dashed line to contribute missing information.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingProfilingSheet) {
            if let metric = selectedMetric {
                ProgressiveProfilingSheet(work: work, author: work.primaryAuthor, metric: metric)
            }
        }
    }
}
