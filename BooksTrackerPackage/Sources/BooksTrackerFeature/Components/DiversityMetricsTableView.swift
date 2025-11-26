import SwiftUI

struct DiversityMetricsTableView: View {
    let metrics: [DiversityMetric]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Diversity Metrics")
                .font(.headline)
                .padding(.bottom, 5)

            ForEach(metrics) { metric in
                HStack {
                    Text(metric.label)
                    Spacer()
                    Text(metric.value != nil ? "\(Int(metric.value! * 100))%" : "Missing Data")
                        .foregroundColor(metric.value != nil ? .primary : .secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diversity Metrics Table")
    }
}
